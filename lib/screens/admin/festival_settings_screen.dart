// lib/screens/admin/festival_settings_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/festival_settings.dart';
import '../../theme/app_theme_colors.dart';

/// Tenant-side editor for `app_config/festival_settings`.
///
/// Reads/Writes the document scoped to the ACTIVE tenant Firebase project via
/// `FirebaseContextProvider.current.firestore` (same pattern as the other admin
/// config screens). The `sendFestivalWishes` Cloud Function consumes exactly
/// this shape.
class FestivalSettingsScreen extends StatefulWidget {
  const FestivalSettingsScreen({super.key});

  @override
  State<FestivalSettingsScreen> createState() => _FestivalSettingsScreenState();
}

class _FestivalSettingsScreenState extends State<FestivalSettingsScreen> {
  final _db = FirebaseContextProvider.current.firestore;

  bool _enabled = false;
  int _advanceDays = 0;
  List<FestivalEntry> _festivals = [];
  String _title = '';
  String _body = '';
  String _emailSubject = '';
  String _emailBody = '';

  bool _isLoading = true;
  bool _isSaving = false;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _emailSubjectCtrl = TextEditingController();
  final _emailBodyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() => _title = _titleCtrl.text);
    _bodyCtrl.addListener(() => _body = _bodyCtrl.text);
    _emailSubjectCtrl.addListener(() => _emailSubject = _emailSubjectCtrl.text);
    _emailBodyCtrl.addListener(() => _emailBody = _emailBodyCtrl.text);
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _emailSubjectCtrl.dispose();
    _emailBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await _db
          .collection('app_config')
          .doc('festival_settings')
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final settings = FestivalSettings.fromMap(doc.data() ?? {});
        setState(() {
          _enabled = settings.enabled;
          _advanceDays = settings.advanceDays;
          _festivals = List.of(settings.festivals);
          _title = settings.title ?? '';
          _body = settings.body ?? '';
          _emailSubject = settings.emailSubject ?? '';
          _emailBody = settings.emailBody ?? '';
          _titleCtrl.text = _title;
          _bodyCtrl.text = _body;
          _emailSubjectCtrl.text = _emailSubject;
          _emailBodyCtrl.text = _emailBody;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to load festival settings: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final settings = FestivalSettings(
        enabled: _enabled,
        advanceDays: _advanceDays,
        festivals: _festivals.where((f) => f.name.isNotEmpty).toList(),
        title: _title,
        body: _body,
        emailSubject: _emailSubject,
        emailBody: _emailBody,
      );
      await _db.collection('app_config').doc('festival_settings').set({
        ...settings.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) _showSnack('Festival settings saved!');
    } catch (e) {
      if (mounted) _showSnack('Error saving: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addFestival() {
    setState(() {
      _festivals.add(FestivalEntry(
        id: 'festival_${DateTime.now().millisecondsSinceEpoch}',
        name: '',
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        enabled: true,
      ));
    });
  }

  void _updateFestival(int index, FestivalEntry updated) {
    setState(() => _festivals[index] = updated);
  }

  void _removeFestival(int index) {
    setState(() => _festivals.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(color: colors.focus),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Festival Settings',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Automated festival wishes via push, in-app & email',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_isSaving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          _buildMasterSwitch(colors),
          const SizedBox(height: 16),
          _buildAdvanceDays(colors),
          const SizedBox(height: 16),
          _buildFestivalList(colors),
          const SizedBox(height: 16),
          _buildMessageTemplates(colors),
        ],
      ),
    );
  }

  Widget _card(AppColors colors, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }

  Widget _buildMasterSwitch(AppColors colors) {
    return _card(
      colors,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: const Text('Enable festival wishes',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'When enabled, the daily job sends wishes to every employee for '
          'the festivals below.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        value: _enabled,
        activeTrackColor: colors.focus,
        onChanged: (v) => setState(() => _enabled = v),
      ),
    );
  }

  Widget _buildAdvanceDays(AppColors colors) {
    return _card(
      colors,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Advance reminder (days before festival)',
                style: TextStyle(
                    color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    color: colors.textSecondary, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _advanceDays,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (var d = 0; d <= 14; d++)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            d == 0 ? 'On the festival day' : '$d day${d == 1 ? '' : 's'} before',
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _advanceDays = v ?? 0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFestivalList(AppColors colors) {
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Text('Festivals',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addFestival,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          if (_festivals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No festivals added yet. Tap "Add" to create one.',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          for (var i = 0; i < _festivals.length; i++)
            _FestivalTile(
              entry: _festivals[i],
              onChanged: (v) => _updateFestival(i, v),
              onRemoved: () => _removeFestival(i),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageTemplates(AppColors colors) {
    return _card(
      colors,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Message templates',
                style: TextStyle(
                    color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Use {festival}, {companyName} and {employeeName} placeholders. '
              'Leave blank to use defaults.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _label(colors, 'Push / in-app title'),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            _label(colors, 'Push / in-app body'),
            TextField(
              controller: _bodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _label(colors, 'Email subject'),
            TextField(
              controller: _emailSubjectCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            _label(colors, 'Email body (HTML)'),
            TextField(
              controller: _emailBodyCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AppColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _FestivalTile extends StatefulWidget {
  final FestivalEntry entry;
  final ValueChanged<FestivalEntry> onChanged;
  final VoidCallback onRemoved;

  const _FestivalTile({
    required this.entry,
    required this.onChanged,
    required this.onRemoved,
  });

  @override
  State<_FestivalTile> createState() => _FestivalTileState();
}

class _FestivalTileState extends State<_FestivalTile> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _nameCtrl.addListener(() {
      if (_nameCtrl.text != widget.entry.name) {
        widget.onChanged(widget.entry.copyWith(name: _nameCtrl.text));
      }
    });
  }

  @override
  void didUpdateWidget(_FestivalTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.name != widget.entry.name &&
        _nameCtrl.text != widget.entry.name) {
      _nameCtrl.text = widget.entry.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final entry = widget.entry;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Switch(
            value: entry.enabled,
            activeTrackColor: colors.focus,
            onChanged: (v) => widget.onChanged(entry.copyWith(enabled: v)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'Festival name',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Pick date',
            icon: Icon(Icons.event_outlined, color: colors.textSecondary),
            onPressed: () => _pickDate(context),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.delete_outline, color: colors.error),
            onPressed: widget.onRemoved,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final parsed = DateTime.tryParse(widget.entry.date);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      widget.onChanged(
        widget.entry.copyWith(date: DateFormat('yyyy-MM-dd').format(picked)),
      );
    }
  }
}
