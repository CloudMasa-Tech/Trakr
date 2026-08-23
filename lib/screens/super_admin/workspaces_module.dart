import 'package:flutter/material.dart';

import '../../control_plane/models/workspace.dart';
import '../../control_plane/models/workspace_provision_request.dart';
import '../../control_plane/models/workspace_status.dart';
import '../../control_plane/services/cross_project_analytics_service.dart';
import '../../control_plane/services/workspace_deletion_service.dart';
import '../../control_plane/services/workspace_provisioning_client_service.dart';
import '../../control_plane/services/workspace_registry_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';
import 'workspace_details_screen.dart';
import 'workspace_provisioning_progress_modal.dart';

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
  final _provisioningClient = WorkspaceProvisioningClientService();

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
    // First confirmation - basic intent
    final firstConfirmed = await _confirm(
      title: 'Delete ${workspace.companyName}?',
      message: 'This will permanently delete the workspace and ALL its data — '
          'employees, managers, attendance records, leave requests, QR tokens, '
          'stored files, and the entire Firebase/GCP project. '
          'This action is IRREVERSIBLE and cannot be undone.',
      confirmLabel: 'I understand, proceed',
      destructive: true,
    );
    if (!firstConfirmed || !mounted) return;

    // Second confirmation - require typing DELETE
    final secondConfirmed = await _confirmDeleteDialog(workspace);
    if (!secondConfirmed || !mounted) return;

    // Third confirmation - final warning
    final thirdConfirmed = await _confirm(
      title: 'FINAL CONFIRMATION',
      message: 'This will IMMEDIATELY and PERMANENTLY:\n'
          '• Delete the Firebase/GCP project (${workspace.firebaseConfig.projectId})\n'
          '• Delete all workspace data in Firestore\n'
          '• Delete the project allocation\n'
          '• Block this Project ID for 30 days (Google grace period)\n\n'
          'Type "DELETE" to confirm you understand this is irreversible.',
      confirmLabel: 'DELETE',
      destructive: true,
      requireTextInput: 'DELETE',
    );
    if (!thirdConfirmed || !mounted) return;

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

  Future<void> _retryProvisioning(Workspace workspace) async {
    final confirmed = await _confirm(
      title: 'Retry provisioning for ${workspace.companyName}?',
      message: 'This will resume provisioning for the workspace using the '
          'existing Firebase project (${workspace.firebaseProjectId}). '
          'The Company Admin invite email will be re-sent if it failed previously.',
      confirmLabel: 'Retry',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    try {
      final request = WorkspaceProvisionRequest(
        workspaceName: workspace.workspaceCode,
        companyName: workspace.companyName,
        companyPhone: workspace.companyPhone ?? '',
        companyAddress: workspace.companyAddress,
        industry: workspace.industry ?? '',
        companyAdminEmail: workspace.adminEmail ?? '',
        existingWorkspaceId: workspace.workspaceId,
      );
      final result = await WorkspaceProvisioningProgressModal.show(
        context,
        request: request,
        initialLogId: WorkspaceProvisioningProgressModal.generateLogId(),
        provisioningClient: _provisioningClient,
      );

      if (!mounted) return;
      if (result != null) {
        _snack('Provisioning completed for ${workspace.companyName}.');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Provisioning failed: $e', error: true);
    }
  }

  Future<void> _editWorkspace(Workspace workspace) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: workspace.companyName);
    final phone = TextEditingController(text: workspace.companyPhone ?? '');
    final address = TextEditingController(text: workspace.companyAddress ?? '');
    final industry = TextEditingController(text: workspace.industry ?? '');
    final adminName = TextEditingController(text: workspace.adminName ?? '');
    final adminEmail = TextEditingController(text: workspace.adminEmail ?? '');
    final supportEmail = TextEditingController(text: workspace.supportEmail ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCoBorder),
        ),
        title: Text('Edit ${workspace.companyName}',
            style: const TextStyle(color: kCoLabel, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _workspaceEditField(name, 'Company name', required: true),
                  _workspaceEditField(phone, 'Company phone', required: true),
                  _workspaceEditField(address, 'Company address', maxLines: 2),
                  _workspaceEditField(industry, 'Industry', required: true),
                  _workspaceEditField(adminName, 'Admin name'),
                  _workspaceEditField(adminEmail, 'Admin email', keyboardType: TextInputType.emailAddress),
                  _workspaceEditField(supportEmail, 'Support email', keyboardType: TextInputType.emailAddress),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: kCoAccent),
            child: const Text('Save changes'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      name.dispose();
      phone.dispose();
      address.dispose();
      industry.dispose();
      adminName.dispose();
      adminEmail.dispose();
      supportEmail.dispose();
      return;
    }

    try {
      await _registry.updateDetails(workspace.workspaceId, {
        'companyName': name.text.trim(),
        'companyPhone': phone.text.trim(),
        'companyAddress': address.text.trim(),
        'industry': industry.text.trim(),
        'adminName': adminName.text.trim(),
        'adminEmail': adminEmail.text.trim().toLowerCase(),
        'supportEmail': supportEmail.text.trim().toLowerCase(),
      });
      if (mounted) _snack('Workspace details updated.');
    } catch (e) {
      if (mounted) _snack('Could not update workspace: $e', error: true);
    } finally {
      name.dispose();
      phone.dispose();
      address.dispose();
      industry.dispose();
      adminName.dispose();
      adminEmail.dispose();
      supportEmail.dispose();
    }
  }

  Widget _workspaceEditField(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: kCoLabel),
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null
            : null,
      ),
    );
  }


  /// Shows a confirmation dialog that requires typing "DELETE" to proceed
  Future<bool> _confirmDeleteDialog(Workspace workspace) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'Confirm Deletion',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete the Firebase/GCP project:\n'
                '${workspace.firebaseConfig.projectId}\n\n'
                'And all associated data. This cannot be undone.\n\n'
                'The project ID will be blocked for 30 days '
                '(Google grace period).',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'Type "DELETE" to confirm:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'DELETE',
                  hintText: 'Type DELETE to confirm',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != 'DELETE') {
                    return 'You must type exactly "DELETE"';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    ) ?? false;
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
    String? requireTextInput,
  }) async {
    final color = destructive ? kCoRed : kCoAccent;
    
    if (requireTextInput != null) {
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();
      
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppThemeColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: kCoBorder),
          ),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.red, fontWeight: FontWeight.w800, fontSize: 17)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style:
                        const TextStyle(color: kCoSubtle, fontSize: 14, height: 1.5)),
                const SizedBox(height: 16),
                Text(
                  'Type "$requireTextInput" to confirm:',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'DELETE',
                    hintText: 'Type DELETE to confirm',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value != requireTextInput) {
                      return 'You must type exactly "$requireTextInput"';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(requireTextInput),
            ),
          ],
        ),
      );
      return result == true;
    }
    
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
                  _buildTable(pageWorkspaces, filtered, loading),
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

  Widget _buildTable(List<Workspace> pageWorkspaces, List<Workspace> allFilteredWorkspaces, bool loading) {
    return CoSectionCard(
      title: 'All workspaces',
      subtitle: loading
          ? 'Loading workspace directory…'
          : 'Showing ${pageWorkspaces.length} of ${allFilteredWorkspaces.length} workspaces.',
      icon: Icons.apartment_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading && pageWorkspaces.isEmpty)
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
else if (pageWorkspaces.isEmpty)
            const CoEmptyState(
              icon: Icons.business_center_outlined,
              message: 'No workspaces found.',
            )
          else
            _workspaceTable(pageWorkspaces, allFilteredWorkspaces),
        if (!loading && allFilteredWorkspaces.length > _pageSize)
          CoPaginationBar(
            page: _page,
            pageSize: _pageSize,
            totalItems: allFilteredWorkspaces.length,
            canNext: (_page + 1) * _pageSize < allFilteredWorkspaces.length,
            onPageChanged: (p) => setState(() => _page = p),
          ),
        ],
      ),
    );
  }

  Widget _workspaceTable(List<Workspace> pageWorkspaces, List<Workspace> allWorkspaces) {
    const labelStyle =
        TextStyle(color: kCoSubtle, fontSize: 11, fontWeight: FontWeight.w700);
    // Check if ANY workspace (across all pages) is unverified to show a warning banner.
    // Exclude workspaces still being provisioned (configuring) or not yet started (pending)
    // since those haven't had a chance to complete GCP verification yet.
    final hasUnverified = allWorkspaces.any((w) =>
        !w.gcpProjectVerified &&
        w.onboardingStatus != WorkspaceOnboardingStatus.configuring &&
        w.onboardingStatus != WorkspaceOnboardingStatus.pending);
    return Column(
      children: [
        if (hasUnverified) _buildUnverifiedWarningBanner(allWorkspaces),
        const Divider(color: kCoBorder, height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('WORKSPACE', style: labelStyle)),
              Expanded(flex: 2, child: Text('PROJECT ID', style: labelStyle)),
              Expanded(flex: 1, child: Text('GCP VERIFIED', style: labelStyle)),
              Expanded(flex: 1, child: Text('HEALTH', style: labelStyle)),
              Expanded(flex: 1, child: Text('PLAN', style: labelStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: labelStyle)),
              Expanded(flex: 2, child: Text('ACTIONS', style: labelStyle)),
            ],
          ),
        ),
        const Divider(color: kCoBorder, height: 1),
        for (var i = 0; i < pageWorkspaces.length; i++) ...[
          if (i > 0) const Divider(color: kCoBorder, height: 1),
          _tableRow(pageWorkspaces[i]),
        ],
      ],
    );
  }

  /// Health badge for the HEALTH column, styled like the Verified badge in
  /// the GCP VERIFIED column.
  Widget _healthChip(WorkspaceHealth health) {
    final (color, icon) = switch (health) {
      WorkspaceHealth.healthy => (kCoGreen, Icons.check_circle_rounded),
      WorkspaceHealth.provisioning => (kCoCyan, Icons.autorenew_rounded),
      WorkspaceHealth.unhealthy => (kCoDanger, Icons.error_outline_rounded),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            health.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnverifiedWarningBanner(List<Workspace> workspaces) {    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCoAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCoAmber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: kCoAmber, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unverified GCP Projects Detected',
                  style: TextStyle(
                    color: kCoAmber,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'One or more workspaces are missing GCP project verification. '
                  'This means the workspace record exists in Firestore but the corresponding '
                  'GCP project was never confirmed as created. These "phantom" workspaces '
                  'may cause issues if used. Run the cleanup script to identify and resolve them.',
                  style: TextStyle(color: kCoSubtle, fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kCoAmber,
              foregroundColor: kCoWhite,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => _showUnverifiedDetails(workspaces),
            child: const Text('View Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showUnverifiedDetails(List<Workspace> workspaces) {
    final unverified = workspaces.where((w) =>
        !w.gcpProjectVerified &&
        w.onboardingStatus != WorkspaceOnboardingStatus.configuring &&
        w.onboardingStatus != WorkspaceOnboardingStatus.pending).toList();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCoBorder),
        ),
        title: const Text(
          'Unverified Workspaces',
          style: TextStyle(color: kCoLabel, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 600,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: unverified.length,
            separatorBuilder: (_, __) => const Divider(color: kCoBorder),
            itemBuilder: (_, index) {
              final w = unverified[index];
              return ListTile(
                dense: true,
                leading: CoCompanyAvatar(name: w.companyName, logoUrl: null, size: 30),
                title: Text(w.companyName, style: const TextStyle(color: kCoLabel, fontWeight: FontWeight.w700)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Code: ${w.workspaceCode}', style: const TextStyle(color: kCoSubtle, fontSize: 11)),
                    Text('Project ID: ${w.firebaseProjectId}', style: const TextStyle(color: kCoSubtle, fontSize: 11)),
                    if (w.gcpProjectDisplayName != null && w.gcpProjectDisplayName!.isNotEmpty)
                      Text('GCP Display Name: ${w.gcpProjectDisplayName}', style: const TextStyle(color: kCoSubtle, fontSize: 11)),
                    const Text('GCP Project Verified: NO', style: TextStyle(color: kCoRed, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: kCoSubtle)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kCoAccent),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // TODO: Could add a "Run cleanup" action here
            },
            child: const Text('Run Cleanup Script', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(Workspace workspace) {
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
            child: Row(
              children: [
                if (workspace.firebaseConfigured) ...[
                  const Icon(Icons.check_circle_rounded,
                      color: kCoGreen, size: 14),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    workspace.firebaseProjectId.isEmpty
                        ? 'Not configured'
                        : workspace.firebaseProjectId,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: workspace.firebaseConfigured
                          ? kCoLabel
                          : kCoSubtle,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  workspace.gcpProjectVerified
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  color: workspace.gcpProjectVerified ? kCoGreen : kCoAmber,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    workspace.gcpProjectVerified ? 'Verified' : 'Unverified',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: workspace.gcpProjectVerified ? kCoGreen : kCoAmber,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _healthChip(workspace.health),
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
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit workspace',
                    color: kCoCyan,
                    onTap: () => _editWorkspace(workspace),
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
                  if (workspace.onboardingStatus == WorkspaceOnboardingStatus.configuring ||
                      workspace.onboardingStatus == WorkspaceOnboardingStatus.failed)
                    _actionButton(
                      icon: Icons.refresh_rounded,
                      tooltip: workspace.onboardingStatus == WorkspaceOnboardingStatus.configuring
                          ? 'Continue provisioning'
                          : 'Retry provisioning',
                      color: kCoAccent,
                      onTap: () => _retryProvisioning(workspace),
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
