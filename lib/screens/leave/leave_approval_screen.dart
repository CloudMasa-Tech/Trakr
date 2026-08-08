import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../models/leave_request.dart';
import '../../providers/auth_session_provider.dart';
import '../../providers/white_label_provider.dart';
import '../../services/leave_service.dart';
import '../../services/staff_service.dart';
import '../../utils/responsive.dart';

// Fixed-brand dark navy palette for the leave approval screen (force-dark).
// Intentional exception: file-scoped brand constants.
const Color _leaveNavy0 = Color(0xFF1A2D5A);
const Color _leaveNavy1 = Color(0xFF162447);
const Color _leaveNavy2 = Color(0xFF243660);
const Color _leaveNavy3 = Color(0xFF243B71);
const Color _leaveNavy4 = Color(0xFF203A5F);
const Color _leaveRed = Color(0xFFFF5757);
const Color _leaveAmber = Color(0xFFFFB800);
const Color _leaveGreen = Color(0xFF00C896);
const Color _leaveBlue = Color(0xFF6EA8FF);
const Color _leaveCoral = Color(0xFFFF8A65);
const Color _leaveGold = Color(0xFFFFB74D);
const Color _leaveError = Color(0xFFF44336);
const Color _leaveOrange = Color(0xFFFF9800);
const Color _leaveSuccess = Color(0xFF4CAF50);
const Color _leaveWhite = Color(0xFFFFFFFF);
const Color _leaveWhite10 = Color(0x1AFFFFFF);
const Color _leaveWhite12 = Color(0x1FFFFFFF);
const Color _leaveWhite38 = Color(0x61FFFFFF);
const Color _leaveWhite54 = Color(0x8AFFFFFF);
const Color _leaveWhite60 = Color(0x99FFFFFF);
const Color _leaveWhite70 = Color(0xB3FFFFFF);

class LeaveApprovalScreen extends StatefulWidget {
  const LeaveApprovalScreen({super.key});

  @override
  State<LeaveApprovalScreen> createState() => _LeaveApprovalScreenState();
}

class _LeaveApprovalScreenState extends State<LeaveApprovalScreen> {
  final LeaveService _leaveService = LeaveService();
  final StaffService _staffService = StaffService();
  LeaveRequest? _selectedRequest;

  Color _getTypeColor(String type) {
    if (type.toLowerCase().contains('sick')) return _leaveCoral;
    if (type.toLowerCase().contains('annual')) return _leaveBlue;
    return _leaveGold;
  }

  String _getDateRange(LeaveRequest req) {
    final format = DateFormat('MMM dd');
    return '${format.format(req.startDate)} - ${format.format(req.endDate)}';
  }

  int _calculateDays(LeaveRequest req) {
    return req.endDate.difference(req.startDate).inDays + 1;
  }

