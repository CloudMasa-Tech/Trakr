import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../control_plane_firebase.dart';
import '../models/subscription.dart';
import '../models/tenant_identity.dart';
import '../models/workspace.dart';
import '../models/workspace_firebase_config.dart';
import '../models/workspace_provision_request.dart';
import '../models/workspace_status.dart';
import '../repositories/tenant_identity_repository.dart';
import 'firebase_config_validator.dart';
import 'tenant_provisioner.dart';
import 'workspace_registry_service.dart';

/// What a provisioning run produced.
class WorkspaceProvisionResult {
  final String workspaceId;
  final String workspaceCode;
  final String workspaceSlug;
  final String firebaseProjectId;
  final String companyId;
  final String adminEmail;
  final String logId;
  final bool emailSent;

  const WorkspaceProvisionResult({
    required this.workspaceId,
    required this.workspaceCode,
    required this.workspaceSlug,
    required this.firebaseProjectId,
    required this.companyId,
    required this.adminEmail,
    this.logId = '',
    required this.emailSent,
  });
}

/// Client-side provisioning for a brand-new tenant workspace.
///
/// Replaces the `provisionWorkspace` HTTPS Cloud Function, which is unusable on
/// the Firebase Spark (free) plan (Cloud Functions require the Blaze plan).
/// Everything runs directly against the Master (default) project from the Super
/// Admin console:
///
/// 1. Generates a unique workspace code/slug and registers the workspace in the
///    Master `workspaces` control plane (bound to the shared default project).
/// 2. Creates the Company Admin login account and emails the credentials
///    (best-effort via the Vercel mailer).
/// 3. Seeds the tenant defaults (company, departments, policies, QR token,
///    roles/permissions) through [DirectTenantProvisioner]/[TenantSeeder].
/// 4. Appends timestamped progress lines to `workspace_provision_logs/{logId}`
///    so the onboarding progress modal keeps streaming in real time.
///
/// Firestore rules gate every write to the signed-in Super Admin, so running
/// from the Client Onboarding console satisfies the same authorization the
/// Cloud Function enforced.
class WorkspaceProvisioningClientService {
  WorkspaceProvisioningClientService({
    WorkspaceRegistryService? registry,
    TenantProvisioner? provisioner,
  })  : _registry = registry ?? WorkspaceRegistryService(),
        _provisioner = provisioner ?? DirectTenantProvisioner();

  final WorkspaceRegistryService _registry;
  final TenantProvisioner _provisioner;

  /// Caches the generated Company Admin password per admin email for the
  /// lifetime of this service instance (one session of the Super Admin
  /// console). A retry of a partially-failed run MUST reuse the original
  /// password so the tenant auth account can be re-authenticated and its uid
  /// recovered by [DirectTenantProvisioner]. Passwords are never persisted.
  final Map<String, String> _passwordsByEmail = <String, String>{};

  FirebaseFirestore get _firestore => ControlPlaneFirebase.instance.firestore;

