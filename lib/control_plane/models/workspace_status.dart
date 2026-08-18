/// Lifecycle status of a workspace in the Master Firebase control plane.
///
/// Governs whether a workspace's tenant Firebase project is usable, and is
/// platform-level state only — it never describes operational data.
enum WorkspaceStatus {
  provisioning,
  active,
  suspended;

  /// The wire value stored in Firestore.
  String get value {
    switch (this) {
      case WorkspaceStatus.provisioning:
        return 'provisioning';
      case WorkspaceStatus.active:
        return 'active';
      case WorkspaceStatus.suspended:
        return 'suspended';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case WorkspaceStatus.provisioning:
        return 'Provisioning';
      case WorkspaceStatus.active:
        return 'Active';
      case WorkspaceStatus.suspended:
        return 'Suspended';
    }
  }

  /// Parses a stored value back into a [WorkspaceStatus], or `null` for
  /// unknown values.
  static WorkspaceStatus? fromValue(String? value) {
    switch (value) {
      case 'provisioning':
        return WorkspaceStatus.provisioning;
      case 'active':
        return WorkspaceStatus.active;
      case 'suspended':
        return WorkspaceStatus.suspended;
      default:
        return null;
    }
  }
}

/// Provisioning state of a workspace's tenant Firebase project.
///
/// Tracks how far the workspace's dedicated Firebase project has been created
/// and configured, independent of its lifecycle [WorkspaceStatus].
enum WorkspaceOnboardingStatus {
  /// Registry entry created; tenant project not yet provisioned.
  pending,

  /// Tenant Firebase project is being created/configured.
  configuring,

  /// Tenant project provisioned and usable.
  ready,

  /// Provisioning failed; requires intervention.
  failed;

  /// The wire value stored in Firestore.
  String get value {
    switch (this) {
      case WorkspaceOnboardingStatus.pending:
        return 'pending';
      case WorkspaceOnboardingStatus.configuring:
        return 'configuring';
      case WorkspaceOnboardingStatus.ready:
        return 'ready';
      case WorkspaceOnboardingStatus.failed:
        return 'failed';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case WorkspaceOnboardingStatus.pending:
        return 'Pending';
      case WorkspaceOnboardingStatus.configuring:
        return 'Configuring';
      case WorkspaceOnboardingStatus.ready:
        return 'Ready';
      case WorkspaceOnboardingStatus.failed:
        return 'Failed';
    }
  }

  /// Parses a stored value back into a [WorkspaceOnboardingStatus], or `null`
  /// for unknown values.
  static WorkspaceOnboardingStatus? fromValue(String? value) {
    switch (value) {
      case 'pending':
        return WorkspaceOnboardingStatus.pending;
      case 'configuring':
        return WorkspaceOnboardingStatus.configuring;
      case 'ready':
        return WorkspaceOnboardingStatus.ready;
      case 'failed':
        return WorkspaceOnboardingStatus.failed;
      default:
        return null;
    }
  }
}
