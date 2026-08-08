import 'package:flutter/material.dart';

import '../../control_plane/models/workspace.dart';
import '../../control_plane/models/workspace_status.dart';
import '../../control_plane/services/cross_project_analytics_service.dart';
import '../../control_plane/services/workspace_deletion_service.dart';
import '../../control_plane/services/workspace_registry_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';
import 'workspace_details_screen.dart';

class WorkspacesModule extends StatefulWidget {
  const WorkspacesModule({super.key});

  @override
  State<WorkspacesModule> createState() => _WorkspacesModuleState();
}

class _WorkspacesModuleState extends State<WorkspacesModule> {
  final _registry = WorkspaceRegistryService();
  final _analytics = CrossProjectAnalyticsService();
  final _platform = PlatformService();
  final _deletion = WorkspaceDeletionService();

  final _searchCtrl = TextEditingController();

  String _statusFilter = 'All';
  String _planFilter = 'All';
  int _page = 0;
  static const int _pageSize = 12;

  // Cache for analytics per workspace
  final Map<String, int> _healthScores = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _viewWorkspace(Workspace workspace) async {
    await WorkspaceDetailsScreen.show(
      context,
      workspaceId: workspace.workspaceId,
      initial: workspace,
    );
  }

  Future<void> _toggleActive(Workspace workspace) async {
    final target = workspace.status != WorkspaceStatus.active;
    final action = target ? 'Activate' : 'Suspend';
    final confirmed = await _confirm(
      title: '$action ${workspace.companyName}?',
      message: target
          ? 'The workspace and its users will regain access to the platform.'
          : 'The workspace will be suspended. This can be reverted at any time.',
      confirmLabel: action,
      destructive: !target,
    );
    if (!confirmed || !mounted) return;
    try {
      if (target) {
        await _registry.activate(workspace.workspaceId);
      } else {
        await _registry.suspend(workspace.workspaceId);
      }

      await _platform.recordActivity(
        type: 'company',
        title: target ? 'Workspace activated' : 'Workspace suspended',
        detail:
            '${workspace.companyName} was ${target ? 'activated' : 'suspended'}.',
      );
      if (!mounted) return;
      _snack('${workspace.companyName} ${target ? 'activated' : 'suspended'}.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update workspace: $e', error: true);
    }
  }

