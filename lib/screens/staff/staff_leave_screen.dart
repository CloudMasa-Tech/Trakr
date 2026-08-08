import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../models/leave_request.dart';
import '../../models/staff.dart';
import '../../providers/auth_session_provider.dart';
import '../../providers/white_label_provider.dart';
import '../../services/leave_service.dart';
import '../../services/staff_service.dart';

// Fixed-brand dark navy palette for the staff leave screen (force-dark).
// Intentional exception: file-scoped brand constants.
const Color _slNavy0 = Color(0xFF243660);
const Color _slNavy1 = Color(0xFF1A2D5A);
const Color _slNavy2 = Color(0xFF203666);
const Color _slPrimary = Color(0xFF0F766E);
const Color _slRed = Color(0xFFFF5757);
const Color _slRedDeep = Color(0xFF4D2C2C);
const Color _slError = Color(0xFFF44336);
const Color _slRed700 = Color(0xFFD32F2F);
const Color _slRed300 = Color(0xFFE57373);
const Color _slGreen = Color(0xFF58D49A);
const Color _slGreen2 = Color(0xFF00C896);
const Color _slGreenDeep = Color(0xFF15392F);
const Color _slSuccess = Color(0xFF4CAF50);
const Color _slBlue = Color(0xFF6EA8FF);
const Color _slAmber = Color(0xFFFFB800);
const Color _slWhite = Color(0xFFFFFFFF);
const Color _slWhite10 = Color(0x1AFFFFFF);
const Color _slWhite38 = Color(0x61FFFFFF);
const Color _slWhite54 = Color(0x8AFFFFFF);
const Color _slWhite60 = Color(0x99FFFFFF);
const Color _slWhite70 = Color(0xB3FFFFFF);

class StaffLeaveScreen extends StatefulWidget {
  const StaffLeaveScreen({super.key});

  @override
  State<StaffLeaveScreen> createState() => _StaffLeaveScreenState();
}

class _StaffLeaveScreenState extends State<StaffLeaveScreen> {
  static const int _leaveAdvanceNoticeHours = 8;

  final _leaveService = LeaveService();
  final _staffService = StaffService();
  final _reasonController = TextEditingController();

  String _selectedLeaveType = '';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _submitting = false;
  int _refreshToken = 0;

  final List<String> _leaveTypes = [
    'Sick Leave',
    'Casual Leave',
    'Half Day Leave',
  ];

