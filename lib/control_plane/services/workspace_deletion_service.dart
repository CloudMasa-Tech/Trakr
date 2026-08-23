import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../firebase/firebase_context.dart';
import '../../firebase/firebase_manager.dart';
import '../../services/platform_service.dart';
import '../control_plane_firebase.dart';
import '../models/workspace.dart';
import '../repositories/workspace_allocation_repository.dart';
import '../utils/map_utils.dart';

/// What a permanent workspace deletion produced.
class WorkspaceDeletionReport {
  const WorkspaceDeletionReport({required this.warnings});

  /// Best-effort cleanup issues that did not block the deletion itself.
  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Orchestrates a permanent (hard) teardown of a workspace and everything tied
/// to it.
///
/// This is a hard delete — unlike the old soft delete it never flips the
/// workspace status to `decommissioned`. The flow:
///
/// 1. Removes the Master registry entry (`workspaces/{workspaceId}`) first so
///    the workspace disappears from the Workspaces list immediately.
/// 2. Best-effort: purges the tenant (data plane) project — every workspace
///    collection plus the company and white-label records (logos are stored as
///    data URLs inside those Firestore docs, so no Cloud Storage is involved).
/// 3. Best-effort: cleans control-plane leftovers — `tenant_users` identity
///    entries bound to the workspace, its Firebase project allocation, and its
///    `workspace_provision_logs`.
///
/// Only step 1 is authoritative: if the registry delete fails the whole call
/// throws and nothing else runs. Steps 2–3 are best-effort; their failures are
/// collected into [WorkspaceDeletionReport.warnings] (and recorded in the audit
/// trail) so the operator still gets an accurate success/error outcome.
class WorkspaceDeletionService {
  WorkspaceDeletionService({
    WorkspaceAllocationRepository? allocations,
    FirebaseManager? firebaseManager,
  })  : _allocations = allocations ?? WorkspaceAllocationRepository(),
        _firebaseManager = firebaseManager ?? FirebaseManager.instance;

  final WorkspaceAllocationRepository _allocations;
  final FirebaseManager _firebaseManager;

  /// Tenant (data plane) collections that hold workspace operational data and
  /// can be purged in full. `users`, `admins`, `companies`, `settings` and
  /// `app_config` are handled separately because they are scoped by company id
  /// or shared with the Master control plane.
  static const List<String> _tenantCollections = <String>[
    'staff',
    'managers',
    'employees',
    'staff_metadata',
    'attendance',
    'attendance_alerts',
    'attendance_logs',
    'checkout_requests',
    'leave_requests',
    'permission_requests',
    'notifications',
    'notification_actions',
    'event_dedupe',
    'departments',
    'designations',
    'leave_policies',
    'holidays',
    'permissions',
  ];

/// Permanently deletes [workspace] and its data by calling the Cloud Function.
/// Returns a report carrying any warnings or errors from the deletion process.
Future<WorkspaceDeletionReport> deleteWorkspace(Workspace workspace) async {
  final warnings = <String>[];

  // Capture tenant hints (companyId/adminUid) from the raw registry doc
  // before it is removed — the Workspace model does not carry them.
  final raw = await _readRegistryExtras(workspace.workspaceId);
  final companyId = raw['companyId'] as String?;
  final adminUid = raw['adminUid'] as String?;

  final tenantProjectId = workspace.firebaseConfig.projectId.trim().isNotEmpty
      ? workspace.firebaseConfig.projectId.trim()
      : workspace.firebaseProjectId.trim();

  if (tenantProjectId.isEmpty) {
    warnings.add(
      'Skipped GCP deletion: this workspace has no Firebase project ID. '
      'Removed the control-plane workspace record instead.',
    );
    await _purgeControlPlane(workspace, warnings: warnings);
  } else {
    // Call the Cloud Function only after validating the project identifier.
    // Uses raw HTTP with an EXPLICIT Authorization header (see
    // TenantProvisioner._deployTenantRulesAndIndexes for why the callable SDK
    // is avoided).
    try {
      final masterApp = _firebaseManager.defaultApp;
      debugPrint(
        'deleteWorkspace: registered apps: '
        '${Firebase.apps.map((a) => '"${a.name}"(${a.options.projectId})').join(', ')}',
      );
      debugPrint(
        'deleteWorkspace: invoking against app "${masterApp.name}" '
        '(project ${masterApp.options.projectId})',
      );

      final masterAuth = FirebaseAuth.instanceFor(app: masterApp);
      final currentUser = masterAuth.currentUser;
      if (currentUser == null) {
        debugPrint(
          'deleteWorkspace: no signed-in user on app "${masterApp.name}" - '
          'aborting before call',
        );
        throw StateError('Admin session expired, please log in again.');
      }

      final idToken = await currentUser.getIdToken(true) ?? '';
      if (idToken.isEmpty) {
        throw StateError('Admin session expired, please log in again.');
      }
      debugPrint(
        'deleteWorkspace: auth OK uid=${currentUser.uid} '
        'token=${idToken.substring(0, 20 < idToken.length ? 20 : idToken.length)}...',
      );

      final url = Uri.parse(
        'https://us-central1-${masterApp.options.projectId}'
        '.cloudfunctions.net/deleteWorkspace',
      );
      debugPrint('deleteWorkspace: POST $url');

      final response = await http
          .post(
            url,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'workspaceId': workspace.workspaceId,
                'projectId': tenantProjectId,
                'confirmation': 'DELETE',
              },
            }),
          )
          .timeout(const Duration(seconds: 300));

