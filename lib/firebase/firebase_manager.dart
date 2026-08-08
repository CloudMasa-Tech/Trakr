import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  Future<FirebaseApp> initializeTenantApp({
    required String workspaceId,
    FirebaseOptions? options,
  }) async {
    final cached = _apps[workspaceId];
    if (cached != null) return cached;

    final existing = Firebase.apps.where((app) => app.name == workspaceId);
    if (existing.isNotEmpty) {
      final app = existing.first;
      _apps[workspaceId] = app;
      return app;
    }

    final resolvedOptions = options ?? await _resolveOptions(workspaceId);
    final app = await Firebase.initializeApp(
      name: workspaceId,
      options: resolvedOptions,
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
    if (cached != null) return cached;

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
    _activeWorkspaceId = null;
    final context = FirebaseContext();
    _activeContext = context;
    FirebaseContextProvider.setActive(context);
    _contextApplier?.call(context);
    return context;
  }

  /// The [FirebaseFirestore] bound to the active (or [workspaceId]) project.
  FirebaseFirestore getFirestore([String? workspaceId]) =>
      FirebaseFirestore.instanceFor(app: getTenantApp(workspaceId));

  /// The [FirebaseAuth] bound to the active (or [workspaceId]) project.
  FirebaseAuth getAuth([String? workspaceId]) =>
      FirebaseAuth.instanceFor(app: getTenantApp(workspaceId));

  /// The [FirebaseMessaging] instance for the active project.
  ///
  /// firebase_messaging 15.x only supports the default Firebase app, so this
  /// always returns the default project's messaging instance.
  FirebaseMessaging getMessaging([String? workspaceId]) =>
      FirebaseMessaging.instance;

  /// Disposes the [FirebaseApp] for [workspaceId] and removes it from the
  /// cache. When the disposed app was active, the default project becomes
  /// active again. The default app itself can never be disposed.
  ///
  /// Fails loudly if the app is still in use (e.g. open Firestore listeners);
  /// cancel dependent streams before calling this.
  Future<void> disposeTenant(String workspaceId) async {
    if (workspaceId == defaultApp.name) {
      throw ArgumentError(
        'The default Firebase app cannot be disposed via disposeTenant().',
      );
    }
    final app = _apps[workspaceId];
    if (app == null) return;

    if (_activeWorkspaceId == workspaceId) {
      _activeWorkspaceId = null;
      _activeContext = null;
      final context = FirebaseContext();
      FirebaseContextProvider.setActive(context);
      _contextApplier?.call(context);
    }

    await app.delete();
    _apps.remove(workspaceId);
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
