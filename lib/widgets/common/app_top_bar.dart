import 'package:flutter/material.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../theme/app_theme_colors.dart';

class AppTopBar extends StatelessWidget {
  final String title;
  final String subtitle;

  const AppTopBar({
    super.key,
    required this.title,
    required this.subtitle,
  });

  String _getInitials() {
    final user = FirebaseContextProvider.current.auth.currentUser;
    if (user?.displayName != null) {
      final parts = user!.displayName!.split(' ');
      return parts.map((p) => p.isNotEmpty ? p[0] : '').take(2).join();
    }
    return 'AD';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppGradientText(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          _iconBtn(context, Icons.notifications_outlined),
          const SizedBox(width: 10),
          _iconBtn(context, Icons.settings_outlined),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.primaryContainer,
            child: Text(
              _getInitials(),
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon) {
    final colors = AppColors.of(context);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: colors.iconSecondary,
        size: 18,
      ),
    );
  }
}
