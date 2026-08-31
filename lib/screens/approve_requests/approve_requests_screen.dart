// lib/screens/approve_requests/approve_requests_screen.dart
//
// Shared "Approve Requests" module used by BOTH the Admin and Manager roles.
// A single consolidated place to review and approve/reject Leave, Permission
// (step-out) and Checkout requests. The UI/tabs/actions are identical for both
// roles; only the underlying data query differs:
//
//   - Manager scope  (isCompanyWide=false, managerScope set):
//       * existing LeaveService.getRequestsForManager
//       * existing PermissionService.getPermissionRequestsForManager
//       * AttendanceService.getCheckoutRequestsForManager (reporting-line
//         filtered copy of the company-wide checkout stream)
//   - Admin scope    (isCompanyWide=true, managerScope null):
//       * full leave/permission collection streams (already read-permitted
//         under existing signedIn() rules)
//       * existing company-wide AttendanceService.getCheckoutRequestsStream
//
// This screen is rendered as a bounded, self-managed-scrolling widget so it
// works both inside the Admin AppShell's Expanded content area and inside the
// Manager shell's non-scroll-wrapped page slot.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/attendance_model.dart';
import '../../models/leave_request.dart';
import '../../models/permission_request.dart';
import '../../services/attendance_service.dart';
import '../../services/leave_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme_colors.dart';

// Fixed-brand dark palette (matches the app's force-dark screens). Intentional
// exception: file-scoped brand constants.
const Color _arPrimary = Color(0xFF0F766E);
const Color _arGreen = Color(0xFF16B86A);
const Color _arRed = Color(0xFFFF5B72);
const Color _arAmber = Color(0xFFFFA400);
const Color _arTintBlue = Color(0xFFEAF3FF);
const Color _arShadow = Color(0x1A6B7897);
const Color _arWhite = Color(0xFFFFFFFF);

enum _RequestTab { leave, permission, checkout }

class ApproveRequestsScreen extends StatefulWidget {
  /// When true this is the Admin company-wide view (no reporting-line filter).
  /// When false it is the Manager team-scoped view and [managerScope] must be
  /// the resolved manager identity (the manager shell's `_attendanceManagerScope`).
  final bool isCompanyWide;

  /// The manager identity used to scope queries (only when [isCompanyWide] is
  /// false). Mirrors the manager shell's scoping key.
  final String? managerScope;

  const ApproveRequestsScreen({
    super.key,
    this.isCompanyWide = false,
    this.managerScope,
  });

  @override
  State<ApproveRequestsScreen> createState() => _ApproveRequestsScreenState();
}

class _ApproveRequestsScreenState extends State<ApproveRequestsScreen> {
  final LeaveService _leaveService = LeaveService();
  final PermissionService _permissionService = PermissionService();
  final AttendanceService _attendanceService = AttendanceService();

  _RequestTab _selectedTab = _RequestTab.leave;

  bool get _companyWide => widget.isCompanyWide;

  String get _scopeLabel =>
      _companyWide ? 'all employees (company-wide)' : 'your team';

  String? get _actorIdentity {
    final user = FirebaseContextProvider.current.auth.currentUser;
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email?.trim();
    return (email != null && email.isNotEmpty) ? email : 'Admin';
  }

  // ─── Data streams ─────────────────────────────────────────────────────────

  Stream<List<LeaveRequest>> _leaveStream() {
    if (_companyWide) {
      return FirebaseContextProvider.current.firestore
          .collection('leave_requests')
          .snapshots()
          .map((snap) => snap.docs
              .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
              .toList());
    }
    final scope = widget.managerScope?.trim();
    if (scope == null || scope.isEmpty) {
      return const Stream.empty();
    }
    return _leaveService.getRequestsForManager(scope);
  }

