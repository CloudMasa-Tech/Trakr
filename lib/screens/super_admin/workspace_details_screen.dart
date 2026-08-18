import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../control_plane/models/workspace.dart';
import '../../control_plane/models/workspace_status.dart';
import '../../control_plane/services/cross_project_analytics_service.dart';
import '../../control_plane/services/workspace_registry_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class WorkspaceDetailsScreen extends StatefulWidget {
  final String workspaceId;
  
  const WorkspaceDetailsScreen({
    super.key,
    required this.workspaceId,
  });

  static Future<void> show(
    BuildContext context, {
    required String workspaceId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkspaceDetailsScreen(
          workspaceId: workspaceId,
        ),
      ),
    );
  }

  @override
  State<WorkspaceDetailsScreen> createState() => _WorkspaceDetailsScreenState();
}

class _WorkspaceDetailsScreenState extends State<WorkspaceDetailsScreen> {
  final _registry = WorkspaceRegistryService();
  final _analytics = CrossProjectAnalyticsService();

  Workspace? _workspace;
  String? _error;
  bool _loadingUsers = false;

  int _health = 0;
  DateTime? _lastLogin;
  Map<String, int> _userCounts = {'total': 0, 'staff': 0, 'managers': 0, 'admins': 0};

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _loadingUsers = true);
    try {
      final w = await _registry.resolveById(widget.workspaceId);
      final health =
          await _analytics.getWorkspaceHealthScore(widget.workspaceId);
      final login = await _analytics.getLastLoginTime(widget.workspaceId);
      final userCounts = await _analytics.getWorkspaceUserCounts(widget.workspaceId);

      if (!mounted) return;
      setState(() {
        _workspace = w ?? _workspace;
        _health = health;
        _lastLogin = login;
        _userCounts = userCounts;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingUsers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_workspace == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final w = _workspace!;

    return Scaffold(
      backgroundColor: AppThemeColors.backgroundDark,
      appBar: AppBar(
        title: Text(w.companyName),
        backgroundColor: AppThemeColors.darkAppBar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Workspaces',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(w),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text('Error: $_error',
                        style: const TextStyle(color: kCoRed)),
                  ),
                _buildCompanyInfoSection(w),
                const SizedBox(height: 24),
                _buildWorkspaceInfoSection(w),
                const SizedBox(height: 24),
                _buildHealthSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyInfoSection(Workspace w) {
    return CoSectionCard(
      title: 'Company',
      subtitle: 'Workspace tenant organization',
      icon: Icons.business,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoCompanyAvatar(name: w.companyName, logoUrl: null, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.companyName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kCoLabel,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                    ),
                    if (w.adminEmail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Admin: ${w.adminEmail}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoSubtle, fontSize: 12),
                      ),
                    ],
                    if (w.companyPhone != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Phone: ${w.companyPhone}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoSubtle, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (w.supportEmail != null) ...[
            const SizedBox(height: 12),
            Text(
              'Support: ${w.supportEmail}',
              style: const TextStyle(color: kCoSubtle, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  color: kCoSubtle, size: 16),
              const SizedBox(width: 6),
              Text(
                w.createdAt == null
                    ? 'Created: —'
                    : 'Created: ${DateFormat('dd MMM yyyy').format(w.createdAt!)}',
                style: const TextStyle(color: kCoLabel, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceInfoSection(Workspace w) {
    return CoSectionCard(
      title: 'Workspace',
      subtitle: 'Tenant project details',
      icon: Icons.info_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoMetricCard(
                  icon: Icons.workspace_premium,
                  label: 'Plan',
                  value: w.subscription.planName.isEmpty
                      ? 'Free'
                      : w.subscription.planName),
              const SizedBox(width: 8),
              CoStatusChip(isActive: w.status == WorkspaceStatus.active),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.flutter_dash_rounded,
                  color: kCoSubtle, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  w.firebaseProjectId.isEmpty
                      ? 'Not configured'
                      : w.firebaseProjectId,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: w.firebaseConfigured ? kCoLabel : kCoSubtle,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (w.firebaseConfigured) ...[
                const SizedBox(width: 5),
                const Icon(Icons.check_circle_rounded,
                    color: kCoGreen, size: 14),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Workspace w) {
    return CoSectionCard(
      title: 'Workspace Overview',
      subtitle: 'Status and metadata from Master control plane',
      icon: Icons.info_outline,
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          CoMetricCard(icon: Icons.tag, label: 'Code', value: w.workspaceCode),
          CoMetricCard(
              icon: Icons.rocket_launch,
              label: 'Status',
              value: w.status.label),
          CoMetricCard(
              icon: Icons.workspace_premium,
              label: 'Plan',
              value: w.subscription.planName.isEmpty
                  ? 'Free'
                  : w.subscription.planName),
          CoMetricCard(
              icon: Icons.mail_outline,
              label: 'Support',
              value: w.supportEmail ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildHealthSection() {
    return CoSectionCard(
      title: 'Cross-Project Analytics',
      subtitle: 'Backend aggregated metrics',
      icon: Icons.analytics_outlined,
      child: _loadingUsers
          ? const Center(child: CircularProgressIndicator())
          : Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                CoMetricCard(
                    icon: Icons.favorite,
                    label: 'Health Score',
                    value: '$_health/100',
                    accent: _health > 80 ? kCoGreen : kCoRed),
                CoMetricCard(
                    icon: Icons.login,
                    label: 'Last Login',
                    value: relativeTimeLabel(_lastLogin),
                    accent: kCoAmber),
                ...?_buildUserStatsCards(),
              ],
            ),
    );
  }

  List<Widget>? _buildUserStatsCards() {
    if (_userCounts.isEmpty) return null;
    final total = _userCounts['total'] ?? 0;
    final staff = _userCounts['staff'] ?? 0;
    final managers = _userCounts['managers'] ?? 0;
    final admins = _userCounts['admins'] ?? 0;
    return [
      CoMetricCard(
        icon: Icons.group,
        label: 'Total',
        value: '$total',
        accent: kCoLabel,
      ),
      const SizedBox(width: 8),
      CoMetricCard(
        icon: Icons.badge,
        label: 'Staff',
        value: '$staff',
        accent: kCoBlue,
      ),
      const SizedBox(width: 8),
      CoMetricCard(
        icon: Icons.workspace_premium,
        label: 'Managers',
        value: '$managers',
        accent: kCoAmber,
      ),
      const SizedBox(width: 8),
      CoMetricCard(
        icon: Icons.admin_panel_settings,
        label: 'Admins',
        value: '$admins',
        accent: kCoGreen,
      ),
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }}
