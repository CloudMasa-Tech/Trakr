import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../control_plane/models/workspace.dart';
import '../../control_plane/models/workspace_status.dart';
import '../../control_plane/models/workspace_firebase_config.dart';
import '../../control_plane/services/cross_project_analytics_service.dart';
import '../../control_plane/services/workspace_registry_service.dart';
import '../../screens/super_admin/firebase_config_upload_field.dart';
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

  /// Opens a dialog to edit the workspace's Firebase configuration.
  Future<void> _editFirebaseConfig(Workspace workspace) async {
    var currentConfig = workspace.firebaseConfig;
    var confirmed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: AppThemeColors.darkCanvas,
              title: const Text(
                'Edit Firebase Configuration',
                style: TextStyle(color: kCoLabel, fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: FirebaseConfigUploadField(
                    config: currentConfig,
                    confirmed: confirmed,
                    enabled: true,
                    onParsed: (config) {
                      setDialogState(() => currentConfig = config);
                    },
                    onRemove: () {
                      setDialogState(() => currentConfig = const WorkspaceFirebaseConfig(
                        apiKey: '',
                        appId: '',
                        projectId: '',
                        messagingSenderId: '',
                        storageBucket: '',
                        authDomain: '',
                      ));
                    },
                    onConfirmedChanged: (v) {
                      setDialogState(() => confirmed = v);
                    },
                    errorText: _error,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
                ),
                FilledButton(
                  onPressed: (!confirmed || currentConfig.apiKey.trim().isEmpty)
                      ? null
                      : () async {
                          Navigator.of(dialogContext).pop();
                          await _saveFirebaseConfig(workspace.workspaceId, currentConfig);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: kCoAccent,
                    disabledBackgroundColor: kCoBorder,
                  ),
                  child: const Text('Save Configuration',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Saves the updated Firebase configuration to the workspace registry.
  Future<void> _saveFirebaseConfig(
      String workspaceId, WorkspaceFirebaseConfig config) async {
    try {
      await _registry.updateFirebaseConfig(workspaceId, config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: kCoSuccess,
          content: Text('Firebase configuration updated successfully.'),
        ),
      );
      _loadDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kCoDanger,
          content: Text('Failed to update configuration: $e'),
        ),
      );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Firebase Configuration',
            onPressed: () => _editFirebaseConfig(w),
          ),
        ],
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
    final hasGcpDisplayName = w.gcpProjectDisplayName != null &&
        w.gcpProjectDisplayName!.trim().isNotEmpty &&
        w.gcpProjectDisplayName != w.companyName;

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
                    if (hasGcpDisplayName) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.cloud_outlined,
                              color: kCoSubtle, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'GCP Project Display Name: ${w.gcpProjectDisplayName}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kCoSubtle, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ],
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
              CoStatusChip(
                isActive: w.status == WorkspaceStatus.active,
                label: w.status.label,
                colorOverride: w.status == WorkspaceStatus.provisioning ? kCoAmber : null,
              ),
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
          if (w.gcpProjectDisplayName != null &&
              w.gcpProjectDisplayName!.trim().isNotEmpty &&
              w.gcpProjectDisplayName != w.companyName) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.cloud_outlined,
                    color: kCoSubtle, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'GCP Display Name: ${w.gcpProjectDisplayName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kCoSubtle,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