      debugPrint('deleteWorkspace: HTTP ${response.statusCode}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError(
          'Admin session expired or insufficient permissions, please log in '
          'again. (Server responded ${response.statusCode}: ${response.body})',
        );
      }
      if (response.statusCode != 200) {
        throw StateError(
          'Failed to delete workspace via Cloud Function: '
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final data = asStringKeyedMap(_callableResult(response.body));
      debugPrint('Cloud Function deleteWorkspace succeeded: $data');

      if (data['success'] != true) {
        throw StateError(
          'Cloud Function returned error: ${data['error'] ?? 'unknown error'}',
        );
      }

      if (data['warnings'] is List) {
        warnings.addAll(List<String>.from(data['warnings']));
      }

      debugPrint('WorkspaceDeletionService: Cloud Function deletion succeeded');
      await _purgeControlPlane(workspace, warnings: warnings);
    } catch (e) {
      debugPrint('WorkspaceDeletionService.deleteWorkspace: error - $e');
      rethrow;
    }
  }

  // Clean up local tenant data references (best-effort)
  // The Cloud Function handles the GCP project deletion and master Firestore cleanup
  if (workspace.firebaseConfig.isValid) {
    try {
      await _purgeTenantData(
        workspace,
        companyId: companyId,
        adminUid: adminUid,
        warnings: warnings,
      );
    } catch (e) {
      warnings.add('Tenant data purge failed: $e');
    }
  } else {
    warnings.add(
      'Skipped tenant data purge: the workspace configuration is incomplete.',
    );
  }

  // Record local audit trail
  await _recordDeletionAudit(
    workspace,
    companyId: companyId,
    warnings: warnings,
  );

