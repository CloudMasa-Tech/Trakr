import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../firebase/firebase_context_provider.dart';
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
  final num totalApprovedLeaves;
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
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseContextProvider.current.firestore
                .collection('geo_config')
                .doc('default')
                .snapshots(),
            builder: (context, geoSnap) {
              final holidayDateKeys = <String>{};
              final holidayNames = <String, String>{};
              bool sundayWorking = false;

              if (geoSnap.hasData && geoSnap.data?.data() != null) {
                final geoData = geoSnap.data!.data() as Map<String, dynamic>;
                sundayWorking = geoData['sundayWorking'] as bool? ?? false;
                final rawDates = geoData['holidayDates'];
                if (rawDates is List) {
                  for (var d in rawDates) {
                    if (d != null && d.toString().trim().isNotEmpty) {
                      holidayDateKeys.add(d.toString().trim());
                    }
                  }
                }
                final rawEvents = geoData['holidayEvents'];
                if (rawEvents is List) {
                  for (var ev in rawEvents) {
                    if (ev is Map) {
                      final dk = ev['dateKey']?.toString().trim();
                      final name = ev['title']?.toString().trim() ?? 'Holiday';
                      if (dk != null && dk.isNotEmpty) {
                        holidayDateKeys.add(dk);
                        holidayNames[dk] = name;
                      }
                    }
                  }
                }
              }

              // Standard official calendar holidays
              const standardOfficialHolidays = {
                '2026-01-01': 'New Year',
                '2026-01-14': 'Pongal',
                '2026-01-26': 'Republic Day',
                '2026-03-04': 'Holi',
                '2026-03-21': 'Eid-ul-Fitr',
                '2026-03-26': 'Ram Navami',
                '2026-04-03': 'Good Friday',
                '2026-04-05': 'Easter',
                '2026-04-14': 'Tamil New Year',
                '2026-05-01': 'May Day',
                '2026-05-27': 'Eid-ul-Zuha',
                '2026-06-26': 'Muharram',
                '2026-08-15': 'Independence Day',
                '2026-08-26': 'Milad-un-Nabi',
                '2026-09-04': 'Janmashtami',
                '2026-10-02': 'Gandhi Jayanti',
                '2026-10-20': 'Dussehra',
                '2026-11-08': 'Diwali',
                '2026-11-24': 'Guru Nanak Jayanti',
                '2026-12-25': 'Christmas',
              };
              for (final entry in standardOfficialHolidays.entries) {
                holidayDateKeys.add(entry.key);
                holidayNames.putIfAbsent(entry.key, () => entry.value);
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseContextProvider.current.firestore
                    .collection('leave_requests')
                    .snapshots(),
                builder: (context, leaveSnap) {
                  double dynamicApprovedLeaves = widget.totalApprovedLeaves.toDouble();
                  if (leaveSnap.hasData && leaveSnap.data != null) {
                    final counted = _calculateApprovedLeavesInMonth(
                      widget.staff.employeeId,
                      widget.staff.id,
                      widget.staff.name,
                      widget.month,
                      widget.year,
                      leaveSnap.data!,
                    );
                    if (counted > 0 || widget.totalApprovedLeaves == 0) {
                      dynamicApprovedLeaves = counted;
                    }
                  }

                  return StreamBuilder<List<AttendanceModel>>(
                    stream: _attendanceService.getAttendanceHistoryStream(
                      widget.staff.employeeId,
                      alternativeIds: [
                        widget.staff.id,
                        widget.staff.email,
                        widget.staff.name,
                      ],
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
                      int presentDays = 0;
                      int absentDays = 0;
                      double attendanceLeaveDays = 0.0;

                      for (var record in records) {
                        final dateKey =
                            '${record.date.year}-${record.date.month.toString().padLeft(2, '0')}-${record.date.day.toString().padLeft(2, '0')}';
                        final isOfficeLeave = holidayDateKeys.contains(dateKey);

                        if (isOfficeLeave) {
                          // Office Leave Day (Company Holiday) - MUST NOT count as absent or employee leave!
                          continue;
                        }

                        if (record.policyAction == 'half_day_leave') {
                          attendanceLeaveDays += 0.5;
                        } else if (record.status == AttendanceStatus.leave ||
                            record.policyAction == 'full_day_leave' ||
                            (record.policyAction == 'full_day_absent' &&
                                record.policyLabel.toLowerCase().contains('leave'))) {
                          attendanceLeaveDays += 1.0;
                        } else if (record.countsAsAbsent) {
                          absentDays++;
                        } else if (record.countsAsAttended) {
                          presentDays++;
                        }

                        totalPendingMinutes += record.displayPendingMinutes;
                        totalPermissionMinutes += record.permissionMinutes;
                      }

                      final totalPendingWithPermissionMinutes =
                          totalPendingMinutes + totalPermissionMinutes;
                      final fullDays = totalPendingWithPermissionMinutes ~/ 360;
                      final remainder = totalPendingWithPermissionMinutes % 360;

                      double pendingHrsLeaves = fullDays.toDouble();
                      if (remainder >= 300) {
                        // 5 to 6 hrs -> 1 day
                        pendingHrsLeaves += 1.0;
                      } else if (remainder >= 150) {
                        // 2.5 to 4.99 hrs -> 0.5 day
                        pendingHrsLeaves += 0.5;
                      }

                      final double approvedLeaves = [
                        dynamicApprovedLeaves,
                        attendanceLeaveDays,
                        widget.totalApprovedLeaves.toDouble(),
                      ].reduce((a, b) => a > b ? a : b);

                      final double totalLeaveTaken = approvedLeaves + pendingHrsLeaves;

                      final int totalWorkingDays = _calculateWorkingDaysInMonth(
                        widget.year,
                        widget.month,
                        holidayDateKeys,
                        sundayWorking: sundayWorking,
                      );

                      final int officeLeaveDaysInMonth = _calculateOfficeLeaveDaysInMonth(
                        widget.year,
                        widget.month,
                        holidayDateKeys,
                        sundayWorking: sundayWorking,
                      );

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
                            // Person Monthly Dashboard Cards
                            _buildDashboardCards(
                              context: context,
                              presentDays: presentDays,
                              absentDays: absentDays,
                              totalWorkingDays: totalWorkingDays,
                              officeLeaveDaysInMonth: officeLeaveDaysInMonth,
                              totalLeaveTaken: totalLeaveTaken,
                              approvedLeaves: approvedLeaves,
                              pendingHrsLeaves: pendingHrsLeaves,
                              pendingHoursStr: pendingHoursStr,
                              permissionHoursStr: permissionHoursStr,
                              totalPendingHoursStr: totalPendingHoursStr,
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
                                final dateKey =
                                    '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}';
                                final isOfficeHoliday =
                                    holidayDateKeys.contains(dateKey);
                                final holidayName =
                                    holidayNames[dateKey] ?? 'Office Leave';

                                final isAbsent = r.countsAsAbsent;
                                final isLate = r.countsAsLate;
                                final isHalfDayLeave =
                                    r.policyAction == 'half_day_leave';
                                final isFullDayLeave = r.statusLabel == 'Leave' ||
                                    (r.policyAction == 'full_day_absent' &&
                                        r.policyLabel.toLowerCase().contains('leave'));

                                final statusText = isOfficeHoliday
                                    ? holidayName
                                    : isHalfDayLeave
                                        ? 'Half Day'
                                        : isFullDayLeave
                                            ? 'Leave'
                                            : isAbsent
                                                ? 'Absent'
                                                : isLate
                                                    ? 'Late'
                                                    : 'Present';

                                final statusColor = isOfficeHoliday
                                    ? const Color(0xFF818CF8)
                                    : isHalfDayLeave
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
                                  final checkInText = isOfficeHoliday
                                      ? '-'
                                      : r.checkInFormatted.replaceAll(' ', '\n');
                                  final checkOutText = isOfficeHoliday
                                      ? '-'
                                      : r.checkOutFormatted.replaceAll(' ', '\n');
                                  final pendingText = isOfficeHoliday
                                      ? '-'
                                      : _formatCompactMinutes(
                                          r.displayPendingMinutes);
                                  final permissionText = isOfficeHoliday
                                      ? '-'
                                      : _formatCompactMinutes(
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
                                              color: !isOfficeHoliday &&
                                                      r.displayPendingMinutes > 0
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
                                              color: !isOfficeHoliday &&
                                                      r.permissionMinutes > 0
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
                                          isOfficeHoliday ? '-' : r.checkInFormatted,
                                          style: const TextStyle(
                                              color: AppThemeColors.darkMuted,
                                              fontSize: 13),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: Text(
                                          isOfficeHoliday ? '-' : r.checkOutFormatted,
                                          style: const TextStyle(
                                              color: AppThemeColors.darkMuted,
                                              fontSize: 13),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 15,
                                        child: Text(
                                          isOfficeHoliday
                                              ? '-'
                                              : r.pendingHoursFormatted,
                                          style: TextStyle(
                                            color: !isOfficeHoliday &&
                                                    r.displayPendingMinutes > 0
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
                                          isOfficeHoliday
                                              ? '-'
                                              : r.permissionHoursFormatted,
                                          style: TextStyle(
                                            color: !isOfficeHoliday &&
                                                    r.permissionMinutes > 0
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
          );
        },
      );
    },
  ),
),
      ],
    );
  }

  int _calculateWorkingDaysInMonth(
    int year,
    int month,
    Set<String> holidayDates, {
    bool sundayWorking = false,
  }) {
    final lastDay = DateTime(year, month + 1, 0).day;
    int count = 0;
    for (int day = 1; day <= lastDay; day++) {
      final d = DateTime(year, month, day);
      if (!sundayWorking && d.weekday == DateTime.sunday) {
        continue;
      }
      final dateKey =
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      if (holidayDates.contains(dateKey)) {
        continue;
      }
      count++;
    }
    return count;
  }

  int _calculateOfficeLeaveDaysInMonth(
    int year,
    int month,
    Set<String> holidayDates, {
    bool sundayWorking = false,
  }) {
    final lastDay = DateTime(year, month + 1, 0).day;
    int count = 0;
    for (int day = 1; day <= lastDay; day++) {
      final d = DateTime(year, month, day);
      if (!sundayWorking && d.weekday == DateTime.sunday) {
        continue;
      }
      final dateKey =
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      if (holidayDates.contains(dateKey)) {
        count++;
      }
    }
    return count;
  }

  double _calculateApprovedLeavesInMonth(
    String empId,
    String staffId,
    String staffName,
    int targetMonth,
    int targetYear,
    QuerySnapshot leaveSnap,
  ) {
    double totalPaid = 0;
    double totalUnpaid = 0;
    final empClean = empId.trim().toLowerCase();
    final staffClean = staffId.trim().toLowerCase();
    final nameClean = staffName.trim().toLowerCase();

    for (var doc in leaveSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'approved') continue;

      final docEmpId = (data['employeeId'] ?? '').toString().trim().toLowerCase();
      final docUserId = (data['userId'] ?? '').toString().trim().toLowerCase();
      final docUserName =
          (data['userName'] ?? data['name'] ?? '').toString().trim().toLowerCase();

      final matches = (empClean.isNotEmpty &&
              (docEmpId == empClean || docUserId == empClean)) ||
          (staffClean.isNotEmpty &&
              (docEmpId == staffClean || docUserId == staffClean)) ||
          (nameClean.isNotEmpty &&
              docUserName.isNotEmpty &&
              (docUserName == nameClean ||
                  nameClean.contains(docUserName) ||
                  docUserName.contains(nameClean)));
      if (!matches) continue;

      final startTs = data['startDate'] as Timestamp?;
      final endTs = data['endDate'] as Timestamp?;
      if (startTs == null || endTs == null) continue;

      final start = startTs.toDate();
      final end = endTs.toDate();
      final isPaid = data['isPaid'] == true;
      final isHalfDay =
          data['type']?.toString().toLowerCase().contains('half') == true;
      final paidPerRequest = (data['paidDayCount'] as num?)?.toDouble();
      final unpaidPerRequest = (data['unpaidDayCount'] as num?)?.toDouble();
      final requestDays = (data['leaveDayCount'] as num?)?.toDouble() ??
          (isHalfDay
              ? (end.difference(start).inDays + 1) * 0.5
              : (end.difference(start).inDays + 1).toDouble());

      DateTime current = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);

      while (!current.isAfter(last)) {
        if (current.month == targetMonth && current.year == targetYear) {
          final dayValue = isHalfDay ? 0.5 : 1.0;
          if (paidPerRequest != null || unpaidPerRequest != null) {
            final paidRatio =
                requestDays == 0 ? 0.0 : (paidPerRequest ?? 0) / requestDays;
            final unpaidRatio = requestDays == 0
                ? 0.0
                : (unpaidPerRequest ?? 0) / requestDays;
            totalPaid += dayValue * paidRatio;
            totalUnpaid += dayValue * unpaidRatio;
          } else if (isPaid) {
            totalPaid += dayValue;
          } else {
            totalUnpaid += dayValue;
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }

    return totalPaid + totalUnpaid;
  }

  String _formatDays(double days) {
    if (days == days.roundToDouble()) {
      return days.toInt().toString();
    }
    return days.toStringAsFixed(1);
  }

  Widget _buildDashboardCards({
    required BuildContext context,
    required int presentDays,
    required int absentDays,
    required int totalWorkingDays,
    required int officeLeaveDaysInMonth,
    required double totalLeaveTaken,
    required double approvedLeaves,
    required double pendingHrsLeaves,
    required String pendingHoursStr,
    required String permissionHoursStr,
    required String totalPendingHoursStr,
  }) {
    final attendancePercent = totalWorkingDays > 0
        ? (presentDays / totalWorkingDays * 100).clamp(0.0, 100.0)
        : 0.0;

    // Card 1: Working & Present Days (Compact)
    final cardWorkingDays = _buildCompactCard(
      accentColor: _meaGreen,
      icon: Icons.calendar_today_rounded,
      title: 'WORKINGS & PRESENT',
      badgeText: '${attendancePercent.toStringAsFixed(0)}%',
      mainValue: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$presentDays',
            style: const TextStyle(
              color: _meaGreen,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            ' / $totalWorkingDays Days',
            style: const TextStyle(
              color: AppThemeColors.darkText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      subtitle: 'Present: $presentDays d  •  Absent: $absentDays d',
    );

    // Card 2: Total Leave Taken (Compact)
    final cardLeaveTaken = _buildCompactCard(
      accentColor: _meaRed,
      icon: Icons.event_busy_rounded,
      title: 'TOTAL LEAVE TAKEN',
      badgeText: totalLeaveTaken > 0 ? '${_formatDays(totalLeaveTaken)}d' : null,
      mainValue: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            _formatDays(totalLeaveTaken),
            style: const TextStyle(
              color: _meaRed,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            totalLeaveTaken == 1.0 ? 'Day' : 'Days',
            style: const TextStyle(
              color: AppThemeColors.darkText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      subtitle: '${_formatDays(approvedLeaves)}d approved  •  ${_formatDays(pendingHrsLeaves)}d pending hrs',
    );

    // Card 3: Pending & Permission Hours (Compact)
    final cardPendingHours = _buildCompactCard(
      accentColor: _meaAmber,
      icon: Icons.hourglass_bottom_rounded,
      title: 'PENDING & PERMISSION',
      badgeText: pendingHrsLeaves > 0 ? '=${_formatDays(pendingHrsLeaves)}d leave' : null,
      mainValue: Text(
        totalPendingHoursStr,
        style: const TextStyle(
          color: _meaAmber,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: 'Pending: $pendingHoursStr  •  Perm: $permissionHoursStr',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= 900) {
          return Row(
            children: [
              Expanded(child: cardWorkingDays),
              const SizedBox(width: 14),
              Expanded(child: cardLeaveTaken),
              const SizedBox(width: 14),
              Expanded(child: cardPendingHours),
            ],
          );
        } else {
          return Column(
            children: [
              cardWorkingDays,
              const SizedBox(height: 12),
              cardLeaveTaken,
              const SizedBox(height: 12),
              cardPendingHours,
            ],
          );
        }
      },
    );
  }

  Widget _buildCompactCard({
    required Color accentColor,
    required IconData icon,
    required String title,
    required Widget mainValue,
    required String subtitle,
    String? badgeText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          mainValue,
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppThemeColors.darkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
