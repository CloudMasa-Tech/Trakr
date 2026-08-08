import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/workspace_status.dart';
import 'workspace_registry_service.dart';

/// Provides cross-project analytics for the Super Admin console.
///
/// In a full Multi-Tenant deployment, aggregating analytics across hundreds of
/// separate Firebase projects cannot be done effectively from the client (e.g.
/// via fan-out queries). That path is intended to eventually go through a
/// centralized backend (a Cloud Function aggregating via BigQuery or a
/// cross-project pipeline).
///
/// Today the platform runs on a single Firebase project, so the values below
/// are computed from real data in that project wherever a source exists:
///
/// - [getGlobalTotalUsers] counts the master `users` collection.
/// - [getLastLoginTime] reads the most recent `lastLoginAt` in `users`.
/// - [getWorkspaceHealthScore] derives from the workspace registry status.
class CrossProjectAnalyticsService {
  CrossProjectAnalyticsService({
    WorkspaceRegistryService? registry,
    FirebaseFirestore? firestore,
  })  : _registry = registry ?? WorkspaceRegistryService(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  final WorkspaceRegistryService _registry;
  final FirebaseFirestore _firestore;

  /// Returns the most recent user login recorded in the master `users`
  /// collection (the single-project equivalent of the tenant's last activity).
  Future<DateTime?> getLastLoginTime(String workspaceId) async {
    final snapshot = await _firestore
        .collection('users')
        .orderBy('lastLoginAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final value = snapshot.docs.first.data()['lastLoginAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  /// Derives a workspace health score (0–100) from real registry state:
  /// active workspaces are healthy, provisioning/suspended/decommissioned ones
  /// score lower. Replaces the previous hardcoded `98`.
  Future<int> getWorkspaceHealthScore(String workspaceId) async {
    final workspace = await _registry.resolveById(workspaceId);
    if (workspace == null) return 0;
    return switch (workspace.status) {
      WorkspaceStatus.active => 100,
      WorkspaceStatus.provisioning => 50,
      WorkspaceStatus.suspended => 30,
      WorkspaceStatus.decommissioned => 0,
    };
  }

  /// Counts users across the master `users` collection (the single-project
  /// equivalent of "all tenants").
  Future<int> getGlobalTotalUsers() async {
    final snapshot = await _firestore.collection('users').count().get();
    return snapshot.count ?? 0;
  }
}
