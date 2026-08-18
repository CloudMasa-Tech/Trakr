import 'package:flutter/material.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';

class AttendanceLogTable extends StatefulWidget {
  final AttendanceService attendanceService;
  final String? managerName;
  final String? employeeId;
  final String? title;
  final String? emptyMessage;
  final DateTime? selectedDate;
  final bool showFilterSelector;
  final String initialFilter;

  const AttendanceLogTable({
    super.key,
    required this.attendanceService,
    this.managerName,
    this.employeeId,
    this.title,
    this.emptyMessage,
    this.selectedDate,
    this.showFilterSelector = true,
    this.initialFilter = 'All',
  });

  @override
  State<AttendanceLogTable> createState() => _AttendanceLogTableState();
}

class _AttendanceLogTableState extends State<AttendanceLogTable> {
  late String _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final attendanceStream = _getStream();

    return StreamBuilder<List<AttendanceModel>>(
      stream: attendanceStream,
      builder: (context, snap) {
        final rows = snap.data ?? [];
        late final Widget content;

        if (snap.connectionState == ConnectionState.waiting) {
          content = SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(color: colors.primary),
            ),
          );
        } else if (rows.isEmpty) {
          content = SizedBox(
            height: 152,
            child: Center(
              child: Text(
                widget.emptyMessage ??
                    'No attendance records for ${_selectedFilter.toLowerCase()}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        } else {
          content = ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: colors.divider),
            itemBuilder: (_, i) => _Row(
              record: rows[i],
              showDate: _selectedFilter != 'Today',
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            const minWidth = 1320.0;

            return Container(
              width:
                  constraints.maxWidth.isFinite ? constraints.maxWidth : null,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title / Filter header – always visible
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 26,
                      isMobile ? 16 : 28,
                      isMobile ? 16 : 26,
                      isMobile ? 12 : 24,
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title ??
                                    "$_selectedFilter's Attendance Log",
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildCountBadge(rows.length),
                                  const SizedBox(width: 8),
                                  if (widget.showFilterSelector)
                                    Expanded(child: _buildFilterSelector()),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Text(
                                widget.title ??
                                    "$_selectedFilter's Attendance Log",
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              if (widget.showFilterSelector) ...[
                                _buildCountBadge(rows.length),
                                const SizedBox(width: 12),
                              ],
                              if (widget.showFilterSelector)
                                _buildFilterSelector()
                              else
                                _buildCountBadge(rows.length),
                            ],
                          ),
                  ),

                  // Mobile: card list | Desktop: horizontal-scroll table
                  if (isMobile)
                    _buildMobileCardList(rows)
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth > minWidth
                              ? constraints.maxWidth
                              : minWidth,
                          maxWidth: constraints.maxWidth > minWidth
                              ? constraints.maxWidth
                              : minWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 18,
                              ),
                              decoration: BoxDecoration(
                                color: colors.tableHeader,
                                border: Border.symmetric(
                                  horizontal: BorderSide(
                                    color: colors.border,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _hdr(context, 'EMPLOYEE', flex: 3),
                                  _hdr(context, 'DATE', flex: 2),
                                  _hdr(context, 'DESIGNATION', flex: 2),
                                  _hdr(context, 'STATUS', flex: 2),
                                  _hdr(context, 'CHECK-IN', flex: 1.5),
                                  _hdr(context, 'CHECK-OUT', flex: 1.5),
                                  _hdr(context, 'WORKING HRS/MIN', flex: 1.8),
                                  _hdr(context, 'PENDING HRS', flex: 1.6),
                                  _hdr(context, 'ABSENT/PRESENT', flex: 1.6),
                                  _hdr(context, 'PERMISSION', flex: 2.2),
                                ],
                              ),
                            ),
                            content,
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Stream<List<AttendanceModel>> _getStream() {
    if (widget.employeeId != null) {
      switch (_selectedFilter) {
        case 'Weekly':
          return widget.attendanceService
              .getAttendanceHistoryStream(widget.employeeId!, limit: 7);
        case 'Monthly':
          return widget.attendanceService
              .getAttendanceHistoryStream(widget.employeeId!, limit: 30);
        case 'All':
          return widget.attendanceService
              .getAttendanceHistoryStream(widget.employeeId!);
        default:
          return widget.attendanceService
              .getTodayAttendanceStreamForEmployee(widget.employeeId!);
      }
    } else if (widget.managerName != null) {
      switch (_selectedFilter) {
        case 'Weekly':
          return widget.attendanceService
              .getWeeklyAttendanceStreamByManager(widget.managerName!);
        case 'Monthly':
          return widget.attendanceService
              .getMonthlyAttendanceStreamByManager(widget.managerName!);
        case 'All':
          return widget.attendanceService
              .getAttendanceHistoryStreamByManager(widget.managerName!);
        default:
          return widget.attendanceService
              .getTodayAttendanceStreamByManager(widget.managerName!);
      }
    }

    switch (_selectedFilter) {
      case 'Weekly':
        return widget.attendanceService.getWeeklyAttendanceStreamAll();
      case 'Monthly':
        return widget.attendanceService.getMonthlyAttendanceStreamAll();
      case 'All':
        return widget.attendanceService.getAttendanceHistoryStreamAll();
      default:
        return widget.attendanceService.getTodayAttendanceStream();
    }
  }

  Widget _buildFilterSelector() {
    final colors = AppColors.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.tableHeader,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Today', 'Weekly', 'Monthly', 'All'].map((f) {
          final isSel = _selectedFilter == f;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSel ? colors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                f,
                style: TextStyle(
                  color: isSel ? colors.onPrimary : colors.textSecondary,
                  fontSize: 11,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCountBadge(int count) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.tableHeader,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count records',
        style: TextStyle(
          color: colors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _hdr(BuildContext context, String text, {double flex = 1}) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: isMobile ? 10 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMobileCardList(List<AttendanceModel> rows) {
    final colors = AppColors.of(context);
    if (rows.isEmpty) {
      return SizedBox(
        height: 152,
        child: Center(
          child: Text(
            widget.emptyMessage ??
                'No attendance records for ${_selectedFilter.toLowerCase()}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
      itemBuilder: (_, i) => _MobileAttendanceCard(
        record: rows[i],
        showDate: _selectedFilter != 'Today',
      ),
    );
  }
}

class _MobileAttendanceCard extends StatelessWidget {
  final AttendanceModel record;
  final bool showDate;

  const _MobileAttendanceCard({
    required this.record,
    required this.showDate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = _mobileStatus(context, record);
    final absenceColor = record.countsAsAbsent ? colors.error : colors.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AttendanceAvatar(record: record, radius: 17),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.displayEmployeeName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      record.displayEmployeeId,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _mobileStatusBadge(status),
            ],
          ),
          const SizedBox(height: 12),
          _mobileDetailRow(
            context,
            'Date',
            showDate ? record.dateFormatted : record.dateFormatted,
            'Designation',
            record.department.isEmpty ? '-' : record.department,
          ),
          const SizedBox(height: 9),
          _mobileDetailRow(
            context,
            'Check-in',
            record.checkInFormatted,
            'Check-out',
            record.checkOutFormatted,
          ),
          const SizedBox(height: 9),
          _mobileDetailRow(
            context,
            'Working Hr',
            record.workingHoursFormatted,
            'Pending Hr',
            record.pendingHoursFormatted,
          ),
          const SizedBox(height: 9),
          _mobileDetailRow(
            context,
            'Absence',
            record.countsAsAbsent ? 'Absent' : 'Present',
            'Permission',
            record.permissionActivityLabel,
            firstValueColor: absenceColor,
          ),
        ],
      ),
    );
  }

  _MobileAttendanceStatus _mobileStatus(
      BuildContext context, AttendanceModel record) {
    final colors = AppColors.of(context);
    if (record.policyAction == 'half_day_leave') {
      return _MobileAttendanceStatus(
        label: 'Half Day',
        color: colors.focus,
      );
    }
    if (record.statusLabel == 'Leave') {
      return _MobileAttendanceStatus(
        label: 'Leave',
        color: colors.focus,
      );
    }
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return _MobileAttendanceStatus(
        label: 'Absent',
        color: colors.error,
      );
    }
    if (record.countsAsLate) {
      return _MobileAttendanceStatus(
        label: 'Late',
        color: colors.warning,
      );
    }
    return _MobileAttendanceStatus(
      label: 'Present',
      color: colors.success,
    );
  }

  Widget _mobileStatusBadge(_MobileAttendanceStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _mobileDetailRow(
    BuildContext context,
    String firstLabel,
    String firstValue,
    String secondLabel,
    String secondValue, {
    Color? firstValueColor,
    Color? secondValueColor,
  }) {
    final colors = AppColors.of(context);
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        children: [
          TextSpan(
            text: '$firstLabel: ',
            style: TextStyle(color: colors.textSecondary),
          ),
          TextSpan(
            text: firstValue,
            style: TextStyle(
              color: firstValueColor ?? colors.textPrimary,
            ),
          ),
          const TextSpan(text: '   '),
          TextSpan(
            text: '$secondLabel: ',
            style: TextStyle(color: colors.textSecondary),
          ),
          TextSpan(
            text: secondValue,
            style: TextStyle(
              color: secondValueColor ?? colors.textPrimary,
            ),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _MobileAttendanceStatus {
  final String label;
  final Color color;

  const _MobileAttendanceStatus({
    required this.label,
    required this.color,
  });
}

class _Row extends StatelessWidget {
  final AttendanceModel record;
  final bool showDate;

  const _Row({
    required this.record,
    required this.showDate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 26, vertical: isMobile ? 12 : 16),
      child: Row(
        children: [
          // Employee name + id
          Expanded(
            flex: 30,
            child: Row(
              children: [
                _AttendanceAvatar(
                  record: record,
                  radius: isMobile ? 14 : 17,
                ),
                SizedBox(width: isMobile ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.employeeName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: isMobile ? 12 : 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        record.employeeId,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: isMobile ? 10 : 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Date
          Expanded(
            flex: 20,
            child: Text(
              showDate ? record.dateFormatted : 'Today',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: isMobile ? 11 : 13,
              ),
            ),
          ),

          // Designation
          Expanded(
            flex: 20,
            child: Text(
              record.department,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: isMobile ? 11 : 13,
              ),
            ),
          ),

          // Status
          Expanded(flex: 20, child: _StatusBadge(record)),

          // Check-in
          Expanded(
            flex: 15,
            child: _CheckInTime(record: record),
          ),

          // Check-out
          Expanded(
            flex: 15,
            child: _CheckOutTime(record: record),
          ),

          // Working hours
          Expanded(
            flex: 18,
            child: _WorkingHours(record: record),
          ),
          Expanded(
            flex: 16,
            child: _PendingHours(record: record),
          ),
          Expanded(
            flex: 16,
            child: _PendingAbsence(record: record),
          ),
          Expanded(
            flex: 22,
            child: _PermissionActivity(record: record),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AttendanceModel record;
  const _StatusBadge(this.record);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    Color bg, fg;
    IconData icon;
    String label;

    if (record.statusLabel == 'Leave') {
      bg = colors.focus.withValues(alpha: 0.14);
      fg = colors.focus;
      icon = Icons.event_available_rounded;
      label = 'Leave';
    } else if (record.policyAction == 'full_day_absent') {
      bg = colors.error.withValues(alpha: 0.14);
      fg = colors.error;
      icon = Icons.remove_circle_outline;
      label = 'Absent';
    } else {
      switch (record.status) {
        case AttendanceStatus.present:
          bg = colors.success.withValues(alpha: 0.14);
          fg = colors.success;
          icon = Icons.check;
          label = 'Ontime';
          break;
        case AttendanceStatus.absent:
          bg = colors.error.withValues(alpha: 0.14);
          fg = colors.error;
          icon = Icons.close;
          label = 'Absent';
          break;
        case AttendanceStatus.late:
          bg = colors.warning.withValues(alpha: 0.14);
          fg = colors.warning;
          icon = Icons.access_time;
          label = 'Late';
          break;
        case AttendanceStatus.wfh:
          bg = colors.success.withValues(alpha: 0.14);
          fg = colors.success;
          icon = Icons.laptop_mac;
          label = 'Ontime';
          break;
        case AttendanceStatus.leave:
          bg = colors.focus.withValues(alpha: 0.14);
          fg = colors.focus;
          icon = Icons.event_available_rounded;
          label = 'Leave';
          break;
      }
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 10, vertical: isMobile ? 4 : 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: isMobile ? 10 : 12),
            SizedBox(width: isMobile ? 4 : 6),
            Text(label,
                style: TextStyle(
                  color: fg,
                  fontSize: isMobile ? 10 : 12,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

class _CheckInTime extends StatelessWidget {
  final AttendanceModel record;

  const _CheckInTime({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final color = switch (record.arrivalBand) {
      'green' => colors.success,
      'orange' => colors.warning,
      'red' => colors.error,
      'blue' => colors.focus,
      _ => colors.textSecondary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          record.checkInFormatted,
          style: TextStyle(
            color: color,
            fontSize: isMobile ? 11 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (record.lateMinutes > 0)
          Text(
            '${record.lateMinutes} min late',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: isMobile ? 9 : 10.5,
            ),
          ),
      ],
    );
  }
}

class _CheckOutTime extends StatelessWidget {
  final AttendanceModel record;

  const _CheckOutTime({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Text(
      record.checkOutFormatted,
      style: TextStyle(
        color: record.isCheckedOut ? colors.primary : colors.textSecondary,
        fontSize: isMobile ? 11 : 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _WorkingHours extends StatelessWidget {
  final AttendanceModel record;

  const _WorkingHours({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hasDuration = record.workingDuration != null;
    return Text(
      record.workingHoursFormatted,
      style: TextStyle(
        color: hasDuration ? colors.primary : colors.textSecondary,
        fontSize: isMobile ? 11 : 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PendingHours extends StatelessWidget {
  final AttendanceModel record;

  const _PendingHours({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hasPending = record.pendingMinutes > 0;
    return Text(
      record.pendingHoursFormatted,
      style: TextStyle(
        color: hasPending ? colors.error : colors.success,
        fontSize: isMobile ? 11 : 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AttendanceAvatar extends StatelessWidget {
  final AttendanceModel record;
  final double radius;

  const _AttendanceAvatar({
    required this.record,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final photoBytes = record.employeePhotoBytes;
    final photoUrl = record.employeePhotoUrl?.trim();
    final hasNetworkPhoto = photoUrl != null &&
        photoUrl.isNotEmpty &&
        !photoUrl.startsWith('data:image');
    ImageProvider? profileImage;
    if (photoBytes != null) {
      profileImage = MemoryImage(photoBytes);
    } else if (hasNetworkPhoto) {
      profileImage = NetworkImage(photoUrl);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: _avatarColor(colors, record.employeeName),
      backgroundImage: profileImage,
      child: photoBytes != null || hasNetworkPhoto
          ? null
          : Text(
              _initials(record.employeeName),
              style: TextStyle(
                color: colors.onPrimary,
                fontSize: radius <= 14 ? 10 : 11,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    return parts
        .map((part) => part.isNotEmpty ? part[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  Color _avatarColor(AppColors colors, String name) {
    final palette = colors.chartSeries;
    return palette[name.length % palette.length];
  }
}

class _PendingAbsence extends StatelessWidget {
  final AttendanceModel record;

  const _PendingAbsence({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      record.pendingAbsenceLabel,
      style: TextStyle(
        color: _pendingAbsenceColor(colors, record.pendingAbsenceLabel),
        fontSize: MediaQuery.of(context).size.width < 600 ? 11 : 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

Color _pendingAbsenceColor(AppColors colors, String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('leave')) return colors.focus;
  if (normalized == 'present') return colors.success;
  return colors.error;
}

class _PermissionActivity extends StatelessWidget {
  final AttendanceModel record;

  const _PermissionActivity({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasPermission = record.hasPermissionActivity;
    final color = !hasPermission
        ? colors.textSecondary
        : record.isPermissionReEntryDelayed
            ? colors.error
            : record.isTemporaryExit
                ? colors.secondary
                : colors.focus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          record.permissionActivityLabel,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: MediaQuery.of(context).size.width < 600 ? 11 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hasPermission)
          Text(
            record.permissionActivityDetail,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
