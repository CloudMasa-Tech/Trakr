import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import '../landing/landing_page.dart';
import 'auth_shared.dart';
import 'login_screen.dart';
import 'role_guards.dart';

class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});

  static int _buildCount = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    _buildCount++;
    AuthSessionProvider.timingLog(
        'AuthGateScreen.build #$_buildCount | '
        'isLoading=${auth.isLoading} isAuthenticated=${auth.isAuthenticated} '
        'role=${auth.role?.value ?? 'null'} user=${auth.user?.uid ?? 'null'} '
        'error=${auth.errorMessage != null}');

    if (auth.isLoading) {
      AuthSessionProvider.timingLog(
          'AuthGateScreen.build -> AuthLoadingScreen (isLoading)');
      return const AuthLoadingScreen();
    }

    if (auth.user != null && auth.role == null) {
      AuthSessionProvider.timingLog(
          'AuthGateScreen.build -> AuthLoadingScreen (restoring session, user set but role null)');
      return AuthLoadingScreen(
        message: 'Restoring your session...',
        errorMessage: auth.errorMessage,
      );
    }

    if (!auth.isAuthenticated || auth.role == null) {
      AuthSessionProvider.timingLog(
          'AuthGateScreen.build -> back to LoginScreen/LandingPage (not authed)');
      if (kIsWeb) {
        return const LandingPage();
      }
      return const LoginScreen();
    }

    AuthSessionProvider.timingLog(
        'AuthGateScreen.build -> rendering homeForRole=${auth.role!.value} (dashboard shell build)');
    // Post-login redirect is centralized in RoleRouter so the three roles share
    // exactly one source of truth for their home screens.
    return RoleRouter.homeForRole(auth.role!, auth.signOut);
  }
}
