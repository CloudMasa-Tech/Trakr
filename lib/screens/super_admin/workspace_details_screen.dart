import 'dart:convert';
import 'package:flutter/material.dart';

import '../../control_plane/models/workspace.dart';

import '../../control_plane/services/cross_project_analytics_service.dart';
import '../../control_plane/services/workspace_registry_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class WorkspaceDetailsScreen extends StatefulWidget {
  final String workspaceId;
  final Workspace initial;

  const WorkspaceDetailsScreen({
    super.key,
    required this.workspaceId,
    required this.initial,
  });

  static Future<void> show(
    BuildContext context, {
    required String workspaceId,
    required Workspace initial,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkspaceDetailsScreen(
          workspaceId: workspaceId,
          initial: initial,
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
  bool _loading = false;
  String? _error;

  int _health = 0;
  DateTime? _lastLogin;

  @override
  void initState() {
    super.initState();
    _workspace = widget.initial;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    try {
      final w = await _registry.resolveById(widget.workspaceId);
      final health =
          await _analytics.getWorkspaceHealthScore(widget.workspaceId);
      final login = await _analytics.getLastLoginTime(widget.workspaceId);

      if (!mounted) return;
      setState(() {
        _workspace = w ?? _workspace;
        _health = health;
        _lastLogin = login;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
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
                _buildHealthSection(),
                const SizedBox(height: 24),
                _buildConfigSection(w),
              ],
            ),
          ),
        ),
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
      child: _loading
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
              ],
            ),
    );
  }

  Widget _buildConfigSection(Workspace w) {
    final configMap = w.firebaseConfig.toMap();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(configMap);
    return CoSectionCard(
      title: 'Firebase Configuration',
      subtitle: 'Assigned Project: ${w.firebaseProjectId}',
      icon: Icons.code,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          jsonStr,
          style: const TextStyle(
            color: kCoGreen,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
