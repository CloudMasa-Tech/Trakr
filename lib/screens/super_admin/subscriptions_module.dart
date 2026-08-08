import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/company.dart';
import '../../services/company_analytics_service.dart';
import '../../services/company_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

const List<String> kPlanOptions = ['Free', 'Starter', 'Pro', 'Enterprise'];
const List<String> kSubscriptionStatusOptions = [
  'active',
  'trial',
  'past_due',
  'canceled',
];
const List<String> kBillingCycleOptions = ['Monthly', 'Annual'];

class SubscriptionsModule extends StatefulWidget {
  const SubscriptionsModule({super.key});

  @override
  State<SubscriptionsModule> createState() => _SubscriptionsModuleState();
}

class _SubscriptionsModuleState extends State<SubscriptionsModule> {
  final _companyService = CompanyService();
  final _analytics = CompanyAnalyticsService();
  final _platform = PlatformService();

  Map<String, String> _adminByCompany = const {};
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _analytics.getCompanyAdminMap().then((map) {
      if (mounted) setState(() => _adminByCompany = map);
    });
  }

  Future<void> _editSubscription(Company company) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _SubscriptionDialog(company: company),
    );
    if (result == null || !mounted) return;
    final old = company;
    try {
      await _companyService.updateCompany(company.id, result);
      await _applyStatsDelta(old, result);
      await _platform.recordActivity(
        type: 'subscription',
        title: 'Subscription updated',
        detail:
            '${company.name} plan changed to ${result['plan']} (${result['billingCycle']}).',
        companyId: company.id,
        companyName: company.name,
      );
      await _platform.recordAudit(
        category: 'Subscription',
        action: 'update',
        targetType: 'company',
        targetId: company.id,
        targetName: company.name,
        changes: result,
      );
      if (!mounted) return;
      _snack('Subscription for ${company.name} updated.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update subscription: $e', error: true);
    }
  }

  Future<void> _applyStatsDelta(
      Company old, Map<String, dynamic> result) async {
    final oldPlan = old.plan;
    final newPlan = result['plan'] as String? ?? oldPlan;
    final oldStatus = old.subscriptionStatus;
    final newStatus = result['subscriptionStatus'] as String? ?? oldStatus;
    final deltas = <String, dynamic>{};
    if (oldPlan != newPlan) {
      _bumpPlan(deltas, oldPlan, -1);
      _bumpPlan(deltas, newPlan, 1);
    }
    if (oldStatus == 'active' && newStatus != 'active') {
      deltas['activeSubscriptions'] = -1;
    } else if (oldStatus != 'active' && newStatus == 'active') {
      deltas['activeSubscriptions'] = 1;
    }
    if (oldStatus == 'trial' && newStatus != 'trial') {
      deltas['trialCompanies'] = -1;
    } else if (oldStatus != 'trial' && newStatus == 'trial') {
      deltas['trialCompanies'] = 1;
    }
    if (deltas.isNotEmpty) {
      await _platform.bumpStats(deltas);
    }
  }

  void _bumpPlan(Map<String, dynamic> deltas, String plan, int delta) {
    switch (plan) {
      case 'Starter':
        deltas['planStarter'] = (deltas['planStarter'] ?? 0) + delta;
      case 'Pro':
        deltas['planPro'] = (deltas['planPro'] ?? 0) + delta;
      case 'Enterprise':
        deltas['planEnterprise'] = (deltas['planEnterprise'] ?? 0) + delta;
      default:
        deltas['planFree'] = (deltas['planFree'] ?? 0) + delta;
    }
  }

  Future<void> _quickAction(
      Company company, Map<String, dynamic> updates, String label) async {
    final confirmed = await _confirm(
      title: '$label — ${company.name}?',
      message: 'Set subscription status to '
          '"${updates['subscriptionStatus']}".',
      confirmLabel: label,
    );
    if (!confirmed || !mounted) return;
    try {
      final old = company;
      await _companyService.updateCompany(company.id, updates);
      await _applyStatsDelta(old, updates);
      await _platform.recordActivity(
        type: 'subscription',
        title: label,
        detail: '${company.name} — ${updates['subscriptionStatus']}.',
        companyId: company.id,
        companyName: company.name,
      );
      await _platform.recordAudit(
        category: 'Subscription',
        action: label.toLowerCase().replaceAll(' ', '_'),
        targetType: 'company',
        targetId: company.id,
        targetName: company.name,
        changes: updates,
      );
      if (!mounted) return;
      _snack('${company.name} marked ${updates['subscriptionStatus']}.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update subscription: $e', error: true);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
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
            style: FilledButton.styleFrom(backgroundColor: kCoAccent),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kCoError : kCoSuccess,
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
          child: StreamBuilder<List<Company>>(
            stream: _companyService.streamAllCompanies(),
            builder: (context, snapshot) {
              final companies = snapshot.data ?? const <Company>[];
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final filtered = companies.where((c) {
                if (_statusFilter == 'All') return true;
                return c.subscriptionStatus == _statusFilter;
              }).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(companies, loading),
                  const SizedBox(height: 20),
                  _buildMetrics(companies, loading),
                  const SizedBox(height: 24),
                  _buildDistribution(companies, loading),
                  const SizedBox(height: 24),
                  _buildTable(filtered, loading),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<Company> companies, bool loading) {
    final onPlan = companies.where((c) => c.plan != 'Free').length;
    return CoPageHeader(
      title: 'Subscriptions',
      subtitle:
          '${loading ? '…' : onPlan} of ${loading ? '…' : companies.length} '
          'companies on a paid plan. Manage plan, billing cycle, and status.',
      actions: [
        CoFilterMenu(
          label: 'All statuses',
          options: const ['All', 'active', 'trial', 'past_due', 'canceled'],
          value: _statusFilter,
          onChanged: (v) => setState(() => _statusFilter = v),
        ),
      ],
    );
  }

  Widget _buildMetrics(List<Company> companies, bool loading) {
    final active =
        companies.where((c) => c.subscriptionStatus == 'active').length;
    final trials =
        companies.where((c) => c.subscriptionStatus == 'trial').length;
    final expiring = companies.where((c) {
      final renewsAt = c.renewsAt;
      return renewsAt != null &&
          renewsAt.isBefore(DateTime.now().add(const Duration(days: 7)));
    }).length;
    final metrics = [
      CoMetricCard(
        icon: Icons.verified_outlined,
        label: 'Active Subscriptions',
        value: loading ? '—' : '$active',
        accent: kCoGreen,
      ),
      CoMetricCard(
        icon: Icons.hourglass_top_rounded,
        label: 'Trial Companies',
        value: loading ? '—' : '$trials',
        accent: kCoAmber,
      ),
      CoMetricCard(
        icon: Icons.event_busy_rounded,
        label: 'Expiring in 7 days',
        value: loading ? '—' : '$expiring',
        accent: kCoOrange,
      ),
      CoMetricCard(
        icon: Icons.workspace_premium_outlined,
        label: 'On Paid Plans',
        value: loading
            ? '—'
            : '${companies.where((c) => c.plan != 'Free').length}',
        accent: kCoCyan,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        const spacing = 12.0;
        final itemWidth = (c.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final m in metrics) SizedBox(width: itemWidth, child: m),
          ],
        );
      },
    );
  }

  Widget _buildDistribution(List<Company> companies, bool loading) {
    final sections = [
      (companies.where((c) => c.plan == 'Free').length, 'Free', kCoGrey),
      (companies.where((c) => c.plan == 'Starter').length, 'Starter', kCoBlue),
      (companies.where((c) => c.plan == 'Pro').length, 'Pro', kCoCyan),
      (
        companies.where((c) => c.plan == 'Enterprise').length,
        'Enterprise',
        kCoViolet
      ),
    ];
    final total = companies.length;
    return CoSectionCard(
      title: 'Plan distribution',
      subtitle: 'Companies by subscription plan.',
      icon: Icons.donut_large_rounded,
      child: loading || total == 0
          ? const CoEmptyState(
              icon: Icons.donut_large_rounded, message: 'No subscription data.')
          : SizedBox(
              height: 160,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: [
                          for (final s in sections)
                            if (s.$1 > 0)
                              PieChartSectionData(
                                value: s.$1.toDouble(),
                                color: s.$3,
                                radius: 40,
                                showTitle: false,
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in sections) ...[
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: s.$3,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  s.$2,
                                  style: const TextStyle(
                                    color: kCoLabel,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${s.$1}',
                                style: const TextStyle(
                                  color: kCoLabel,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTable(List<Company> companies, bool loading) {
    return CoSectionCard(
      title: 'Company subscriptions',
      subtitle: 'Plan, billing cycle, and subscription status per company.',
      icon: Icons.workspace_premium_outlined,
      child: loading && companies.isEmpty
          ? const CoEmptyState(
              icon: Icons.hourglass_empty_rounded, message: 'Loading…')
          : companies.isEmpty
              ? const CoEmptyState(
                  icon: Icons.workspace_premium_outlined,
                  message: 'No companies match this filter.')
              : LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth < 860) return _cards(companies);
                    return _table(companies);
                  },
                ),
    );
  }

  Widget _table(List<Company> companies) {
    const labelStyle =
        TextStyle(color: kCoSubtle, fontSize: 11, fontWeight: FontWeight.w700);
    return Column(
      children: [
        const Divider(color: kCoBorder, height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('COMPANY', style: labelStyle)),
              Expanded(flex: 1, child: Text('PLAN', style: labelStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: labelStyle)),
              Expanded(flex: 1, child: Text('CYCLE', style: labelStyle)),
              Expanded(flex: 2, child: Text('RENEWS', style: labelStyle)),
              Expanded(flex: 2, child: Text('ACTIONS', style: labelStyle)),
            ],
          ),
        ),
        const Divider(color: kCoBorder, height: 1),
        for (var i = 0; i < companies.length; i++) ...[
          if (i > 0) const Divider(color: kCoBorder, height: 1),
          _tableRow(companies[i]),
        ],
      ],
    );
  }

  Widget _tableRow(Company company) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CoCompanyAvatar(
                    name: company.name, logoUrl: company.logoUrl, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoLabel,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _adminByCompany[company.id] ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: kCoSubtle, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 1, child: _planChip(company.plan)),
          Expanded(flex: 1, child: _statusChip(company.subscriptionStatus)),
          Expanded(
            flex: 1,
            child: Text(
              company.billingCycle,
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              company.renewsAt == null
                  ? '—'
                  : DateFormat('dd MMM yyyy').format(company.renewsAt!),
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                if (company.subscriptionStatus != 'past_due')
                  _quickButton(
                    icon: Icons.warning_amber_rounded,
                    tooltip: 'Mark past due',
                    color: kCoOrange,
                    onTap: () => _quickAction(company,
                        {'subscriptionStatus': 'past_due'}, 'Mark past due'),
                  ),
                if (company.subscriptionStatus != 'canceled')
                  _quickButton(
                    icon: Icons.cancel_outlined,
                    tooltip: 'Cancel subscription',
                    color: kCoRed,
                    onTap: () => _quickAction(
                        company,
                        {'subscriptionStatus': 'canceled'},
                        'Cancel subscription'),
                  ),
                if (company.subscriptionStatus != 'active')
                  _quickButton(
                    icon: Icons.play_circle_outline_rounded,
                    tooltip: 'Set active',
                    color: kCoGreen,
                    onTap: () => _quickAction(company,
                        {'subscriptionStatus': 'active'}, 'Set active'),
                  ),
                IconButton(
                  onPressed: () => _editSubscription(company),
                  icon: const Icon(Icons.edit_outlined,
                      color: kCoSubtle, size: 19),
                  tooltip: 'Edit subscription',
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color color,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _cards(List<Company> companies) {
    return Column(
      children: [
        for (var i = 0; i < companies.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _card(companies[i]),
        ],
      ],
    );
  }

  Widget _card(Company company) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoCompanyAvatar(
                  name: company.name, logoUrl: company.logoUrl, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  company.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kCoLabel,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5),
                ),
              ),
              _planChip(company.plan),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statusChip(company.subscriptionStatus),
              _meta('Cycle: ${company.billingCycle}'),
              _meta(
                company.renewsAt == null
                    ? 'Renews: —'
                    : 'Renews: ${DateFormat('dd MMM yyyy').format(company.renewsAt!)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _editSubscription(company),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit subscription'),
              style: TextButton.styleFrom(
                foregroundColor: kCoAccent,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String text) {
    return Text(text, style: const TextStyle(color: kCoSubtle, fontSize: 12));
  }

  Widget _planChip(String plan) {
    final (color, label) = switch (plan) {
      'Starter' => (kCoBlue, 'Starter'),
      'Pro' => (kCoCyan, 'Pro'),
      'Enterprise' => (kCoViolet, 'Enterprise'),
      _ => (kCoGrey, 'Free'),
    };
    return _chip(color, label);
  }

  Widget _statusChip(String status) {
    final (color, label) = switch (status) {
      'trial' => (kCoAmber, 'Trial'),
      'past_due' => (kCoOrange, 'Past due'),
      'canceled' => (kCoRed, 'Canceled'),
      _ => (kCoGreen, 'Active'),
    };
    return _chip(color, label);
  }

  Widget _chip(Color color, String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SubscriptionDialog extends StatefulWidget {
  final Company company;

  const _SubscriptionDialog({required this.company});

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late String _plan;
  late String _status;
  late String _cycle;
  DateTime? _renewsAt;

  @override
  void initState() {
    super.initState();
    _plan = widget.company.plan;
    _status = widget.company.subscriptionStatus;
    _cycle = widget.company.billingCycle;
    _renewsAt = widget.company.renewsAt;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kCoBorder),
      ),
      title: Text('Subscription — ${widget.company.name}',
          style: const TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dropdown('Plan', kPlanOptions, _plan, (v) => _plan = v!),
            const SizedBox(height: 12),
            _dropdown('Status', kSubscriptionStatusOptions, _status,
                (v) => _status = v!),
            const SizedBox(height: 12),
            _dropdown('Billing cycle', kBillingCycleOptions, _cycle,
                (v) => _cycle = v!),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text('Renewal date',
                      style: TextStyle(
                          color: kCoLabel,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                TextButton.icon(
                  onPressed: () => _pickRenewalDate(),
                  icon: const Icon(Icons.event_rounded, size: 16),
                  label: Text(
                    _renewsAt == null
                        ? 'Select date'
                        : DateFormat('dd MMM yyyy').format(_renewsAt!),
                    style: const TextStyle(color: kCoAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(<String, dynamic>{
              'plan': _plan,
              'subscriptionStatus': _status,
              'billingCycle': _cycle,
              if (_renewsAt != null) 'renewsAt': _renewsAt!.toUtc(),
            });
          },
          style: FilledButton.styleFrom(backgroundColor: kCoAccent),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _dropdown(String label, List<String> options, String value,
      ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCoBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: value,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kCoSubtle),
              items: options
                  .map((o) => DropdownMenuItem<String>(
                        value: o,
                        child: Text(o,
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickRenewalDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _renewsAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kCoAccent,
            surface: AppThemeColors.darkSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _renewsAt = picked);
    }
  }
}