  return WorkspaceDeletionReport(warnings: warnings);
}

  /// Unwraps the callable-protocol response body: returns the payload from
  /// `{"result": ...}`, or throws on `{"error": {...}}`.
  dynamic _callableResult(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('error')) {
        final error = decoded['error'];
        final message =
            error is Map ? (error['message'] ?? error.toString()) : error;
        throw StateError('Cloud Function returned error: $message');
      }
      return decoded['result'];
    }
    throw StateError(
      'Cloud Function returned an unexpected response body: $body',
    );
  }

  Future<Map<String, dynamic>> _readRegistryExtras(String workspaceId) async {
    try {
      final snap = await ControlPlaneFirebase.instance.firestore
          .collection('workspaces')
          .doc(workspaceId)
          .get();
      return snap.data() ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  // ---------------------------------------------------------------------------
  // Tenant (data plane) teardown
  // ---------------------------------------------------------------------------

  Future<void> _purgeTenantData(
    Workspace workspace, {
    required String? companyId,
    required String? adminUid,
    required List<String> warnings,
  }) async {
    FirebaseApp? app;
    final tenantProjectId = workspace.firebaseConfig.projectId;
    final sharesDefaultProject =
        tenantProjectId.isNotEmpty &&
            tenantProjectId ==
                FirebaseManager.instance.defaultApp.options.projectId;

    FirebaseContext context;
    try {
      if (sharesDefaultProject) {
        // Reuse the authenticated default app context so every delete operation
        // carries the Super Admin's token and satisfies Firestore rules.
        // A fresh secondary app is unauthenticated and all writes would fail.
        context = FirebaseContext();
      } else {
        app = await FirebaseManager.instance.initializeTenantApp(
          workspaceId: workspace.workspaceId,
          options: workspace.firebaseConfig.toFirebaseOptions(),
        );
        context = FirebaseContext.fromApp(app);
      }

      await _purgeTenantFirestore(
        context,
        companyId: companyId,
        adminUid: adminUid,
        warnings: warnings,
      );
    } catch (e) {
      // warnings are already collected inside _purgeTenantFirestore
    } finally {
      // BEST-EFFORT: Always attempt to dispose the tenant app so it is not
      // left cached after deletion. disposeTenant is idempotent — if the app
      // was already removed from the cache, the call is a no-op.
      if (app != null && !sharesDefaultProject) {
        try {
          await _firebaseManager.disposeTenant(workspace.workspaceId);
        } catch (_) {
          // disposal failure is best-effort; do not block workspace deletion
        }
      }
    }
  }

  Future<void> _purgeTenantFirestore(
    FirebaseContext context, {
    required String? companyId,
    required String? adminUid,
    required List<String> warnings,
  }) async {
    final db = context.firestore;

    // Company-scoped records (safe even when the tenant shares a project).
    if (companyId != null && companyId.isNotEmpty) {
      try {
        await _deleteScopedDocs(db, 'users', 'companyId', companyId);
      } catch (e) {
        warnings.add('Could not purge users: $e');
      }
      try {
        await _deleteScopedDocs(db, 'admins', 'companyId', companyId);
      } catch (e) {
        warnings.add('Could not purge admins: $e');
      }
      try {
        await db.collection('companies').doc(companyId).delete();
      } catch (e) {
        warnings.add('Could not purge the company document: $e');
      }
    }

    // Fixed-path tenant defaults seeded during provisioning.
    const fixedDocs = <String>[
      'settings/white_label',
      'app_config/admin_access',
      'geo_config/default',
      'offices/default',
      'holidays/default',
    ];
    for (final path in fixedDocs) {
      try {
        await db.doc(path).delete();
      } catch (_) {}
    }

    // QR tokens are keyed by tenant id (admin auth uid) or company id.
    if (adminUid != null && adminUid.isNotEmpty) {
      try {
        await db.collection('qr_tokens').doc(adminUid).delete();
      } catch (_) {}
    }
    if (companyId != null && companyId.isNotEmpty) {
      try {
        await db.collection('qr_tokens').doc(companyId).delete();
      } catch (_) {}
    }

    // Full purge of tenant-only collections.
    for (final name in _tenantCollections) {
      try {
        await _deleteCollection(db, name);
      } catch (e) {
        warnings.add('Could not purge "$name": $e');
      }
    }

    // REQUIRED BACKEND MECHANISM FOR FIREBASE AUTH CLEANUP:
    // Firebase Authentication users cannot be securely deleted from client-side 
    // code without their current password or highly privileged Admin SDK credentials.
    // If the Firebase Auth user must be deleted so the email can be reused, 
    // the system requires a backend Cloud Function (e.g., triggered by workspace 
    // deletion or a dedicated HTTPS callable) that uses the Admin SDK:
    // `admin.auth().deleteUser(adminUid)`.
    if (adminUid != null && adminUid.isNotEmpty) {
      warnings.add(
        'Auth User not deleted: Backend Cloud Function required to securely delete '
        'Firebase Auth user ($adminUid).',
      );
    }
  }

  /// Deletes every document of [collection] in chunks of 400 (the client SDK
  /// has no "delete collection" operation, so this paginates in batches).
  Future<void> _deleteCollection(FirebaseFirestore db, String name) async {
    final ref = db.collection(name);
    while (true) {
      final snap = await ref.limit(400).get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        if (['managers', 'users', 'admins', 'staff'].contains(name)) {
          await _deleteSubcollection(doc.reference.collection('notifications'));
          await _deleteSubcollection(doc.reference.collection('roles'));
        }
        await doc.reference.delete();
      }
      if (snap.docs.length < 400) return;
    }
  }

  /// Deletes documents in [collection] where [field] equals [value], in chunks
  /// of 400. Used for company-scoped records so other tenants (or the platform
  /// super admin) are never touched in a shared project.
  Future<void> _deleteScopedDocs(
    FirebaseFirestore db,
    String collection,
    String field,
    String value,
  ) async {
    while (true) {
      final snap = await db
          .collection(collection)
          .where(field, isEqualTo: value)
          .limit(400)
          .get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        if (['users', 'managers', 'admins', 'staff'].contains(collection)) {
          await _deleteSubcollection(doc.reference.collection('notifications'));
          await _deleteSubcollection(doc.reference.collection('roles'));
        }
        await doc.reference.delete();
      }
      if (snap.docs.length < 400) return;
    }
  }

  Future<void> _deleteSubcollection(CollectionReference ref) async {
    while (true) {
      final snap = await ref.limit(400).get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
      if (snap.docs.length < 400) return;
    }
  }

  // ---------------------------------------------------------------------------
  // Control plane cleanup
  // ---------------------------------------------------------------------------

  Future<void> _purgeControlPlane(
    Workspace workspace, {
    required List<String> warnings,
  }) async {
    final master = ControlPlaneFirebase.instance.firestore;

    // Login identity index entries pointing at this workspace.
    try {
      final snap = await master
          .collection('tenant_users')
          .where('workspaceId', isEqualTo: workspace.workspaceId)
          .get();
      for (final doc in snap.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (e) {
      warnings.add('Could not purge the tenant identity index: $e');
    }

    // Project allocation: permanently take the bound project out of the pool
    // so it is never handed to another tenant.
    try {
      final allocation =
          await _allocations.getByProjectId(workspace.firebaseProjectId);
      if (allocation != null &&
          allocation.allocatedWorkspaceId == workspace.workspaceId) {
        await _allocations.delete(workspace.firebaseProjectId);
      }
    } catch (e) {
      warnings.add('Could not delete the project allocation: $e');
    }

    // Provisioning audit logs referencing this workspace.
    try {
      final snap = await master
          .collection('workspace_provision_logs')
          .where('workspaceId', isEqualTo: workspace.workspaceId)
          .get();
      for (final doc in snap.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _recordDeletionAudit(
    Workspace workspace, {
    required String? companyId,
    required List<String> warnings,
  }) async {
    try {
      final platform =
          PlatformService(context: ControlPlaneFirebase.instance.context);
      await platform.recordAudit(
        category: 'workspace',
        action: 'delete_workspace',
        actorRole: 'super_admin',
        targetType: 'workspace',
        targetId: workspace.workspaceId,
        targetName: workspace.companyName,
        changes: <String, dynamic>{
          'workspaceCode': workspace.workspaceCode,
          'firebaseProjectId': workspace.firebaseProjectId,
          if (companyId != null) 'companyId': companyId,
          if (warnings.isNotEmpty) 'cleanupWarnings': warnings,
        },
      );
    } catch (e) {
      debugPrint('WorkspaceDeletionService: audit write failed - $e');
    }
  }
}
