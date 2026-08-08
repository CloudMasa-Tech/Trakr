import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/attendance_model.dart';
import '../../models/staff.dart';
import '../../services/attendance_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';

// Fixed-brand palette for the payroll screen (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _payPrimary = Color(0xFF0F766E);
const Color _payRed = Color(0xFFFF5757);
const Color _payTeal = Color(0xFF5EEAD4);
const Color _payGreen = Color(0xFF10B981);
const Color _payAmber = Color(0xFFFFB800);
const Color _payPrimarySoft = Color(0x140F766E);
const Color _payCyan = Color(0xFF22D3EE);
const Color _payShadow = Color(0x1A6B7897);

class _PayrollEntry {
  final Staff staff;
  int presentCount = 0;
  int absentCount = 0;
  int pendingMinutes = 0;
  int permissionMinutes = 0;
  double paidLeaveCount = 0;
  double unpaidLeaveCount = 0;

  _PayrollEntry(this.staff);

  double get salary => staff.salary ?? 0;
  int get totalPendingMinutes => pendingMinutes + permissionMinutes;
  double get totalLeaveCount => paidLeaveCount + unpaidLeaveCount;

  double dailyRate(int daysInMonth) =>
      daysInMonth <= 0 ? 0 : salary / daysInMonth;
  double hourlyRate(int daysInMonth) => dailyRate(daysInMonth) / 8;

  double absentDeduction(int daysInMonth) =>
      absentCount * dailyRate(daysInMonth);
  double leaveDeduction(int daysInMonth) =>
      unpaidLeaveCount * dailyRate(daysInMonth);
  double pendingDeduction(int daysInMonth) =>
      (totalPendingMinutes / 60) * hourlyRate(daysInMonth);

  double totalDeductions(int daysInMonth) =>
      absentDeduction(daysInMonth) +
      leaveDeduction(daysInMonth) +
      pendingDeduction(daysInMonth);

  double netPay(int daysInMonth) {
    final net = salary - totalDeductions(daysInMonth);
    return net < 0 ? 0 : net;
  }
}

class _PayrollTotals {
  final int peopleCount;
  final int configuredSalaryCount;
  final double grossSalary;
  final double deductions;
  final double netPay;
  final double unpaidLeaveDays;

