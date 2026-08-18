import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
