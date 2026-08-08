import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../widgets/dashboard/export_dropdown.dart';
import '../../widgets/dashboard/holiday_calendar_widget.dart';

class ManagerAttendanceLogScreen extends StatefulWidget {
  const ManagerAttendanceLogScreen({super.key});

  @override
  State<ManagerAttendanceLogScreen> createState() =>
      _ManagerAttendanceLogScreenState();
}

class _ManagerAttendanceLogScreenState
    extends State<ManagerAttendanceLogScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _calendarMonth = DateTime.now();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manager Log',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _ManagerLogTheme.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'View managers attendance records and filter them by calendar date.',
                style: TextStyle(
                  color: _ManagerLogTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 1000;
                  final table = _ManagerAttendanceLogTable(
                    attendanceService: _attendanceService,
                    selectedDate: _selectedDate,
                    searchQuery: _searchQuery,
                    searchController: _searchController,
                    onSearchChanged: (value) =>
                        setState(() => _searchQuery = value.trim()),
                    onClearSearch: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    onPickDate: _pickDate,
                  );

                  final calendar = HolidayCalendarWidget(
                    visibleMonth: _calendarMonth,
                    selectedDate: _selectedDate,
                    onPreviousMonth: () {
                      setState(() {
                        _calendarMonth = DateTime(
                            _calendarMonth.year, _calendarMonth.month - 1);
                      });
                    },
                    onNextMonth: () {
                      setState(() {
                        _calendarMonth = DateTime(
                            _calendarMonth.year, _calendarMonth.month + 1);
                      });
                    },
                    onDateSelected: (date) {
                      setState(() {
                        _selectedDate = date;
                      });
                    },
                  );

                  if (isMobile) {
                    return Column(
                      children: [
                        calendar,
                        const SizedBox(height: 24),
                        table,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 360, child: calendar),
                      const SizedBox(width: 24),
                      Expanded(child: table),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagerAttendanceLogTable extends StatelessWidget {
  final AttendanceService attendanceService;
  final DateTime selectedDate;
  final String searchQuery;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onPickDate;

  const _ManagerAttendanceLogTable({
    required this.attendanceService,
    required this.selectedDate,
    required this.searchQuery,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceModel>>(
      stream: attendanceService.getManagersAttendanceHistoryStreamAll(
        date: selectedDate,
      ),
      builder: (context, snapshot) {
        var records = snapshot.data ?? const <AttendanceModel>[];
        final query = searchQuery.toLowerCase();
        if (query.isNotEmpty) {
          records = records.where((record) {
            return record.displayEmployeeName.toLowerCase().contains(query) ||
                record.displayEmployeeId.toLowerCase().contains(query) ||
                record.displayDepartment.toLowerCase().contains(query);
          }).toList();
        }

        final dateLabel = DateFormat('dd/MM/yyyy').format(selectedDate);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _ManagerLogTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ManagerLogTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _ManagerLogTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 700;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 26,
                      isMobile ? 16 : 28,
                      isMobile ? 16 : 26,
                      isMobile ? 12 : 24,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Managers Attendance Record',
                                style: TextStyle(
                                  color: _ManagerLogTheme.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (records.isNotEmpty) ...[
                              ExportDropdown(
                                records: records,
                                fileNamePrefix: 'Manager_Log',
                              ),
                              const SizedBox(width: 12),
                            ],
                            _countChip('${records.length} records'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (isMobile) ...[
                          _searchField(),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _dateFilterButton(dateLabel),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(flex: 3, child: _searchField()),
                              const SizedBox(width: 12),
                              _dateFilterButton(dateLabel),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (!isMobile)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 18,
                      ),
                      decoration: const BoxDecoration(
                        color: _ManagerLogTheme.header,
                        border: Border.symmetric(
                          horizontal:
                              BorderSide(color: _ManagerLogTheme.border),
                        ),
                      ),
                      child: const Row(
                        children: [
                          _ManagerLogHeader('MANAGER', flex: 30),
                          _ManagerLogHeader('DATE', flex: 20),
                          _ManagerLogHeader('DESIGNATION', flex: 20),
                          _ManagerLogHeader('STATUS', flex: 20),
                          _ManagerLogHeader('CHECK-IN', flex: 15),
                          _ManagerLogHeader('CHECK-OUT', flex: 15),
                          _ManagerLogHeader('WORKING HRS/MIN', flex: 18),
                          _ManagerLogHeader('PENDING HRS', flex: 16),
                          _ManagerLogHeader('PERMISSION HR', flex: 16),
                          _ManagerLogHeader('ABSENT / PRESENT', flex: 16),
                        ],
                      ),
                    ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _ManagerLogTheme.primary,
                        ),
                      ),
                    )
                  else if (records.isEmpty)
                    const SizedBox(
                      height: 152,
                      child: Center(
                        child: Text(
                          'No manager attendance records found.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ManagerLogTheme.muted,
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
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: _ManagerLogTheme.border,
                      ),
                      itemBuilder: (context, index) => isMobile
                          ? _ManagerLogMobileCard(record: records[index])
                          : _ManagerLogRow(record: records[index]),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _dateFilterButton(String dateLabel) {
    return OutlinedButton.icon(
      onPressed: onPickDate,
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Text(dateLabel),
      style: OutlinedButton.styleFrom(
        foregroundColor: _ManagerLogTheme.primary,
        side: const BorderSide(color: _ManagerLogTheme.primary),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      cursorColor: _ManagerLogTheme.primary,
      style: const TextStyle(
        color: _ManagerLogTheme.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: 'Search by manager, ID, or designation...',
        hintStyle: const TextStyle(
          color: _ManagerLogTheme.muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(
          Icons.search,
          size: 18,
          color: _ManagerLogTheme.primary,
        ),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.clear,
                  size: 16,
                  color: _ManagerLogTheme.muted,
                ),
                onPressed: onClearSearch,
              ),
        filled: true,
        fillColor: _ManagerLogTheme.header,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _countChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _ManagerLogTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _ManagerLogTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ManagerLogTheme {
  static const Color surface = AppThemeColors.darkSurface;
  static const Color border = AppThemeColors.darkBorder;
  static const Color header = AppThemeColors.darkCanvas;
  static const Color text = AppThemeColors.darkText;
  static const Color muted = AppThemeColors.darkMuted;
  static const Color primary = Color(0xFF0F766E);
  static const Color success = Color(0xFF16B86A);
  static const Color warning = Color(0xFFFFA400);
  static const Color danger = Color(0xFFFF3D4F);
  static const Color info = Color(0xFF155E75);
  static const Color blue = Color(0xFF38BDF8);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color indigo = Color(0xFF5B6EF5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color shadow = Color(0x1A6B7897);
}

class _ManagerLogHeader extends StatelessWidget {
  final String label;
  final int flex;

  const _ManagerLogHeader(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          color: _ManagerLogTheme.muted.withValues(alpha: 0.78),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ManagerLogRow extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerLogRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AttendanceService()
          .isEmployeeOnApprovedLeave(record.employeeId, record.date),
      builder: (context, snapshot) {
        final isOnLeave = snapshot.data == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: Row(
            children: [
              Expanded(flex: 30, child: _identity(record)),
              Expanded(flex: 20, child: _mutedText(record.dateFormatted)),
              Expanded(flex: 20, child: _mutedText(record.displayDepartment)),
              Expanded(
                flex: 20,
                child:
                    isOnLeave ? const SizedBox.shrink() : _statusBadge(record),
              ),
              Expanded(
                flex: 15,
                child: isOnLeave
                    ? const Text('')
                    : Text(
                        record.checkInFormatted,
                        style: TextStyle(
                          color: _checkInColor(record),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              Expanded(
                flex: 15,
                child: isOnLeave
                    ? const Text('')
                    : _mutedText(record.checkOutFormatted),
              ),
              Expanded(
                flex: 18,
                child: isOnLeave
                    ? const Text('')
                    : _primaryText(record.workingHoursFormatted),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave ? const Text('') : _pendingText(record),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave
                    ? const Text('')
                    : Text(
                        record.permissionHoursFormatted,
                        style: TextStyle(
                          color: record.permissionMinutes > 0
                              ? _ManagerLogTheme.primary
                              : _ManagerLogTheme.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave
                    ? const Text(
                        'Absent',
                        style: TextStyle(
                          color: _ManagerLogTheme.danger,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _absenceText(record),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ManagerLogMobileCard extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerLogMobileCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _identity(record)),
              _statusBadge(record),
            ],
          ),
          const SizedBox(height: 12),
          _managerMobileDetailRow(
            'Date',
            record.dateFormatted,
            'Designation',
            record.displayDepartment.isEmpty ? '-' : record.displayDepartment,
          ),
          const SizedBox(height: 9),
          _managerMobileDetailRow(
            'Check-in',
            record.checkInFormatted,
            'Check-out',
            record.checkOutFormatted,
          ),
          const SizedBox(height: 9),
          _managerMobileDetailRow(
            'Working Hr',
            record.workingHoursFormatted,
            'Pending Hr',
            record.pendingHoursFormatted,
          ),
          const SizedBox(height: 9),
          _managerMobileDetailRow(
            'Absence',
            record.countsAsAbsent ? 'Absent' : 'Present',
            'Permission',
            record.permissionActivityLabel,
            firstValueColor: record.countsAsAbsent
                ? _ManagerLogTheme.danger
                : _ManagerLogTheme.success,
          ),
        ],
      ),
    );
  }

  Widget _managerMobileDetailRow(
    String firstLabel,
    String firstValue,
    String secondLabel,
    String secondValue, {
    Color? firstValueColor,
    Color? secondValueColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final firstColumnWidth = constraints.maxWidth * 0.43;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: firstColumnWidth,
              child: _managerMobileDetailText(
                firstLabel,
                firstValue,
                valueColor: firstValueColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _managerMobileDetailText(
                secondLabel,
                secondValue,
                valueColor: secondValueColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _managerMobileDetailText(
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: TextStyle(color: valueColor ?? _ManagerLogTheme.text),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: const TextStyle(
        color: _ManagerLogTheme.muted,
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

Widget _identity(AttendanceModel record) {
  return Row(
    children: [
      _ManagerLogAvatar(record: record),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.displayEmployeeName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ManagerLogTheme.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              record.displayEmployeeId,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ManagerLogTheme.muted.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _mutedText(String value) {
  return Text(
    value,
    style: const TextStyle(
      color: _ManagerLogTheme.muted,
      fontSize: 13,
    ),
  );
}

Widget _primaryText(String value) {
  return Text(
    value,
    style: const TextStyle(
      color: _ManagerLogTheme.primary,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

Widget _pendingText(AttendanceModel record) {
  final hasPending = record.displayPendingMinutes > 0;
  return Text(
    record.pendingHoursFormatted,
    style: TextStyle(
      color: hasPending ? _ManagerLogTheme.danger : _ManagerLogTheme.success,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

Widget _absenceText(AttendanceModel record) {
  final normalized = record.pendingAbsenceLabel.toLowerCase();
  final color = normalized.contains('leave')
      ? _ManagerLogTheme.blue
      : normalized.contains('absent')
          ? _ManagerLogTheme.danger
          : _ManagerLogTheme.success;
  return Text(
    record.pendingAbsenceLabel,
    style: TextStyle(
      color: color,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

Widget _statusBadge(AttendanceModel record) {
  final label = _statusLabel(record);
  if (label.isEmpty) return const SizedBox.shrink();
  final color = _statusColor(record);
  return Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

String _statusLabel(AttendanceModel record) {
  if (record.policyAction == 'half_day_leave') return 'Half Day';
  if (record.statusLabel == 'Leave') return 'Leave';
  if (record.countsAsAbsent || record.statusLabel == 'Absent') return 'Absent';
  if (record.countsAsLate) return 'Late';
  if (record.countsAsPresent || record.checkInTime != null) return 'Present';
  return '';
}

Color _statusColor(AttendanceModel record) {
  if (record.policyAction == 'half_day_leave') return _ManagerLogTheme.cyan;
  if (record.statusLabel == 'Leave') return _ManagerLogTheme.blue;
  if (record.countsAsAbsent || record.statusLabel == 'Absent') {
    return _ManagerLogTheme.danger;
  }
  if (record.countsAsLate) return _ManagerLogTheme.warning;
  return _ManagerLogTheme.success;
}

class _ManagerLogAvatar extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerLogAvatar({required this.record});

  @override
  Widget build(BuildContext context) {
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
      radius: 17,
      backgroundColor: record.identityCleared
          ? _ManagerLogTheme.header
          : _avatarColor(record.employeeName),
      backgroundImage: profileImage,
      child: record.identityCleared || profileImage != null
          ? null
          : Text(
              _initials(record.employeeName),
              style: const TextStyle(
                color: _ManagerLogTheme.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  return parts
      .map((part) => part.isNotEmpty ? part[0] : '')
      .take(2)
      .join()
      .toUpperCase();
}

Color _avatarColor(String name) {
  const colors = [
    _ManagerLogTheme.indigo,
    _ManagerLogTheme.success,
    _ManagerLogTheme.warning,
    _ManagerLogTheme.danger,
    _ManagerLogTheme.info,
  ];
  return colors[name.length % colors.length];
}

Color _checkInColor(AttendanceModel record) {
  switch (record.arrivalBand) {
    case 'green':
      return _ManagerLogTheme.success;
    case 'orange':
      return _ManagerLogTheme.warning;
    case 'red':
      return _ManagerLogTheme.danger;
    case 'blue':
      return _ManagerLogTheme.info;
    default:
      return _ManagerLogTheme.muted;
  }
}
