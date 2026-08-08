import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../control_plane/models/workspace.dart';
import '../../control_plane/services/workspace_registry_service.dart';
import '../../models/platform_models.dart';
import '../../services/platform_service.dart';
import '../../theme/portal_palette.dart';
import 'workspace_details_screen.dart';
import 'dashboard_states.dart';
import 'portal_widgets.dart';

enum _BootStatus { loading, loaded, error }

class PlatformDashboardModule extends StatefulWidget {
  const PlatformDashboardModule({super.key});

  @override
  State<PlatformDashboardModule> createState() =>
      _PlatformDashboardModuleState();
}

class _PlatformDashboardModuleState extends State<PlatformDashboardModule> {
  static const Duration _bootstrapTimeout = Duration(seconds: 20);

  final _registry = WorkspaceRegistryService();
  final _platform = PlatformService();

  _BootStatus _boot = _BootStatus.loading;
  String? _bootError;

  bool _reconciling = false;

  // First-load seeds so the live streams below never flash a spinner or
  // render empty sections after the bootstrap has already fetched data.
  PlatformStats _seedStats = const PlatformStats(totalCompanies: -1);
  List<Workspace> _seedWorkspaces = const [];
  List<PlatformActivityEvent> _seedActivity = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Fetches stats, companies, activity, and the admin-name map in parallel,
  /// bounded by a single timeout. Any failure surfaces the full-page error
  /// state instead of a never-ending spinner.
  Future<void> _bootstrap() async {
    setState(() {
      _boot = _BootStatus.loading;
      _bootError = null;
    });
    try {
      final results = await Future.wait<Object>([
        _traced(
          'READ platformStats/dashboard',
          _platform.getStats(),
        ),
        _traced(
          'READ workspaces (streamWorkspaces)',
          _registry.streamWorkspaces().timeout(_bootstrapTimeout).first,
        ),
        _traced(
          'READ activity_logs (streamActivity)',
          _platform.streamActivity(limit: 10).timeout(_bootstrapTimeout).first,
        ),
      ]).timeout(_bootstrapTimeout);
      if (!mounted) return;
      setState(() {
        _seedStats = results[0] as PlatformStats;
        _seedWorkspaces = results[1] as List<Workspace>;
        _seedActivity = results[2] as List<PlatformActivityEvent>;
        _boot = _BootStatus.loaded;
      });
    } catch (e) {
      debugPrint('[Dashboard.bootstrap] FAILED: $e');
      if (!mounted) return;
      setState(() {
        _boot = _BootStatus.error;
        _bootError = '$e';
      });
    }
  }

  /// Logs the request + outcome of each parallel bootstrap call so the exact
  /// failing collection/document is visible in the console.
  Future<T> _traced<T>(String label, Future<T> future) async {
    debugPrint('[Dashboard.bootstrap] $label → request');
    try {
      final value = await future;
      debugPrint('[Dashboard.bootstrap] $label → SUCCESS');
      return value;
    } catch (e) {
      debugPrint('[Dashboard.bootstrap] $label → FAILED: $e');
      rethrow;
    }
  }

  /// Forces the live streams to re-subscribe by rebuilding this widget's
  /// subtree (each `stream()` call returns a fresh Firestore stream).
  void _retryStreams() => setState(() {});