  Stream<List<PermissionRequest>> _permissionStream() {
    if (_companyWide) {
      return FirebaseContextProvider.current.firestore
          .collection('permission_requests')
          .snapshots()
          .map((snap) => snap.docs
              .map((doc) => PermissionRequest.fromFirestore(doc))
              .toList());
    }
    final scope = widget.managerScope?.trim();
    if (scope == null || scope.isEmpty) {
      return const Stream.empty();
    }
    return _permissionService.getPermissionRequestsForManager(scope);
  }

  Stream<List<CheckoutRequest>> _checkoutStream() {
    if (_companyWide) {
      return _attendanceService.getCheckoutRequestsStream();
    }
    final scope = widget.managerScope?.trim();
    if (scope == null || scope.isEmpty) {
      return const Stream.empty();
    }
    return _attendanceService.getCheckoutRequestsForManager(scope);
  }

  // ─── Approve / Reject (reuse existing service logic) ─────────────────────

  Future<void> _approveLeave(LeaveRequest request) async {
    try {
      await _leaveService.updateLeaveStatus(
        request.id,
        'approved',
        managerResponseReason: 'Approved from Approve Requests',
        actingManagerName: _companyWide ? null : (widget.managerScope ?? ''),
      );
      _snack('Leave request approved', _arGreen);
    } catch (e) {
      _snack('Could not approve leave: $e', _arRed);
    }
  }

  Future<void> _rejectLeave(LeaveRequest request) async {
    try {
      await _leaveService.updateLeaveStatus(
        request.id,
        'rejected',
        rejectionReason: 'Rejected from Approve Requests',
        actingManagerName: _companyWide ? null : (widget.managerScope ?? ''),
      );
      _snack('Leave request rejected', _arRed);
    } catch (e) {
      _snack('Could not reject leave: $e', _arRed);
    }
  }

  Future<void> _approvePermission(PermissionRequest request) async {
    try {
      await _permissionService.approvePermissionRequest(
        requestId: request.id,
        managerName: _actorIdentity ?? 'Admin',
        response: 'Approved from Approve Requests',
        isPaid: request.isPaid,
        returnTime: request.toTime ?? request.returnTime,
      );
      _snack('Permission request approved', _arGreen);
    } catch (e) {
      _snack('Could not approve permission: $e', _arRed);
    }
  }

  Future<void> _rejectPermission(PermissionRequest request) async {
    try {
      await _permissionService.rejectPermissionRequest(
        request.id,
        _actorIdentity ?? 'Admin',
        'Rejected from Approve Requests',
      );
      _snack('Permission request rejected', _arRed);
    } catch (e) {
      _snack('Could not reject permission: $e', _arRed);
    }
  }

  Future<void> _approveCheckout(CheckoutRequest request) async {
    try {
      await _attendanceService.approveCheckoutRequest(
        request,
        adminNote: 'Approved from Approve Requests',
      );
      _snack('Checkout request approved', _arGreen);
    } catch (e) {
      _snack('Could not approve checkout: $e', _arRed);
    }
  }

  Future<void> _rejectCheckout(CheckoutRequest request) async {
    try {
      await _attendanceService.rejectCheckoutRequest(
        request,
        adminNote: 'Rejected from Approve Requests',
      );
      _snack('Checkout request rejected', _arRed);
    } catch (e) {
      _snack('Could not reject checkout: $e', _arRed);
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final padding = isMobile ? 16.0 : 24.0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isMobile),
            const SizedBox(height: 18),
            _buildTabBar(isMobile),
            const SizedBox(height: 18),
            Expanded(child: _buildTabContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final body = _companyWide
        ? 'Review and manage leave, permission and checkout requests from all employees (company-wide).'
        : 'Review and manage leave, permission and checkout requests from $_scopeLabel.';

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Approve Requests',
          style: TextStyle(
            color: AppThemeColors.darkText,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: const TextStyle(
            color: AppThemeColors.darkMuted,
            fontSize: 13.5,
          ),
        ),
      ],
    );