  String _formatStatus(String status) {
    if (status.isEmpty) return 'Pending';
    return status[0].toUpperCase() + status.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    final themeColor = context.watch<WhiteLabelProvider>().primaryColor;
    final isMobile = ResponsiveBreakpoints.isMobile(context);
    final padding = isMobile ? 16.0 : 24.0;

    return auth.user != null
        ? FutureBuilder(
            future: _staffService.getStaffByUserIdentity(
              uid: auth.user!.uid,
              email: auth.user!.email,
            ),
            builder: (context, staffSnapshot) {
              String? managerName;
              if (staffSnapshot.hasData && staffSnapshot.data != null) {
                managerName = staffSnapshot.data!.name;
              } else if (staffSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  body: AppBackground(
                    forceDark: true,
                    child: Center(
                      child: CircularProgressIndicator(color: themeColor),
                    ),
                  ),
                );
              } else {
                // Fallback to displayName or email
                managerName = auth.user?.displayName ??
                    auth.user?.email?.split('@').first;
              }

              return _buildLeaveApprovalScreen(
                themeColor,
                isMobile,
                padding,
                managerName,
              );
            },
          )
        : Scaffold(
            backgroundColor: Colors.transparent,
            body: AppBackground(
              forceDark: true,
              child: Center(
                child: Text(
                  'Please log in first',
                  style: TextStyle(color: _leaveWhite.withValues(alpha: 0.6)),
                ),
              ),
            ),
          );
  }

  Widget _buildLeaveApprovalScreen(
    Color themeColor,
    bool isMobile,
    double padding,
    String? managerName,
  ) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 960;
                  final headerText = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Leave Approvals',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _leaveWhite,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Manage staff time-off requests and monitor team capacity.',
                        style: TextStyle(color: _leaveWhite60),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        managerName != null && managerName.trim().isNotEmpty
                            ? 'Signed in as: $managerName'
                            : 'Signed in as: (unknown)',
                        style:
                            const TextStyle(color: _leaveWhite70, fontSize: 12),
                      ),
                    ],
                  );
                  final statsWidget = StreamBuilder<Map<String, int>>(
                    stream: managerName != null && managerName.trim().isNotEmpty
                        ? _leaveService.getApprovalStatsByManager(managerName)
                        : Stream.value(
                            const {
                              'pending': 0,
                              'approved': 0,
                              'approvedToday': 0
                            },
                          ),
                    builder: (context, snapshot) {
                      final stats = snapshot.data ??
                          const {
                            'pending': 0,
                            'approved': 0,
                            'approvedToday': 0
                          };
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _buildStatCard(
                            'Pending',
                            '${stats['pending'] ?? 0}',
                            Icons.pending_actions_rounded,
                            _leaveAmber,
                            themeColor,
                          ),
                          _buildStatCard(
                            'Approved Today',
                            '${stats['approvedToday'] ?? 0}',
                            Icons.check_circle_rounded,
                            _leaveGreen,
                            themeColor,
                          ),
                        ],
                      );
                    },
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        headerText,
                        const SizedBox(height: 16),
                        statsWidget,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headerText,
                      statsWidget,
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 1100;
                    if (stacked) {
                      return Column(
                        children: [
                          Expanded(
                              child:
                                  _buildRequestsList(themeColor, managerName)),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 420,
                            child: _selectedRequest != null
                                ? _buildEmployeeDetails(
                                    _selectedRequest!,
                                    themeColor,
                                  )
                                : _buildEmptyDetails(),
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            flex: 2,
                            child: _buildRequestsList(themeColor, managerName)),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 1,
                          child: _selectedRequest != null
                              ? _buildEmployeeDetails(
                                  _selectedRequest!, themeColor)
                              : _buildEmptyDetails(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsList(Color themeColor, String? managerName) {
    // If no manager name, show empty
    if (managerName == null || managerName.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _leaveNavy1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _leaveWhite10),
        ),
        child: Center(
          child: Text(
            'Manager information not found. Please ensure you are logged in as a manager.',
            style: TextStyle(color: _leaveWhite.withValues(alpha: 0.6)),
          ),
        ),
      );
    }

    return StreamBuilder<List<LeaveRequest>>(
      stream: _leaveService.getPendingRequestsByManager(managerName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: themeColor));
        }

        final requests = snapshot.data ?? const <LeaveRequest>[];

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _leaveNavy1,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _leaveWhite10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.list_alt_rounded,
                          color: _leaveWhite70, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Pending Requests',
                        style: TextStyle(
                          color: _leaveWhite,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${requests.length} open',
                    style: TextStyle(
                      color: themeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: requests.isEmpty
                    ? Center(
                        child: Text(
                          'No pending leave requests found.',
                          style: TextStyle(
                              color: _leaveWhite.withValues(alpha: 0.55)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final req = requests[index];
                          final isSelected = _selectedRequest?.id == req.id;

                          return GestureDetector(
                            onTap: () => setState(() => _selectedRequest = req),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected ? _leaveNavy3 : _leaveNavy0,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? themeColor.withValues(alpha: 0.7)
                                      : _leaveWhite10,
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 760;
                                  if (compact) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 24,
                                              backgroundImage:
                                                  req.userPhotoUrl != null
                                                      ? NetworkImage(
                                                          req.userPhotoUrl!)
                                                      : null,
                                              backgroundColor: _leaveWhite12,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    req.userName,
                                                    style: const TextStyle(
                                                      color: _leaveWhite,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: _getTypeColor(
                                                                  req.type)
                                                              .withValues(
                                                                  alpha: 0.14),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                        ),
                                                        child: Text(
                                                          req.type
                                                              .toUpperCase(),
                                                          style: TextStyle(
                                                            color:
                                                                _getTypeColor(
                                                                    req.type),
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        '${_getDateRange(req)} (${_calculateDays(req)} day${_calculateDays(req) > 1 ? 's' : ''})',
                                                        style: const TextStyle(
                                                          color: _leaveWhite60,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (req.reason.trim().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            req.reason,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _leaveWhite54,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _buildActionButton(
                                              req,
                                              'Reject',
                                              _leaveRed,
                                              themeColor,
                                              managerName,
                                            ),
                                            _buildActionButton(
                                              req,
                                              'Approve',
                                              themeColor,
                                              themeColor,
                                              managerName,
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundImage: req.userPhotoUrl !=
                                                null
                                            ? NetworkImage(req.userPhotoUrl!)
                                            : null,
                                        backgroundColor: _leaveWhite12,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              req.userName,
                                              style: const TextStyle(
                                                color: _leaveWhite,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _getTypeColor(req.type)
                                                            .withValues(
                                                                alpha: 0.14),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    req.type.toUpperCase(),
                                                    style: TextStyle(
                                                      color: _getTypeColor(
                                                          req.type),
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '${_getDateRange(req)} (${_calculateDays(req)} day${_calculateDays(req) > 1 ? 's' : ''})',
                                                    style: const TextStyle(
                                                      color: _leaveWhite60,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (req.reason
                                                .trim()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                req.reason,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: _leaveWhite54,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          _buildActionButton(
                                            req,
                                            'Reject',
                                            _leaveRed,
                                            themeColor,
                                            managerName,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildActionButton(
                                            req,
                                            'Approve',
                                            themeColor,
                                            themeColor,
                                            managerName,
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmployeeDetails(LeaveRequest req, Color themeColor) {
    return StreamBuilder<LeaveBalanceSummary>(
      stream: _leaveService.getLeaveBalanceSummary(req.userId),
      builder: (context, balanceSnapshot) {
        final balance = balanceSnapshot.data ??
            const LeaveBalanceSummary(
              monthlyAllowance: LeaveService.monthlyLeaveAllowance,
              approvedDays: 0,
              pendingDays: 0,
              remainingDays: LeaveService.monthlyLeaveAllowance,
            );

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _leaveNavy1,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _leaveWhite10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage: req.userPhotoUrl != null
                          ? NetworkImage(req.userPhotoUrl!)
                          : null,
                      backgroundColor: _leaveWhite12,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      req.userName,
                      style: const TextStyle(
                        color: _leaveWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      req.department,
                      style:
                          const TextStyle(color: _leaveWhite60, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 140,
                    child: _buildMiniCard(
                      'Monthly Allowance',
                      '${_leaveService.formatLeaveDays(balance.monthlyAllowance)} Days',
                      accent: themeColor,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: _buildMiniCard(
                      'Remaining',
                      '${_leaveService.formatLeaveDays(balance.remainingDays)} Days',
                      accent: _leaveGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 140,
                    child: _buildMiniCard(
                      'Approved',
                      '${_leaveService.formatLeaveDays(balance.approvedDays)} Day${balance.approvedDays == 1 ? '' : 's'}',
                      accent: _leaveBlue,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: _buildMiniCard(
                      'Pending',
                      '${_leaveService.formatLeaveDays(balance.pendingDays)} Day${balance.pendingDays == 1 ? '' : 's'}',
                      accent: _leaveAmber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'LEAVE HISTORY',
                style: TextStyle(
                  color: _leaveWhite54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<LeaveRequest>>(
                  stream: _leaveService.getHistoryForUser(req.userId),
                  builder: (context, snapshot) {
                    final history = snapshot.data ?? const <LeaveRequest>[];
                    if (history.isEmpty) {
                      return Center(
                        child: Text(
                          'No leave history yet',
                          style: TextStyle(
                              color: _leaveWhite.withValues(alpha: 0.45)),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final statusColor = item.status == 'approved'
                            ? _leaveGreen
                            : item.status == 'rejected'
                                ? _leaveRed
                                : _leaveAmber;
                        return _buildHistoryItem(
                          item.type,
                          '${_getDateRange(item)} (${_calculateDays(item)} day${_calculateDays(item) > 1 ? 's' : ''})',
                          _formatStatus(item.status),
                          statusColor,
                          subtitle: item.managerResponseReason
                                      ?.trim()
                                      .isNotEmpty ==
                                  true
                              ? '${item.reason}\nDecision: ${item.managerResponseReason}'
                              : item.reason,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _leaveNavy3,
                    foregroundColor: _leaveWhite,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('View Full Employee Profile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniCard(String title, String value, {required Color accent}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _leaveNavy0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _leaveWhite10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: _leaveWhite54, fontSize: 10)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDetails() {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _leaveNavy1,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _leaveWhite10),
      ),
      child: Text(
        'Select a request to view details',
        style: TextStyle(color: _leaveWhite.withValues(alpha: 0.35)),
      ),
    );
  }

  Widget _buildActionButton(
    LeaveRequest req,
    String text,
    Color color,
    Color themeColor,
    String? managerName,
  ) {
    return ElevatedButton(
      onPressed: () async {
        if (text == 'Reject') {
          _showRejectionDialog(req, themeColor, managerName);
        } else {
          _showApprovalDialog(req, themeColor, managerName);
          return;
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: text == 'Approve' ? color : _leaveNavy0,
        foregroundColor: text == 'Approve' ? _leaveWhite : color,
        side: BorderSide(
          color: text == 'Reject' ? color : themeColor.withValues(alpha: 0.24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text),
    );
  }

  void _showApprovalDialog(
    LeaveRequest req,
    Color themeColor,
    String? managerName,
  ) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => Theme(
        data: ThemeData.dark().copyWith(
          dialogTheme: const DialogThemeData(
            backgroundColor: _leaveNavy0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _leaveNavy2,
            hintStyle: const TextStyle(color: _leaveWhite38),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _leaveWhite10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: themeColor, width: 1.4),
            ),
          ),
        ),
        child: AlertDialog(
          backgroundColor: _leaveNavy0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _leaveWhite10),
          ),
          title: const Text(
            'Approve Leave Request',
            style: TextStyle(color: _leaveWhite, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Employee: ${req.userName}',
                style: const TextStyle(color: _leaveWhite70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Leave Type: ${req.type}',
                style: const TextStyle(color: _leaveWhite70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Duration: ${_getDateRange(req)} (${_calculateDays(req)} day${_calculateDays(req) > 1 ? 's' : ''})',
                style: const TextStyle(color: _leaveWhite70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _leaveNavy4,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _leaveWhite10),
                ),
                child: Text(
                  'Staff Reason: ${req.reason}',
                  style: const TextStyle(
                    color: _leaveWhite60,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Approval Reason (Required)',
                style: TextStyle(
                  color: _leaveWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 4,
                style: const TextStyle(color: _leaveWhite),
                decoration: InputDecoration(
                  hintText: 'Explain your approval decision',
                  hintStyle: const TextStyle(color: _leaveWhite38),
                  filled: true,
                  fillColor: _leaveNavy2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _leaveWhite70),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();

                if (reason.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide an approval reason'),
                      backgroundColor: _leaveOrange,
                    ),
                  );
                  return;
                }

                try {
                  await _leaveService.updateLeaveStatus(
                    req.id,
                    'approved',
                    managerResponseReason: reason,
                    actingManagerName: managerName,
                    enforceAssignedManager: true,
                  );

                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (_selectedRequest?.id == req.id) {
                    setState(() => _selectedRequest = null);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Leave request approved successfully'),
                      backgroundColor: _leaveSuccess,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(e.toString().replaceFirst('Exception: ', '')),
                      backgroundColor: _leaveError,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: _leaveWhite,
              ),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRejectionDialog(
    LeaveRequest req,
    Color themeColor,
    String? managerName,
  ) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => Theme(
        data: ThemeData.dark().copyWith(
          dialogTheme: const DialogThemeData(
            backgroundColor: _leaveNavy0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _leaveNavy2,
            hintStyle: const TextStyle(color: _leaveWhite38),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _leaveWhite10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _leaveRed, width: 1.4),
            ),
          ),
        ),
        child: AlertDialog(
          backgroundColor: _leaveNavy0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _leaveWhite10),
          ),
          title: const Text(
            'Reject Leave Request',
            style: TextStyle(color: _leaveWhite, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Employee: ${req.userName}',
                style: const TextStyle(color: _leaveWhite70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Leave Type: ${req.type}',
                style: const TextStyle(color: _leaveWhite70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Duration: ${_getDateRange(req)} (${_calculateDays(req)} day${_calculateDays(req) > 1 ? 's' : ''})',
                style: const TextStyle(color: _leaveWhite70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _leaveNavy4,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _leaveWhite10),
                ),
                child: Text(
                  'Staff Reason: ${req.reason}',
                  style: const TextStyle(
                    color: _leaveWhite60,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Rejection Reason (Required)',
                style: TextStyle(
                  color: _leaveWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 4,
                style: const TextStyle(color: _leaveWhite),
                decoration: InputDecoration(
                  hintText: 'Explain why you are rejecting this request',
                  hintStyle: const TextStyle(color: _leaveWhite38),
                  filled: true,
                  fillColor: _leaveNavy2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _leaveWhite70),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();

                if (reason.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide a rejection reason'),
                      backgroundColor: _leaveOrange,
                    ),
                  );
                  return;
                }

                try {
                  await _leaveService.updateLeaveStatus(
                    req.id,
                    'rejected',
                    managerResponseReason: reason,
                    rejectionReason: reason,
                    actingManagerName: managerName,
                    enforceAssignedManager: true,
                  );

                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (_selectedRequest?.id == req.id) {
                    setState(() => _selectedRequest = null);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Leave request rejected successfully'),
                      backgroundColor: _leaveError,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(e.toString().replaceFirst('Exception: ', '')),
                      backgroundColor: _leaveError,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _leaveRed,
                foregroundColor: _leaveWhite,
              ),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color themeColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _leaveNavy0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: _leaveWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: _leaveWhite60, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    String title,
    String date,
    String status,
    Color statusColor, {
    String subtitle = '',
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _leaveNavy0,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _leaveWhite10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _leaveWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date,
                  style: const TextStyle(color: _leaveWhite60, fontSize: 12),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _leaveWhite38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