  const _PayrollTotals({
    required this.peopleCount,
    required this.configuredSalaryCount,
    required this.grossSalary,
    required this.deductions,
    required this.netPay,
    required this.unpaidLeaveDays,
  });
}

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final _searchController = TextEditingController();

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String _searchQuery = '';
  _PayrollEntry? _selectedEntry;

  final List<String> _months = const [
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
    'December',
  ];

  List<int> get _years {
    final currentYear = DateTime.now().year;
    return List.generate(11, (index) => currentYear - 5 + index);
  }

  int get _daysInSelectedMonth =>
      DateTime(_selectedYear, _selectedMonth + 1, 0).day;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Staff _managerDocToStaff(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Staff(
      id: doc.id,
      name: (data['name'] as String? ?? '').trim(),
      email: (data['email'] as String? ?? '').trim(),
      phone: (data['phone'] as String? ?? '').trim(),
      department: (data['department'] as String? ?? '').trim(),
      position: (data['position'] as String? ?? 'Manager').trim(),
      employeeId: (data['employeeId'] as String? ?? '').trim(),
      joinDate: (data['joinDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      photoUrl: data['photoUrl'] as String?,
      reportsTo: data['reportsTo'] as String?,
      salary:
          data['salary'] != null ? (data['salary'] as num).toDouble() : null,
      role: 'manager',
      isActive: (data['status'] as String? ?? 'active') != 'inactive',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      bloodGroup: data['bloodGroup'] as String?,
      gender: data['gender'] as String?,
      nationality: data['nationality'] as String?,
      dob: (data['dob'] as Timestamp?)?.toDate(),
      address: data['address'] as String?,
    );
  }

  void _calculateLeavesInMonth(_PayrollEntry entry, QuerySnapshot leaveSnap) {
    final empId = entry.staff.employeeId;
    for (final doc in leaveSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['userId'] != empId && data['employeeId'] != empId) continue;

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
        if (current.month == _selectedMonth && current.year == _selectedYear) {
          final dayValue = isHalfDay ? 0.5 : 1.0;
          if (paidPerRequest != null || unpaidPerRequest != null) {
            final paidRatio =
                requestDays == 0 ? 0.0 : (paidPerRequest ?? 0) / requestDays;
            final unpaidRatio =
                requestDays == 0 ? 0.0 : (unpaidPerRequest ?? 0) / requestDays;
            entry.paidLeaveCount += dayValue * paidRatio;
            entry.unpaidLeaveCount += dayValue * unpaidRatio;
          } else if (isPaid) {
            entry.paidLeaveCount += dayValue;
          } else {
            entry.unpaidLeaveCount += dayValue;
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }
  }

  _PayrollTotals _totalsFor(List<_PayrollEntry> entries) {
    final daysInMonth = _daysInSelectedMonth;
    var gross = 0.0;
    var deductions = 0.0;
    var net = 0.0;
    var unpaidLeaves = 0.0;
    var configured = 0;

    for (final entry in entries) {
      gross += entry.salary;
      deductions += entry.totalDeductions(daysInMonth);
      net += entry.netPay(daysInMonth);
      unpaidLeaves += entry.unpaidLeaveCount;
      if (entry.staff.salary != null && entry.staff.salary! > 0) configured++;
    }

    return _PayrollTotals(
      peopleCount: entries.length,
      configuredSalaryCount: configured,
      grossSalary: gross,
      deductions: deductions,
      netPay: net,
      unpaidLeaveDays: unpaidLeaves,
    );
  }

  String _formatMoney(num amount) {
    return 'INR ${NumberFormat.decimalPattern().format(amount.round())}';
  }

  String _formatHours(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '$hours hrs ${mins.toString().padLeft(2, '0')} min';
  }

  String _formatDays(double days) {
    if (days == days.roundToDouble()) return days.toInt().toString();
    return days.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Staff>>(
        stream: StaffService().getAllStaff(),
        builder: (context, staffSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseContextProvider.current.firestore
                .collection('managers')
                .orderBy('name')
                .snapshots(),
            builder: (context, managerSnapshot) {
              return StreamBuilder<List<AttendanceModel>>(
                stream: _attendanceService.getAttendanceHistoryStreamAll(),
                builder: (context, attendanceSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseContextProvider.current.firestore
                        .collection('leave_requests')
                        .where('status', isEqualTo: 'approved')
                        .snapshots(),
                    builder: (context, leaveSnapshot) {
                      final loading = staffSnapshot.connectionState ==
                              ConnectionState.waiting ||
                          managerSnapshot.connectionState ==
                              ConnectionState.waiting ||
                          attendanceSnapshot.connectionState ==
                              ConnectionState.waiting;

                      final entries = _buildEntries(
                        staffSnapshot.data ?? [],
                        managerSnapshot.data?.docs ?? [],
                        attendanceSnapshot.data ?? [],
                        leaveSnapshot.data,
                      );

                      final filtered = entries.where((entry) {
                        if (_searchQuery.trim().isEmpty) return true;
                        final query = _searchQuery.toLowerCase().trim();
                        return entry.staff.name.toLowerCase().contains(query) ||
                            entry.staff.employeeId
                                .toLowerCase()
                                .contains(query) ||
                            entry.staff.department
                                .toLowerCase()
                                .contains(query) ||
                            entry.staff.position.toLowerCase().contains(query);
                      }).toList()
                        ..sort((a, b) => a.staff.name.compareTo(b.staff.name));

                      if (_selectedEntry != null) {
                        final match = entries.where((entry) =>
                            entry.staff.employeeId ==
                            _selectedEntry!.staff.employeeId);
                        _selectedEntry = match.isEmpty ? null : match.first;
                      }

                      final totals = _totalsFor(entries);

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final showPanel = _selectedEntry != null &&
                              constraints.maxWidth >= 1100;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(24, 22, 24, 24),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildHeader(),
                                      const SizedBox(height: 18),
                                      _buildSummaryCards(totals),
                                      const SizedBox(height: 18),
                                      _buildPayrollTable(
                                        filtered,
                                        loading,
                                        compact: constraints.maxWidth < 850,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (showPanel)
                                _PayrollDetailPanel(
                                  entry: _selectedEntry!,
                                  daysInMonth: _daysInSelectedMonth,
                                  formatMoney: _formatMoney,
                                  formatHours: _formatHours,
                                  formatDays: _formatDays,
                                  onClose: () =>
                                      setState(() => _selectedEntry = null),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  List<_PayrollEntry> _buildEntries(
    List<Staff> staff,
    List<QueryDocumentSnapshot> managerDocs,
    List<AttendanceModel> attendance,
    QuerySnapshot? leaves,
  ) {
    final managers = managerDocs
        .map(_managerDocToStaff)
        .where((manager) =>
            manager.employeeId.isNotEmpty || manager.name.isNotEmpty)
        .toList();
    final peopleByKey = <String, Staff>{};

    for (final person in [...staff, ...managers]) {
      final key = person.employeeId.trim().isNotEmpty
          ? person.employeeId.trim()
          : person.id;
      if (key.isNotEmpty) peopleByKey[key] = person;
    }

    final entries = <String, _PayrollEntry>{};
    for (final person in peopleByKey.values) {
      if (person.employeeId.trim().isEmpty) continue;
      final entry = _PayrollEntry(person);
      entries[person.employeeId] = entry;
      if (leaves != null) _calculateLeavesInMonth(entry, leaves);
    }

    for (final record in attendance) {
      if (record.date.month != _selectedMonth ||
          record.date.year != _selectedYear) {
        continue;
      }
      final entry = entries[record.employeeId];
      if (entry == null) continue;
      if (record.countsAsAbsent) {
        entry.absentCount++;
      } else if (record.countsAsAttended) {
        entry.presentCount++;
      }
      entry.pendingMinutes += record.displayPendingMinutes;
      entry.permissionMinutes += record.permissionMinutes;
    }

    return entries.values.toList();
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 700;
        const title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payroll Integration',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppThemeColors.darkText,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Monthly payroll from salary, attendance, pending hours, and approved leaves.',
              style: TextStyle(fontSize: 14, color: AppThemeColors.darkMuted),
            ),
          ],
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              _buildDateSelectors(),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            title,
            _buildDateSelectors(),
          ],
        );
      },
    );
  }

  Widget _buildDateSelectors() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _selectorShell(
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedMonth,
              dropdownColor: AppThemeColors.darkSurface,
              icon: const Icon(Icons.arrow_drop_down,
                  color: AppThemeColors.darkMuted),
              style: const TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: List.generate(
                12,
                (index) => DropdownMenuItem<int>(
                  value: index + 1,
                  child: Text(_months[index]),
                ),
              ),
              onChanged: (value) {
                if (value != null) setState(() => _selectedMonth = value);
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        _selectorShell(
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedYear,
              dropdownColor: AppThemeColors.darkSurface,
              icon: const Icon(Icons.arrow_drop_down,
                  color: AppThemeColors.darkMuted),
              style: const TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: _years
                  .map((year) => DropdownMenuItem<int>(
                        value: year,
                        child: Text(year.toString()),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedYear = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectorShell(Widget child) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: child,
    );
  }

  Widget _buildSummaryCards(_PayrollTotals totals) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 760;
        final width =
            isNarrow ? double.infinity : (constraints.maxWidth - 48) / 4;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _PayrollStatCard(
              width: width,
              title: 'People',
              value: '${totals.peopleCount}',
              subtitle: '${totals.configuredSalaryCount} salary configured',
              icon: Icons.groups_2_outlined,
              color: _payCyan,
            ),
            _PayrollStatCard(
              width: width,
              title: 'Gross Salary',
              value: _formatMoney(totals.grossSalary),
              subtitle: DateFormat('MMMM yyyy')
                  .format(DateTime(_selectedYear, _selectedMonth)),
              icon: Icons.payments_outlined,
              color: _payGreen,
            ),
            _PayrollStatCard(
              width: width,
              title: 'Deductions',
              value: _formatMoney(totals.deductions),
              subtitle: '${_formatDays(totals.unpaidLeaveDays)} unpaid leaves',
              icon: Icons.trending_down_rounded,
              color: _payRed,
            ),
            _PayrollStatCard(
              width: width,
              title: 'Net Payroll',
              value: _formatMoney(totals.netPay),
              subtitle: 'Payable after deductions',
              icon: Icons.account_balance_wallet_outlined,
              color: _payPrimary,
            ),
          ],
        );
      },
    );
  }

  Widget _buildPayrollTable(
    List<_PayrollEntry> entries,
    bool loading, {
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _payShadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTableToolbar(),
          if (!compact) _buildTableHeader(),
          if (loading)
            const SizedBox(
              height: 180,
              child: Center(
                child: CircularProgressIndicator(color: _payPrimary),
              ),
            )
          else if (entries.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'No payroll records match the filters.',
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
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppThemeColors.darkBorder),
              itemBuilder: (context, index) => _PayrollRow(
                entry: entries[index],
                daysInMonth: _daysInSelectedMonth,
                compact: compact,
                selected: _selectedEntry?.staff.employeeId ==
                    entries[index].staff.employeeId,
                formatMoney: _formatMoney,
                formatHours: _formatHours,
                formatDays: _formatDays,
                onTap: () => setState(() => _selectedEntry = entries[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableToolbar() {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 620;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payroll Register',
                style: TextStyle(
                  color: AppThemeColors.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$_daysInSelectedMonth calendar days in selected month',
                style: const TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          final search = SizedBox(
            width: stack ? double.infinity : 280,
            height: 38,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style:
                  const TextStyle(color: AppThemeColors.darkText, fontSize: 13),
              cursorColor: _payPrimary,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppThemeColors.darkCanvas,
                hintText: 'Search payroll...',
                hintStyle: TextStyle(
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.7),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppThemeColors.darkBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppThemeColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _payPrimary),
                ),
              ),
            ),
          );

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 12), search],
            );
          }

          return Row(children: [title, const Spacer(), search]);
        },
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      decoration: const BoxDecoration(
        color: AppThemeColors.darkCanvas,
        border: Border(bottom: BorderSide(color: AppThemeColors.darkBorder)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 20, child: _TableHeaderText('EMPLOYEE')),
          Expanded(flex: 13, child: _TableHeaderText('SALARY')),
          Expanded(flex: 10, child: _TableHeaderText('PRESENT')),
          Expanded(flex: 10, child: _TableHeaderText('ABSENT')),
          Expanded(flex: 12, child: _TableHeaderText('UNPAID LEAVE')),
          Expanded(flex: 14, child: _TableHeaderText('PENDING')),
          Expanded(flex: 14, child: _TableHeaderText('DEDUCTIONS')),
          Expanded(flex: 14, child: _TableHeaderText('NET PAY')),
          Expanded(flex: 10, child: _TableHeaderText('STATUS')),
        ],
      ),
    );
  }
}

