import 'package:flutter/foundation.dart';

import '../../firebase/firebase_context.dart';
import '../../firebase/firebase_manager.dart';
import '../../services/company_logo_service.dart';
import '../../services/company_service.dart';
import '../models/workspace.dart';
import 'tenant_seeder.dart';

/// Company-level details seeded into the tenant (data plane) project when a
/// workspace is provisioned.
class TenantCompanySpec {
  final String name;
  final String? email;
  final String? phone;
  final String? website;
  final String? address;
  final String industry;
  final String companySize;
  final String country;
  final String timezone;

  const TenantCompanySpec({
    required this.name,
    this.email,
    this.phone,
    this.website,
    this.address,
    this.industry = '',
    this.companySize = '',
    this.country = '',
    this.timezone = '',
  });
}

/// The initial Company Admin account created inside the tenant project.
class TenantAdminSpec {
  final String name;
  final String email;
  final String phone;
  final String password;

  const TenantAdminSpec({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
  });
}

/// What provisioning created inside the tenant (data plane) project.
class TenantProvisioningResult {
  final String companyId;
  final String adminUid;
  final String adminEmail;

  const TenantProvisioningResult({
    required this.companyId,
    required this.adminUid,
    required this.adminEmail,
  });
}

/// Provisions the tenant (data plane) side of a workspace.
///
/// This is the seam where an automated backend (a callable Cloud Function or a
/// provisioning service) can be swapped in later: today [DirectTenantProvisioner]
/// initializes the tenant [FirebaseApp] in-process and creates the company +
/// admin directly against the tenant project. A future backend implementation
/// would perform the same steps server-side (with privileged Admin SDK access)
/// and the rest of the provisioning flow would not change.
abstract class TenantProvisioner {
  /// Creates the tenant company record and the initial Company Admin inside
  /// the workspace's dedicated Firebase project.
  ///
  /// The tenant [FirebaseApp] is initialized (not activated) so the caller's
  /// active project — the Master control plane — is never disturbed.
  Future<TenantProvisioningResult> provision({
    required Workspace workspace,
    required TenantCompanySpec company,
    required TenantAdminSpec admin,
    Uint8List? logoBytes,
    String? logoContentType,
    void Function(double progress)? onLogoProgress,
  });

  /// Best-effort cleanup of anything [provision] may have created in the
  /// tenant project. Defaults to a no-op; implementations override to tear
  /// down resources they created.
  Future<void> rollback(Workspace workspace) async {}
}

/// In-process [TenantProvisioner] that writes directly to the tenant project
/// using the app's own Firebase SDK instances.
class DirectTenantProvisioner implements TenantProvisioner {
  DirectTenantProvisioner({FirebaseManager? firebaseManager})
      : _firebaseManager = firebaseManager ?? FirebaseManager.instance;

  final FirebaseManager _firebaseManager;

  /// In-flight provisioning state per workspace, used to tear the tenant side
  /// down completely when provisioning fails.
  final Map<String, _ActiveProvisioning> _active =
      <String, _ActiveProvisioning>{};

