import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../models/attendance_model.dart';
import '../../models/notification_model.dart';
import '../../services/attendance_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme_colors.dart';

// Fixed-brand palette for the notifications history screen (force-dark).
// Intentional exception: file-scoped brand constants.
const Color _nhPrimary = Color(0xFF0F766E);
const Color _nhShadow = Color(0x1A6B7897);
const Color _nhPink = Color(0xFFFF5B72);
const Color _nhWhite = Color(0xFFFFFFFF);
const Color _nhGreen = Color(0xFF4CAF50);
const Color _nhRed = Color(0xFFF44336);

class NotificationsHistoryScreen extends StatelessWidget {
  const NotificationsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return SafeArea(
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 700 ? 14 : 24,
            22,
            MediaQuery.sizeOf(context).width < 700 ? 14 : 24,
            110,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile) ...[
                const Text(
                  'Admin Notifications',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppThemeColors.darkText,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Track automated alerts received by admin.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.darkMuted,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const NotificationsTable(),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationsTable extends StatefulWidget {
  const NotificationsTable({super.key});

  @override
  State<NotificationsTable> createState() => _NotificationsTableState();
}

class _NotificationsTableState extends State<NotificationsTable> {
  final _searchCtrl = TextEditingController();
  final _horizontalScrollCtrl = ScrollController();
  final _listScrollCtrl = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    _listScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _nhShadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(26),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    cursorColor: _nhPrimary,
                    style: const TextStyle(
                      color: AppThemeColors.darkText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by name...',
                      hintStyle:
                          const TextStyle(color: AppThemeColors.darkMuted),
                      prefixIcon:
                          const Icon(Icons.search, size: 18, color: _nhPrimary),
                      filled: true,
                      fillColor: AppThemeColors.darkCanvas,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppThemeColors.darkBorder),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 700) {
                return _buildNotificationsList();
              }

              final tableWidth =
                  constraints.maxWidth < 760 ? 760.0 : constraints.maxWidth;
              return Scrollbar(
                controller: _horizontalScrollCtrl,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 26, vertical: 18),
                          decoration: const BoxDecoration(
                            color: AppThemeColors.darkCanvas,
                            border: Border.symmetric(
                              horizontal:
                                  BorderSide(color: AppThemeColors.darkBorder),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Expanded(
                                  flex: 3,
                                  child: Text('USER', style: _hdrStyle)),
                              Expanded(
                                  flex: 1,
                                  child: Text('TYPE', style: _hdrStyle)),
                              Expanded(
                                  flex: 4,
                                  child:
                                      Text('NOTIFICATION', style: _hdrStyle)),
                              Expanded(
                                  flex: 2,
                                  child: Text('DATE', style: _hdrStyle)),
                              Expanded(
                                  flex: 1,
                                  child: Text('STATUS', style: _hdrStyle)),
                            ],
                          ),
                        ),
                        _buildNotificationsList(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseContextProvider.current.firestore
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        var models = docs
            .map((d) => NotificationModel.fromFirestore(d))
            .where((m) => m.recipient.trim().toLowerCase() == 'admin')
            .toList();

        if (_query.isNotEmpty) {
          models = models
              .where((m) =>
                  (m.employeeName.isNotEmpty ? m.employeeName : m.content)
                      .toLowerCase()
                      .contains(_query.toLowerCase()))
              .toList();
        }

        if (models.isEmpty) {
          return const SizedBox(
            height: 150,
            child: Center(child: Text('No notifications found.')),
          );
        }

        final availableHeight = MediaQuery.sizeOf(context).height - 330;
        final maxListHeight = availableHeight < 260 ? 260.0 : availableHeight;
        final listHeight = (models.length * 96.0).clamp(150.0, maxListHeight);

        return SizedBox(
          height: listHeight,
          child: Scrollbar(
            controller: _listScrollCtrl,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _listScrollCtrl,
              itemCount: models.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppThemeColors.darkBorder),
              itemBuilder: (ctx, i) => _NotificationRow(model: models[i]),
            ),
          ),
        );
      },
    );
  }

  static const _hdrStyle = TextStyle(
    color: AppThemeColors.darkMuted,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
}

class _NotificationRow extends StatefulWidget {
  final NotificationModel model;
  const _NotificationRow({required this.model});

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  final _attendanceService = AttendanceService();
  bool _approving = false;

  NotificationModel get model => widget.model;

  Future<void> _approveCheckoutRequest() async {
    if (_approving || model.requestId.isEmpty) return;
    setState(() => _approving = true);
    try {
      final collection = model.requestCollection.isNotEmpty
          ? model.requestCollection
          : 'checkout_requests';
      final doc = await FirebaseContextProvider.current.firestore
          .collection(collection)
          .doc(model.requestId)
          .get();
      if (!doc.exists) throw Exception('Checkout request not found.');

      final request = CheckoutRequest.fromFirestore(doc);
      if (request.status != 'pending') {
        throw Exception('Checkout request is already ${request.status}.');
      }

      await _attendanceService.approveCheckoutRequest(
        request,
        adminNote: 'Approved from notification',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checkout request approved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not approve checkout: $e'),
          backgroundColor: _nhPink,
        ),
      );
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = NotificationService.cleanNotificationText(model.title);
    final content = NotificationService.cleanNotificationText(model.content);
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.employeeName.isNotEmpty ? model.employeeName : '-',
                    style: const TextStyle(
                      color: AppThemeColors.darkText,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMM dd, yyyy').format(model.timestamp),
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _typeBadge(model.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppThemeColors.darkText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        content,
                        style: const TextStyle(
                          color: AppThemeColors.darkMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: model.actionType == 'checkout_request' &&
                      model.requestId.isNotEmpty
                  ? FilledButton(
                      onPressed: _approving ? null : _approveCheckoutRequest,
                      style: FilledButton.styleFrom(
                        backgroundColor: _nhPrimary,
                        foregroundColor: _nhWhite,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        _approving ? '...' : 'Approve',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : _statusBadge(model.status),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(
                  model.employeeName.isNotEmpty ? model.employeeName : '-',
                  style: const TextStyle(
                      color: AppThemeColors.darkText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13))),
          Expanded(flex: 1, child: _typeBadge(model.type)),
          Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppThemeColors.darkText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(content,
                      style: const TextStyle(
                          color: AppThemeColors.darkMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              )),
          Expanded(
              flex: 2,
              child: Text(
                  DateFormat('MMM dd, yyyy HH:mm').format(model.timestamp),
                  style: const TextStyle(
                      color: AppThemeColors.darkMuted, fontSize: 12))),
          Expanded(
            flex: 1,
            child: model.actionType == 'checkout_request' &&
                    model.requestId.isNotEmpty
                ? FilledButton(
                    onPressed: _approving ? null : _approveCheckoutRequest,
                    style: FilledButton.styleFrom(
                      backgroundColor: _nhPrimary,
                      foregroundColor: _nhWhite,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      _approving ? '...' : 'Approve',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : _statusBadge(model.status),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _nhPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(type,
          style: const TextStyle(
              color: _nhPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statusBadge(String status) {
    final isSent = status.toLowerCase() == 'sent';
    return Row(
      children: [
        Icon(isSent ? Icons.check_circle : Icons.error,
            color: isSent ? _nhGreen : _nhRed, size: 14),
        const SizedBox(width: 4),
        Text(status,
            style: TextStyle(
                color: isSent ? _nhGreen : _nhRed,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
