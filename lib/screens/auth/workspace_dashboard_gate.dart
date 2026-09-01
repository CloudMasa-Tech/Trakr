import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import '../landing/landing_page.dart';
import 'auth_shared.dart';
import 'login_screen.dart';
import 'role_guards.dart';

/// Renders the dashboard for a `/workspace/:workspaceSlug/dashboard` URL.
///
/// The router's redirect already normalizes the URL to the signed-in tenant's
/// slug; this screen mirrors [AuthGateScreen]'s loading/login/home states and
/// defensively corrects a stale slug in the address bar (e.g. when the deep
/// link was typed by hand).
class WorkspaceDashboardGate extends StatefulWidget {
  final String workspaceSlug;

  const WorkspaceDashboardGate({super.key, required this.workspaceSlug});

  @override
  State<WorkspaceDashboardGate> createState() => _WorkspaceDashboardGateState();
}

class _WorkspaceDashboardGateState extends State<WorkspaceDashboardGate> {
  bool _urlChecked = false;
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    AuthSessionProvider.timingLog(
        'WorkspaceDashboardGate.initState slug=${widget.workspaceSlug}');
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileUrl());
  }

  void _reconcileUrl() {
    if (_urlChecked || !mounted) return;
    _urlChecked = true;

    final auth = context.read<AuthSessionProvider>();
    if (!auth.isAuthenticated || auth.role == null) return;
    if (auth.role == AppUserRole.superAdmin) return;

    final slug = auth.workspaceSlug;
    if (slug != null && slug.isNotEmpty && slug != widget.workspaceSlug) {
      AuthSessionProvider.timingLog(
          'WorkspaceDashboardGate.reconcileUrl -> context.go(/workspace/$slug/dashboard) '
          '(widget slug ${widget.workspaceSlug} stale)');
      context.go('/workspace/$slug/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    _buildCount++;
    AuthSessionProvider.timingLog(
        'WorkspaceDashboardGate.build #$_buildCount slug=${widget.workspaceSlug} | '
        'isLoading=${auth.isLoading} isAuthenticated=${auth.isAuthenticated} '
        'role=${auth.role?.value ?? 'null'} user=${auth.user?.uid ?? 'null'} '
        'error=${auth.errorMessage != null}');

    if (auth.isLoading) {
      return const AuthLoadingScreen();
    }

    if (auth.user != null && auth.role == null) {
      return AuthLoadingScreen(
        message: 'Restoring your session...',
        errorMessage: auth.errorMessage,
      );
    }

    if (!auth.isAuthenticated || auth.role == null) {
      AuthSessionProvider.timingLog(
          'WorkspaceDashboardGate.build -> back to LoginScreen (not authed/role null)');
      if (kIsWeb) {
        return const LandingPage();
      }
      return const LoginScreen();
    }

    AuthSessionProvider.timingLog(
        'WorkspaceDashboardGate.build -> rendering homeForRole=${auth.role!.value} (dashboard shell build)');
    return RoleRouter.homeForRole(auth.role!, auth.signOut);
  }
}
