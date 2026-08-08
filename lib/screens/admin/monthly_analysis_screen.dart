import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../models/attendance_model.dart';
import '../../models/staff.dart';
import '../../services/attendance_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';
import 'monthly_employee_analysis_screen.dart';

// Fixed-brand palette for the monthly analysis screen (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _maPrimary = Color(0xFF0F766E);
const Color _maAmber = Color(0xFFFFB800);
const Color _maRed = Color(0xFFFF5757);
const Color _maGreen = Color(0xFF00C896);
const Color _maCyan = Color(0xFF22D3EE);
const Color _maShadow = Color(0x1A6B7897);
const Color _maWhite = Color(0xFFFFFFFF);

class _EmployeeSummary {
  final Staff staff;
  int presentCount = 0;
  int absentCount = 0;
  int pendingMinutes = 0;
  int permissionMinutes = 0;
  double paidLeaveCount = 0;
  double unpaidLeaveCount = 0;

  int get totalPendingMinutes => pendingMinutes + permissionMinutes;
  double get totalLeaveCount => paidLeaveCount + unpaidLeaveCount;

  _EmployeeSummary(this.staff);
}

class MonthlyAnalysisScreen extends StatefulWidget {
  const MonthlyAnalysisScreen({super.key});

  @override
  State<MonthlyAnalysisScreen> createState() => _MonthlyAnalysisScreenState();
}

