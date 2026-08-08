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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();

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
      if (kIsWeb) {
        return const LandingPage();
      }
      return const LoginScreen();
    }

    // Post-login redirect is centralized in RoleRouter so the three roles share
    // exactly one source of truth for their home screens.
    return RoleRouter.homeForRole(auth.role!, auth.signOut);
  }
}
