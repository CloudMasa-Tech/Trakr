import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'firebase_context.dart';
import 'firebase_context_provider.dart';

/// Resolves the platform-specific [FirebaseOptions] for a given workspace id.
///
/// This is the seam where per-workspace Firebase projects are discovered at
/// runtime (e.g. from a registry doc or a hardcoded map) instead of being
/// baked into the app at compile time.
typedef TenantOptionsResolver = Future<FirebaseOptions> Function(
    String workspaceId);

/// Invoked whenever the active Firebase project changes so app singletons
/// (e.g. [NotificationService]) can re-bind to the new [FirebaseContext].
typedef FirebaseContextApplier = void Function(FirebaseContext context);

/// Manages dynamic, multi-project Firebase initialization.
///
/// Every workspace is bound to its own named [FirebaseApp] created with
/// `Firebase.initializeApp(name: workspaceId, options: firebaseOptions)`. Apps
/// are cached by workspace id, never initialized twice, and can be disposed and
/// re-created at runtime, so switching between Firebase projects does not
/// require restarting the app.
///
/// The default Firebase project (the one bootstrapped in `main()`) is never
/// disposed and remains the fallback whenever no workspace app is active.
class FirebaseManager {
  FirebaseManager._internal();

  /// The shared [FirebaseManager] instance.
  static final FirebaseManager instance = FirebaseManager._internal();

  final Map<String, FirebaseApp> _apps = <String, FirebaseApp>{};

  /// Workspaces currently undergoing provisioning. The tenant app for these
  /// workspaces must never be disposed until the provisioning operation
  /// completes (success or failure).
  final Set<String> _activeProvisioningWorkspaces = {};

  String? _activeWorkspaceId;
  FirebaseContext? _activeContext;

  /// Resolves [FirebaseOptions] for a workspace id when `initializeTenantApp`
  /// is called without explicit options.
  TenantOptionsResolver? tenantOptionsResolver;

  FirebaseContextApplier? _contextApplier;

  /// Registers a callback invoked after the active Firebase project changes.
  /// `main()` uses this to re-bind the [NotificationService] singleton.
  void setContextApplier(FirebaseContextApplier applier) {
    _contextApplier = applier;
  }

  /// The workspace ids that currently have a live [FirebaseApp] managed here.
  List<String> get initializedWorkspaceIds => _apps.keys.toList();

  /// The workspace id of the currently active [FirebaseApp], or `null` when
  /// the default project is active.
  String? get activeWorkspaceId => _activeWorkspaceId;

  /// The currently active tenant [FirebaseApp], or `null` when the default
  /// project is active.
  FirebaseApp? get activeApp =>
      _activeWorkspaceId == null ? null : _apps[_activeWorkspaceId];

  /// Whether a tenant app (not the default project) is currently active.
  bool get hasActiveTenant => _activeWorkspaceId != null;

  /// The [FirebaseContext] bound to the currently active project.
  FirebaseContext get activeContext => _activeContext ??= FirebaseContext();

  /// Whether [workspaceId] currently has an in-provisioning operation.
  bool _isProvisioning(String workspaceId) =>
      _activeProvisioningWorkspaces.contains(workspaceId);

  /// Whether [workspaceId] currently has an in-provisioning operation.
  bool isProvisioning(String workspaceId) => _isProvisioning(workspaceId);

  /// Adds [workspaceId] to the set of workspaces with active provisioning.
  /// Call this before starting any provisioning operation that uses the tenant
  /// Firebase app, so that [disposeTenant] knows not to dispose the app until
  /// the operation completes.
  void markProvisioning(String workspaceId) {
    _activeProvisioningWorkspaces.add(workspaceId);
  }

  /// Removes [workspaceId] from the set of workspaces with active provisioning.
  /// Call this after all provisioning operations using the tenant app have
  /// completed (success or failure).
  void clearProvisioning(String workspaceId) {
    _activeProvisioningWorkspaces.remove(workspaceId);
  }

  /// Whether a [FirebaseApp] is already initialized for [workspaceId], either
  /// through this manager or through the Firebase core registry.
  bool isInitialized(String workspaceId) =>
      _apps.containsKey(workspaceId) ||
      Firebase.apps.any((app) => app.name == workspaceId);

  /// Initializes (or reuses) the default Firebase project if it has not been
  /// bootstrapped yet. Used as the fallback before any workspace is resolved.
  Future<FirebaseApp> ensureDefaultApp({FirebaseOptions? options}) async {
    if (Firebase.apps.isEmpty) {
      final opts = options ?? DefaultFirebaseOptions.currentPlatform;
      await Firebase.initializeApp(options: opts);
    }
    return Firebase.app();
  }

