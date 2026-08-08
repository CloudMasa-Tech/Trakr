import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_model.dart';
import '../../models/staff.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';

// Fixed-brand palette for the monthly employee analysis screen (force-dark).
// Intentional exception: file-scoped brand constants.
const Color _meaRed = Color(0xFFFF5757);
const Color _meaPrimary = Color(0xFF0F766E);
const Color _meaAmber = Color(0xFFFFB800);
const Color _meaCyan = Color(0xFF22D3EE);
const Color _meaBlue = Color(0xFF38BDF8);
const Color _meaAmberDeep = Color(0xFFFFB400);
const Color _meaGreen = Color(0xFF00C896);

class MonthlyEmployeeAnalysisScreen extends StatefulWidget {
  final Staff staff;
  final int month;
  final int year;
  final int totalApprovedLeaves;
  final VoidCallback onBack;

  const MonthlyEmployeeAnalysisScreen({
    super.key,
    required this.staff,
    required this.month,
    required this.year,
    required this.totalApprovedLeaves,
    required this.onBack,
  });

  @override
  State<MonthlyEmployeeAnalysisScreen> createState() =>
      _MonthlyEmployeeAnalysisScreenState();
}

class _MonthlyEmployeeAnalysisScreenState
    extends State<MonthlyEmployeeAnalysisScreen> {
  final AttendanceService _attendanceService = AttendanceService();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Custom Header with Back Button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            children: [
              InkWell(
                onTap: widget.onBack,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppThemeColors.darkSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppThemeColors.darkBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: AppThemeColors.darkText,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${widget.staff.name} - ${DateFormat('MMMM yyyy').format(DateTime(widget.year, widget.month))}',
                  style: const TextStyle(
                    color: AppThemeColors.darkText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<List<AttendanceModel>>(
            stream: _attendanceService.getAttendanceHistoryStream(
              widget.staff.employeeId,
              limit: null,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _meaPrimary),
                );
              }

              final allRecords = snapshot.data ?? <AttendanceModel>[];
              final records = allRecords
                  .where((r) =>
                      r.date.month == widget.month &&
                      r.date.year == widget.year)
                  .toList();

              int totalPendingMinutes = 0;
              int totalPermissionMinutes = 0;

              for (var record in records) {
                // Note: Since we are not doing the async isEmployeeOnApprovedLeave check here directly on each row,
                // we use the policyAction or basic status. (Or we could assume it's accurate enough,
                // since we have totalApprovedLeaves passed in).
                totalPendingMinutes += record.displayPendingMinutes;
                totalPermissionMinutes += record.permissionMinutes;
              }

              final totalPendingWithPermissionMinutes =
                  totalPendingMinutes + totalPermissionMinutes;
              final fullDays = totalPendingWithPermissionMinutes ~/ 360;
              final remainder = totalPendingWithPermissionMinutes % 360;

              double additionalAbsent = fullDays.toDouble();
              if (remainder >= 300) {
                // 5 to 6 hrs -> 1 day
                additionalAbsent += 1.0;
              } else if (remainder >= 150) {
                // 2.5 to 4.99 hrs -> 0.5 day
                additionalAbsent += 0.5;
              }

              final pendingHoursStr =
                  _formatHoursMinutesSeconds(totalPendingMinutes);
              final permissionHoursStr =
                  _formatHoursMinutesSeconds(totalPermissionMinutes);
              final totalPendingHoursStr =
                  _formatHoursMinutesSeconds(totalPendingWithPermissionMinutes);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Calculation Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppThemeColors.darkSurface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppThemeColors.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Absence Calculation',
                            style: TextStyle(
                              color: AppThemeColors.darkText,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final children = [
                                _buildStatItem('Pending Hours', pendingHoursStr,
                                    _meaAmber),
                                _buildStatItem('Permission Hours',
                                    permissionHoursStr, _meaPrimary),
                                _buildStatItem('Total Pending Hours',
                                    totalPendingHoursStr, _meaRed),
                              ];
                              if (constraints.maxWidth < 550) {
                                return Wrap(
                                  spacing: 24,
                                  runSpacing: 16,
                                  alignment: WrapAlignment.start,
                                  children: children,
                                );
                              }
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: children,
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _meaRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _meaRed.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calculate_outlined,
                                    color: _meaRed, size: 28),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Leave / Absence From Total Pending',
                                        style: TextStyle(
                                          color: _meaRed,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$additionalAbsent Days leave (pending + permission hrs)',
                                        style: const TextStyle(
                                          color: AppThemeColors.darkText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Rule: 6 hrs = 1 day, 2.5 - 4.99 hrs = 0.5 day, 5 - 6 hrs = 1 day',
                                        style: TextStyle(
                                          color: AppThemeColors.darkMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Table
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppThemeColors.darkSurface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppThemeColors.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(22),
                            child: Text(
                              'Monthly Attendance Log',
                              style: TextStyle(
                                color: AppThemeColors.darkText,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          // Table Headers
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isMobile = constraints.maxWidth < 600;
                              return Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 12 : 26,
                                  vertical: isMobile ? 12 : 18,
                                ),
                                decoration: const BoxDecoration(
                                  color: AppThemeColors.darkCanvas,
                                  border: Border(
                                    bottom: BorderSide(
                                        color: AppThemeColors.darkBorder),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: isMobile ? 18 : 20,
                                      child: _TableHeaderText(
                                          isMobile ? 'DATE' : 'DATE'),
                                    ),
                                    Expanded(
                                      flex: isMobile ? 17 : 20,
                                      child: _TableHeaderText(
                                          isMobile ? 'STATUS' : 'STATUS'),
                                    ),
                                    Expanded(
                                      flex: isMobile ? 13 : 15,
                                      child: _TableHeaderText(
                                          isMobile ? 'IN' : 'CHECK IN'),
                                    ),
                                    Expanded(
                                      flex: isMobile ? 13 : 15,
                                      child: _TableHeaderText(
                                          isMobile ? 'OUT' : 'CHECK OUT'),
                                    ),
                                    Expanded(
                                      flex: isMobile ? 14 : 15,
                                      child: _TableHeaderText(
                                          isMobile ? 'PEND' : 'PENDING'),
                                    ),
                                    Expanded(
                                      flex: isMobile ? 14 : 15,
                                      child: _TableHeaderText(
                                          isMobile ? 'PERM' : 'PERMISSION'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          if (records.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: Text(
                                  'No attendance logs found for this month.',
                                  style: TextStyle(
                                    color: AppThemeColors.darkMuted,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: records.length,
                              separatorBuilder: (context, index) {
                                return const Divider(
                                  height: 1,
                                  color: AppThemeColors.darkBorder,
                                );
                              },
                              itemBuilder: (context, index) {
                                final r = records[index];
                                final isAbsent = r.countsAsAbsent;
                                final isLate = r.countsAsLate;
                                final isHalfDayLeave =
                                    r.policyAction == 'half_day_leave';
                                final isFullDayLeave = r.statusLabel == 'Leave';
                                final statusText = isHalfDayLeave
                                    ? 'Half Day'
                                    : isFullDayLeave
                                        ? 'Leave'
                                        : isAbsent
                                            ? 'Absent'
                                            : isLate
                                                ? 'Late'
                                                : 'Present';
                                final statusColor = isHalfDayLeave
                                    ? _meaCyan
                                    : isFullDayLeave
                                        ? _meaBlue
                                        : isAbsent
                                            ? _meaRed
                                            : isLate
                                                ? _meaAmberDeep
                                                : _meaGreen;

                                final bool isMobile =
                                    MediaQuery.of(context).size.width < 600;
                                if (isMobile) {
                                  final dateText =
                                      DateFormat('dd/MM').format(r.date);
                                  final checkInText =
                                      r.checkInFormatted.replaceAll(' ', '\n');
                                  final checkOutText =
                                      r.checkOutFormatted.replaceAll(' ', '\n');
                                  final pendingText = _formatCompactMinutes(
                                      r.displayPendingMinutes);
                                  final permissionText = _formatCompactMinutes(
                                      r.permissionMinutes);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 18,
                                          child: Text(
                                            dateText,
                                            style: const TextStyle(
                                              color: AppThemeColors.darkText,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 17,
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 13,
                                          child: Text(
                                            checkInText,
                                            style: const TextStyle(
                                              color: AppThemeColors.darkMuted,
                                              fontSize: 10,
                                              height: 1.1,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 13,
                                          child: Text(
                                            checkOutText,
                                            style: const TextStyle(
                                              color: AppThemeColors.darkMuted,
                                              fontSize: 10,
                                              height: 1.1,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 14,
                                          child: Text(
                                            pendingText,
                                            style: TextStyle(
                                              color: r.displayPendingMinutes > 0
                                                  ? _meaAmber
                                                  : AppThemeColors.darkMuted,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 14,
                                          child: Text(
                                            permissionText,
                                            style: TextStyle(
                                              color: r.permissionMinutes > 0
                                                  ? _meaPrimary
                                                  : AppThemeColors.darkMuted,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 26, vertical: 16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 20,
                                        child: Text(
                                          r.dateFormatted,
                                          style: const TextStyle(
                                              color: AppThemeColors.darkText,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 20,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              statusText,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: Text(
                                          r.checkInFormatted,
                                          style: const TextStyle(
                                              color: AppThemeColors.darkMuted,
                                              fontSize: 13),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: Text(
                                          r.checkOutFormatted,
                                          style: const TextStyle(
                                              color: AppThemeColors.darkMuted,
                                              fontSize: 13),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: Text(
                                          r.pendingHoursFormatted,
                                          style: TextStyle(
                                            color: r.displayPendingMinutes > 0
                                                ? _meaAmber
                                                : AppThemeColors.darkMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: Text(
                                          r.permissionHoursFormatted,
                                          style: TextStyle(
                                            color: r.permissionMinutes > 0
                                                ? _meaPrimary
                                                : AppThemeColors.darkMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppThemeColors.darkMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  String _formatHoursMinutesSeconds(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '$hours hrs ${minutes.toString().padLeft(2, '0')} min';
  }

  String _formatCompactMinutes(int totalMinutes) {
    if (totalMinutes <= 0) return '0m';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}

class _TableHeaderText extends StatelessWidget {
  final String label;
  const _TableHeaderText(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppThemeColors.darkMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}