  @override
  Future<TenantProvisioningResult> provision({
    required Workspace workspace,
    required TenantCompanySpec company,
    required TenantAdminSpec admin,
    Uint8List? logoBytes,
    String? logoContentType,
    void Function(double progress)? onLogoProgress,
  }) async {
    final workspaceId = workspace.workspaceId;
    String step = 'initialize tenant app';
    try {
      debugPrint(
        'TenantProvisioner.provision: step "$step" starting '
        '(workspace=$workspaceId)…',
      );
      final tenantProjectId = workspace.firebaseConfig.projectId;
      final sharesDefaultProject = tenantProjectId.isNotEmpty &&
          tenantProjectId == _firebaseManager.defaultApp.options.projectId;

      FirebaseContext context;
      if (sharesDefaultProject) {
        // The tenant lives in the same project as the signed-in Super Admin
        // (the shared default project). Reuse the authenticated default app
        // context instead of a fresh unauthenticated tenant app, so every
        // provisioning write carries the Super Admin's token and satisfies the
        // Firestore `inCompany`/`isSuperAdmin` rules. A freshly initialized
        // secondary app has no signed-in user, so `request.auth` is null and
        // every write would be rejected with `permission-denied`.
        context = FirebaseContext();
        debugPrint(
          'TenantProvisioner.provision: step "$step" reused the authenticated '
          'default context (shared project "$tenantProjectId").',
        );
      } else {
        final tenantApp = await _firebaseManager.initializeTenantApp(
          workspaceId: workspace.workspaceId,
          options: workspace.firebaseConfig.toFirebaseOptions(),
        );
        debugPrint(
          'TenantProvisioner.provision: step "$step" succeeded '
          '(app=${tenantApp.name}).',
        );
        context = FirebaseContext.fromApp(tenantApp);
      }

      final state = _ActiveProvisioning(
        workspaceId: workspace.workspaceId,
        context: context,
      );
      _active[workspace.workspaceId] = state;

      step = 'allocate company id';
      debugPrint('TenantProvisioner.provision: step "$step" starting…');
      final companyRef = context.firestore.collection('companies').doc();
      state.companyId = companyRef.id;
      debugPrint(
        'TenantProvisioner.provision: step "$step" succeeded '
        '(companyId=${state.companyId}).',
      );

      String? logoUrl;
      if (logoBytes != null && state.companyId!.isNotEmpty) {
        step = 'encode company logo';
        debugPrint('TenantProvisioner.provision: step "$step" starting…');
        logoUrl = await CompanyLogoService.uploadLogoWithProgress(
          logoBytes,
          companyId: state.companyId!,
          contentType: logoContentType ?? 'image/png',
          onProgress: onLogoProgress,
        );
        debugPrint(
          'TenantProvisioner.provision: step "$step" succeeded '
          '(${logoUrl.length} chars).',
        );
      }

      step = 'onboard company and admin';
      debugPrint(
        'TenantProvisioner.provision: step "$step" starting '
        '(companyId=${state.companyId}, admin=${admin.email})…',
      );
      final result = await CompanyService(context: context).onboardCompany(
        companyId: state.companyId,
        name: company.name,
        email: company.email ?? '',
        phone: company.phone ?? '',
        address: company.address,
        logoUrl: logoUrl,
        website: company.website,
        industry: company.industry,
        companySize: company.companySize,
        country: company.country,
        timezone: company.timezone,
        adminName: admin.name,
        adminEmail: admin.email,
        adminPhone: admin.phone,
        adminPassword: admin.password,
      );
      debugPrint(
        'TenantProvisioner.provision: step "$step" succeeded '
        '(companyId=${result.companyId}, adminUid=${result.adminUid}).',
      );

      state.companyId = result.companyId;
      state.adminUid = result.adminUid;

      step = 'seed tenant defaults';
      debugPrint('TenantProvisioner.provision: step "$step" starting…');
      final seeder = TenantSeeder(context: context);
      state.seeds = await seeder.seed(
        companyId: result.companyId,
        adminUid: result.adminUid,
        adminEmail: result.adminEmail,
        companyName: company.name,
        supportEmail: company.email,
      );
      debugPrint('TenantProvisioner.provision: step "$step" succeeded.');

      _active.remove(workspace.workspaceId);
      return TenantProvisioningResult(
        companyId: result.companyId,
        adminUid: result.adminUid,
        adminEmail: result.adminEmail,
      );
    } catch (e, st) {
      debugPrint(
        'TenantProvisioner.provision: FAILED at step "$step" '
        'for workspace "$workspaceId" - $e\n$st',
      );
      await _teardownTenant(workspaceId);
      rethrow;
    }
  }

  @override
  Future<void> rollback(Workspace workspace) async {
    await _teardownTenant(workspace.workspaceId);
  }

  /// Tears down everything [provision] created inside the tenant project:
  /// seeded defaults, company + admin/user docs, then the tenant [FirebaseApp]
  /// itself. Every step is best-effort and idempotent.
  Future<void> _teardownTenant(String workspaceId) async {
    final state = _active.remove(workspaceId);
    if (state != null) {
      if (state.seeds != null) {
        try {
          await TenantSeeder(context: state.context).rollback(state.seeds!);
        } catch (_) {}
      }
      final adminUid = state.adminUid;
      if (adminUid != null) {
        try {
          await _deleteAdminDocs(state.context, adminUid);
          await state.context.firestore
              .collection('users')
              .doc(adminUid)
              .delete();
        } catch (_) {}
      }
      final companyId = state.companyId;
      if (companyId != null) {
        // Deleting the company document also removes its logo data URL — there
        // is no separate Cloud Storage object to purge.
        try {
          await state.context.firestore
              .collection('companies')
              .doc(companyId)
              .delete();
        } catch (_) {}
      }
    }
    try {
      await _firebaseManager.disposeTenant(workspaceId);
    } catch (_) {
      // The tenant app may still be in use (open listeners); disposal is
      // best-effort. The registry/allocation rollback continues regardless.
    }
  }

  Future<void> _deleteAdminDocs(
      FirebaseContext context, String adminUid) async {
    try {
      final snap = await context.firestore
          .collection('admins')
          .where('authUid', isEqualTo: adminUid)
          .limit(10)
          .get();
      for (final doc in snap.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// Mutable record of what [DirectTenantProvisioner.provision] has created so
/// far for a workspace, so a failure can be rolled back completely.
class _ActiveProvisioning {
  _ActiveProvisioning({required this.workspaceId, required this.context});

  final String workspaceId;
  final FirebaseContext context;
  String? companyId;
  String? adminUid;
  TenantSeedResult? seeds;
}