class _PayrollRow extends StatelessWidget {
  final _PayrollEntry entry;
  final int daysInMonth;
  final bool compact;
  final bool selected;
  final String Function(num) formatMoney;
  final String Function(int) formatHours;
  final String Function(double) formatDays;
  final VoidCallback onTap;

  const _PayrollRow({
    required this.entry,
    required this.daysInMonth,
    required this.compact,
    required this.selected,
    required this.formatMoney,
    required this.formatHours,
    required this.formatDays,
    required this.onTap,
  });

  bool get _salaryMissing =>
      entry.staff.salary == null || entry.staff.salary! <= 0;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        onTap: onTap,
        child: Container(
          color: selected ? _payPrimarySoft : null,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PayrollAvatar(name: entry.staff.name),
                  const SizedBox(width: 12),
                  Expanded(child: _EmployeeText(staff: entry.staff)),
                  _PayrollStatusPill(configured: !_salaryMissing),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MobileMetric('Salary', formatMoney(entry.salary)),
                  _MobileMetric('Present', '${entry.presentCount}'),
                  _MobileMetric('Absent', '${entry.absentCount}'),
                  _MobileMetric(
                      'Unpaid Leave', formatDays(entry.unpaidLeaveCount)),
                  _MobileMetric(
                      'Pending', formatHours(entry.totalPendingMinutes)),
                  _MobileMetric(
                      'Net Pay', formatMoney(entry.netPay(daysInMonth)),
                      strong: true),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? _payPrimarySoft : null,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 20,
              child: Row(
                children: [
                  _PayrollAvatar(name: entry.staff.name),
                  const SizedBox(width: 10),
                  Expanded(child: _EmployeeText(staff: entry.staff)),
                ],
              ),
            ),
            _PayrollCell(formatMoney(entry.salary), 13,
                muted: _salaryMissing, strong: true),
            _PayrollCell('${entry.presentCount}', 10, color: _payGreen),
            _PayrollCell('${entry.absentCount}', 10,
                color: entry.absentCount > 0 ? _payRed : null),
            _PayrollCell(formatDays(entry.unpaidLeaveCount), 12,
                color: entry.unpaidLeaveCount > 0 ? _payAmber : null),
            _PayrollCell(formatHours(entry.totalPendingMinutes), 14,
                color: entry.totalPendingMinutes > 0 ? _payAmber : null),
            _PayrollCell(formatMoney(entry.totalDeductions(daysInMonth)), 14,
                color: entry.totalDeductions(daysInMonth) > 0 ? _payRed : null),
            _PayrollCell(formatMoney(entry.netPay(daysInMonth)), 14,
                strong: true, color: _payPrimary),
            Expanded(
              flex: 10,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PayrollStatusPill(configured: !_salaryMissing),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollDetailPanel extends StatelessWidget {
  final _PayrollEntry entry;
  final int daysInMonth;
  final String Function(num) formatMoney;
  final String Function(int) formatHours;
  final String Function(double) formatDays;
  final VoidCallback onClose;

  const _PayrollDetailPanel({
    required this.entry,
    required this.daysInMonth,
    required this.formatMoney,
    required this.formatHours,
    required this.formatDays,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 390,
      decoration: const BoxDecoration(
        color: AppThemeColors.darkSurface,
        border: Border(left: BorderSide(color: AppThemeColors.darkBorder)),
      ),
      child: SafeArea(
        left: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Payroll Details',
                      style: TextStyle(
                        color: AppThemeColors.darkText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: AppThemeColors.darkMuted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _PayrollAvatar(name: entry.staff.name, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _EmployeeText(staff: entry.staff, large: true)),
                ],
              ),
              const SizedBox(height: 22),
              _DetailSection(
                title: 'Attendance',
                rows: [
                  _DetailRow('Present Days', '${entry.presentCount}'),
                  _DetailRow('Absent Days', '${entry.absentCount}'),
                  _DetailRow('Paid Leave', formatDays(entry.paidLeaveCount)),
                  _DetailRow(
                      'Unpaid Leave', formatDays(entry.unpaidLeaveCount)),
                  _DetailRow(
                      'Pending Hours', formatHours(entry.pendingMinutes)),
                  _DetailRow(
                      'Permission Hours', formatHours(entry.permissionMinutes)),
                ],
              ),
              const SizedBox(height: 20),
              _DetailSection(
                title: 'Salary',
                rows: [
                  _DetailRow('Monthly Salary', formatMoney(entry.salary)),
                  _DetailRow(
                      'Daily Rate', formatMoney(entry.dailyRate(daysInMonth))),
                  _DetailRow('Hourly Rate',
                      formatMoney(entry.hourlyRate(daysInMonth))),
                ],
              ),
              const SizedBox(height: 20),
              _DetailSection(
                title: 'Deductions',
                rows: [
                  _DetailRow('Absence Deduction',
                      '- ${formatMoney(entry.absentDeduction(daysInMonth))}'),
                  _DetailRow('Unpaid Leave Deduction',
                      '- ${formatMoney(entry.leaveDeduction(daysInMonth))}'),
                  _DetailRow('Pending Hours Deduction',
                      '- ${formatMoney(entry.pendingDeduction(daysInMonth))}'),
                  _DetailRow('Total Deductions',
                      '- ${formatMoney(entry.totalDeductions(daysInMonth))}',
                      strong: true, color: _payRed),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _payPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _payPrimary.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Net Payable',
                      style: TextStyle(
                        color: AppThemeColors.darkMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(entry.netPay(daysInMonth)),
                      style: const TextStyle(
                        color: _payTeal,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayrollStatCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _PayrollStatCard({
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppThemeColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppThemeColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppThemeColors.darkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppThemeColors.darkText,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppThemeColors.darkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

class _PayrollAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const _PayrollAvatar({required this.name, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _payPrimary.withValues(alpha: 0.2),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: TextStyle(
          color: _payTeal,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EmployeeText extends StatelessWidget {
  final Staff staff;
  final bool large;

  const _EmployeeText({required this.staff, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          staff.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppThemeColors.darkText,
            fontSize: large ? 16 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${staff.employeeId} • ${staff.position.isEmpty ? staff.department : staff.position}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppThemeColors.darkMuted.withValues(alpha: 0.78),
            fontSize: large ? 12 : 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PayrollCell extends StatelessWidget {
  final String value;
  final int flex;
  final bool strong;
  final bool muted;
  final Color? color;

  const _PayrollCell(
    this.value,
    this.flex, {
    this.strong = false,
    this.muted = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ??
              (muted ? AppThemeColors.darkMuted : AppThemeColors.darkText),
          fontSize: 12.5,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _PayrollStatusPill extends StatelessWidget {
  final bool configured;

  const _PayrollStatusPill({required this.configured});

  @override
  Widget build(BuildContext context) {
    final color = configured ? _payGreen : _payAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        configured ? 'Ready' : 'No Salary',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MobileMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _MobileMetric(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppThemeColors.darkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: strong ? _payTeal : AppThemeColors.darkText,
              fontSize: 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;

  const _DetailSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _payTeal,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final Color? color;

  const _DetailRow(
    this.label,
    this.value, {
    this.strong = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:
                    strong ? AppThemeColors.darkText : AppThemeColors.darkMuted,
                fontSize: 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppThemeColors.darkText,
              fontSize: 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
