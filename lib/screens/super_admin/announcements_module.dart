import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/platform_models.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class AnnouncementsModule extends StatefulWidget {
  const AnnouncementsModule({super.key});

  @override
  State<AnnouncementsModule> createState() => _AnnouncementsModuleState();
}

class _AnnouncementsModuleState extends State<AnnouncementsModule> {
  final _platform = PlatformService();
  String _statusFilter = 'all';

  Future<void> _createAnnouncement() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AnnouncementDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _platform.createAnnouncement(
        title: result['title'] as String,
        body: result['body'] as String,
        status: result['status'] as String,
        audience: result['audience'] as String,
        publishAt: result['publishAt'] as DateTime?,
        expiresAt: result['expiresAt'] as DateTime?,
      );
      await _platform.recordAudit(
        category: 'announcement',
        action: 'created announcement',
        targetType: 'announcement',
        targetName: result['title'] as String,
        changes: {'status': result['status'] as String},
      );
      if (!mounted) return;
      _snack('Announcement created.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not create: $e', error: true);
    }
  }

  Future<void> _setStatus(AnnouncementModel a, String status) async {
    try {
      await _platform.updateAnnouncementStatus(a.id, status);
      await _platform.recordAudit(
        category: 'announcement',
        action: '$status announcement',
        targetType: 'announcement',
        targetName: a.title,
      );
      if (!mounted) return;
      _snack(
          'Announcement ${status == 'published' ? 'published' : 'set to draft'}.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update: $e', error: true);
    }
  }

  Future<void> _delete(AnnouncementModel a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete announcement?',
            style: TextStyle(color: kCoLabel, fontSize: 16)),
        content: Text(
          '"${a.title}" will be permanently removed.',
          style: const TextStyle(color: kCoSubtle, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kCoError),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _platform.deleteAnnouncement(a.id);
      await _platform.recordAudit(
        category: 'announcement',
        action: 'deleted announcement',
        targetType: 'announcement',
        targetName: a.title,
      );
      if (!mounted) return;
      _snack('Announcement deleted.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not delete: $e', error: true);
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
          child: CoPageHeader(
            title: 'Announcements',
            subtitle:
                'Publish platform-wide announcements with a draft-to-live lifecycle.',
            actions: [
              FilledButton.icon(
                onPressed: _createAnnouncement,
                style: FilledButton.styleFrom(
                  backgroundColor: kCoAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New announcement'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CoFilterMenu(
              label: 'Filter',
              options: const ['All statuses', 'Draft', 'Published', 'Archived'],
              value: _statusFilter == 'all'
                  ? 'All statuses'
                  : _statusFilter[0].toUpperCase() + _statusFilter.substring(1),
              onChanged: (v) => setState(() {
                _statusFilter = switch (v) {
                  'Draft' => 'draft',
                  'Published' => 'published',
                  'Archived' => 'archived',
                  _ => 'all',
                };
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<AnnouncementModel>>(
            stream: _platform.streamAnnouncements(limit: 200),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const CoInlineLoading(
                    label: 'Could not load announcements.');
              }
              if (!snapshot.hasData) {
                return const CoInlineLoading(label: 'Loading announcements…');
              }
              var items = snapshot.data!;
              if (_statusFilter != 'all') {
                items = items.where((a) => a.status == _statusFilter).toList();
              }
              if (items.isEmpty) {
                return const CoInlineLoading(
                    label: 'No announcements match the current filter.');
              }
              final isDesktop = MediaQuery.of(context).size.width >= 1024;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          _tile(items[i], isDesktop),
                          if (i != items.length - 1) const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(AnnouncementModel a, bool isDesktop) {
    final published = a.status == 'published';
    final (statusColor, statusLabel) = switch (a.status) {
      'published' => (kCoSuccess, 'Published'),
      'archived' => (kCoGrey500, 'Archived'),
      _ => (kCoOrange500, 'Draft'),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCoBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kCoAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.campaign_outlined, color: kCoAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.title,
                        style: const TextStyle(
                          color: kCoLabel,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  a.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _meta(Icons.groups_rounded, a.audience),
                    _meta(Icons.person_outline_rounded, a.createdBy),
                    _meta(
                      Icons.schedule_rounded,
                      DateFormat('dd MMM yyyy').format(a.createdAt.toLocal()),
                    ),
                    if (a.expiresAt != null)
                      _meta(
                        Icons.event_available_outlined,
                        'Expires ${DateFormat('dd MMM yyyy').format(a.expiresAt!.toLocal())}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 12),
            _actions(a, published),
          ],
        ],
      ),
    );
  }

  Widget _actions(AnnouncementModel a, bool published) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (a.status == 'draft')
          OutlinedButton.icon(
            onPressed: () => _setStatus(a, 'published'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kCoSuccess,
              side: const BorderSide(color: kCoBorder),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.publish_rounded, size: 15),
            label: const Text('Publish'),
          ),
        if (published)
          OutlinedButton.icon(
            onPressed: () => _setStatus(a, 'draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kCoSubtle,
              side: const BorderSide(color: kCoBorder),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.unpublished_outlined, size: 15),
            label: const Text('Unpublish'),
          ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: () => _delete(a),
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded,
              color: kCoDanger, size: 19),
        ),
      ],
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kCoSubtle, size: 13),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: kCoSubtle, fontSize: 11.5)),
      ],
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog();

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'all';
  String _status = 'published';
  DateTime? _publishAt;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
      ValueChanged<DateTime> onPicked, String title, String help) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) => Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: child!,
      ),
    );
    if (picked != null) {
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 9, minute: 0),
      );
      final combined = time == null
          ? picked
          : DateTime(
              picked.year, picked.month, picked.day, time.hour, time.minute);
      onPicked(combined);
    }
  }

  void _save() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and message are required.')),
      );
      return;
    }
    Navigator.pop(context, {
      'title': title,
      'body': body,
      'audience': _audience,
      'status': _status,
      'publishAt': _publishAt,
      'expiresAt': _expiresAt,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('New announcement',
          style: TextStyle(
              color: kCoLabel, fontSize: 17, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                style: const TextStyle(color: kCoLabel),
                decoration: _input('Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                style: const TextStyle(color: kCoLabel),
                maxLines: 4,
                decoration: _input('Message'),
              ),
              const SizedBox(height: 14),
              const Text('Audience',
                  style: TextStyle(color: kCoSubtle, fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _chip('all', 'Everyone'),
                  _chip('admins', 'Admins'),
                  _chip('staff', 'Staff only'),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Status',
                  style: TextStyle(color: kCoSubtle, fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _statusChip('published', 'Publish now'),
                  _statusChip('draft', 'Save as draft'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _dateButton(
                      label: _publishAt == null
                          ? 'Schedule publish'
                          : DateFormat('dd MMM, HH:mm').format(_publishAt!),
                      onTap: () => _pickDate((d) {
                        setState(() => _publishAt = d);
                        if (_status == 'draft') _status = 'published';
                      }, 'Publish date', 'When the announcement goes live'),
                      onClear: _publishAt == null
                          ? null
                          : () => setState(() => _publishAt = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _dateButton(
                      label: _expiresAt == null
                          ? 'Set expiry'
                          : 'Expires ${DateFormat('dd MMM').format(_expiresAt!)}',
                      onTap: () => _pickDate((d) {
                        setState(() => _expiresAt = d);
                      }, 'Expiry date', 'When the announcement is hidden'),
                      onClear: _expiresAt == null
                          ? null
                          : () => setState(() => _expiresAt = null),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: kCoAccent),
          child: const Text('Save announcement'),
        ),
      ],
    );
  }

  Widget _chip(String value, String label) {
    final selected = _audience == value;
    return InkWell(
      onTap: () => setState(() => _audience = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected ? kCoAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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

  Widget _statusChip(String value, String label) {
    final selected = _status == value;
    return InkWell(
      onTap: () => setState(() => _status = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? kCoSuccess.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kCoSuccess : kCoBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? kCoSuccess : kCoSubtle,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.darkSurface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: kCoBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              InkWell(
                onTap: onClear,
                child:
                    const Icon(Icons.close_rounded, color: kCoSubtle, size: 15),
              )
            else
              const Icon(Icons.calendar_today_outlined,
                  color: kCoSubtle, size: 14),
          ],
        ),
      ),
    );
  }

  InputDecoration _input(String hint) {
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
}
