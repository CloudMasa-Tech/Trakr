import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attendqr/control_plane/services/super_admin_config_service.dart';
import 'package:attendqr/firebase/firebase_context.dart';
import 'package:attendqr/providers/auth_session_provider.dart';

const _superAdminEmail = 'keerthana.s@cloudmasa.com';
const _superAdminPassword = 'Superadmin@123';
const _superAdminUid = 'super-admin-uid';

const _testOptions = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: 'test-app-id',
  messagingSenderId: 'test-sender',
  projectId: 'test-project',
);

/// In-memory [FirebasePlatform] backed by a single default app.
class _FakeCorePlatform extends FirebasePlatform {
  _FakeCorePlatform(this._apps);

  final Map<String, FirebaseAppPlatform> _apps;

  @override
  List<FirebaseAppPlatform> get apps => _apps.values.toList();

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final resolvedName = name ?? defaultFirebaseAppName;
    final existing = _apps[resolvedName];
    if (existing != null) return existing;
    final app = FirebaseAppPlatform(resolvedName, options ?? _testOptions);
    _apps[resolvedName] = app;
    return app;
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final existing = _apps[name];
    if (existing == null) {
      throw StateError('No Firebase App named "$name" has been created.');
    }
    return existing;
  }
}

/// [FirebaseAuthPlatform] whose auth state is driven by a local broadcast
/// stream so [AuthSessionProvider]'s idTokenChanges listener fires exactly as
/// it would against a real backend.
class _FakeAuthPlatform extends FirebaseAuthPlatform {
  _FakeAuthPlatform();

  final _controller = StreamController<UserPlatform?>.broadcast();
  UserPlatform? _currentUser;
  final Map<String, String> _uidsByEmail = {};
  String _defaultUid = _superAdminUid;

  @override
  UserPlatform? get currentUser => _currentUser;
  @override
  set currentUser(UserPlatform? value) => _currentUser = value;

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) {
    if (currentUser != null) _currentUser = FakeUserPlatform(this, currentUser);
    return this;
  }

  @override
  Stream<UserPlatform?> idTokenChanges() => _controller.stream;

  @override
  Stream<UserPlatform?> authStateChanges() => _controller.stream;

  @override
  Stream<UserPlatform?> userChanges() => _controller.stream;

  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final uid = _uidsByEmail[email.toLowerCase()] ?? _defaultUid;
    final user = FakeUserPlatform(
      this,
      PigeonUserDetails(
        userInfo: PigeonUserInfo(
          uid: uid,
          email: email,
          displayName: 'Test User',
          isAnonymous: false,
          isEmailVerified: true,
          providerId: 'password',
        ),
        providerData: const [],
      ),
    );
    _currentUser = user;
    _controller.add(user);
    return _FakeUserCredential(auth: this, user: user);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  /// Maps a sign-in email to a fixed uid (used to simulate a non-super-admin
  /// tenant user logging in on the Master project).
  void setUidForEmail(String email, String uid) {
    _uidsByEmail[email.toLowerCase()] = uid;
  }

  void reset() {
    _currentUser = null;
    _uidsByEmail.clear();
    _defaultUid = _superAdminUid;
  }
}

class FakeUserPlatform extends UserPlatform {
  FakeUserPlatform(FirebaseAuthPlatform auth, PigeonUserDetails userDetails)
      : super(auth, _FakeMultiFactor(auth), userDetails);
}

class _FakeMultiFactor extends MultiFactorPlatform {
  _FakeMultiFactor(super.auth);
}

class _FakeUserCredential extends UserCredentialPlatform {
  _FakeUserCredential({required super.auth, super.user});
}

/// [FirebaseFirestorePlatform] backed by an in-memory document map keyed by
/// dotted path (`users/<uid>`, `app_config/admin_access`, ...).
class _FakeFirestorePlatform extends FirebaseFirestorePlatform {
  _FakeFirestorePlatform(this.docs);

