import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../services/notification_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class NotificationsModule extends StatefulWidget {
  const NotificationsModule({super.key});

  @override
  State<NotificationsModule> createState() => _NotificationsModuleState();
}

class _NotificationsModuleState extends State<NotificationsModule> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _target = 'admin';
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('Title and message are required.', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final pushed = await NotificationService().sendBroadcastNotification(
        title: title,
        body: body,
        recipient: _target,
      );
      final payload = {
        'type': 'broadcast',
        'notificationFormat': 'dynamic',
        'title': title,
        'content': body,
        'notificationTitle': title,
        'notificationBody': body,
        'recipient': _target,
        'senderEmail': PlatformService.currentEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'allowFirestorePush': false,
      };
      await FirebaseContextProvider.current.firestore
          .collection('notifications')
          .add(payload);
      await PlatformService().recordAudit(
        category: 'platform',
        action: 'sent broadcast notification',
        targetType: 'notification',
        changes: {
          'target': _target,
          'title': title,
        },
      );
      if (!mounted) return;
      _titleController.clear();
      _bodyController.clear();
      _snack(pushed
          ? 'Broadcast sent (push + Firestore).'
          : 'Broadcast saved to Firestore. Push delivery failed.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not send: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kCoError : kCoSuccess,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
          child: const CoPageHeader(
            title: 'Notifications',
            subtitle:
                'Send platform-wide push notifications (Vercel pipeline) and review history.',
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _composer(),
                    const SizedBox(height: 24),
                    const Text(
                      'Sent broadcasts',
                      style: TextStyle(
                        color: kCoLabel,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _history(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compose broadcast',
            style: TextStyle(
              color: kCoLabel,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Broadcasts are stored in Firestore and appear in the '
            'notifications history.',
            style: TextStyle(color: kCoSubtle, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: kCoLabel),
            decoration: _inputDecoration('Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            style: const TextStyle(color: kCoLabel),
            maxLines: 4,
            decoration: _inputDecoration('Message'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Deliver to:',
                  style: TextStyle(color: kCoSubtle, fontSize: 13)),
              const SizedBox(width: 12),
              _targetChip('admin', 'All admins & company admins'),
              const SizedBox(width: 8),
              _targetChip('all', 'Everyone'),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: kCoAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kCoWhite),
                    )
                  : const Icon(Icons.send_rounded, size: 17),
              label: const Text('Send broadcast'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetChip(String value, String label) {
    final selected = _target == value;
    return InkWell(
      onTap: () => setState(() => _target = value),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? kCoAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? kCoAccent : kCoBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? kCoAccent : kCoSubtle,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kCoSubtle, fontSize: 13.5),
      filled: true,
      fillColor: AppThemeColors.darkSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: kCoBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: kCoBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: kCoAccent.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _history() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseContextProvider.current.firestore
          .collection('notifications')
          .where('type', isEqualTo: 'broadcast')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const CoInlineLoading(label: 'Could not load history.');
        }
        if (!snapshot.hasData) {
          return const CoInlineLoading(label: 'Loading…');
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kCoBorder),
            ),
            child: const Center(
              child: Text(
                'No broadcasts sent yet.',
                style: TextStyle(color: kCoSubtle),
              ),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kCoBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < docs.length; i++) ...[
                _historyTile(docs[i].data()),
                if (i != docs.length - 1)
                  const Divider(color: kCoBorder, height: 1),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _historyTile(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? 'Untitled';
    final body = data['content']?.toString() ?? '';
    final target = data['recipient'] == 'all' ? 'Everyone' : 'Admins';
    final t = (data['timestamp'] as Timestamp?)?.toDate();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kCoAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child:
                const Icon(Icons.campaign_outlined, color: kCoAccent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: kCoLabel,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeLabel(t),
                      style: const TextStyle(color: kCoSubtle, fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
                ),
                const SizedBox(height: 5),
                Text(
                  'Delivered to: $target',
                  style: const TextStyle(
                    color: kCoSubtle,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime? t) {
    if (t == null) return '';
    return DateFormat('dd MMM, HH:mm').format(t.toLocal());
  }
}