  /// The default [FirebaseApp] — the fallback project that is never disposed.
  FirebaseApp get defaultApp {
    if (Firebase.apps.isEmpty) {
      throw StateError(
        'The default Firebase app has not been initialized. Call '
        'FirebaseManager.instance.ensureDefaultApp() or '
        'Firebase.initializeApp() first.',
      );
    }
    return Firebase.app();
  }

  /// Initializes the named [FirebaseApp] for [workspaceId] and caches it.
  ///
  /// Idempotent: returns the already-initialized app when one exists for the
  /// workspace, so duplicate initialization is prevented. When [options] is
  /// omitted, [tenantOptionsResolver] is used.
  ///
  /// When [options] IS provided, the existing app (if any) is verified against
  /// the requested project identity (`apiKey`/`projectId`/`appId`). A cached or
  /// registry app bound to a *different* project is a stale app (e.g. left over
  /// from an earlier run of the same session that used an older config, or a
  /// config referencing the master project) and is disposed and re-initialized
  /// from [options] so every downstream Auth/Firestore call uses the current
  /// config instead of a stale API key.
  Future<FirebaseApp> initializeTenantApp({
    required String workspaceId,
    FirebaseOptions? options,
  }) async {
    // A tracked wrapper can outlive its platform app (failed dispose, direct
    // out-of-band delete(), hot-restart churn). Never reuse a wrapper the SDK
    // no longer lists — every downstream Auth/Firestore call would throw
    // app/app-deleted. Drop it now so the branches below build a fresh app.
    final previouslyCached = _apps[workspaceId];
    if (previouslyCached != null && !_isAppLive(previouslyCached)) {
      debugPrint(
        'FirebaseManager.initializeTenantApp: tracked app "$workspaceId" is '
        'no longer registered with the Firebase SDK (deleted out-of-band) — '
        'dropping the stale wrapper; a fresh app instance will be created.',
      );
      _apps.remove(workspaceId);
    }
    if (options == null) {
      // No config was requested — reuse any app already bound to the workspace.
      final cached = _apps[workspaceId];
      if (cached != null) {
        debugPrint(
          'FirebaseManager.initializeTenantApp: REUSING tracked app '
          '"$workspaceId" (project ${cached.options.projectId})',
        );
        return cached;
      }
      final existing = Firebase.apps.where((app) => app.name == workspaceId);
      if (existing.isNotEmpty) {
        final app = existing.first;
        debugPrint(
          'FirebaseManager.initializeTenantApp: adopting UNTRACKED app '
          '"$workspaceId" (no options provided to verify it — caller beware)',
        );
        _apps[workspaceId] = app;
        return app;
      }
      debugPrint(
        'FirebaseManager.initializeTenantApp: creating NEW app "$workspaceId"',
      );
      return _initialize(
        workspaceId: workspaceId,
        options: await _resolveOptions(workspaceId),
      );
    }

    // A config was explicitly requested. Never silently reuse an app that was
    // initialized from a different config earlier in the session — that would
    // bind the workspace's Auth/Firestore calls to the wrong project (e.g. the
    // master project's API key) and surface as `api-key-not-valid`.
    final cached = _apps[workspaceId];
    if (cached != null) {
      if (_sameProject(cached.options, options)) {
        debugPrint(
          'FirebaseManager.initializeTenantApp: REUSING tracked app '
          '"$workspaceId" (project ${cached.options.projectId})',
        );
        return cached;
      }
      debugPrint(
        'FirebaseManager.initializeTenantApp: tracked app "$workspaceId" is '
        'bound to a different project than requested — replacing',
      );
      return _replaceStaleApp(workspaceId: workspaceId, options: options);
    }

    // Registered at the Firebase core level but NOT tracked by this manager.
    // This is a ZOMBIE app: it survived a previous disposeTenant() whose
    // app.delete() threw (e.g. live listeners during failed provisioning).
    // Its Firestore client may already be terminated — handing it back would
    // surface as [cloud_firestore/failed-precondition] "The client has already
    // been terminated". Always delete and recreate a completely fresh app.
    final untracked = Firebase.apps.where((app) => app.name == workspaceId).toList();
    if (untracked.isNotEmpty) {
      debugPrint(
        'FirebaseManager.initializeTenantApp: found UNTRACKED app '
        '"$workspaceId" (not in manager cache — likely a zombie from a '
        'failed dispose whose app.delete() did not complete). Deleting it and '
        'creating a fresh app.',
      );
      try {
        await untracked.first.delete();
      } catch (e) {
        debugPrint(
          'FirebaseManager.initializeTenantApp: failed to delete untracked '
          'app "$workspaceId" (${e is Exception ? e : e}) — attempting to '
          're-initialize over it anyway',
        );
      }
      return _initialize(workspaceId: workspaceId, options: options);
    }

    debugPrint(
      'FirebaseManager.initializeTenantApp: creating NEW app "$workspaceId" '
      '(project ${options.projectId})',
    );
    return _initialize(workspaceId: workspaceId, options: options);
  }

