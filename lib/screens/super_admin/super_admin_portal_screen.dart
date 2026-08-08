import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../widgets/common/trakr_logo.dart';

import '../../theme/portal_palette.dart';
import '../auth/access_denied_screen.dart';
import 'analytics_module.dart';
import 'announcements_module.dart';
import 'audit_logs_module.dart';
import 'billing_module.dart';
import 'client_onboarding_module.dart';
import 'workspaces_module.dart';
import 'dashboard_module.dart';
import 'notifications_module.dart';
import 'platform_settings_module.dart';
import 'reports_module.dart';
import 'security_module.dart';
import 'subscriptions_module.dart';
import 'support_module.dart';
import 'users_module.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final Widget Function(BuildContext) builder;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.builder,
  });
}

class SuperAdminPortalScreen extends StatefulWidget {
  final Future<void> Function() onLogout;

  const SuperAdminPortalScreen({super.key, required this.onLogout});

  @override
  State<SuperAdminPortalScreen> createState() => _SuperAdminPortalScreenState();
}

class _SuperAdminPortalScreenState extends State<SuperAdminPortalScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _themeProvider = ThemeProvider();
  int _index = 0;

  static final List<_NavItem> _items = [
    _NavItem(
      label: 'Dashboard',
      icon: Icons.space_dashboard_rounded,
      builder: (_) => const PlatformDashboardModule(),
    ),
    _NavItem(
      label: 'Client Onboarding',
      icon: Icons.add_business_rounded,
      builder: (_) => const ClientOnboardingModule(),
    ),
    _NavItem(
      label: 'Workspaces',
      icon: Icons.apartment_rounded,
      builder: (_) => const WorkspacesModule(),
    ),
    _NavItem(
      label: 'Users',
      icon: Icons.group_rounded,
      builder: (_) => const UsersModule(),
    ),
    _NavItem(
      label: 'Subscriptions',
      icon: Icons.workspace_premium_rounded,
      builder: (_) => const SubscriptionsModule(),
    ),
    _NavItem(
      label: 'Billing',
      icon: Icons.receipt_long_rounded,
      builder: (_) => const BillingModule(),
    ),
    _NavItem(
      label: 'Analytics',
      icon: Icons.insights_rounded,
      builder: (_) => const AnalyticsModule(),
    ),
    _NavItem(
      label: 'Reports',
      icon: Icons.description_outlined,
      builder: (_) => const ReportsModule(),
    ),
    _NavItem(
      label: 'Support',
      icon: Icons.support_agent_rounded,
      builder: (_) => const SupportModule(),
    ),
    _NavItem(
      label: 'Audit Logs',
      icon: Icons.history_rounded,
      builder: (_) => const AuditLogsModule(),
    ),
    _NavItem(
      label: 'Notifications',
      icon: Icons.notifications_none_rounded,
      builder: (_) => const NotificationsModule(),
    ),
    _NavItem(
      label: 'Announcements',
      icon: Icons.campaign_outlined,
      builder: (_) => const AnnouncementsModule(),
    ),
    _NavItem(
      label: 'Security',
      icon: Icons.shield_outlined,
      builder: (_) => const SecurityModule(),
    ),
    _NavItem(
      label: 'Settings',
      icon: Icons.settings_rounded,
      builder: (_) => const PlatformSettingsModule(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _themeProvider.load();
  }

  @override
  void dispose() {
    _themeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    // Defense-in-depth: even if the portal is mounted outside AuthGateScreen
    // (e.g. a deep link), non-super-admins never see its contents.
    if (!auth.canAccessSuperAdmin) {
      return const AccessDeniedScreen();
    }

    final width = MediaQuery.of(context).size.width;
    final showSidebar = width >= 760;
    final rail = width < 1000;
    final item = _items[_index];

    return ListenableBuilder(
      listenable: _themeProvider,
      builder: (context, _) {
        final isDark = _themeProvider.isDark;
        return Theme(
          data: portalTheme(isDark: isDark),
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            drawer:
                showSidebar ? null : _buildSidebar(context, auth, rail: false),
            body: AppBackground(
              forceDark: isDark,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showSidebar) _buildSidebar(context, auth, rail: rail),
                  Expanded(
                    child: Column(
                      children: [
                        _buildTopBar(context, item, rail || !showSidebar),
                        Expanded(
                          child: ColoredBox(
                            color: (isDark
                                    ? AppThemeColors.backgroundDark
                                    : AppThemeColors.backgroundLight)
                                .withValues(alpha: 0.35),
                            child: item.builder(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context, AuthSessionProvider auth,
      {required bool rail}) {
    final palette = PortalPalette.of(context);
    final width = rail ? 76.0 : 250.0;
    return Container(
      width: width,
      color: palette.appBar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: rail ? 14 : 18,
                vertical: 18,
              ),
              child: Row(
                children: [
                  TrakrLogo(
                    size: rail ? 38 : 40,
                  ),
                  if (!rail) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRAKR',
                          style: TextStyle(
                            color: palette.label,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Platform Console',
                          style: TextStyle(
                            color: palette.subtle,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Divider(color: palette.border, height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                    vertical: 12, horizontal: rail ? 8 : 12),
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (!rail && _isSectionStart(i)) _sectionHeader(context, i),
                    _navTile(context, i, item: _items[i], rail: rail),
                  ],
                ],
              ),
            ),
            Divider(color: palette.border, height: 1),
            _buildUserFooter(context, auth, rail: rail),
          ],
        ),
      ),
    );
  }

  bool _isSectionStart(int index) {
    return index == 1 || index == 4 || index == 9;
  }

  Widget _sectionHeader(BuildContext context, int index) {
    final label = switch (index) {
      1 => 'Tenants',
      4 => 'Commercial',
      _ => 'Operations',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: PortalPalette.of(context).subtle,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _navTile(BuildContext context, int index,
      {required _NavItem item, required bool rail}) {
    final palette = PortalPalette.of(context);
    final selected = index == _index;
    final color = selected ? palette.hero : palette.subtle;
    final bg =
        selected ? palette.accent.withValues(alpha: 0.22) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: item.label,
        waitDuration: rail ? const Duration(milliseconds: 300) : null,
        child: InkWell(
          onTap: () {
            setState(() => _index = index);
            if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: rail ? 0 : 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: palette.accent.withValues(alpha: 0.5))
                  : null,
            ),
            child: Row(
              mainAxisAlignment:
                  rail ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(item.icon, color: color, size: 20),
                if (!rail) ...[
                  const SizedBox(width: 12),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: selected ? palette.label : palette.subtle,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserFooter(BuildContext context, AuthSessionProvider auth,
      {required bool rail}) {
    final palette = PortalPalette.of(context);
    final name = auth.user?.displayName?.trim().isNotEmpty == true
        ? auth.user!.displayName!.trim()
        : (auth.user?.email ?? 'Super Admin');
    return Padding(
      padding: EdgeInsets.all(rail ? 10 : 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: palette.accent.withValues(alpha: 0.25),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: palette.hero,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          if (!rail) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.label,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    'Super Admin',
                    style: TextStyle(
                      color: palette.subtle,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: widget.onLogout,
              icon: Icon(Icons.logout_rounded, color: palette.subtle, size: 20),
              tooltip: 'Sign out',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, _NavItem item, bool showMenu) {
    final palette = PortalPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: palette.appBar.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          if (showMenu) ...[
            IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: Icon(Icons.menu_rounded, color: palette.subtle),
              tooltip: 'Menu',
            ),
            const SizedBox(width: 4),
          ],
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(item.icon, color: palette.hero, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    color: palette.label,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Super Admin • TRAKR Platform',
                  style: TextStyle(
                    color: palette.subtle,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _themeProvider.toggle,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: palette.subtle,
              size: 20,
            ),
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          ),
        ],
      ),
    );
  }
}
