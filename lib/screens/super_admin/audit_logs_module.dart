import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/platform_models.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/platform_export.dart';
import 'portal_widgets.dart';

class AuditLogsModule extends StatefulWidget {
  const AuditLogsModule({super.key});

  @override
  State<AuditLogsModule> createState() => _AuditLogsModuleState();
}

class _AuditLogsModuleState extends State<AuditLogsModule> {
  final _platform = PlatformService();
  final _searchController = TextEditingController();
  String _category = 'all';
  String _search = '';
  String? _exporting;

  final _categories = [
    ('all', 'All'),
    ('company', 'Companies'),
    ('user', 'Users'),
    ('subscription', 'Subscriptions'),
    ('billing', 'Billing'),
    ('security', 'Security'),
    ('announcement', 'Announcements'),
    ('support', 'Support'),
    ('platform', 'Platform'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AuditEvent> _filter(List<AuditEvent> all) {
    final query = _search.trim().toLowerCase();
    return all.where((e) {
      if (_category != 'all' && e.category != _category) return false;
      if (query.isEmpty) return true;
      final haystack =
          '${e.action} ${e.actorEmail} ${e.actorRole} ${e.targetName} ${e.targetType} ${e.detail}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _export() async {
    if (_exporting != null) return;
    setState(() => _exporting = 'pdf');
    try {
      final snap = await _platform.fetchAuditLogsAll();
      final rows = snap
          .map((e) => [
                e.timestamp,
                e.category,
                e.action,
                e.actorEmail,
                e.actorRole ?? '',
                e.targetType ?? '',
                e.targetName ?? '',
                e.detail,
              ])
          .toList();
      await PlatformExport.toCsv(
        name: 'audit_logs_${DateFormat('yyyyMMdd').format(DateTime.now())}',
        headers: const [
          'Time',
          'Category',
          'Action',
          'Actor',
          'Role',
          'Target type',
          'Target',
          'Detail',
        ],
        rows: rows,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audit log exported to CSV.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
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
            title: 'Audit Logs',
            subtitle:
                'Immutable trail of every platform and company administration action.',
            actions: [
              OutlinedButton.icon(
                onPressed: _exporting != null ? null : _export,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kCoAccent,
                  side: const BorderSide(color: kCoBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
                icon: _exporting != null
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kCoAccent),
                      )
                    : const Icon(Icons.download_rounded, size: 17),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
          child: Row(
            children: [
              Expanded(
                child: CoSearchField(
                  controller: _searchController,
                  hint: 'Search actor, action, or target…',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 10),
              CoFilterMenu(
                label: 'Filter',
                options: _categories.map((c) => c.$2).toList(),
                value: _categories.firstWhere((c) => c.$1 == _category).$2,
                onChanged: (v) {
                  final match = _categories.where((c) => c.$2 == v);
                  if (match.isNotEmpty) {
                    setState(() => _category = match.first.$1);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<AuditEvent>>(
            stream: _platform.streamAuditLogs(limit: 300),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const CoInlineLoading(
                    label: 'Could not load audit log.');
              }
              if (!snapshot.hasData) {
                return const CoInlineLoading(label: 'Loading audit log…');
              }
              final events = _filter(snapshot.data!);
              if (events.isEmpty) {
                return const CoInlineLoading(label: 'No matching entries.');
              }
              final isDesktop = MediaQuery.of(context).size.width >= 1024;
              if (isDesktop) return _desktopTable(events);
              return _mobileList(events);
            },
          ),
        ),
      ],
    );
  }

  Widget _desktopTable(List<AuditEvent> events) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kCoBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _headerRow(),
                  const Divider(color: kCoBorder, height: 1),
                  for (final e in events) ...[
                    _row(e),
                    if (e != events.last)
                      const Divider(color: kCoBorder, height: 1),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow() {
    final widths = <String, double>{
      'Time': 150,
      'Category': 110,
      'Action': 150,
      'Actor': 190,
      'Target': 190,
      'Detail': 380,
    };
    return _RowLayout(
      children: [
        for (final entry in widths.entries)
          SizedBox(
            width: entry.value,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                entry.key,
                style: const TextStyle(
                  color: kCoSubtle,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(AuditEvent e) {
    final widths = <double>[150, 110, 150, 190, 190, 380];
    return _RowLayout(
      children: [
        for (var i = 0; i < widths.length; i++)
          SizedBox(
            width: widths[i],
            child: _cell(i, e),
          ),
      ],
    );
  }

  Widget _cell(int i, AuditEvent e) {
    switch (i) {
      case 0:
        return Text(
          _timeLabel(e.timestamp),
          style: const TextStyle(color: kCoSubtle, fontSize: 12),
        );
      case 1:
        return _categoryBadge(e.category);
      case 2:
        return Text(
          e.action,
          style: const TextStyle(
              color: kCoLabel, fontSize: 12.5, fontWeight: FontWeight.w600),
        );
      case 3:
        return Text(
          e.actorEmail,
          style: const TextStyle(color: kCoLabel, fontSize: 12),
        );
      case 4:
        return Text(
          e.targetType == null
              ? '—'
              : '${e.targetType}${e.targetName == null ? '' : ': ${e.targetName}'}',
          style: const TextStyle(color: kCoSubtle, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        );
      default:
        return Text(
          e.detail,
          style: const TextStyle(color: kCoSubtle, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _categoryBadge(String category) {
    Color color;
    switch (category) {
      case 'company':
        color = kCoBlue500;
        break;
      case 'user':
        color = kCoTeal500;
        break;
      case 'subscription':
        color = kCoPurple500;
        break;
      case 'billing':
        color = kCoOrange500;
        break;
      case 'security':
        color = kCoRed500;
        break;
      case 'announcement':
        color = kCoPink500;
        break;
      default:
        color = kCoAccent;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          category[0].toUpperCase() + category.substring(1),
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _mobileList(List<AuditEvent> events) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final e = events[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kCoBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _categoryBadge(e.category),
                  const Spacer(),
                  Text(
                    _timeLabel(e.timestamp),
                    style: const TextStyle(color: kCoSubtle, fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                e.action,
                style: const TextStyle(
                    color: kCoLabel, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${e.actorEmail}'
                '${e.targetType == null ? '' : ' · ${e.targetType}${e.targetName == null ? '' : ': ${e.targetName}'}'}',
                style: const TextStyle(color: kCoSubtle, fontSize: 12),
              ),
              if (e.detail.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  e.detail,
                  style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _timeLabel(DateTime t) {
    return DateFormat('dd MMM, HH:mm').format(t.toLocal());
  }
}

class _RowLayout extends StatelessWidget {
  const _RowLayout({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final c in children) ...[c, const SizedBox(width: 8)],
          ],
        ),
      ),
    );
  }
}
