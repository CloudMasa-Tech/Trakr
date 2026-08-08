import '../../providers/auth_session_provider.dart';
import '../models/workspace.dart';
import '../models/workspace_status.dart';
import '../repositories/tenant_identity_repository.dart';
import '../repositories/workspace_repository.dart';

/// What an email resolves to before any credentials are exchanged.
enum LoginWorkspaceKind {
  /// The platform Super Admin — authenticated against the Master project.
  superAdmin,

  /// A member of a tenant workspace — authenticate against that tenant.
  tenant,

  /// The email has no entry in the identity index. The caller must produce the
  /// same generic invalid-credentials error as a wrong password so the index
  /// cannot be used to enumerate which emails exist.
  notFound,

  /// The email is known but its workspace cannot be used right now.
  unavailable,
}

/// The result of resolving a login email against the Master control plane.
class LoginWorkspaceResolution {
  final LoginWorkspaceKind kind;

  /// The resolved tenant workspace (only when [kind] is `tenant`).
  final Workspace? workspace;

  /// Human-readable message (only when [kind] is `unavailable`).
  final String? message;

  const LoginWorkspaceResolution._(this.kind, {this.workspace, this.message});

  const LoginWorkspaceResolution.superAdmin()
      : this._(LoginWorkspaceKind.superAdmin);

  const LoginWorkspaceResolution.tenant(Workspace workspace)
      : this._(LoginWorkspaceKind.tenant, workspace: workspace);

  const LoginWorkspaceResolution.notFound()
      : this._(LoginWorkspaceKind.notFound);

  const LoginWorkspaceResolution.unavailable(String message)
      : this._(LoginWorkspaceKind.unavailable, message: message);

  bool get isSuperAdmin => kind == LoginWorkspaceKind.superAdmin;
  bool get isTenant => kind == LoginWorkspaceKind.tenant;
  bool get isNotFound => kind == LoginWorkspaceKind.notFound;
  bool get isUnavailable => kind == LoginWorkspaceKind.unavailable;
}

/// Resolves a login email into the Firebase project it must authenticate
/// against, using the Master control-plane identity index.
///
/// The Super Admin email resolves to the Master project itself. Every other
/// email is looked up in `tenant_users/{email}`; when present, its workspace is
/// read from the registry and validated (active + provisioned). This service
/// only *resolves* — tenant activation is owned by `TenantBootstrapService`.
class LoginWorkspaceResolverService {
  LoginWorkspaceResolverService({
    TenantIdentityRepository? identities,
    WorkspaceRepository? workspaces,
  })  : _identities = identities ?? TenantIdentityRepository(),
        _workspaces = workspaces ?? WorkspaceRepository();

  /// Shared instance used by the app.
  static final LoginWorkspaceResolverService instance =
      LoginWorkspaceResolverService();

  final TenantIdentityRepository _identities;
  final WorkspaceRepository _workspaces;

  /// Resolves [rawEmail] against the Master control plane.
  ///
  /// Throws on a Master connectivity failure (the caller surfaces a generic
  /// message) but never leaks whether an email is registered.
  Future<LoginWorkspaceResolution> resolve(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (email.isEmpty) {
      return const LoginWorkspaceResolution.notFound();
    }

    if (email == AuthSessionProvider.superAdminEmail) {
      return const LoginWorkspaceResolution.superAdmin();
    }

    final identity = await _identities.getByEmail(email);
    if (identity == null) {
      return const LoginWorkspaceResolution.notFound();
    }

    final workspace = await _workspaces.getById(identity.workspaceId);
    if (workspace == null) {
      // Stale index entry (workspace decommissioned/deleted). Treat as unknown
      // so the caller shows the same generic invalid-credentials error.
      return const LoginWorkspaceResolution.notFound();
    }

    return _validate(workspace);
  }

  LoginWorkspaceResolution _validate(Workspace workspace) {
    if (!workspace.firebaseConfig.isValid) {
      return const LoginWorkspaceResolution.unavailable(
        'This workspace is not ready yet. Please try again shortly.',
      );
    }

    switch (workspace.status) {
      case WorkspaceStatus.active:
        return LoginWorkspaceResolution.tenant(workspace);
      case WorkspaceStatus.provisioning:
        return const LoginWorkspaceResolution.unavailable(
          'This workspace is still being set up. '
          'Please try again in a few minutes.',
        );
      case WorkspaceStatus.suspended:
        return const LoginWorkspaceResolution.unavailable(
          'This workspace is currently suspended. '
          'Please contact your administrator for support.',
        );
      case WorkspaceStatus.decommissioned:
        return const LoginWorkspaceResolution.unavailable(
          'This workspace is no longer available.',
        );
    }
  }
}
