// lib/widgets/common/sidebar.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme_colors.dart';
import 'trakr_logo.dart';

class Sidebar extends StatefulWidget {
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

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  static const _analyticsSection = 'ANALYTICS';
  static const _attendanceSection = 'ATTENDANCE MONITOR';
  static const _payrollSection = 'PAYROLL';
  static const _directorySection = 'DIRECTORY & ACCESS';
  static const _appSettingSection = 'APP SETTING';
  static const _profileSettingSection = 'PROFILE SETTING';

  late final Set<String> _expandedSections;

  @override
  void initState() {
    super.initState();
    _expandedSections = {};
    final section = _sectionForIndex(widget.selectedIndex);
    if (section != null) _expandedSections.add(section);
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final section = _sectionForIndex(widget.selectedIndex);
      if (section != null && !_expandedSections.contains(section)) {
        _expandedSections.add(section);
      }
    }
  }

  static String? _sectionForIndex(int index) {
    switch (index) {
      case 0:
        return _analyticsSection;
      case 11:
      case 12:
      case 13:
      case 17:
        return _attendanceSection;
      case 4:
        return _payrollSection;
      case 3:
      case 15:
      case 16:
        return _directorySection;
      case 5:
        return _profileSettingSection;
      case 7:
      case 8:
      case 9:
        return _appSettingSection;
      default:
        return null;
    }
  }

  void _toggleSection(String section) {
    setState(() {
      if (_expandedSections.contains(section)) {
        _expandedSections.remove(section);
      } else {
        _expandedSections.add(section);
      }
    });
  }

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

    final name = widget.adminName?.trim().isNotEmpty == true
        ? widget.adminName!
        : 'Admin';
    final designation = widget.adminRole ?? 'HR Admin';
    final avatarImage = _decodeSidebarImage(widget.photoUrl);

    return Container(
      width: 230,
      height: double.infinity,
      color: colors.sidebar,
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: true,
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

                if (widget.onProfileTap != null) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: InkWell(
                      onTap: widget.onProfileTap,
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
                                child: widget.photoUrl?.trim().isNotEmpty ==
                                        true
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

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                // ── ANALYTICS ────────────────────────────────────────────
                _sectionHeader(context, _analyticsSection),
                _CollapsibleSectionGroup(
                  expanded: _expandedSections.contains(_analyticsSection),
                  children: [
                    _SidebarItem(
                        index: 0,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.grid_view_rounded,
                        label: 'Dashboard',
                        onTap: widget.onItemSelected),
                  ],
                ),

                const SizedBox(height: 14),
                // ── ATTENDANCE MONITOR ───────────────────────────────────
                _sectionHeader(context, _attendanceSection),
                _CollapsibleSectionGroup(
                  expanded: _expandedSections.contains(_attendanceSection),
                  children: [
                    _SidebarItem(
                        index: 11,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.history_rounded,
                        label: 'Attendance Monitoring',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 12,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.manage_history_rounded,
                        label: 'Manager Activity Log',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 13,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.analytics_outlined,
                        label: 'Monthly Analysis',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 17,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.fact_check_outlined,
                        label: 'Approve Requests',
                        onTap: widget.onItemSelected),
                  ],
                ),

                const SizedBox(height: 14),
                // ── PAYROLL ──────────────────────────────────────────────
                _sectionHeader(context, _payrollSection),
                _CollapsibleSectionGroup(
                  expanded: _expandedSections.contains(_payrollSection),
                  children: [
                    _SidebarItem(
                        index: 4,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.payments_outlined,
                        label: 'Payroll & Compensation',
                        onTap: widget.onItemSelected),
                  ],
                ),

                const SizedBox(height: 14),
                // ── DIRECTORY & ACCESS ───────────────────────────────────
                _sectionHeader(context, _directorySection),
                _CollapsibleSectionGroup(
                  expanded: _expandedSections.contains(_directorySection),
                  children: [
                    _SidebarItem(
                        index: 3,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.people_outline_rounded,
                        label: 'Employee Directory',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 15,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Roles & Permissions',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 16,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.work_outline_rounded,
                        label: 'Designations',
                        onTap: widget.onItemSelected),
                  ],
                ),

                const SizedBox(height: 14),
                // ── APP SETTING ───────────────────────────────────────────
                _sectionHeader(context, _appSettingSection),
                _CollapsibleSectionGroup(
                  expanded: _expandedSections.contains(_appSettingSection),
                  children: [
                    _SidebarItem(
                        index: 7,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.settings_outlined,
                        label: 'Geo-Fencing Setup',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 8,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.calendar_today_outlined,
                        label: 'Weekoff / Holiday Setup',
                        onTap: widget.onItemSelected),
                    _SidebarItem(
                        index: 9,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.celebration_outlined,
                        label: 'Festival Setting',
                        onTap: widget.onItemSelected),
                  ],
                ),

                const SizedBox(height: 14),
                // ── Notifications (top-level, no header) ─────────────────
                _SidebarItem(
                    index: 14,
                    selectedIndex: widget.selectedIndex,
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: widget.onItemSelected),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                // ── PROFILE SETTING ───────────────────────────────────────
                _sectionHeader(context, _profileSettingSection),
                _CollapsibleSectionGroup(
                  expanded: _expandedSections.contains(_profileSettingSection),
                  children: [
                    _SidebarItem(
                        index: 5,
                        selectedIndex: widget.selectedIndex,
                        icon: Icons.person_outline_rounded,
                        label: 'Profile Setting',
                        onTap: widget.onItemSelected),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.onLogout != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onLogout,
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

  Widget _sectionHeader(BuildContext context, String label) {
    final colors = AppColors.of(context);
    final expanded = _expandedSections.contains(label);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleSection(label),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4)),
              ),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: expanded ? colors.focus : colors.iconMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsibleSectionGroup extends StatelessWidget {
  final bool expanded;
  final List<Widget> children;
  const _CollapsibleSectionGroup({
    required this.expanded,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    // `AnimatedSize` animates between the expanded Column (intrinsic height)
    // and a zero-height box when collapsed. It is safe inside the sidebar's
    // `CustomScrollView`/`SliverFillRemaining` (unbounded height) — unlike
    // `AnimatedCrossFade`, which produced a zero-size Stack (all-Positioned
    // children) under loose constraints and crashed with layout assertions.
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: expanded
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: children,
            )
          : const SizedBox(width: double.infinity, height: 0),
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