import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme_colors.dart';

class FirestoreNotificationBanner extends StatefulWidget {
  final Iterable<String> identities;
  final Duration visibleDuration;

  const FirestoreNotificationBanner({
    super.key,
    required this.identities,
    this.visibleDuration = const Duration(seconds: 5),
  });

  @override
  State<FirestoreNotificationBanner> createState() =>
      _FirestoreNotificationBannerState();
}

class _FirestoreNotificationBannerState
    extends State<FirestoreNotificationBanner> {
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _subscriptions = [];
  OverlayEntry? _entry;
  Timer? _hideTimer;
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant FirestoreNotificationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = _normalized(oldWidget.identities).join('|');
    final newIds = _normalized(widget.identities).join('|');
    if (oldIds != newIds) {
      _clearSubscriptions();
      _primed = false;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _entry?.remove();
    _clearSubscriptions();
    super.dispose();
  }

  void _subscribe() {
    final ids = _normalized(widget.identities);
    if (ids.isEmpty) return;

    for (var i = 0; i < ids.length; i += 10) {
      final end = (i + 10).clamp(0, ids.length);
      _subscriptions.add(
        FirebaseContextProvider.current.firestore
            .collection('notifications')
            .where('recipient', whereIn: ids.sublist(i, end))
            .snapshots()
            .listen(_handleSnapshot),
      );
    }
  }

  List<String> _normalized(Iterable<String> values) {
    final ids = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) ids.add(trimmed);
    }
    return ids.toList();
  }

  void _clearSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _handleSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!_primed) {
      _primed = true;
      return;
    }

    final added = snapshot.docChanges
        .where((change) => change.type == DocumentChangeType.added)
        .map((change) => change.doc)
        .toList();
    if (added.isEmpty || !mounted) return;

    added.sort((a, b) {
      final at = _timestampFrom(a.data() ?? const <String, dynamic>{});
      final bt = _timestampFrom(b.data() ?? const <String, dynamic>{});
      return bt.compareTo(at);
    });
    final data = added.first.data();
    if (data != null) _show(data);
  }

  DateTime _timestampFrom(Map<String, dynamic> data) {
    final timestamp = data['timestamp'];
    if (timestamp is Timestamp) return timestamp.toDate();
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();
    return DateTime.now();
  }

  void _show(Map<String, dynamic> data) {
    final title = NotificationService.cleanNotificationText(
      (data['title'] ?? data['type'] ?? 'New notification').toString(),
    );
    final content = NotificationService.cleanNotificationText(
      (data['content'] ?? data['message'] ?? '').toString(),
    );

    _hideTimer?.cancel();
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (context) {
        final width = MediaQuery.sizeOf(context).width;
        return Positioned(
          top: MediaQuery.paddingOf(context).top + 14,
          left: width < 620 ? 12 : null,
          right: 12,
          child: Align(
            alignment: Alignment.topRight,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Builder(builder: (context) {
                  final colors = AppColors.of(context);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border),
                      boxShadow: [
                        BoxShadow(
                          color: colors.overlay,
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          color: colors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (content.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _hide,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              Icons.close_rounded,
                              color: colors.iconSecondary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_entry!);
    _hideTimer = Timer(widget.visibleDuration, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
