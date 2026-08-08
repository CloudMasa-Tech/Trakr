import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/responsive.dart';

// Fixed-brand palette for the weekend/holiday screen (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _whPrimary = Color(0xFF0F766E);
const Color _whTintBlack = Color(0x05000000);
const Color _whTintRed = Color(0xFFFFD9D9);
const Color _whBlue = Color(0xFF3B82F6);
const Color _whGreen = Color(0xFF16A34A);
const Color _whRed = Color(0xFFEF4444);
const Color _whGrey = Color(0xFFD1D5DB);
const Color _whTintBlue = Color(0xFFBFDBFE);
const Color _whSuccess = Color(0xFF00C896);
const Color _whRedBright = Color(0xFFFF3D4F);
const Color _whChipDarkGreen = Color(0xFF0D2E27);
const Color _whChipDarkMaroon = Color(0xFF321B25);
const Color _whChipGreenBorder = Color(0xFF1E6B56);
const Color _whChipMaroonBorder = Color(0xFF743040);
const Color _whRed600 = Color(0xFFE53935);
const Color _whWhite = Color(0xFFFFFFFF);

class WeekendHolidayScreen extends StatefulWidget {
  const WeekendHolidayScreen({super.key});

  @override
  State<WeekendHolidayScreen> createState() => _WeekendHolidayScreenState();
}