  final Map<String, Map<String, dynamic>?> docs;

  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) =>
      this;

  @override
  CollectionReferencePlatform collection(String path) =>
      _FakeCollectionReference(this, path);

  @override
  DocumentReferencePlatform doc(String path) =>
      _FakeDocumentReference(this, path);

  void reset() {
    docs.clear();
  }
}

class _FakeCollectionReference extends CollectionReferencePlatform {
  _FakeCollectionReference(super.firestore, super.path) {
    parameters.putIfAbsent('where', () => <List<dynamic>>[]);
    parameters.putIfAbsent('orderBy', () => <List<dynamic>>[]);
    parameters.putIfAbsent('limit', () => null);
    parameters.putIfAbsent('limitToLast', () => null);
    parameters.putIfAbsent('startAt', () => null);
    parameters.putIfAbsent('startAfter', () => null);
    parameters.putIfAbsent('endAt', () => null);
    parameters.putIfAbsent('endBefore', () => null);
  }

  @override
  DocumentReferencePlatform doc([String? path]) {
    final resolvedPath = path ?? 'auto-${DateTime.now().microsecondsSinceEpoch}';
    return firestore.doc('${this.path}/$resolvedPath');
  }

  @override
  QueryPlatform where(List<List<dynamic>> conditions) => this;

  @override
  QueryPlatform limit(int limit) => this;

  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    final store = (firestore as _FakeFirestorePlatform).docs;
    final prefix = '$path/';
    final docs = store.entries
        .where((e) => e.key.startsWith(prefix) && e.value != null)
        .map((e) => DocumentSnapshotPlatform(
              firestore,
              e.key,
              e.value,
              PigeonSnapshotMetadata(
                hasPendingWrites: false,
                isFromCache: false,
              ),
            ))
        .toList();
    return QuerySnapshotPlatform(
        docs, const [], SnapshotMetadataPlatform(false, false));
  }
}

class _FakeDocumentReference extends DocumentReferencePlatform {
  _FakeDocumentReference(super.firestore, super.path);

  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    final store = (firestore as _FakeFirestorePlatform).docs;
    return DocumentSnapshotPlatform(
      firestore,
      path,
      store[path],
      PigeonSnapshotMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      ),
    );
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    (firestore as _FakeFirestorePlatform).docs[path] = Map.of(data);
  }

  @override
  Future<void> delete() async {
    (firestore as _FakeFirestorePlatform).docs[path] = null;
  }
}

class _FakeMessagingPlatform extends FirebaseMessagingPlatform {
  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;