  Future<void> _deleteWorkspace(Workspace workspace) async {
    final confirmed = await _confirm(
      title: 'Delete ${workspace.companyName}?',
      message: 'This permanently deletes the workspace and all of its data — '
          'employees, managers, attendance records, leave requests, QR tokens '
          'and stored files. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final report = await _deletion.deleteWorkspace(workspace);
      await _platform.recordActivity(
        type: 'company',
        title: 'Workspace deleted',
        detail: '${workspace.companyName} was permanently deleted.',
      );
      if (!mounted) return;
      if (report.hasWarnings) {
        _snack(
          '${workspace.companyName} was deleted, but some data could not be '
          'removed.',
          warning: true,
        );
      } else {
        _snack('${workspace.companyName} was permanently deleted.');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Could not delete workspace: $e', error: true);
    }
  }

  List<Workspace> _filtered(List<Workspace> workspaces) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return workspaces.where((w) {
      final matchesStatus =
          _statusFilter == 'All' || w.status.label == _statusFilter;
      final matchesPlan =
          _planFilter == 'All' || w.subscription.planName == _planFilter;
      if (!matchesStatus || !matchesPlan) return false;
      if (query.isEmpty) return true;
      return w.companyName.toLowerCase().contains(query) ||
          w.workspaceCode.toLowerCase().contains(query);
    }).toList();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final color = destructive ? kCoRed : kCoAccent;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCoBorder),
        ),
        title: Text(title,
            style: const TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(message,
            style:
                const TextStyle(color: kCoSubtle, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String message, {bool error = false, bool warning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kCoError : (warning ? kCoAmber : kCoSuccess),
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 16,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: StreamBuilder<List<Workspace>>(
            stream: _registry.streamWorkspaces(),
            builder: (context, snapshot) {
              final workspaces = snapshot.data ?? const <Workspace>[];
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final filtered = _filtered(workspaces);
              final totalPages =
                  (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
              if (_page >= totalPages) {
                _page = totalPages - 1;
              }
              final pageStart = (_page * _pageSize).clamp(0, filtered.length);
              final pageEnd =
                  ((_page + 1) * _pageSize).clamp(0, filtered.length);
              final pageWorkspaces = filtered.sublist(pageStart, pageEnd);

              // Pre-fetch missing analytics for visible page
              for (final w in pageWorkspaces) {
                if (!_healthScores.containsKey(w.workspaceId)) {
                  _analytics.getWorkspaceHealthScore(w.workspaceId).then((v) {
                    if (mounted) {
                      setState(() => _healthScores[w.workspaceId] = v);
                    }
                  });
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(workspaces, filtered.length, loading),
                  const SizedBox(height: 20),
                  _buildToolbar(loading),
                  const SizedBox(height: 14),
                  _buildTable(pageWorkspaces, filtered.length, loading),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<Workspace> workspaces, int shown, bool loading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Workspaces',
          style: TextStyle(
            color: kCoLabel,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${loading ? '…' : workspaces.length} workspaces on the platform. '
          'Search, filter, and manage each tenant workspace directly from Master.',
          style: const TextStyle(color: kCoSubtle, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool loading) {
    return LayoutBuilder(
      builder: (context, c) {
        final search = CoSearchField(
          controller: _searchCtrl,
          hint: 'Search workspaces…',
          onChanged: (_) => setState(() => _page = 0),
        );
        final statusFilter = CoFilterMenu(
          label: 'All statuses',
          options: const [
            'All',
            'Provisioning',
            'Active',
            'Suspended',
            'Decommissioned'
          ],
          value: _statusFilter,
          onChanged: (v) => setState(() {
            _statusFilter = v;
            _page = 0;
          }),
        );
        final planFilter = CoFilterMenu(
          label: 'All plans',
          options: const ['All', 'Free', 'Starter', 'Pro', 'Enterprise'],
          value: _planFilter,
          onChanged: (v) => setState(() {
            _planFilter = v;
            _page = 0;
          }),
        );
        if (c.maxWidth < 760) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(width: 260, child: search),
              statusFilter,
              planFilter,
            ],
          );
        }
        return Row(
          children: [
            search,
            const Spacer(),
            statusFilter,
            const SizedBox(width: 10),
            planFilter,
          ],
        );
      },
    );
  }

  Widget _buildTable(List<Workspace> workspaces, int total, bool loading) {
    return CoSectionCard(
      title: 'All workspaces',
      subtitle: loading
          ? 'Loading workspace directory…'
          : 'Showing ${workspaces.length} of $total workspaces.',
      icon: Icons.apartment_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading && workspaces.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kCoAccent),
                ),
              ),
            )
          else if (workspaces.isEmpty)
            const CoEmptyState(
              icon: Icons.business_center_outlined,
              message: 'No workspaces found.',
            )
          else
            _workspaceTable(workspaces),
          if (!loading && total > _pageSize)
            CoPaginationBar(
              page: _page,
              pageSize: _pageSize,
              totalItems: total,
              canNext: (_page + 1) * _pageSize < total,
              onPageChanged: (p) => setState(() => _page = p),
            ),
        ],
      ),
    );
  }

  Widget _workspaceTable(List<Workspace> workspaces) {
    const labelStyle =
        TextStyle(color: kCoSubtle, fontSize: 11, fontWeight: FontWeight.w700);
    return Column(
      children: [
        const Divider(color: kCoBorder, height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('WORKSPACE', style: labelStyle)),
              Expanded(flex: 2, child: Text('PROJECT ID', style: labelStyle)),
              Expanded(flex: 1, child: Text('HEALTH', style: labelStyle)),
              Expanded(flex: 1, child: Text('PLAN', style: labelStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: labelStyle)),
              Expanded(flex: 2, child: Text('ACTIONS', style: labelStyle)),
            ],
          ),
        ),
        const Divider(color: kCoBorder, height: 1),
        for (var i = 0; i < workspaces.length; i++) ...[
          if (i > 0) const Divider(color: kCoBorder, height: 1),
          _tableRow(workspaces[i]),
        ],
      ],
    );
  }

  Widget _tableRow(Workspace workspace) {
    final health = _healthScores[workspace.workspaceId] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CoCompanyAvatar(
                    name: workspace.companyName, logoUrl: null, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspace.companyName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoLabel,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      Text(
                        workspace.workspaceCode,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kCoSubtle, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              workspace.firebaseProjectId,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Icon(Icons.favorite_rounded,
                    color: health > 90
                        ? kCoGreen
                        : (health > 70 ? kCoAmber : kCoRed),
                    size: 14),
                const SizedBox(width: 4),
                Text(
                  health > 0 ? '$health/100' : '...',
                  style: const TextStyle(
                      color: kCoLabel,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _planChip(workspace.subscription.planName.isEmpty
                  ? 'Free'
                  : workspace.subscription.planName),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CoStatusChip(
                  isActive: workspace.status == WorkspaceStatus.active),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _actionButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View',
                    onTap: () => _viewWorkspace(workspace),
                  ),
                  _actionButton(
                    icon: workspace.status == WorkspaceStatus.active
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    tooltip: workspace.status == WorkspaceStatus.active
                        ? 'Suspend'
                        : 'Activate',
                    color: workspace.status == WorkspaceStatus.active
                        ? kCoAmber
                        : kCoGreen,
                    onTap: () => _toggleActive(workspace),
                  ),
                  _actionButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    color: kCoRed,
                    onTap: () => _deleteWorkspace(workspace),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planChip(String plan) {
    Color color;
    switch (plan) {
      case 'Starter':
        color = kCoBlue;
        break;
      case 'Pro':
        color = kCoCyan;
        break;
      case 'Enterprise':
        color = kCoViolet;
        break;
      default:
        color = kCoGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        plan.isEmpty ? 'Free' : plan,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 18, color: color ?? kCoSubtle),
        ),
      ),
    );
  }
}
