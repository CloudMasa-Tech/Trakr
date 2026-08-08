import 'dart:typed_data';

import '../../services/platform_service.dart';
import '../models/firebase_project_allocation.dart';
import '../models/subscription.dart';
import '../models/tenant_identity.dart';
import '../models/workspace.dart';
import '../models/workspace_status.dart';
import '../repositories/tenant_identity_repository.dart';
import '../repositories/workspace_allocation_repository.dart';
import 'tenant_provisioner.dart';
import 'workspace_registry_service.dart';

/// Why workspace provisioning could not complete.
enum WorkspaceProvisioningError {
  /// The requested workspace code is already registered (or empty).
  codeUnavailable(
    'A workspace with this code already exists. Choose another one.',
  ),

  /// The allocation pool has no unused Firebase project to hand out.
  noProjectsAvailable(
    'No unused Firebase projects are available. '
    'The platform team needs to add capacity to the pool.',
  ),

  /// A candidate project could not be reserved atomically.
  allocationFailed(
    'Could not reserve a Firebase project for this workspace. '
    'Please try again.',
  ),

  /// Something failed partway through provisioning.
  provisioningFailed(
    'Workspace provisioning failed and the workspace was marked as failed. '
    'It remains in the registry for review.',
  ),

  /// An unexpected error interrupted provisioning.
  unexpected(
    'Workspace provisioning failed unexpectedly. Please try again.',
  );

  const WorkspaceProvisioningError(this.message);

  /// Human-readable message safe to show to the user.
  final String message;
}

/// Thrown by [WorkspaceProvisioningService.provisionWorkspace] when a
/// workspace cannot be provisioned.
class WorkspaceProvisioningException implements Exception {
  const WorkspaceProvisioningException(this.error, {this.details});

  /// The machine-readable reason for the failure.
  final WorkspaceProvisioningError error;

  /// Optional extra detail (e.g. the underlying error) for diagnostics.
  final String? details;

  /// Human-readable message safe to show to the user.
  String get message =>
      details == null ? error.message : '${error.message} $details';

  @override
  String toString() => message;
}

/// What a successful provisioning run produced.
class WorkspaceProvisioningResult {
  /// The registered workspace entry in the Master control plane.
  final Workspace workspace;

  /// The initial company + admin created inside the tenant project.
  final TenantProvisioningResult tenant;

  /// The Firebase project that was allocated to this workspace.
  final FirebaseProjectAllocation allocation;

  const WorkspaceProvisioningResult({
    required this.workspace,
    required this.tenant,
    required this.allocation,
  });
}

/// Orchestrates end-to-end provisioning of a new tenant workspace.
///
/// Runs entirely against the Master Firebase control plane plus one hand-off
/// to [TenantProvisioner] for the tenant (data plane) project:
///
/// 1. Allocates an unused, pre-created Firebase project (atomically).
/// 2. Saves the project's config in the Master `workspaces/{workspaceId}` doc.
/// 3. Marks the project allocated so it can never be reused.
/// 4. Stores the workspace metadata (code, company, subscription, support).
/// 5. Creates the initial Company Admin inside the tenant project and seeds
///    every tenant default (departments, designations, attendance settings,
///    leave policies, holiday calendar, roles/permissions, QR token, branding).
/// 6. Marks the workspace active/ready and returns the result.
///
/// On any failure the run rolls back what it created inside the tenant project
/// and marks the workspace `failed`, keeping the registry entry and its bound
/// project allocation so the failure is visible and can be retried — a
/// half-provisioned state never survives, and a failed run never silently
/// disappears.
class WorkspaceProvisioningService {
  WorkspaceProvisioningService({
    WorkspaceRegistryService? registry,
    WorkspaceAllocationRepository? allocations,
    TenantProvisioner? provisioner,
    TenantIdentityRepository? identities,
  })  : _registry = registry ?? WorkspaceRegistryService(),
        _allocations = allocations ?? WorkspaceAllocationRepository(),
        _provisioner = provisioner ?? DirectTenantProvisioner(),
        _identities = identities ?? TenantIdentityRepository();

  final WorkspaceRegistryService _registry;
  final WorkspaceAllocationRepository _allocations;
  final TenantProvisioner _provisioner;
  final TenantIdentityRepository _identities;

