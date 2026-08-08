import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import 'portal_widgets.dart';

class ProfileModule extends StatelessWidget {
  const ProfileModule({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    final user = auth.user;
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email?.split('@').first ?? 'Super Admin');
    final email = user?.email ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: kCoLabel,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your Super Admin account details.',
                style: TextStyle(color: kCoSubtle, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              CoSectionCard(
                title: 'Account',
                subtitle: 'Signed in as a platform Super Admin.',
                icon: Icons.person_rounded,
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: kCoAccent.withValues(alpha: 0.25),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: kCoCyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: kCoLabel,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: const TextStyle(
                                  color: kCoSubtle,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: kCoGreen.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kCoGreen.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Text(
                                  'Super Admin',
                                  style: TextStyle(
                                    color: kCoGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CoSectionCard(
                title: 'Session',
                subtitle: 'Manage your sign-in session.',
                icon: Icons.shield_outlined,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Signing out returns you to the login screen. '
                        'Company attendance data is unaffected.',
                        style: TextStyle(
                          color: kCoSubtle,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: auth.isLoading ? null : auth.signOut,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kCoErrorLight,
                        side:
                            BorderSide(color: kCoRed500.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