class _MonthlyAnalysisScreenState extends State<MonthlyAnalysisScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Default to current month and year
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  _EmployeeSummary? _selectedSummary;

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

  void _calculateLeavesInMonth(
      _EmployeeSummary summary, QuerySnapshot leaveSnap) {
    String empId = summary.staff.employeeId;
    for (var doc in leaveSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['userId'] == empId || data['employeeId'] == empId) {
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
          if (current.month == _selectedMonth &&
              current.year == _selectedYear) {
            final dayValue = isHalfDay ? 0.5 : 1.0;
            if (paidPerRequest != null || unpaidPerRequest != null) {
              final paidRatio =
                  requestDays == 0 ? 0.0 : (paidPerRequest ?? 0) / requestDays;
              final unpaidRatio = requestDays == 0
                  ? 0.0
                  : (unpaidPerRequest ?? 0) / requestDays;
              summary.paidLeaveCount += dayValue * paidRatio;
              summary.unpaidLeaveCount += dayValue * unpaidRatio;
            } else if (isPaid) {
              summary.paidLeaveCount += dayValue;
            } else {
              summary.unpaidLeaveCount += dayValue;
            }
          }
          current = current.add(const Duration(days: 1));
        }
      }
    }
  }

  String _formatHoursMinutesSeconds(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '$hours hrs ${mins.toString().padLeft(2, '0')} min';
  }

  static String _formatLeaveDays(double days) {
    if (days == days.roundToDouble()) return days.toInt().toString();
    return days.toStringAsFixed(1);
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
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
                            final allStaff = staffSnapshot.data ?? [];
                            final managers = (managerSnapshot.data?.docs ?? [])
                                .map(_managerDocToStaff)
                                .where((manager) =>
                                    manager.employeeId.isNotEmpty ||
                                    manager.name.isNotEmpty)
                                .toList();
                            final peopleByKey = <String, Staff>{};
                            for (final staff in allStaff) {
                              final key = staff.employeeId.trim().isNotEmpty
                                  ? staff.employeeId.trim()
                                  : staff.id;
                              peopleByKey[key] = staff;
                            }
                            for (final manager in managers) {
                              final key = manager.employeeId.trim().isNotEmpty
                                  ? manager.employeeId.trim()
                                  : manager.id;
                              peopleByKey[key] = manager;
                            }
                            final allPeople = peopleByKey.values.toList();
                            final allRecords =
                                attendanceSnapshot.data ?? <AttendanceModel>[];
                            final allLeaves = leaveSnapshot.data;

                            // Group by employee
                            final Map<String, _EmployeeSummary> summaries = {};
                            for (var staff in allPeople) {
                              if (staff.employeeId.trim().isEmpty) continue;
                              final summary = _EmployeeSummary(staff);
                              summaries[staff.employeeId] = summary;
                              if (allLeaves != null) {
                                _calculateLeavesInMonth(summary, allLeaves);
                              }
                            }

                            // Filter records by month/year and aggregate
                            for (var record in allRecords) {
                              if (record.date.month != _selectedMonth ||
                                  record.date.year != _selectedYear) {
                                continue;
                              }

                              final summary = summaries[record.employeeId];
                              if (summary == null) continue;

                              if (record.countsAsAbsent) {
                                summary.absentCount++;
                              } else if (record.countsAsAttended) {
                                summary.presentCount++;
                              }

                              summary.pendingMinutes +=
                                  record.displayPendingMinutes;
                              summary.permissionMinutes +=
                                  record.permissionMinutes;
                            }

                            // Apply Search Filter and remove those with 0 records if desired (but usually we show all staff)
                            var filteredSummaries = summaries.values.where((s) {
                              if (_searchQuery.isNotEmpty) {
                                final query = _searchQuery.toLowerCase();
                                final nameMatch =
                                    s.staff.name.toLowerCase().contains(query);
                                final idMatch = s.staff.employeeId
                                    .toLowerCase()
                                    .contains(query);
                                final deptMatch = s.staff.department
                                    .toLowerCase()
                                    .contains(query);
                                return nameMatch || idMatch || deptMatch;
                              }
                              return true;
                            }).toList();

                            // Sort by name
                            filteredSummaries.sort(
                                (a, b) => a.staff.name.compareTo(b.staff.name));

                            if (_selectedSummary != null) {
                              return MonthlyEmployeeAnalysisScreen(
                                staff: _selectedSummary!.staff,
                                month: _selectedMonth,
                                year: _selectedYear,
                                totalApprovedLeaves:
                                    _selectedSummary!.totalLeaveCount.round(),
                                onBack: () =>
                                    setState(() => _selectedSummary = null),
                              );
                            }

                            return SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title Header
                                  // Title Header
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isMobile =
                                          MediaQuery.of(context).size.width <
                                              650;
                                      const titleWidget = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Monthly Analysis',
                                            style: TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w900,
                                              color: AppThemeColors.darkText,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Overall and monthly results of attendance records',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppThemeColors.darkMuted,
                                            ),
                                          ),
                                        ],
                                      );

                                      if (isMobile) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildDateSelectors(),
                                          ],
                                        );
                                      }

                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          titleWidget,
                                          _buildDateSelectors(),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Table Container
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppThemeColors.darkSurface,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                          color: AppThemeColors.darkBorder),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: _maShadow,
                                          blurRadius: 24,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Search & Filter Header
                                        _buildTableHeaderSection(),

                                        // Table Headers
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final isMobile =
                                                constraints.maxWidth < 800;
                                            if (isMobile) {
                                              return const SizedBox.shrink();
                                            }
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 26,
                                                      vertical: 18),
                                              decoration: const BoxDecoration(
                                                color:
                                                    AppThemeColors.darkCanvas,
                                                border: Border(
                                                  bottom: BorderSide(
                                                      color: AppThemeColors
                                                          .darkBorder),
                                                ),
                                              ),
                                              child: const Row(
                                                children: [
                                                  Expanded(
                                                      flex: 18,
                                                      child: _TableHeaderText(
                                                          'EMPLOYEE')),
                                                  Expanded(
                                                      flex: 14,
                                                      child: _TableHeaderText(
                                                          'DESIGNATION')),
                                                  Expanded(
                                                      flex: 14,
                                                      child: _TableHeaderText(
                                                          'POSITION')),
                                                  Expanded(
                                                      flex: 8,
                                                      child: _TableHeaderText(
                                                          'PRESENT')),
                                                  Expanded(
                                                      flex: 8,
                                                      child: _TableHeaderText(
                                                          'ABSENT')),
                                                  Expanded(
                                                      flex: 16,
                                                      child: _TableHeaderText(
                                                          'PENDING')),
                                                  Expanded(
                                                      flex: 16,
                                                      child: _TableHeaderText(
                                                          'PERMISSION')),
                                                  Expanded(
                                                      flex: 16,
                                                      child: _TableHeaderText(
                                                          'TOTAL PENDING')),
                                                  Expanded(
                                                      flex: 12,
                                                      child: _TableHeaderText(
                                                          'LEAVE')),
                                                ],
                                              ),
                                            );
                                          },
                                        ),

                                        // Table Rows
                                        if (attendanceSnapshot
                                                    .connectionState ==
                                                ConnectionState.waiting ||
                                            staffSnapshot.connectionState ==
                                                ConnectionState.waiting)
                                          const SizedBox(
                                            height: 180,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                color: _maPrimary,
                                              ),
                                            ),
                                          )
                                        else if (filteredSummaries.isEmpty)
                                          const SizedBox(
                                            height: 152,
                                            child: Center(
                                              child: Text(
                                                'No attendance records matches the filters.',
                                                style: TextStyle(
                                                  color:
                                                      AppThemeColors.darkMuted,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          ListView.separated(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: filteredSummaries.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(
                                              height: 1,
                                              color: AppThemeColors.darkBorder,
                                            ),
                                            itemBuilder: (context, index) {
                                              return _MonthlyAnalysisRow(
                                                summary:
                                                    filteredSummaries[index],
                                                selectedMonth: _selectedMonth,
                                                selectedYear: _selectedYear,
                                                formatTime:
                                                    _formatHoursMinutesSeconds,
                                                onTap: () => setState(() =>
                                                    _selectedSummary =
                                                        filteredSummaries[
                                                            index]),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          });
                    },
                  );
                },
              );
            }),
      ),
    );
  }

  Widget _buildDateSelectors() {
    return Row(
      children: [
        // Month Dropdown
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppThemeColors.darkBorder),
          ),
          child: DropdownButtonHideUnderline(
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
              items: List.generate(12, (index) {
                return DropdownMenuItem<int>(
                  value: index + 1,
                  child: Text(_months[index]),
                );
              }),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedMonth = val);
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Year Dropdown
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppThemeColors.darkBorder),
          ),
          child: DropdownButtonHideUnderline(
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
              items: _years.map((year) {
                return DropdownMenuItem<int>(
                  value: year,
                  child: Text(year.toString()),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedYear = val);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeaderSection() {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          const titleWidget = Text(
            'Monthly Summary Report',
            style: TextStyle(
              color: AppThemeColors.darkText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          );
          final searchWidget = SizedBox(
            width: isMobile ? double.infinity : 240,
            height: 38,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: _maWhite, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppThemeColors.darkCanvas,
                hintText: 'Search employee...',
                hintStyle: TextStyle(
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.6),
                ),
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
                  borderSide: const BorderSide(color: _maPrimary),
                ),
              ),
            ),
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget,
                const SizedBox(height: 12),
                searchWidget,
              ],
            );
          }

          return Row(
            children: [
              titleWidget,
              const Spacer(),
              searchWidget,
            ],
          );
        },
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

