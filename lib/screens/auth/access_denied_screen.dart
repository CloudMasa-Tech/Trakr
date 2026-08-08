import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import '../../theme/app_theme_colors.dart';
import 'role_guards.dart';

/// Shown whenever an authenticated user opens a route that requires a role they
/// do not hold (e.g. a company admin or employee hitting a Super Admin page).
/// Offers a way back to the caller's own dashboard and a sign-out action.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.gpp_bad_rounded,
                    size: 64,
                    color: colors.warning,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Access Denied',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'You do not have permission to view this page. '
                  'This area is restricted to authorized roles only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                if (auth.isAuthenticated && auth.role != null) ...[
                  FilledButton.icon(
                    onPressed: () => RoleRouter.navigateToHome(context),
                    icon: const Icon(Icons.space_dashboard_rounded),
                    label: const Text('Go to My Dashboard'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: auth.isAuthenticated ? auth.signOut : null,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
