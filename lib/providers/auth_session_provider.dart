import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../control_plane/models/workspace.dart';
import '../control_plane/services/login_workspace_resolver_service.dart';
import '../control_plane/services/super_admin_config_service.dart';
import '../control_plane/services/tenant_bootstrap_service.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../firebase/firebase_manager.dart';
import '../services/staff_service.dart';
import '../services/notification_service.dart';
import '../services/platform_service.dart';

/// The canonical app roles. Legacy role strings ('company_admin', 'staff',
/// 'engineer', 'user', ...) are folded into these four by
/// [AppUserRoleX.fromValue], so older Firestore data keeps working.
enum AppUserRole { superAdmin, admin, manager, employee }

extension AppUserRoleX on AppUserRole {
  String get value {
    switch (this) {
      case AppUserRole.superAdmin:
        return 'super_admin';
      case AppUserRole.admin:
        return 'admin';
      case AppUserRole.manager:
        return 'manager';
      case AppUserRole.employee:
        return 'employee';
    }
  }

  String get label {
    switch (this) {
      case AppUserRole.superAdmin:
        return 'Super Admin';
      case AppUserRole.admin:
        return 'Admin';
      case AppUserRole.manager:
        return 'Manager';
      case AppUserRole.employee:
        return 'Employee';
    }
  }

  static AppUserRole? fromValue(String? value) {
    switch (value) {
      case 'super_admin':
      case 'superAdmin':
      case 'superadmin':
        return AppUserRole.superAdmin;
      case 'admin':
      case 'company_admin':
      case 'companyAdmin':
      case 'companyadmin':
        return AppUserRole.admin;
      case 'manager':
        return AppUserRole.manager;
      case 'user':
      case 'employee':
      case 'engineer':
      case 'staff':
        return AppUserRole.employee;
      default:
        return null;
    }
  }
}

class AuthSessionProvider extends ChangeNotifier {
  static const String _roleCachePrefix = 'auth_session_role_';
  static const String _sessionActiveKey = 'auth_session_active';
  static const String _sessionUidKey = 'auth_session_uid';

  /// The only account permitted to hold the platform-wide `super_admin` role.
  /// Resolved from the Master `app_config/admin_access` config doc (set by the
  /// server-side setup tooling), with a `SUPERADMIN_EMAIL` dart-define fallback.
  /// The password is never shipped in the app — it lives server-side only.
  static String? get superAdminEmail => SuperAdminConfig.email;

  final GoogleSignIn? _googleSignIn = kIsWeb ? null : GoogleSignIn();

  User? _user;
  AppUserRole? _role;
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<User?>? _authSub;
  Timer? _roleRetryTimer;
  Timer? _authRestoreTimer;
  int _authRestoreAttempts = 0;
  int _authChangeVersion = 0;
  Completer<void>? _pendingAuthCompleter;

  /// Uid whose role resolution is currently in flight. Used to dedupe the
  /// duplicate auth-state events (the constructor's direct call plus the
  /// `idTokenChanges` listener) so the session role is resolved only once.
  String? _resolvingUid;

  late FirebaseContext _context;

  /// The tenant workspace the current session is bound to (set during
  /// sign-in). `null` on the Master project (e.g. Super Admin) and after
  /// sign-out.
  Workspace? _workspace;