  Future<void> _refreshStats() async {
    setState(() => _reconciling = true);
    try {
      await _platform.reconcileStats().timeout(_bootstrapTimeout);
      await _platform.recordActivity(
        type: 'stats',
        title: 'Platform statistics refreshed',
        detail: 'All aggregated counters were recomputed from source data.',
      );
      await _platform.recordAudit(
        category: 'Platform',
        action: 'refresh_stats',
        targetType: 'platform',
        targetName: 'PlatformStats',
      );
      if (!mounted) return;
      _snack('Platform statistics refreshed.');
    } on TimeoutException {
      if (!mounted) return;
      _snack('Refresh timed out. Statistics may be stale.', error: true);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not refresh statistics: $e', error: true);
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kCoError : kCoSuccess,
        content: Text(message),
      ),
    );
  }

  Future<void> _viewWorkspace(Workspace workspace) async {
    await WorkspaceDetailsScreen.show(
      context,
      workspaceId: workspace.workspaceId,
      initial: workspace,
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_boot) {
      _BootStatus.loading => const DashboardSkeleton(),
      _BootStatus.error => DashboardErrorState(
          message: _bootError,
          onRetry: _bootstrap,
        ),
      _BootStatus.loaded => _buildLoaded(context),
    };
  }

  Widget _buildLoaded(BuildContext context) {
    final palette = PortalPalette.of(context);
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
          child: StreamBuilder<PlatformStats>(
            stream: _platform.streamStats(),
            initialData: _seedStats,
            builder: (context, statsSnap) {
              final stats = statsSnap.data ?? _seedStats;
              final statsLoading = stats.totalCompanies < 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CoPageHeader(
                    title: 'Platform overview',
                    subtitle: 'Companies, users, revenue, and activity across '
                        'the entire TRAKR platform.',
                    actions: [
                      FilledButton.icon(
                        onPressed: _reconciling ? null : _refreshStats,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        icon: _reconciling
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kCoWhite,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                            _reconciling ? 'Refreshing…' : 'Refresh stats'),
                      ),
                    ],
                  ),
                  if (statsSnap.hasError) ...[
                    const SizedBox(height: 14),
                    SectionErrorState(
                      message: 'Live stats updates are unavailable. '
                          'Showing the last loaded data.',
                      onRetry: _retryStreams,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildMetrics(stats, statsLoading),
                  const SizedBox(height: 24),
                  _buildCharts(stats, statsLoading),
                  const SizedBox(height: 24),
                  _buildBottomSections(stats, statsLoading),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMetrics(PlatformStats stats, bool loading) {
    String value(dynamic v) => loading ? '—' : '$v';
    final metrics = [
      CoMetricCard(
        icon: Icons.apartment_rounded,
        label: 'Total Companies',
        value: value(stats.totalCompanies),
      ),
      CoMetricCard(
        icon: Icons.check_circle_outline_rounded,
        label: 'Active Companies',
        value: value(stats.activeCompanies),
        accent: kCoGreen,
      ),
      CoMetricCard(
        icon: Icons.group_rounded,
        label: 'Total Users',
        value: value(stats.totalUsers),
        accent: kCoBlue,
      ),
      CoMetricCard(
        icon: Icons.waving_hand_outlined,
        label: 'Active Users Today',
        value: value(stats.activeUsersToday),
        accent: kCoAmber,
      ),
      CoMetricCard(
        icon: Icons.payments_outlined,
        label: 'Monthly Revenue',
        value: loading ? '—' : coMoney(stats.monthlyRevenue, 'USD'),
        accent: kCoCyan,
      ),
      CoMetricCard(
        icon: Icons.support_agent_outlined,
        label: 'Open Tickets',
        value: value(stats.openTickets),
        accent: kCoViolet,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 1100 ? 6 : (c.maxWidth >= 760 ? 3 : 2);
        const spacing = 12.0;
        final itemWidth = (c.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(width: itemWidth, child: metric),
          ],
        );
      },
    );
  }

  Widget _buildCharts(PlatformStats stats, bool loading) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCompanyGrowth(stats, loading),
              const SizedBox(height: 18),
              _buildRevenueTrend(stats, loading),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildCompanyGrowth(stats, loading)),
            const SizedBox(width: 18),
            Expanded(child: _buildRevenueTrend(stats, loading)),
          ],
        );
      },
    );
  }

  List<({String key, String label})> _lastMonths(int count) {
    final now = DateTime.now();
    final list = <({String key, String label})>[];
    for (var i = count - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      list.add((
        key: '${date.year}-${date.month.toString().padLeft(2, '0')}',
        label: DateFormat('MMM').format(date),
      ));
    }
    return list;
  }

  Widget _buildCompanyGrowth(PlatformStats stats, bool loading) {
    final months = _lastMonths(6);
    final maxCount = months.fold<int>(1, (acc, m) {
      final c = stats.companiesByMonth[m.key] ?? 0;
      return c > acc ? c : acc;
    });
    return CoSectionCard(
      title: 'Company growth',
      subtitle: 'New companies onboarded in the last 6 months.',
      icon: Icons.trending_up_rounded,
      child: Builder(
        builder: (context) {
          final palette = PortalPalette.of(context);
          return loading
              ? const CoInlineLoading()
              : SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final month in months)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Column(
                              children: [
                                Text(
                                  '${stats.companiesByMonth[month.key] ?? 0}',
                                  style: TextStyle(
                                    color: palette.subtle,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor:
                                          ((stats.companiesByMonth[month.key] ??
                                                      0) /
                                                  maxCount)
                                              .clamp(0.06, 1.0)
                                              .toDouble(),
                                      widthFactor: 1,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              palette.accent,
                                              palette.hero,
                                            ],
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                          ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(6),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  month.label,
                                  style: TextStyle(
                                      color: palette.subtle, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
        },
      ),
    );
  }

  Widget _buildRevenueTrend(PlatformStats stats, bool loading) {
    final months = _lastMonths(6);
    final maxRevenue = months.fold<double>(1, (acc, m) {
      final r = stats.revenueByMonth[m.key] ?? 0;
      return r > acc ? r : acc;
    });
    return CoSectionCard(
      title: 'Monthly revenue',
      subtitle: 'Revenue recognized in the last 6 months.',
      icon: Icons.attach_money_rounded,
      child: Builder(
        builder: (context) {
          final palette = PortalPalette.of(context);
          return loading
              ? const CoInlineLoading()
              : SizedBox(
                  height: 160,
                  child: months
                          .every((m) => (stats.revenueByMonth[m.key] ?? 0) <= 0)
                      ? const CoEmptyState(
                          icon: Icons.payments_outlined,
                          message: 'No revenue recorded yet.',
                        )
                      : BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: maxRevenue,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: palette.border,
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(enabled: true),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 26,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= months.length) {
                                      return const SizedBox();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        months[i].label,
                                        style: TextStyle(
                                          color: palette.subtle,
                                          fontSize: 10,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: List.generate(months.length, (i) {
                              final revenue =
                                  stats.revenueByMonth[months[i].key] ?? 0;
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: revenue,
                                    color: palette.hero,
                                    width: 14,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                );
        },
      ),
    );
  }

  Widget _buildPlanDonut(PlatformStats stats, bool loading) {
    final sections = [
      (stats.planFree, 'Free', kCoGrey),
      (stats.planStarter, 'Starter', kCoBlue),
      (stats.planPro, 'Pro', kCoCyan),
      (stats.planEnterprise, 'Enterprise', kCoViolet),
    ];
    final total = sections.fold<int>(0, (acc, s) => acc + s.$1);
    return CoSectionCard(
      title: 'Plan distribution',
      subtitle: 'Companies by subscription plan.',
      icon: Icons.donut_large_rounded,
      child: Builder(
        builder: (context) {
          final palette = PortalPalette.of(context);
          return loading || total == 0
              ? const CoEmptyState(
                  icon: Icons.donut_large_rounded,
                  message: 'No subscription data.',
                )
              : SizedBox(
                  height: 170,
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
                                    radius: 42,
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
                                      style: TextStyle(
                                        color: palette.label,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${s.$1}',
                                    style: TextStyle(
                                      color: palette.label,
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
                );
        },
      ),
    );
  }

  Widget _buildBottomSections(PlatformStats stats, bool loading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final planDonut = _buildPlanDonut(stats, loading);
            if (c.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  planDonut,
                  const SizedBox(height: 18),
                  _buildRecentlyOnboarded(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: planDonut),
                const SizedBox(width: 18),
                Expanded(child: _buildRecentlyOnboarded()),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _buildRecentActivity(),
      ],
    );
  }

  Widget _buildRecentlyOnboarded() {
    return CoSectionCard(
      title: 'Recently onboarded companies',
      subtitle: 'Latest client companies added to the platform.',
      icon: Icons.rocket_launch_outlined,
      child: StreamBuilder<List<Workspace>>(
        stream: _registry.streamWorkspaces(),
        initialData: _seedWorkspaces,
        builder: (context, snapshot) {
          final palette = PortalPalette.of(context);
          if (snapshot.hasError) {
            return SectionErrorState(
              message: 'Could not load the company list.',
              onRetry: _retryStreams,
            );
          }
          final workspaces = snapshot.data ?? _seedWorkspaces;
          final loading = snapshot.connectionState == ConnectionState.waiting;
          if (loading && workspaces.isEmpty) return const CoInlineLoading();
          if (workspaces.isEmpty) {
            return const CoEmptyState(
              icon: Icons.business_center_outlined,
              message: 'No companies onboarded yet.',
            );
          }
          final recent = workspaces.take(5).toList();
          return Column(
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0) Divider(color: palette.border, height: 1),
                InkWell(
                  onTap: () => _viewWorkspace(recent[i]),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                    child: Row(
                      children: [
                        CoCompanyAvatar(
                          name: recent[i].companyName,
                          logoUrl: null,
                          size: 34,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recent[i].companyName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.label,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                recent[i].supportEmail ?? '—',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: palette.subtle, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          recent[i].createdAt == null
                              ? '—'
                              : DateFormat('dd MMM')
                                  .format(recent[i].createdAt!),
                          style: TextStyle(
                              color: palette.subtle,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecentActivity() {
    return CoSectionCard(
      title: 'Recent activity',
      subtitle: 'Latest Super Admin platform actions.',
      icon: Icons.history_rounded,
      child: StreamBuilder<List<PlatformActivityEvent>>(
        stream: _platform.streamActivity(limit: 10),
        initialData: _seedActivity,
        builder: (context, snapshot) {
          final palette = PortalPalette.of(context);
          if (snapshot.hasError) {
            return SectionErrorState(
              message: 'Could not load the activity feed.',
              onRetry: _retryStreams,
            );
          }
          final events = snapshot.data ?? _seedActivity;
          if (events.isEmpty) {
            return const CoEmptyState(
              icon: Icons.history_rounded,
              message: 'No platform activity yet.',
            );
          }
          return Column(
            children: [
              for (var i = 0; i < events.length; i++) ...[
                if (i > 0) Divider(color: palette.border, height: 1),
                _activityRow(palette, events[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _activityRow(PortalPalette palette, PlatformActivityEvent event) {
    final color = switch (event.type) {
      'company' => kCoBlue,
      'subscription' => kCoCyan,
      'billing' => kCoGreen,
      'security' => kCoRed,
      'support' => kCoViolet,
      _ => palette.accent,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.bolt_rounded, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.label,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (event.companyName != null &&
                    event.companyName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.companyName!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.subtle, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            relativeTimeLabel(event.timestamp),
            style: TextStyle(
              color: palette.subtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
