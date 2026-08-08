import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme_colors.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../utils/responsive.dart';

// Fixed-brand palette for the checkout request screen (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _crPrimary = Color(0xFF0F766E);
const Color _crGreen = Color(0xFF16B86A);
const Color _crRed = Color(0xFFFF5B72);
const Color _crTintBlue = Color(0xFFEAF3FF);
const Color _crAmber = Color(0xFFFFB400);
const Color _crShadow = Color(0x126B7897);
const Color _crWhite = Color(0xFFFFFFFF);

class CheckoutRequestScreen extends StatefulWidget {
  const CheckoutRequestScreen({super.key});

  @override
  State<CheckoutRequestScreen> createState() => _CheckoutRequestScreenState();
}

class _CheckoutRequestScreenState extends State<CheckoutRequestScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _syncRequests();
  }

  Future<void> _syncRequests() async {
    setState(() => _isSyncing = true);
    try {
      await _attendanceService.syncOverdueAttendanceRecords();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _approveRequest(CheckoutRequest request) async {
    try {
      await _attendanceService.approveCheckoutRequest(
        request,
        adminNote: 'Approved from dashboard',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout request approved.'),
          backgroundColor: _crGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update request: $error'),
          backgroundColor: _crRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.isMobile(context);
    final padding = isMobile ? 16.0 : 28.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile),
              const SizedBox(height: 24),
              Expanded(
                child: StreamBuilder<List<CheckoutRequest>>(
                  stream: _attendanceService.getCheckoutRequestsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _crPrimary),
                      );
                    }

                    final requests = snapshot.data ?? const <CheckoutRequest>[];
                    if (requests.isEmpty) {
                      return _buildEmptyState();
                    }

                    final pending = requests
                        .where((request) => request.status == 'pending')
                        .toList();
                    final history = requests
                        .where((request) => request.status != 'pending')
                        .toList();

                    return ListView(
                      children: [
                        _buildSectionTitle('Pending Approval', pending.length),
                        const SizedBox(height: 12),
                        if (pending.isEmpty)
                          _buildEmptyPanel('No pending checkout requests.')
                        else
                          ...pending.map(_buildRequestCard),
                        const SizedBox(height: 22),
                        _buildSectionTitle('Recent Decisions', history.length),
                        const SizedBox(height: 12),
                        if (history.isEmpty)
                          _buildEmptyPanel(
                              'Approved and rejected requests appear here.')
                        else
                          ...history.take(12).map(_buildRequestCard),
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

  Widget _buildHeader(bool isMobile) {
    const titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Checkout Requests',
          style: TextStyle(
            color: AppThemeColors.darkText,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Review staff who missed the configured checkout window and one-hour grace period.',
          style: TextStyle(color: AppThemeColors.darkMuted, fontSize: 13.5),
        ),
      ],
    );

    final syncButton = OutlinedButton.icon(
      onPressed: _isSyncing ? null : _syncRequests,
      icon: _isSyncing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_rounded, size: 18),
      label: Text(_isSyncing ? 'Checking' : 'Check Now'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _crPrimary,
        side: const BorderSide(color: _crPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: syncButton),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: titleBlock),
        const SizedBox(width: 16),
        syncButton,
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
            color: _crTintBlue,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: _crPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(CheckoutRequest request) {
    final isMobile = ResponsiveBreakpoints.isMobile(context);
    final isPending = request.status == 'pending';
    final statusColor = request.status == 'approved'
        ? _crGreen
        : request.status == 'rejected'
            ? _crRed
            : _crAmber;
    final date = DateFormat('MMM dd, yyyy').format(request.checkoutDeadline);
    final checkIn = request.checkInTime == null
        ? 'Not available'
        : DateFormat('hh:mm a').format(request.checkInTime!);
    final deadline = DateFormat('hh:mm a').format(request.checkoutDeadline);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _crShadow,
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
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.logout_rounded, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.employeeName.isEmpty
                          ? request.employeeId
                          : request.employeeName,
                      style: const TextStyle(
                        color: AppThemeColors.darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.department}  •  ${request.employeeId}',
                      style: const TextStyle(
                        color: AppThemeColors.darkMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(request.status, statusColor),
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
                children: [
                  _detail(Icons.calendar_today_rounded, 'Date', date,
                      width: itemWidth),
                  _detail(Icons.login_rounded, 'Check-in', checkIn,
                      width: itemWidth),
                  _detail(Icons.schedule_rounded, 'Checkout due', deadline,
                      width: itemWidth),
                  _detail(
                    Icons.phone_rounded,
                    'Phone',
                    request.phone.isEmpty ? 'No phone' : request.phone,
                    width: itemWidth,
                  ),
                  _detail(
                    Icons.email_rounded,
                    'Email',
                    request.email.isEmpty ? 'No email' : request.email,
                    width: itemWidth,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            request.queryMessage,
            style: const TextStyle(
              color: AppThemeColors.darkMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: isMobile ? double.infinity : null,
                  child: ElevatedButton.icon(
                    onPressed: () => _approveRequest(request),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _crPrimary,
                      foregroundColor: _crWhite,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value, {double? width}) {
    return SizedBox(
      width: width,
      child: Container(
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

  Widget _buildEmptyState() {
    return _buildEmptyPanel(
      'No checkout requests yet. Missed checkouts appear here one hour after the configured checkout time ends.',
    );
  }

  Widget _buildEmptyPanel(String message) {
    return Container(
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
    );
  }
}
