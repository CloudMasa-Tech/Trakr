import 'package:firebase_core/firebase_core.dart';

import '../../firebase/firebase_manager.dart';
import '../models/subscription.dart';
import '../models/workspace.dart';
import '../models/workspace_firebase_config.dart';
import '../models/workspace_status.dart';
import '../repositories/workspace_repository.dart';

/// Domain service orchestrating the workspace lifecycle against the Master
/// Firebase control plane.
///
/// Sits above [WorkspaceRepository] and owns the workspace lifecycle rules:
/// unique codes, provisioning/status transitions, and the bridge from a
/// registry entry to its tenant (data plane) [FirebaseApp].
class WorkspaceRegistryService {
  WorkspaceRegistryService({WorkspaceRepository? repository})
      : _repository = repository ?? WorkspaceRepository();

  final WorkspaceRepository _repository;

  /// Whether [workspaceCode] is not yet registered.
  Future<bool> isCodeAvailable(String workspaceCode) {
    return _repository.isCodeAvailable(workspaceCode);
  }

  /// Generates a unique workspace code derived from [companyName].
  ///
  /// Produces a lowercase slug (e.g. `green-hospital`) and, if taken, appends a
  /// numeric suffix (`green-hospital-2`, `green-hospital-3`, ...) until an
  /// available code is found.
  Future<String> generateUniqueWorkspaceCode(String companyName) async {
    final base = companyName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final slug = base.isEmpty ? 'workspace' : base;

    var candidate = slug;
    var attempt = 1;
    while (!await isCodeAvailable(candidate)) {
      attempt += 1;
      candidate = '$slug-$attempt';
    }
    return candidate;
  }

  /// Resolves a workspace by its human-friendly code.
  Future<Workspace?> resolveByCode(String workspaceCode) {
    return _repository.getByCode(workspaceCode);
  }

  /// Resolves a workspace by its stable id.
  Future<Workspace?> resolveById(String workspaceId) {
    return _repository.getById(workspaceId);
  }

  /// Streams a workspace for live status/subscription updates.
  Stream<Workspace?> streamWorkspace(String workspaceId) {
    return _repository.streamById(workspaceId);
  }

  /// Lists every registered workspace, newest first.
  Future<List<Workspace>> listWorkspaces() {
    return _repository.getAll();
  }

  /// Streams every registered workspace, newest first.
  Stream<List<Workspace>> streamWorkspaces() {
    return _repository.streamAll();
  }

  /// Registers a new workspace in the control plane.
  ///
  /// Enforces a unique [workspaceCode], generates a fresh [Workspace.workspaceId]
  /// when none is supplied, and seeds the entry in `provisioning` state. The
  /// tenant Firebase project itself is provisioned separately via
  /// [provisionTenantApp].
  Future<Workspace> registerWorkspace({
    required String companyName,
    required String workspaceCode,
    required String firebaseProjectId,
    required WorkspaceFirebaseConfig firebaseConfig,
    Subscription subscription = const Subscription.empty(),
    String? supportEmail,
    String? workspaceId,
  }) async {
    if (!await isCodeAvailable(workspaceCode)) {
      throw Exception(
        'A workspace already exists with code "$workspaceCode".',
      );
    }

    final id = workspaceId ?? await _repository.nextId();
    final now = DateTime.now();

    final workspace = Workspace(
      workspaceId: id,
      workspaceCode: workspaceCode,
      companyName: companyName,
      firebaseProjectId: firebaseProjectId,
      firebaseConfig: firebaseConfig,
      status: WorkspaceStatus.provisioning,
      onboardingStatus: WorkspaceOnboardingStatus.pending,
      subscription: subscription,
      supportEmail: supportEmail,
      createdAt: now,
      updatedAt: now,
    );

    await _repository.create(workspace);
    return workspace;
  }

  /// Builds the [FirebaseOptions] needed to initialize a workspace's tenant
  /// project from its stored configuration.
  FirebaseOptions buildFirebaseOptions(Workspace workspace) {
    return workspace.firebaseConfig.toFirebaseOptions();
  }

