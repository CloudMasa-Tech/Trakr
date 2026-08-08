import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/platform_models.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class SecurityModule extends StatefulWidget {
  const SecurityModule({super.key});

  @override
  State<SecurityModule> createState() => _SecurityModuleState();
}

class _SecurityModuleState extends State<SecurityModule> {
  final _platform = PlatformService();
  String _typeFilter = 'all';
  bool _clearing = false;

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Clear security events?',
            style: TextStyle(color: kCoLabel, fontSize: 16)),
        content: const Text(
          'This permanently deletes the recorded security events. The '
          'aggregated counters will also be reset.',
          style: TextStyle(color: kCoSubtle, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kCoError),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      final snap = await FirebaseContextProvider.current.firestore
          .collection('security_events')
          .limit(500)
          .get();
      final batch = FirebaseContextProvider.current.firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await _platform.bumpStats({
        'failedLogins': -snap.docs.length,
        'lockedAccounts': 0,
        'suspiciousLogins': 0,
        'passwordResets': 0,
      });
      await _platform.recordAudit(
        category: 'security',
        action: 'cleared security events',
        changes: {'count': snap.docs.length},
      );
      if (!mounted) return;
      _snack('Security events cleared.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not clear events: $e', error: true);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _delete(String id) async {
    await _platform.deleteSecurityEvent(id);
    await _platform.bumpStats({'failedLogins': -1});
    await _platform.recordAudit(
      category: 'security',
      action: 'dismissed security event',
      targetType: 'security_event',
      targetId: id,
    );
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
          child: CoPageHeader(
            title: 'Security Center',
            subtitle:
                'Monitor failed logins, locked accounts, and suspicious activity.',
            actions: [
              OutlinedButton.icon(
                onPressed: _clearing ? null : _clearAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kCoDanger,
                  side: const BorderSide(color: kCoBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
                icon: _clearing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kCoDanger),
                      )
                    : const Icon(Icons.delete_sweep_outlined, size: 17),
                label: const Text('Clear events'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
          child: _kpiRow(),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('all', 'All events'),
              _filterChip('failed_login', 'Failed logins'),
              _filterChip('locked_account', 'Locked accounts'),
              _filterChip('suspicious_login', 'Suspicious logins'),
              _filterChip('password_reset', 'Password resets'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<SecurityEvent>>(
            stream: _platform.streamSecurityEvents(limit: 300),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const CoInlineLoading(
                    label: 'Could not load security events.');
              }
              if (!snapshot.hasData) {
                return const CoInlineLoading(label: 'Loading events…');
              }
              var events = snapshot.data!;
              if (_typeFilter != 'all') {
                events = events.where((e) => e.type == _typeFilter).toList();
              }
              if (events.isEmpty) {
                return const CoInlineLoading(
                    label: 'No security events match the current filter.');
              }
              return ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 40 : 16,
                  vertical: 4,
                ),
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final e = events[index];
                  return _eventTile(e);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _kpiRow() {
    return StreamBuilder<PlatformStats>(
      stream: _platform.streamStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        return LayoutBuilder(
          builder: (context, constraints) {
            const cardCount = 4;
            const spacing = 12.0;
            final cardWidth = constraints.maxWidth >= 900
                ? (constraints.maxWidth - (cardCount - 1) * spacing) / cardCount
                : constraints.maxWidth;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _kpi(
                  width: cardWidth,
                  label: 'Failed logins',
                  value: stats?.failedLogins ?? 0,
                  icon: Icons.login_rounded,
                  color: kCoRed500,
                ),
                _kpi(
                  width: cardWidth,
                  label: 'Locked accounts',
                  value: stats?.lockedAccounts ?? 0,
                  icon: Icons.lock_outline_rounded,
                  color: kCoOrange500,
                ),
                _kpi(
                  width: cardWidth,
                  label: 'Suspicious logins',
                  value: stats?.suspiciousLogins ?? 0,
                  icon: Icons.warning_amber_rounded,
                  color: kCoPurple500,
                ),
                _kpi(
                  width: cardWidth,
                  label: 'Password resets',
                  value: stats?.passwordResets ?? 0,
                  icon: Icons.password_rounded,
                  color: kCoTeal500,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _kpi({
    required double width,
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCoBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: kCoLabel,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: kCoSubtle, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _typeFilter == value;
    return InkWell(
      onTap: () => setState(() => _typeFilter = value),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? kCoAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? kCoAccent : kCoBorder),
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

  Widget _eventTile(SecurityEvent e) {
    final (color, icon, label) = switch (e.type) {
      'locked_account' => (
          kCoOrange500,
          Icons.lock_outline_rounded,
          'Account locked'
        ),
      'suspicious_login' => (
          kCoPurple500,
          Icons.warning_amber_rounded,
          'Suspicious login'
        ),
      'password_reset' => (
          kCoTeal500,
          Icons.password_rounded,
          'Password reset'
        ),
      _ => (kCoRed500, Icons.login_rounded, 'Failed login'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCoBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: kCoLabel,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.email,
                        style: const TextStyle(color: kCoSubtle, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (e.detail != null && e.detail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    e.detail!,
                    style: const TextStyle(color: kCoSubtle, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd MMM yyyy, HH:mm:ss')
                      .format(e.timestamp.toLocal()),
                  style: const TextStyle(
                    color: kCoSubtle,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(e.id),
            tooltip: 'Dismiss event',
            icon: const Icon(Icons.close_rounded, color: kCoSubtle, size: 18),
          ),
        ],
      ),
    );
  }
}
