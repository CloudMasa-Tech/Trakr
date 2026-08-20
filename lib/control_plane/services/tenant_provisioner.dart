import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../firebase/firebase_context.dart';
import '../../firebase/firebase_manager.dart';
import '../../services/access_control_service.dart';
import '../../services/company_logo_service.dart';
import '../../services/email_service.dart';
import '../models/workspace.dart';
import '../models/workspace_firebase_config.dart';
import 'firebase_config_validator.dart';
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

      // Mark workspace as configuring so the UI can show progress
      await _updateWorkspaceOnboardingStatus(workspaceId, 'configuring');
      final tenantProjectId = workspace.firebaseConfig.projectId;

      // ── Tenant isolation guard ────────────────────────────────────────
      // Every workspace must live in its OWN dedicated Firebase project. The
      // TRAKR Master (platform) project can never be used as a tenant project,
      // so tenant bootstrap writes can never reach control-plane data.
      if (tenantProjectId.trim().isEmpty) {
        throw StateError(
          'The workspace has no Firebase project mapped. Upload the '
          'client-side configuration of the workspace\'s own dedicated '
          'Firebase project before provisioning.',
        );
      }
      if (tenantProjectId == _firebaseManager.defaultApp.options.projectId) {
        throw StateError(
          'The TRAKR Master platform project cannot be provisioned as a '
          'workspace. Workspaces require their own dedicated Firebase '
          'project — create one in the Firebase Console and upload ITS '
          'client-side configuration.',
        );
      }

      // Verify the workspace firebaseConfig carries valid tenant-project
      // credentials.  If the stored config references the master project's
      // API key or is otherwise incomplete, the tenant app initialization
      // will fail with api-key-not-valid when createUserWithEmailAndPassword
      // is called.  Fail fast here with a clear message rather than letting
      // the auth call produce a cryptic error later.
      final config = workspace.firebaseConfig;
      if (config.apiKey.isEmpty ||
          config.projectId.isEmpty ||
          config.apiKey == _firebaseManager.defaultApp.options.apiKey) {
        throw StateError(
          'The workspace\'s Firebase configuration is incomplete or '
          'references the master project\'s API key.  Upload the client‑'
          'side configuration for the workspace\'s own dedicated Firebase '
          'project (API key, projectId, appId, messagingSenderId, '
          'authDomain, storageBucket all required).',
        );
      }


      // Verify the workspace firebaseConfig has valid credentials for the
      // tenant project. If the stored config references the master project
      // API key/project, provisioning will fail with api-key-not-valid.
      final defaultProjectId = _firebaseManager.defaultApp.options.projectId;
      if (tenantProjectId == defaultProjectId) {
        // Already caught above, but defensive check
        throw StateError(
          'The workspace Firebase project ID matches the master project. '
          'Workspaces must use a dedicated Firebase project.',
        );
      }

      // ── Create tenant project if it doesn't exist ───────────────────────
      // The project is created under folder 818058604638 (tenant-projects)
      // which automatically grants the required IAM roles via folder-level inheritance.
      step = 'create tenant project if needed';
      debugPrint(
        'TenantProvisioner.provision: step "$step" starting…',
      );
      final gcpResult = await _createTenantProjectIfNeeded(
        projectId: tenantProjectId,
        companyName: workspace.companyName,
        // billingAccount can be passed if needed, e.g., 'billingAccounts/XXXXXX'
      );
      debugPrint('TenantProvisioner.provision: step "$step" succeeded, GCP display name: ${gcpResult.displayName}, projectNumber: ${gcpResult.projectNumber}');
      
      // If the project ID was regenerated due to collision, update the workspace
      // config so subsequent steps use the correct project ID.
      String actualProjectId = tenantProjectId;
      if (gcpResult.projectIdChanged) {
        debugPrint(
          'TenantProvisioner.provision: project ID changed from '
          '"$tenantProjectId" to "${gcpResult.finalProjectId}" due to collision. '
          'Updating workspace config.',
        );
        actualProjectId = gcpResult.finalProjectId;
        await _updateWorkspaceProjectId(workspace.workspaceId, actualProjectId);
        // Also update the local config object so subsequent steps use the new ID
        final updatedConfig = WorkspaceFirebaseConfig(
          apiKey: workspace.firebaseConfig.apiKey,
          appId: workspace.firebaseConfig.appId,
          projectId: actualProjectId,
          messagingSenderId: workspace.firebaseConfig.messagingSenderId,
          storageBucket: workspace.firebaseConfig.storageBucket,
          authDomain: workspace.firebaseConfig.authDomain,
          measurementId: workspace.firebaseConfig.measurementId,
          iosBundleId: workspace.firebaseConfig.iosBundleId,
          iosClientId: workspace.firebaseConfig.iosClientId,
          androidClientId: workspace.firebaseConfig.androidClientId,
          configMethod: workspace.firebaseConfig.configMethod,
          npmPackage: workspace.firebaseConfig.npmPackage,
          sdkVersion: workspace.firebaseConfig.sdkVersion,
          cdnUrl: workspace.firebaseConfig.cdnUrl,
        );
        workspace = workspace.copyWith(
          firebaseConfig: updatedConfig,
          firebaseProjectId: actualProjectId,
        );
      }
      
      // Store the derived GCP display name in the workspace registry
      await _updateWorkspaceGcpDisplayName(workspace.workspaceId, gcpResult.displayName);

      // Persist granular provisioning flags from the CF response so the UI
      // can show exactly which steps have completed.
      await _updateWorkspaceProvisioningFlags(
        workspace.workspaceId,
        firebaseEnabled: gcpResult.firebaseEnabled,
        apisEnabled: gcpResult.apisEnabled,
        firestoreDbCreated: gcpResult.firestoreDbCreated,
        authEnabled: gcpResult.authEnabled,
      );

      // ── Live connectivity validation ────────────────────────────────
      // Proves the apiKey + project are valid and reachable before investing
      // effort into full provisioning. Any auth response (even "no account for
      // this email") proves the project is reachable; only genuinely broken
      // configuration (bad apiKey, unknown project, auth disabled, network
      // failure) is reported as a failure. The temp app is always deleted.
      try {
        final connectionResult =
            await FirebaseConfigValidator.testConnection(config);
        if (!connectionResult.success) {
          throw StateError(
            'Could not validate the workspace Firebase project before '
            'creating the admin account: ${connectionResult.message}',
          );
        }
        debugPrint(
          'TenantProvisioner.provision: step "validate tenant project '
          'connection" succeeded (${connectionResult.message}).',
        );
      } catch (e) {
        throw StateError(
          'Failed to validate the workspace Firebase project configuration: '
          '$e',
        );
      }

      // Mark the workspace as GCP project verified with the project number
      // ONLY after connectivity validation confirms the project is live and
      // reachable. Setting this flag too early (e.g. right after GCP project
      // creation) can leave the workspace stuck in a "verified" state when
      // Firebase enablement or API activation actually failed.
      await _updateWorkspaceGcpVerified(
        workspace.workspaceId,
        gcpResult.projectNumber,
      );

      try {
        // 1. Initialize the tenant app. This must happen BEFORE
        // markProvisioning() so a stale app bound to a different config can be
        // disposed and re-created — FirebaseManager refuses to dispose an app
        // while provisioning is marked in-flight.
        final tenantApp = await _firebaseManager.initializeTenantApp(
          workspaceId: workspace.workspaceId,
          options: workspace.firebaseConfig.toFirebaseOptions(),
        );
        _firebaseManager.markProvisioning(workspaceId);
        debugPrint(
          'TenantProvisioner.provision: step "$step" succeeded '
          '(app=${tenantApp.name}).',
        );
        final context = FirebaseContext.fromApp(tenantApp);

        final state = _ActiveProvisioning(
          workspaceId: workspace.workspaceId,
          context: context,
        );
        _active[workspace.workspaceId] = state;

        // 2. The tenant app must be bound to the workspace's stored config.
        //    The admin account is created through THIS app's auth instance, so
        //    a stale/mismatched app would silently write to the wrong project.
        final appOptions = tenantApp.options;
        if (appOptions.apiKey != config.apiKey ||
            appOptions.projectId != config.projectId ||
            appOptions.appId != config.appId) {
          throw StateError(
            'The tenant Firebase app for this workspace is bound to a '
            'different Firebase project than the workspace\'s stored '
            'configuration (apiKey/projectId/appId do not match). Re-upload '
            'the workspace\'s own client-side configuration and retry.',
          );
        }
        final tenantAuth = FirebaseAuth.instanceFor(app: context.app);
        await _verifyTenantCredentials(auth: tenantAuth, config: config);
        debugPrint(
          'TenantProvisioner.provision: step "verify tenant credentials" '
          'succeeded (tenant project=${appOptions.projectId}).',
        );

        // Deploy Firestore rules and indexes to the tenant project automatically
        step = 'deploy tenant Firestore rules and indexes';
        debugPrint('TenantProvisioner.provision: step "$step" starting…');
        await _deployTenantRulesAndIndexes(
          tenantProjectId: appOptions.projectId,
        );
        await _updateWorkspaceRulesDeployed(workspace.workspaceId);
        debugPrint('TenantProvisioner.provision: step "$step" succeeded.');

        step = 'allocate company id';
        debugPrint('TenantProvisioner.provision: step "$step" starting…');
        state.companyId = workspace.workspaceId;
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
        final normalizedEmail = admin.email.trim().toLowerCase();
        final normalizedPhone = admin.phone.trim();
        final companyId = state.companyId!;

        // 1. Create (or recover) the auth user in the tenant project.
        //
        // The Auth client SDK has no lookup-by-email API (that is Admin SDK
        // only), so an already-existing account can only be detected through the
        // `email-already-in-use` error thrown by createUserWithEmailAndPassword.
        // On a retry of a partially-failed run the account exists with the SAME
        // password (cached in-session by the client service), so signing back in
        // recovers the uid and lets provisioning resume idempotently.
        //
        // IMPORTANT: This must be done BEFORE any Firestore writes because the
        // user's uid is needed as the document key, and the user document must
        // exist with companyId for inCompany() and sameCompanyOnCreate() rules to work.
        User adminUser;
        var authUserCreatedThisRun = false;
        try {
          final credential = await tenantAuth.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: admin.password,
          );
          adminUser = credential.user!;
          authUserCreatedThisRun = true;
          debugPrint(
            'TenantProvisioner.provision: created new auth user, uid: '
            '${adminUser.uid}.',
          );
        } on FirebaseAuthException catch (e) {
          if (e.code != 'email-already-in-use') rethrow;
          // A previous run created the account. Recover it by signing back in
          // with the same password (the operator's retry keeps the original
          // password in-session). The session is then treated exactly like a
          // freshly-created account for the Firestore writes below.
          debugPrint(
            'TenantProvisioner.provision: account for "$normalizedEmail" '
            'already exists — attempting sign-in recovery.',
          );
          try {
            final credential = await tenantAuth.signInWithEmailAndPassword(
              email: normalizedEmail,
              password: admin.password,
            );
            adminUser = credential.user!;
            debugPrint(
              'TenantProvisioner.provision: recovered existing auth user, '
              'uid: ${adminUser.uid}.',
            );
          } on FirebaseAuthException catch (recoveryError) {
            // Handle "client already been terminated" error - this can happen
            // when the Firebase project state is inconsistent after a workspace
            // deletion/recreation. Treat as a retryable condition by rethrowing
            // with a descriptive message so the operator can retry the provisioning.
            if (recoveryError.code == 'wrong-password' ||
                recoveryError.code == 'invalid-credential' ||
                recoveryError.code == 'invalid-login-credentials' ||
                recoveryError.code == 'user-disabled' ||
                recoveryError.code == 'too-many-requests' ||
                recoveryError.message?.contains('terminated') == true) {
              // Re-throw with a message that indicates this is a transient state
              // issue that can be resolved by retrying the provisioning operation.
              throw FirebaseAuthException(
                code: 'provisioning-transient-error',
                message:
                    'The Firebase Auth client appears to be in an inconsistent state '
                    '(likely due to a recent workspace deletion/recreation). '
                    'Please retry the provisioning operation. If the error persists, '
                    'contact support with the workspace ID and this error code: '
                    'provisioning-transient-error.',
              );
            }
            // For all other auth errors, re-throw the original error
            rethrow;
          }
        }
        final adminUid = adminUser.uid;
        // Force a token refresh and give Firestore time to pick up the new auth
        // state, so the writes below carry a valid token.
        await adminUser.updateDisplayName(admin.name.trim());
        await adminUser.getIdToken(true);
        await Future.delayed(const Duration(milliseconds: 1000));
        state.authUserCreatedThisRun = authUserCreatedThisRun;
        state.adminUid = adminUid;

        // 2. Initialize Firestore documents in the exact order required to satisfy
        // the authorization rules from the client.
        final firestore = context.firestore;
        final now = FieldValue.serverTimestamp();
        final permissionIds = <String>[
          for (final permission in AccessControlService.defaultPermissions)
            permission.id,
        ];

        // Step 2a: Seed `app_config/admin_access` FIRST. The Firestore rules use
        // this doc as the bootstrap trust anchor (isSeededBootstrapAdmin): a
        // self-created `users/{uid}` doc may only carry RBAC privilege fields when
        // the caller's email is the recorded `primaryAdminEmail`. The rule allows
        // the very first create only for the signed-in user whose email matches,
        // and afterwards only the recorded primary admin (or the platform Super
        // Admin) may update it — so a random signed-in user can never claim it.
        final adminAccessRef =
            firestore.doc('app_config/admin_access');
        state.adminAccessDocPreExisted = await _docExists(adminAccessRef);
        await _guardPermission(
          () => adminAccessRef.set({
            'primaryAdminEmail': normalizedEmail,
            'adminEmails': <String>[normalizedEmail],
            'updatedAt': now,
          }),
          'app_config/admin_access',
        );
        // Mark that this run created/overwrote the admin_access doc, so that
        // rollback on failure immediately deletes it (rather than relying on a
        // later session with a different email to clean it up).
        state.adminAccessDocPreExisted = false;

        // Probe pre-existence BEFORE writing so a rollback is conservative: it
        // only ever removes data this run created, never data left behind by an
        // earlier run that could not complete its own teardown.
        final userRef = firestore.collection('users').doc(adminUid);
        final companyRef = firestore.collection('companies').doc(companyId);
        final adminRef =
            firestore.collection('admins').doc(workspace.workspaceId);
        state.userDocPreExisted = await _docExists(userRef);
        state.companyDocPreExisted = await _docExists(companyRef);
        state.adminDocPreExisted = await _docExists(adminRef);
        debugPrint(
          'TenantProvisioner.provision: pre-existence probe '
          '(adminAccess=${state.adminAccessDocPreExisted}, '
          'user=${state.userDocPreExisted}, '
          'company=${state.companyDocPreExisted}, '
          'admin=${state.adminDocPreExisted}).',
        );

        // Step 2b: Write the `users/{uid}` document.
        // Rule `request.auth.uid == userId` + isSeededBootstrapAdmin() allows this
        // write with privilege fields.
        // This establishes the `userCompanyId()` lookup used by other rules.
        // Company document ID is workspaceId (deterministic), so adminId references workspaceId.
        await _guardPermission(
          () => userRef.set({
            'name': admin.name.trim(),
            'email': normalizedEmail,
            'phone': normalizedPhone,
            'role': 'admin',
            'adminId': workspace.workspaceId,
            'companyId': companyId,
            'roleId': 'company_admin',
            'roleName': 'Company Admin',
            'roleLevel': 80,
            // Written before the seed batch so the `roles/*` seeding passes the
            // `hasAnyPermission(..., ['roles.manage'])` rule: batched writes do
            // not see each other during rules evaluation, so the admin's direct
            // permissionIds must already exist when the roles are created.
            'permissionIds': permissionIds,
            'hasRegistered': true,
            'createdAt': now,
            'updatedAt': now,
          }),
          'users/$adminUid',
        );

        // Step 2c: Write the `companies/{companyId}` document.
        // Rule `inCompany(companyId)` allows this because `userCompanyId()` now resolves.
        // companyId is workspaceId (deterministic), so this doc is at companies/{workspaceId}.
        final domain = normalizedEmail.contains('@')
            ? normalizedEmail.split('@').last
            : null;
        await _guardPermission(
          () => companyRef.set({
            'name': company.name.trim(),
            'domain': domain,
            'email': company.email ?? '',
            'supportEmail': company.email ?? '',
            'phone': company.phone ?? '',
            'address': company.address?.trim(),
            'logoUrl': logoUrl,
            'companyLogoUrl': logoUrl,
            'website': company.website?.trim(),
            'industry': company.industry,
            'companySize': company.companySize,
            'country': company.country,
            'timezone': company.timezone,
            'primaryColorHex': '0F766E',
            'isActive': true,
            'createdAt': now,
            'updatedAt': now,
            'lastActiveAt': now,
          }),
          'companies/$companyId',
        );

        // Step 2d: Write the `admins/{workspaceId}` document.
        // Rule `sameCompanyOnCreate()` allows this because the resource `companyId` matches workspaceId.
        await _guardPermission(
          () => adminRef.set({
            'name': admin.name.trim(),
            'email': normalizedEmail,
            'phone': normalizedPhone,
            'role': 'admin',
            'status': 'active',
            'isActive': true,
            'authUid': adminUid,
            'companyId': companyId,
            'roleId': 'company_admin',
            'roleName': 'Company Admin',
            'roleLevel': 80,
            'permissionIds': permissionIds,
            'hasRegistered': true,
            'createdAt': now,
            'updatedAt': now,
          }),
          'admins/${workspace.workspaceId}',
        );

        // Step 2e: Verify the rules actually allow the tenant admin to READ the
        // workspace back. A ruleset that denies reads would make the provisioned
        // workspace unusable, so we fail here with actionable guidance instead of
        // reporting a false success.
        step = 'verify tenant Firestore rules';
        debugPrint('TenantProvisioner.provision: step "$step" starting…');
        await _guardPermission(
          () async {
            final check = await firestore
                .collection('companies')
                .doc(companyId)
                .get();
            if (!check.exists) {
              throw StateError(
                'The tenant Firestore accepted writes but the company document '
                'could not be read back. Re-run provisioning after verifying the '
                'TRAKR Firestore rules are deployed.',
              );
            }
          },
          'read-back of companies/$companyId',
        );
        debugPrint('TenantProvisioner.provision: step "$step" succeeded.');

        debugPrint(
          'TenantProvisioner.provision: step "onboard company and admin" '
          'succeeded (companyId=$companyId, adminUid=$adminUid).',
        );

        step = 'send credentials email';
        try {
          await EmailService.sendAccountCredentials(
            recipientEmail: normalizedEmail,
            password: admin.password,
            roleLabel: 'Company Admin',
            recipientName: admin.name,
          );
          debugPrint(
            'TenantProvisioner.provision: step "$step" succeeded '
            'for "$normalizedEmail".',
          );
        } catch (e, st) {
          debugPrint(
            'TenantProvisioner.provision: step "$step" failed (best-effort) '
            '- $e\n$st',
          );
        }

        state.adminUid = adminUid;

        step = 'seed tenant defaults';
        debugPrint('TenantProvisioner.provision: step "$step" starting…');
        final seeder = TenantSeeder(context: context);
        state.seeds = await seeder.seed(
          companyId: companyId,
          adminUid: adminUid,
          adminEmail: normalizedEmail,
          companyName: company.name,
          supportEmail: company.email,
        );
        debugPrint('TenantProvisioner.provision: step "$step" succeeded.');

