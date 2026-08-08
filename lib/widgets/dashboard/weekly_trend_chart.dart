import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';

class MonthlyTrendChart extends StatelessWidget {
  final AttendanceService attendanceService;
  const MonthlyTrendChart({super.key, required this.attendanceService});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final cardPadding = isCompact ? 16.0 : 20.0;
        final barWidth = isCompact ? 6.0 : 10.0;
        final barsSpace = isCompact ? 2.0 : 3.0;
        final labelFontSize = isCompact ? 10.0 : 12.0;
        final chartHeight = isCompact ? 205.0 : 190.0;

        return Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Monthly Attendance\nTrend',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.35,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.tableHeader,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Jan-Dec',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 18 : 24),

              // Bar chart
              StreamBuilder<List<MonthlyAttendance>>(
                stream: attendanceService.getYearlyMonthlyTrendStream(),
                builder: (context, snap) {
                  final data = snap.data ??
                      [
                        'Jan',
                        'Feb',
                        'Mar',
                        'Apr',
                        'May',
                        'Jun',
                        'Jul',
                        'Aug',
                        'Sep',
                        'Oct',
                        'Nov',
                        'Dec',
                      ]
                          .map((month) => MonthlyAttendance(
                              label: month, present: 0, absent: 0, late: 0))
                          .toList();
                  final maxTotal = data.fold<int>(
                    0,
                    (max, item) => item.total > max ? item.total : max,
                  );
                  final maxY = maxTotal <= 0 ? 5.0 : (maxTotal + 2).toDouble();

                  return SizedBox(
                    height: chartHeight,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY,
                        barTouchData: BarTouchData(enabled: true),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: colors.chartGrid,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= data.length) {
                                  return const SizedBox();
                                }
                                final label = isCompact
                                    ? data[i].label.substring(0, 1)
                                    : data[i].label;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: SizedBox(
                                    width: isCompact ? 18 : 32,
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: colors.chartLabel,
                                        fontSize: labelFontSize,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: List.generate(data.length, (i) {
                          final d = data[i];
                          return BarChartGroupData(
                            x: i,
                            barsSpace: barsSpace,
                            barRods: [
                              BarChartRodData(
                                toY: d.present.toDouble(),
                                color: colors.success,
                                width: barWidth,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                              BarChartRodData(
                                toY: d.absent.toDouble(),
                                color: colors.error,
                                width: barWidth,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                              BarChartRodData(
                                toY: d.late.toDouble(),
                                color: colors.warning,
                                width: barWidth,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Legend
              Wrap(
                spacing: isCompact ? 14 : 20,
                runSpacing: 8,
                children: [
                  _Legend(colors.success, 'Present'),
                  _Legend(colors.error, 'Absent'),
                  _Legend(colors.warning, 'Late'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            )),
      ],
    );
  }
}
