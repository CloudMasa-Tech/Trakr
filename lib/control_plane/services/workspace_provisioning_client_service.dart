import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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

  FirebaseFirestore get _firestore => ControlPlaneFirebase.instance.firestore;

  /// Generates a unique, URL-safe id for a provisioning audit-log doc.
  static String generateLogId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'provision-$millis-$rand';
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
        request.targetFirebaseAccountEmail.trim().toLowerCase();

    if (workspaceName.isEmpty) throw Exception('Workspace name is required');
    if (companyName.isEmpty) throw Exception('Company name is required');
    if (companyPhone.isEmpty) throw Exception('Company phone is required');
    if (industry.isEmpty) throw Exception('Industry is required');
    if (!adminEmail.contains('@')) {
      throw Exception('A valid Company Admin email is required');
    }
    if (!targetFirebaseAccountEmail.contains('@')) {
      throw Exception('A valid Firebase account email is required');
    }

    final adminName = _adminNameFromEmail(adminEmail);
    final adminPassword = _generateAdminPassword();

    final workspaceCode =
        await _registry.generateUniqueWorkspaceCode(workspaceName);
    final workspaceSlug = workspaceCode;
    final defaultApp = Firebase.app();
    final firebaseProjectId = defaultApp.options.projectId;
    final firebaseConfig =
        WorkspaceFirebaseConfig.fromFirebaseOptions(defaultApp.options);

    final workspaceId = _firestore.collection('workspaces').doc().id;
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
      'workspaceId': workspaceId,
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
        '"$workspaceCode" (id=$workspaceId)…',
      );
      await _registerWorkspace(
        workspaceId: workspaceId,
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
      await logLine('Using the shared Firebase project "$firebaseProjectId".');
      debugPrint(
        'WorkspaceProvisioningClientService.provision: workspace registered.',
      );

      final workspace = Workspace(
        workspaceId: workspaceId,
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
        '"$workspaceId"…',
      );
      await _firestore.collection('workspaces').doc(workspaceId).update({
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
        workspaceId: workspaceId,
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
        'workspaceId': workspaceId,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return WorkspaceProvisionResult(
        workspaceId: workspaceId,
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
        '"$workspaceId" (code="$workspaceCode") - $e\n$st',
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
        await _firestore.collection('workspaces').doc(workspaceId).update({
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