  /// Provisions a brand-new workspace end to end.
  ///
  /// [workspaceCode] is normalized to a lowercase slug and must be unique.
  /// [company] and [admin] describe what gets seeded into the tenant project;
  /// [subscription] and [supportEmail] are platform-level metadata stored in
  /// the Master registry. An optional [logoBytes]/[logoContentType] pair is
  /// encoded into the company record as a data URL, reporting [onLogoProgress]
  /// as a value in `[0, 1]`.
  Future<WorkspaceProvisioningResult> provisionWorkspace({
    required String workspaceCode,
    required TenantCompanySpec company,
    required TenantAdminSpec admin,
    Subscription subscription = const Subscription.empty(),
    String? supportEmail,
    Uint8List? logoBytes,
    String? logoContentType,
    void Function(double progress)? onLogoProgress,
  }) async {
    final code = workspaceCode.trim().toLowerCase();
    if (code.isEmpty || !await _registry.isCodeAvailable(code)) {
      throw const WorkspaceProvisioningException(
        WorkspaceProvisioningError.codeUnavailable,
      );
    }

    final allocation = await _reserveProject();

    Workspace? workspace;
    try {
      workspace = await _registry.registerWorkspace(
        companyName: company.name,
        workspaceCode: code,
        firebaseProjectId: allocation.projectId,
        firebaseConfig: allocation.firebaseConfig,
        subscription: subscription,
        supportEmail: supportEmail,
      );

      await _registry.setOnboardingStatus(
        workspace.workspaceId,
        WorkspaceOnboardingStatus.configuring,
      );
      await _allocations.bindWorkspace(
          allocation.projectId, workspace.workspaceId);

      final tenant = await _provisioner.provision(
        workspace: workspace,
        company: company,
        admin: admin,
        logoBytes: logoBytes,
        logoContentType: logoContentType,
        onLogoProgress: onLogoProgress,
      );

      await _registry.markProvisioned(workspace.workspaceId);
      await _registry.recordAdminEmail(workspace.workspaceId, admin.email);
      await _identities.upsert(
        email: admin.email,
        workspaceId: workspace.workspaceId,
        role: TenantIdentityRole.companyAdmin,
        name: admin.name,
      );
      await _recordProvisioningAudit(
        workspace,
        action: 'provision_workspace',
        success: true,
      );

      return WorkspaceProvisioningResult(
        workspace: workspace,
        tenant: tenant,
        allocation: allocation,
      );
    } on WorkspaceProvisioningException {
      await _handleProvisioningFailure(workspace, allocation);
      rethrow;
    } catch (e) {
      await _handleProvisioningFailure(workspace, allocation);
      throw WorkspaceProvisioningException(
        WorkspaceProvisioningError.provisioningFailed,
        details: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Picks an available project and claims it atomically.
  Future<FirebaseProjectAllocation> _reserveProject() async {
    final available = await _allocations.listAvailable();
    if (available.isEmpty) {
      throw const WorkspaceProvisioningException(
        WorkspaceProvisioningError.noProjectsAvailable,
      );
    }

    for (final candidate in available) {
      final claimed = await _allocations.claimByProjectId(candidate.projectId);
      if (claimed) return candidate;
    }

    throw const WorkspaceProvisioningException(
      WorkspaceProvisioningError.noProjectsAvailable,
    );
  }

  /// Handles a failed provisioning run.
  ///
  /// When the workspace was already registered, the tenant side is rolled back
  /// and the registry entry is marked `failed` — the entry and its bound
  /// allocation are kept so the failure is visible and retryable. Only when
  /// nothing was registered yet is the reserved allocation released.
  Future<void> _handleProvisioningFailure(
    Workspace? workspace,
    FirebaseProjectAllocation allocation,
  ) async {
    if (workspace == null) {
      try {
        await _allocations.release(allocation.projectId);
      } catch (_) {}
      return;
    }

    try {
      await _provisioner.rollback(workspace);
    } catch (_) {}
    try {
      await _registry.markFailed(workspace.workspaceId);
    } catch (_) {}

    await _recordProvisioningAudit(
      workspace,
      action: 'provision_workspace_failed',
      success: false,
    );
  }

  /// Records the provisioning outcome in the Master audit + activity trails.
  ///
  /// Best-effort only — a failed audit write must never mask the provisioning
  /// result that is about to surface to the caller.
  Future<void> _recordProvisioningAudit(
    Workspace workspace, {
    required String action,
    required bool success,
  }) async {
    try {
      final platform = PlatformService();
      await platform.recordAudit(
        category: 'workspace',
        action: action,
        actorRole: 'super_admin',
        targetType: 'workspace',
        targetId: workspace.workspaceId,
        targetName: workspace.companyName,
        changes: <String, dynamic>{
          'workspaceCode': workspace.workspaceCode,
          'firebaseProjectId': workspace.firebaseProjectId,
          'success': success,
        },
      );
      if (success) {
        await platform.recordActivity(
          type: 'workspace_provisioned',
          title: 'Workspace provisioned',
          detail: '${workspace.companyName} (${workspace.workspaceCode})',
          companyName: workspace.companyName,
        );
      }
    } catch (_) {
      // Best-effort: audit logging never affects the provisioning outcome.
    }
  }
}
