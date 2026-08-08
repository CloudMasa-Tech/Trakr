import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme_colors.dart';

class _Holiday {
  final DateTime date;
  final String name;
  final String category; // 'Government', 'Festival'

  const _Holiday(this.date, this.name, this.category);
}

class HolidayCalendarWidget extends StatelessWidget {
  final DateTime? visibleMonth;
  final DateTime? selectedDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  static final List<_Holiday> _holidays = [
    // National & Government
    _Holiday(DateTime(2026, 1, 1), 'New Year', 'Government'),
    _Holiday(DateTime(2026, 1, 26), 'Republic Day', 'Government'),
    _Holiday(DateTime(2026, 5, 1), 'May Day', 'Government'),
    _Holiday(DateTime(2026, 8, 15), 'Independence Day', 'Government'),
    _Holiday(DateTime(2026, 10, 2), 'Gandhi Jayanti', 'Government'),
    _Holiday(DateTime(2026, 11, 24), 'Guru Nanak Jayanti', 'Government'),

    // Festival
    _Holiday(DateTime(2026, 1, 14), 'Pongal', 'Festival'),
    _Holiday(DateTime(2026, 3, 4), 'Holi', 'Festival'),
    _Holiday(DateTime(2026, 3, 26), 'Ram Navami', 'Festival'),
    _Holiday(DateTime(2026, 4, 14), 'Tamil New Year', 'Festival'),
    _Holiday(DateTime(2026, 9, 4), 'Janmashtami', 'Festival'),
    _Holiday(DateTime(2026, 10, 20), 'Dussehra', 'Festival'),
    _Holiday(DateTime(2026, 11, 8), 'Diwali', 'Festival'),

    _Holiday(DateTime(2026, 3, 21), 'Eid-ul-Fitr', 'Festival'),
    _Holiday(DateTime(2026, 5, 27), 'Eid-ul-Zuha', 'Festival'),
    _Holiday(DateTime(2026, 6, 26), 'Muharram', 'Festival'),
    _Holiday(DateTime(2026, 8, 26), 'Milad-un-Nabi', 'Festival'),

    _Holiday(DateTime(2026, 4, 3), 'Good Friday', 'Festival'),
    _Holiday(DateTime(2026, 4, 5), 'Easter', 'Festival'),
    _Holiday(DateTime(2026, 12, 25), 'Christmas', 'Festival'),
  ];

  const HolidayCalendarWidget({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final requestedMonth = visibleMonth ?? DateTime.now();
    final monthStart = DateTime(requestedMonth.year, requestedMonth.month);
    final firstGridDay =
        monthStart.subtract(Duration(days: monthStart.weekday % 7));
    final monthLabel = DateFormat('MMMM yyyy').format(monthStart);
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final upcomingLimit = _holidays.map((h) {
      var hDate = DateTime(now.year, h.date.month, h.date.day);
      if (hDate.isBefore(todayOnly)) {
        hDate = DateTime(now.year + 1, h.date.month, h.date.day);
      }
      return _Holiday(hDate, h.name, h.category);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date))
      ..take(5);

    final upcomingLimitTake5 = upcomingLimit.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                color: colors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Holiday Calendar',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CalendarNavButton(
                icon: Icons.chevron_left_rounded,
                onPressed: onPreviousMonth,
              ),
              Text(
                monthLabel,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _CalendarNavButton(
                icon: Icons.chevron_right_rounded,
                onPressed: onNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, index) {
              final date = firstGridDay.add(Duration(days: index));
              final inMonth = date.month == monthStart.month;
              final isSelected = _isSameDay(date, selectedDate);
              final holiday = _holidayFor(date);
              return _CalendarDayCell(
                date: date,
                inMonth: inMonth,
                isSelected: isSelected,
                isHoliday: holiday != null,
                isFestival: holiday?.category == 'Festival',
                holidayColor: _getHolidayColor(colors, holiday),
                onTap: () => onDateSelected(date),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _CalendarLegendDot(
                color: colors.primary,
                label: 'Selected Date',
              ),
              _CalendarLegendDot(
                color: colors.success,
                label: 'Present',
              ),
              _CalendarLegendDot(
                color: colors.warning,
                label: 'Late',
              ),
              _CalendarLegendDot(
                color: colors.error,
                label: 'Absent',
              ),
              _CalendarLegendDot(
                color: colors.focus,
                label: 'Government',
              ),
              _CalendarLegendDot(
                color: colors.secondary,
                label: 'Festival',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upcoming Holidays',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (upcomingLimitTake5.isEmpty)
                  Text(
                    'No upcoming holidays scheduled',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                else
                  ...upcomingLimitTake5.map(
                    (holiday) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _HolidayRow(holiday: holiday),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime? b) {
    return b != null &&
        a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  static _Holiday? _holidayFor(DateTime date) {
    for (final holiday in _holidays) {
      if (date.month == holiday.date.month && date.day == holiday.date.day) {
        return _Holiday(
          DateTime(date.year, date.month, date.day),
          holiday.name,
          holiday.category,
        );
      }
    }
    return null;
  }

  static Color? _getHolidayColor(AppColors colors, _Holiday? holiday) {
    if (holiday == null) return null;
    switch (holiday.category) {
      case 'Government':
        return colors.focus;
      case 'Festival':
        return colors.secondary;
      default:
        return colors.focus;
    }
  }
}

class _CalendarNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CalendarNavButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: colors.iconSecondary, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }
}

class _CalendarWeekday extends StatelessWidget {
  final String label;

  const _CalendarWeekday(this.label);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime date;
  final bool inMonth;
  final bool isSelected;
  final bool isHoliday;
  final bool isFestival;
  final Color? holidayColor;
  final VoidCallback onTap;

  const _CalendarDayCell({
    required this.date,
    required this.inMonth,
    required this.isSelected,
    required this.isHoliday,
    required this.isFestival,
    this.holidayColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final background = isSelected
        ? colors.primary
        : isHoliday
            ? holidayColor ?? colors.focus
            : Colors.transparent;

    final textColor = isSelected
        ? colors.onPrimary
        : isFestival
            ? colors.onSecondary
            : isHoliday
                ? colors.focus
                : inMonth
                    ? colors.textPrimary
                    : colors.textMuted.withValues(alpha: 0.55);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            '${date.day}',
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight:
                  isSelected || isHoliday ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _CalendarLegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HolidayRow extends StatelessWidget {
  final _Holiday holiday;

  const _HolidayRow({required this.holiday});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final holidayOnly =
        DateTime(holiday.date.year, holiday.date.month, holiday.date.day);
    final isExpired = holidayOnly.isBefore(todayOnly);

    final color = HolidayCalendarWidget._getHolidayColor(colors, holiday) ??
        colors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '${holiday.date.day}',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(holiday.date),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holiday.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  holiday.category,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isExpired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                'Expired',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
