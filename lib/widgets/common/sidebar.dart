// lib/widgets/common/sidebar.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme_colors.dart';
import 'trakr_logo.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Future<void> Function()? onLogout;
  final VoidCallback? onProfileTap;
  final String? adminName;
  final String? adminRole;
  final String? photoUrl;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.onLogout,
    this.onProfileTap,
    this.adminName,
    this.adminRole,
    this.photoUrl,
  });

  ImageProvider? _decodeSidebarImage(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('data:image')) {
      final payload = raw.contains(',') ? raw.split(',').last : raw;
      try {
        return MemoryImage(base64Decode(payload));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(raw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    final name = adminName?.trim().isNotEmpty == true ? adminName! : 'Admin';
    final designation = adminRole ?? 'HR Admin';
    final avatarImage = _decodeSidebarImage(photoUrl);

    return Container(
      width: 230,
      height: double.infinity,
      color: colors.sidebar,
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),

                // ── Brand Header ─────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: TrakrLogo(size: 120),
                  ),
                ),

                if (onProfileTap != null) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: InkWell(
                      onTap: onProfileTap,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.surfaceRaised.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.border.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    colors.secondary,
                                    colors.focus,
                                  ],
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: colors.surface,
                                backgroundImage: avatarImage,
                                child: photoUrl?.trim().isNotEmpty == true
                                    ? null
                                    : Text(
                                        name.trim().isNotEmpty
                                            ? name.trim()[0].toUpperCase()
                                            : 'A',
                                        style: TextStyle(
                                          color: colors.textInverse,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    designation,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: colors.iconMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // ── MAIN Section ─────────────────────────────────────────
                _sectionLabel(context, 'MAIN'),
                const SizedBox(height: 6),

                _SidebarItem(
                    index: 0,
                    selectedIndex: selectedIndex,
                    icon: Icons.grid_view_rounded,
                    label: 'Dashboard',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 11,
                    selectedIndex: selectedIndex,
                    icon: Icons.history_rounded,
                    label: 'Attendance History',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 12,
                    selectedIndex: selectedIndex,
                    icon: Icons.manage_history_rounded,
                    label: 'Manager Log',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 13,
                    selectedIndex: selectedIndex,
                    icon: Icons.analytics_outlined,
                    label: 'Monthly Analysis',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 4,
                    selectedIndex: selectedIndex,
                    icon: Icons.payments_outlined,
                    label: 'Payroll',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 2,
                    selectedIndex: selectedIndex,
                    icon: Icons.location_on_outlined,
                    label: 'Geo-Tagging',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 10,
                    selectedIndex: selectedIndex,
                    icon: Icons.calendar_month_outlined,
                    label: 'Weekend / Holiday',
                    onTap: onItemSelected),

                _SidebarItem(
                    index: 3,
                    selectedIndex: selectedIndex,
                    icon: Icons.people_outline_rounded,
                    label: 'Team Directory',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 9,
                    selectedIndex: selectedIndex,
                    icon: Icons.assignment_late_outlined,
                    label: 'Checkout Request',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 8,
                    selectedIndex: selectedIndex,
                    icon: Icons.notifications_active_outlined,
                    label: 'Manager Requests',
                    onTap: onItemSelected),
                _SidebarItem(
                    index: 14,
                    selectedIndex: selectedIndex,
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: onItemSelected),

                const SizedBox(height: 20),

                const Spacer(),
                if (onLogout != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Logout'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.error,
                          foregroundColor: colors.onError,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          shadowColor: colors.error.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Text(label,
          style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4)),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final int index;
  final int selectedIndex;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  const _SidebarItem({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isSelected = index == selectedIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: FocusableActionDetector(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap(index);
              return null;
            },
          ),
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? colors.sidebarSelected : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isSelected
                    ? Border.all(color: colors.border.withValues(alpha: 0.7))
                    : Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(icon,
                      color: isSelected ? colors.primary : colors.iconSecondary,
                      size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: colors.secondary, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
