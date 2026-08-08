import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../widgets/dashboard/export_dropdown.dart';
import '../../widgets/dashboard/holiday_calendar_widget.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  DateTime _calendarMonth = DateTime.now();
  DateTime? _selectedDate;

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
                'Attendance History',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppThemeColors.darkText,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 1000;
                  final table = AdminAttendanceHistoryTable(
                    attendanceService: AttendanceService(),
                    title: 'Full Attendance History',
                    emptyMessage: 'No attendance records available yet.',
                    selectedDate: _selectedDate,
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
                        if (_selectedDate != null &&
                            _selectedDate!.year == date.year &&
                            _selectedDate!.month == date.month &&
                            _selectedDate!.day == date.day) {
                          _selectedDate = null;
                        } else {
                          _selectedDate = date;
                        }
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

class AdminAttendanceHistoryTable extends StatefulWidget {
  final AttendanceService attendanceService;
  final String title;
  final String emptyMessage;
  final DateTime? selectedDate;

  const AdminAttendanceHistoryTable({
    super.key,
    required this.attendanceService,
    required this.title,
    required this.emptyMessage,
    this.selectedDate,
  });

  @override
  State<AdminAttendanceHistoryTable> createState() =>
      _AdminAttendanceHistoryTableState();
}

class _AdminAttendanceHistoryTableState
    extends State<AdminAttendanceHistoryTable> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Today', 'Weekly', 'Monthly'

  int _filterMonth = DateTime.now().month;
  int _filterYear = DateTime.now().year;

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  List<int> get _years {
    final currentYear = DateTime.now().year;
    return List.generate(11, (index) => currentYear - 5 + index);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildMonthYearSelectors({bool isMobile = false}) {
    final monthDropdown = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _AdminHistoryTheme.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AdminHistoryTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _filterMonth,
          dropdownColor: _AdminHistoryTheme.surface,
          icon: const Icon(Icons.arrow_drop_down,
              color: _AdminHistoryTheme.muted),
          style: const TextStyle(
            color: _AdminHistoryTheme.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          isExpanded: isMobile,
          items: List.generate(12, (index) {
            return DropdownMenuItem<int>(
              value: index + 1,
              child: Text(_months[index]),
            );
          }),
          onChanged: (val) {
            if (val != null) {
              setState(() => _filterMonth = val);
            }
          },
        ),
      ),
    );

    final yearDropdown = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _AdminHistoryTheme.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AdminHistoryTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _filterYear,
          dropdownColor: _AdminHistoryTheme.surface,
          icon: const Icon(Icons.arrow_drop_down,
              color: _AdminHistoryTheme.muted),
          style: const TextStyle(
            color: _AdminHistoryTheme.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          isExpanded: isMobile,
          items: _years.map((year) {
            return DropdownMenuItem<int>(
              value: year,
              child: Text(year.toString()),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _filterYear = val);
            }
          },
        ),
      ),
    );

    return Row(
      mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
      children: [
        isMobile ? Expanded(child: monthDropdown) : monthDropdown,
        const SizedBox(width: 8),
        isMobile ? Expanded(child: yearDropdown) : yearDropdown,
      ],
    );
  }

  Stream<List<AttendanceModel>> _getStream() {
    switch (_selectedFilter) {
      case 'Today':
        return widget.attendanceService.getTodayAttendanceStream();
      case 'Weekly':
        return widget.attendanceService.getWeeklyAttendanceStreamAll();
      case 'Monthly':
        return widget.attendanceService.getMonthlyAttendanceStreamAll(
          forMonth: DateTime(_filterYear, _filterMonth),
        );
      default:
        return widget.attendanceService.getAttendanceHistoryStreamAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceModel>>(
      stream: _getStream(),
      builder: (context, snapshot) {
        var records = snapshot.data ?? const <AttendanceModel>[];
        if (widget.selectedDate != null) {
          records = records
              .where((record) => _isSameDate(record.date, widget.selectedDate!))
              .toList();
        }

        // Apply local search filtering
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          records = records.where((r) {
            return r.displayEmployeeName.toLowerCase().contains(query) ||
                r.displayEmployeeId.toLowerCase().contains(query);
          }).toList();
        }

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _AdminHistoryTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _AdminHistoryTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _AdminHistoryTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Header with Search & Filter ---
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 26,
                      isMobile ? 16 : 28,
                      isMobile ? 16 : 26,
                      isMobile ? 12 : 24,
                    ),
                    child: Column(
                      children: [
                        if (isMobile)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: const TextStyle(
                                  color: _AdminHistoryTheme.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  if (widget.selectedDate != null)
                                    _dateBadge(widget.selectedDate!),
                                  if (records.isNotEmpty)
                                    ExportDropdown(
                                      records: records,
                                      fileNamePrefix:
                                          "Admin_Attendance_$_selectedFilter",
                                      fileNameBuilder: _buildExportFileName,
                                    ),
                                  _countBadge(records.length),
                                ],
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: const TextStyle(
                                    color: _AdminHistoryTheme.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (widget.selectedDate != null) ...[
                                _dateBadge(widget.selectedDate!),
                                const SizedBox(width: 12),
                              ],
                              if (records.isNotEmpty) ...[
                                ExportDropdown(
                                  records: records,
                                  fileNamePrefix:
                                      "Admin_Attendance_$_selectedFilter",
                                  fileNameBuilder: _buildExportFileName,
                                ),
                                const SizedBox(width: 12),
                              ],
                              _countBadge(records.length),
                            ],
                          ),
                        const SizedBox(height: 20),
                        isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    onChanged: (v) =>
                                        setState(() => _searchQuery = v),
                                    cursorColor: _AdminHistoryTheme.primary,
                                    style: const TextStyle(
                                      color: _AdminHistoryTheme.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Search by employee or ID...',
                                      hintStyle: TextStyle(
                                        color: _AdminHistoryTheme.muted
                                            .withValues(alpha: 0.5),
                                        fontSize: 13,
                                      ),
                                      prefixIcon: const Icon(Icons.search,
                                          size: 18,
                                          color: _AdminHistoryTheme.primary),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                size: 16,
                                                color: _AdminHistoryTheme.muted,
                                              ),
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(
                                                    () => _searchQuery = '');
                                              },
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: _AdminHistoryTheme.header,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 0),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_selectedFilter == 'Monthly') ...[
                                    _buildMonthYearSelectors(isMobile: true),
                                    const SizedBox(height: 12),
                                  ],
                                  _buildFilterSelector(isMobile: true),
                                ],
                              )
                            : Row(
                                children: [
                                  // Search Field
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: (v) =>
                                          setState(() => _searchQuery = v),
                                      cursorColor: _AdminHistoryTheme.primary,
                                      style: const TextStyle(
                                        color: _AdminHistoryTheme.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Search by employee or ID...',
                                        hintStyle: TextStyle(
                                          color: _AdminHistoryTheme.muted
                                              .withValues(alpha: 0.5),
                                          fontSize: 13,
                                        ),
                                        prefixIcon: const Icon(Icons.search,
                                            size: 18,
                                            color: _AdminHistoryTheme.primary),
                                        suffixIcon: _searchQuery.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.clear,
                                                  size: 16,
                                                  color:
                                                      _AdminHistoryTheme.muted,
                                                ),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  setState(
                                                      () => _searchQuery = '');
                                                },
                                              )
                                            : null,
                                        filled: true,
                                        fillColor: _AdminHistoryTheme.header,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 0),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (_selectedFilter == 'Monthly') ...[
                                    _buildMonthYearSelectors(isMobile: false),
                                    const SizedBox(width: 12),
                                  ],
                                  // Filter Selector
                                  _buildFilterSelector(isMobile: false),
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
                        color: _AdminHistoryTheme.header,
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: _AdminHistoryTheme.border,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          _AdminHistoryTableHeader('EMPLOYEE', flex: 30),
                          _AdminHistoryTableHeader('DATE', flex: 20),
                          _AdminHistoryTableHeader('DESIGNATION', flex: 20),
                          _AdminHistoryTableHeader('STATUS', flex: 20),
                          _AdminHistoryTableHeader('CHECK-IN', flex: 15),
                          _AdminHistoryTableHeader('CHECK-OUT', flex: 15),
                          _AdminHistoryTableHeader('WORKING HRS/MIN', flex: 18),
                          _AdminHistoryTableHeader('PENDING HRS', flex: 16),
                          _AdminHistoryTableHeader('PERMISSION HR', flex: 16),
                          _AdminHistoryTableHeader('ABSENT / PRESENT',
                              flex: 16),
                        ],
                      ),
                    ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _AdminHistoryTheme.primary,
                        ),
                      ),
                    )
                  else if (records.isEmpty)
                    SizedBox(
                      height: 152,
                      child: Center(
                        child: Text(
                          widget.emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _AdminHistoryTheme.muted
                                .withValues(alpha: 0.75),
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
                        color: _AdminHistoryTheme.border,
                      ),
                      itemBuilder: (context, index) => isMobile
                          ? _AdminAttendanceMobileCard(record: records[index])
                          : _AdminAttendanceRow(record: records[index]),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _buildExportFileName(List<AttendanceModel> records) {
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);
    final day = DateFormat('EEEE').format(now);
    final personName = _exportPersonName(records);
    final base = personName == null
        ? 'Admin_Attendance_$_selectedFilter'
        : '${personName}_Attendance';
    return '${_safeFileNamePart(base)}_${date}_$day';
  }

  String? _exportPersonName(List<AttendanceModel> records) {
    if (_searchQuery.trim().isEmpty || records.isEmpty) return null;

    final normalizedNames = records
        .map((record) => record.displayEmployeeName.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (normalizedNames.length == 1) return normalizedNames.first;

    final normalizedIds = records
        .map((record) => record.displayEmployeeId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (normalizedIds.length == 1) {
      final matchingRecord = records.firstWhere(
        (record) => record.displayEmployeeId.trim() == normalizedIds.first,
      );
      return matchingRecord.displayEmployeeName.trim().isEmpty
          ? normalizedIds.first
          : matchingRecord.displayEmployeeName.trim();
    }

    return null;
  }

  String _safeFileNamePart(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'Attendance' : cleaned;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _countBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _AdminHistoryTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '$count records',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: _AdminHistoryTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _dateBadge(DateTime date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _AdminHistoryTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        DateFormat('dd/MM/yyyy').format(date),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: _AdminHistoryTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildFilterSelector({bool isMobile = false}) {
    return Container(
      height: 40,
      width: isMobile ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _AdminHistoryTheme.header,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
        children: ['All', 'Today', 'Weekly', 'Monthly'].map((f) {
          final isSel = _selectedFilter == f;
          Widget item = GestureDetector(
            onTap: () => setState(() => _selectedFilter = f),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isSel ? _AdminHistoryTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                f,
                style: TextStyle(
                  color: isSel
                      ? _AdminHistoryTheme.white
                      : _AdminHistoryTheme.muted,
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
          if (isMobile) {
            return Expanded(child: item);
          }
          return item;
        }).toList(),
      ),
    );
  }
}

class _AdminHistoryTheme {
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

class _AdminHistoryTableHeader extends StatelessWidget {
  final String label;
  final int flex;

  const _AdminHistoryTableHeader(this.label,
      {required this.flex}); // ignore: prefer_const_constructors

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          color: _AdminHistoryTheme.muted.withValues(alpha: 0.78),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminAttendanceRow extends StatelessWidget {
  final AttendanceModel record;

  const _AdminAttendanceRow({required this.record});

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
              Expanded(
                flex: 30,
                child: Row(
                  children: [
                    _AdminAttendanceAvatar(record: record, radius: 17),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.displayEmployeeName,
                            style: const TextStyle(
                              color: _AdminHistoryTheme.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            record.displayEmployeeId,
                            style: TextStyle(
                              color: _AdminHistoryTheme.muted
                                  .withValues(alpha: 0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 20,
                child: Text(
                  record.dateFormatted,
                  style: const TextStyle(
                    color: _AdminHistoryTheme.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 20,
                child: Text(
                  record.displayDepartment,
                  style: const TextStyle(
                    color: _AdminHistoryTheme.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: isOnLeave
                      ? const SizedBox.shrink()
                      : _AdminStatusBadge(record: record),
                ),
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
                    : Text(
                        record.checkOutFormatted,
                        style: TextStyle(
                          color: record.isCheckedOut
                              ? _AdminHistoryTheme.primary
                              : _AdminHistoryTheme.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              Expanded(
                flex: 18,
                child: isOnLeave
                    ? const Text('')
                    : Text(
                        record.workingHoursFormatted,
                        style: TextStyle(
                          color: record.workingDuration == null
                              ? _AdminHistoryTheme.muted.withValues(alpha: 0.75)
                              : _AdminHistoryTheme.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave
                    ? const Text('')
                    : _AdminPendingText(record: record),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave
                    ? const Text('')
                    : Text(
                        record.permissionHoursFormatted,
                        style: TextStyle(
                          color: record.permissionMinutes > 0
                              ? _AdminHistoryTheme.primary
                              : _AdminHistoryTheme.muted,
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
                          color: _AdminHistoryTheme.danger,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _AdminPendingAbsenceText(record: record),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _checkInColor(AttendanceModel record) {
    switch (record.arrivalBand) {
      case 'green':
        return _AdminHistoryTheme.success;
      case 'orange':
        return _AdminHistoryTheme.warning;
      case 'red':
        return _AdminHistoryTheme.danger;
      case 'blue':
        return _AdminHistoryTheme.info;
      default:
        return _AdminHistoryTheme.muted;
    }
  }
}

class _AdminStatusBadge extends StatelessWidget {
  final AttendanceModel record;

  const _AdminStatusBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(record);
    if (label.isEmpty) return const SizedBox.shrink();
    final foreground = _statusColor(record);
    final icon = _statusIcon(record);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(AttendanceModel record) {
    if (record.policyAction == 'half_day_leave') return 'Half Day';
    if (record.statusLabel == 'Leave') return 'Leave';
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return 'Absent';
    }
    if (record.countsAsLate) return 'Late';
    if (record.countsAsPresent || record.checkInTime != null) {
      return 'Present';
    }
    return '';
  }

  Color _statusColor(AttendanceModel record) {
    if (record.policyAction == 'half_day_leave') return _AdminHistoryTheme.cyan;
    if (record.statusLabel == 'Leave') return _AdminHistoryTheme.blue;
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return _AdminHistoryTheme.danger;
    }
    if (record.countsAsLate) return _AdminHistoryTheme.warning;
    return _AdminHistoryTheme.success;
  }

  IconData _statusIcon(AttendanceModel record) {
    if (record.policyAction == 'half_day_leave' ||
        record.statusLabel == 'Leave') {
      return Icons.event_available_rounded;
    }
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return Icons.cancel_outlined;
    }
    if (record.countsAsLate) return Icons.access_time;
    return Icons.check;
  }
}

class _AdminAttendanceMobileCard extends StatelessWidget {
  final AttendanceModel record;

  const _AdminAttendanceMobileCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final status = _mobileStatus(record);
    final absenceColor = record.countsAsAbsent
        ? _AdminHistoryTheme.danger
        : _AdminHistoryTheme.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminAttendanceAvatar(record: record, radius: 17),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.displayEmployeeName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminHistoryTheme.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      record.displayEmployeeId,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _AdminHistoryTheme.muted.withValues(alpha: 0.8),
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
            'Date',
            record.dateFormatted,
            'Designation',
            record.displayDepartment.isEmpty ? '-' : record.displayDepartment,
          ),
          const SizedBox(height: 9),
          _mobileDetailRow(
            'Check-in',
            record.checkInFormatted,
            'Check-out',
            record.checkOutFormatted,
          ),
          const SizedBox(height: 9),
          _mobileDetailRow(
            'Working Hr',
            record.workingHoursFormatted,
            'Pending Hr',
            record.pendingHoursFormatted,
          ),
          const SizedBox(height: 9),
          _mobileDetailRow(
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

  _AdminMobileAttendanceStatus _mobileStatus(AttendanceModel record) {
    if (record.policyAction == 'half_day_leave') {
      return const _AdminMobileAttendanceStatus(
        label: 'Half Day',
        color: _AdminHistoryTheme.cyan,
      );
    }
    if (record.statusLabel == 'Leave') {
      return const _AdminMobileAttendanceStatus(
        label: 'Leave',
        color: _AdminHistoryTheme.blue,
      );
    }
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return const _AdminMobileAttendanceStatus(
        label: 'Absent',
        color: _AdminHistoryTheme.danger,
      );
    }
    if (record.countsAsLate) {
      return const _AdminMobileAttendanceStatus(
        label: 'Late',
        color: _AdminHistoryTheme.warning,
      );
    }
    return const _AdminMobileAttendanceStatus(
      label: 'Present',
      color: _AdminHistoryTheme.success,
    );
  }

  Widget _mobileStatusBadge(_AdminMobileAttendanceStatus status) {
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
    String firstLabel,
    String firstValue,
    String secondLabel,
    String secondValue, {
    Color? firstValueColor,
    Color? secondValueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: _mobileDetailText(
            firstLabel,
            firstValue,
            valueColor: firstValueColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _mobileDetailText(
            secondLabel,
            secondValue,
            valueColor: secondValueColor,
          ),
        ),
      ],
    );
  }

  Widget _mobileDetailText(
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
            style: TextStyle(color: valueColor ?? _AdminHistoryTheme.text),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: const TextStyle(
        color: _AdminHistoryTheme.muted,
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _AdminMobileAttendanceStatus {
  final String label;
  final Color color;

  const _AdminMobileAttendanceStatus({
    required this.label,
    required this.color,
  });
}

class _AdminPendingText extends StatelessWidget {
  final AttendanceModel record;

  const _AdminPendingText({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasPending = record.displayPendingMinutes > 0;
    return Text(
      record.pendingHoursFormatted,
      style: TextStyle(
        color:
            hasPending ? _AdminHistoryTheme.danger : _AdminHistoryTheme.success,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AdminAttendanceAvatar extends StatelessWidget {
  final AttendanceModel record;
  final double radius;

  const _AdminAttendanceAvatar({
    required this.record,
    required this.radius,
  });

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
      radius: radius,
      backgroundColor: record.identityCleared
          ? _AdminHistoryTheme.header
          : _avatarColor(record.employeeName),
      backgroundImage: profileImage,
      child: record.identityCleared || photoBytes != null || hasNetworkPhoto
          ? null
          : Text(
              _initials(record.employeeName),
              style: TextStyle(
                color: _AdminHistoryTheme.white,
                fontSize: radius <= 16 ? 10 : 11,
                fontWeight: FontWeight.w700,
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

  Color _avatarColor(String name) {
    const colors = [
      _AdminHistoryTheme.indigo,
      _AdminHistoryTheme.success,
      _AdminHistoryTheme.warning,
      _AdminHistoryTheme.danger,
      _AdminHistoryTheme.info,
    ];
    return colors[name.length % colors.length];
  }
}

class _AdminPendingAbsenceText extends StatelessWidget {
  final AttendanceModel record;

  const _AdminPendingAbsenceText({required this.record});

  @override
  Widget build(BuildContext context) {
    final normalized = record.pendingAbsenceLabel.toLowerCase();
    final color = normalized.contains('absent')
        ? _AdminHistoryTheme.danger
        : normalized.contains('late')
            ? _AdminHistoryTheme.warning
            : normalized.contains('leave')
                ? _AdminHistoryTheme.blue
                : _AdminHistoryTheme.success;
    return Text(
      record.pendingAbsenceLabel,
      style: TextStyle(
        color: color,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