  /// Whether [app] is still registered with the Firebase SDK.
  ///
  /// An app whose `delete()` completed (or was triggered out-of-band) is
  /// removed from `Firebase.apps` while its Dart wrapper can survive in
  /// `_apps`. Reusing that stale wrapper makes every Auth/Firestore call throw
  /// `firebase_core/app-deleted`. Reuse is only safe while the registry still
  /// lists an app under the same name.
  static bool _isAppLive(FirebaseApp app) {
    try {
      return Firebase.apps.any((candidate) => candidate.name == app.name);
    } catch (_) {
      return false;
    }
  }

  /// Whether [a] and [b] describe the same Firebase project + app. These three
  /// fields are the project identity; every other option (authDomain, storage
  /// bucket, measurement id, …) follows from them.
  static bool _sameProject(FirebaseOptions a, FirebaseOptions b) {
    return a.apiKey == b.apiKey &&
        a.projectId == b.projectId &&
        a.appId == b.appId;
  }

  /// Disposes a stale [FirebaseApp] bound to [workspaceId] and re-initializes
  /// it from [options], so the workspace's app is always bound to the config
  /// the caller requested.
  ///
  /// Throws when the workspace is mid-provisioning (the app must not be
  /// disposed while a provisioning operation is in flight) or when the app is
  /// the default project — callers must resolve those states first.
  Future<FirebaseApp> _replaceStaleApp({
    required String workspaceId,
    required FirebaseOptions options,
  }) async {
    debugPrint(
      'FirebaseManager: replacing the stale Firebase app for workspace '
      '"$workspaceId" — it is bound to a different project than the requested '
      'config. Re-initializing from the current config.',
    );
    final cached = _apps[workspaceId];
    if (cached != null) {
      await disposeTenant(workspaceId);
    } else {
      final existing = Firebase.apps.where((app) => app.name == workspaceId);
      if (existing.isNotEmpty) {
        await existing.first.delete();
      }
    }
    return _initialize(workspaceId: workspaceId, options: options);
  }

  Future<FirebaseApp> _initialize({
    required String workspaceId,
    required FirebaseOptions options,
  }) async {
    final app = await Firebase.initializeApp(
      name: workspaceId,
      options: options,
    );
    _apps[workspaceId] = app;

    if (kIsWeb) {
      await FirebaseAuth.instanceFor(app: app).setPersistence(
        Persistence.LOCAL,
      );
      FirebaseFirestore.instanceFor(app: app).settings = const Settings(
        webExperimentalForceLongPolling: true,
      );
    }
    return app;
  }

  /// Returns the [FirebaseApp] bound to [workspaceId].
  ///
  /// When no workspace id is given, the active tenant app is returned, falling
  /// back to the default project when no tenant is active.
  FirebaseApp getTenantApp([String? workspaceId]) {
    final id = workspaceId ?? _activeWorkspaceId;
    if (id == null) return defaultApp;

    final cached = _apps[id];
    if (cached != null) {
      if (!_isAppLive(cached)) {
        debugPrint(
          'FirebaseManager.getTenantApp: cached app "$id" is no longer '
          'registered with the Firebase SDK (deleted out-of-band) — dropping '
          'stale wrapper.',
        );
        _apps.remove(id);
      } else {
        return cached;
      }
    }

    final existing = Firebase.apps.where((app) => app.name == id);
    if (existing.isNotEmpty) {
      final app = existing.first;
      _apps[id] = app;
      return app;
    }

    throw StateError(
      'No Firebase app has been initialized for workspace "$id". Call '
      'initializeTenantApp() first.',
    );
  }

  /// Initializes [workspaceId] (if needed) and makes it the active project.
  ///
  /// Returns the [FirebaseContext] bound to the newly active app.
  Future<FirebaseContext> activateTenant({
    required String workspaceId,
    FirebaseOptions? options,
  }) async {
    final app = await initializeTenantApp(
      workspaceId: workspaceId,
      options: options,
    );
    return activateApp(app, workspaceId: workspaceId);
  }

  /// Makes [app] the active project and rebinds the app-wide Firebase services.
  ///
  /// Updates [FirebaseContextProvider] so widgets and services resolve the new
  /// project, and notifies the registered [FirebaseContextApplier] so
  /// singletons (e.g. [NotificationService]) re-bind their instances.
  FirebaseContext activateApp(FirebaseApp app, {String? workspaceId}) {
    final isDefault = app.name == defaultApp.name;

    if (!isDefault) {
      final name = workspaceId ?? app.name;
      _apps[name] = app;
      _activeWorkspaceId = name;
    } else {
      _activeWorkspaceId = null;
    }

    final context =
        isDefault ? FirebaseContext() : FirebaseContext.fromApp(app);
    _activeContext = context;
    FirebaseContextProvider.setActive(context);
    _contextApplier?.call(context);
    return context;
  }

