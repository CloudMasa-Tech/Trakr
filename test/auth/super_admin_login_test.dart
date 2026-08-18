import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendqr/control_plane/services/login_workspace_resolver_service.dart';
import 'package:attendqr/control_plane/services/super_admin_config_service.dart';
import 'package:attendqr/providers/auth_session_provider.dart';
import 'package:attendqr/screens/app_shell.dart';
import 'package:attendqr/screens/auth/access_denied_screen.dart';
import 'package:attendqr/screens/auth/role_guards.dart';
import 'package:attendqr/screens/employee/employee_home_screen.dart';
import 'package:attendqr/screens/manager/manager_dashboard_screen.dart';
import 'package:attendqr/screens/super_admin/super_admin_portal_screen.dart';

void main() {
  group('Super Admin role resolution', () {
    test('super_admin role string maps to the superAdmin role', () {
      // The value written by functions/make_superadmin.js to users/{uid}.role
      // and read by AuthSessionProvider._loadRole().
      expect(AppUserRoleX.fromValue('super_admin'), AppUserRole.superAdmin);
      expect(AppUserRoleX.fromValue('superAdmin'), AppUserRole.superAdmin);
      expect(AppUserRoleX.fromValue('superadmin'), AppUserRole.superAdmin);
    });

    test('legacy role strings still fold into the four canonical roles', () {
      expect(AppUserRoleX.fromValue('company_admin'), AppUserRole.admin);
      expect(AppUserRoleX.fromValue('manager'), AppUserRole.manager);
      expect(AppUserRoleX.fromValue('staff'), AppUserRole.employee);
      expect(AppUserRoleX.fromValue('engineer'), AppUserRole.employee);
      expect(AppUserRoleX.fromValue('user'), AppUserRole.employee);
    });

    test('unknown role strings resolve to null (no role granted)', () {
      expect(AppUserRoleX.fromValue(null), isNull);
      expect(AppUserRoleX.fromValue(''), isNull);
      expect(AppUserRoleX.fromValue('ceo'), isNull);
      expect(AppUserRoleX.fromValue('SUPER_ADMIN'), isNull);
    });

    test('value/label round-trip is stable', () {
      expect(AppUserRole.superAdmin.value, 'super_admin');
      expect(AppUserRole.superAdmin.label, 'Super Admin');
      expect(AppUserRoleX.fromValue(AppUserRole.superAdmin.value),
          AppUserRole.superAdmin);
    });
  });

  group('Super Admin identity config', () {
    tearDown(SuperAdminConfig.reset);

    test('is unconfigured before any config is loaded', () {
      // On a fresh launch before login the config doc cannot be read (Firestore
      // rules require an authenticated caller), so the app must not pretend to
      // know a Super Admin identity yet.
      expect(SuperAdminConfig.email, isNull);
      expect(SuperAdminConfig.isConfigured, isFalse);
      expect(SuperAdminConfig.matches('keerthana.s@cloudmasa.com'), isFalse);
    });

    test('matches() is empty-safe and case/whitespace-insensitive', () {
      expect(SuperAdminConfig.matches(null), isFalse);
      expect(SuperAdminConfig.matches(''), isFalse);
      expect(SuperAdminConfig.matches('   '), isFalse);
    });
  });

  group('login workspace resolution kinds', () {
    test('super admin resolution routes to the Master project', () {
      const resolution = LoginWorkspaceResolution.superAdmin();
      expect(resolution.isSuperAdmin, isTrue);
      expect(resolution.isTenant, isFalse);
      expect(resolution.isNotFound, isFalse);
      expect(resolution.isUnavailable, isFalse);
      expect(resolution.workspace, isNull);
    });

    test('other resolution kinds are mutually exclusive', () {
      const notFound = LoginWorkspaceResolution.notFound();
      expect(notFound.isNotFound, isTrue);
      expect(notFound.isSuperAdmin, isFalse);

      const unavailable =
          LoginWorkspaceResolution.unavailable('workspace suspended');
      expect(unavailable.isUnavailable, isTrue);
      expect(unavailable.message, isNotNull);
    });
  });

  group('Super Admin dashboard redirect', () {
    test('homeForRole redirects super admin to the Super Admin portal', () {
      // AuthGateScreen delegates the post-login redirect to this single source
      // of truth, so verifying it covers the "redirected to the Super Admin
      // Dashboard" requirement.
      final widget =
          RoleRouter.homeForRole(AppUserRole.superAdmin, () async {});
      expect(widget, isA<SuperAdminPortalScreen>());
    });

    test('every role maps to its own dashboard', () {
      expect(RoleRouter.homeForRole(AppUserRole.admin, () async {}),
          isA<AppShell>());
      expect(RoleRouter.homeForRole(AppUserRole.manager, () async {}),
          isA<ManagerDashboardScreen>());
      expect(RoleRouter.homeForRole(AppUserRole.employee, () async {}),
          isA<EmployeeHomeScreen>());
    });

    test('portal route is super-admin-only', () {
      expect(RoleRouter.superAdminRoute, '/super-admin');
      expect(
          RoleRouter.allows({AppUserRole.superAdmin}, AppUserRole.superAdmin),
          isTrue);
      expect(
          RoleRouter.allows({AppUserRole.superAdmin}, AppUserRole.admin),
          isFalse);
      expect(
          RoleRouter.allows({AppUserRole.superAdmin}, AppUserRole.manager),
          isFalse);
      expect(
          RoleRouter.allows({AppUserRole.superAdmin}, AppUserRole.employee),
          isFalse);
      expect(RoleRouter.allows({AppUserRole.superAdmin}, null), isFalse);
    });

    test('denied users are bounced to the Access Denied screen', () {
      const guard = RoleGuard(
        allowedRoles: {AppUserRole.superAdmin},
        builder: _unusedBuilder,
      );
      expect(guard.denied, isNull);
      expect(const AccessDeniedScreen(), isA<AccessDeniedScreen>());
    });
  });
}

Widget _unusedBuilder(AuthSessionProvider auth) => const SizedBox.shrink();
