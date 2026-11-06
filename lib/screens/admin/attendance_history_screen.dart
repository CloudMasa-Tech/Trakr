import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../widgets/dashboard/export_dropdown.dart';

/// Attendance Monitoring — the records view a manager opens to understand
/// what a person actually did: when they arrived, when they left, how long
/// they worked, and whether a missing day was leave or an absence.
///
/// Design notes (why this is shaped the way it is):
///  * ONE status per day. The previous table carried two competing status
///    columns ("STATUS" and "ABSENT / PRESENT") that could disagree, and an
///    approved leave day rendered with a blank status plus the word "Absent".
///    [_DayOutcome] now resolves attendance + leave into a single verdict
///    that the badge, the summary tiles and the detail panel all read from.
///  * Leave is loaded once, not per row. See
///    [AttendanceService.loadApprovedLeaveIndex].
///  * Totals before details. A manager scanning a month wants the shape of it
///    first; the summary tiles double as filters.
///  * Jargon is explained in place rather than assumed ("Shortfall",
///    "Permission").
class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  DateTime? _selectedDate;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
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
              // Matches the sidebar label. The page used to be headed
              // "Attendance History" while the nav item said "Attendance
              // Monitoring", so you could never be sure you were where you
              // meant to be.
              const Text(
                'Attendance Monitoring',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppThemeColors.darkText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Check-in, check-out, worked hours and approved leave for '
                'every team member.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 22),
              AdminAttendanceHistoryTable(
                attendanceService: AttendanceService(),
                title: 'Attendance Records',
                emptyMessage: 'No attendance records available yet.',
                selectedDate: _selectedDate,
                onPickDate: _pickDate,
                onClearDate: () => setState(() => _selectedDate = null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Day outcome — the single source of truth for "what happened that day"
// ═══════════════════════════════════════════════════════════════════════

enum _DayKind { present, late, halfDay, onLeave, absent, noRecord }

/// Attendance record + approved leave, resolved into one verdict.
class _DayOutcome {
  final AttendanceModel record;
  final ApprovedLeaveSpan? leave;

  const _DayOutcome({required this.record, this.leave});

  _DayKind get kind {
    final l = leave;
    // Approved leave outranks everything the attendance doc says. A person
    // on sanctioned leave is NOT absent, which is how the old view read.
    if (l != null) return l.isHalfDay ? _DayKind.halfDay : _DayKind.onLeave;
    if (record.policyAction == 'half_day_leave') return _DayKind.halfDay;
    if (record.statusLabel == 'Leave') return _DayKind.onLeave;
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return _DayKind.absent;
    }
    if (record.countsAsLate) return _DayKind.late;
    if (record.countsAsPresent || record.checkInTime != null) {
      return _DayKind.present;
    }
    return _DayKind.noRecord;
  }

  /// True when the person was at work in some capacity — used to decide
  /// whether the time columns carry any meaning for this row.
  bool get attended => record.checkInTime != null;

  String get label {
    switch (kind) {
      case _DayKind.present:
        return 'Present';
      case _DayKind.late:
        return 'Late';
      case _DayKind.halfDay:
        return 'Half Day';
      case _DayKind.onLeave:
        return 'On Leave';
      case _DayKind.absent:
        return 'Absent';
      case _DayKind.noRecord:
        return 'No Record';
    }
  }

  /// The second line under the badge: the reason in plain words.
  String? get detail {
    final l = leave;
    if (l != null) {
      final paid = l.isPaid ? 'Paid' : 'Unpaid';
      return '${l.type} · $paid';
    }
    switch (kind) {
      case _DayKind.late:
        return record.lateMinutes > 0
            ? 'Arrived ${_humanMinutes(record.lateMinutes)} late'
            : null;
      case _DayKind.absent:
        return record.checkInTime == null ? 'No check-in recorded' : null;
      case _DayKind.present:
        return record.isCheckedOut ? null : 'Still checked in';
      default:
        return null;
    }
  }

  Color get color {
    switch (kind) {
      case _DayKind.present:
        return _T.success;
      case _DayKind.late:
        return _T.warning;
      case _DayKind.halfDay:
        return _T.cyan;
      case _DayKind.onLeave:
        return _T.blue;
      case _DayKind.absent:
        return _T.danger;
      case _DayKind.noRecord:
        return _T.muted;
    }
  }

  IconData get icon {
    switch (kind) {
      case _DayKind.present:
        return Icons.check_circle_rounded;
      case _DayKind.late:
        return Icons.schedule_rounded;
      case _DayKind.halfDay:
        return Icons.timelapse_rounded;
      case _DayKind.onLeave:
        return Icons.beach_access_rounded;
      case _DayKind.absent:
        return Icons.cancel_rounded;
      case _DayKind.noRecord:
        return Icons.help_outline_rounded;
    }
  }
}

String _humanMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

// ═══════════════════════════════════════════════════════════════════════
// Records table
// ═══════════════════════════════════════════════════════════════════════

class AdminAttendanceHistoryTable extends StatefulWidget {
  final AttendanceService attendanceService;
  final String title;
  final String emptyMessage;
  final DateTime? selectedDate;
  final VoidCallback? onPickDate;
  final VoidCallback? onClearDate;

  const AdminAttendanceHistoryTable({
    super.key,
    required this.attendanceService,
    required this.title,
    required this.emptyMessage,
    this.selectedDate,
    this.onPickDate,
    this.onClearDate,
  });

  @override
  State<AdminAttendanceHistoryTable> createState() =>
      _AdminAttendanceHistoryTableState();
}

class _AdminAttendanceHistoryTableState
    extends State<AdminAttendanceHistoryTable> {
  static const int _pageSize = 40;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Today', 'Weekly', 'Monthly'

  /// Summary-tile drill-down. Null means "show everything".
  _DayKind? _kindFilter;

  int _filterMonth = DateTime.now().month;
  int _filterYear = DateTime.now().year;
  int _visibleCount = _pageSize;
  bool _legendOpen = false;
  final Set<String> _expandedRows = <String>{};

  late Future<ApprovedLeaveIndex> _leaveIndexFuture;

  @override
  void initState() {
    super.initState();
    _leaveIndexFuture = widget.attendanceService.loadApprovedLeaveIndex();
  }

  void _reloadLeave() {
    setState(() {
      _leaveIndexFuture = widget.attendanceService.loadApprovedLeaveIndex();
    });
  }

  final List<String> _months = const [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
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
    return FutureBuilder<ApprovedLeaveIndex>(
      future: _leaveIndexFuture,
      builder: (context, leaveSnap) {
        final leaveIndex = leaveSnap.data ?? const ApprovedLeaveIndex.empty();
        final leaveLoading =
            leaveSnap.connectionState == ConnectionState.waiting;

        return StreamBuilder<List<AttendanceModel>>(
          stream: _getStream(),
          builder: (context, snapshot) {
            final loading =
                snapshot.connectionState == ConnectionState.waiting ||
                    leaveLoading;

            // ── Resolve every record into a single verdict, once ──────────
            var outcomes = (snapshot.data ?? const <AttendanceModel>[])
                .map((r) => _DayOutcome(
                      record: r,
                      leave: leaveIndex.lookup(r.employeeId, r.date),
                    ))
                .toList();

            if (widget.selectedDate != null) {
              outcomes = outcomes
                  .where((o) =>
                      _isSameDate(o.record.date, widget.selectedDate!))
                  .toList();
            }

            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              outcomes = outcomes.where((o) {
                return o.record.displayEmployeeName
                        .toLowerCase()
                        .contains(q) ||
                    o.record.displayEmployeeId.toLowerCase().contains(q);
              }).toList();
            }

            // Tiles summarise everything matching the period + search, so
            // the numbers stay stable while drilling into one of them.
            final summary = _Summary.from(outcomes);

            if (_kindFilter != null) {
              outcomes =
                  outcomes.where((o) => o.kind == _kindFilter).toList();
            }

            // Newest first, then alphabetical — a predictable order beats
            // whatever order the query happened to return.
            outcomes.sort((a, b) {
              final byDate = b.record.date.compareTo(a.record.date);
              if (byDate != 0) return byDate;
              return a.record.displayEmployeeName
                  .toLowerCase()
                  .compareTo(b.record.displayEmployeeName.toLowerCase());
            });

            final records = outcomes.map((o) => o.record).toList();
            final visible = outcomes.take(_visibleCount).toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 760;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryBand(
                      summary: summary,
                      active: _kindFilter,
                      loading: loading,
                      onSelect: (kind) => setState(() {
                        _kindFilter = _kindFilter == kind ? null : kind;
                        _visibleCount = _pageSize;
                      }),
                    ),
                    const SizedBox(height: 18),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildToolbar(records, isMobile),
                          if (_kindFilter != null)
                            _buildActiveFilterStrip(outcomes.length),
                          if (!isMobile) _buildTableHeader(),
                          if (loading)
                            const SizedBox(
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: _T.primary),
                              ),
                            )
                          else if (visible.isEmpty)
                            _buildEmptyState()
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: _T.border,
                              ),
                              itemBuilder: (context, index) {
                                final outcome = visible[index];
                                final key = _rowKey(outcome.record);
                                return _AttendanceRecordTile(
                                  outcome: outcome,
                                  compact: isMobile,
                                  expanded: _expandedRows.contains(key),
                                  onToggle: () => setState(() {
                                    if (!_expandedRows.remove(key)) {
                                      _expandedRows.add(key);
                                    }
                                  }),
                                );
                              },
                            ),
                          if (!loading && outcomes.length > visible.length)
                            _buildShowMore(outcomes.length, visible.length),
                          _buildLegend(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _rowKey(AttendanceModel r) => '${r.employeeId}|${r.dateKey}';

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _T.border),
        boxShadow: const [
          BoxShadow(color: _T.shadow, blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }

  // ── Toolbar ──────────────────────────────────────────────────────────
  Widget _buildToolbar(List<AttendanceModel> records, bool isMobile) {
    final searchField = TextField(
      controller: _searchController,
      onChanged: (v) => setState(() {
        _searchQuery = v;
        _visibleCount = _pageSize;
      }),
      cursorColor: _T.primary,
      style: const TextStyle(
        color: _T.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: 'Search by employee name or ID…',
        hintStyle: TextStyle(
          color: _T.muted.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        prefixIcon: const Icon(Icons.search, size: 18, color: _T.primary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear, size: 16, color: _T.muted),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: _T.header,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 26,
        isMobile ? 16 : 24,
        isMobile ? 16 : 26,
        isMobile ? 12 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _T.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh leave data',
                onPressed: _reloadLeave,
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: _T.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _periodChip(),
              if (widget.selectedDate != null) _dateBadge(widget.selectedDate!),
              _countBadge(records.length),
              if (records.isNotEmpty)
                ExportDropdown(
                  records: records,
                  fileNamePrefix: 'Attendance_$_selectedFilter',
                  fileNameBuilder: _buildExportFileName,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (isMobile) ...[
            searchField,
            const SizedBox(height: 12),
            if (_selectedFilter == 'Monthly') ...[
              _buildMonthYearSelectors(isMobile: true),
              const SizedBox(height: 12),
            ],
            _buildFilterSelector(isMobile: true),
          ] else
            Row(
              children: [
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: 12),
                if (_selectedFilter == 'Monthly') ...[
                  _buildMonthYearSelectors(isMobile: false),
                  const SizedBox(width: 12),
                ],
                _buildFilterSelector(isMobile: false),
              ],
            ),
        ],
      ),
    );
  }

  /// Spells out the period in words. "All / Today / Weekly / Monthly" alone
  /// never told you which month you were actually looking at.
  Widget _periodChip() {
    String text;
    switch (_selectedFilter) {
      case 'Today':
        text = DateFormat('EEEE, d MMM yyyy').format(DateTime.now());
        break;
      case 'Weekly':
        text = 'This week';
        break;
      case 'Monthly':
        text = DateFormat('MMMM yyyy')
            .format(DateTime(_filterYear, _filterMonth));
        break;
      default:
        text = 'All time';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _T.header,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _T.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.date_range_rounded, size: 13, color: _T.muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: _T.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterStrip(int count) {
    final kind = _kindFilter!;
    final sample = _DayKindStyle.of(kind);
    return Container(
      margin: const EdgeInsets.fromLTRB(26, 0, 26, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: sample.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sample.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(sample.icon, size: 15, color: sample.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing $count ${sample.label.toLowerCase()} '
              '${count == 1 ? 'record' : 'records'} only.',
              style: TextStyle(
                color: sample.color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _kindFilter = null),
            style: TextButton.styleFrom(
              foregroundColor: sample.color,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Show all'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
      decoration: const BoxDecoration(
        color: _T.header,
        border: Border.symmetric(horizontal: BorderSide(color: _T.border)),
      ),
      child: const Row(
        children: [
          _Th('EMPLOYEE', flex: 26),
          _Th('DATE', flex: 15),
          _Th('DAY', flex: 20),
          _Th('IN', flex: 11),
          _Th('OUT', flex: 11),
          _Th('WORKED', flex: 13),
          _Th('SHORTFALL', flex: 13, tip:
              'Time owed for the day: late arrival + early check-out + '
              'approved step-out time.'),
          _Th('PERMISSION', flex: 13, tip:
              'Approved time spent away from the office during the day.'),
          SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _searchQuery.isNotEmpty ||
        _kindFilter != null ||
        widget.selectedDate != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 24),
      child: Column(
        children: [
          Icon(
            filtered ? Icons.filter_alt_off_rounded : Icons.inbox_rounded,
            size: 34,
            color: _T.muted.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'No records match these filters.'
                : widget.emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _T.muted.withValues(alpha: 0.85),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (filtered) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                widget.onClearDate?.call();
                setState(() {
                  _searchQuery = '';
                  _kindFilter = null;
                });
              },
              style: TextButton.styleFrom(foregroundColor: _T.primary),
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Clear all filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShowMore(int total, int shown) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _T.border)),
      ),
      child: Center(
        child: TextButton.icon(
          onPressed: () => setState(() => _visibleCount += _pageSize),
          style: TextButton.styleFrom(foregroundColor: _T.primary),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: Text('Show more  ·  $shown of $total'),
        ),
      ),
    );
  }

  /// Plain-language definitions, collapsed by default. "Pending Hrs" and
  /// "Permission Hr" were column headings nobody outside the team could read.
  Widget _buildLegend() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _T.border)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _legendOpen,
          onExpansionChanged: (v) => setState(() => _legendOpen = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 26),
          childrenPadding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
          iconColor: _T.muted,
          collapsedIconColor: _T.muted,
          leading: const Icon(Icons.help_outline_rounded,
              size: 18, color: _T.muted),
          title: const Text(
            'What do these statuses and columns mean?',
            style: TextStyle(
              color: _T.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                for (final kind in _DayKind.values)
                  _legendItem(_DayKindStyle.of(kind)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _T.border),
            const SizedBox(height: 14),
            _legendLine('Worked',
                'Time between check-in and check-out, clipped to the '
                'configured office hours.'),
            _legendLine('Shortfall',
                'Time owed for the day — late arrival plus early check-out '
                'plus approved step-out time. Zero is good.'),
            _legendLine('Permission',
                'Approved time away from the office during the working day '
                '(a step-out that was signed off).'),
            _legendLine('On Leave',
                'An approved leave request covers this date. It is NOT '
                'counted as an absence.'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(_DayKindStyle style) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(style.icon, size: 14, color: style.color),
        const SizedBox(width: 6),
        Text(
          style.label,
          style: TextStyle(
            color: style.color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _legendLine(String term, String meaning) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$term — ',
              style: const TextStyle(
                color: _T.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: meaning),
          ],
        ),
        style: TextStyle(
          color: _T.muted.withValues(alpha: 0.9),
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }

  // ── Filter controls ──────────────────────────────────────────────────
  Widget _buildMonthYearSelectors({bool isMobile = false}) {
    Widget wrap(Widget child) => Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _T.header,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _T.border),
          ),
          child: DropdownButtonHideUnderline(child: child),
        );

    final monthDropdown = wrap(
      DropdownButton<int>(
        value: _filterMonth,
        dropdownColor: _T.surface,
        icon: const Icon(Icons.arrow_drop_down, color: _T.muted),
        style: const TextStyle(
          color: _T.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        isExpanded: isMobile,
        items: List.generate(
          12,
          (index) => DropdownMenuItem<int>(
            value: index + 1,
            child: Text(_months[index]),
          ),
        ),
        onChanged: (val) {
          if (val != null) {
            setState(() {
              _filterMonth = val;
              _visibleCount = _pageSize;
            });
          }
        },
      ),
    );

    final yearDropdown = wrap(
      DropdownButton<int>(
        value: _filterYear,
        dropdownColor: _T.surface,
        icon: const Icon(Icons.arrow_drop_down, color: _T.muted),
        style: const TextStyle(
          color: _T.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        isExpanded: isMobile,
        items: _years
            .map((year) => DropdownMenuItem<int>(
                  value: year,
                  child: Text(year.toString()),
                ))
            .toList(),
        onChanged: (val) {
          if (val != null) {
            setState(() {
              _filterYear = val;
              _visibleCount = _pageSize;
            });
          }
        },
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

  Widget _buildFilterSelector({bool isMobile = false}) {
    return Container(
      height: 40,
      width: isMobile ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _T.header,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
        children: [
          ...['All', 'Today', 'Weekly', 'Monthly'].map((f) {
            final isSel = _selectedFilter == f && widget.selectedDate == null;
            Widget item = GestureDetector(
              onTap: () {
                widget.onClearDate?.call();
                setState(() {
                  _selectedFilter = f;
                  _visibleCount = _pageSize;
                });
              },
              child: Container(
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isSel ? _T.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    color: isSel ? _T.white : _T.muted,
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
            return isMobile ? Expanded(child: item) : item;
          }),
          if (widget.onPickDate != null) ...[
            const SizedBox(width: 2),
            IconButton(
              tooltip: 'Filter by a specific date',
              icon: Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: widget.selectedDate != null ? _T.primary : _T.muted,
              ),
              onPressed: widget.onPickDate,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateBadge(DateTime date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _T.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_outlined, size: 13, color: _T.primary),
          const SizedBox(width: 6),
          Text(
            DateFormat('dd MMM yyyy').format(date),
            style: const TextStyle(
              color: _T.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (widget.onClearDate != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: widget.onClearDate,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child:
                    Icon(Icons.close_rounded, size: 13, color: _T.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _T.header,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _T.border),
      ),
      child: Text(
        '$count ${count == 1 ? 'record' : 'records'}',
        style: const TextStyle(
          color: _T.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── Export naming (unchanged behaviour) ──────────────────────────────
  String _buildExportFileName(List<AttendanceModel> records) {
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);
    final day = DateFormat('EEEE').format(now);
    final personName = _exportPersonName(records);
    final base = personName == null
        ? 'Attendance_$_selectedFilter'
        : '${personName}_Attendance';
    return '${_safeFileNamePart(base)}_${date}_$day';
  }

  String? _exportPersonName(List<AttendanceModel> records) {
    if (_searchQuery.trim().isEmpty || records.isEmpty) return null;
    final names = records
        .map((record) => record.displayEmployeeName.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (names.length == 1) return names.first;
    final ids = records
        .map((record) => record.displayEmployeeId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.length == 1) return ids.first;
    return null;
  }

  String _safeFileNamePart(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.replaceAll(RegExp(r'^_|_$'), '');
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ═══════════════════════════════════════════════════════════════════════
// Summary band
// ═══════════════════════════════════════════════════════════════════════

class _Summary {
  final int present;
  final int late;
  final int halfDay;
  final int onLeave;
  final int absent;
  final int totalWorkedMinutes;
  final int workedDays;

  const _Summary({
    required this.present,
    required this.late,
    required this.halfDay,
    required this.onLeave,
    required this.absent,
    required this.totalWorkedMinutes,
    required this.workedDays,
  });

  factory _Summary.from(List<_DayOutcome> outcomes) {
    var present = 0, late = 0, halfDay = 0, onLeave = 0, absent = 0;
    var minutes = 0, days = 0;
    for (final o in outcomes) {
      switch (o.kind) {
        case _DayKind.present:
          present++;
          break;
        case _DayKind.late:
          late++;
          break;
        case _DayKind.halfDay:
          halfDay++;
          break;
        case _DayKind.onLeave:
          onLeave++;
          break;
        case _DayKind.absent:
        case _DayKind.noRecord:
          absent++;
          break;
      }
      final worked = o.record.workingDuration;
      if (worked != null && worked.inMinutes > 0) {
        minutes += worked.inMinutes;
        days++;
      }
    }
    return _Summary(
      present: present,
      late: late,
      halfDay: halfDay,
      onLeave: onLeave,
      absent: absent,
      totalWorkedMinutes: minutes,
      workedDays: days,
    );
  }

  String get averageWorked {
    if (workedDays == 0) return '—';
    return _humanMinutes((totalWorkedMinutes / workedDays).round());
  }
}

class _SummaryBand extends StatelessWidget {
  final _Summary summary;
  final _DayKind? active;
  final bool loading;
  final ValueChanged<_DayKind> onSelect;

  const _SummaryBand({
    required this.summary,
    required this.active,
    required this.loading,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Every record falls into exactly one of the five status tiles, so the
    // tiles always add up to the record count shown on the table. A tile
    // that silently omitted a category (half days) made the numbers look
    // wrong for no visible reason.
    final tiles = <Widget>[
      _tile(_DayKind.present, summary.present, 'On time'),
      _tile(_DayKind.late, summary.late, 'Arrived late'),
      _tile(_DayKind.halfDay, summary.halfDay, 'Partial day'),
      _tile(_DayKind.onLeave, summary.onLeave, 'Approved leave'),
      _tile(_DayKind.absent, summary.absent, 'No attendance'),
      _StatTile(
        // Not a status, so not clickable — it reads as a figure, not a filter.
        label: 'Avg worked',
        value: loading ? '—' : summary.averageWorked,
        caption: summary.workedDays == 0
            ? 'No completed days'
            : 'Across ${summary.workedDays} '
                '${summary.workedDays == 1 ? 'day' : 'days'}',
        color: _T.primary,
        icon: Icons.timer_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth < 640
            ? 2
            : c.maxWidth < 1040
                ? 3
                : 6;
        const gap = 12.0;
        final width = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  Widget _tile(_DayKind kind, int count, String caption) {
    final style = _DayKindStyle.of(kind);
    return _StatTile(
      label: style.label,
      value: loading ? '—' : '$count',
      caption: caption,
      color: style.color,
      icon: style.icon,
      selected: active == kind,
      onTap: () => onSelect(kind),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _StatTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Tooltip(
          message: onTap == null ? '' : 'Show only $label records',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : _T.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? color : _T.border,
                width: selected ? 1.5 : 1,
              ),
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
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 14, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _T.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: const TextStyle(
                    color: _T.text,
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _T.muted.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Record row
// ═══════════════════════════════════════════════════════════════════════

class _AttendanceRecordTile extends StatelessWidget {
  final _DayOutcome outcome;
  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;

  const _AttendanceRecordTile({
    required this.outcome,
    required this.compact,
    required this.expanded,
    required this.onToggle,
  });

  AttendanceModel get record => outcome.record;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        child: Column(
          children: [
            compact ? _buildCompact() : _buildWide(),
            if (expanded) _DetailPanel(outcome: outcome),
          ],
        ),
      ),
    );
  }

  // ── Desktop row ──────────────────────────────────────────────────────
  Widget _buildWide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
      child: Row(
        children: [
          Expanded(flex: 26, child: _employeeCell()),
          Expanded(flex: 15, child: _dateCell()),
          Expanded(flex: 20, child: _DayBadge(outcome: outcome)),
          Expanded(flex: 11, child: _timeCell(isCheckIn: true)),
          Expanded(flex: 11, child: _timeCell(isCheckIn: false)),
          Expanded(flex: 13, child: _workedCell()),
          Expanded(flex: 13, child: _shortfallCell()),
          Expanded(flex: 13, child: _permissionCell()),
          SizedBox(
            width: 28,
            child: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20, color: _T.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _employeeCell() {
    return Row(
      children: [
        _Avatar(record: record, radius: 17),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.displayEmployeeName.isEmpty
                    ? 'Removed employee'
                    : record.displayEmployeeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _T.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                record.displayEmployeeId.isEmpty
                    ? '—'
                    : record.displayEmployeeId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _T.muted.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateCell() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('dd MMM yyyy').format(record.date),
          style: const TextStyle(
            color: _T.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          DateFormat('EEEE').format(record.date),
          style: TextStyle(
            color: _T.muted.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// Times only mean something when the person actually clocked in. On a
  /// leave or absent day this shows an explicit em dash rather than an empty
  /// cell, so "no value" is never mistaken for "failed to load".
  Widget _timeCell({required bool isCheckIn}) {
    if (!outcome.attended) return const _Dash();
    final text =
        isCheckIn ? record.checkInFormatted : record.checkOutFormatted;
    final color = isCheckIn
        ? _arrivalColor()
        : (record.isCheckedOut ? _T.text : _T.warning);
    return Text(
      isCheckIn || record.isCheckedOut ? text : 'Open',
      style: TextStyle(
        color: color,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Color _arrivalColor() {
    switch (record.arrivalBand) {
      case 'green':
        return _T.success;
      case 'orange':
        return _T.warning;
      case 'red':
        return _T.danger;
      case 'blue':
        return _T.info;
      default:
        return _T.text;
    }
  }

  Widget _workedCell() {
    if (!outcome.attended) return const _Dash();
    final duration = record.workingDuration;
    return Text(
      duration == null ? '—' : record.workingHoursFormatted,
      style: TextStyle(
        color: duration == null ? _T.muted : _T.text,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _shortfallCell() {
    if (!outcome.attended) return const _Dash();
    final minutes = record.displayPendingMinutes;
    // Zero shortfall is the good case and should read as calm, not as
    // another number competing for attention.
    if (minutes <= 0) {
      return const Row(
        children: [
          Icon(Icons.check_rounded, size: 13, color: _T.success),
          SizedBox(width: 4),
          Text('None',
              style: TextStyle(
                color: _T.success,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              )),
        ],
      );
    }
    return Text(
      _humanMinutes(minutes),
      style: const TextStyle(
        color: _T.danger,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _permissionCell() {
    if (!outcome.attended) return const _Dash();
    final minutes = record.permissionMinutes;
    if (minutes <= 0) {
      return Text(
        'None',
        style: TextStyle(
          color: _T.muted.withValues(alpha: 0.7),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Text(
      _humanMinutes(minutes),
      style: const TextStyle(
        color: _T.info,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  // ── Mobile card ──────────────────────────────────────────────────────
  Widget _buildCompact() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(record: record, radius: 17),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.displayEmployeeName.isEmpty
                          ? 'Removed employee'
                          : record.displayEmployeeName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _T.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${record.displayEmployeeId} · '
                      '${DateFormat('EEE, dd MMM').format(record.date)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _T.muted.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: _T.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DayBadge(outcome: outcome),
          if (outcome.attended) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _miniStat('In', record.checkInFormatted,
                        _arrivalColor())),
                Expanded(
                  child: _miniStat(
                    'Out',
                    record.isCheckedOut ? record.checkOutFormatted : 'Open',
                    record.isCheckedOut ? _T.text : _T.warning,
                  ),
                ),
                Expanded(
                    child: _miniStat(
                        'Worked', record.workingHoursFormatted, _T.text)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _miniStat(
                    'Shortfall',
                    record.displayPendingMinutes <= 0
                        ? 'None'
                        : _humanMinutes(record.displayPendingMinutes),
                    record.displayPendingMinutes <= 0 ? _T.success : _T.danger,
                  ),
                ),
                Expanded(
                  child: _miniStat(
                    'Permission',
                    record.permissionMinutes <= 0
                        ? 'None'
                        : _humanMinutes(record.permissionMinutes),
                    record.permissionMinutes <= 0 ? _T.muted : _T.info,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: _T.muted.withValues(alpha: 0.7),
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) {
    return Text(
      '—',
      style: TextStyle(
        color: _T.muted.withValues(alpha: 0.45),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// The one status badge for the day, with its reason underneath.
class _DayBadge extends StatelessWidget {
  final _DayOutcome outcome;

  const _DayBadge({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final detail = outcome.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: outcome.color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: outcome.color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(outcome.icon, color: outcome.color, size: 12),
              const SizedBox(width: 6),
              Text(
                outcome.label,
                style: TextStyle(
                  color: outcome.color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _T.muted.withValues(alpha: 0.85),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Everything that does not earn a column: shown on demand instead of being
/// crammed into the row.
class _DetailPanel extends StatelessWidget {
  final _DayOutcome outcome;

  const _DetailPanel({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final r = outcome.record;
    final leave = outcome.leave;

    final entries = <({String label, String value})>[
      (label: 'Designation', value: _orDash(r.displayDepartment)),
      (label: 'Reporting manager', value: _orDash(r.managerName)),
      (
        label: 'Office window',
        value: (r.officeStartTime == null && r.officeEndTime == null)
            ? '—'
            : '${r.officeStartTime ?? '—'} – ${r.officeEndTime ?? '—'}'
      ),
      if (leave != null) ...[
        (label: 'Leave type', value: leave.type),
        (
          label: 'Leave dates',
          value: '${DateFormat('dd MMM').format(leave.start)} – '
              '${DateFormat('dd MMM yyyy').format(leave.end)}'
        ),
        (label: 'Leave reason', value: _orDash(leave.reason)),
        (label: 'Paid', value: leave.isPaid ? 'Yes' : 'No'),
      ],
      if (outcome.attended) ...[
        (label: 'Late by', value: _humanMinutes(r.lateMinutes)),
        (
          label: 'Permission detail',
          value: _orDash(r.permissionActivityDetail)
        ),
        (label: 'Policy note', value: _orDash(r.policyLabel)),
        (label: 'Location', value: _orDash(r.geoTagFormatted)),
      ],
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 20),
      decoration: BoxDecoration(
        color: _T.header.withValues(alpha: 0.5),
        border: const Border(top: BorderSide(color: _T.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DAY DETAIL',
            style: TextStyle(
              color: _T.muted.withValues(alpha: 0.8),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final perRow = c.maxWidth < 560 ? 1 : (c.maxWidth < 900 ? 2 : 3);
              const gap = 16.0;
              final width = (c.maxWidth - gap * (perRow - 1)) / perRow;
              return Wrap(
                spacing: gap,
                runSpacing: 14,
                children: [
                  for (final e in entries)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.label,
                            style: TextStyle(
                              color: _T.muted.withValues(alpha: 0.75),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            e.value,
                            style: const TextStyle(
                              color: _T.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _orDash(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? '—' : v;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared bits
// ═══════════════════════════════════════════════════════════════════════

class _DayKindStyle {
  final String label;
  final Color color;
  final IconData icon;

  const _DayKindStyle(this.label, this.color, this.icon);

  static _DayKindStyle of(_DayKind kind) {
    switch (kind) {
      case _DayKind.present:
        return const _DayKindStyle(
            'Present', _T.success, Icons.check_circle_rounded);
      case _DayKind.late:
        return const _DayKindStyle('Late', _T.warning, Icons.schedule_rounded);
      case _DayKind.halfDay:
        return const _DayKindStyle(
            'Half Day', _T.cyan, Icons.timelapse_rounded);
      case _DayKind.onLeave:
        return const _DayKindStyle(
            'On Leave', _T.blue, Icons.beach_access_rounded);
      case _DayKind.absent:
        return const _DayKindStyle('Absent', _T.danger, Icons.cancel_rounded);
      case _DayKind.noRecord:
        return const _DayKindStyle(
            'No Record', _T.muted, Icons.help_outline_rounded);
    }
  }
}

class _Th extends StatelessWidget {
  final String label;
  final int flex;
  final String? tip;

  const _Th(this.label, {required this.flex, this.tip});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _T.muted.withValues(alpha: 0.78),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
    return Expanded(
      flex: flex,
      child: tip == null
          ? text
          : Tooltip(
              message: tip!,
              waitDuration: const Duration(milliseconds: 300),
              child: Row(
                children: [
                  Flexible(child: text),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline_rounded,
                    size: 11,
                    color: _T.muted.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AttendanceModel record;
  final double radius;

  const _Avatar({required this.record, required this.radius});

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
          ? _T.header
          : _avatarColor(record.employeeName),
      backgroundImage: profileImage,
      child: record.identityCleared || photoBytes != null || hasNetworkPhoto
          ? null
          : Text(
              _initials(record.employeeName),
              style: TextStyle(
                color: _T.white,
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
    const colors = [_T.indigo, _T.success, _T.warning, _T.danger, _T.info];
    return colors[name.length % colors.length];
  }
}

class _T {
  static const Color surface = AppThemeColors.darkSurface;
  static const Color border = AppThemeColors.darkBorder;
  static const Color header = AppThemeColors.darkCanvas;
  static const Color text = AppThemeColors.darkText;
  static const Color muted = AppThemeColors.darkMuted;
  static const Color primary = Color(0xFF0F766E);
  static const Color success = Color(0xFF16B86A);
  static const Color warning = Color(0xFFFFA400);
  static const Color danger = Color(0xFFFF3D4F);
  static const Color info = Color(0xFF38BDF8);
  static const Color blue = Color(0xFF5B8DEF);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color indigo = Color(0xFF5B6EF5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color shadow = Color(0x1A6B7897);
}