class _MonthlyAnalysisRow extends StatelessWidget {
  final _EmployeeSummary summary;
  final int selectedMonth;
  final int selectedYear;
  final String Function(int) formatTime;
  final VoidCallback onTap;

  const _MonthlyAnalysisRow({
    required this.summary,
    required this.selectedMonth,
    required this.selectedYear,
    required this.formatTime,
    required this.onTap,
  });

  Widget _buildMobileDetailItem(IconData icon, String label, String value,
      {Color? textColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppThemeColors.darkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                    color: textColor ?? AppThemeColors.darkText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApprovedLeaveDetailItem(_EmployeeSummary summary) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.calendar_today_outlined,
            size: 16, color: AppThemeColors.darkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Approved Leave',
                style: TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              if (summary.totalLeaveCount == 0)
                const Text(
                  '0',
                  style: TextStyle(
                      color: AppThemeColors.darkMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary.paidLeaveCount > 0)
                      Text(
                        'Paid: ${_MonthlyAnalysisScreenState._formatLeaveDays(summary.paidLeaveCount)}',
                        style: const TextStyle(
                            color: _maCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    if (summary.unpaidLeaveCount > 0)
                      Text(
                        'Unpaid: ${_MonthlyAnalysisScreenState._formatLeaveDays(summary.unpaidLeaveCount)}',
                        style: const TextStyle(
                            color: _maAmber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final isMobile = mediaWidth < 800;

    if (isMobile) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _maPrimary.withValues(alpha: 0.2),
                    child: Text(
                      summary.staff.name.isNotEmpty
                          ? summary.staff.name[0].toUpperCase()
                          : 'E',
                      style: const TextStyle(
                        color: _maPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.staff.name,
                          style: const TextStyle(
                            color: AppThemeColors.darkText,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          summary.staff.employeeId,
                          style: TextStyle(
                            color:
                                AppThemeColors.darkMuted.withValues(alpha: 0.7),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppThemeColors.darkCanvas,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppThemeColors.darkBorder),
                    ),
                    child: Text(
                      summary.staff.position.isNotEmpty
                          ? summary.staff.position
                          : '-',
                      style: const TextStyle(
                        color: AppThemeColors.darkMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppThemeColors.darkBorder, height: 1),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.business_outlined,
                          'Designation',
                          summary.staff.department,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.check_circle_outline,
                          'Present Days',
                          '${summary.presentCount}',
                          textColor: _maGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.cancel_outlined,
                          'Absent Days',
                          '${summary.absentCount}',
                          textColor: _maRed,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.hourglass_empty_outlined,
                          'Pending Hours',
                          formatTime(summary.pendingMinutes),
                          textColor:
                              summary.pendingMinutes > 0 ? _maAmber : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.vpn_key_outlined,
                          'Permission Hours',
                          formatTime(summary.permissionMinutes),
                          textColor:
                              summary.permissionMinutes > 0 ? _maPrimary : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _buildApprovedLeaveDetailItem(summary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildMobileDetailItem(
                    Icons.calculate_outlined,
                    'Total Pending Hours',
                    formatTime(summary.totalPendingMinutes),
                    textColor: summary.totalPendingMinutes > 0 ? _maRed : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        child: Row(
          children: [
            // Employee info
            Expanded(
              flex: 18,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _maPrimary.withValues(alpha: 0.2),
                    child: Text(
                      summary.staff.name.isNotEmpty
                          ? summary.staff.name[0].toUpperCase()
                          : 'E',
                      style: const TextStyle(
                        color: _maPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.staff.name,
                          style: const TextStyle(
                            color: AppThemeColors.darkText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          summary.staff.employeeId,
                          style: TextStyle(
                            color:
                                AppThemeColors.darkMuted.withValues(alpha: 0.7),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Designation
            Expanded(
              flex: 14,
              child: Text(
                summary.staff.department,
                style: const TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 13,
                ),
              ),
            ),

            // Position
            Expanded(
              flex: 14,
              child: Text(
                summary.staff.position.isNotEmpty
                    ? summary.staff.position
                    : '-',
                style: const TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Present
            Expanded(
              flex: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _maGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${summary.presentCount}',
                    style: const TextStyle(
                      color: _maGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),

            // Absent
            Expanded(
              flex: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _maRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${summary.absentCount}',
                    style: const TextStyle(
                      color: _maRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),

            // Pending Hours
            Expanded(
              flex: 16,
              child: Text(
                formatTime(summary.pendingMinutes),
                style: TextStyle(
                  color: summary.pendingMinutes > 0
                      ? _maAmber
                      : AppThemeColors.darkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            // Permission Hours
            Expanded(
              flex: 16,
              child: Text(
                formatTime(summary.permissionMinutes),
                style: TextStyle(
                  color: summary.permissionMinutes > 0
                      ? _maPrimary
                      : AppThemeColors.darkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            // Total Pending Hours
            Expanded(
              flex: 16,
              child: Text(
                formatTime(summary.totalPendingMinutes),
                style: TextStyle(
                  color: summary.totalPendingMinutes > 0
                      ? _maRed
                      : AppThemeColors.darkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            // Approved Leave
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: summary.totalLeaveCount == 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              AppThemeColors.darkMuted.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '0',
                          style: TextStyle(
                            color: AppThemeColors.darkMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (summary.paidLeaveCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: _maPrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Paid: ${_MonthlyAnalysisScreenState._formatLeaveDays(summary.paidLeaveCount)}',
                                style: const TextStyle(
                                    color: _maCyan,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (summary.unpaidLeaveCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _maAmber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Unpaid: ${_MonthlyAnalysisScreenState._formatLeaveDays(summary.unpaidLeaveCount)}',
                                style: const TextStyle(
                                    color: _maAmber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
