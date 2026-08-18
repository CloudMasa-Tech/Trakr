import 'package:go_router/go_router.dart';

import '../providers/auth_session_provider.dart';
import '../screens/auth/auth_gate_screen.dart';
import '../screens/auth/workspace_dashboard_gate.dart';
import '../screens/super_admin/super_admin_portal_screen.dart';
import '../screens/super_admin/workspace_details_screen.dart';

/// Route pattern for a tenant's web dashboard, e.g.
/// `/workspace/cloudmasa-innovation-lab/dashboard`.
const String workspaceDashboardRoute = '/workspace/:workspaceSlug/dashboard';

/// Route pattern for the Super Admin portal.
const String superAdminRoute = '/super-admin';

/// Route pattern for workspace details in Super Admin portal.
const String superAdminWorkspaceDetailsRoute = '/super-admin/workspace/:workspaceId/details';

/// Builds the app-wide [GoRouter].
///
/// [auth] drives routing reactively: it is passed as `refreshListenable`, so
/// every session change re-runs the redirect below without manual navigation
/// calls. The redirect keeps the workspace-scoped URL in the address bar and
/// bounces unauthenticated or super-admin users out of tenant routes.
GoRouter buildAppRouter(AuthSessionProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;

      // While the session is being restored/validated, let the screens render
      // their own loading state instead of redirecting mid-restore.
      if (auth.isLoading) return null;

      if (path.startsWith('/workspace/')) {
        // Tenant dashboard deep links require a signed-in, non-super-admin user.
        if (!auth.isAuthenticated || auth.role == null) {
          return '/';
        }
        if (auth.role == AppUserRole.superAdmin) {
          return '/';
        }
        final slug = auth.workspaceSlug;
        if (slug != null && slug.isNotEmpty) {
          final requestedSlug = _slugFromPath(path);
          if (requestedSlug != slug) {
            return '/workspace/$slug/dashboard';
          }
        }
        return null;
      }

      // A signed-in tenant user always lands on their own workspace dashboard
      // URL so the address bar reflects the workspace (e.g.
      // `/workspace/cloudmasa-innovation-lab/dashboard`).
      if (path == '/' &&
          auth.isAuthenticated &&
          auth.role != null &&
          auth.role != AppUserRole.superAdmin) {
        final slug = auth.workspaceSlug;
        if (slug != null && slug.isNotEmpty) {
          return '/workspace/$slug/dashboard';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AuthGateScreen(),
      ),
      GoRoute(
        path: workspaceDashboardRoute,
        builder: (context, state) => WorkspaceDashboardGate(
          workspaceSlug: state.pathParameters['workspaceSlug'] ?? '',
        ),
      ),
      GoRoute(
        path: superAdminRoute,
        builder: (context, state) => SuperAdminPortalScreen(
          onLogout: () async => context.go('/'),
        ),
      ),
      GoRoute(
        path: superAdminWorkspaceDetailsRoute,
        builder: (context, state) => WorkspaceDetailsScreen(
          workspaceId: state.pathParameters['workspaceId'] ?? '',
        ),
      ),
    ],
  );
}

String? _slugFromPath(String path) {
  final segments = path.split('/');
  if (segments.length >= 3 && segments[1] == 'workspace') {
    final slug = segments[2];
    return slug.isEmpty ? null : slug;
  }
  return null;
}