  /// Switches the active project back to the default Firebase project.
  FirebaseContext activateDefault() {
    // Capture BEFORE nulling — the provisioning lock belongs to the workspace
    // being deactivated, and must be released for dispose/retry cycles to work.
    final previousWorkspaceId = _activeWorkspaceId;
    _activeWorkspaceId = null;
    try {
      final context = FirebaseContext();
      _activeContext = context;
      FirebaseContextProvider.setActive(context);
      _contextApplier?.call(context);
      return context;
    } finally {
      clearProvisioning(previousWorkspaceId ?? '');
    }
  }

  /// Disposes the [FirebaseApp] for [workspaceId] and removes it from the
  /// cache. When the disposed app was active, the default project becomes
  /// active again. The default app itself can never be disposed.
  ///
  /// Fails loudly if the app is still in use (e.g. open Firestore listeners);
  /// cancel dependent streams before calling this.
  ///
  /// Idempotent: safely handles being called when the app has already been
  /// deleted or removed from the cache.
  Future<void> disposeTenant(String workspaceId) async {
    if (workspaceId == defaultApp.name) {
      throw ArgumentError(
        'The default Firebase app cannot be disposed via disposeTenant().',
      );
    }
    if (_isProvisioning(workspaceId)) {
      throw StateError(
        'Cannot dispose the tenant Firebase app for "$workspaceId" while a '
        'provisioning operation is still in progress. Wait for the provisioning '
        'to complete (success or failure) before disposing the app.',
      );
    }
    final app = _apps[workspaceId];
    if (app == null) {
      // Not tracked by this manager, but a zombie may still be registered at
      // the Firebase core level from an earlier failed dispose. Best-effort
      // clean it up so a later initializeTenantApp() can never pick it up.
      final zombie = Firebase.apps.where((a) => a.name == workspaceId).toList();
      if (zombie.isNotEmpty) {
        debugPrint(
          'FirebaseManager.disposeTenant: "$workspaceId" was not tracked but '
          'an unregistered app with that name exists — deleting the zombie.',
        );
        await _deleteAppWithRetry(zombie.first, workspaceId);
      }
      return;
    }

    if (_activeWorkspaceId == workspaceId) {
      _activeWorkspaceId = null;
      _activeContext = null;
      final context = FirebaseContext();
      FirebaseContextProvider.setActive(context);
      _contextApplier?.call(context);
    }

    // Explicitly terminate the tenant's Firestore client first. This tears
    // down streams/writes deterministically BEFORE app.delete(), making the
    // delete far less likely to fail — and guarantees that even if the rest
    // of teardown goes wrong, no terminated client is ever handed back out.
    try {
      await FirebaseFirestore.instanceFor(app: app).terminate();
    } catch (e) {
      debugPrint(
        'FirebaseManager.disposeTenant: Firestore terminate for '
        '"$workspaceId" failed (non-fatal, may already be terminated): $e',
      );
    }

    final deleted = await _deleteAppWithRetry(app, workspaceId);
    debugPrint(
      deleted
          ? 'FirebaseManager.disposeTenant: app "$workspaceId" fully deleted'
          : 'FirebaseManager.disposeTenant: WARNING — app "$workspaceId" could '
              'NOT be fully deleted; initializeTenantApp() will treat it as a '
              'zombie and replace it on next use',
    );
    _apps.remove(workspaceId);
  }

  /// Deletes a [FirebaseApp], retrying once after a short delay (in-flight
  /// platform teardown often needs a tick to release). Returns whether the
  /// deletion actually succeeded — callers must not assume it did.
  Future<bool> _deleteAppWithRetry(FirebaseApp app, String label) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await app.delete();
        return true;
      } catch (e) {
        debugPrint(
          'FirebaseManager._deleteAppWithRetry: app.delete() for "$label" '
          'failed (attempt $attempt/2): $e',
        );
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
    return false;
  }

  /// Disposes every cached tenant [FirebaseApp].
  ///
  /// Tenants that are still in use (open listeners) are skipped and stay
  /// cached so they can be disposed later.
  Future<void> disposeAllTenants() async {
    final ids = _apps.keys.toList();
    for (final id in ids) {
      try {
        await disposeTenant(id);
      } catch (_) {
        // Intentionally ignored; the tenant stays cached for a later retry.
      }
    }
  }

  Future<FirebaseOptions> _resolveOptions(String workspaceId) async {
    final resolver = tenantOptionsResolver;
    if (resolver == null) {
      throw StateError(
        'No FirebaseOptions available for workspace "$workspaceId". Pass '
        '`options:` to initializeTenantApp() or register '
        'FirebaseManager.instance.tenantOptionsResolver.',
      );
    }
    return resolver(workspaceId);
  }
}
