import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../widgets/dashboard/holiday_calendar_widget.dart';

class _HolidayItem {
  final DateTime date;
  final String name;
  final String category; // 'Government', 'Festival', 'Office Leave'
  final bool isCustom;

  const _HolidayItem({
    required this.date,
    required this.name,
    required this.category,
    this.isCustom = false,
  });

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class HolidayCalendarScreen extends StatefulWidget {
  const HolidayCalendarScreen({super.key});

  @override
  State<HolidayCalendarScreen> createState() => _HolidayCalendarScreenState();
}

class _HolidayCalendarScreenState extends State<HolidayCalendarScreen> {
  DateTime _calendarMonth = DateTime.now();
  DateTime? _selectedDate;
  String _selectedCategory = 'All'; // 'All', 'Upcoming', 'Government', 'Festival'

  static final List<_HolidayItem> _standardHolidays = [
    // National & Government
    _HolidayItem(date: DateTime(2026, 1, 1), name: 'New Year', category: 'Government'),
    _HolidayItem(date: DateTime(2026, 1, 26), name: 'Republic Day', category: 'Government'),
    _HolidayItem(date: DateTime(2026, 5, 1), name: 'May Day', category: 'Government'),
    _HolidayItem(date: DateTime(2026, 8, 15), name: 'Independence Day', category: 'Government'),
    _HolidayItem(date: DateTime(2026, 10, 2), name: 'Gandhi Jayanti', category: 'Government'),
    _HolidayItem(date: DateTime(2026, 11, 24), name: 'Guru Nanak Jayanti', category: 'Government'),

    // Festival
    _HolidayItem(date: DateTime(2026, 1, 14), name: 'Pongal', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 3, 4), name: 'Holi', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 3, 21), name: 'Eid-ul-Fitr', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 3, 26), name: 'Ram Navami', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 4, 3), name: 'Good Friday', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 4, 5), name: 'Easter', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 4, 14), name: 'Tamil New Year', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 5, 27), name: 'Eid-ul-Zuha', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 6, 26), name: 'Muharram', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 8, 26), name: 'Milad-un-Nabi', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 9, 4), name: 'Janmashtami', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 10, 20), name: 'Dussehra', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 11, 8), name: 'Diwali', category: 'Festival'),
    _HolidayItem(date: DateTime(2026, 12, 25), name: 'Christmas', category: 'Festival'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;
                  final headerLeft = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Color(0xFF0EA5E9),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Holiday Calendar',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppThemeColors.darkText,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Official company holidays, festival celebrations, and office leave schedule',
                            style: TextStyle(
                              color: AppThemeColors.darkMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );

                  final addBtn = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _showAddHolidayDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Add Holiday / Festival',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        headerLeft,
                        const SizedBox(height: 14),
                        addBtn,
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      headerLeft,
                      addBtn,
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Real-time config listener for custom added office holidays
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseContextProvider.current.firestore
                    .collection('geo_config')
                    .doc('default')
                    .snapshots(),
                builder: (context, snapshot) {
                  final allHolidays = List<_HolidayItem>.from(_standardHolidays);
                  final existingKeys = allHolidays.map((h) => h.dateKey).toSet();

                  if (snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    final rawDates = data['holidayDates'];
                    if (rawDates is List) {
                      for (var d in rawDates) {
                        final str = d?.toString().trim();
                        if (str != null && str.isNotEmpty && !existingKeys.contains(str)) {
                          final parsed = DateTime.tryParse(str);
                          if (parsed != null) {
                            allHolidays.add(_HolidayItem(
                              date: parsed,
                              name: 'Office Leave',
                              category: 'Office Leave',
                              isCustom: true,
                            ));
                            existingKeys.add(str);
                          }
                        }
                      }
                    }

                    final rawEvents = data['holidayEvents'];
                    if (rawEvents is List) {
                      for (var ev in rawEvents) {
                        if (ev is Map) {
                          final dk = ev['dateKey']?.toString().trim();
                          final name = ev['title']?.toString().trim() ?? 'Holiday';
                          final cat = ev['category']?.toString().trim() ?? 'Office Leave';
                          if (dk != null && dk.isNotEmpty && !existingKeys.contains(dk)) {
                            final parsed = DateTime.tryParse(dk);
                            if (parsed != null) {
                              allHolidays.add(_HolidayItem(
                                date: parsed,
                                name: name,
                                category: cat,
                                isCustom: true,
                              ));
                              existingKeys.add(dk);
                            }
                          }
                        }
                      }
                    }
                  }

                  allHolidays.sort((a, b) => a.date.compareTo(b.date));

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 950;

                      final calendarWidget = HolidayCalendarWidget(
                        visibleMonth: _calendarMonth,
                        selectedDate: _selectedDate,
                        onPreviousMonth: () {
                          setState(() {
                            _calendarMonth = DateTime(
                                _calendarMonth.year, _calendarMonth.month - 1);
                          });
                        },
                        onNextMonth: () {
                          setState(() {
                            _calendarMonth = DateTime(
                                _calendarMonth.year, _calendarMonth.month + 1);
                          });
                        },
                        onDateSelected: (date) {
                          setState(() {
                            if (_selectedDate != null &&
                                _selectedDate!.year == date.year &&
                                _selectedDate!.month == date.month &&
                                _selectedDate!.day == date.day) {
                              _selectedDate = null;
                            } else {
                              _selectedDate = date;
                            }
                          });
                        },
                      );

                      final listWidget = _buildHolidayList(allHolidays);

                      if (isMobile) {
                        return Column(
                          children: [
                            calendarWidget,
                            const SizedBox(height: 24),
                            listWidget,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 380, child: calendarWidget),
                          const SizedBox(width: 24),
                          Expanded(child: listWidget),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHolidayList(List<_HolidayItem> allHolidays) {
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    var filtered = allHolidays;
    if (_selectedCategory == 'Upcoming') {
      filtered = allHolidays.where((h) => !h.date.isBefore(todayOnly)).toList();
    } else if (_selectedCategory != 'All') {
      filtered = allHolidays.where((h) => h.category == _selectedCategory).toList();
    }

    if (_selectedDate != null) {
      filtered = filtered.where((h) =>
          h.date.year == _selectedDate!.year &&
          h.date.month == _selectedDate!.month &&
          h.date.day == _selectedDate!.day).toList();
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Tabs
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildCategoryChip('All', allHolidays.length),
                    _buildCategoryChip(
                      'Upcoming',
                      allHolidays.where((h) => !h.date.isBefore(todayOnly)).length,
                    ),
                    _buildCategoryChip(
                      'Government',
                      allHolidays.where((h) => h.category == 'Government').length,
                    ),
                    _buildCategoryChip(
                      'Festival',
                      allHolidays.where((h) => h.category == 'Festival').length,
                    ),
                  ],
                ),
              ),
              if (_selectedDate != null)
                InkWell(
                  onTap: () => setState(() => _selectedDate = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('dd MMM').format(_selectedDate!),
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.close, size: 14, color: Color(0xFFEF4444)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppThemeColors.darkBorder),
          const SizedBox(height: 14),

          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _selectedDate != null
                      ? 'No holiday on ${DateFormat('dd MMMM yyyy').format(_selectedDate!)}'
                      : 'No holidays found for this category.',
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppThemeColors.darkBorder),
              itemBuilder: (context, index) {
                final item = filtered[index];
                final isUpcoming = !item.date.isBefore(todayOnly);
                final diffDays = item.date.difference(todayOnly).inDays;

                Color badgeColor;
                if (item.category == 'Government') {
                  badgeColor = const Color(0xFF0EA5E9);
                } else if (item.category == 'Festival') {
                  badgeColor = const Color(0xFFF59E0B);
                } else {
                  badgeColor = const Color(0xFF818CF8);
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      // Date Box
                      Container(
                        width: 58,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              item.date.day.toString().padLeft(2, '0'),
                              style: TextStyle(
                                color: badgeColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              DateFormat('MMM').format(item.date).toUpperCase(),
                              style: TextStyle(
                                color: badgeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Name & Day of Week
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                color: AppThemeColors.darkText,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('EEEE, yyyy').format(item.date),
                              style: const TextStyle(
                                color: AppThemeColors.darkMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Category Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.category,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Upcoming / Status Tag
                      if (isUpcoming)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            diffDays == 0
                                ? 'Today'
                                : diffDays == 1
                                    ? 'Tomorrow'
                                    : 'In $diffDays days',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        const Text(
                          'Passed',
                          style: TextStyle(
                            color: AppThemeColors.darkMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                      if (item.isCustom) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18, color: Color(0xFFEF4444)),
                          tooltip: 'Delete custom holiday',
                          onPressed: () => _deleteCustomHoliday(item),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomHoliday(_HolidayItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Holiday',
            style: TextStyle(
                color: AppThemeColors.darkText, fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to remove "${item.name}" on ${item.dateKey}?',
            style: const TextStyle(color: AppThemeColors.darkMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppThemeColors.darkMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final docRef = FirebaseContextProvider.current.firestore
          .collection('geo_config')
          .doc('default');
      final snap = await docRef.get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};

      final rawDates = List<dynamic>.from(data['holidayDates'] ?? []);
      rawDates.removeWhere((d) => d?.toString().trim() == item.dateKey);

      final rawEvents = List<dynamic>.from(data['holidayEvents'] ?? []);
      rawEvents.removeWhere((ev) {
        if (ev is Map) {
          final dk = ev['dateKey']?.toString().trim();
          return dk == item.dateKey;
        }
        return false;
      });

      await docRef.set({
        'holidayDates': rawDates,
        'holidayEvents': rawEvents,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Holiday "${item.name}" removed.'),
          backgroundColor: const Color(0xFF0EA5E9),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete holiday: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
  }

  Future<void> _showAddHolidayDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    DateTime pickedDate = _selectedDate ?? DateTime.now();
    String category = 'Festival';
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final dateKeyStr = DateFormat('yyyy-MM-dd').format(pickedDate);
            final displayDateStr =
                DateFormat('EEE, dd MMMM yyyy').format(pickedDate);

            return AlertDialog(
              backgroundColor: AppThemeColors.darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppThemeColors.darkBorder),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.celebration_rounded,
                        color: Color(0xFF0EA5E9), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Add Holiday / Festival',
                    style: TextStyle(
                      color: AppThemeColors.darkText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Holiday Name / Festival',
                        style: TextStyle(
                          color: AppThemeColors.darkText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(
                            color: AppThemeColors.darkText, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Diwali, Eid, Regional Holiday',
                          hintStyle: const TextStyle(
                              color: AppThemeColors.darkMuted, fontSize: 13),
                          filled: true,
                          fillColor: AppThemeColors.darkCanvas,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppThemeColors.darkBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppThemeColors.darkBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF0EA5E9), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Date',
                        style: TextStyle(
                          color: AppThemeColors.darkText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: pickedDate,
                            firstDate: DateTime(2025, 1, 1),
                            lastDate: DateTime(2030, 12, 31),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFF0EA5E9),
                                    onPrimary: Colors.white,
                                    surface: AppThemeColors.darkSurface,
                                    onSurface: AppThemeColors.darkText,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (selected != null) {
                            setDialogState(() => pickedDate = selected);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppThemeColors.darkCanvas,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppThemeColors.darkBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded,
                                  color: Color(0xFF0EA5E9), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '$displayDateStr ($dateKeyStr)',
                                  style: const TextStyle(
                                    color: AppThemeColors.darkText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: AppThemeColors.darkMuted),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Category',
                        style: TextStyle(
                          color: AppThemeColors.darkText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          'Festival',
                          'Government',
                          'Office Leave'
                        ].map((cat) {
                          final isCatSelected = category == cat;
                          return InkWell(
                            onTap: () => setDialogState(() => category = cat),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isCatSelected
                                    ? const Color(0xFF0EA5E9)
                                    : AppThemeColors.darkCanvas,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCatSelected
                                      ? const Color(0xFF0EA5E9)
                                      : AppThemeColors.darkBorder,
                                ),
                              ),
                              child: Text(
                                cat,
                                style: TextStyle(
                                  color: isCatSelected
                                      ? Colors.white
                                      : AppThemeColors.darkText,
                                  fontSize: 12,
                                  fontWeight: isCatSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '💡 When saved, this date will immediately be recognized company-wide as an official holiday. Any automatic absence records for this date will be purged.',
                        style: TextStyle(
                          color: AppThemeColors.darkMuted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppThemeColors.darkMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final name = titleCtrl.text.trim();
                          if (name.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a holiday title.'),
                                backgroundColor: Color(0xFFEF4444),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            final firestore =
                                FirebaseContextProvider.current.firestore;
                            final docRef = firestore
                                .collection('geo_config')
                                .doc('default');
                            final snap = await docRef.get();
                            final data = snap.data() ?? {};

                            final rawDates = List<String>.from(
                                data['holidayDates'] ?? []);
                            if (!rawDates.contains(dateKeyStr)) {
                              rawDates.add(dateKeyStr);
                              rawDates.sort();
                            }

                            final rawEvents = List<dynamic>.from(
                                data['holidayEvents'] ?? []);
                            // Remove existing event for this dateKey if any
                            rawEvents.removeWhere((ev) =>
                                ev is Map && ev['dateKey'] == dateKeyStr);
                            rawEvents.add({
                              'dateKey': dateKeyStr,
                              'title': name,
                              'category': category,
                              'date': Timestamp.fromDate(pickedDate),
                            });

                            await docRef.set({
                              'holidayDates': rawDates,
                              'holidayEvents': rawEvents,
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));

                            // Purge any errant missing_ or autoMarkedAbsent attendance docs for this dateKey
                            try {
                              final attSnap = await firestore
                                  .collection('attendance')
                                  .where('dateKey', isEqualTo: dateKeyStr)
                                  .get();
                              for (final doc in attSnap.docs) {
                                final d = doc.data();
                                if (doc.id.startsWith('missing_') ||
                                    d['autoMarkedAbsent'] == true) {
                                  await doc.reference.delete();
                                }
                              }
                            } catch (_) {}

                            if (ctx.mounted) Navigator.of(ctx).pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Holiday "$name" added successfully and synchronized.'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to save holiday: $e'),
                                backgroundColor: const Color(0xFFEF4444),
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add Holiday',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryChip(String label, int count) {
    final isSelected = _selectedCategory == label;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = label),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0EA5E9)
              : AppThemeColors.darkCanvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0EA5E9)
                : AppThemeColors.darkBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : AppThemeColors.darkText,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppThemeColors.darkBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppThemeColors.darkMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