class _WeekendHolidayScreenState extends State<WeekendHolidayScreen> {
  final _db = FirebaseContextProvider.current.firestore;
  final _holidayDatesCtrl = TextEditingController();
  bool _sundayWorking = false;
  bool _isLoading = true;
  bool _isSaving = false;
  DateTime _visibleMonth = DateTime.now();
  DateTime? _selectedDate;
  List<_HolidayEvent> _holidayEvents = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final doc = await _db.collection('geo_config').doc('default').get();
    if (doc.exists) {
      final data = doc.data()!;
      final holidayDates = _parseHolidayDates(data['holidayDates']);
      final holidayEvents = _parseHolidayEvents(data['holidayEvents']);
      final mergedEvents = _mergeHolidaySources(
        holidayDates: holidayDates,
        holidayEvents: holidayEvents,
      );

      setState(() {
        _sundayWorking = data['sundayWorking'] as bool? ?? false;
        _holidayEvents = mergedEvents;
        _holidayDatesCtrl.text =
            mergedEvents.map((event) => event.dateKey).join(', ');
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  Set<String> _parseHolidayDates(Object? data) {
    if (data is List) {
      return data
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    if (data is String) {
      return data
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    return {};
  }

  List<_HolidayEvent> _parseHolidayEvents(Object? data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .map(_HolidayEvent.fromMap)
          .toList();
    }
    return [];
  }

  List<_HolidayEvent> _mergeHolidaySources({
    required Set<String> holidayDates,
    required List<_HolidayEvent> holidayEvents,
  }) {
    final byDate = <String, _HolidayEvent>{
      for (final event in holidayEvents) event.dateKey: event,
    };

    for (final dateString in holidayDates) {
      if (byDate.containsKey(dateString)) continue;
      final date = DateTime.tryParse(dateString);
      if (date == null) continue;
      byDate[dateString] = _HolidayEvent(
        date: DateTime(date.year, date.month, date.day),
        title: 'Holiday',
        category: _HolidayEvent.categoryOther,
        reason: 'Marked by admin.',
      );
    }

    final merged = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return merged;
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final manualHolidayDates = _parseHolidayDates(_holidayDatesCtrl.text);
      final allEventDates = {
        ...manualHolidayDates,
        ..._holidayEvents.map((event) => event.dateKey),
      }.toList()
        ..sort();
      final eventsToSave = _mergeHolidaySources(
        holidayDates: allEventDates.toSet(),
        holidayEvents: _holidayEvents,
      );

      await _db.collection('geo_config').doc('default').set({
        'saturdayWorking': true,
        'sundayWorking': _sundayWorking,
        'holidayDates': allEventDates,
        'holidayEvents': eventsToSave.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _holidayEvents = eventsToSave;
        _holidayDatesCtrl.text = allEventDates.join(', ');
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Settings saved successfully.'),
          backgroundColor: _whSuccess,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving settings: ${e.toString()}'),
          backgroundColor: _whRed600,
        ));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);
  }

  void _showAddEventDialog() {
    final dateController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(_selectedDate ?? DateTime.now()),
    );
    final titleController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var selectedCategory = _HolidayEvent.categoryGovernment;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            InputDecoration decoration(String label, {String? hint}) {
              return InputDecoration(
                labelText: label,
                hintText: hint,
                filled: true,
                fillColor: AppThemeColors.darkCanvas,
                labelStyle: const TextStyle(color: AppThemeColors.darkMuted),
                hintStyle: const TextStyle(color: AppThemeColors.darkMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppThemeColors.darkBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppThemeColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _whPrimary, width: 1.4),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: AppThemeColors.darkSurface,
              title: const Text(
                'Add Holiday Event',
                style: TextStyle(color: AppThemeColors.darkText),
              ),
              content: SizedBox(
                width: 360,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: dateController,
                          readOnly: true,
                          style:
                              const TextStyle(color: AppThemeColors.darkText),
                          decoration:
                              decoration('Date', hint: 'YYYY-MM-DD').copyWith(
                            suffixIcon: const Icon(
                              Icons.calendar_today_outlined,
                              color: AppThemeColors.darkMuted,
                            ),
                          ),
                          onTap: () async {
                            final initialDate =
                                DateTime.tryParse(dateController.text.trim()) ??
                                    _selectedDate ??
                                    DateTime.now();
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: initialDate,
                              firstDate: DateTime(DateTime.now().year - 3),
                              lastDate: DateTime(DateTime.now().year + 5),
                            );
                            if (picked == null) return;
                            dateController.text =
                                DateFormat('yyyy-MM-dd').format(picked);
                          },
                          validator: (value) {
                            if (DateTime.tryParse(value?.trim() ?? '') ==
                                null) {
                              return 'Choose a valid date.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: titleController,
                          style:
                              const TextStyle(color: AppThemeColors.darkText),
                          textCapitalization: TextCapitalization.words,
                          decoration: decoration('Event name'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Event name is required.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          dropdownColor: AppThemeColors.darkSurface,
                          style:
                              const TextStyle(color: AppThemeColors.darkText),
                          iconEnabledColor: AppThemeColors.darkMuted,
                          items: _HolidayEvent.categories
                              .map((category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(
                                      category,
                                      style: const TextStyle(
                                          color: AppThemeColors.darkText),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedCategory = value);
                          },
                          decoration: decoration('Category'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: reasonController,
                          style:
                              const TextStyle(color: AppThemeColors.darkText),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: decoration('Reason'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) {
                      return;
                    }
                    final parsedDate =
                        DateTime.parse(dateController.text.trim());
                    final normalizedDate = DateTime(
                      parsedDate.year,
                      parsedDate.month,
                      parsedDate.day,
                    );
                    final titleText = titleController.text.trim();
                    final reasonText = reasonController.text.trim();

                    setState(() {
                      _selectedDate = normalizedDate;
                      _visibleMonth =
                          DateTime(normalizedDate.year, normalizedDate.month);
                      _holidayEvents.removeWhere(
                          (event) => event.dateKey == _dateKey(normalizedDate));
                      _holidayEvents.add(_HolidayEvent(
                        date: normalizedDate,
                        title: titleText,
                        category: selectedCategory,
                        reason: reasonText.isEmpty
                            ? 'Marked by admin.'
                            : reasonText,
                      ));
                    });
                    Navigator.of(dialogContext).pop();
                    await _saveConfig();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  _HolidayEvent? _eventFor(DateTime date) {
    for (final event in _holidayEvents) {
      if (event.isSameDate(date)) return event;
    }
    return null;
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case _HolidayEvent.categoryGovernment:
        return _whTintRed; // Government Holiday (Light Pink)
      default:
        return _whGrey; // Grey fallback
    }
  }

  @override
  void dispose() {
    _holidayDatesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.isMobile(context);
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month);
    final firstGridDay =
        monthStart.subtract(Duration(days: monthStart.weekday % 7));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekend & Holiday Calendar',
                        style: TextStyle(
                          color: AppThemeColors.darkText,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Manage weekend workdays, holiday events and public calendar details that drive staff and manager alerts.',
                        style: TextStyle(
                          color: AppThemeColors.darkMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isMobile) ...[
                        _buildConfigCard(),
                        const SizedBox(height: 20),
                        _buildAddEventCard(),
                        const SizedBox(height: 20),
                        _buildCalendarCard(firstGridDay, monthStart),
                        const SizedBox(height: 20),
                        _buildUpcomingCard(),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildConfigCard(),
                                  const SizedBox(height: 12),
                                  _buildAddEventCard(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildCalendarCard(firstGridDay, monthStart),
                                  const SizedBox(height: 12),
                                  _buildUpcomingCard(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _whTintBlack,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppThemeColors.darkCanvas,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.settings_outlined,
                    color: _whPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Weekend & Holiday Settings',
                style: TextStyle(
                  color: AppThemeColors.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildToggleRow(
            title: 'Saturday is working day',
            subtitle:
                'Saturday is always treated as a workday. Add a Saturday date below only when admin declares it a holiday.',
            value: true,
            onChanged: null,
          ),
          const SizedBox(height: 20),
          _buildToggleRow(
            title: 'Sunday is working day',
            subtitle: 'Enable when Sunday should be treated as a workday.',
            value: _sundayWorking,
            onChanged: (v) => setState(() => _sundayWorking = v),
          ),
          const SizedBox(height: 12),
          const Text(
            'Holiday Dates (YYYY-MM-DD)',
            style: TextStyle(
                color: AppThemeColors.darkMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _holidayDatesCtrl,
            maxLines: 2,
            style: const TextStyle(color: AppThemeColors.darkText),
            decoration: InputDecoration(
              hintText: '2026-01-01, 2026-04-14, 2026-05-01, 2026-12-25',
              hintStyle: const TextStyle(
                  color: AppThemeColors.darkMuted, fontSize: 14),
              filled: true,
              fillColor: AppThemeColors.darkCanvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppThemeColors.darkBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppThemeColors.darkBorder),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add multiple dates separated by comma.',
            style: TextStyle(color: AppThemeColors.darkMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveConfig,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: _isSaving
                  ? const Text('Saving...')
                  : const Text('Save Calendar Settings'),
              style: FilledButton.styleFrom(
                backgroundColor: _whPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.edit_calendar_outlined,
              color: _whBlue, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppThemeColors.darkText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: _whPrimary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAddEventCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _whTintBlack,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppThemeColors.darkCanvas,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, color: _whPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Add Holiday Event',
                style: TextStyle(
                  color: AppThemeColors.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Create a new holiday event with category and reason.',
            style: TextStyle(color: AppThemeColors.darkMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showAddEventDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('+ Add Event'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _whPrimary,
                side: const BorderSide(color: _whTintBlue),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard(DateTime firstGridDay, DateTime monthStart) {
    final monthLabel = DateFormat('MMMM yyyy').format(monthStart);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _whTintBlack,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  color: _whBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                monthLabel,
                style: const TextStyle(
                  color: AppThemeColors.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _buildNavButton(Icons.chevron_left_rounded, () {
                setState(() {
                  _visibleMonth =
                      DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                });
              }),
              const SizedBox(width: 8),
              _buildNavButton(Icons.chevron_right_rounded, () {
                setState(() {
                  _visibleMonth =
                      DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                });
              }),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _CalendarWeekday('Su'),
              _CalendarWeekday('Mo'),
              _CalendarWeekday('Tu'),
              _CalendarWeekday('We'),
              _CalendarWeekday('Th'),
              _CalendarWeekday('Fr'),
              _CalendarWeekday('Sa'),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final date = firstGridDay.add(Duration(days: index));
              final inMonth = date.month == monthStart.month;
              final event = _eventFor(date);
              final isSelected = _selectedDate != null &&
                  _selectedDate!.year == date.year &&
                  _selectedDate!.month == date.month &&
                  _selectedDate!.day == date.day;

              final holidayColor =
                  event != null ? _colorForCategory(event.category) : null;
              final background = isSelected
                  ? _whPrimary // _ManagerDashTheme.primary
                  : event != null
                      ? holidayColor
                      : Colors.transparent;

              final bool isReligious =
                  event != null && holidayColor != _whTintRed;

              final textColor = isSelected || isReligious
                  ? _whWhite
                  : event != null
                      ? _whRedBright // _ManagerDashTheme.danger
                      : inMonth
                          ? AppThemeColors.darkText // _ManagerDashTheme.text
                          : AppThemeColors.darkMuted.withValues(
                              alpha: 0.55); // _ManagerDashTheme.muted

              return Material(
                color: background,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => _selectDate(date),
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: isSelected || event != null
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _LegendChip(color: _whTintRed, label: 'Government Holiday'),
              _LegendChip(color: _whGrey, label: 'Weekend Off'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon,
          color: AppThemeColors.darkMuted), // _ManagerDashTheme.muted
      style: IconButton.styleFrom(
        backgroundColor:
            AppThemeColors.darkCanvas, // _ManagerDashTheme.surfaceSoft
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _buildUpcomingCard() {
    final todayOnly =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    final upcomingHolidays = _holidayEvents
        .where((event) => !event.date.isBefore(todayOnly))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final expiredHolidays = _holidayEvents
        .where((event) => event.date.isBefore(todayOnly))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _whTintBlack,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: _whBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Upcoming Holidays',
                style: TextStyle(
                  color: AppThemeColors.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (upcomingHolidays.isNotEmpty) ...[
            const Text(
              'Upcoming',
              style: TextStyle(
                color: _whGreen,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: _whGreen.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            ...upcomingHolidays
                .map((e) => _buildHolidayRow(e, isUpcoming: true)),
            const SizedBox(height: 20),
          ],
          if (expiredHolidays.isNotEmpty) ...[
            const Text(
              'Expired',
              style: TextStyle(
                color: _whRed,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: _whRed.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            ...expiredHolidays
                .map((e) => _buildHolidayRow(e, isUpcoming: false)),
            const SizedBox(height: 20),
          ],
          if (upcomingHolidays.isEmpty && expiredHolidays.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No holidays configured.',
                style: TextStyle(color: AppThemeColors.darkMuted, fontSize: 14),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.list, size: 18),
              label: const Text('View All Holidays'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _whPrimary,
                side: const BorderSide(color: _whTintBlue),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayRow(_HolidayEvent event, {required bool isUpcoming}) {
    final themeColor = isUpcoming ? _whGreen : _whRed;
    final bgColor = isUpcoming ? _whChipDarkGreen : _whChipDarkMaroon;
    final borderColor = isUpcoming ? _whChipGreenBorder : _whChipMaroonBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(
              isUpcoming
                  ? Icons.event_available_outlined
                  : Icons.event_busy_outlined,
              color: themeColor,
              size: 20,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    color: themeColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.category,
                  style: TextStyle(
                    color: themeColor.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd').format(event.date),
                  style: TextStyle(
                    color: themeColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                Text(
                  DateFormat('MMM yyyy').format(event.date),
                  style: TextStyle(
                    color: themeColor,
                    fontSize: 10,
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
}

class _CalendarWeekday extends StatelessWidget {
  final String label;
  const _CalendarWeekday(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppThemeColors.darkText, // _ManagerDashTheme.text
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppThemeColors.darkMuted, // _ManagerDashTheme.muted
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HolidayEvent {
  final DateTime date;
  final String title;
  final String category;
  final String reason;

  static const String categoryGovernment = 'Government';
  static const String categoryOther = 'Other';

  static const List<String> categories = [
    categoryGovernment,
    categoryOther,
  ];

  _HolidayEvent({
    required this.date,
    required this.title,
    required this.category,
    required this.reason,
  });

  String get dateKey {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool isSameDate(DateTime other) {
    return date.year == other.year &&
        date.month == other.month &&
        date.day == other.day;
  }

  Map<String, dynamic> toMap() {
    return {
      'date': dateKey,
      'title': title,
      'category': category,
      'reason': reason,
    };
  }

  static _HolidayEvent fromMap(Map<String, dynamic> data) {
    final dateValue = data['date'];
    DateTime? resolved;
    if (dateValue is Timestamp) {
      resolved = dateValue.toDate();
    } else if (dateValue is String) {
      resolved = DateTime.tryParse(dateValue);
    }
    return _HolidayEvent(
      date: resolved ?? DateTime.now(),
      title: data['title'] as String? ?? 'Holiday',
      category: data['category'] as String? ?? categoryOther,
      reason: data['reason'] as String? ?? 'Marked by admin.',
    );
  }
}
