import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme_colors.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/dashboard/live_qr_widget.dart';
import '../../widgets/dashboard/weekly_trend_chart.dart';
import '../../widgets/dashboard/stat_card.dart';

// Fixed-brand palette for the shared attendance dashboard. Intentional
// exception: file-scoped brand constants.
const Color _dashPrimary = Color(0xFF0F766E);
const Color _dashPrimarySoft = Color(0x100F766E);
const Color _dashGreen = Color(0xFF16B86A);
const Color _dashTintGreen = Color(0xFFDDF8E9);
const Color _dashAmber = Color(0xFFFFB400);
const Color _dashTintAmber = Color(0xFFFFF0C8);
const Color _dashOrange = Color(0xFFF97316);
const Color _dashPink = Color(0xFFE92E5A);
const Color _dashTintPink = Color(0xFFFFE3EB);
const Color _dashViolet = Color(0xFF7C3AED);
const Color _dashTintViolet = Color(0xFFF0E8FF);
const Color _dashTintBlue = Color(0xFFEAF1FF);

class AttendanceDashboardScreen extends StatefulWidget {
  const AttendanceDashboardScreen({super.key});

  @override
  State<AttendanceDashboardScreen> createState() =>
      _AttendanceDashboardScreenState();
}

class _AttendanceDashboardScreenState extends State<AttendanceDashboardScreen> {
  final _svc = AttendanceService();
  StreamSubscription? _sub;
  Timer? _overdueSyncTimer;

  int present = 0, absent = 0, late = 0;
  int totalStaff = 0, totalManagers = 0;
  StreamSubscription? _dirSub;

  @override
  void initState() {
    super.initState();
    unawaited(_svc.syncOverdueAttendanceRecords());
    _overdueSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_svc.syncOverdueAttendanceRecords()),
    );
    _sub = _svc.getTodayStatsStream().listen((s) {
      if (mounted) {
        setState(() {
          present = s['present'] ?? 0;
          absent = s['absent'] ?? 0;
          late = s['late'] ?? 0;
        });
      }
    }, onError: (Object e, StackTrace st) {
      debugPrint('AttendanceDashboard today stats stream error: $e\n$st');
    });

    _dirSub = _svc.getDirectoryStatsStream().listen((s) {
      if (mounted) {
        setState(() {
          totalStaff = s['totalStaff'] ?? 0;
          totalManagers = s['totalManagers'] ?? 0;
        });
      }
    }, onError: (Object e, StackTrace st) {
      debugPrint('AttendanceDashboard directory stats stream error: $e\n$st');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dirSub?.cancel();
    _overdueSyncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.isMobile(context);
    final horizontalPadding = isMobile ? 14.0 : 20.0;

    return AppBackground(
      forceDark: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile) ...[
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Dashboard',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppThemeColors.darkText,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Real-time overview of organization-wide attendance.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColors.darkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  StatCard(
                    icon: Icons.groups_2_outlined,
                    iconColor: _dashPrimary,
                    iconBg: _dashTintBlue,
                    count: totalStaff,
                    label: 'Total Staff',
                    trendLabel: 'Staff directory',
                    showTrendAsText: true,
                  ),
                  StatCard(
                    icon: Icons.manage_accounts_outlined,
                    iconColor: _dashViolet,
                    iconBg: _dashTintViolet,
                    count: totalManagers,
                    label: 'Managers',
                    trendLabel: 'Department leads',
                    showTrendAsText: true,
                  ),
                  StatCard(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: _dashGreen,
                    iconBg: _dashTintGreen,
                    count: present,
                    label: 'Present',
                    trendLabel: '',
                    showFooter: false,
                  ),
                  StatCard(
                    icon: Icons.cancel_outlined,
                    iconColor: _dashPink,
                    iconBg: _dashTintPink,
                    count: absent,
                    label: 'Absent',
                    trendLabel: '',
                    showFooter: false,
                  ),
                  StatCard(
                    icon: Icons.schedule_rounded,
                    iconColor: _dashAmber,
                    iconBg: _dashTintAmber,
                    count: late,
                    label: 'Late',
                    trendLabel: '',
                    showFooter: false,
                  ),
                ];

                final spacing = constraints.maxWidth >= 600 ? 16.0 : 6.0;
                final cardHeight = constraints.maxWidth >= 600 ? 150.0 : 104.0;

                return SizedBox(
                  height: cardHeight,
                  child: Row(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        Expanded(child: cards[i]),
                        if (i != cards.length - 1) SizedBox(width: spacing),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackPanels = constraints.maxWidth < 980;
                if (stackPanels) {
                  return Column(
                    children: [
                      MonthlyTrendChart(attendanceService: _svc),
                      const SizedBox(height: 16),
                      const LiveQrWidget(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: MonthlyTrendChart(attendanceService: _svc),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      flex: 2,
                      child: LiveQrWidget(),
                    ),
                  ],
                );
              },
            ),
            _AdminRecentAttendancePanel(attendanceService: _svc),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _AdminRecentAttendancePanel extends StatelessWidget {
  final AttendanceService attendanceService;

  const _AdminRecentAttendancePanel({required this.attendanceService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceModel>>(
      stream: attendanceService.getTodayAttendanceStreamAll(),
      builder: (context, snapshot) {
        final records = List<AttendanceModel>.from(
            snapshot.data ?? const <AttendanceModel>[])
          ..sort((a, b) {
            final aTime = a.checkOutTime ?? a.checkInTime ?? a.date;
            final bTime = b.checkOutTime ?? b.checkInTime ?? b.date;
            return bTime.compareTo(aTime);
          });

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppThemeColors.darkSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppThemeColors.darkBorder),
            boxShadow: const [
              BoxShadow(
                color: _dashPrimarySoft,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(color: _dashPrimary),
                  ),
                )
              else if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No attendance history found yet.',
                      style: TextStyle(color: AppThemeColors.darkMuted),
                    ),
                  ),
                )
              else
                _AdminRecentAttendanceFeed(records: records),
            ],
          ),
        );
      },
    );
  }
}