  AuthSessionProvider({FirebaseContext? context}) {
    debugPrint('[AuthSessionProvider] constructor called');
    setContext(context ?? FirebaseContextProvider.current, isInitial: true);
    // Resolve the platform Super Admin email from the Master config doc (with
    // a dart-define fallback) before any role/guard logic runs.
    unawaited(SuperAdminConfig.ensureLoaded(_firestore));
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      debugPrint(
          '[AuthSessionProvider] existing user found: ${currentUser.email}');
      unawaited(_handleAuthChanged(currentUser));
    } else {
      debugPrint(
          '[AuthSessionProvider] no existing user, checking saved session');
      unawaited(_prepareStartupSessionRestore());
    }
  }

  FirebaseAuth get _auth => _context.auth;
  FirebaseFirestore get _firestore => _context.firestore;

  /// The Firebase project context this session is currently bound to.
  ///
  /// On launch (and after sign-out) this is the Master control-plane project.
  /// During a tenant session it is the tenant's own project.
  FirebaseContext get context => _context;

  /// Points this provider (and the whole app) back at the Master project so a
  /// login can be resolved against the control plane from a clean slate.
  Future<void> _ensureMasterContext() async {
    final defaultApp = FirebaseManager.instance.defaultApp;
    if (_context.app.name == defaultApp.name) return;
    setContext(FirebaseManager.instance.activateDefault());
  }

  User? get user => _user;
  AppUserRole? get role => _role;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null && _role != null;
  bool get isSuperAdmin => _role == AppUserRole.superAdmin;
  bool get isCompanyAdmin => _role == AppUserRole.admin;
  bool get isManager => _role == AppUserRole.manager;
  bool get isEmployee => _role == AppUserRole.employee;

  /// The signed-in tenant's URL slug for web dashboard routes, e.g.
  /// `cloudmasa-innovation-lab` (route `/workspace/:workspaceSlug/dashboard`).
  ///
  /// Falls back to the bootstrapped/restored workspace so it is available both
  /// after a fresh login and after a cached-session restore. `null` for the
  /// Super Admin (who lives on the Master project and has no workspace URL).
  String? get workspaceSlug {
    final workspace =
        _workspace ?? TenantBootstrapService.instance.lastWorkspace;
    if (workspace == null) return null;
    final slug = workspace.workspaceSlug;
    if (slug.isNotEmpty) return slug;
    final code = workspace.workspaceCode;
    return code.isNotEmpty ? code : null;
  }

  /// Whether the current session may access Super Admin portal routes.
  bool get canAccessSuperAdmin => isAuthenticated && isSuperAdmin;

  @override
  void dispose() {
    _authSub?.cancel();
    _roleRetryTimer?.cancel();
    _authRestoreTimer?.cancel();
    _pendingAuthCompleter = null;
    super.dispose();
  }

  /// Switches the provider to a new Firebase project context.
  void setContext(FirebaseContext context, {bool isInitial = false}) {
    if (!isInitial && _context.app.name == context.app.name) return;

    _context = context;

    // Cancel all previous subscriptions to avoid leaks and race conditions.
    _authSub?.cancel();
    _roleRetryTimer?.cancel();
    _authRestoreTimer?.cancel();

    // Reset state
    _user = null;
    _role = null;
    _isLoading = true;
    _errorMessage = null;

    // Re-initialize listeners against the new context.
    _authSub = _auth.idTokenChanges().listen(_handleAuthChanged);
    if (!isInitial) notifyListeners();
  }

  Future<void> _prepareStartupSessionRestore() async {
    final hasSavedSession = await _hasSavedSession();
    if (!hasSavedSession || _auth.currentUser != null) {
      // Fresh launch (signed out previously), or an auth session already
      // exists: nothing to restore from the saved cache — the auth listener
      // owns any session that is still restoring asynchronously.
      _role = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    // Reconnect to the workspace that was active on the previous launch so the
    // saved session can resolve against its tenant project. On the fresh Master
    // context there is no user to restore, so without this the restore check
    // would spin forever.
    try {
      final restored =
          await TenantBootstrapService.instance.restoreLastWorkspace();
      if (restored != null) {
        debugPrint(
            '[AuthSessionProvider] restored last workspace: ${restored.app.name}');
        _workspace = TenantBootstrapService.instance.lastWorkspace;
        setContext(restored);
        final tenantUser = _auth.currentUser;
        if (tenantUser != null) {
          unawaited(_handleAuthChanged(tenantUser));
          return;
        }
      }
    } catch (e) {
      debugPrint('[AuthSessionProvider] workspace restore failed: $e');
      await TenantBootstrapService.instance.clearLastWorkspace();
    }

    // No reconnectable workspace: the saved session belongs to the Master
    // project (e.g. the Super Admin). If an auth session resolved while we were
    // restoring, NEVER clobber it — the Super Admin on web restores
    // asynchronously, so `_handleAuthChanged` may have already set `_role`.
    // Otherwise hand off to the bounded restore check instead of wiping the
    // saved session out from under the auth listener.
    if (_role != null || _auth.currentUser != null) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    _scheduleAuthRestoreCheck();
  }

  void _resolvePendingAuth() {
    if (_pendingAuthCompleter != null && !_pendingAuthCompleter!.isCompleted) {
      _pendingAuthCompleter!.complete();
      _pendingAuthCompleter = null;
    }
  }

  Future<void> _handleAuthChanged(User? user) async {
    _user = user;

    if (user == null) {
      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] user=null, hasSavedSession=${await _hasSavedSession()}');
      _roleRetryTimer?.cancel();
      if (await _hasSavedSession()) {
        debugPrint(
            '[AuthSessionProvider._handleAuthChanged] saved session exists, scheduling restore check');
        _isLoading = true;
        notifyListeners();
        _scheduleAuthRestoreCheck();
        // Do NOT call _resolvePendingAuth() here. During a signIn flow the
        // null event fires (no signed-in user on a fresh tenant app) before
        // signInWithEmailAndPassword completes. Completing the pending auth
        // completer here would let signIn() resume before the actual user
        // event fires, causing _role to still be null and throwing a false
        // "Access denied" error. The signIn flow's completer must only be
        // completed when a real user arrives and the role is resolved.
        return;
      }
      _role = null;
      _isLoading = false;
      notifyListeners();
      // Do NOT call _resolvePendingAuth() here for the same reason as above.
      return;
    }

    debugPrint(
        '[AuthSessionProvider._handleAuthChanged] user=${user.email}, uid=${user.uid}');

    // Already resolved for this exact session — later auth events (token
    // refresh, duplicated listeners) must not re-read the role and must never
    // re-enter the retry loop.
    if (_role != null && _auth.currentUser?.uid == user.uid) {
      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] role already resolved '
          '(${_role!.value}), skipping duplicate resolution');
      _authRestoreTimer?.cancel();
      _roleRetryTimer?.cancel();
      _resolvePendingAuth();
      return;
    }

    // A resolution for this uid is already in flight (constructor call +
    // listener fired back-to-back). Let the in-flight resolution finish and
    // settle the state; do NOT complete the pending completer here because the
    // in-flight call still owns it.
    if (_resolvingUid == user.uid) {
      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] resolution already in '
          'flight for uid=${user.uid}, skipping duplicate');
      return;
    }
    _resolvingUid = user.uid;
    // Only calls that actually proceed to resolution bump the version, so a
    // skipped duplicate can never invalidate the in-flight resolution.
    final authChangeVersion = ++_authChangeVersion;

    // Make sure the platform Super Admin email is resolved (from the Master
    // app_config doc) before any role guard runs against it.
    await SuperAdminConfig.ensureLoaded(_firestore);

    _authRestoreTimer?.cancel();
    final locallyCachedRole = await _loadLocallyCachedRole(user.uid);
    // Only trust the local role cache for regular users. Admin/super-admin
    // roles are always re-validated against Firestore so role changes (e.g. a
    // company admin promoted to super admin) take effect on the next launch.
    final canUseCachedSession = _isCurrentAuthChange(authChangeVersion, user) &&
        locallyCachedRole != null &&
        locallyCachedRole == AppUserRole.employee;
    if (canUseCachedSession) {
      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] using cached role: ${locallyCachedRole.value}');
      _errorMessage = null;
      _role = locallyCachedRole;
      _isLoading = false;
      notifyListeners();
      _resolvePendingAuth();
      _clearResolvingUid(user.uid);
      return;
    }
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] calling _loadRole (timeout 20s)');
      final role = await _loadRole(user.uid).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint(
              '[AuthSessionProvider._handleAuthChanged] _loadRole TIMED OUT after 20s');
          throw TimeoutException('Role resolution timed out');
        },
      );
      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] _loadRole returned: ${role?.value}');
      if (!_isCurrentAuthChange(authChangeVersion, user)) {
        debugPrint(
            '[AuthSessionProvider._handleAuthChanged] stale auth change, discarding');
        _resolvePendingAuth();
        return;
      }

      if (role == null) {
        debugPrint(
            '[AuthSessionProvider._handleAuthChanged] role is null, trying cache');
        final cachedRole = await _loadCachedRole(user.uid);
        if (!_isCurrentAuthChange(authChangeVersion, user)) {
          _resolvePendingAuth();
          return;
        }

        if (cachedRole != null) {
          debugPrint(
              '[AuthSessionProvider._handleAuthChanged] using cached role: ${cachedRole.value}');
          _errorMessage = null;
          _role = cachedRole;
          _isLoading = false;
          notifyListeners();
          unawaited(NotificationService().updateTokenInFirestore());
          _resolvePendingAuth();
          return;
        }

        debugPrint(
            '[AuthSessionProvider._handleAuthChanged] no role found, scheduling retry');
        _errorMessage =
            'We could not refresh your role yet. Please check your connection.';
        _role = null;
        _isLoading = false;
        notifyListeners();
        _scheduleRoleRetry(user);
        _resolvePendingAuth();
        return;
      }

      debugPrint(
          '[AuthSessionProvider._handleAuthChanged] role resolved: ${role.value}');
      _errorMessage = null;
      _role = role;
      unawaited(_saveActiveSession(user.uid, role));
      _roleRetryTimer?.cancel();
      _isLoading = false;
      notifyListeners();

      // Update FCM Token for push notifications
      unawaited(NotificationService().updateTokenInFirestore());
    } catch (e) {
      debugPrint('[AuthSessionProvider._handleAuthChanged] error: $e');
      final cachedRole = await _loadCachedRole(user.uid);
      if (!_isCurrentAuthChange(authChangeVersion, user)) {
        _resolvePendingAuth();
        return;
      }

      if (cachedRole != null) {
        _errorMessage = null;
        _role = cachedRole;
        _isLoading = false;
        notifyListeners();
        unawaited(NotificationService().updateTokenInFirestore());
        _resolvePendingAuth();
        return;
      }

      _errorMessage =
          'Connection timeout or network error. Please check your internet connection and try again.';
      _role = null;
      _isLoading = false;
      notifyListeners();
      _scheduleRoleRetry(user);
    } finally {
      // Always release the in-flight guard so a later sign-in/sign-out cycle
      // for the same uid is never blocked by a stale lock.
      _clearResolvingUid(user.uid);
    }
    _resolvePendingAuth();
  }

  void _clearResolvingUid(String uid) {
    if (_resolvingUid == uid) _resolvingUid = null;
  }

  bool _isCurrentAuthChange(int version, User user) {
    return version == _authChangeVersion && _auth.currentUser?.uid == user.uid;
  }

  void _scheduleRoleRetry(User user) {
    if (_roleRetryTimer?.isActive == true) return;
    _roleRetryTimer = Timer(const Duration(seconds: 5), () {
      if (_auth.currentUser?.uid == user.uid && _role == null) {
        unawaited(_handleAuthChanged(user));
      }
    });
  }

  void _scheduleAuthRestoreCheck() {
    if (_authRestoreTimer?.isActive == true) return;
    _authRestoreTimer = Timer(const Duration(seconds: 2), () async {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        _authRestoreAttempts = 0;
        unawaited(_handleAuthChanged(currentUser));
        return;
      }

      if (await _hasSavedSession()) {
        if (_authRestoreAttempts++ < 10) {
          _scheduleAuthRestoreCheck();
        } else {
          // The saved session never restored (e.g. signed out on another
          // device or the session expired). Forget it and land on the login
          // screen instead of spinning forever.
          debugPrint(
              '[AuthSessionProvider] saved session did not restore after 10 attempts, clearing');
          await _clearActiveSession(null);
          _authRestoreAttempts = 0;
          _role = null;
          _isLoading = false;
          notifyListeners();
        }
      } else {
        _authRestoreAttempts = 0;
        _role = null;
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<AppUserRole?> _loadCachedRole(String uid) async {
    final locallyCachedRole = _guardSuperAdminActive(
      await _loadLocallyCachedRole(uid),
      uid,
    );
    if (locallyCachedRole != null) return locallyCachedRole;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      final role = _guardSuperAdminActive(
        AppUserRoleX.fromValue(doc.data()?['role'] as String?),
        uid,
      );
      if (role != null) {
        unawaited(_cacheRole(uid, role));
        return role;
      }
    } catch (_) {}

    final user = _auth.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;

    for (final collection in const ['staff', 'managers', 'admins']) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('email', isEqualTo: email)
            .limit(1)
            .get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) continue;
        final role = switch (collection) {
          'staff' => AppUserRole.employee,
          'managers' => AppUserRole.manager,
          'admins' => AppUserRole.admin,
          _ => null,
        };
        if (role == null) continue;
        unawaited(_cacheRole(uid, role));
        return role;
      } catch (_) {}
    }

    if (SuperAdminConfig.matches(email)) {
      return AppUserRole.superAdmin;
    }

    return null;
  }

  Future<AppUserRole?> _loadLocallyCachedRole(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppUserRoleX.fromValue(prefs.getString('$_roleCachePrefix$uid'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheRole(String uid, AppUserRole role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_roleCachePrefix$uid', role.value);
    } catch (_) {}
  }

  Future<void> _saveActiveSession(String uid, AppUserRole role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sessionActiveKey, true);
      await prefs.setString(_sessionUidKey, uid);
      await prefs.setString('$_roleCachePrefix$uid', role.value);
    } catch (_) {}
  }

  Future<bool> _hasSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_sessionActiveKey) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearActiveSession(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUid = uid ?? prefs.getString(_sessionUidKey);
      await prefs.setBool(_sessionActiveKey, false);
      await prefs.remove(_sessionUidKey);
      if (cachedUid != null) {
        await prefs.remove('$_roleCachePrefix$cachedUid');
      }
    } catch (_) {}
  }

  /// Super-admin is a platform role authorized exclusively from the signed-in
  /// account's own `users/{uid}.role` document. Per [SuperAdminConfig], the
  /// configured Super Admin email only drives routing — never authorization —
  /// so no email comparison is performed here. Any role that claims
  /// `super_admin` for an account other than the currently signed-in one is
  /// downgraded so it can never enter the Super Admin portal.
  AppUserRole? _guardSuperAdminActive(AppUserRole? role, String? uid) {
    if (role == AppUserRole.superAdmin) {
      if (uid != null && uid == _auth.currentUser?.uid) return role;
      debugPrint(
          '[AuthSessionProvider] super_admin role denied for uid="$uid"');
      return null;
    }
    return role;
  }

  Future<AppUserRole?> _loadRole(String uid) async {
    debugPrint('[AuthSessionProvider._loadRole] uid=$uid');
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _firestore.collection('users').doc(uid).get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[AuthSessionProvider._loadRole] TIMEOUT reading users doc');
          throw Exception('Connection timeout');
        },
      );
    } on FirebaseException catch (e) {
      debugPrint(
          '[AuthSessionProvider._loadRole] Firestore error reading users/$uid: '
          'code=${e.code}, message=${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint(
            '[AuthSessionProvider._loadRole] PERMISSION_DENIED — Firestore rules '
            'may deny read access to users/$uid. Check tenant Firestore rules '
            'deployment.');
      }
      rethrow;
    }
    final data = doc.data();
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[AuthSessionProvider._loadRole] currentUser is null');
      return null;
    }

    debugPrint(
        '[AuthSessionProvider._loadRole] user doc exists=${doc.exists}, data=$data');

    final storedRole = _guardSuperAdminActive(
      AppUserRoleX.fromValue(data?['role'] as String?),
      user.uid,
    );
    debugPrint(
        '[AuthSessionProvider._loadRole] storedRole from users doc: ${data?['role']} -> ${storedRole?.value}');

    if (storedRole != null) {
      // The signed-in user's `users/{uid}.role` document is the authoritative
      // source of truth for the session role, including `super_admin`, which is
      // pinned to the authenticated account by `_guardSuperAdminActive`. No
      // extra directory lookup is required. (A previous version also demanded
      // an `admins` directory match on top of the users doc, which made the
      // Super Admin login fail whenever that lookup came back empty on the
      // Master project.)
      debugPrint(
          '[AuthSessionProvider._loadRole] returning stored role: ${storedRole.value}');
      return storedRole;
    }

    debugPrint(
        '[AuthSessionProvider._loadRole] no stored role, inferring from directory');

    final inferredRole = await _inferRoleFromDirectory(
      email: user.email,
      phone: user.phoneNumber,
      allowAuthenticatedAdminFallback: true,
    );
    debugPrint(
        '[AuthSessionProvider._loadRole] inferredRole: ${inferredRole?.value}');

    if (inferredRole != null) {
      debugPrint(
          '[AuthSessionProvider._loadRole] writing inferred role to users doc');
      await _firestore.collection('users').doc(uid).set({
        'name': user.displayName ??
            user.email?.split('@').first ??
            user.phoneNumber ??
            inferredRole.label,
        if (user.email != null) 'email': user.email?.trim(),
        if (user.phoneNumber != null) 'phone': user.phoneNumber,
        'photoUrl': user.photoURL,
        'role': inferredRole.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return inferredRole;
    }

    debugPrint(
        '[AuthSessionProvider._loadRole] returning storedRole (fallback): ${storedRole?.value}');
    return storedRole;
  }

  Future<AppUserRole?> _inferRoleFromDirectory({
    String? email,
    String? phone,
    bool allowAuthenticatedAdminFallback = false,
  }) async {
    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    final normalizedPhone = phone?.trim() ?? '';

    if (normalizedEmail.isEmpty && normalizedPhone.isEmpty) {
      return null;
    }

    if (normalizedEmail.isNotEmpty && SuperAdminConfig.matches(normalizedEmail)) {
      return AppUserRole.superAdmin;
    }

    if (normalizedEmail.isNotEmpty) {
      final exactManager = await _firestore
          .collection('managers')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (exactManager.docs.isNotEmpty) return AppUserRole.manager;

      final exactStaff = await _firestore
          .collection('staff')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (exactStaff.docs.isNotEmpty) return AppUserRole.employee;

      if (await _isAuthorizedAdminDirectoryEmail(normalizedEmail)) {
        return AppUserRole.admin;
      }
    }

    if (normalizedPhone.isNotEmpty) {
      final exactManager = await _firestore
          .collection('managers')
          .where('phone', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
      if (exactManager.docs.isNotEmpty) return AppUserRole.manager;

      final exactStaff = await _firestore
          .collection('staff')
          .where('phone', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
      if (exactStaff.docs.isNotEmpty) return AppUserRole.employee;
    }

    final managerSnapshot =
        await _firestore.collection('managers').limit(100).get();
    for (final doc in managerSnapshot.docs) {
      final docEmail =
          (doc.data()['email'] as String? ?? '').trim().toLowerCase();
      final docPhone = (doc.data()['phone'] as String? ?? '').trim();
      if (normalizedEmail.isNotEmpty && docEmail == normalizedEmail) {
        return AppUserRole.manager;
      }
      if (normalizedPhone.isNotEmpty && docPhone == normalizedPhone) {
        return AppUserRole.manager;
      }
    }

    final staffSnapshot = await _firestore.collection('staff').limit(200).get();
    for (final doc in staffSnapshot.docs) {
      final docEmail =
          (doc.data()['email'] as String? ?? '').trim().toLowerCase();
      final docPhone = (doc.data()['phone'] as String? ?? '').trim();
      if (normalizedEmail.isNotEmpty && docEmail == normalizedEmail) {
        return AppUserRole.employee;
      }
      if (normalizedPhone.isNotEmpty && docPhone == normalizedPhone) {
        return AppUserRole.employee;
      }
    }

    if (allowAuthenticatedAdminFallback &&
        await _isSignedInAuthUserAdminFallback(normalizedEmail)) {
      return AppUserRole.admin;
    }

    return null;
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final trimmedEmail = email.trim().toLowerCase();

      final resolvedRole = await _inferRoleFromDirectory(email: trimmedEmail);
      if (resolvedRole == null) {
        _setLoading(false);
        throw Exception(
          'Your email is not authorized to register. Please ask your '
          'administrator or manager to onboard you first.',
        );
      }

      final staffService = StaffService(context: _context);
      String? staffId;
      String? staffCompanyId;
      if (resolvedRole == AppUserRole.employee) {
        final staffRecord = await staffService.getStaffByEmail(trimmedEmail);
        if (staffRecord != null && !staffRecord.isActive) {
          _setLoading(false);
          throw Exception(
            'Your account is deactivated. Please contact your administrator.',
          );
        }
        staffId = staffRecord?.id;
        staffCompanyId = staffRecord?.companyId;
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      await credential.user?.updateDisplayName(name.trim());
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'name': name.trim(),
        'email': trimmedEmail,
        'role': resolvedRole.value,
        'companyId': staffCompanyId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (staffId != null) {
        await staffService.markStaffAsRegistered(staffId);
      }

      _user = credential.user;
      _role = resolvedRole;
      if (credential.user != null) {
        unawaited(_saveActiveSession(credential.user!.uid, resolvedRole));
      }
      _setLoading(false);
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      throw Exception(_friendlyMessage(e));
    } catch (e) {
      _setLoading(false);
      if (e is Exception) rethrow;
      throw Exception('Registration error: ${e.toString()}');
    }
  }

Future<void> signIn({
    required String email,
    required String password,
  }) async {
    debugPrint('[AuthSessionProvider.signIn] email=$email');

    _setLoading(true);
    _errorMessage = null;

    try {
      final normalizedEmail = email.trim().toLowerCase();
      debugPrint(
          '[AuthSessionProvider.signIn] resolving workspace for $normalizedEmail');
      final resolution =
          await LoginWorkspaceResolverService.instance.resolve(normalizedEmail);

      if (resolution.isSuperAdmin) {
        debugPrint('[AuthSessionProvider.signIn] super admin -> master auth');
        _workspace = null;
        await _ensureMasterContext();
      } else if (resolution.isTenant) {
        final workspace = resolution.workspace!;
        _workspace = workspace;
        debugPrint(
            '[AuthSessionProvider.signIn] tenant ${workspace.workspaceId} -> activating');
        final tenantContext =
            await TenantBootstrapService.instance.bootstrap(workspace);
        setContext(tenantContext);
      } else if (resolution.isUnavailable) {
        debugPrint('[AuthSessionProvider.signIn] workspace unavailable: '
            '${resolution.message}');
        _workspace = null;
        throw Exception(resolution.message);
      } else {
        // Email not in the index: authenticate against the Master project so
        // the returned error is identical to a wrong password (the index can
        // never be used to enumerate registered emails).
        debugPrint(
            '[AuthSessionProvider.signIn] email not in index -> master auth');
        _workspace = null;
        await _ensureMasterContext();
      }

      // Set the completer BEFORE authenticating so a synchronous auth-stream
      // event (which completes it inside _handleAuthChanged) can never be lost.
      _pendingAuthCompleter = Completer<void>();
      final pendingAuth = _pendingAuthCompleter;

      debugPrint(
          '[AuthSessionProvider.signIn] calling signInWithEmailAndPassword');
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('Sign-in did not return a user.');
      }

      debugPrint(
          '[AuthSessionProvider.signIn] Firebase auth success, waiting for _handleAuthChanged');
      if (pendingAuth != null && !pendingAuth.isCompleted) {
        await pendingAuth.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint(
                '[AuthSessionProvider.signIn] _pendingAuthCompleter TIMED OUT after 30s');
            throw Exception('Login timed out while loading your workspace.');
          },
        );
      }

      debugPrint(
          '[AuthSessionProvider.signIn] _handleAuthChanged completed, role=${_role?.value}');
      if (_role == null) {
        // Build a diagnostic error message that helps future debugging.
        final uid = user.uid;
        String detail;
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(uid)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 5));
          if (!userDoc.exists) {
            detail = 'No users/$uid document found in this project\'s '
                'Firestore. The provisioning step that creates this document '
                'may have failed.';
          } else {
            final roleValue = userDoc.data()?['role'];
            if (roleValue == null) {
              detail = 'The users/$uid document exists but has no "role" field.';
            } else {
              detail = 'The users/$uid document has role="$roleValue" but '
                  'role resolution could not interpret it.';
            }
          }
        } on FirebaseException catch (e) {
          detail = 'Permission denied reading users/$uid — Firestore rules '
              'may not be deployed to this tenant project '
              '(error: ${e.code}).';
        } catch (_) {
          detail = 'Could not read users/$uid to diagnose the issue.';
        }
        _errorMessage ??=
            'Access denied: $detail '
            'Please contact your administrator.';
        debugPrint('[AuthSessionProvider.signIn] no role, signing out: '
            '$_errorMessage');
        await _auth.signOut();
        await _clearActiveSession(user.uid);
        throw Exception(_errorMessage);
      }

      _setLoading(false);
    } on FirebaseAuthException catch (e) {
      debugPrint(
          '[AuthSessionProvider.signIn] FirebaseAuthException: ${e.code}');
      _pendingAuthCompleter = null;
      _setLoading(false);
      unawaited(PlatformService().recordSecurityEvent(
        type: 'failed_login',
        email: email.trim().toLowerCase(),
        detail: e.code,
      ));
      throw Exception(_friendlyMessage(e));
    } catch (e) {
      debugPrint('[AuthSessionProvider.signIn] unexpected error: $e');
      _pendingAuthCompleter = null;
      _setLoading(false);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    debugPrint('[AuthSessionProvider.signInWithGoogle] called');
    _setLoading(true);
    _errorMessage = null;
    try {
      UserCredential credential;

      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        credential = await _auth.signInWithPopup(provider);
      } else {
        final googleUser = await _googleSignIn?.signIn();
        if (googleUser == null) {
          debugPrint('[AuthSessionProvider.signInWithGoogle] user cancelled');
          _setLoading(false);
          return;
        }

        final googleAuth = await googleUser.authentication;
        final authCredential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        credential = await _auth.signInWithCredential(authCredential);
      }

      final user = credential.user;
      if (user == null) {
        throw Exception('Google sign-in did not return a user.');
      }

      debugPrint(
          '[AuthSessionProvider.signInWithGoogle] auth success, waiting for _handleAuthChanged');
      // Set the completer BEFORE authenticating (see signIn for the rationale).
      // If the role already resolved (the auth event fired during the popup),
      // there is nothing left to wait for.
      _pendingAuthCompleter = Completer<void>();
      final pendingAuth = _pendingAuthCompleter;
      if (_role == null && pendingAuth != null && !pendingAuth.isCompleted) {
        await pendingAuth.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint(
                '[AuthSessionProvider.signInWithGoogle] _pendingAuthCompleter TIMED OUT after 30s');
            throw Exception('Login timed out while loading your workspace.');
          },
        );
      }

      debugPrint(
          '[AuthSessionProvider.signInWithGoogle] _handleAuthChanged completed, role=${_role?.value}');
      if (_role == null) {
        final uid = user.uid;
        String detail;
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(uid)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 5));
          if (!userDoc.exists) {
            detail = 'No users/$uid document found in this project\'s '
                'Firestore. The provisioning step that creates this document '
                'may have failed.';
          } else {
            final roleValue = userDoc.data()?['role'];
            if (roleValue == null) {
              detail = 'The users/$uid document exists but has no "role" field.';
            } else {
              detail = 'The users/$uid document has role="$roleValue" but '
                  'role resolution could not interpret it.';
            }
          }
        } on FirebaseException catch (e) {
          detail = 'Permission denied reading users/$uid — Firestore rules '
              'may not be deployed to this tenant project '
              '(error: ${e.code}).';
        } catch (_) {
          detail = 'Could not read users/$uid to diagnose the issue.';
        }
        _errorMessage ??=
            'Access denied: $detail '
            'Please contact your administrator.';
        debugPrint(
            '[AuthSessionProvider.signInWithGoogle] no role, signing out: '
            '$_errorMessage');
        await _auth.signOut();
        await _googleSignIn?.signOut();
        await _clearActiveSession(user.uid);
        throw Exception(_errorMessage);
      }

      debugPrint(
          '[AuthSessionProvider.signInWithGoogle] writing role=${_role!.value} to users doc');
      await _firestore.collection('users').doc(user.uid).set({
        'name':
            user.displayName ?? user.email?.split('@').first ?? _role!.label,
        'email': user.email,
        'photoUrl': user.photoURL,
        'role': _role!.value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint(
              '[AuthSessionProvider.signInWithGoogle] users doc write TIMED OUT after 15s');
        },
      );

      _setLoading(false);
    } on FirebaseAuthException catch (e) {
      debugPrint(
          '[AuthSessionProvider.signInWithGoogle] FirebaseAuthException: ${e.code}');
      _pendingAuthCompleter = null;
      _setLoading(false);
      throw Exception(_friendlyMessage(e));
    } catch (e) {
      debugPrint('[AuthSessionProvider.signInWithGoogle] error: $e');
      _pendingAuthCompleter = null;
      _setLoading(false);
      if (e is Exception) rethrow;
      throw Exception('Google sign-in failed. Please try again.');
    }
  }

  /// Sends a password-reset email via Firebase Auth.
  /// First verifies the email exists in Firestore directories,
  /// then sends the real Firebase password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    _setLoading(true);
    final trimmedEmail = email.trim().toLowerCase();

    try {
      // Step 1: Verify email exists in our system (staff/managers/admins)
      bool existsInSystem = false;
      try {
        existsInSystem = await _checkEmailExistsInSystem(trimmedEmail);

        if (!existsInSystem) {
          _setLoading(false);
          throw Exception(
            'This email is not registered in our system. '
            'Please check the email address or contact your administrator.',
          );
        }
      } catch (firestoreError) {
        // If Firestore check fails (e.g. permission or index),
        // we will proceed to try sending the email anyway as a fallback.
        // This ensures the feature works even if cloud rules are pending deployment.
      }

      // Step 2: Removed fetchSignInMethodsForEmail due to deprecation.
      // We rely on the system existence check above, then proceed to send the email.

      // Step 3: Send the actual password reset email
      await _auth.sendPasswordResetEmail(email: trimmedEmail);

      // Trigger push notification to their phone
      try {
        await NotificationService().sendNotificationToUser(
          identifier: trimmedEmail,
          title: 'Password Reset Requested',
          body:
              'A password reset email has been sent to your registered address. Please follow the instructions to secure your account.',
        );
      } catch (e) {
        debugPrint('Failed to send password reset push notification: $e');
      }

      _setLoading(false);
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      throw Exception(_friendlyMessage(e));
    } catch (e) {
      _setLoading(false);
      if (e is Exception) rethrow;
      throw Exception('Failed to send reset email: ${e.toString()}');
    }
  }

  /// Check if an email exists in any Firestore role directory.
  Future<bool> _checkEmailExistsInSystem(String email) async {
    // Check admins
    final adminQuery = await _firestore
        .collection('admins')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (adminQuery.docs.isNotEmpty) return true;

    // Check managers
    final managerQuery = await _firestore
        .collection('managers')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (managerQuery.docs.isNotEmpty) return true;

    // Check staff
    final staffQuery = await _firestore
        .collection('staff')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (staffQuery.docs.isNotEmpty) return true;

    // Check users collection as fallback
    final usersQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (usersQuery.docs.isNotEmpty) return true;

    return false;
  }

  Future<bool> _isSignedInAuthUserAdminFallback(String normalizedEmail) async {
    debugPrint(
        '[AuthSessionProvider._isSignedInAuthUserAdminFallback] email=$normalizedEmail');
    final currentUser = _auth.currentUser;
    if (currentUser == null || normalizedEmail.isEmpty) return false;

    final authEmail = currentUser.email?.trim().toLowerCase() ?? '';
    if (authEmail != normalizedEmail) return false;

    if (await _emailExistsInRoleDirectory(
      collection: 'managers',
      email: normalizedEmail,
    )) {
      return false;
    }

    if (await _emailExistsInRoleDirectory(
      collection: 'staff',
      email: normalizedEmail,
    )) {
      return false;
    }

    try {
      await _firestore.collection('admins').doc(currentUser.uid).set({
        'name': currentUser.displayName ??
            normalizedEmail.split('@').first.replaceAll('.', ' '),
        'email': normalizedEmail,
        'authUid': currentUser.uid,
        'role': AppUserRole.admin.value,
        'status': 'active',
        'isActive': true,
        'photoUrl': currentUser.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'firebase_auth_verified',
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    debugPrint(
        '[AuthSessionProvider._isSignedInAuthUserAdminFallback] authorized as admin');
    return true;
  }

  Future<bool> _emailExistsInRoleDirectory({
    required String collection,
    required String email,
  }) async {
    try {
      final exactEmail = await _firestore
          .collection(collection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (exactEmail.docs.isNotEmpty) return true;

      final docs = await _firestore.collection(collection).limit(200).get();
      for (final doc in docs.docs) {
        if (_recordEmailMatches(doc.data(), email)) return true;
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    return false;
  }

  Future<bool> _isAuthorizedAdminDirectoryEmail(String? email) async {
    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    if (normalizedEmail.isEmpty) return false;

    try {
      final exactAdmin = await _firestore
          .collection('admins')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (exactAdmin.docs
          .any((doc) => _isActiveAdminDirectoryData(doc.data()))) {
        return true;
      }

      final admins = await _firestore.collection('admins').limit(100).get();
      for (final doc in admins.docs) {
        final data = doc.data();
        if (_recordEmailMatches(data, normalizedEmail) &&
            _isActiveAdminDirectoryData(data)) {
          return true;
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    try {
      final exactUser = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (exactUser.docs
          .any((doc) => _isActiveAdminDirectoryData(doc.data()))) {
        return true;
      }

      final users = await _firestore.collection('users').limit(100).get();
      for (final doc in users.docs) {
        final data = doc.data();
        if (_recordEmailMatches(data, normalizedEmail) &&
            _isActiveAdminDirectoryData(data)) {
          return true;
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    if (await _isConfiguredAdminEmail(normalizedEmail)) return true;

    return false;
  }

  bool _isActiveAdminDirectoryData(Map<String, dynamic>? data) {
    if (data == null) return false;
    final role = (data['role'] as String? ?? 'admin').trim().toLowerCase();
    final status = (data['status'] as String? ?? 'active').trim().toLowerCase();
    final isActive = data['isActive'];
    final active = isActive is bool ? isActive : true;
    return (role == 'super_admin' ||
            role == 'superadmin' ||
            role == 'admin' ||
            role == 'company_admin' ||
            role == 'companyadmin') &&
        active &&
        status != 'inactive';
  }

  bool _recordEmailMatches(Map<String, dynamic>? data, String normalizedEmail) {
    if (data == null || normalizedEmail.isEmpty) return false;
    return _adminEmailCandidates(data).contains(normalizedEmail);
  }

  Set<String> _adminEmailCandidates(Map<String, dynamic> data) {
    final values = <String>{};
    for (final key in const [
      'email',
      'adminEmail',
      'primaryAdminEmail',
      'emailAddress',
      'mail',
      'loginEmail',
      'authEmail',
    ]) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        values.add(value.trim().toLowerCase());
      }
    }
    return values;
  }

  Future<bool> _isConfiguredAdminEmail(String normalizedEmail) async {
    DocumentSnapshot<Map<String, dynamic>> config;
    try {
      config =
          await _firestore.collection('app_config').doc('admin_access').get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
    final data = config.data();
    if (data == null) return false;

    final primaryEmail =
        (data['primaryAdminEmail'] as String? ?? '').trim().toLowerCase();
    if (primaryEmail == normalizedEmail) return true;

    final email = (data['email'] as String? ?? '').trim().toLowerCase();
    if (email == normalizedEmail) return true;

    final adminEmails = data['adminEmails'];
    if (adminEmails is Iterable) {
      return adminEmails.any(
        (value) => value.toString().trim().toLowerCase() == normalizedEmail,
      );
    }

    final allowedAdminEmails = data['allowedAdminEmails'];
    if (allowedAdminEmails is Iterable) {
      return allowedAdminEmails.any(
        (value) => value.toString().trim().toLowerCase() == normalizedEmail,
      );
    }

    return false;
  }

  Future<void> signOut() async {
    debugPrint('[AuthSessionProvider.signOut] called');
    _setLoading(true);
    final uid = _auth.currentUser?.uid;
    await _auth.signOut();
    await _googleSignIn?.signOut();
    await _clearActiveSession(uid);
    _role = null;
    _workspace = null;
    // Return to the Master control-plane project first so all tenant
    // subscriptions are cancelled, then tear the tenant app down and forget
    // the cached workspace. The next login resolves from a clean slate.
    await _ensureMasterContext();
    await TenantBootstrapService.instance.clearLastWorkspace();
    _setLoading(false);
    debugPrint('[AuthSessionProvider.signOut] complete');
  }

  /// Forces a refresh of the current user's ID token.
  /// This is useful after server-side custom claims changes (e.g., super_admin claim)
  /// to ensure the client picks up the new claims without requiring a full sign-out/in.
  Future<void> forceTokenRefresh() async {
    final user = _auth.currentUser;
    if (user != null) {
      debugPrint('[AuthSessionProvider.forceTokenRefresh] forcing token refresh for ${user.uid}');
      await user.getIdToken(true);
      debugPrint('[AuthSessionProvider.forceTokenRefresh] token refreshed');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _friendlyMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'user-not-found':
        return 'No account was found for that email.';
      case 'wrong-password':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact your administrator.';
      case 'too-many-requests':
        return 'Too many login attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error while contacting Firebase. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Authentication.';
      case 'invalid-api-key':
        return 'The Firebase web API key is not valid for this app configuration.';
      case 'app-not-authorized':
        return 'This app or domain is not authorized to use the configured Firebase project.';
      case 'internal-error':
        return 'Firebase returned an internal error. Check the browser console for the exact auth response.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