    if (isMobile) return titleBlock;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: titleBlock)],
    );
  }

  Widget _buildTabBar(bool isMobile) {
    Widget tab(String label, _RequestTab tab) {
      final selected = _selectedTab == tab;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _selectedTab = tab),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: selected
                  ? _arPrimary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _arPrimary : AppThemeColors.darkMuted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: Row(
        children: [
          tab('Leave', _RequestTab.leave),
          tab('Permission', _RequestTab.permission),
          tab('Checkout', _RequestTab.checkout),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case _RequestTab.leave:
        return _buildLeaveTab();
      case _RequestTab.permission:
        return _buildPermissionTab();
      case _RequestTab.checkout:
        return _buildCheckoutTab();
    }
  }

  // ─── Leave tab ────────────────────────────────────────────────────────────

  Widget _buildLeaveTab() {
    return StreamBuilder<List<LeaveRequest>>(
      stream: _leaveStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _arPrimary),
          );
        }
        final requests = snapshot.data ?? const <LeaveRequest>[];
        final pending =
            requests.where((r) => r.status == 'pending').toList()
              ..sort((a, b) => b.startDate.compareTo(a.startDate));
        final history =
            requests.where((r) => r.status != 'pending').toList()
              ..sort((a, b) {
                final aa = a.respondedAt ?? a.startDate;
                final bb = b.respondedAt ?? b.startDate;
                return bb.compareTo(aa);
              });
        return _buildRequestList(
          pendingTitle: 'Pending Leave Requests',
          historyTitle: 'Recent Leave Decisions',
          pending: pending,
          history: history,
          emptyMessage: 'No leave requests found for $_scopeLabel.',
          cardBuilder: _buildLeaveCard,
        );
      },
    );
  }

  Widget _buildLeaveCard(LeaveRequest r) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final isPending = r.status == 'pending';
    final statusColor =
        r.status == 'approved' ? _arGreen : r.status == 'rejected' ? _arRed : _arAmber;
    final date = '${DateFormat('MMM dd').format(r.startDate)} – ${DateFormat('MMM dd, yyyy').format(r.endDate)}';
    return _buildCard(
      leadingInitial: r.userName.isNotEmpty ? r.userName[0].toUpperCase() : 'S',
      leadingColor: _arPrimary,
      name: r.userName,
      subtitle: '${r.department}  •  ${r.employeeId ?? r.userId}',
      status: r.status,
      statusColor: statusColor,
      details: [
        _detail(Icons.calendar_today_rounded, 'Dates', date),
        _detail(Icons.category_rounded, 'Type', r.type),
        _detail(
          Icons.account_balance_wallet_rounded,
          'Pay',
          r.isPaid ? 'Paid (${r.paidDayCount.toStringAsFixed(0)}d)' : 'Unpaid (${r.unpaidDayCount.toStringAsFixed(0)}d)',
        ),
      ],
      body: [
        if (r.reason.isNotEmpty)
          Text(
            'Reason: ${r.reason}',
            style: TextStyle(
              color: AppThemeColors.darkText,
              fontSize: isMobile ? 13 : 14,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Requested: ${_fmt(r.createdAt)}',
          style: const TextStyle(
            color: AppThemeColors.darkMuted,
            fontSize: 12,
          ),
        ),
      ],
      pendingActions: isPending
          ? [
              _actionButton(
                label: 'Approve',
                icon: Icons.check_rounded,
                color: _arGreen,
                isMobile: isMobile,
                onPressed: () => _approveLeave(r),
              ),
              _actionButton(
                label: 'Reject',
                icon: Icons.close_rounded,
                color: _arRed,
                isMobile: isMobile,
                onPressed: () => _rejectLeave(r),
              ),
            ]
          : null,
    );
  }

  // ─── Permission tab ───────────────────────────────────────────────────────

  Widget _buildPermissionTab() {
    return StreamBuilder<List<PermissionRequest>>(
      stream: _permissionStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _arPrimary),
          );
        }
        final requests = snapshot.data ?? const <PermissionRequest>[];
        final pending =
            requests.where((r) => r.status == 'pending').toList()
              ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
        final history =
            requests.where((r) => r.status != 'pending').toList()
              ..sort((a, b) {
                final aa = a.respondedAt ?? a.requestedAt;
                final bb = b.respondedAt ?? b.requestedAt;
                return bb.compareTo(aa);
              });
        return _buildRequestList(
          pendingTitle: 'Pending Permission Requests',
          historyTitle: 'Recent Permission Decisions',
          pending: pending,
          history: history,
          emptyMessage: 'No permission requests found for $_scopeLabel.',
          cardBuilder: _buildPermissionCard,
        );
      },
    );
  }

  Widget _buildPermissionCard(PermissionRequest r) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final isPending = r.status == 'pending';
    final statusColor =
        r.status == 'approved' ? _arGreen : r.status == 'rejected' ? _arRed : _arAmber;
    final window = r.fromTime != null && r.toTime != null
        ? '${DateFormat('hh:mm a').format(r.fromTime!)} – ${DateFormat('hh:mm a').format(r.toTime!)}'
        : r.returnTime != null
            ? 'Return: ${DateFormat('hh:mm a').format(r.returnTime!)}'
            : 'N/A';
    return _buildCard(
      leadingInitial: r.employeeName.isNotEmpty
          ? r.employeeName[0].toUpperCase()
          : 'S',
      leadingColor: _arPrimary,
      name: r.employeeName,
      subtitle: '${r.department}  •  ${r.employeeId}',
      status: r.status,
      statusColor: statusColor,
      details: [
        _detail(Icons.schedule_rounded, 'Window', window),
        if (r.permissionType != null)
          _detail(Icons.low_priority_rounded, 'Type', r.permissionType!),
        _detail(Icons.paid_rounded, 'Paid', r.isPaid ? 'Yes' : 'No'),
      ],
      body: [
        if (r.reason.isNotEmpty)
          Text(
            'Reason: ${r.reason}',
            style: TextStyle(
              color: AppThemeColors.darkText,
              fontSize: isMobile ? 13 : 14,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Requested: ${_fmt(r.requestedAt)}',
          style: const TextStyle(
            color: AppThemeColors.darkMuted,
            fontSize: 12,
          ),
        ),
      ],
      pendingActions: isPending
          ? [
              _actionButton(
                label: 'Approve',
                icon: Icons.check_rounded,
                color: _arGreen,
                isMobile: isMobile,
                onPressed: () => _approvePermission(r),
              ),
              _actionButton(
                label: 'Reject',
                icon: Icons.close_rounded,
                color: _arRed,
                isMobile: isMobile,
                onPressed: () => _rejectPermission(r),
              ),
            ]
          : null,
    );
  }

  // ─── Checkout tab ─────────────────────────────────────────────────────────

  Widget _buildCheckoutTab() {
    return StreamBuilder<List<CheckoutRequest>>(
      stream: _checkoutStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _arPrimary),
          );
        }
        final requests = snapshot.data ?? const <CheckoutRequest>[];
        final pending =
            requests.where((r) => r.status == 'pending').toList()
              ..sort((a, b) => b.checkoutDeadline.compareTo(a.checkoutDeadline));
        final history =
            requests.where((r) => r.status != 'pending').toList()
              ..sort((a, b) {
                final aa = a.resolvedAt ?? a.createdAt;
                final bb = b.resolvedAt ?? b.createdAt;
                return bb.compareTo(aa);
              });
        return _buildRequestList(
          pendingTitle: 'Pending Checkout Requests',
          historyTitle: 'Recent Checkout Decisions',
          pending: pending,
          history: history,
          emptyMessage: 'No checkout requests found for $_scopeLabel.',
          cardBuilder: _buildCheckoutCard,
        );
      },
    );
  }

  Widget _buildCheckoutCard(CheckoutRequest r) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final isPending = r.status == 'pending';
    final statusColor =
        r.status == 'approved' ? _arGreen : r.status == 'rejected' ? _arRed : _arAmber;
    final date = DateFormat('MMM dd, yyyy').format(r.checkoutDeadline);
    final checkIn =
        r.checkInTime == null ? 'Not available' : DateFormat('hh:mm a').format(r.checkInTime!);
    final deadline = DateFormat('hh:mm a').format(r.checkoutDeadline);
    return _buildCard(
      leadingIcon: Icons.logout_rounded,
      leadingColor: statusColor,
      name: r.employeeName.isEmpty ? r.employeeId : r.employeeName,
      subtitle: '${r.department}  •  ${r.employeeId}',
      status: r.status,
      statusColor: statusColor,
      details: [
        _detail(Icons.calendar_today_rounded, 'Date', date),
        _detail(Icons.login_rounded, 'Check-in', checkIn),
        _detail(Icons.schedule_rounded, 'Checkout due', deadline),
        _detail(Icons.email_rounded, 'Email', r.email.isEmpty ? '—' : r.email),
        _detail(Icons.phone_rounded, 'Phone', r.phone.isEmpty ? '—' : r.phone),
      ],
      body: [
        if (r.queryMessage.isNotEmpty)
          Text(
            r.queryMessage,
            style: const TextStyle(
              color: AppThemeColors.darkMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
      ],
      pendingActions: isPending
          ? [
              _actionButton(
                label: 'Approve',
                icon: Icons.check_rounded,
                color: _arGreen,
                isMobile: isMobile,
                onPressed: () => _approveCheckout(r),
              ),
              _actionButton(
                label: 'Reject',
                icon: Icons.close_rounded,
                color: _arRed,
                isMobile: isMobile,
                onPressed: () => _rejectCheckout(r),
              ),
            ]
          : null,
    );
  }

  // ─── Shared layout helpers ────────────────────────────────────────────────

  Widget _buildRequestList<T>({
    required String pendingTitle,
    required String historyTitle,
    required List<T> pending,
    required List<T> history,
    required String emptyMessage,
    required Widget Function(T item) cardBuilder,
  }) {
    if (pending.isEmpty && history.isEmpty) {
      return _buildEmptyPanel(emptyMessage);
    }
    return ListView(
      children: [
        if (pending.isNotEmpty) ...[
          _buildSectionTitle(pendingTitle, pending.length),
          const SizedBox(height: 12),
          ...pending.map(cardBuilder),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionTitle(historyTitle, history.length),
          const SizedBox(height: 12),
          ...history.take(15).map(cardBuilder),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppThemeColors.darkText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _arTintBlue,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: _arPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPanel(String message) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppThemeColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppThemeColors.darkBorder),
        ),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppThemeColors.darkMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    IconData? leadingIcon,
    String? leadingInitial,
    required Color leadingColor,
    required String name,
    required String subtitle,
    required String status,
    required Color statusColor,
    required List<Widget> details,
    required List<Widget> body,
    List<Widget>? pendingActions,
  }) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _arShadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: leadingColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: leadingIcon != null
                    ? Icon(leadingIcon, color: leadingColor)
                    : Center(
                        child: Text(
                          leadingInitial ?? 'S',
                          style: TextStyle(
                            color: leadingColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppThemeColors.darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppThemeColors.darkMuted,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(status, statusColor),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 520 ? 2 : 3;
              const gap = 10.0;
              final itemWidth =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: details
                    .map((d) => SizedBox(width: itemWidth, child: d))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          ...body,
          if (pendingActions != null && pendingActions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: pendingActions
                  .map((a) => SizedBox(
                        width: isMobile ? double.infinity : null,
                        child: a,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, size: 16, color: AppThemeColors.darkMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppThemeColors.darkText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status, Color color) {
    final label = status.isEmpty
        ? 'Pending'
        : '${status[0].toUpperCase()}${status.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isMobile,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: _arWhite,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _fmt(DateTime? t) {
    if (t == null) return '—';
    return DateFormat('MMM dd, yyyy hh:mm a').format(t);
  }
}