  /// Provisions (or returns the cached) tenant [FirebaseApp] for [workspace].
  ///
  /// Bridges the control plane to the data plane via [FirebaseManager], using
  /// [Workspace.workspaceId] as the named app so switching projects never
  /// requires an app restart.
  Future<FirebaseApp> provisionTenantApp(Workspace workspace) {
    return FirebaseManager.instance.initializeTenantApp(
      workspaceId: workspace.workspaceId,
      options: workspace.firebaseConfig.toFirebaseOptions(),
    );
  }

  /// Updates the stored tenant firebase configuration after provisioning.
  Future<Workspace> updateFirebaseConfig(
    String workspaceId,
    WorkspaceFirebaseConfig firebaseConfig,
  ) async {
    await _repository.update(workspaceId, {
      'firebaseConfig': firebaseConfig.toMap(),
    });
    return _requireUpdated(workspaceId);
  }

  /// Marks a workspace as ready once its tenant project is provisioned.
  Future<Workspace> markProvisioned(String workspaceId) async {
    await _repository.update(workspaceId, {
      'onboardingStatus': WorkspaceOnboardingStatus.ready.value,
      'status': WorkspaceStatus.active.value,
    });
    return _requireUpdated(workspaceId);
  }

  /// Records the ONE Company Admin's login email on the registry entry.
  ///
  /// This is the workspace-side half of the login identity index: combined
  /// with the `tenant_users/{email}` entry it lets a future login resolve this
  /// workspace from the admin's email without any manual workspace code.
  Future<void> recordAdminEmail(
    String workspaceId,
    String adminEmail,
  ) async {
    final normalized = adminEmail.trim().toLowerCase();
    if (normalized.isEmpty) return;
    await _repository.update(workspaceId, {'adminEmail': normalized});
  }

  /// Marks a workspace whose tenant provisioning failed.
  ///
  /// The registry entry (and its bound Firebase project allocation) is kept so
  /// the failure is visible in the platform console and can be retried later —
  /// the workspace simply stays non-active until intervention.
  Future<Workspace> markFailed(String workspaceId) async {
    await _repository.update(workspaceId, {
      'onboardingStatus': WorkspaceOnboardingStatus.failed.value,
      'status': WorkspaceStatus.provisioning.value,
    });
    return _requireUpdated(workspaceId);
  }

  /// Sets the onboarding (provisioning) status of a workspace.
  Future<Workspace> setOnboardingStatus(
    String workspaceId,
    WorkspaceOnboardingStatus onboardingStatus,
  ) async {
    await _repository.update(workspaceId, {
      'onboardingStatus': onboardingStatus.value,
    });
    return _requireUpdated(workspaceId);
  }

  /// Sets the lifecycle status of a workspace.
  Future<Workspace> setStatus(
    String workspaceId,
    WorkspaceStatus status,
  ) async {
    await _repository.update(workspaceId, {
      'status': status.value,
    });
    return _requireUpdated(workspaceId);
  }

  /// Activates a workspace.
  Future<Workspace> activate(String workspaceId) {
    return setStatus(workspaceId, WorkspaceStatus.active);
  }

  /// Suspends a workspace (e.g. billing issues).
  Future<Workspace> suspend(String workspaceId) {
    return setStatus(workspaceId, WorkspaceStatus.suspended);
  }

  /// Replaces the subscription attached to a workspace.
  Future<Workspace> updateSubscription(
    String workspaceId,
    Subscription subscription,
  ) async {
    await _repository.update(workspaceId, {
      'subscription': subscription.toMap(),
    });
    return _requireUpdated(workspaceId);
  }

  /// Deletes the workspace registry entry.
  ///
  /// Note: this does not dispose the tenant [FirebaseApp]. Call
  /// `FirebaseManager.instance.disposeTenant(workspaceId)` first when the
  /// tenant project should be torn down too.
  Future<void> deleteWorkspace(String workspaceId) {
    return _repository.delete(workspaceId);
  }

  Future<Workspace> _requireUpdated(String workspaceId) async {
    final updated = await _repository.getById(workspaceId);
    if (updated == null) {
      throw StateError('Workspace "$workspaceId" not found after update.');
    }
    return updated;
  }
}
