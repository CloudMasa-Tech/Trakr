import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../models/leave_request.dart';
import '../../models/permission_request.dart';
import '../../services/leave_service.dart';
import '../../services/permission_service.dart';

class ManagerRequestsScreen extends StatefulWidget {
  const ManagerRequestsScreen({super.key});

  @override
  State<ManagerRequestsScreen> createState() => _ManagerRequestsScreenState();
}

class _ManagerRequestsScreenState extends State<ManagerRequestsScreen> {
  final LeaveService _leaveService = LeaveService();
  final PermissionService _permissionService = PermissionService();

  int _selectedTab = 0; // 0 for Leaves, 1 for Permissions

  // Custom Colors following white-label theme / glassmorphic dashboard rules
  static const Color _bg = Color(0xFF0F172A);
  static const Color _cardColor = Color(0xFF1E293B);
  static const Color _borderColor = Color(0xFF334155);
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF10B981);
  static const Color _dangerColor = Color(0xFFEF4444);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: _bg,
        width: double.infinity,
        height: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Manager Requests',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Review self-applied leave and permission requests submitted by managers.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),

              // Segmented Tab bar
              _buildSegmentedControl(),
              const SizedBox(height: 24),

              // Content Area
              _selectedTab == 0
                  ? _buildLeaveRequestsList()
                  : _buildPermissionRequestsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabButton(
              0, 'Leave Requests', Icons.assignment_turned_in_rounded),
          _buildTabButton(
              1, 'Permission Requests', Icons.verified_user_rounded),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16, color: isSelected ? _textPrimary : _textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? _textPrimary : _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveRequestsList() {
    return StreamBuilder<List<LeaveRequest>>(
      stream: _managerLeaveRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator(color: _primaryColor),
            ),
          );
        }
        final requests = snapshot.data ?? const <LeaveRequest>[];

        return Column(
          children: [
            _buildSummaryCards(
              total: requests.length,
              pending: _countStatus(requests.map((r) => r.status), 'pending'),
              approved: _countStatus(requests.map((r) => r.status), 'approved'),
              rejected: _countStatus(requests.map((r) => r.status), 'rejected'),
            ),
            const SizedBox(height: 16),
            if (requests.isEmpty)
              _buildEmptyState(
                'No manager leave requests found. New requests submitted to Admin will appear here.',
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return _buildLeaveCard(requests[index]);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionRequestsList() {
    return StreamBuilder<List<PermissionRequest>>(
      stream: _managerPermissionRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator(color: _primaryColor),
            ),
          );
        }
        final requests = snapshot.data ?? const <PermissionRequest>[];

        return Column(
          children: [
            _buildSummaryCards(
              total: requests.length,
              pending: _countStatus(requests.map((r) => r.status), 'pending'),
              approved: _countStatus(requests.map((r) => r.status), 'approved'),
              rejected: _countStatus(requests.map((r) => r.status), 'rejected'),
            ),
            const SizedBox(height: 16),
            if (requests.isEmpty)
              _buildEmptyState(
                'No manager permission requests found. New requests submitted to Admin will appear here.',
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return _buildPermissionCard(requests[index]);
                },
              ),
          ],
        );
      },
    );
  }

  Stream<List<LeaveRequest>> _managerLeaveRequestsStream() {
    return FirebaseContextProvider.current.firestore
        .collection('leave_requests')
        .snapshots()
        .asyncMap((snapshot) async {
      final managerIds = await _managerIdentitySet();
      final requests = <LeaveRequest>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final request = LeaveRequest.fromFirestore(data, doc.id);
          if (_isManagerRequestData(
            data: data,
            employeeId: request.employeeId ?? request.userId,
            managerName: request.managerName,
            managerIds: managerIds,
          )) {
            requests.add(request);
          }
        } catch (_) {}
      }
      requests.sort((a, b) {
        if (a.status == 'pending' && b.status != 'pending') return -1;
        if (a.status != 'pending' && b.status == 'pending') return 1;
        return b.startDate.compareTo(a.startDate);
      });
      return requests;
    });
  }

  Stream<List<PermissionRequest>> _managerPermissionRequestsStream() {
    return FirebaseContextProvider.current.firestore
        .collection('permission_requests')
        .snapshots()
        .asyncMap((snapshot) async {
      final managerIds = await _managerIdentitySet();
      final requests = <PermissionRequest>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final request = PermissionRequest.fromFirestore(doc);
          if (_isManagerRequestData(
            data: data,
            employeeId: request.employeeId,
            managerName: request.managerName,
            managerIds: managerIds,
          )) {
            requests.add(request);
          }
        } catch (_) {}
      }
      requests.sort((a, b) {
        if (a.status == 'pending' && b.status != 'pending') return -1;
        if (a.status != 'pending' && b.status == 'pending') return 1;
        return b.requestedAt.compareTo(a.requestedAt);
      });
      return requests;
    });
  }

  Future<Set<String>> _managerIdentitySet() async {
    final snap = await FirebaseContextProvider.current.firestore
        .collection('managers')
        .get();
    final ids = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      for (final value in [
        doc.id,
        data['employeeId'],
        data['email'],
        data['name'],
      ]) {
        final normalized = _normalizeIdentity(value?.toString() ?? '');
        if (normalized.isNotEmpty) ids.add(normalized);
      }
    }
    return ids;
  }

  bool _isManagerRequestData({
    required Map<String, dynamic> data,
    required String? employeeId,
    required String? managerName,
    required Set<String> managerIds,
  }) {
    final isManager = data['isManager'] == true;
    final assignedToAdmin = _normalizeIdentity(managerName ?? '') == 'admin';
    final requesterIsManager =
        managerIds.contains(_normalizeIdentity(employeeId ?? ''));
    return isManager || (assignedToAdmin && requesterIsManager);
  }

  String _normalizeIdentity(String value) => value.trim().toLowerCase();

  int _countStatus(Iterable<String> statuses, String expected) {
    return statuses
        .where((status) => status.toLowerCase() == expected.toLowerCase())
        .length;
  }

  Widget _buildSummaryCards({
    required int total,
    required int pending,
    required int approved,
    required int rejected,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 24) / 3;
        final isCompact = cardWidth < 180;

        final cards = [
          _RequestMetric(
              'Pending', pending, Icons.hourglass_top_rounded, _warningColor),
          _RequestMetric('Approved', approved,
              Icons.check_circle_outline_rounded, _successColor),
          _RequestMetric(
              'Rejected', rejected, Icons.cancel_outlined, _dangerColor),
        ];

        return Row(
          children: [
            Expanded(child: _buildMetricCard(cards[0], isCompact)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard(cards[1], isCompact)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard(cards[2], isCompact)),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(_RequestMetric metric, bool isCompact) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8.0 : 16.0,
        vertical: isCompact ? 12.0 : 18.0,
      ),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: isCompact ? 32 : 42,
            height: isCompact ? 32 : 42,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
            ),
            child: Icon(
              metric.icon,
              color: metric.color,
              size: isCompact ? 16 : 21,
            ),
          ),
          SizedBox(width: isCompact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  metric.value.toString(),
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: isCompact ? 16 : 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.label,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: isCompact ? 10 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.inbox_rounded, size: 48, color: _textSecondary),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveCard(LeaveRequest req) {
    final days = req.endDate.difference(req.startDate).inDays + 1;
    final dateStr =
        '${DateFormat('MMM dd, yyyy').format(req.startDate)} - ${DateFormat('MMM dd, yyyy').format(req.endDate)}';
    final isPending = req.status == 'pending';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _primaryColor.withValues(alpha: 0.2),
                backgroundImage:
                    req.userPhotoUrl != null && req.userPhotoUrl!.isNotEmpty
                        ? NetworkImage(req.userPhotoUrl!)
                        : null,
                child: req.userPhotoUrl == null || req.userPhotoUrl!.isEmpty
                    ? const Icon(Icons.person_rounded,
                        color: _textPrimary, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.userName,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Designation: ${req.department}',
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _buildStatusIndicator(req.status),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: _borderColor, height: 1),
          const SizedBox(height: 16),
          _buildInfoRow('Leave Type', req.type),
          const SizedBox(height: 8),
          _buildInfoRow('Date Range', dateStr),
          const SizedBox(height: 8),
          _buildInfoRow('Duration', '$days Day${days > 1 ? "s" : ""}'),
          const SizedBox(height: 8),
          _buildInfoRow('Reason', req.reason),
          if (req.managerResponseReason != null &&
              req.managerResponseReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Admin Response', req.managerResponseReason!),
          ] else if (req.rejectionReason != null &&
              req.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Rejection Reason', req.rejectionReason!),
          ],
          if (isPending) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _handleLeaveAction(req, false),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _dangerColor,
                    side: const BorderSide(color: _dangerColor),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _handleLeaveAction(req, true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _successColor,
                    foregroundColor: _textPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionCard(PermissionRequest req) {
    final dateStr =
        req.date != null ? DateFormat('MMM dd, yyyy').format(req.date!) : '-';
    final durationStr = (req.fromTime != null && req.toTime != null)
        ? '${DateFormat('hh:mm a').format(req.fromTime!)} - ${DateFormat('hh:mm a').format(req.toTime!)}'
        : '-';
    final isPending = req.status == 'pending';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _primaryColor.withValues(alpha: 0.2),
                child: const Icon(Icons.person_rounded,
                    color: _textPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.employeeName,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Designation: ${req.department}',
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _buildStatusIndicator(req.status),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: _borderColor, height: 1),
          const SizedBox(height: 16),
          _buildInfoRow('Permission Type', req.permissionType ?? 'General'),
          const SizedBox(height: 8),
          _buildInfoRow('Date', dateStr),
          const SizedBox(height: 8),
          _buildInfoRow('Duration', durationStr),
          const SizedBox(height: 8),
          _buildInfoRow('Reason', req.reason),
          if (req.managerResponse != null &&
              req.managerResponse!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Admin Response', req.managerResponse!),
          ] else if (req.rejectionReason != null &&
              req.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Rejection Reason', req.rejectionReason!),
          ],
          if (isPending) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _handlePermissionAction(req, false),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _dangerColor,
                    side: const BorderSide(color: _dangerColor),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _handlePermissionAction(req, true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _successColor,
                    foregroundColor: _textPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'approved':
        bg = _successColor.withValues(alpha: 0.15);
        fg = _successColor;
        break;
      case 'rejected':
        bg = _dangerColor.withValues(alpha: 0.15);
        fg = _dangerColor;
        break;
      default:
        bg = _warningColor.withValues(alpha: 0.15);
        fg = _warningColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: _textPrimary, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Future<void> _handleLeaveAction(LeaveRequest req, bool approve) async {
    final actionText = approve ? 'Approve' : 'Reject';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text('$actionText Leave Request',
            style: const TextStyle(color: _textPrimary)),
        content: Text(
          'Are you sure you want to ${actionText.toLowerCase()} this leave request?',
          style: const TextStyle(color: _textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? _successColor : _dangerColor,
              foregroundColor: _textPrimary,
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _leaveService.updateLeaveStatus(
        req.id,
        approve ? 'approved' : 'rejected',
        managerResponseReason:
            approve ? 'Approved by Admin' : 'Rejected by Admin',
        rejectionReason: approve ? null : 'Rejected by Admin',
        actingManagerName: 'Admin',
        enforceAssignedManager: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Leave request successfully $actionText' 'd.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating request: $e')),
      );
    }
  }

  Future<void> _handlePermissionAction(
      PermissionRequest req, bool approve) async {
    final actionText = approve ? 'Approve' : 'Reject';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text('$actionText Permission Request',
            style: const TextStyle(color: _textPrimary)),
        content: Text(
          'Are you sure you want to ${actionText.toLowerCase()} this permission request?',
          style: const TextStyle(color: _textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? _successColor : _dangerColor,
              foregroundColor: _textPrimary,
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (approve) {
        await _permissionService.approvePermissionRequest(
          requestId: req.id,
          managerName: 'Admin',
          response: 'Approved by Admin',
          isPaid: true,
        );
      } else {
        await _permissionService.rejectPermissionRequest(
          req.id,
          'Admin',
          'Rejected by Admin',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Permission request successfully $actionText' 'd.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating request: $e')),
      );
    }
  }
}

class _RequestMetric {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _RequestMetric(this.label, this.value, this.icon, this.color);
}
