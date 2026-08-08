import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase/firebase_context.dart';
import '../../firebase/firebase_manager.dart';
import '../models/workspace.dart';

/// Bootstraps a resolved [Workspace] into a live tenant Firebase project.
///
/// Owns the tenant (data plane) lifecycle on top of [FirebaseManager]:
///
/// - `bootstrap` initializes and activates the workspace's named
///   [FirebaseApp] and caches the workspace config locally so a later app
///   restart can reconnect automatically.
/// - `restoreLastWorkspace` reconnects from the local cache only (no network
///   needed), which is what powers auto-reconnect after restart.
/// - `clearLastWorkspace` tears the tenant app down and forgets the cache.
///
/// All reads of the Master control plane are left to `LoginWorkspaceResolverService`;
/// this service never queries Firestore directly.
class TenantBootstrapService {
  TenantBootstrapService._internal();

  /// Shared instance used by the app.
  static final TenantBootstrapService instance =
      TenantBootstrapService._internal();

  static const String _cacheIdKey = 'workspace_cache_id';
  static const String _cacheJsonKey = 'workspace_cache_json';

  Workspace? _lastWorkspace;

  /// The most recently bootstrapped or restored workspace, or `null` when the
  /// app is not connected to a tenant yet.
  Workspace? get lastWorkspace => _lastWorkspace;

  /// Initializes and activates the tenant [FirebaseApp] for [workspace], then
  /// caches the workspace locally for automatic reconnect on the next launch.
  Future<FirebaseContext> bootstrap(Workspace workspace) async {
    _lastWorkspace = workspace;
    final context = await FirebaseManager.instance.activateTenant(
      workspaceId: workspace.workspaceId,
      options: workspace.firebaseConfig.toFirebaseOptions(),
    );
    await _cacheWorkspace(workspace);
    return context;
  }

  /// Reconnects to the workspace that was active the last time the app ran.
  ///
  /// Returns `null` when no workspace has been connected before, or throws when
  /// the cached workspace exists but cannot be activated (e.g. corrupted or
  /// incomplete credentials) — the caller should [clearLastWorkspace] in that
  /// case.
  Future<FirebaseContext?> restoreLastWorkspace() async {
    final workspace = await _readCachedWorkspace();
    if (workspace == null) {
      _lastWorkspace = null;
      return null;
    }
    _lastWorkspace = workspace;
    return FirebaseManager.instance.activateTenant(
      workspaceId: workspace.workspaceId,
      options: workspace.firebaseConfig.toFirebaseOptions(),
    );
  }

  /// Disposes the tenant [FirebaseApp] and forgets the cached workspace, so the
  /// app returns to the workspace-code entry flow.
  Future<void> clearLastWorkspace() async {
    final workspace = _lastWorkspace ?? await _readCachedWorkspace();
    if (workspace != null) {
      try {
        await FirebaseManager.instance.disposeTenant(workspace.workspaceId);
      } catch (_) {
        // The tenant app may still be in use (open listeners); disposal is
        // best-effort. The cache is cleared regardless.
      }
    }
    _lastWorkspace = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheIdKey);
    await prefs.remove(_cacheJsonKey);
  }

  Future<void> _cacheWorkspace(Workspace workspace) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheIdKey, workspace.workspaceId);
      await prefs.setString(_cacheJsonKey, _toCacheJson(workspace));
    } catch (_) {
      // Caching is best-effort; a failed cache write must not fail login.
    }
  }

  Future<Workspace?> _readCachedWorkspace() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheJsonKey);
      if (json == null || json.isEmpty) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      final id = map['workspaceId'] as String?;
      if (id == null || id.isEmpty) return null;
      return Workspace.fromMap(map, id);
    } catch (_) {
      return null;
    }
  }

  /// Serializes a workspace into a JSON-safe map.
  ///
  /// `Workspace.toMap()` writes Firestore `Timestamp`s (which `jsonEncode`
  /// cannot serialize), so the cache uses plain ISO strings instead. Timestamps
  /// are not needed to reconnect, so they degrade to `null` on restore.
  String _toCacheJson(Workspace workspace) {
    return jsonEncode({
      'workspaceId': workspace.workspaceId,
      'workspaceCode': workspace.workspaceCode,
      'workspaceSlug': workspace.workspaceSlug,
      'companyName': workspace.companyName,
      'firebaseProjectId': workspace.firebaseProjectId,
      'firebaseConfig': workspace.firebaseConfig.toMap(),
      'status': workspace.status.value,
      'onboardingStatus': workspace.onboardingStatus.value,
      'subscription': {
        'planId': workspace.subscription.planId,
        'planName': workspace.subscription.planName,
        'status': workspace.subscription.status.value,
        'billingCycle': workspace.subscription.billingCycle.value,
        'price': workspace.subscription.price,
        'currency': workspace.subscription.currency,
        'seats': workspace.subscription.seats,
      },
      if (workspace.supportEmail != null)
        'supportEmail': workspace.supportEmail,
      if (workspace.createdAt != null)
        'createdAt': workspace.createdAt!.toIso8601String(),
      if (workspace.updatedAt != null)
        'updatedAt': workspace.updatedAt!.toIso8601String(),
    });
  }
}