class _AdminRecentAttendanceFeed extends StatelessWidget {
  final List<AttendanceModel> records;

  const _AdminRecentAttendanceFeed({required this.records});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activities',
          style: TextStyle(
            color: AppThemeColors.darkText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ...records
            .take(6)
            .map((record) => _AdminAttendanceAlertRow(record: record)),
      ],
    );
  }
}

class _AdminAttendanceAlertRow extends StatelessWidget {
  final AttendanceModel record;

  const _AdminAttendanceAlertRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final isPermissionDelay = record.isPermissionReEntryDelayed;
    final isTempExit = record.isTemporaryExit;
    final isEarly = record.isEarlyCheckout;
    final color = isPermissionDelay
        ? _dashPink
        : isTempExit
            ? _dashOrange
            : isEarly
                ? _dashOrange
                : record.countsAsAbsent
                    ? _dashPink
                    : record.countsAsLate
                        ? _dashAmber
                        : _dashGreen;
    final icon = isPermissionDelay
        ? Icons.error_outline_rounded
        : isTempExit
            ? Icons.directions_walk_rounded
            : isEarly
                ? Icons.warning_amber_rounded
                : record.countsAsAbsent
                    ? Icons.cancel_outlined
                    : record.countsAsLate
                        ? Icons.schedule_rounded
                        : Icons.check_circle_outline_rounded;
    final statusText = record.hasPermissionActivity
        ? record.permissionActivityLabel
        : isEarly
            ? 'Early checkout'
            : _statusLabel(record);
    final time = record.isCheckedOut
        ? record.checkOutFormatted
        : record.checkInFormatted;
    final action = record.isCheckedOut ? 'checked out' : 'checked in';
    final detail = record.hasPermissionActivity
        ? record.permissionActivityDetail
        : '${record.department} | $action at $time';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppThemeColors.darkBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.employeeName.isEmpty
                      ? 'Staff / Manager'
                      : record.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppThemeColors.darkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(AttendanceModel record) {
    if (record.policyAction == 'half_day_leave') return 'Half Day';
    if (record.statusLabel == 'Leave') return 'Leave';
    if (record.countsAsAbsent || record.statusLabel == 'Absent') {
      return 'Absent';
    }
    if (record.countsAsLate) return 'Late';
    return 'Present';
  }
}
