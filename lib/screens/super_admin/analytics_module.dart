import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/company.dart';
import '../../services/company_analytics_service.dart';
import '../../services/company_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class AnalyticsModule extends StatefulWidget {
  const AnalyticsModule({super.key});

  @override
  State<AnalyticsModule> createState() => _AnalyticsModuleState();
}

class _AnalyticsModuleState extends State<AnalyticsModule> {
  final _companyService = CompanyService();
  final _analytics = CompanyAnalyticsService();

  int _totalUsers = 0;
  int _totalAdmins = 0;
  int _totalStaff = 0;
  int _totalManagers = 0;
  bool _loading = true;
  Map<String, int> _usersByCompany = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _analytics.getTotalUserCount(),
      _analytics.getTotalCompanyAdminCount(),
      _analytics.getStaffCountTotal(),
      _analytics.getManagerCountTotal(),
      _analytics.getUserCountByCompany(),
    ]);
    if (!mounted) return;
    setState(() {
      _totalUsers = results[0] as int;
      _totalAdmins = results[1] as int;
      _totalStaff = results[2] as int;
      _totalManagers = results[3] as int;
      _usersByCompany = results[4] as Map<String, int>;
      _loading = false;
    });
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
              final companiesLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(companies, companiesLoading),
                  const SizedBox(height: 20),
                  _buildMetrics(companies, companiesLoading),
                  const SizedBox(height: 24),
                  _buildCharts(companies, companiesLoading),
                  const SizedBox(height: 18),
                  _buildDistribution(companies),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<Company> companies, bool loading) {
    return const CoPageHeader(
      title: 'Platform analytics',
      subtitle: 'Growth, adoption, and composition across the TRAKR platform.',
    );
  }

  Widget _buildMetrics(List<Company> companies, bool loading) {
    final active = companies.where((c) => c.isActive).length;
    final metrics = [
      CoMetricCard(
        icon: Icons.apartment_rounded,
        label: 'Total Companies',
        value: loading ? '—' : '${companies.length}',
      ),
      CoMetricCard(
        icon: Icons.check_circle_outline_rounded,
        label: 'Active Companies',
        value: loading ? '—' : '$active',
        accent: kCoGreen,
      ),
      CoMetricCard(
        icon: Icons.group_rounded,
        label: 'Total Users',
        value: _loading ? '—' : '$_totalUsers',
        accent: kCoBlue,
      ),
      CoMetricCard(
        icon: Icons.admin_panel_settings_rounded,
        label: 'Company Admins',
        value: _loading ? '—' : '$_totalAdmins',
        accent: kCoAmber,
      ),
      CoMetricCard(
        icon: Icons.engineering_outlined,
        label: 'Staff',
        value: _loading ? '—' : '$_totalStaff',
        accent: kCoCyan,
      ),
      CoMetricCard(
        icon: Icons.people_outline_rounded,
        label: 'Managers',
        value: _loading ? '—' : '$_totalManagers',
        accent: kCoViolet,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
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

  Map<String, int> _growthByMonth(List<Company> companies) {
    final counts = <String, int>{};
    for (final company in companies) {
      final created = company.createdAt;
      if (created == null) continue;
      final key = '${created.year}-${created.month.toString().padLeft(2, '0')}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Widget _buildCharts(List<Company> companies, bool loading) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGrowthChart(companies, loading),
              const SizedBox(height: 18),
              _buildPlanDonut(companies, loading),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildGrowthChart(companies, loading)),
            const SizedBox(width: 18),
            Expanded(child: _buildPlanDonut(companies, loading)),
          ],
        );
      },
    );
  }

  Widget _buildGrowthChart(List<Company> companies, bool loading) {
    final months = _lastMonths(8);
    final counts = _growthByMonth(companies);
    var running = 0;
    final spots = <FlSpot>[];
    for (var i = 0; i < months.length; i++) {
      running += counts[months[i].key] ?? 0;
      spots.add(FlSpot(i.toDouble(), running.toDouble()));
    }
    final maxY = running == 0 ? 5.0 : (running + 2).toDouble();
    return CoSectionCard(
      title: 'Companies onboarded',
      subtitle: 'Cumulative companies created in the last 8 months.',
      icon: Icons.trending_up_rounded,
      child: loading && companies.isEmpty
          ? const CoInlineLoading()
          : SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => AppThemeColors.darkCanvas,
                      getTooltipItems: (spots) {
                        return [
                          for (final spot in spots)
                            LineTooltipItem(
                              '${months[spot.x.toInt()].label}: ${spot.y.toInt()}',
                              const TextStyle(
                                color: kCoLabel,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ];
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: kCoBorder,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
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
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= months.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              months[i].label,
                              style: const TextStyle(
                                color: kCoSubtle,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: kCoCyan,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            kCoCyan.withValues(alpha: 0.25),
                            kCoCyan.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPlanDonut(List<Company> companies, bool loading) {
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
      title: 'Plan mix',
      subtitle: 'Share of companies by subscription plan.',
      icon: Icons.donut_large_rounded,
      child: loading || total == 0
          ? const CoEmptyState(
              icon: Icons.donut_large_rounded, message: 'No data yet.')
          : SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 42,
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

  Widget _buildDistribution(List<Company> companies) {
    final active = companies.where((c) => c.isActive).length;
    final sorted = companies.toList()
      ..sort((a, b) =>
          (_usersByCompany[b.id] ?? 0).compareTo(_usersByCompany[a.id] ?? 0));
    final top = sorted.take(8).toList();
    final maxUsers = top.fold<int>(0, (acc, c) {
      final u = _usersByCompany[c.id] ?? 0;
      return u > acc ? u : acc;
    });

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUsersDistribution(top, maxUsers),
              const SizedBox(height: 18),
              _buildActiveSplit(companies, active),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildUsersDistribution(top, maxUsers)),
            const SizedBox(width: 18),
            Expanded(child: _buildActiveSplit(companies, active)),
          ],
        );
      },
    );
  }

  Widget _buildUsersDistribution(List<Company> top, int maxUsers) {
    return CoSectionCard(
      title: 'Users by company',
      subtitle: 'Top companies by login accounts.',
      icon: Icons.groups_outlined,
      child: top.isEmpty
          ? const CoEmptyState(
              icon: Icons.groups_outlined, message: 'No companies yet.')
          : Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          top[i].name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kCoLabel,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: maxUsers == 0
                                ? 0
                                : (_usersByCompany[top[i].id] ?? 0) / maxUsers,
                            minHeight: 7,
                            backgroundColor: kCoAccent.withValues(alpha: 0.12),
                            valueColor: const AlwaysStoppedAnimation(kCoCyan),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${_usersByCompany[top[i].id] ?? 0}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: kCoLabel,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildActiveSplit(List<Company> companies, int active) {
    final inactive = companies.length - active;
    final activePct = companies.isEmpty ? 0.0 : active / companies.length;
    return CoSectionCard(
      title: 'Active vs inactive',
      subtitle: 'Share of companies by status.',
      icon: Icons.donut_large_rounded,
      child: companies.isEmpty
          ? const CoEmptyState(
              icon: Icons.donut_large_rounded, message: 'No data yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _legendDot(kCoGreen),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Active',
                          style: TextStyle(
                              color: kCoLabel,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text('$active',
                        style: const TextStyle(
                            color: kCoLabel,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _legendDot(kCoRed),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Inactive',
                          style: TextStyle(
                              color: kCoLabel,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text('$inactive',
                        style: const TextStyle(
                            color: kCoLabel,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        Expanded(
                          flex: active,
                          child: Container(color: kCoGreen),
                        ),
                        if (inactive > 0)
                          Expanded(
                            flex: inactive,
                            child: Container(color: kCoRed),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(activePct * 100).toStringAsFixed(0)}% of companies are active',
                  style: const TextStyle(color: kCoSubtle, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