  @override
  Future<String?> getToken({String? vapidKey}) async => null;
}

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  @override
  Future<void> initWithParams(SignInInitParameters params) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseApp app;
  late FirebaseAuth auth;
  late FirebaseFirestore firestore;
  late _FakeAuthPlatform fakeAuth;
  late _FakeFirestorePlatform fakeFirestore;

  setUpAll(() async {
    FirebasePlatform.instance =
        _FakeCorePlatform(<String, FirebaseAppPlatform>{});
    fakeAuth = _FakeAuthPlatform();
    FirebaseAuthPlatform.instance = fakeAuth;
    FirebaseFirestorePlatform.instance = fakeFirestore = _FakeFirestorePlatform(
      <String, Map<String, dynamic>?>{},
    );
    FirebaseMessagingPlatform.instance = _FakeMessagingPlatform();
    GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform();

    await Firebase.initializeApp(options: _testOptions);
    app = Firebase.app();
    auth = FirebaseAuth.instanceFor(app: app);
    firestore = FirebaseFirestore.instanceFor(app: app);
  });

  setUp(() {
    SuperAdminConfig.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fakeAuth.reset();
    fakeFirestore.reset();
    fakeFirestore.docs.addAll(<String, Map<String, dynamic>>{
      'users/$_superAdminUid': <String, dynamic>{
        'role': 'super_admin',
        'email': _superAdminEmail,
        'status': 'active',
      },
      'app_config/admin_access': <String, dynamic>{
        'primaryAdminEmail': _superAdminEmail,
      },
    });
  });

  tearDown(() {
    SuperAdminConfig.reset();
  });

  FirebaseContext buildContext() {
    return FirebaseContext(app: app, auth: auth, firestore: firestore);
  }

  test('super admin login resolves to superAdmin and persists the session',
      () async {
    final provider = AuthSessionProvider(context: buildContext());
    addTearDown(provider.dispose);

    await provider.signIn(
      email: _superAdminEmail,
      password: _superAdminPassword,
    );
    await Future.delayed(const Duration(milliseconds: 100));

    expect(provider.errorMessage, isNull);
    expect(provider.user?.email, _superAdminEmail);
    expect(provider.role, AppUserRole.superAdmin);
    expect(provider.isSuperAdmin, isTrue);
    expect(provider.isAuthenticated, isTrue);
    expect(provider.canAccessSuperAdmin, isTrue);
    // The Super Admin lives on the Master project and has no tenant workspace.
    expect(provider.workspaceSlug, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('auth_session_role_$_superAdminUid'),
      'super_admin',
    );
    expect(prefs.getBool('auth_session_active'), isTrue);
  });

  test('sign out clears the session; sign in again re-resolves from Firestore',
      () async {
    final provider = AuthSessionProvider(context: buildContext());
    addTearDown(provider.dispose);

    await provider.signIn(
      email: _superAdminEmail,
      password: _superAdminPassword,
    );
    expect(provider.role, AppUserRole.superAdmin);

    await provider.signOut();

    expect(provider.role, isNull);
    expect(provider.isAuthenticated, isFalse);
    expect(provider.isSuperAdmin, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_session_role_$_superAdminUid'), isNull);
    expect(prefs.getBool('auth_session_active'), isFalse);

    await provider.signIn(
      email: _superAdminEmail,
      password: _superAdminPassword,
    );
    await Future.delayed(const Duration(milliseconds: 100));
    expect(provider.role, AppUserRole.superAdmin);
    expect(provider.isSuperAdmin, isTrue);
    expect(provider.canAccessSuperAdmin, isTrue);
  });

  test('a regular admin user is never granted the super admin role',
      () async {
    const adminEmail = 'admin@green-hospital.com';
    const adminUid = 'company-admin-uid';
    fakeAuth.setUidForEmail(adminEmail, adminUid);
    fakeFirestore.docs['users/$adminUid'] = <String, dynamic>{
      'role': 'admin',
      'email': adminEmail,
      'status': 'active',
    };

    final provider = AuthSessionProvider(context: buildContext());
    addTearDown(provider.dispose);

    await provider.signIn(email: adminEmail, password: 'somePassword123');

    expect(provider.user?.email, adminEmail);
    expect(provider.role, AppUserRole.admin);
    expect(provider.isCompanyAdmin, isTrue);
    expect(provider.isSuperAdmin, isFalse);
    expect(provider.canAccessSuperAdmin, isFalse);
  });

  test('super admin email without a users doc is still resolved as super_admin '
      'via the Master config', () async {
    // No `users/super-admin-uid` doc — only the configured admin email.
    fakeFirestore.docs.remove('users/$_superAdminUid');

    final provider = AuthSessionProvider(context: buildContext());
    addTearDown(provider.dispose);

    await provider.signIn(
      email: _superAdminEmail,
      password: _superAdminPassword,
    );

    // The Super Admin is authorized by the Master app_config identity, not by
    // a directory entry, so the role is resolved even without a users/{uid} doc.
    expect(provider.role, AppUserRole.superAdmin);
    expect(provider.isSuperAdmin, isTrue);
    expect(provider.canAccessSuperAdmin, isTrue);
  });
}
