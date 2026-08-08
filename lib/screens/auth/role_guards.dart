import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import '../app_shell.dart';
import '../employee/employee_home_screen.dart';
import '../super_admin/super_admin_portal_screen.dart';
import 'access_denied_screen.dart';
import 'auth_shared.dart';

/// Centralizes role → home routing so the redirect targets for the three app
/// roles live in exactly one place. Used by [AuthGateScreen] for the post-login
/// redirect and by [RoleGuard] for protected named routes.
class RoleRouter {
  RoleRouter._();

  /// Named route for the Super Admin portal (guarded via [RoleGuard]).
  static const String superAdminRoute = '/super-admin';

  /// Named route for the generic Access Denied page.
  static const String accessDeniedRoute = '/access-denied';

  /// Whether [role] is allowed to enter a route restricted to [allowedRoles].
  static bool allows(Set<AppUserRole> allowedRoles, AppUserRole? role) =>
      role != null && allowedRoles.contains(role);

  /// The home screen for a signed-in [role].
  static Widget homeForRole(
    AppUserRole role,
    Future<void> Function() onLogout,
  ) {
    switch (role) {
      case AppUserRole.superAdmin:
        return SuperAdminPortalScreen(onLogout: onLogout);
      case AppUserRole.companyAdmin:
        return AppShell(initialIndex: 0, onLogout: onLogout);
      case AppUserRole.user:
        return EmployeeHomeScreen(role: role, onLogout: onLogout);
    }
  }

  /// Returns the blocked user to their own dashboard. The router's redirect
  /// resolves the correct destination (workspace URL for tenant users, the
  /// Super Admin portal stays at `/`), so this just navigates to the gate.
  static void navigateToHome(BuildContext context) {
    final auth = context.read<AuthSessionProvider>();
    if (!auth.isAuthenticated || auth.role == null) return;
    context.go('/');
  }
}

/// Route-level guard: watches the auth session and only shows [builder]'s
/// screen when the signed-in user's role is in [allowedRoles]. Otherwise it
/// shows [AccessDeniedScreen] (or [denied] when provided).
class RoleGuard extends StatelessWidget {
  final Set<AppUserRole> allowedRoles;
  final Widget Function(AuthSessionProvider auth) builder;
  final Widget? denied;

  const RoleGuard({
    super.key,
    required this.allowedRoles,
    required this.builder,
    this.denied,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    if (auth.isLoading) {
      return const AuthLoadingScreen();
    }
    if (!RoleRouter.allows(allowedRoles, auth.role)) {
      return denied ?? const AccessDeniedScreen();
    }
    return builder(auth);
  }
}