  String _formatIndianAppliedTime(DateTime value) {
    final indianTime = value.toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateFormat('MMM dd, yyyy hh:mm a').format(indianTime);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _startDate.isBefore(DateTime.now()) ? DateTime.now() : _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _endDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _submitLeaveRequest(
    String userId,
    String userName,
    String? photoUrl,
    String department,
  ) async {
    if (_selectedLeaveType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a leave type.'),
          backgroundColor: _slError,
        ),
      );
      return;
    }

    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a reason for your leave request.'),
          backgroundColor: _slError,
        ),
      );
      return;
    }

    // Leave must be requested before office start on the selected date.
    final officeStart =
        DateTime(_startDate.year, _startDate.month, _startDate.day, 10, 0);
    if (!DateTime.now().isBefore(officeStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Leave must be applied before office start time (10:00 AM) on the start date.'),
          backgroundColor: _slError,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      await _leaveService.submitLeaveRequest(
        userId: userId,
        userName: userName,
        userPhotoUrl: photoUrl,
        department: department,
        type: _selectedLeaveType,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
        advanceNoticeHours: _leaveAdvanceNoticeHours,
      );

      _reasonController.clear();
      setState(() => _refreshToken++);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Your leave request has been sent to the manager for approval.'),
          backgroundColor: _slSuccess,
        ),
      );

      setState(() {
        _selectedLeaveType = '';
        _startDate = DateTime.now();
        _endDate = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _slError,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    final whiteLabel = context.watch<WhiteLabelProvider>();
    final themeColor = whiteLabel.primaryColor;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leave',
              style: TextStyle(
                color: _slWhite,
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              isMobile
                  ? 'Request leave and track status'
                  : 'Request leave, track approvals, and see your remaining balance.',
              style: TextStyle(color: _slWhite60, fontSize: isMobile ? 11 : 12),
            ),
          ],
        ),
      ),
      body: AppBackground(
        forceDark: true,
        child: StreamBuilder<Staff?>(
          stream: auth.user != null
              ? _staffService.getStaffById(auth.user!.uid)
              : Stream.value(null),
          builder: (context, staffSnapshot) {
            final staff = staffSnapshot.data;

            if (staffSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _slWhite),
              );
            }

            if (staff == null) {
              return Center(
                child: Text(
                  'Staff information not found',
                  style: TextStyle(color: _slWhite.withValues(alpha: 0.7)),
                ),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Leave Balance Summary
                  FutureBuilder<LeaveBalanceSummary>(
                    future: Future.value(_refreshToken).then((_) =>
                        _leaveService.getLeaveBalanceSummaryOnce(staff.id)),
                    builder: (context, balanceSnapshot) {
                      final balance = balanceSnapshot.data ??
                          const LeaveBalanceSummary(
                            monthlyAllowance:
                                LeaveService.monthlyLeaveAllowance,
                            approvedDays: 0,
                            pendingDays: 0,
                            remainingDays: LeaveService.monthlyLeaveAllowance,
                          );

                      return Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isMobile ? 12 : 18),
                        decoration: BoxDecoration(
                          color: _slNavy1,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _slWhite10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monthly Balance',
                              style: TextStyle(
                                color: _slWhite70,
                                fontSize: isMobile ? 12 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: isMobile ? 8 : 16,
                              runSpacing: isMobile ? 12 : 16,
                              children: [
                                _balanceCard(
                                    'Monthly',
                                    _leaveService.formatLeaveDays(
                                        balance.monthlyAllowance),
                                    themeColor,
                                    isMobile),
                                _balanceCard(
                                  'Approved',
                                  _leaveService
                                      .formatLeaveDays(balance.approvedDays),
                                  _slBlue,
                                  isMobile,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Apply Leave Form
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isMobile ? 14 : 20),
                    decoration: BoxDecoration(
                      color: _slNavy1,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _slWhite10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Apply Leave',
                          style: TextStyle(
                            color: _slWhite,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Leave Type Dropdown
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Leave Type',
                              style: TextStyle(
                                color: _slWhite70,
                                fontSize: isMobile ? 11 : 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: _slNavy0,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _slWhite10),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedLeaveType.isEmpty
                                      ? null
                                      : _selectedLeaveType,
                                  isExpanded: true,
                                  hint: Text(
                                    'Select Leave Type',
                                    style: TextStyle(
                                      color: _slWhite54,
                                      fontSize: isMobile ? 13 : 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  dropdownColor: _slNavy0,
                                  style: TextStyle(
                                    color: _slWhite,
                                    fontSize: isMobile ? 13 : 14,
                                  ),
                                  items: _leaveTypes.map((type) {
                                    return DropdownMenuItem(
                                      value: type,
                                      child: Text(type),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(
                                          () => _selectedLeaveType = value);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Start and End Dates
                        isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Start Date
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Start Date',
                                        style: TextStyle(
                                          color: _slWhite70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: _pickStartDate,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: _slNavy0,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border:
                                                Border.all(color: _slWhite10),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                color: themeColor,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  DateFormat('MMM dd, yyyy')
                                                      .format(_startDate),
                                                  style: const TextStyle(
                                                    color: _slWhite,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // End Date
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'End Date',
                                        style: TextStyle(
                                          color: _slWhite70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: _pickEndDate,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: _slNavy0,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border:
                                                Border.all(color: _slWhite10),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                color: themeColor,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  DateFormat('MMM dd, yyyy')
                                                      .format(_endDate),
                                                  style: const TextStyle(
                                                    color: _slWhite,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Start',
                                          style: TextStyle(
                                            color: _slWhite70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        InkWell(
                                          onTap: _pickStartDate,
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: _slNavy0,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border:
                                                  Border.all(color: _slWhite10),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.calendar_today,
                                                  color: themeColor,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    DateFormat('MMM dd')
                                                        .format(_startDate),
                                                    style: const TextStyle(
                                                      color: _slWhite,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'End',
                                          style: TextStyle(
                                            color: _slWhite70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        InkWell(
                                          onTap: _pickEndDate,
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: _slNavy0,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border:
                                                  Border.all(color: _slWhite10),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.calendar_today,
                                                  color: themeColor,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    DateFormat('MMM dd')
                                                        .format(_endDate),
                                                    style: const TextStyle(
                                                      color: _slWhite,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                        const SizedBox(height: 18),

                        if ((staff.reportsTo ?? '').trim().isNotEmpty) ...[
                          FutureBuilder<bool>(
                            future: _leaveService.validateManagerForLeave(
                                staff.reportsTo!.trim()),
                            builder: (context, snapshot) {
                              final managerFound = snapshot.data ?? false;
                              return Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(isMobile ? 10 : 12),
                                decoration: BoxDecoration(
                                  color: managerFound ? _slNavy2 : _slRedDeep,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: managerFound
                                        ? _slWhite10
                                        : _slRed700.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      managerFound
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color:
                                          managerFound ? _slSuccess : _slError,
                                      size: isMobile ? 16 : 18,
                                    ),
                                    SizedBox(width: isMobile ? 6 : 8),
                                    Expanded(
                                      child: Text(
                                        managerFound
                                            ? 'Request will be sent to: ${staff.reportsTo!.trim()}'
                                            : 'Manager "${staff.reportsTo!.trim()}" not found in system',
                                        style: TextStyle(
                                          color: managerFound
                                              ? _slWhite70
                                              : _slRed300,
                                          fontSize: isMobile ? 11 : 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                        ],

                        // Reason TextField
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reason',
                              style: TextStyle(
                                color: _slWhite70,
                                fontSize: isMobile ? 11 : 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _slNavy0,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _slWhite10),
                              ),
                              child: TextField(
                                controller: _reasonController,
                                maxLines: 3,
                                style: TextStyle(
                                  color: _slWhite,
                                  fontSize: isMobile ? 13 : 14,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  filled: false,
                                  hintText: 'Explain the leave request',
                                  hintStyle: TextStyle(color: _slWhite38),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitting
                                ? null
                                : () => _submitLeaveRequest(
                                      staff.id,
                                      staff.name,
                                      staff.photoUrl,
                                      staff.department,
                                    ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _slPrimary,
                              foregroundColor: _slWhite,
                              padding: EdgeInsets.symmetric(
                                  vertical: isMobile ? 12 : 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              disabledBackgroundColor:
                                  _slPrimary.withValues(alpha: 0.5),
                            ),
                            child: Text(
                              _submitting ? 'Submitting...' : 'Submit Leave',
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _slGreenDeep,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '1 unpaid leave day is available per month. Extra leave is still allowed and marked as paid leave.',
                            style: TextStyle(
                              color: _slGreen,
                              fontSize: isMobile ? 11 : 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Leave History
                  FutureBuilder<List<LeaveRequest>>(
                    future: Future.value(_refreshToken).then(
                      (_) => _leaveService.getRequestsForUserOnce(staff.id,
                          limit: 10),
                    ),
                    builder: (context, snapshot) {
                      final requests = snapshot.data ?? const <LeaveRequest>[];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Leave History',
                            style: TextStyle(
                              color: _slWhite,
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (requests.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                  vertical: isMobile ? 30 : 40),
                              decoration: BoxDecoration(
                                color: _slNavy1,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _slWhite10),
                              ),
                              child: Center(
                                child: Text(
                                  'No leave requests yet',
                                  style: TextStyle(
                                    color: _slWhite.withValues(alpha: 0.5),
                                    fontSize: isMobile ? 13 : 14,
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: requests.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final request = requests[index];
                                final statusColor =
                                    _getStatusColor(request.status);

                                return Container(
                                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                                  decoration: BoxDecoration(
                                    color: _slNavy1,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _slWhite10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: isMobile
                                            ? CrossAxisAlignment.start
                                            : CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  request.type,
                                                  style: TextStyle(
                                                    color: _slWhite,
                                                    fontSize:
                                                        isMobile ? 13 : 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${DateFormat('MMM dd').format(request.startDate)} - ${DateFormat('MMM dd').format(request.endDate)}',
                                                  style: TextStyle(
                                                    color: _slWhite70,
                                                    fontSize:
                                                        isMobile ? 11 : 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Applied ${_formatIndianAppliedTime(request.createdAt ?? request.startDate)}',
                                                  style: TextStyle(
                                                    color: _slWhite54,
                                                    fontSize:
                                                        isMobile ? 10 : 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: isMobile ? 8 : 12),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isMobile ? 8 : 12,
                                              vertical: isMobile ? 4 : 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _capitalizeStatus(request.status),
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: isMobile ? 10 : 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (request.reason.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 10),
                                          child: Text(
                                            'Reason: ${request.reason}',
                                            style: TextStyle(
                                              color: _slWhite60,
                                              fontSize: isMobile ? 11 : 12,
                                            ),
                                          ),
                                        ),
                                      if ((request.managerName ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            'Manager: ${request.managerName}',
                                            style: TextStyle(
                                              color: _slWhite54,
                                              fontSize: isMobile ? 11 : 12,
                                            ),
                                          ),
                                        ),
                                      if ((request.managerResponseReason ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  request.status == 'approved'
                                                      ? _slGreen2.withValues(
                                                          alpha: 0.12)
                                                      : _slRed.withValues(
                                                          alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              request.status == 'approved'
                                                  ? 'Approval Reason: ${request.managerResponseReason}'
                                                  : 'Decision Reason: ${request.managerResponseReason}',
                                              style: TextStyle(
                                                color:
                                                    request.status == 'approved'
                                                        ? _slGreen
                                                        : _slRed,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (request.rejectionReason != null &&
                                          request.rejectionReason!.isNotEmpty &&
                                          request.rejectionReason !=
                                              request.managerResponseReason)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  _slRed.withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Rejection Reason: ${request.rejectionReason}',
                                              style: const TextStyle(
                                                color: _slRed,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _balanceCard(String label, String value, Color color, bool isMobile) {
    return SizedBox(
      width: isMobile ? 74 : 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _slWhite70,
              fontSize: isMobile ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return _slGreen2;
      case 'rejected':
        return _slRed;
      case 'pending':
        return _slAmber;
      default:
        return _slWhite70;
    }
  }

  String _capitalizeStatus(String status) {
    return status[0].toUpperCase() + status.substring(1);
  }
}
