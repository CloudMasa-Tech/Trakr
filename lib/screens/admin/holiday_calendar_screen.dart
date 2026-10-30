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

  const _HolidayItem({
    required this.date,
    required this.name,
    required this.category,
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
              Row(
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
                    ],
                  ),
                );
              },
            ),
        ],
      ),
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