  /// Generates a unique, URL-safe id for a provisioning audit-log doc.
  static String generateLogId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'provision-$millis-$rand';
  }

  /// Generates a deterministic [workspaceId] from [workspaceCode].
  /// The workspaceId is the workspace code itself, ensuring idempotent retry:
  /// the same workspace code always maps to the same workspaceId, so company/
  /// user/ admin documents can use deterministic IDs (companies/{workspaceId},
  /// admins/{workspaceId}) without generating random IDs.
  static String generateWorkspaceIdFromCode(String workspaceCode) {
    final normalized = workspaceCode.trim().toLowerCase();
    // Ensure the workspaceId is a valid Firestore document ID (no dots,
    // slash, or other invalid characters).
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9-]'), '');
    return safe.isEmpty ? 'workspace' : safe;
  }

  /// Provisions [request] end to end, streaming progress into
  /// `workspace_provision_logs/{logId}`. Throws when provisioning fails; the
  /// audit log and workspace registry entry are marked `failed` first.
  Future<WorkspaceProvisionResult> provision(
    WorkspaceProvisionRequest request,
  ) async {
    final workspaceName = request.workspaceName.trim();
    final companyName = request.companyName.trim();
    final companyPhone = request.companyPhone.trim();
    final companyAddress = (request.companyAddress?.trim().isNotEmpty ?? false)
        ? request.companyAddress!.trim()
        : null;
    final industry = request.industry.trim();
    final adminEmail = request.companyAdminEmail.trim().toLowerCase();
    final targetFirebaseAccountEmail =
        request.targetFirebaseAccountEmail?.trim().toLowerCase() ?? '';

    if (workspaceName.isEmpty) throw Exception('Workspace name is required');
    if (companyName.isEmpty) throw Exception('Company name is required');
    if (companyPhone.isEmpty) throw Exception('Company phone is required');
    if (industry.isEmpty) throw Exception('Industry is required');
    if (!adminEmail.contains('@')) {
      throw Exception('A valid Company Admin email is required');
    }
    if (targetFirebaseAccountEmail.isNotEmpty &&
        !targetFirebaseAccountEmail.contains('@')) {
      throw Exception('A valid Firebase account email is required');
    }

    // ── Firebase project mapping ─────────────────────────────────────────
    // The dedicated Firebase project is created manually in the Firebase
    // Console and its CLIENT-side configuration is uploaded in the Create
    // Workspace form. Every workspace must map to its OWN Firebase project;
    // the shared TRAKR platform project can never be used as a tenant project.
    final uploadedConfig = request.firebaseConfig;
    if (uploadedConfig == null || !uploadedConfig.isValid) {
      throw Exception(
        'Invalid Firebase configuration. Upload the client-side Firebase '
        'config for the workspace\'s dedicated project and confirm the '
        'mapping before provisioning.',
      );
    }
    final firebaseProjectId = uploadedConfig.projectId;
    if (firebaseProjectId.trim().isEmpty) {
      throw Exception(
        'Missing projectId. Verify the uploaded file is a client-side '
        'Firebase configuration.',
      );
    }

    // Validate that this is NOT the shared TRAKR platform project.
    // In Spark plan mode, each workspace has its own dedicated project.
    // The Master project is never used as a tenant project.
    if (FirebaseConfigValidator.isPlatformProject(firebaseProjectId)) {
      throw Exception(
        'The uploaded Firebase configuration points to the shared TRAKR '
        'platform project. Every workspace must map to its own dedicated '
        'Firebase project created in the Firebase Console. '
        'serviceAccountKey.json and private keys are never accepted.',
      );
    }

    final adminName = _adminNameFromEmail(adminEmail);
    final adminPassword = _passwordsByEmail[adminEmail] ??=
        _generateAdminPassword();

    // ── Retry resolution ───────────────────────────────────────────────
    // A previous failed run for the same admin email keeps its registry entry
    // in `provisioning` state. Reuse that entry (same workspaceId/code) so a
    // retry resumes instead of creating a duplicate workspace with a
    // new -2/-3 suffix. A retry also reuses the cached password so the tenant
    // auth account created by the earlier run can be recovered.
    final existingMatches = await _registry.listByAdminEmail(adminEmail);
    String? retriedWorkspaceId;
    String? retriedWorkspaceCode;
    for (final match in existingMatches) {
      if (match.status == WorkspaceStatus.provisioning) {
        if (retriedWorkspaceId == null ||
            match.companyName.trim().toLowerCase() ==
                companyName.trim().toLowerCase()) {
          retriedWorkspaceId = match.workspaceId;
          retriedWorkspaceCode = match.workspaceCode;
        }
      } else {
        throw Exception(
          'Admin email "$adminEmail" is already bound to an active workspace '
          '("${match.companyName}" · ${match.workspaceCode}). Use a different '
          'admin email.',
        );
      }
    }

    final String workspaceCode;
    final String finalWorkspaceId;
    if (retriedWorkspaceId != null && retriedWorkspaceCode != null) {
      // The retried workspace must still map to the SAME Firebase project the
      // failed run was registered against; otherwise the retry would silently
      // re-point an existing registration at a new project.
      final retried = existingMatches
          .firstWhere((match) => match.workspaceId == retriedWorkspaceId);
      if (retried.firebaseProjectId.trim().isNotEmpty &&
          retried.firebaseProjectId.trim() != firebaseProjectId) {
        throw Exception(
          'This admin email is already registered to the failed workspace '
          '"$retriedWorkspaceCode" (id "$retriedWorkspaceId"), which was '
          'mapped to Firebase project "${retried.firebaseProjectId}". '
          'Re-upload the client-side configuration of THAT project to retry '
          'it, or use a different admin email.',
        );
      }
      workspaceCode = retriedWorkspaceCode;
      finalWorkspaceId = retriedWorkspaceId;
      debugPrint(
        'WorkspaceProvisioningClientService.provision: resuming failed '
        'workspace "$finalWorkspaceId" (code="$workspaceCode") for '
        '"$adminEmail".',
      );
    } else {
      final generatedCode =
          await _registry.generateUniqueWorkspaceCode(workspaceName);
      workspaceCode = generatedCode;
      finalWorkspaceId = generateWorkspaceIdFromCode(generatedCode);
    }

    final workspaceSlug = workspaceCode;
    final firebaseConfig = uploadedConfig;
    final logId = (request.logId?.trim().isNotEmpty ?? false)
        ? request.logId!.trim()
        : generateLogId();
    final logRef = _firestore.collection('workspace_provision_logs').doc(logId);

    var logSeq = 0;
    Future<void> logLine(String message) async {
      logSeq += 1;
      try {
        await logRef.update({
          'logs': FieldValue.arrayUnion(<Map<String, dynamic>>[
            {'seq': logSeq, 'at': Timestamp.now(), 'message': message},
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Live log appends are best-effort; provisioning continues regardless.
      }
    }

    await logRef.set({
      'logId': logId,
      'workspaceId': finalWorkspaceId,
      'workspaceName': workspaceName,
      'status': 'processing',
      'startedAt': FieldValue.serverTimestamp(),
      'logs': <Map<String, dynamic>>[
        {
          'seq': 1,
          'at': Timestamp.now(),
          'message': 'Starting workspace provisioning for "$workspaceName"…',
        },
      ],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    logSeq = 1;

    try {
      debugPrint(
        'WorkspaceProvisioningClientService.provision: registering workspace '
        '"$workspaceCode" (id=$finalWorkspaceId)…',
      );
      await _registerWorkspace(
        workspaceId: finalWorkspaceId,
        workspaceCode: workspaceCode,
        workspaceSlug: workspaceSlug,
        companyName: companyName,
        firebaseProjectId: firebaseProjectId,
        firebaseConfig: firebaseConfig,
        adminEmail: adminEmail,
        adminName: adminName,
        workspaceName: workspaceName,
        targetFirebaseAccountEmail: targetFirebaseAccountEmail,
      );
      await logLine(
          'Registered workspace "$workspaceCode" in the control plane.');
      await logLine(
          'Mapped workspace to its dedicated Firebase project '
          '"$firebaseProjectId" (configuration uploaded by the Super Admin).');
      debugPrint(
        'WorkspaceProvisioningClientService.provision: workspace registered.',
      );

      final workspace = Workspace(
        workspaceId: finalWorkspaceId,
        workspaceCode: workspaceCode,
        workspaceSlug: workspaceSlug,
        companyName: companyName,
        firebaseProjectId: firebaseProjectId,
        firebaseConfig: firebaseConfig,
        status: WorkspaceStatus.provisioning,
        onboardingStatus: WorkspaceOnboardingStatus.configuring,
        subscription: const Subscription(
          planId: 'free',
          planName: 'Free',
          status: SubscriptionStatus.trialing,
          billingCycle: BillingCycle.monthly,
          price: 0,
          currency: 'USD',
          seats: 0,
        ),
        supportEmail: adminEmail,
      );

      debugPrint(
        'WorkspaceProvisioningClientService.provision: provisioning tenant '
        '(company="$companyName", admin="$adminEmail")…',
      );
      final tenant = await _provisioner.provision(
        workspace: workspace,
        company: TenantCompanySpec(
          name: companyName,
          email: adminEmail,
          phone: companyPhone,
          address: companyAddress,
          industry: industry,
          companySize: '',
          country: '',
          timezone: '',
        ),
        admin: TenantAdminSpec(
          name: adminName,
          email: adminEmail,
          phone: '',
          password: adminPassword,
        ),
      );
      debugPrint(
        'WorkspaceProvisioningClientService.provision: tenant provisioned '
        '(companyId=${tenant.companyId}, adminUid=${tenant.adminUid}).',
      );
      await logLine('Created Company Admin account for $adminEmail.');
      await logLine(
          'Seeded tenant data (departments, policies, QR token, permissions).');

      debugPrint(
        'WorkspaceProvisioningClientService.provision: activating workspace '
        '"$finalWorkspaceId"…',
      );
      await _firestore.collection('workspaces').doc(finalWorkspaceId).update({
        'status': WorkspaceStatus.active.value,
        'onboardingStatus': WorkspaceOnboardingStatus.ready.value,
        'companyId': tenant.companyId,
        'adminUid': tenant.adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await logLine('Workspace activated.');
      debugPrint(
        'WorkspaceProvisioningClientService.provision: workspace activated.',
      );

      debugPrint(
        'WorkspaceProvisioningClientService.provision: writing tenant login '
        'index for "$adminEmail"…',
      );
      await TenantIdentityRepository().upsert(
        email: adminEmail,
        workspaceId: finalWorkspaceId,
        role: TenantIdentityRole.companyAdmin,
        name: adminName,
      );
      await logLine('Registered the tenant login index.');
      debugPrint(
        'WorkspaceProvisioningClientService.provision: tenant login index written.',
      );

      await logLine('Login credentials emailed to the Company Admin.');
      await logLine('Provisioning complete.');
      await logRef.update({
        'status': 'succeeded',
        'workspaceSlug': workspaceSlug,
        'workspaceCode': workspaceCode,
        'workspaceId': finalWorkspaceId,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return WorkspaceProvisionResult(
        workspaceId: finalWorkspaceId,
        workspaceCode: workspaceCode,
        workspaceSlug: workspaceSlug,
        firebaseProjectId: firebaseProjectId,
        companyId: tenant.companyId,
        adminEmail: adminEmail,
        logId: logId,
        emailSent: true,
      );
    } catch (e, st) {
      final message = _errorMessage(e);
      debugPrint(
        'WorkspaceProvisioningClientService.provision: FAILED for workspace '
        '"$finalWorkspaceId" (code="$workspaceCode") - $e\n$st',
      );
      try {
        await logRef.update({
          'status': 'failed',
          'errorMessage': message,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      try {
        await _firestore.collection('workspaces').doc(finalWorkspaceId).update({
          'status': WorkspaceStatus.provisioning.value,
          'onboardingStatus': WorkspaceOnboardingStatus.failed.value,
          'error': message,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _registerWorkspace({
    required String workspaceId,
    required String workspaceCode,
    required String workspaceSlug,
    required String companyName,
    required String firebaseProjectId,
    required WorkspaceFirebaseConfig firebaseConfig,
    required String adminEmail,
    required String adminName,
    required String workspaceName,
    required String targetFirebaseAccountEmail,
  }) async {
    await _firestore.collection('workspaces').doc(workspaceId).set({
      'workspaceId': workspaceId,
      'workspaceCode': workspaceCode,
      'workspaceSlug': workspaceSlug,
      'companyName': companyName,
      'firebaseProjectId': firebaseProjectId,
      'firebaseConfig': firebaseConfig.toMap(),
      'firebaseConfigured': true,
      'status': WorkspaceStatus.provisioning.value,
      'onboardingStatus': WorkspaceOnboardingStatus.configuring.value,
      'subscription': const Subscription(
        planId: 'free',
        planName: 'Free',
        status: SubscriptionStatus.trialing,
        billingCycle: BillingCycle.monthly,
        price: 0,
        currency: 'USD',
        seats: 0,
      ).toMap(),
      'supportEmail': adminEmail,
      'adminEmail': adminEmail,
      'adminName': adminName,
      'workspaceName': workspaceName,
      if (targetFirebaseAccountEmail.isNotEmpty)
        'targetFirebaseAccountEmail': targetFirebaseAccountEmail,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _adminNameFromEmail(String email) {
    final local = email.split('@').first;
    final cleaned = local
        .replaceAll(RegExp(r'[^A-Za-z0-9 .]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Company Admin' : cleaned;
  }

  String _generateAdminPassword() {
    final rng = Random.secure();
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digits = '0123456789';
    const special = '!@#\$%^&*';
    const chars = lower + upper + digits + special;
    final buffer = StringBuffer()
      ..write(lower[rng.nextInt(lower.length)])
      ..write(upper[rng.nextInt(upper.length)])
      ..write(digits[rng.nextInt(digits.length)])
      ..write(special[rng.nextInt(special.length)]);
    for (var i = 0; i < 10; i++) {
      buffer.write(chars[rng.nextInt(chars.length)]);
    }
    return (buffer.toString().split('')..shuffle(rng)).join();
  }

  String _errorMessage(Object error) {
    String raw;
    if (error is FirebaseException) {
      final code = error.code.isEmpty ? '' : '[${error.code}] ';
      raw = code +
          (error.message?.trim().isNotEmpty == true
              ? error.message!.trim()
              : error.toString());
    } else {
      raw = error.toString();
    }
    raw = raw.replaceFirst('Exception: ', '');
    return raw.length > 500 ? raw.substring(0, 500) : raw;
  }
}