_active.remove(workspace.workspaceId);
        _firebaseManager.clearProvisioning(workspaceId);
        await _updateWorkspaceOnboardingStatus(workspaceId, 'ready');
        return TenantProvisioningResult(
          companyId: companyId,
          adminUid: adminUid,
          adminEmail: normalizedEmail,
        );
      } catch (e, st) {
        debugPrint(
          'TenantProvisioner.provision: FAILED at step "$step" '
          'for workspace "$workspaceId" - $e\n$st',
        );
        _firebaseManager.clearProvisioning(workspaceId);
        await _updateWorkspaceOnboardingStatus(
          workspaceId,
          'failed',
          failedStep: step,
          lastError: e.toString(),
        );
        await _teardownTenant(workspaceId);
        rethrow;
      }
    } catch (e, st) {
      debugPrint(
        'TenantProvisioner.provision: FAILED at step "$step" '
        'for workspace "$workspaceId" - $e\n$st',
      );
      rethrow;
    }
  }

  @override
  Future<void> rollback(Workspace workspace) async {
    await _teardownTenant(workspace.workspaceId);
  }

  /// Tears down what THIS provisioning run created inside the tenant project,
  /// then the tenant [FirebaseApp] itself. Every step is best-effort and
  /// idempotent.
  ///
  /// The teardown is deliberately **conservative**: documents that already
  /// existed before this run started (e.g. left behind by a crashed earlier
  /// run that could not finish its own teardown) are never deleted, and the
  /// auth account is only removed when THIS run created it. This guarantees a
  /// retry can never destroy data it did not create.
  Future<void> _teardownTenant(String workspaceId) async {
    final state = _active.remove(workspaceId);
    if (state != null) {
      if (state.seeds != null) {
        try {
          await TenantSeeder(context: state.context).rollback(state.seeds!);
        } catch (_) {}
      }
      // app_config/admin_access is the bootstrap trust anchor; only remove it
      // when THIS run created it (never a pre-existing one).
      if (!state.adminAccessDocPreExisted) {
        try {
          await state.context.firestore
              .doc('app_config/admin_access')
              .delete();
        } catch (_) {}
      }
      final adminUid = state.adminUid;
      if (adminUid != null) {
        if (!state.adminDocPreExisted) {
          try {
            await _deleteAdminDocs(state.context, adminUid);
          } catch (_) {}
        }
        if (!state.userDocPreExisted) {
          try {
            await state.context.firestore
                .collection('users')
                .doc(adminUid)
                .delete();
          } catch (_) {}
        }
      }
      final companyId = state.companyId;
      if (companyId != null && !state.companyDocPreExisted) {
        // Deleting the company document also removes its logo data URL — there
        // is no separate Cloud Storage object to purge.
        try {
          await state.context.firestore
              .collection('companies')
              .doc(companyId)
              .delete();
        } catch (_) {}
      }
      // Remove the auth account ONLY when this run created it. A recovered
      // (pre-existing) account stays so a retry can sign back in with the
      // same password and resume.
      if (state.authUserCreatedThisRun) {
        try {
          final currentUser =
              FirebaseAuth.instanceFor(app: state.context.app).currentUser;
          if (currentUser != null && currentUser.uid == adminUid) {
            await currentUser.delete();
          }
        } catch (_) {
          // Auth-user deletion can be blocked by rules/providers; the tenant
          // app disposal below still frees the session.
        }
      }
      // Clear any stale cached app state for this workspace so that a
      // subsequent provisioning attempt re-initializes from a clean slate
      // instead of reusing a terminated app (which triggers
      // "client already been terminated" / 400 Bad Request errors).
      try {
        await _firebaseManager.disposeTenant(workspaceId);
      } catch (_) {
        // disposal failure is best-effort; continue with registry rollback.
      }
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

  /// Whether [ref] already exists. Reads can fail under locked/default rules;
  /// an unknown state is treated as "not pre-existing" so rollback stays
  /// best-effort and never risks destroying data it could not verify.
  Future<bool> _docExists(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return (await ref.get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// Proves the initialized tenant app's auth is bound to a valid, reachable
  /// Firebase project BEFORE any admin account is created.
  ///
  /// Reuses the EXACT auth instance that will create the admin account, so a
  /// failure here means `createUserWithEmailAndPassword` would fail with the
  /// same cryptic auth error (`api-key-not-valid` and friends). Failing fast
  /// here surfaces an actionable message instead.
  ///
  /// The probe uses deliberately wrong credentials: every auth response —
  /// including "no such account" / "wrong password" — proves the apiKey +
  /// project responded, so the config is valid for this project. Only genuinely
  /// broken configuration (bad/restricted apiKey, unknown project, auth
  /// disabled, network failure) is reported as a failure.
  Future<void> _verifyTenantCredentials({
    required FirebaseAuth auth,
    required WorkspaceFirebaseConfig config,
  }) async {
    try {
      await auth
          .signInWithEmailAndPassword(
            email: 'provisioning-check@trakr.invalid',
            password: 'not-the-real-password',
          )
          .timeout(const Duration(seconds: 15));
    } on FirebaseAuthException catch (e) {
      final result =
          FirebaseConfigValidator.classifyAuthFailure(e, config.projectId);
      if (!result.success) {
        throw StateError(
          'Could not verify the workspace Firebase project before creating '
          'the admin account: ${result.message}',
        );
      }
      // Expected: the probe credentials are rejected. The round-trip reaching
      // the project means the configuration is valid for this project.
    } on TimeoutException {
      throw StateError(
        'Timed out while verifying the workspace Firebase project. Check the '
        'network connection and retry.',
      );
    }
  }
  /// Runs [operation] and converts a `permission-denied` rejection into a
  /// clear, actionable error explaining that the tenant project's Firestore is
  /// still in locked/default mode and the TRAKR rules must be deployed.
  Future<T> _guardPermission<T>(Future<T> Function() operation,
      String what) async {
    try {
      return await operation();
    } on FirebaseException catch (e) {
      final message = (e.message ?? e.code).toLowerCase();
      if (e.code == 'permission-denied' ||
          message.contains('permission-denied') ||
          message.contains('permission denied')) {
        throw StateError(
          'The tenant project rejected the "$what" operation with '
          'permission-denied. This usually means the project\'s Cloud '
          'Firestore is still in its default/locked mode. Deploy the TRAKR '
          'Firestore rules to the project (firebase deploy --only '
          'firestore:rules) and retry — provisioning resumes safely from where '
          'it stopped.',
        );
      }
      rethrow;
    }
  }

  /// Deploys the TRAKR Firestore rules and indexes to the tenant project
  /// by calling the Vercel backend API, which uses the Firebase Admin SDK
  /// with proper OAuth2 credentials to deploy via the Security Rules REST API.
  /// Deploys the TRAKR Firestore rules and indexes to the tenant project
  /// by calling the Cloud Function `deployTenantRules` via the Firebase Functions SDK.
  /// This is called automatically during provisioning after the tenant project
  /// is verified but before any admin accounts or data are created.
  Future<void> _deployTenantRulesAndIndexes({
    required String tenantProjectId,
  }) async {
    debugPrint(
      'TenantProvisioner._deployTenantRulesAndIndexes: deploying to $tenantProjectId',
    );

    try {
      debugPrint('Calling Cloud Function deployTenantRules for $tenantProjectId');

      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('deployTenantRules').call({
        'tenantProjectId': tenantProjectId,
      }).timeout(const Duration(seconds: 300));

      final data = result.data as Map<String, dynamic>;
      debugPrint('Cloud Function deployTenantRules succeeded: $data');

      // Verify the response indicates success
      if (data['success'] != true) {
        throw StateError('Cloud Function returned error: ${data['error'] ?? 'unknown error'}');
      }

      debugPrint('TenantProvisioner._deployTenantRulesAndIndexes: completed successfully');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud Function deployTenantRules failed: ${e.code} - ${e.message}');
      throw StateError(
        'Failed to deploy tenant rules via Cloud Function: ${e.message}. '
        'Ensure the Cloud Functions are deployed and the master service account has '
        'Firebase Rules Admin and Datastore Index Admin roles on the tenant project. '
        'Details: ${e.details}',
      );
    } catch (e) {
      debugPrint('TenantProvisioner._deployTenantRulesAndIndexes: error - $e');
      rethrow;
    }
  }

  /// Creates a new GCP/Firebase project under the configured folder (818058604638)
  /// by calling the Cloud Function `createTenantProject` via the Firebase Functions SDK.
  /// This is called during provisioning if the project doesn't exist yet.
  /// The project will be created under folder 818058604638 (tenant-projects),
  // and will automatically inherit the required IAM roles via folder-level inheritance.
  /// Returns a tuple of (displayName, projectNumber, finalProjectId, projectIdChanged)
  Future<({String displayName, String projectNumber, String finalProjectId, bool projectIdChanged, bool firebaseEnabled, bool apisEnabled, bool firestoreDbCreated, bool authEnabled, bool alreadyExisted})> _createTenantProjectIfNeeded({
    required String projectId,
    required String companyName,
    String? billingAccount,
  }) async {
    debugPrint(
      'TenantProvisioner._createTenantProjectIfNeeded: creating project $projectId',
    );

    try {
      debugPrint('Calling Cloud Function createTenantProject for $projectId');

      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('createTenantProject').call({
        'projectId': projectId,
        'companyName': companyName,
        if (billingAccount != null) 'billingAccount': billingAccount,
      }).timeout(const Duration(seconds: 300));

      final data = result.data as Map<String, dynamic>;
      debugPrint('Cloud Function createTenantProject succeeded: $data');

      if (data['success'] != true) {
        throw StateError('Cloud Function returned error: ${data['error'] ?? 'unknown error'}');
      }

      final displayName = data['displayName'] as String?;
      final projectNumber = data['projectNumber'] as String?;
      final finalProjectId = data['projectId'] as String? ?? projectId;
      final projectIdChanged = data['projectIdChanged'] as bool? ?? false;
      final alreadyExisted = data['alreadyExisted'] as bool? ?? false;
      final firebaseEnabled = data['firebaseEnabled'] as bool? ?? false;
      final apisEnabled = data['apisEnabled'] as bool? ?? false;
      final firestoreDbCreated = data['firestoreDbCreated'] as bool? ?? false;
      final authEnabled = data['authEnabled'] as bool? ?? false;
      debugPrint(
        'TenantProvisioner._createTenantProjectIfNeeded: completed successfully, '
        'displayName: $displayName, projectNumber: $projectNumber, '
        'finalProjectId: $finalProjectId, projectIdChanged: $projectIdChanged, '
        'alreadyExisted: $alreadyExisted, firebaseEnabled: $firebaseEnabled, '
        'apisEnabled: $apisEnabled, firestoreDbCreated: $firestoreDbCreated, '
        'authEnabled: $authEnabled',
      );

      return (
        displayName: displayName ?? companyName,
        projectNumber: projectNumber ?? '',
        finalProjectId: finalProjectId,
        projectIdChanged: projectIdChanged,
        firebaseEnabled: firebaseEnabled,
        apisEnabled: apisEnabled,
        firestoreDbCreated: firestoreDbCreated,
        authEnabled: authEnabled,
        alreadyExisted: alreadyExisted,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud Function createTenantProject failed: ${e.code} - ${e.message}');
      throw StateError(
        'Failed to create tenant project via Cloud Function: ${e.message}. '
        'Ensure the Cloud Functions are deployed and the master service account has '
        'Project Creator role on folder 818058604638. '
        'Details: ${e.details}',
      );
    } catch (e) {
      debugPrint('TenantProvisioner._createTenantProjectIfNeeded: error - $e');
      rethrow;
    }
  }

  /// Updates the workspace with the derived GCP project display name.
  Future<void> _updateWorkspaceGcpDisplayName(
    String workspaceId,
    String gcpProjectDisplayName,
  ) async {
    try {
      final firestore = FirebaseFirestore.instanceFor(app: _firebaseManager.defaultApp);
      await firestore
          .collection('workspaces')
          .doc(workspaceId)
          .update({'gcpProjectDisplayName': gcpProjectDisplayName});
      debugPrint(
        'TenantProvisioner: Updated workspace $workspaceId with GCP display name: $gcpProjectDisplayName',
      );
    } catch (e) {
      debugPrint('TenantProvisioner: Failed to update GCP display name: $e');
      // Non-fatal - don't block provisioning
    }
  }

  /// Updates the workspace's firebaseConfig.projectId when the Cloud Function
  /// regenerated the project ID due to a collision.
  Future<void> _updateWorkspaceProjectId(
    String workspaceId,
    String newProjectId,
  ) async {
    try {
      final firestore = FirebaseFirestore.instanceFor(app: _firebaseManager.defaultApp);
      await firestore.collection('workspaces').doc(workspaceId).update({
        'firebaseConfig.projectId': newProjectId,
      });
      debugPrint(
        'TenantProvisioner: Updated workspace $workspaceId with new project ID: $newProjectId',
      );
    } catch (e) {
      debugPrint('TenantProvisioner: Failed to update project ID: $e');
      // Non-fatal - don't block provisioning
    }
  }

  /// Updates the workspace with GCP project verified status and project number.
  /// Called after createTenantProject succeeds and returns a projectNumber.
  Future<void> _updateWorkspaceGcpVerified(
    String workspaceId,
    String projectNumber,
  ) async {
    try {
      final firestore = FirebaseFirestore.instanceFor(app: _firebaseManager.defaultApp);
      await firestore.collection('workspaces').doc(workspaceId).update({
        'gcpProjectVerified': true,
        'gcpProjectNumber': projectNumber,
      });
      debugPrint(
        'TenantProvisioner: Updated workspace $workspaceId as GCP verified with projectNumber: $projectNumber',
      );
    } catch (e) {
      debugPrint('TenantProvisioner: Failed to update GCP verified status: $e');
      // Non-fatal - don't block provisioning
    }
  }

  /// Updates granular provisioning flags on the workspace document.
  /// Called after each provisioning step completes in the Cloud Function.
  Future<void> _updateWorkspaceProvisioningFlags(
    String workspaceId, {
    required bool firebaseEnabled,
    required bool apisEnabled,
    required bool firestoreDbCreated,
    required bool authEnabled,
  }) async {
    try {
      final firestore = FirebaseFirestore.instanceFor(app: _firebaseManager.defaultApp);
      await firestore.collection('workspaces').doc(workspaceId).update({
        'firebaseEnabled': firebaseEnabled,
        'apisEnabled': apisEnabled,
        'firestoreDbCreated': firestoreDbCreated,
        'authEnabled': authEnabled,
      });
      debugPrint(
        'TenantProvisioner: Updated workspace $workspaceId provisioning flags — '
        'firebaseEnabled=$firebaseEnabled, apisEnabled=$apisEnabled, '
        'firestoreDbCreated=$firestoreDbCreated, authEnabled=$authEnabled',
      );
    } catch (e) {
      debugPrint('TenantProvisioner: Failed to update provisioning flags: $e');
    }
  }

  /// Marks the workspace as having successfully deployed Firestore rules.
  Future<void> _updateWorkspaceRulesDeployed(String workspaceId) async {
    try {
      final firestore = FirebaseFirestore.instanceFor(app: _firebaseManager.defaultApp);
      await firestore.collection('workspaces').doc(workspaceId).update({
        'rulesDeployed': true,
      });
      debugPrint('TenantProvisioner: Marked workspace $workspaceId rules as deployed');
    } catch (e) {
      debugPrint('TenantProvisioner: Failed to update rulesDeployed: $e');
    }
  }

  /// Updates the workspace onboarding status.
  Future<void> _updateWorkspaceOnboardingStatus(
    String workspaceId,
    String status, {
    String? failedStep,
    String? lastError,
  }) async {
    try {
      final firestore = FirebaseFirestore.instanceFor(app: _firebaseManager.defaultApp);
      final updateData = <String, dynamic>{
        'onboardingStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (failedStep != null) updateData['provisioningFailedStep'] = failedStep;
      if (lastError != null) updateData['provisioningLastError'] = lastError;
      await firestore.collection('workspaces').doc(workspaceId).update(updateData);
      debugPrint('TenantProvisioner: Updated workspace $workspaceId onboardingStatus=$status');
    } catch (e) {
      debugPrint('TenantProvisioner: Failed to update onboardingStatus: $e');
    }
  }
}

class _ActiveProvisioning {
  _ActiveProvisioning({required this.workspaceId, required this.context});

  final String workspaceId;
  final FirebaseContext context;
  String? companyId;
  String? adminUid;
  TenantSeedResult? seeds;

  bool authUserCreatedThisRun = false;

  bool adminAccessDocPreExisted = false;
  bool userDocPreExisted = false;
  bool companyDocPreExisted = false;
  bool adminDocPreExisted = false;
}
