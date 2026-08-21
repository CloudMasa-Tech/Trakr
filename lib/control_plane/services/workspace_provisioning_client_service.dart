import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../control_plane_firebase.dart';
import '../models/subscription.dart';
import '../models/tenant_identity.dart';
import '../models/workspace.dart';
import '../models/workspace_firebase_config.dart';
import '../models/workspace_provision_request.dart';
import '../models/workspace_status.dart';
import '../repositories/tenant_identity_repository.dart';
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
  final String? emailError;

  const WorkspaceProvisionResult({
    required this.workspaceId,
    required this.workspaceCode,
    required this.workspaceSlug,
    required this.firebaseProjectId,
    required this.companyId,
    required this.adminEmail,
    this.logId = '',
    required this.emailSent,
    this.emailError,
  });
}


class _TenantProjectAllocation {
  final String projectId;
  final WorkspaceFirebaseConfig firebaseConfig;
  final String displayName;
  final String projectNumber;
  final bool projectIdChanged;
  final bool firebaseEnabled;
  final bool apisEnabled;
  final bool firestoreDbCreated;
  final bool authEnabled;
  final bool alreadyExisted;

  const _TenantProjectAllocation({
    required this.projectId,
    required this.firebaseConfig,
    required this.displayName,
    required this.projectNumber,
    required this.projectIdChanged,
    required this.firebaseEnabled,
    required this.apisEnabled,
    required this.firestoreDbCreated,
    required this.authEnabled,
    required this.alreadyExisted,
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

  /// Finds an incomplete workspace by its normalized code or admin email.
  /// Used by both the onboarding form and the provisioning service so every
  /// entry point converges on the same resume behavior.
  Future<Workspace?> findIncompleteWorkspace({
    required String workspaceName,
    required String adminEmail,
  }) async {
    final normalizedEmail = adminEmail.trim().toLowerCase();
    final normalizedCode = workspaceName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final candidates = await _registry.listWorkspaces();
    for (final workspace in candidates) {
      if (workspace.status != WorkspaceStatus.provisioning) continue;
      final codeMatches = normalizedCode.isNotEmpty &&
          workspace.workspaceCode.trim().toLowerCase() == normalizedCode;
      final emailMatches = normalizedEmail.isNotEmpty &&
          (workspace.adminEmail ?? "").trim().toLowerCase() == normalizedEmail;
      if (codeMatches || emailMatches) return workspace;
    }
    return null;
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
    if (workspaceName.isEmpty) throw Exception('Workspace name is required');
    if (companyName.isEmpty) throw Exception('Company name is required');
    if (companyPhone.isEmpty) throw Exception('Company phone is required');
    if (industry.isEmpty) throw Exception('Industry is required');
    if (!adminEmail.contains('@')) {
      throw Exception('A valid Company Admin email is required');
    }

    final adminName = _adminNameFromEmail(adminEmail);
    final adminPassword = _passwordsByEmail[adminEmail] ??=
        _generateAdminPassword();

    // Resolve an explicit retry target first; otherwise discover an incomplete
    // workspace by code OR admin email so onboarding and Continue provisioning
    // cannot diverge.
    final retryWorkspaceId = request.existingWorkspaceId?.trim();
    final discoveredWorkspace = retryWorkspaceId != null && retryWorkspaceId.isNotEmpty
        ? await _registry.resolveById(retryWorkspaceId)
        : await findIncompleteWorkspace(
            workspaceName: workspaceName,
            adminEmail: adminEmail,
          );
    String? retriedWorkspaceId;
    String? retriedWorkspaceCode;
    Workspace? retriedWorkspace;
    if (discoveredWorkspace != null &&
        discoveredWorkspace.status == WorkspaceStatus.provisioning) {
      retriedWorkspaceId = discoveredWorkspace.workspaceId;
      retriedWorkspaceCode = discoveredWorkspace.workspaceCode;
      retriedWorkspace = discoveredWorkspace;
      debugPrint(
        "WorkspaceProvisioningClientService: resuming incomplete workspace "
        "${discoveredWorkspace.workspaceId} by code/email match.",
      );
    }

    final existingMatches = await _registry.listByAdminEmail(adminEmail);
    for (final match in existingMatches) {
      final isRetryTarget = retriedWorkspaceId != null &&
          match.workspaceId == retriedWorkspaceId;
      if (isRetryTarget) {
        debugPrint(
          "WorkspaceProvisioningClientService: excluding current retry workspace "
          "${match.workspaceId} from admin-email uniqueness check.",
        );
        continue;
      }
      if (match.status == WorkspaceStatus.provisioning) {
        if (retriedWorkspaceId == null ||
            match.companyName.trim().toLowerCase() ==
                companyName.trim().toLowerCase()) {
          retriedWorkspaceId = match.workspaceId;
          retriedWorkspaceCode = match.workspaceCode;
          retriedWorkspace = match;
        }
      } else {
        throw Exception(
          "Admin email $adminEmail is already bound to an active workspace "
          "(${match.companyName} · ${match.workspaceCode}). Use a different "
          "admin email.",
        );
      }
    }

    final String workspaceCode;
    final String finalWorkspaceId;
    if (retriedWorkspaceId != null && retriedWorkspaceCode != null) {
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

    final storedProjectId = retriedWorkspace?.firebaseProjectId.trim() ?? '';
    final storedConfigProjectId = retriedWorkspace?.firebaseConfig.projectId.trim() ?? '';
    final retryProjectId = storedProjectId.isNotEmpty ? storedProjectId : storedConfigProjectId;
    final workspaceSlug = workspaceCode;
    final provisionalFirebaseProjectId = retryProjectId.isNotEmpty ? retryProjectId : workspaceCode;
    if (retryProjectId.isNotEmpty) {
      debugPrint(
        'WorkspaceProvisioningClientService.provision: retry will reuse existing Firebase project '
        '"$retryProjectId" for workspace "$finalWorkspaceId".',
      );
    }
    const emptyFirebaseConfig = WorkspaceFirebaseConfig(
      apiKey: '',
      appId: '',
      projectId: '',
      messagingSenderId: '',
      storageBucket: '',
      authDomain: '',
    );
    var firebaseProjectId = provisionalFirebaseProjectId;
    var firebaseConfig = retriedWorkspace?.firebaseConfig ?? emptyFirebaseConfig;
    final logId = (request.logId?.trim().isNotEmpty ?? false)
        ? request.logId!.trim()
        : generateLogId();
    final logRef = _firestore.collection('workspace_provision_logs').doc(logId);

    var logSeq = 0;
    var workspaceActivated = false;
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
        companyPhone: companyPhone,
        companyAddress: companyAddress,
        industry: industry,
      );
      await logLine(
          'Registered workspace "$workspaceCode" in the control plane.');
      await logLine(
          "Automatic Firebase project provisioning will allocate the workspace's dedicated project.");
      debugPrint(
        'WorkspaceProvisioningClientService.provision: workspace registered.',
      );

      debugPrint(
        'WorkspaceProvisioningClientService: allocating Firebase project '
        '"$firebaseProjectId" for workspace "$finalWorkspaceId".',
      );
      final allocation = await _allocateTenantProject(
        // On resume this is the stored project ID, never the workspace code.
        projectSeed: firebaseProjectId,
        workspaceCode: workspaceCode,
        workspaceId: finalWorkspaceId,
        companyName: companyName,
      );
      firebaseProjectId = allocation.projectId;
      firebaseConfig = allocation.firebaseConfig;
      await _registry.update(finalWorkspaceId, {
        'firebaseProjectId': firebaseProjectId,
        'firebaseConfig': firebaseConfig.toMap(),
        'firebaseConfigured': true,
        'gcpProjectDisplayName': allocation.displayName,
        'gcpProjectVerified': true,
        'gcpProjectNumber': allocation.projectNumber,
        'firebaseEnabled': allocation.firebaseEnabled,
        'apisEnabled': allocation.apisEnabled,
        'firestoreDbCreated': allocation.firestoreDbCreated,
        'authEnabled': allocation.authEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final workspace = Workspace(
        workspaceId: finalWorkspaceId,
        workspaceCode: workspaceCode,
        workspaceSlug: workspaceSlug,
        companyName: companyName,
        companyPhone: companyPhone,
        companyAddress: companyAddress,
        industry: industry,
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
        '(companyId=${tenant.companyId}, adminUid=${tenant.adminUid}, '
        'firebaseProjectId=${tenant.firebaseProjectId}).',
      );
      firebaseProjectId = tenant.firebaseProjectId;
      firebaseConfig = tenant.firebaseConfig;
      await _registry.updateFirebaseConfig(finalWorkspaceId, firebaseConfig);
      await logLine('Created Company Admin account for $adminEmail.');
      await logLine(
          'Seeded tenant data (departments, policies, QR token, permissions).');

      debugPrint(
        'WorkspaceProvisioningClientService.provision: activating workspace '
        '"$finalWorkspaceId"…',
      );
      await _registry.update(finalWorkspaceId, {
        'status': WorkspaceStatus.active.value,
        'onboardingStatus': WorkspaceOnboardingStatus.ready.value,
        'companyId': tenant.companyId,
        'adminUid': tenant.adminUid,
        'firebaseProjectId': firebaseProjectId,
        'firebaseConfig': firebaseConfig.toMap(),
        'adminEmailSent': tenant.adminEmailSent,
        if (tenant.adminEmailError != null) 'adminEmailError': tenant.adminEmailError,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      workspaceActivated = true;
      await logLine(tenant.adminEmailSent
          ? 'Admin invite email sent successfully.'
          : 'Admin invite email failed; workspace remains active. Manual resend is required.');
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

      final completionMessage = "Workspace $workspaceName provisioning complete: project=$firebaseProjectId, adminEmailSent=${tenant.adminEmailSent}";
      debugPrint(completionMessage);
      await logLine(completionMessage);
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
        emailSent: tenant.adminEmailSent,
        emailError: tenant.adminEmailError,
      );
    } catch (e, st) {
      final message = _errorMessage(e);
      debugPrint(
        'WorkspaceProvisioningClientService.provision: FAILED for workspace '
        '"$finalWorkspaceId" (code="$workspaceCode") - $e\n$st',
      );
      try {
        await logRef.update({
          'status': workspaceActivated ? 'succeeded' : 'failed',
          'errorMessage': message,
          if (workspaceActivated) 'warningMessage': message,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      try {
        await _registry.update(finalWorkspaceId, {
          'status': workspaceActivated
              ? WorkspaceStatus.active.value
              : WorkspaceStatus.provisioning.value,
          'onboardingStatus': workspaceActivated
              ? WorkspaceOnboardingStatus.ready.value
              : WorkspaceOnboardingStatus.failed.value,
          'error': message,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      rethrow;
    }
  }


  Future<_TenantProjectAllocation> _allocateTenantProject({
    required String projectSeed,
    required String workspaceCode,
    required String workspaceId,
    required String companyName,
  }) async {
    final functions = FirebaseFunctions.instance;
    final result = await functions
        .httpsCallable('createTenantProject', options: HttpsCallableOptions(timeout: const Duration(seconds: 540)))
        .call({
      'projectId': projectSeed,
      'workspaceCode': workspaceCode,
      'workspaceId': workspaceId,
      'companyName': companyName,
    }).timeout(const Duration(seconds: 540));

    final data = result.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception('Cloud Function returned error: ${data['error'] ?? 'unknown error'}');
    }

    final firebaseConfig = WorkspaceFirebaseConfig.fromMap(
      Map<String, dynamic>.from((data['firebaseConfig'] as Map?) ?? const <String, dynamic>{}),
    );

    return _TenantProjectAllocation(
      projectId: (data['projectId'] as String?) ?? projectSeed,
      firebaseConfig: firebaseConfig,
      displayName: (data['displayName'] as String?) ?? companyName,
      projectNumber: (data['projectNumber'] as String?) ?? '',
      projectIdChanged: data['projectIdChanged'] as bool? ?? false,
      firebaseEnabled: data['firebaseEnabled'] as bool? ?? false,
      apisEnabled: data['apisEnabled'] as bool? ?? false,
      firestoreDbCreated: data['firestoreDbCreated'] as bool? ?? false,
      authEnabled: data['authEnabled'] as bool? ?? false,
      alreadyExisted: data['alreadyExisted'] as bool? ?? false,
    );
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
    required String companyPhone,
    String? companyAddress,
    required String industry,
  }) async {
    final data = <String, dynamic>{
      'workspaceId': workspaceId,
      'workspaceCode': workspaceCode,
      'workspaceSlug': workspaceSlug,
      'companyName': companyName,
      'firebaseProjectId': firebaseProjectId,
      'companyPhone': companyPhone,
      'companyAddress': companyAddress,
      'industry': industry,
      'firebaseConfig': firebaseConfig.toMap(),
      'firebaseConfigured': false,
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
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _registry.createDocument(workspaceId, data);
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
