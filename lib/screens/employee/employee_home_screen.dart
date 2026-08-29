import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dart:typed_data';
import 'package:provider/provider.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/attendance_model.dart';
import '../../models/leave_request.dart';
import '../../models/staff.dart';
import '../../providers/auth_session_provider.dart';
import '../../providers/white_label_provider.dart';
import '../../services/anniversary_greeting_service.dart';
import '../../services/attendance_service.dart';
import '../../services/leave_service.dart';
import '../../services/notification_service.dart';
import '../../services/permission_service.dart';
import '../../services/profile_photo_sync_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/profile_photo_picker.dart';
import '../../widgets/anniversary_greeting_dialog.dart';
import '../staff/staff_scan_qr_screen.dart';
import '../../widgets/dashboard/export_dropdown.dart';

class _ProfileDetailItem {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileDetailItem(this.icon, this.label, this.value);
}

class _StaffDashTheme {
//   static const page = AppThemeColors.backgroundDark;
  static const surface = AppThemeColors.darkSurface;
  static const soft = AppThemeColors.darkCanvas;
  static const tableHeader = AppThemeColors.darkCanvas;
  static const border = AppThemeColors.darkBorder;
  static const text = AppThemeColors.darkText;
  static const muted = AppThemeColors.darkMuted;
  static const primary = Color(0xFF0F766E);
  static const primaryLight = Color(0xFF123A4A);
  static const sidebarTop = Color(0xFF0F766E);
  static const sidebarBottom = Color(0xFF1E3A8A);
  static const warning = Color(0xFFFF8A12);
  static const danger = Color(0xFFFF3D4F);
  static const shadow = Color(0x126B7897);
}

class EmployeeHomeScreen extends StatefulWidget {
  final AppUserRole role;
  final Future<void> Function() onLogout;

  const EmployeeHomeScreen({
    super.key,
    required this.role,
    required this.onLogout,
  });

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final LeaveService _leaveService = LeaveService();
  final AnniversaryGreetingService _anniversaryGreetingService =
      AnniversaryGreetingService();

  int _selectedIndex = 0;
  List<AttendanceModel> _recentActivity = [];
  AttendanceModel? _todayRecord;
  Staff? _currentStaff;
  int _monthPresent = 0;
  int _monthAbsent = 0;
  int _monthLate = 0;
//   final int _monthWfh = 0;
  int _monthWorkingMinutes = 0;

  final TextEditingController _leaveReasonController = TextEditingController();
  final TextEditingController _permissionReasonController =
      TextEditingController();
  String _leaveType = '';
  DateTime _leaveStart = DateTime.now();
  DateTime _leaveEnd = DateTime.now();
  bool _isSubmittingLeave = false;
  String _permissionType = '';
  DateTime _permissionDate = DateTime.now();
  DateTime? _permissionFrom;
  DateTime? _permissionTo;
  bool _isSubmittingPermission = false;
  bool _isUploadingProfilePhoto = false;
  DateTime _calendarMonth = DateTime.now();
  DateTime? _selectedCalendarDate;

  StreamSubscription<List<AttendanceModel>>? _activitySub;
  StreamSubscription<List<AttendanceModel>>? _historySub;
  StreamSubscription<DocumentSnapshot>? _rulesSub;
  Timer? _overdueSyncTimer;
  bool _anniversaryGreetingChecked = false;

  String get _staffDesignation {
    final department = _currentStaff?.department.trim();
    if (department != null && department.isNotEmpty) return department;
    final position = _currentStaff?.position.trim();
    if (position != null && position.isNotEmpty) return position;
    return 'Staff';
  }

  String _checkInStartRule = '08:30 AM';
  String _checkOutEndRule = '07:30 PM';

  @override
  void initState() {
    super.initState();
    unawaited(_attendanceService.syncOverdueAttendanceRecords());
    _overdueSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_attendanceService.syncOverdueAttendanceRecords()),
    );
    _initializeAttendanceStreams();
    _listenAttendanceRules();

    // Set default permission times (9 AM to 10 AM today)
    final now = DateTime.now();
    _permissionFrom = DateTime(now.year, now.month, now.day, 9, 0);
    _permissionTo = DateTime(now.year, now.month, now.day, 10, 0);
  }

  @override
  void dispose() {
    _activitySub?.cancel();
    _historySub?.cancel();
    _rulesSub?.cancel();
    _overdueSyncTimer?.cancel();
    _leaveReasonController.dispose();
    _permissionReasonController.dispose();
    super.dispose();
  }

  Future<void> _initializeAttendanceStreams() async {
    final user = FirebaseAuth.instance.currentUser;
    final staff = await _loadCurrentStaff();
    final employeeId = staff?.employeeId ?? user?.uid;

    debugPrint('DEBUG EmployeeHomeScreen:');
    debugPrint('  - User UID: ${user?.uid}');
    debugPrint('  - Staff employeeId: ${staff?.employeeId}');
    debugPrint('  - Final employeeId used: $employeeId');

    if (!mounted) return;

    setState(() {
      _currentStaff = staff;
    });
    unawaited(_showAnniversaryGreetingIfDue(staff));

    _activitySub?.cancel();
    _historySub?.cancel();

    if (employeeId != null) {
      _activitySub = _attendanceService
          .getTodayAttendanceStreamForEmployee(employeeId)
          .listen((records) {
        if (!mounted) return;
        setState(() {
          _recentActivity = records.take(5).toList();
          _todayRecord = records.isNotEmpty ? records.first : null;
        });
      }, onError: (Object e, StackTrace st) {
        debugPrint('EmployeeHome activity stream error: $e\n$st');
      });
      _historySub = _attendanceService
          .getAttendanceHistoryStream(employeeId, limit: 90)
          .listen((records) {
        if (!mounted) return;
        _updateMonthlySummary(records);
      }, onError: (Object e, StackTrace st) {
        debugPrint('EmployeeHome history stream error: $e\n$st');
      });
      return;
    }

    _activitySub =
        _attendanceService.getTodayAttendanceStream().listen((records) {
      if (!mounted) return;
      setState(() {
        _recentActivity = records.take(5).toList();
        _todayRecord = null;
      });
    }, onError: (Object e, StackTrace st) {
      debugPrint('EmployeeHome activity stream error: $e\n$st');
    });
  }

  Future<void> _showAnniversaryGreetingIfDue(Staff? staff) async {
    if (_anniversaryGreetingChecked || staff == null) return;
    _anniversaryGreetingChecked = true;

    final companyName =
        context.read<WhiteLabelProvider>().config.displayCompanyName;
    final recipient = staff.employeeId.trim().isNotEmpty
        ? staff.employeeId.trim()
        : staff.id.trim();
    final greeting = await _anniversaryGreetingService.createTodayGreetingIfDue(
      profileId: staff.id,
      recipient: recipient,
      employeeName: staff.name,
      joinDate: staff.joinDate,
      companyName: companyName,
      role: 'staff',
      audienceIds: {
        staff.id,
        staff.employeeId,
        staff.email,
        FirebaseAuth.instance.currentUser?.uid ?? '',
      },
    );

    if (!mounted || greeting == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    unawaited(showAnniversaryGreetingDialog(context, greeting));
  }

  void _listenAttendanceRules() {
    _rulesSub = FirebaseContextProvider.current.firestore
        .collection('geo_config')
        .doc('default')
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data() ?? {};
      setState(() {
        _checkInStartRule =
            data['checkInStart']?.toString() ?? _checkInStartRule;
        _checkOutEndRule = data['checkOutEnd']?.toString() ?? _checkOutEndRule;
      });
    }, onError: (Object e, StackTrace st) {
      debugPrint('EmployeeHome._listenAttendanceRules error: $e\n$st');
    });
  }

  void _updateMonthlySummary(List<AttendanceModel> records) {
    final now = DateTime.now();
    final monthRecords = records
        .where((record) =>
            record.date.year == now.year && record.date.month == now.month)
        .toList();
    setState(() {
      _monthPresent = monthRecords
          .where((record) =>
              record.status == AttendanceStatus.present ||
              record.status == AttendanceStatus.wfh)
          .length;
      _monthAbsent = monthRecords
          .where((record) => record.status == AttendanceStatus.absent)
          .length;
      _monthLate = monthRecords
          .where((record) => record.status == AttendanceStatus.late)
          .length;
      _monthWorkingMinutes = monthRecords.fold<int>(
        0,
        (total, record) => total + (record.workingDuration?.inMinutes ?? 0),
      );
    });
  }

  Future<Staff?> _loadCurrentStaff() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return _attendanceService.getStaffByUserIdentity(
      uid: user.uid,
      email: user.email,
    );
  }

  Future<void> _pickAndSaveStaffPhoto() async {
    if (_isUploadingProfilePhoto || _currentStaff == null) return;

    try {
      final photoUrl = await pickProfilePhotoDataUrl();
      if (photoUrl == null) return;

      setState(() => _isUploadingProfilePhoto = true);
      await _saveStaffPhotoUrl(photoUrl);

      if (!mounted) return;
      setState(() {
        _currentStaff = _staffWithPhoto(_currentStaff!, photoUrl);
        _isUploadingProfilePhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isUploadingProfilePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save profile photo: $error')),
      );
    }
  }

  Future<void> _saveStaffPhotoUrl(String photoUrl) async {
    final staff = _currentStaff;
    final user = FirebaseAuth.instance.currentUser;
    if (staff == null) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.update(
      FirebaseFirestore.instance.collection('staff').doc(staff.id),
      {'photoUrl': photoUrl, 'updatedAt': FieldValue.serverTimestamp()},
    );

    if (user != null) {
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
        {'photoUrl': photoUrl, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    await ProfilePhotoSyncService.updateAttendancePhoto(
      photoUrl: photoUrl,
      employeeIds: [staff.employeeId],
    );
  }

  Future<void> _removeStaffPhoto() async {
    if (_isUploadingProfilePhoto || _currentStaff == null) return;

    try {
      setState(() => _isUploadingProfilePhoto = true);
      await _saveStaffPhotoUrl('');
      if (!mounted) return;
      setState(() {
        _currentStaff = _staffWithPhoto(_currentStaff!, null);
        _isUploadingProfilePhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isUploadingProfilePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to remove profile photo: $error')),
      );
    }
  }

  Staff _staffWithPhoto(Staff staff, String? photoUrl) {
    return Staff(
      id: staff.id,
      name: staff.name,
      email: staff.email,
      phone: staff.phone,
      department: staff.department,
      position: staff.position,
      employeeId: staff.employeeId,
      joinDate: staff.joinDate,
      photoUrl: photoUrl,
      photoBase64: staff.photoBase64,
      reportsTo: staff.reportsTo,
      salary: staff.salary,
      role: staff.role,
      password: staff.password,
      isActive: staff.isActive,
      hasRegistered: staff.hasRegistered,
      createdAt: staff.createdAt,
      updatedAt: staff.updatedAt,
      bloodGroup: staff.bloodGroup,
      gender: staff.gender,
      nationality: staff.nationality,
      dob: staff.dob,
      address: staff.address,
    );
  }

  int get _monthTotal => _monthPresent + _monthAbsent + _monthLate;

  Future<void> _showLogoutConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final staffName =
        user?.displayName ?? user?.email?.split('@').first ?? 'Staff';
    final staffDisplayName = _currentStaff?.name.isNotEmpty == true
        ? _currentStaff!.name
        : staffName;
    final staffDesignation = _staffDesignation;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= 980;
        final navLabelSize = constraints.maxWidth < 380 ? 10.0 : 11.0;
        final employeeId =
            _currentStaff?.employeeId ?? FirebaseAuth.instance.currentUser?.uid;
        final pageBody = _buildPageBody(staffName, employeeId);

        if (showSidebar) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: AppBackground(
              forceDark: true,
              child: Row(
                children: [
                  _StaffSidebar(
                    selectedIndex: _selectedIndex,
                    onItemSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    onLogout: _showLogoutConfirmation,
                    userName: staffDisplayName,
                    designation: staffDesignation,
                    photoUrl: _currentStaff?.photoUrl,
                    isUploadingPhoto: _isUploadingProfilePhoto,
                    onUploadPhoto: _pickAndSaveStaffPhoto,
                    onRemovePhoto: _removeStaffPhoto,
                    onProfileTap: () => _showStaffProfilePopup(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _DesktopHeader(
                          title: _pageTitle,
                          onLogout: widget.onLogout,
                        ),
                        Expanded(child: pageBody),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: _StaffDashTheme.surface,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => _showStaffProfilePopup(context),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        _StaffDashTheme.primary.withValues(alpha: 0.2),
                    backgroundImage: _staffProfileImageProvider(),
                    child: !_staffHasProfilePhoto
                        ? Text(
                            staffDisplayName.isNotEmpty
                                ? staffDisplayName[0].toUpperCase()
                                : 'S',
                            style: const TextStyle(
                              color: _StaffDashTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showStaffProfilePopup(context),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          staffDisplayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: _StaffDashTheme.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          staffDesignation,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                _StaffDashTheme.muted.withValues(alpha: 0.85),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _showLogoutConfirmation,
                icon: const Icon(
                  Icons.logout_rounded,
                  color: _StaffDashTheme.danger,
                ),
                tooltip: 'Logout',
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: AppBackground(
            forceDark: true,
            child: pageBody,
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: _StaffDashTheme.border, width: 1),
                ),
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) => setState(() => _selectedIndex = index),
                type: BottomNavigationBarType.fixed,
                backgroundColor: _StaffDashTheme.surface,
                selectedItemColor: _StaffDashTheme.primary,
                unselectedItemColor: _StaffDashTheme.muted,
                selectedLabelStyle: TextStyle(
                  fontSize: navLabelSize,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: navLabelSize,
                  fontWeight: FontWeight.w500,
                ),
                elevation: 0,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.event_note_outlined),
                    activeIcon: Icon(Icons.event_note_rounded),
                    label: 'Attendances',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.qr_code_scanner_rounded),
                    activeIcon: Icon(Icons.qr_code_scanner_rounded),
                    label: 'Scan QR',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.beach_access_outlined),
                    activeIcon: Icon(Icons.beach_access_rounded),
                    label: 'Leave',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.verified_user_outlined),
                    activeIcon: Icon(Icons.verified_user_rounded),
                    label: 'Permission',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.notifications_none_rounded),
                    activeIcon: Icon(Icons.notifications_rounded),
                    label: 'Alerts',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String get _pageTitle {
    switch (_selectedIndex) {
      case 1:
        return 'Attendances';
      case 2:
        return 'Scan QR';
      case 3:
        return 'Leave';
      case 4:
        return 'Permission';
      case 5:
        return 'Notifications';
      default:
        return 'Home';
    }
  }

  Widget _buildPageBody(String staffName, String? userId) {
    if (_selectedIndex == 2) {
      return const StaffScanQRScreen(autoStart: true);
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 420 ? 14.0 : 24.0;
    final bottomPadding = screenWidth < 980 ? 88.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        horizontalPadding,
        horizontalPadding,
        bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedIndex == 1) ...[
            _StaffAttendanceHistory(
              attendanceService: _attendanceService,
              employeeId: userId,
            ),
          ] else if (_selectedIndex == 3) ...[
            _buildLeaveSection(userId, staffName),
          ] else if (_selectedIndex == 4) ...[
            _buildPermissionSection(userId, staffName),
          ] else if (_selectedIndex == 5) ...[
            _StaffNotificationsPanel(
              attendanceService: _attendanceService,
              leaveService: _leaveService,
              staff: _currentStaff,
              employeeId: userId,
            ),
          ] else ...[
            _StaffOverviewDashboard(
              name: staffName,
              staff: _currentStaff,
              todayRecord: _todayRecord,
              records: _recentActivity,
              present: _monthPresent,
              late: _monthLate,
              absent: _monthAbsent,
              total: _monthTotal,
              workingMinutes: _monthWorkingMinutes,
              onScanAttendance: () => setState(() => _selectedIndex = 2),
              calendarMonth: _calendarMonth,
              selectedCalendarDate: _selectedCalendarDate,
              onPreviousMonth: () {
                setState(() {
                  _calendarMonth = DateTime(
                    _calendarMonth.year,
                    _calendarMonth.month - 1,
                  );
                });
              },
              onNextMonth: () {
                setState(() {
                  _calendarMonth = DateTime(
                    _calendarMonth.year,
                    _calendarMonth.month + 1,
                  );
                });
              },
              onDateSelected: (date) {
                setState(() {
                  _selectedCalendarDate = date;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLeaveSection(String? userId, String staffName) {
    if (userId == null) {
      return const _PlaceholderPanel(
        icon: Icons.error_outline,
        title: 'Leave Unavailable',
        message:
            'No user is signed in. Please sign in again to access leave requests.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Leave Request',
          style: TextStyle(
            color: _StaffDashTheme.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Fill in the details below to apply for leave.',
          style: TextStyle(color: _StaffDashTheme.muted, fontSize: 14),
        ),
        const SizedBox(height: 22),
        StreamBuilder<LeaveBalanceSummary>(
          stream: _leaveService.getLeaveBalanceSummary(userId),
          builder: (context, snapshot) {
            final balance = snapshot.data ??
                const LeaveBalanceSummary(
                  monthlyAllowance: LeaveService.monthlyLeaveAllowance,
                  approvedDays: 0,
                  pendingDays: 0,
                  remainingDays: LeaveService.monthlyLeaveAllowance,
                );

            return _LeaveSummaryGrid(balance: balance);
          },
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _StaffDashTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _StaffDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _StaffDashTheme.shadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _buildLeaveForm(userId, staffName);
            },
          ),
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<LeaveRequest>>(
          stream: _leaveService.getRequestsForUser(userId, limit: 10),
          builder: (context, snapshot) {
            final requests = snapshot.data ?? const <LeaveRequest>[];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LeaveHistoryShell(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 34),
                  child: Center(
                    child: CircularProgressIndicator(
                        color: _StaffDashTheme.primary),
                  ),
                ),
              );
            }
            if (requests.isEmpty) {
              return const _LeaveHistoryShell(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 34),
                  child: Center(
                    child: Text(
                      'No leave requests yet',
                      style: TextStyle(color: _StaffDashTheme.muted),
                    ),
                  ),
                ),
              );
            }

            return _LeaveHistoryShell(
              child: _LeaveHistoryTable(requests: requests),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLeaveForm(String userId, String staffName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Apply for Leave',
          style: TextStyle(
            color: _StaffDashTheme.text,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final leaveType = _LeaveDropdownField(
              value: _leaveType,
              onChanged: (value) {
                if (value != null) setState(() => _leaveType = value);
              },
            );
            final dateRange = _LeaveDateRangeField(
              startDate: _leaveStart,
              endDate: _leaveEnd,
              onPickStart: () => _pickLeaveDate(isStart: true),
              onPickEnd: () => _pickLeaveDate(isStart: false),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leaveType,
                  const SizedBox(height: 18),
                  dateRange,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: leaveType),
                const SizedBox(width: 32),
                Expanded(flex: 2, child: dateRange),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        _inputLabel('Reason'),
        const SizedBox(height: 8),
        Container(
          height: 84,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          decoration: BoxDecoration(
            color: _StaffDashTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _StaffDashTheme.border),
          ),
          child: Stack(
            children: [
              TextField(
                controller: _leaveReasonController,
                maxLines: null,
                expands: true,
                style: const TextStyle(color: _StaffDashTheme.text),
                decoration: const InputDecoration(
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  hintText: 'Please provide a reason for your leave request...',
                  hintStyle: TextStyle(color: Color(0xFFA4AEC7)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Positioned(
                right: 4,
                bottom: 2,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _leaveReasonController,
                  builder: (context, value, child) {
                    return Text(
                      '${value.text.length} / 500',
                      style: const TextStyle(
                        color: _StaffDashTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _isSubmittingLeave ? null : _resetLeaveForm,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _StaffDashTheme.text,
                  side: const BorderSide(color: _StaffDashTheme.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isSubmittingLeave
                    ? null
                    : () => _submitLeave(userId, staffName),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _isSubmittingLeave ? 'Submitting...' : 'Submit Leave Request',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _StaffDashTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 34, vertical: 17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _resetLeaveForm() {
    _leaveReasonController.clear();
    setState(() {
      _leaveType = '';
      _leaveStart = DateTime.now();
      _leaveEnd = DateTime.now();
    });
  }

  Widget _buildPermissionSection(String? userId, String staffName) {
    if (userId == null) {
      return const _PlaceholderPanel(
        icon: Icons.verified_user_outlined,
        title: 'Permission Unavailable',
        message:
            'No user is signed in. Please sign in again to access permission requests.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Permission Request',
          style: TextStyle(
            color: _StaffDashTheme.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Request manager permission for short-duration attendance changes.',
          style: TextStyle(color: _StaffDashTheme.muted, fontSize: 14),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _StaffDashTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _StaffDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _StaffDashTheme.shadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: _buildPermissionForm(userId, staffName),
        ),
        const SizedBox(height: 14),
        _buildPermissionHistory(userId),
      ],
    );
  }

  Widget _buildPermissionForm(String userId, String staffName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Apply for Permission',
          style: TextStyle(
            color: _StaffDashTheme.text,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final typeField = _PermissionDropdownField(
              value: _permissionType,
              onChanged: (value) {
                if (value != null) setState(() => _permissionType = value);
              },
            );
            final dateField = _PermissionPickerTile(
              label: 'Date',
              value: DateFormat('MMM dd, yyyy').format(_permissionDate),
              icon: Icons.calendar_month_rounded,
              onTap: _pickPermissionDate,
            );
            final fromField = _PermissionPickerTile(
              label: 'From Time',
              value: _permissionFrom != null
                  ? DateFormat('hh:mm a').format(_permissionFrom!)
                  : 'Select Time',
              icon: Icons.access_time_rounded,
              onTap: () => _pickPermissionTime(isFrom: true),
            );
            final toField = _PermissionPickerTile(
              label: 'To Time',
              value: _permissionTo != null
                  ? DateFormat('hh:mm a').format(_permissionTo!)
                  : 'Select Time',
              icon: Icons.access_time_filled_rounded,
              onTap: () => _pickPermissionTime(isFrom: false),
            );

            if (compact) {
              return Column(
                children: [
                  typeField,
                  const SizedBox(height: 16),
                  dateField,
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: fromField),
                      const SizedBox(width: 14),
                      Expanded(child: toField),
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: typeField),
                const SizedBox(width: 18),
                Expanded(child: dateField),
                const SizedBox(width: 18),
                Expanded(child: fromField),
                const SizedBox(width: 18),
                Expanded(child: toField),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        _inputLabel('Reason'),
        const SizedBox(height: 8),
        TextField(
          controller: _permissionReasonController,
          minLines: 3,
          maxLines: 5,
          style: const TextStyle(color: _StaffDashTheme.text),
          decoration: InputDecoration(
            hintText: 'Please provide a reason for your permission request...',
            hintStyle: const TextStyle(color: Color(0xFFA4AEC7)),
            filled: true,
            fillColor: _StaffDashTheme.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _StaffDashTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _StaffDashTheme.primary, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _isSubmittingPermission ? null : _resetPermissionForm,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _StaffDashTheme.text,
                  side: const BorderSide(color: _StaffDashTheme.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isSubmittingPermission
                    ? null
                    : () => _submitPermission(userId, staffName),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(_isSubmittingPermission
                    ? 'Submitting...'
                    : 'Submit Permission Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _StaffDashTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 34, vertical: 17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionHistory(String userId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('permission_requests')
          .snapshots(),
      builder: (context, snapshot) {
        final identities = <String>{
          userId,
          if (_currentStaff?.id.trim().isNotEmpty == true)
            _currentStaff!.id.trim(),
          if (_currentStaff?.employeeId.trim().isNotEmpty == true)
            _currentStaff!.employeeId.trim(),
          if (_currentStaff?.email.trim().isNotEmpty == true)
            _currentStaff!.email.trim(),
        };
        final docs = (snapshot.data?.docs ?? const []).where((doc) {
          final data = doc.data();
          final owner = (data['employeeId'] ??
                  data['staffId'] ??
                  data['userId'] ??
                  data['email'] ??
                  '')
              .toString()
              .trim();
          return identities.contains(owner);
        }).toList()
          ..sort((a, b) {
            final aTime = _timestampFrom(a.data()['createdAt']) ??
                _timestampFrom(a.data()['date']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = _timestampFrom(b.data()['createdAt']) ??
                _timestampFrom(b.data()['date']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PermissionHistoryShell(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: CircularProgressIndicator(
                  color: _StaffDashTheme.primary,
                ),
              ),
            ),
          );
        }

        if (docs.isEmpty) {
          return const _PermissionHistoryShell(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text(
                  'No permission requests yet',
                  style: TextStyle(color: _StaffDashTheme.muted),
                ),
              ),
            ),
          );
        }

        return _PermissionHistoryShell(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: _StaffDashTheme.border),
            itemBuilder: (context, index) {
              return _PermissionHistoryTile(data: docs[index].data());
            },
          ),
        );
      },
    );
  }

  void _resetPermissionForm() {
    _permissionReasonController.clear();
    setState(() {
      _permissionType = '';
      _permissionDate = DateTime.now();
      _permissionFrom = DateTime(_permissionDate.year, _permissionDate.month,
          _permissionDate.day, 9, 0);
      _permissionTo = DateTime(_permissionDate.year, _permissionDate.month,
          _permissionDate.day, 10, 0);
    });
  }

  Future<void> _pickPermissionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _permissionDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _permissionDate = picked;
      // Also update the dates on the times if they were already set
      if (_permissionFrom != null) {
        _permissionFrom = DateTime(picked.year, picked.month, picked.day,
            _permissionFrom!.hour, _permissionFrom!.minute);
      }
      if (_permissionTo != null) {
        _permissionTo = DateTime(picked.year, picked.month, picked.day,
            _permissionTo!.hour, _permissionTo!.minute);
      }
    });
  }

  Future<void> _pickPermissionTime({required bool isFrom}) async {
    final initialTime = isFrom
        ? TimeOfDay.fromDateTime(_permissionFrom ?? DateTime.now())
        : TimeOfDay.fromDateTime(_permissionTo ?? DateTime.now());

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _StaffDashTheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF172033),
              secondary: _StaffDashTheme.primary,
              onSecondary: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _StaffDashTheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Colors.white,
              hourMinuteColor: Color(0xFFF3F6FA),
              hourMinuteTextColor: Color(0xFF172033),
              dayPeriodColor: Color(0xFFF3F6FA),
              dayPeriodTextColor: Color(0xFF172033),
              dialBackgroundColor: Color(0xFFF8FAFC),
              dialHandColor: _StaffDashTheme.primary,
              dialTextColor: Color(0xFF172033),
              entryModeIconColor: _StaffDashTheme.primary,
              helpTextStyle: TextStyle(
                color: Color(0xFF172033),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      final dt = DateTime(_permissionDate.year, _permissionDate.month,
          _permissionDate.day, picked.hour, picked.minute);
      if (isFrom) {
        _permissionFrom = dt;
      } else {
        _permissionTo = dt;
      }
    });
  }

  Future<void> _submitPermission(String userId, String staffName) async {
    if (_permissionType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a permission type.')),
      );
      return;
    }

    if (_permissionFrom == null || _permissionTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both From and To times.')),
      );
      return;
    }

    if (_permissionTo!.isBefore(_permissionFrom!) ||
        _permissionTo!.isAtSameMomentAs(_permissionFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('To Time must be after From Time.')),
      );
      return;
    }

    // --- WORKING HOUR VALIDATION ---
    try {
      final now = DateTime.now();
      if (_permissionFrom!.isBefore(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Permission time cannot be earlier than current time.'),
            backgroundColor: _StaffDashTheme.danger,
          ),
        );
        return;
      }

      final fromTimeOfDay = TimeOfDay.fromDateTime(_permissionFrom!);
      final toTimeOfDay = TimeOfDay.fromDateTime(_permissionTo!);

      final startRuleTime = _parseTimeRule(_checkInStartRule);
      final endRuleTime = _parseTimeRule(_checkOutEndRule);

      if (!_isTimeWithinRange(fromTimeOfDay, startRuleTime, endRuleTime) ||
          !_isTimeWithinRange(toTimeOfDay, startRuleTime, endRuleTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Permissions are only allowed during office hours ($_checkInStartRule to $_checkOutEndRule).'),
            backgroundColor: _StaffDashTheme.danger,
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Rule validation error: $e');
    }

    if (_permissionReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a reason for your permission request.'),
        ),
      );
      return;
    }

    setState(() => _isSubmittingPermission = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not signed in.');

      // Use staff's Firestore employeeId (NOT Firebase Auth UID).
      // The manager query filters by this field when looking up team members.
      final staffEmployeeId = _currentStaff?.employeeId.trim() ?? '';
      final employeeName = (_currentStaff?.name.trim().isNotEmpty == true)
          ? _currentStaff!.name.trim()
          : staffName;
      // reportsTo links this staff to their manager – used by the manager dashboard.
      final managerName = _currentStaff?.reportsTo?.trim() ?? '';
      final department = (_currentStaff?.department.trim().isNotEmpty == true)
          ? _currentStaff!.department.trim()
          : widget.role.label;

      if (staffEmployeeId.isEmpty) {
        throw Exception(
          'Your staff profile is not fully set up. '
          'Please contact your administrator.',
        );
      }

      await PermissionService().submitPermissionRequest(
        employeeId: staffEmployeeId,
        employeeName: employeeName,
        department: department,
        managerName: managerName,
        reason: _permissionReasonController.text.trim(),
        permissionType: _permissionType,
        requesterUserId: user.uid,
        staffId: _currentStaff?.id,
        email: user.email ?? _currentStaff?.email,
        date: _permissionDate,
        fromTime: _permissionFrom,
        toTime: _permissionTo,
      );

      if (!mounted) return;
      _resetPermissionForm();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Your permission request has been submitted successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingPermission = false);
    }
  }

  TimeOfDay _parseTimeRule(String rule) {
    try {
      final format = DateFormat.jm(); // Parse "08:30 AM"
      final dt = format.parse(rule.trim());
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (e) {
      // Fallback
      if (rule.contains('AM')) return const TimeOfDay(hour: 8, minute: 30);
      if (rule.contains('PM')) return const TimeOfDay(hour: 19, minute: 30);
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  bool _isTimeWithinRange(TimeOfDay time, TimeOfDay start, TimeOfDay end) {
    final t = time.hour * 60 + time.minute;
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    return t >= s && t <= e;
  }

  DateTime? _timestampFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Widget _inputLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _StaffDashTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Future<void> _pickLeaveDate({required bool isStart}) async {
    final initialDate = isStart ? _leaveStart : _leaveEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final pickedWithTime = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isStart) {
        _leaveStart = pickedWithTime;
        if (_leaveEnd.isBefore(_leaveStart)) {
          _leaveEnd = _leaveStart;
        }
      } else {
        _leaveEnd =
            pickedWithTime.isBefore(_leaveStart) ? _leaveStart : pickedWithTime;
      }
    });
  }

//   bool _isSameDate(DateTime a, DateTime b) {
//     return a.year == b.year && a.month == b.month && a.day == b.day;
//   }

  bool get _staffHasProfilePhoto =>
      _currentStaff?.photoUrl?.trim().isNotEmpty == true;

  ImageProvider? _staffProfileImageProvider() {
    final raw = _currentStaff?.photoUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    final dataImageBytes = _decodeDataImage(raw);
    if (dataImageBytes != null) return MemoryImage(dataImageBytes);
    return NetworkImage(raw);
  }

  Uint8List? _decodeDataImage(String? value) {
    final raw = value?.trim();
    if (raw == null || !raw.startsWith('data:image')) return null;
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submitLeave(String userId, String staffName) async {
    if (_leaveType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a leave type.')),
      );
      return;
    }

    if (_leaveReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a reason for your leave request.')),
      );
      return;
    }

    if (_leaveEnd.isBefore(_leaveStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date.')),
      );
      return;
    }

    setState(() => _isSubmittingLeave = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not signed in.');

      final effectiveUserId = _currentStaff?.id ?? userId;

      await _leaveService.submitLeaveRequest(
        userId: effectiveUserId,
        userName: staffName,
        userPhotoUrl: user.photoURL,
        department: widget.role.label,
        type: _leaveType,
        startDate: _leaveStart,
        endDate: _leaveEnd,
        reason: _leaveReasonController.text.trim(),
      );

      if (!mounted) return;
      _leaveReasonController.clear();
      setState(() {
        _leaveType = '';
        _leaveStart = DateTime.now();
        _leaveEnd = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Your leave request has been sent to the manager for approval.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingLeave = false);
    }
  }

  void _showStaffProfilePopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final staff = _currentStaff;
        final name = staff?.name ??
            FirebaseAuth.instance.currentUser?.displayName ??
            'Staff';
        final designation = _staffDesignation;
        final email =
            staff?.email ?? FirebaseAuth.instance.currentUser?.email ?? 'N/A';
        final joinDateStr = staff != null
            ? DateFormat('dd MMM yyyy').format(staff.joinDate)
            : 'N/A';
        final detailItems = <_ProfileDetailItem>[
          _ProfileDetailItem(Icons.email_outlined, 'Email Address', email),
          _ProfileDetailItem(
              Icons.calendar_today_outlined, 'Joined Date', joinDateStr),
          if (staff != null && staff.phone.isNotEmpty)
            _ProfileDetailItem(
                Icons.phone_outlined, 'Phone Number', staff.phone),
          if (staff != null &&
              staff.bloodGroup != null &&
              staff.bloodGroup!.isNotEmpty)
            _ProfileDetailItem(
                Icons.bloodtype_outlined, 'Blood Group', staff.bloodGroup!),
          if (staff != null && staff.gender != null && staff.gender!.isNotEmpty)
            _ProfileDetailItem(
                Icons.transgender_outlined, 'Gender', staff.gender!),
          if (staff != null &&
              staff.nationality != null &&
              staff.nationality!.isNotEmpty)
            _ProfileDetailItem(
                Icons.flag_outlined, 'Nationality', staff.nationality!),
          if (staff != null && staff.dob != null)
            _ProfileDetailItem(Icons.cake_outlined, 'Date of Birth',
                DateFormat('dd MMM yyyy').format(staff.dob!)),
          if (staff != null &&
              staff.address != null &&
              staff.address!.isNotEmpty)
            _ProfileDetailItem(
                Icons.location_on_outlined, 'Address', staff.address!),
        ];
        var showPhotoActions = false;
        final dialogWidth =
            (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 400.0);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: dialogWidth,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF020617)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: const Color(0xFF1E293B), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 12,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF2D8F), Color(0xFF00FFCC)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(22),
                          topRight: Radius.circular(22),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FFCC)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF00FFCC)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              designation.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF00FFCC),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          StatefulBuilder(
                            builder: (ctx, setInnerState) {
                              final profileImage = _staffProfileImageProvider();
                              final hasPhoto = _staffHasProfilePhoto;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFFF2D8F),
                                              Color(0xFF00FFCC)
                                            ],
                                          ),
                                        ),
                                        child: CircleAvatar(
                                          radius: 46,
                                          backgroundColor:
                                              const Color(0xFF0F172A),
                                          backgroundImage: profileImage,
                                          child: profileImage == null
                                              ? Text(
                                                  name.isNotEmpty
                                                      ? name[0].toUpperCase()
                                                      : 'S',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 32,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 2,
                                        right: 2,
                                        child: GestureDetector(
                                          onTap: () {
                                            setInnerState(() {
                                              showPhotoActions =
                                                  !showPhotoActions;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(7),
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFF1E293B),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black38,
                                                  blurRadius: 4,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.edit_rounded,
                                              color: Color(0xFF00FFCC),
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (showPhotoActions) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          _profilePhotoActionButton(
                                            icon: Icons.photo_camera_rounded,
                                            label: 'Upload photo',
                                            color: const Color(0xFF00FFCC),
                                            onTap: _isUploadingProfilePhoto
                                                ? null
                                                : () {
                                                    Navigator.of(ctx).pop();
                                                    _pickAndSaveStaffPhoto();
                                                  },
                                          ),
                                          if (hasPhoto) ...[
                                            const SizedBox(height: 8),
                                            _profilePhotoActionButton(
                                              icon:
                                                  Icons.delete_outline_rounded,
                                              label: 'Remove photo',
                                              color: const Color(0xFFFF2D8F),
                                              onTap: _isUploadingProfilePhoto
                                                  ? null
                                                  : () {
                                                      Navigator.of(ctx).pop();
                                                      _removeStaffPhoto();
                                                    },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final tileWidth = (constraints.maxWidth - 12) / 2;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: detailItems
                                    .map((item) => SizedBox(
                                          width: tileWidth,
                                          child: _buildProfileDetailTile(item),
                                        ))
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileDetailTile(_ProfileDetailItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(item.icon, color: Colors.white70, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profilePhotoActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffNotificationsPanel extends StatelessWidget {
  final AttendanceService attendanceService;
  final LeaveService leaveService;
  final Staff? staff;
  final String? employeeId;

  const _StaffNotificationsPanel({
    required this.attendanceService,
    required this.leaveService,
    required this.staff,
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEmployeeId = employeeId ?? staff?.employeeId;
    if (effectiveEmployeeId == null || effectiveEmployeeId.isEmpty) {
      return const _PlaceholderPanel(
        icon: Icons.notifications_off_outlined,
        title: 'Notifications Unavailable',
        message: 'We could not find your staff profile right now.',
      );
    }

    return StreamBuilder<List<AttendanceModel>>(
      stream: attendanceService.getAttendanceHistoryStream(
        effectiveEmployeeId,
        limit: 30,
      ),
      builder: (context, attendanceSnapshot) {
        return StreamBuilder<List<LeaveRequest>>(
          stream:
              leaveService.getRequestsForUser(effectiveEmployeeId, limit: 30),
          builder: (context, leaveSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('checkout_requests')
                  .where('employeeId', isEqualTo: effectiveEmployeeId)
                  .snapshots(),
              builder: (context, checkoutSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('permission_requests')
                      .snapshots(),
                  builder: (context, permissionSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream:
                          _anniversaryNotificationStream(effectiveEmployeeId),
                      builder: (context, anniversarySnapshot) {
                        final items = <_StaffNotificationItem>[
                          ..._anniversaryItems(
                              anniversarySnapshot.data?.docs ?? const []),
                          ..._attendanceItems(
                              attendanceSnapshot.data ?? const []),
                          ..._leaveItems(leaveSnapshot.data ?? const []),
                          ..._checkoutItems(
                              checkoutSnapshot.data?.docs ?? const []),
                          ..._permissionItems(
                            permissionSnapshot.hasError
                                ? const []
                                : permissionSnapshot.data?.docs ?? const [],
                            effectiveEmployeeId,
                          ),
                        ]..sort((a, b) => b.time.compareTo(a.time));

                        final unreadCount =
                            items.where((item) => item.isNew).length;

                        final isLoading = attendanceSnapshot.connectionState ==
                                ConnectionState.waiting ||
                            leaveSnapshot.connectionState ==
                                ConnectionState.waiting ||
                            checkoutSnapshot.connectionState ==
                                ConnectionState.waiting ||
                            anniversarySnapshot.connectionState ==
                                ConnectionState.waiting;

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: _StaffDashTheme.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: _StaffDashTheme.border),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _StaffDashTheme.primary
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_rounded,
                                      color: _StaffDashTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Text(
                                      'Notifications',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: _StaffDashTheme.text,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 150),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _StaffDashTheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        '${items.length} updates${unreadCount > 0 ? ' · $unreadCount new' : ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        style: const TextStyle(
                                          color: _StaffDashTheme.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (items.isEmpty)
                                SizedBox(
                                  height: 180,
                                  child: Center(
                                    child: isLoading
                                        ? const CircularProgressIndicator(
                                            color: _StaffDashTheme.primary,
                                          )
                                        : Text(
                                            'No notifications yet',
                                            style: TextStyle(
                                              color: _StaffDashTheme.muted
                                                  .withValues(alpha: 0.78),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: _StaffDashTheme.border,
                                  ),
                                  itemBuilder: (context, index) {
                                    return _StaffNotificationTile(
                                      item: items[index],
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _anniversaryNotificationStream(
    String effectiveEmployeeId,
  ) {
    final identities = <String>{
      effectiveEmployeeId,
      if (staff?.id.trim().isNotEmpty == true) staff!.id.trim(),
      if (staff?.employeeId.trim().isNotEmpty == true) staff!.employeeId.trim(),
      if (staff?.email.trim().isNotEmpty == true) staff!.email.trim(),
    }.take(10).toList();

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('recipient', whereIn: identities)
        .snapshots();
  }

  List<_StaffNotificationItem> _anniversaryItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      return doc.data()['actionType'] == 'work_anniversary';
    }).map((doc) {
      final data = doc.data();
      final title = NotificationService.cleanNotificationText(
        (data['title'] ?? 'Work Anniversary').toString(),
      );
      return _StaffNotificationItem(
        icon: Icons.celebration_rounded,
        color: const Color(0xFFFFA400),
        title: title,
        message: (data['content'] ?? '').toString(),
        time: _timestampFrom(data['timestamp']) ?? DateTime.now(),
        isNew: true,
        anniversaryGreeting: AnniversaryGreeting(
          id: doc.id,
          recipient: (data['recipient'] ?? staff?.employeeId ?? staff?.id ?? '')
              .toString(),
          employeeName:
              (data['employeeName'] ?? data['userName'] ?? staff?.name ?? '')
                  .toString(),
          companyName:
              (data['companyName'] ?? NotificationService.brand).toString(),
          yearsCompleted: (data['yearsCompleted'] as num?)?.toInt() ?? 1,
          title: title,
          message: (data['content'] ?? '').toString(),
          timestamp: _timestampFrom(data['timestamp']) ?? DateTime.now(),
        ),
      );
    }).toList();
  }

  List<_StaffNotificationItem> _attendanceItems(
    List<AttendanceModel> records,
  ) {
    final items = <_StaffNotificationItem>[];
    for (final record in records) {
      if (record.checkInTime != null) {
        items.add(
          _StaffNotificationItem(
            icon: Icons.login_rounded,
            color: _StaffDashTheme.primary,
            title: 'Attendance marked',
            message:
                'Check-in recorded as ${record.statusLabel} for ${record.dateFormatted}.',
            time: record.checkInTime!,
          ),
        );
      }
      if (record.checkOutTime != null) {
        items.add(
          _StaffNotificationItem(
            icon: Icons.logout_rounded,
            color: const Color(0xFF00B980),
            title: 'Checkout marked',
            message:
                'Check-out recorded for ${record.dateFormatted}. Working hours: ${record.workingHoursFormatted}.',
            time: record.checkOutTime!,
          ),
        );
      }
    }
    return items;
  }

  List<_StaffNotificationItem> _leaveItems(List<LeaveRequest> requests) {
    return requests
        .where((request) =>
            request.status == 'approved' || request.status == 'rejected')
        .map((request) {
      final approved = request.status == 'approved';
      final response = request.managerResponseReason ??
          request.rejectionReason ??
          (approved ? 'Approved by manager.' : 'Rejected by manager.');
      return _StaffNotificationItem(
        icon:
            approved ? Icons.event_available_rounded : Icons.event_busy_rounded,
        color: approved ? const Color(0xFF00B980) : _StaffDashTheme.danger,
        title: 'Leave request ${approved ? 'approved' : 'rejected'}',
        message: '${request.type}: $response',
        time: request.respondedAt ??
            request.updatedAt ??
            request.createdAt ??
            request.startDate,
      );
    }).toList();
  }

  List<_StaffNotificationItem> _checkoutItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) => CheckoutRequest.fromFirestore(doc)).map((request) {
      if (request.status == 'pending') {
        return _StaffNotificationItem(
          icon: Icons.error_outline_rounded,
          color: _StaffDashTheme.danger,
          title: 'Checkout missed',
          message: request.queryMessage.isNotEmpty
              ? NotificationService.cleanNotificationText(request.queryMessage)
              : 'You missed checkout for ${request.dateKey}. Please wait for admin approval.',
          time: request.createdAt,
          isNew: true,
        );
      }

      final approved = request.status == 'approved';
      return _StaffNotificationItem(
        icon: approved ? Icons.task_alt_rounded : Icons.cancel_rounded,
        color: approved ? const Color(0xFF00B980) : _StaffDashTheme.danger,
        title: 'Checkout request ${approved ? 'approved' : 'rejected'}',
        message: request.adminNote?.trim().isNotEmpty == true
            ? request.adminNote!.trim()
            : 'Checkout request for ${request.dateKey} was ${request.status}.',
        time: request.resolvedAt ?? request.createdAt,
      );
    }).toList();
  }

  List<_StaffNotificationItem> _permissionItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String effectiveEmployeeId,
  ) {
    final identities = <String>{
      effectiveEmployeeId,
      if (staff?.id.trim().isNotEmpty == true) staff!.id.trim(),
      if (staff?.employeeId.trim().isNotEmpty == true) staff!.employeeId.trim(),
      if (staff?.email.trim().isNotEmpty == true) staff!.email.trim(),
    };

    return docs.where((doc) {
      final data = doc.data();
      final owner = (data['employeeId'] ??
              data['staffId'] ??
              data['userId'] ??
              data['email'] ??
              '')
          .toString()
          .trim();
      final status = (data['status'] ?? '').toString().toLowerCase();
      return identities.contains(owner) &&
          (status == 'approved' || status == 'rejected');
    }).map((doc) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      final approved = status == 'approved';
      final type = (data['type'] ??
              data['permissionType'] ??
              data['requestType'] ??
              'Permission')
          .toString();
      final note = (data['managerResponseReason'] ??
              data['adminNote'] ??
              data['reason'] ??
              '$type request was $status.')
          .toString();
      return _StaffNotificationItem(
        icon: approved ? Icons.verified_user_rounded : Icons.block_rounded,
        color: approved ? const Color(0xFF00B980) : _StaffDashTheme.danger,
        title: 'Permission request ${approved ? 'approved' : 'rejected'}',
        message: note,
        time: _timestampFrom(data['respondedAt']) ??
            _timestampFrom(data['resolvedAt']) ??
            _timestampFrom(data['updatedAt']) ??
            _timestampFrom(data['createdAt']) ??
            DateTime.now(),
      );
    }).toList();
  }

  DateTime? _timestampFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class _StaffNotificationItem {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final DateTime time;
  final bool isNew;
  final AnniversaryGreeting? anniversaryGreeting;

  const _StaffNotificationItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.time,
    this.isNew = false,
    this.anniversaryGreeting,
  });
}

class _StaffNotificationTile extends StatelessWidget {
  final _StaffNotificationItem item;

  const _StaffNotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: item.isNew
                        ? _StaffDashTheme.danger
                        : _StaffDashTheme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.message,
                  style: const TextStyle(
                    color: _StaffDashTheme.muted,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 94),
            child: Text(
              DateFormat('dd MMM, hh:mm a').format(item.time),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: _StaffDashTheme.muted.withValues(alpha: 0.72),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    final greeting = item.anniversaryGreeting;
    if (greeting == null) return child;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showAnniversaryGreetingDialog(context, greeting),
      child: child,
    );
  }
}

class _PermissionDropdownField extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _PermissionDropdownField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _LeaveFieldLabel('Permission Type'),
        const SizedBox(height: 10),
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _StaffDashTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _StaffDashTheme.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value.isEmpty ? null : value,
              isExpanded: true,
              hint: const Text(
                'Select Permission Type',
                style: TextStyle(
                  color: _StaffDashTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _StaffDashTheme.muted,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Late Arrival',
                  child: Text(
                    'Late Arrival',
                    style: TextStyle(color: _StaffDashTheme.text),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Medical Appointment',
                  child: Text(
                    'Medical Appointment',
                    style: TextStyle(color: _StaffDashTheme.text),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Emergency',
                  child: Text(
                    'Emergency',
                    style: TextStyle(color: _StaffDashTheme.text),
                  ),
                ),
              ],
              dropdownColor: _StaffDashTheme.surface,
              style: const TextStyle(
                color: _StaffDashTheme.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionPickerTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _PermissionPickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LeaveFieldLabel(label),
        const SizedBox(height: 10),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _StaffDashTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _StaffDashTheme.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: _StaffDashTheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _StaffDashTheme.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionHistoryShell extends StatelessWidget {
  final Widget child;

  const _PermissionHistoryShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _StaffDashTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _StaffDashTheme.border),
        boxShadow: const [
          BoxShadow(
            color: _StaffDashTheme.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Text(
              'Permission History',
              style: TextStyle(
                color: _StaffDashTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(height: 1, color: _StaffDashTheme.border),
          child,
        ],
      ),
    );
  }
}

class _PermissionHistoryTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _PermissionHistoryTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final type =
        (data['permissionType'] ?? data['type'] ?? 'Permission').toString();
    final status = (data['status'] ?? 'pending').toString().toLowerCase();
    final reason = (data['reason'] ?? '-').toString();
    final fromTime = _formatHistoryTime(data['fromTime']);
    final toTime = _formatHistoryTime(data['toTime']);
    final date =
        data['date'] is Timestamp ? (data['date'] as Timestamp).toDate() : null;
    final statusColor = status == 'approved'
        ? const Color(0xFF00B980)
        : status == 'rejected'
            ? _StaffDashTheme.danger
            : const Color(0xFFFFA000);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
                style: const TextStyle(
                  color: _StaffDashTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                [
                  if (date != null) DateFormat('MMM dd, yyyy').format(date),
                  if (fromTime.isNotEmpty || toTime.isNotEmpty)
                    '$fromTime - $toTime',
                ].join(' • '),
                style: const TextStyle(
                  color: _StaffDashTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reason,
                style: const TextStyle(
                  color: _StaffDashTheme.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          );
          final statusLabel = status.isEmpty
              ? 'Pending'
              : status[0].toUpperCase() + status.substring(1);
          final badge = _LeaveStatusBadge(
            label: statusLabel,
            color: statusColor,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 12),
                badge,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              badge,
            ],
          );
        },
      ),
    );
  }

  String _formatHistoryTime(Object? value) {
    final dateTime = value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : null;
    if (dateTime == null) return value?.toString() ?? '';
    return DateFormat('hh:mm a').format(dateTime);
  }
}

class _LeaveSummaryGrid extends StatelessWidget {
  final LeaveBalanceSummary balance;

  const _LeaveSummaryGrid({required this.balance});

  @override
  Widget build(BuildContext context) {
    final leaveService = LeaveService();
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final columns = availableWidth >= 900
            ? 2
            : availableWidth >= 260
                ? 2
                : 1;
        final cardWidth =
            (availableWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _LeaveSummaryCard(
              label: 'Monthly Leave',
              value: leaveService.formatLeaveDays(balance.monthlyAllowance),
              caption: 'This Month',
              icon: Icons.calendar_month_rounded,
              accent: _StaffDashTheme.primary,
              background: const Color(0xFFEAF1FF),
              width: cardWidth,
            ),
            _LeaveSummaryCard(
              label: 'Approved',
              value: leaveService.formatLeaveDays(balance.approvedDays),
              caption: 'This Month',
              icon: Icons.check_circle_outline_rounded,
              accent: const Color(0xFFFFA000),
              background: const Color(0xFFFFF2DA),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }
}

class _LeaveSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;
  final Color background;
  final double width;

  const _LeaveSummaryCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
    required this.background,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final iconSize = isMobile ? 36.0 : 48.0;
    return SizedBox(
      width: width,
      child: Container(
        constraints: BoxConstraints(minHeight: isMobile ? 96 : 108),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 18,
          vertical: isMobile ? 12 : 16,
        ),
        decoration: BoxDecoration(
          color: _StaffDashTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _StaffDashTheme.border),
          boxShadow: const [
            BoxShadow(
              color: _StaffDashTheme.shadow,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
              ),
              child: Icon(icon, color: accent, size: isMobile ? 20 : 26),
            ),
            SizedBox(width: isMobile ? 9 : 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _StaffDashTheme.text,
                      fontSize: isMobile ? 10 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: _StaffDashTheme.text,
                      fontSize: isMobile ? 19 : 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    caption,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _StaffDashTheme.muted,
                      fontSize: isMobile ? 10 : 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveDropdownField extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _LeaveDropdownField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _LeaveFieldLabel('Leave Type'),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _StaffDashTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _StaffDashTheme.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value.isEmpty ? null : value,
              isExpanded: true,
              hint: const Text(
                'Select Leave Type',
                style: TextStyle(
                  color: _StaffDashTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              dropdownColor: _StaffDashTheme.surface,
              iconEnabledColor: _StaffDashTheme.muted,
              style: const TextStyle(
                color: _StaffDashTheme.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Sick Leave',
                  child: _LeaveDropdownItem(
                    icon: Icons.medical_services_outlined,
                    label: 'Sick Leave',
                  ),
                ),
                DropdownMenuItem(
                  value: 'Casual Leave',
                  child: _LeaveDropdownItem(
                    icon: Icons.event_available_outlined,
                    label: 'Casual Leave',
                  ),
                ),
                DropdownMenuItem(
                  value: 'Half Day Leave',
                  child: _LeaveDropdownItem(
                    icon: Icons.timelapse_rounded,
                    label: 'Half Day Leave',
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaveDropdownItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LeaveDropdownItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _StaffDashTheme.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _StaffDashTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LeaveDateRangeField extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _LeaveDateRangeField({
    required this.startDate,
    required this.endDate,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _LeaveFieldLabel('Date Range'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430;
            if (compact) {
              return Column(
                children: [
                  _LeaveDateButton(
                    label: 'Start Date',
                    date: startDate,
                    onTap: onPickStart,
                  ),
                  const SizedBox(height: 10),
                  _LeaveDateButton(
                    label: 'End Date',
                    date: endDate,
                    onTap: onPickEnd,
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: _LeaveDateButton(
                    label: 'Start Date',
                    date: startDate,
                    onTap: onPickStart,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: _StaffDashTheme.muted, size: 20),
                ),
                Expanded(
                  child: _LeaveDateButton(
                    label: 'End Date',
                    date: endDate,
                    onTap: onPickEnd,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LeaveDateButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _LeaveDateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: BoxConstraints(minHeight: isMobile ? 54 : 60),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 14,
          vertical: isMobile ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: _StaffDashTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _StaffDashTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _StaffDashTheme.muted,
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  color: _StaffDashTheme.text,
                  size: isMobile ? 13 : 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(date),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _StaffDashTheme.text,
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveHistoryShell extends StatelessWidget {
  final Widget child;

  const _LeaveHistoryShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _StaffDashTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _StaffDashTheme.border),
        boxShadow: const [
          BoxShadow(
            color: _StaffDashTheme.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Leave History',
                    style: TextStyle(
                      color: _StaffDashTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  label: const Text('View All'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  iconAlignment: IconAlignment.end,
                  style: TextButton.styleFrom(
                    foregroundColor: _StaffDashTheme.primary,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _LeaveHistoryTable extends StatelessWidget {
  final List<LeaveRequest> requests;

  const _LeaveHistoryTable({required this.requests});

  int _dayCount(LeaveRequest request) {
    return request.endDate.difference(request.startDate).inDays + 1;
  }

  Color _statusColor(String status) {
    return switch (status) {
      'approved' => const Color(0xFF00B980),
      'rejected' => const Color(0xFFFF4F86),
      _ => const Color(0xFFFFA000),
    };
  }

  String _statusLabel(String status) {
    if (status.isEmpty) return 'Pending';
    return '${status[0].toUpperCase()}${status.substring(1)}';
  }

  static String formatIndianAppliedTime(DateTime value) {
    final indianTime = value.toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateFormat('MMM dd, yyyy\nhh:mm a').format(indianTime);
  }

  String _subtype(LeaveRequest request) {
    final type = request.type.toLowerCase();
    if (type.contains('sick')) return 'Medical';
    return 'Personal';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: requests.map((request) {
              final color = _statusColor(request.status);
              return _LeaveHistoryMobileCard(
                request: request,
                days: _dayCount(request),
                statusColor: color,
                statusLabel: _statusLabel(request.status),
                subtype: _subtype(request),
              );
            }).toList(),
          );
        }

        return Column(
          children: [
            Container(
              color: _StaffDashTheme.tableHeader,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: const Row(
                children: [
                  _LeaveHistoryHeaderCell('Leave Type', flex: 2),
                  _LeaveHistoryHeaderCell('Date Range', flex: 2),
                  _LeaveHistoryHeaderCell('Total Days', flex: 1),
                  _LeaveHistoryHeaderCell('Reason', flex: 2),
                  _LeaveHistoryHeaderCell('Status', flex: 2),
                  _LeaveHistoryHeaderCell('Applied On', flex: 2),
                ],
              ),
            ),
            ...requests.map((request) {
              final color = _statusColor(request.status);
              final appliedOn = request.createdAt ?? request.startDate;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: _StaffDashTheme.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          _LeaveTypeIcon(type: request.type, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  request.type,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _StaffDashTheme.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  _subtype(request),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _StaffDashTheme.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${DateFormat('MMM dd').format(request.startDate)} - ${DateFormat('MMM dd, yyyy').format(request.endDate)}',
                        style: const TextStyle(
                          color: _StaffDashTheme.muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${_dayCount(request)} ${_dayCount(request) == 1 ? 'Day' : 'Days'}',
                        style: const TextStyle(
                          color: _StaffDashTheme.muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        request.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _StaffDashTheme.muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _LeaveStatusBadge(
                          label: _statusLabel(request.status),
                          color: color,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _LeaveHistoryTable.formatIndianAppliedTime(appliedOn),
                        style: const TextStyle(
                          color: _StaffDashTheme.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _LeaveHistoryMobileCard extends StatelessWidget {
  final LeaveRequest request;
  final int days;
  final Color statusColor;
  final String statusLabel;
  final String subtype;

  const _LeaveHistoryMobileCard({
    required this.request,
    required this.days,
    required this.statusColor,
    required this.statusLabel,
    required this.subtype,
  });

  @override
  Widget build(BuildContext context) {
    final appliedOn = request.createdAt ?? request.startDate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _StaffDashTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LeaveTypeIcon(type: request.type, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  request.type,
                  style: const TextStyle(
                    color: _StaffDashTheme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _LeaveStatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtype,
            style: const TextStyle(color: _StaffDashTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${DateFormat('MMM dd').format(request.startDate)} - ${DateFormat('MMM dd, yyyy').format(request.endDate)}',
            style: const TextStyle(color: _StaffDashTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '$days ${days == 1 ? 'Day' : 'Days'}',
            style: const TextStyle(color: _StaffDashTheme.muted, fontSize: 13),
          ),
          if (request.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.reason,
              style:
                  const TextStyle(color: _StaffDashTheme.muted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Applied ${_LeaveHistoryTable.formatIndianAppliedTime(appliedOn).replaceFirst('\n', ' ')}',
            style: const TextStyle(color: _StaffDashTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LeaveHistoryHeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _LeaveHistoryHeaderCell(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(
          color: _StaffDashTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LeaveTypeIcon extends StatelessWidget {
  final String type;
  final Color color;

  const _LeaveTypeIcon({
    required this.type,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final icon = type.toLowerCase().contains('sick')
        ? Icons.medical_services_outlined
        : Icons.calendar_month_rounded;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }
}

class _LeaveStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _LeaveStatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LeaveFieldLabel extends StatelessWidget {
  final String label;

  const _LeaveFieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _StaffDashTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  final String title;
  final Future<void> Function() onLogout;

  const _DesktopHeader({
    required this.title,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: _StaffDashTheme.surface,
        border: Border(bottom: BorderSide(color: _StaffDashTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _StaffDashTheme.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          InkWell(
            onTap: onLogout,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _StaffDashTheme.warning,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33FF9F1C),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Logout', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffSidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final VoidCallback onLogout;
  final String userName;
  final String? designation;
  @Deprecated('Use designation instead to bypass hot reload constraint')
  final String? department;
  final String? photoUrl;
  final bool isUploadingPhoto;
  final VoidCallback onUploadPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onProfileTap;

  const _StaffSidebar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
    required this.userName,
    this.designation,
    this.photoUrl,
    required this.isUploadingPhoto,
    required this.onUploadPhoto,
    required this.onRemovePhoto,
    required this.onProfileTap,
  }) : department = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _StaffDashTheme.sidebarTop,
            _StaffDashTheme.sidebarBottom,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _StaffDashTheme.shadow,
            blurRadius: 20,
            offset: Offset(8, 0),
          ),
        ],
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StaffProfileHeader(
            userName: userName,
            designation: designation,
            photoUrl: photoUrl,
            isUploadingPhoto: isUploadingPhoto,
            onUploadPhoto: onUploadPhoto,
            onRemovePhoto: onRemovePhoto,
            onProfileTap: onProfileTap,
          ),
          const SizedBox(height: 18),
          _SidebarNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: selectedIndex == 0,
            onPressed: () => onItemSelected(0),
          ),
          _SidebarNavItem(
            icon: Icons.list_alt_rounded,
            label: 'Attendances',
            selected: selectedIndex == 1,
            onPressed: () => onItemSelected(1),
          ),
          _SidebarNavItem(
            icon: Icons.qr_code_scanner_rounded,
            label: 'Scan QR',
            selected: selectedIndex == 2,
            onPressed: () => onItemSelected(2),
          ),
          _SidebarNavItem(
            icon: Icons.request_page_rounded,
            label: 'Leave',
            selected: selectedIndex == 3,
            onPressed: () => onItemSelected(3),
          ),
          _SidebarNavItem(
            icon: Icons.verified_user_rounded,
            label: 'Permission',
            selected: selectedIndex == 4,
            onPressed: () => onItemSelected(4),
          ),
          _SidebarNavItem(
            icon: Icons.notifications_rounded,
            label: 'Notifications',
            selected: selectedIndex == 5,
            onPressed: () => onItemSelected(5),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _StaffDashTheme.warning,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: const Color(0x33FF9F1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffProfileHeader extends StatelessWidget {
  final String userName;
  final String? designation;
  @Deprecated('Use designation instead to bypass hot reload constraint')
  final String? department;
  final String? photoUrl;
  final bool isUploadingPhoto;
  final VoidCallback onUploadPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onProfileTap;

  const _StaffProfileHeader({
    required this.userName,
    this.designation,
    this.photoUrl,
    required this.isUploadingPhoto,
    required this.onUploadPhoto,
    required this.onRemovePhoto,
    required this.onProfileTap,
  }) : department = null;

  @override
  Widget build(BuildContext context) {
    final initial = userName.trim().isEmpty
        ? 'S'
        : userName.trim().characters.first.toUpperCase();
    final photoBytes = _decodeDataImage(photoUrl);
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;
    final hasNetworkPhoto =
        hasPhoto && !photoUrl!.trim().startsWith('data:image');
    ImageProvider? profileImage;
    if (photoBytes != null) {
      profileImage = MemoryImage(photoBytes);
    } else if (hasNetworkPhoto) {
      profileImage = NetworkImage(photoUrl!.trim());
    }

    return Row(
      children: [
        Tooltip(
          message: hasPhoto
              ? 'Update or remove profile photo'
              : 'Upload profile photo',
          child: InkWell(
            onTap: isUploadingPhoto
                ? null
                : () => _showPhotoMenu(context, hasPhoto: hasPhoto),
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: AppThemeColors.darkCanvas,
                  backgroundImage: profileImage,
                  child: profileImage != null
                      ? null
                      : Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _StaffDashTheme.warning,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: isUploadingPhoto
                        ? const Padding(
                            padding: EdgeInsets.all(5),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName.trim().isEmpty ? 'Staff' : userName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    designation?.trim().isNotEmpty == true
                        ? designation!.trim()
                        : 'Staff Profile',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPhotoMenu(
    BuildContext context, {
    required bool hasPhoto,
  }) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'update',
          child: Row(
            children: [
              Icon(Icons.photo_camera_rounded,
                  color: Color(0xFF00FFCC), size: 18),
              SizedBox(width: 10),
              Text(
                'Update photo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (hasPhoto)
          const PopupMenuItem<String>(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF2D8F), size: 18),
                SizedBox(width: 10),
                Text(
                  'Remove photo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );

    if (action == 'update') onUploadPhoto();
    if (action == 'remove') onRemovePhoto();
  }

  Uint8List? _decodeDataImage(String? value) {
    final raw = value?.trim();
    if (raw == null || !raw.startsWith('data:image')) return null;
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppThemeColors.actionEnd : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icon,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.84),
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.92),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppThemeColors.headingStart, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffOverviewDashboard extends StatelessWidget {
  final String name;
  final Staff? staff;
  final AttendanceModel? todayRecord;
  final List<AttendanceModel> records;
  final int present;
  final int late;
  final int absent;
  @Deprecated('Removed to bypass hot reload constraint')
  final int? wfh;
  final int total;
  final int workingMinutes;
  final VoidCallback onScanAttendance;
  final DateTime calendarMonth;
  final DateTime? selectedCalendarDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  const _StaffOverviewDashboard({
    required this.name,
    required this.staff,
    required this.todayRecord,
    required this.records,
    required this.present,
    required this.late,
    required this.absent,
    required this.total,
    required this.workingMinutes,
    required this.onScanAttendance,
    required this.calendarMonth,
    required this.selectedCalendarDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  }) : wfh = null;

  @override
  Widget build(BuildContext context) {
    final isCheckedIn = todayRecord?.checkInTime != null;
    final isCheckedOut = todayRecord?.isCheckedOut == true;
    final scanLabel = isCheckedOut
        ? 'Attendance Completed'
        : isCheckedIn
            ? 'Check-Out Now'
            : 'Scan QR Now';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StaffOverviewTopBar(name: name, staff: staff),
        const SizedBox(height: 30),
        _AttendanceReminderBanner(
          scanLabel: scanLabel,
          onScanAttendance: isCheckedOut ? null : onScanAttendance,
        ),
      ],
    );
  }
}

class _StaffOverviewTopBar extends StatelessWidget {
  final String name;
  final Staff? staff;

  const _StaffOverviewTopBar({
    required this.name,
    required this.staff,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final displayName = staff?.name.isNotEmpty == true ? staff!.name : name;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting, $displayName! 👋',
              style: TextStyle(
                color: _StaffDashTheme.text,
                fontSize: isMobile ? 22 : 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Track and manage your attendance with QR.',
              style: TextStyle(
                color: _StaffDashTheme.muted,
                fontSize: isMobile ? 13 : 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }

//   String _initial(String value) {
//     final trimmed = value.trim();
//     return trimmed.isEmpty ? 'S' : trimmed[0].toUpperCase();
//   }
}

// class _OverviewTopInfo extends StatelessWidget {
//   final IconData icon;
//   final String title;
//   final String subtitle;
//
//   const _OverviewTopInfo({
//     required this.icon,
//     required this.title,
//     required this.subtitle,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final isMobile = MediaQuery.of(context).size.width < 600;
//     return Container(
//       width: isMobile ? double.infinity : 200,
//       padding: EdgeInsets.symmetric(
//         horizontal: isMobile ? 14 : 16,
//         vertical: isMobile ? 12 : 14,
//       ),
//       decoration: BoxDecoration(
//         color: _StaffDashTheme.surface,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: const [
//           BoxShadow(
//             color: _StaffDashTheme.shadow,
//             blurRadius: 22,
//             offset: Offset(0, 10),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: isMobile ? 38 : 42,
//             height: isMobile ? 38 : 42,
//             decoration: BoxDecoration(
//               color: _StaffDashTheme.primaryLight,
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: Icon(
//               icon,
//               color: _StaffDashTheme.primary,
//               size: isMobile ? 20 : 24,
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   title,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: _StaffDashTheme.text,
//                     fontSize: isMobile ? 13 : 14,
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//                 Text(
//                   subtitle,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: _StaffDashTheme.muted,
//                     fontSize: isMobile ? 11 : 12,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _OverviewProfileChip extends StatelessWidget {
//   final String initial;
//   final String name;
//   final String designation;
//   @Deprecated('Use designation instead to bypass hot reload constraint')
//   final String? department;
//
//   const _OverviewProfileChip({
//     required this.initial,
//     required this.name,
//     required this.designation,
//     this.department,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final isMobile = MediaQuery.of(context).size.width < 600;
//     return Container(
//       width: isMobile ? double.infinity : 230,
//       padding: EdgeInsets.symmetric(
//         horizontal: isMobile ? 14 : 16,
//         vertical: isMobile ? 12 : 14,
//       ),
//       decoration: BoxDecoration(
//         color: _StaffDashTheme.surface,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: const [
//           BoxShadow(
//             color: _StaffDashTheme.shadow,
//             blurRadius: 22,
//             offset: Offset(0, 10),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           CircleAvatar(
//             radius: isMobile ? 20 : 24,
//             backgroundColor: const Color(0xFF17B5B7),
//             child: Text(
//               initial,
//               style: TextStyle(
//                 color: Colors.white,
//                 fontWeight: FontWeight.w900,
//                 fontSize: isMobile ? 15 : 18,
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   name,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: _StaffDashTheme.text,
//                     fontSize: isMobile ? 13 : 14,
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//                 Text(
//                   designation,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: _StaffDashTheme.muted,
//                     fontSize: isMobile ? 11 : 12,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           Icon(
//             Icons.keyboard_arrow_down_rounded,
//             color: _StaffDashTheme.muted,
//             size: isMobile ? 18 : 24,
//           ),
//         ],
//       ),
//     );
//   }
// }

class OverviewStatusCardLegacy extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const OverviewStatusCardLegacy({
    super.key,
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _StaffDashTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAF0FA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D245BFF),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _StaffDashTheme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _StaffDashTheme.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtext,
                    style: const TextStyle(
                      color: _StaffDashTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// class _MonthlyAttendanceSummary extends StatelessWidget {
//   final int present;
//   final int late;
//   final int absent;
//   @Deprecated('Removed to bypass hot reload constraint')
//   final int? wfh;
//   final int total;
//   final int workingMinutes;
//
//   const _MonthlyAttendanceSummary({
//     required this.present,
//     required this.late,
//     required this.absent,
//     this.wfh,
//     required this.total,
//     required this.workingMinutes,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final now = DateTime.now();
//     final workingDays = _workingDaysInMonth(now);
//     final attendedDays = present + late;
//     final attendanceRate =
//         workingDays == 0 ? 0.0 : (attendedDays / workingDays) * 100;
//     final h = workingMinutes ~/ 60;
//     final m = workingMinutes % 60;
//     final String workingHours;
//     if (h == 0 && m == 0) {
//       workingHours = '0 hrs';
//     } else if (m == 0) {
//       workingHours = '$h hrs';
//     } else {
//       final total = h + m / 60.0;
//       workingHours = '${total.toStringAsFixed(1)} hrs';
//     }
//
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
//       decoration: BoxDecoration(
//         color: _StaffDashTheme.surface,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: const Color(0xFFEAF0FA)),
//         boxShadow: const [
//           BoxShadow(
//             color: _StaffDashTheme.shadow,
//             blurRadius: 24,
//             offset: Offset(0, 10),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'This Month Overview',
//             style: TextStyle(
//               color: _StaffDashTheme.text,
//               fontSize: 18,
//               fontWeight: FontWeight.w800,
//             ),
//           ),
//           const SizedBox(height: 28),
//           LayoutBuilder(
//             builder: (context, constraints) {
//               final metrics = [
//                 _HomeMetric(
//                   icon: Icons.calendar_month_rounded,
//                   label: 'Present Days',
//                   value: '$attendedDays / $workingDays',
//                   caption: 'This Month',
//                   color: _StaffDashTheme.primary,
//                   background: _StaffDashTheme.primaryLight,
//                 ),
//                 _HomeMetric(
//                   icon: Icons.trending_up_rounded,
//                   label: 'Attendance Rate',
//                   value: '${attendanceRate.toStringAsFixed(2)}%',
//                   caption: 'Your attendance this month',
//                   color: const Color(0xFF17B982),
//                   background: const Color(0xFFE5F7F0),
//                 ),
//                 _HomeMetric(
//                   icon: Icons.schedule_rounded,
//                   label: 'Working Hours',
//                   value: workingHours,
//                   caption: 'Hours this month',
//                   color: const Color(0xFF8A4DFF),
//                   background: const Color(0xFFF1E9FF),
//                 ),
//                 _HomeMetric(
//                   icon: Icons.access_time_rounded,
//                   label: 'Late Arrivals',
//                   value: '$late',
//                   caption: 'This Month',
//                   color: const Color(0xFFFF9812),
//                   background: const Color(0xFFFFF0DF),
//                 ),
//               ];
//
//               if (constraints.maxWidth < 760) {
//                 return Wrap(
//                   spacing: 14,
//                   runSpacing: 18,
//                   children: metrics
//                       .map((metric) => SizedBox(
//                             width: constraints.maxWidth < 520
//                                 ? constraints.maxWidth
//                                 : (constraints.maxWidth - 14) / 2,
//                             child: metric,
//                           ))
//                       .toList(),
//                 );
//               }
//
//               return Row(
//                 children: metrics
//                     .expand(
//                       (metric) => [
//                         Expanded(child: metric),
//                         if (metric != metrics.last)
//                           Container(
//                             width: 1,
//                             height: 72,
//                             margin: const EdgeInsets.symmetric(horizontal: 26),
//                             color: _StaffDashTheme.border,
//                           ),
//                       ],
//                     )
//                     .toList(),
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }
//
//   int _workingDaysInMonth(DateTime date) {
//     final lastDay = DateTime(date.year, date.month + 1, 0).day;
//     var count = 0;
//     for (var day = 1; day <= lastDay; day++) {
//       if (DateTime(date.year, date.month, day).weekday != DateTime.sunday) {
//         count++;
//       }
//     }
//     return count;
//   }
// }

// class _HomeMetric extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final String value;
//   final String caption;
//   final Color color;
//   final Color background;
//
//   const _HomeMetric({
//     required this.icon,
//     required this.label,
//     required this.value,
//     required this.caption,
//     required this.color,
//     required this.background,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final isMobile = MediaQuery.of(context).size.width < 600;
//     return Row(
//       children: [
//         Container(
//           width: isMobile ? 48 : 58,
//           height: isMobile ? 48 : 58,
//           decoration: BoxDecoration(
//             color: background,
//             borderRadius: BorderRadius.circular(16),
//           ),
//           child: Icon(icon, color: color, size: isMobile ? 24 : 30),
//         ),
//         SizedBox(width: isMobile ? 12 : 18),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 label,
//                 overflow: TextOverflow.ellipsis,
//                 style: TextStyle(
//                   color: _StaffDashTheme.muted,
//                   fontSize: isMobile ? 11 : 13,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//               const SizedBox(height: 6),
//               Text(
//                 value,
//                 overflow: TextOverflow.ellipsis,
//                 style: TextStyle(
//                   color: _StaffDashTheme.text,
//                   fontSize: isMobile ? 20 : 24,
//                   fontWeight: FontWeight.w900,
//                 ),
//               ),
//               const SizedBox(height: 5),
//               Text(
//                 caption,
//                 overflow: TextOverflow.ellipsis,
//                 style: TextStyle(
//                   color: _StaffDashTheme.muted,
//                   fontSize: isMobile ? 10 : 12,
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

class SummaryLegendRowLegacy extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;

  const SummaryLegendRowLegacy({
    super.key,
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0 : ((value / total) * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _StaffDashTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value ($percent%)',
            style: const TextStyle(
              color: _StaffDashTheme.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class OverviewRecentActivityLegacy extends StatelessWidget {
  final List<AttendanceModel> records;

  const OverviewRecentActivityLegacy({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _StaffDashTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAF0FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Activity',
                  style: TextStyle(
                    color: _StaffDashTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Your recent attendance activities.',
            style: TextStyle(color: _StaffDashTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 22),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 70),
              child: Text(
                'No recent activity available yet.',
                style: TextStyle(color: _StaffDashTheme.muted),
              ),
            )
          else
            Column(
              children: records
                  .map((record) => OverviewActivityRowLegacy(record: record))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class OverviewActivityRowLegacy extends StatelessWidget {
  final AttendanceModel record;

  const OverviewActivityRowLegacy({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (record.status) {
      AttendanceStatus.present => const Color(0xFF31B879),
      AttendanceStatus.late => const Color(0xFFFFAA4D),
      AttendanceStatus.wfh => const Color(0xFF155E75),
      AttendanceStatus.absent => const Color(0xFFFF5470),
      AttendanceStatus.leave => const Color(0xFF38BDF8),
    };
    final action = record.isCheckedOut ? 'Checked out' : 'Checked in';
    final time = record.isCheckedOut
        ? record.checkOutFormatted
        : record.checkInFormatted;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEAF0FA))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor:
                record.identityCleared ? _StaffDashTheme.surface : statusColor,
            child: Text(
              record.identityCleared ? '' : _initial(record.employeeName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    color: _StaffDashTheme.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('MMM d').format(record.date)}, $time',
                  style: const TextStyle(
                    color: _StaffDashTheme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              record.statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'S' : trimmed[0].toUpperCase();
  }
}

class _AttendanceReminderBanner extends StatelessWidget {
  final String scanLabel;
  final VoidCallback? onScanAttendance;

  const _AttendanceReminderBanner({
    required this.scanLabel,
    required this.onScanAttendance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 34),
      decoration: BoxDecoration(
        color: _StaffDashTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAF0FA)),
        boxShadow: const [
          BoxShadow(
            color: _StaffDashTheme.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: _QrAttendanceHero(
        scanLabel: scanLabel,
        onScanAttendance: onScanAttendance,
      ),
    );
  }
}

class _QrAttendanceHero extends StatelessWidget {
  final String scanLabel;
  final VoidCallback? onScanAttendance;

  const _QrAttendanceHero({
    required this.scanLabel,
    required this.onScanAttendance,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        const illustration = _QrIllustration();
        final copy = Column(
          crossAxisAlignment:
              compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            const Text(
              'MARK YOUR ATTENDANCE',
              style: TextStyle(
                color: _StaffDashTheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Scan QR to Check-In / Check-Out',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _StaffDashTheme.text,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Use your system to scan the official QR code displayed at your workplace to mark your attendance.',
              style: TextStyle(
                color: _StaffDashTheme.muted,
                fontSize: 14,
                height: 1.8,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: onScanAttendance,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
              label: Text(scanLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: _StaffDashTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFB8C4DD),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            children: [
              illustration,
              const SizedBox(height: 24),
              copy,
            ],
          );
        }

        return Row(
          children: [
            const Expanded(child: _QrIllustration()),
            const SizedBox(width: 28),
            Expanded(child: copy),
          ],
        );
      },
    );
  }
}

class _QrIllustration extends StatelessWidget {
  const _QrIllustration();

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SizedBox(
      height: isMobile ? 220 : 290,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 300,
          height: 290,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F6FF),
                  shape: BoxShape.circle,
                ),
              ),
              Positioned(
                left: 18,
                bottom: 34,
                child: Transform.rotate(
                  angle: -0.07,
                  child: const _DeviceFrame(
                    width: 82,
                    height: 150,
                    borderColor: Color(0xFF1F2937),
                    qrSize: 54,
                  ),
                ),
              ),
              const Positioned(
                right: 26,
                bottom: 24,
                child: _DeviceFrame(
                  width: 116,
                  height: 206,
                  borderColor: Color(0xFF7EA7FF),
                  qrSize: 76,
                ),
              ),
              Positioned(
                left: 58,
                bottom: 4,
                child: Container(
                  width: 86,
                  height: 78,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC8AB),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(44),
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(38),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceFrame extends StatelessWidget {
  final double width;
  final double height;
  final Color borderColor;
  final double qrSize;

  const _DeviceFrame({
    required this.width,
    required this.height,
    required this.borderColor,
    required this.qrSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.13),
        border: Border.all(color: borderColor, width: 6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A245BFF),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.qr_code_2_rounded,
          color: Colors.black87,
          size: qrSize,
        ),
      ),
    );
  }
}

// class _ScanningRulesPanel extends StatelessWidget {
//   const _ScanningRulesPanel();
//
//   @override
//   Widget build(BuildContext context) {
//     return const Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Scanning Rules',
//           style: TextStyle(
//             color: _StaffDashTheme.text,
//             fontSize: 18,
//             fontWeight: FontWeight.w900,
//           ),
//         ),
//         SizedBox(height: 18),
//         _ScanningRuleRow(
//           icon: Icons.check_circle_rounded,
//           color: Color(0xFF17B982),
//           background: Color(0xFFE4F8F0),
//           text: 'Scan only the official QR displayed at your workplace.',
//         ),
//         _ScanningRuleRow(
//           icon: Icons.schedule_rounded,
//           color: _StaffDashTheme.primary,
//           background: _StaffDashTheme.primaryLight,
//           text: 'Check-in allowed within working hours only.',
//         ),
//         _ScanningRuleRow(
//           icon: Icons.logout_rounded,
//           color: Color(0xFFFF8A12),
//           background: Color(0xFFFFF0DF),
//           text: 'You can check-out only after completing minimum working time.',
//         ),
//         _ScanningRuleRow(
//           icon: Icons.location_on_rounded,
//           color: Color(0xFF8A4DFF),
//           background: Color(0xFFF1E9FF),
//           text: 'Ensure your location is enabled for accurate attendance.',
//         ),
//         _ScanningRuleRow(
//           icon: Icons.block_rounded,
//           color: Color(0xFFFF4F4F),
//           background: Color(0xFFFFE9E9),
//           text: "Do not share or scan someone else's QR.",
//         ),
//         _ScanningRuleRow(
//           icon: Icons.workspace_premium_rounded,
//           color: Color(0xFFFFA000),
//           background: Color(0xFFFFF4D9),
//           text: 'One scan at a time. Multiple scans will not be counted.',
//           showDivider: false,
//         ),
//       ],
//     );
//   }
// }

// class _ScanningRuleRow extends StatelessWidget {
//   final IconData icon;
//   final Color color;
//   final Color background;
//   final String text;
//   final bool showDivider;
//
//   const _ScanningRuleRow({
//     required this.icon,
//     required this.color,
//     required this.background,
//     required this.text,
//     this.showDivider = true,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         border: showDivider
//             ? const Border(
//                 bottom: BorderSide(color: _StaffDashTheme.border),
//               )
//             : null,
//       ),
//       padding: const EdgeInsets.symmetric(vertical: 12),
//       child: Row(
//         children: [
//           Container(
//             width: 34,
//             height: 34,
//             decoration: BoxDecoration(
//               color: background,
//               shape: BoxShape.circle,
//             ),
//             child: Icon(icon, color: color, size: 20),
//           ),
//           const SizedBox(width: 14),
//           Expanded(
//             child: Text(
//               text,
//               style: const TextStyle(
//                 color: _StaffDashTheme.muted,
//                 fontSize: 14,
//                 height: 1.35,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class _StaffAttendanceHistory extends StatelessWidget {
  final AttendanceService attendanceService;
  final String? employeeId;

  const _StaffAttendanceHistory({
    required this.attendanceService,
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    if (employeeId == null) {
      return const _PlaceholderPanel(
        icon: Icons.history_toggle_off_rounded,
        title: 'Attendance Unavailable',
        message: 'We could not find your staff attendance profile right now.',
      );
    }

    return StreamBuilder<List<AttendanceModel>>(
      initialData: const <AttendanceModel>[],
      stream:
          attendanceService.getAttendanceHistoryStream(employeeId!, limit: 60),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <AttendanceModel>[];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;

            if (snapshot.hasError) {
              return _buildTableShell(
                count: 0,
                child: Column(
                  children: [
                    if (!isMobile) const _AttendanceTableHeader(),
                    const SizedBox(
                      height: 124,
                      child: Center(
                        child: Text(
                          'Attendance records could not be loaded right now.',
                          style: TextStyle(
                            color: _StaffDashTheme.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (records.isEmpty) {
              return _buildTableShell(
                count: 0,
                child: Column(
                  children: [
                    if (!isMobile) const _AttendanceTableHeader(),
                    const SizedBox(
                      height: 124,
                      child: Center(
                        child: Text(
                          'No attendance records yet',
                          style: TextStyle(
                            color: _StaffDashTheme.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return _buildTableShell(
              count: records.length,
              exportButton: ExportDropdown(
                records: records,
                fileNamePrefix: 'Staff_Attendance',
                primaryColorOverride: _StaffDashTheme.primary,
              ),
              child: Column(
                children: [
                  if (!isMobile) const _AttendanceTableHeader(),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: _StaffDashTheme.border,
                    ),
                    itemBuilder: (_, index) {
                      final record = records[index];
                      if (isMobile) {
                        return _StaffAttendanceMobileCard(record: record);
                      }
                      return _AttendanceHistoryRow(record: record);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTableShell({
    required int count,
    required Widget child,
    Widget? exportButton,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final exportWidget = exportButton;
        final countBadge = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF5B6EF5).withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count records',
            style: const TextStyle(
              color: Color(0xFF5B6EF5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _StaffDashTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _StaffDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 26,
                  compact ? 18 : 22,
                  compact ? 16 : 20,
                  compact ? 16 : 20,
                ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Attendance History',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              color: _StaffDashTheme.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (exportWidget != null) exportWidget,
                              countBadge,
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Attendance History',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                color: _StaffDashTheme.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (exportWidget != null) exportWidget,
                              countBadge,
                            ],
                          ),
                        ],
                      ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }
}

class _AttendanceTableHeader extends StatelessWidget {
  const _AttendanceTableHeader();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width < 600) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
      decoration: const BoxDecoration(
        color: _StaffDashTheme.tableHeader,
        border: Border.symmetric(
          horizontal: BorderSide(
            color: _StaffDashTheme.border,
          ),
        ),
      ),
      child: const Row(
        children: [
          _AttendanceHeaderCell('EMPLOYEE', flex: 3),
          _AttendanceHeaderCell('DATE', flex: 2),
          _AttendanceHeaderCell('DESIGNATION', flex: 2),
          _AttendanceHeaderCell('STATUS', flex: 2),
          _AttendanceHeaderCell('CHECK-IN', flex: 1),
          _AttendanceHeaderCell('CHECK-OUT', flex: 1),
          _AttendanceHeaderCell('WORKING HR', flex: 2),
          _AttendanceHeaderCell('PENDING HR', flex: 2),
          _AttendanceHeaderCell('PERMISSION HR', flex: 2),
          _AttendanceHeaderCell('ABSENT/PRESENT', flex: 2),
        ],
      ),
    );
  }
}

class _StaffAttendanceMobileCard extends StatelessWidget {
  final AttendanceModel record;

  const _StaffAttendanceMobileCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: record.identityCleared
                    ? _StaffDashTheme.surface
                    : _avatarColor(record.employeeName),
                child: Text(
                  record.identityCleared ? '' : _initials(record.employeeName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.displayEmployeeName,
                      style: const TextStyle(
                        color: _StaffDashTheme.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      record.displayEmployeeId,
                      style: const TextStyle(
                        color: _StaffDashTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _AttendanceStatusBadge(record: record),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _infoRow(context, Icons.calendar_today, record.dateFormatted),
              _infoRow(context, Icons.business, record.displayDepartment),
              _infoRow(context, Icons.login, record.checkInFormatted),
              _infoRow(context, Icons.logout, record.checkOutFormatted),
              _infoRow(context, Icons.schedule, record.workingHoursFormatted),
              _infoRow(
                context,
                Icons.pending_actions_outlined,
                record.pendingHoursFormatted,
              ),
              _infoRow(
                context,
                Icons.verified_user_outlined,
                record.permissionHoursFormatted,
              ),
              _infoRow(
                context,
                Icons.event_busy_outlined,
                record.pendingAbsenceLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final maxWidth = MediaQuery.of(context).size.width < 600 ? 160.0 : 220.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _StaffDashTheme.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _StaffDashTheme.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    return parts.map((part) => part.isNotEmpty ? part[0] : '').take(2).join();
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF5B6EF5),
      Color(0xFF00C896),
      Color(0xFFFFB800),
      Color(0xFFFF5757),
      Color(0xFF155E75),
      Color(0xFFAB6EF5),
    ];
    return colors[name.length % colors.length];
  }
}

class _AttendanceHeaderCell extends StatelessWidget {
  final String text;
  final int flex;

  const _AttendanceHeaderCell(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: _StaffDashTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _AttendanceHistoryRow extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceHistoryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AttendanceService()
          .isEmployeeOnApprovedLeave(record.employeeId, record.date),
      builder: (context, snapshot) {
        final isOnLeave = snapshot.data == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: record.identityCleared
                          ? _StaffDashTheme.surface
                          : _avatarColor(record.employeeName),
                      child: Text(
                        record.identityCleared
                            ? ''
                            : _initials(record.employeeName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.displayEmployeeName,
                          style: const TextStyle(
                            color: _StaffDashTheme.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          record.displayEmployeeId,
                          style: const TextStyle(
                            color: _StaffDashTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  record.dateFormatted,
                  style: const TextStyle(
                    color: _StaffDashTheme.text,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  record.displayDepartment,
                  style: const TextStyle(
                    color: _StaffDashTheme.text,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: isOnLeave
                    ? const SizedBox.shrink()
                    : _AttendanceStatusBadge(record: record),
              ),
              Expanded(
                flex: 1,
                child: isOnLeave
                    ? const Text('')
                    : _AttendanceCheckIn(record: record),
              ),
              Expanded(
                flex: 1,
                child: isOnLeave
                    ? const Text('')
                    : _AttendanceCheckOut(record: record),
              ),
              Expanded(
                flex: 2,
                child: isOnLeave
                    ? const Text('')
                    : _AttendanceWorkingHours(record: record),
              ),
              Expanded(
                flex: 2,
                child: isOnLeave
                    ? const Text('')
                    : _AttendancePendingHours(record: record),
              ),
              Expanded(
                flex: 2,
                child: isOnLeave
                    ? const Text('')
                    : _AttendancePermissionHours(record: record),
              ),
              Expanded(
                flex: 2,
                child: isOnLeave
                    ? const Text(
                        'Absent',
                        style: TextStyle(
                          color: Color(0xFFFF5757),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _AttendancePendingAbsence(record: record),
              ),
            ],
          ),
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    return parts.map((part) => part.isNotEmpty ? part[0] : '').take(2).join();
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF5B6EF5),
      Color(0xFF00C896),
      Color(0xFFFFB800),
      Color(0xFFFF5757),
      Color(0xFF155E75),
      Color(0xFFAB6EF5),
    ];
    return colors[name.length % colors.length];
  }
}

class _AttendanceStatusBadge extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceStatusBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    if (record.policyAction == 'half_day_leave') {
      bg = const Color(0xFF22D3EE).withValues(alpha: 0.14);
      fg = const Color(0xFF22D3EE);
      icon = Icons.event_available_rounded;
      label = 'Half Day';
    } else if (record.statusLabel == 'Leave') {
      bg = const Color(0xFF38BDF8).withValues(alpha: 0.14);
      fg = const Color(0xFF38BDF8);
      icon = Icons.event_available_rounded;
      label = 'Leave';
    } else if (record.checkInTime == null) {
      return const SizedBox.shrink();
    } else {
      switch (record.status) {
        case AttendanceStatus.present:
        case AttendanceStatus.wfh:
        case AttendanceStatus.absent:
          bg = const Color(0xFF00C896).withValues(alpha: 0.14);
          fg = const Color(0xFF00C896);
          icon = Icons.check;
          label = 'Ontime';
          break;
        case AttendanceStatus.leave:
          bg = const Color(0xFF38BDF8).withValues(alpha: 0.14);
          fg = const Color(0xFF38BDF8);
          icon = Icons.event_available_rounded;
          label = 'Leave';
          break;
        case AttendanceStatus.late:
          bg = const Color(0xFFFFB800).withValues(alpha: 0.14);
          fg = const Color(0xFFFFB800);
          icon = Icons.access_time;
          label = 'Late';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCheckIn extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceCheckIn({required this.record});

  @override
  Widget build(BuildContext context) {
    final color = switch (record.arrivalBand) {
      'green' => const Color(0xFF00C896),
      'orange' => const Color(0xFFFFB800),
      'red' => const Color(0xFFFF5757),
      'blue' => const Color(0xFF155E75),
      _ => _StaffDashTheme.text,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          record.checkInFormatted,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (record.lateMinutes > 0)
          Text(
            '${record.lateMinutes} min late',
            style: const TextStyle(
              color: _StaffDashTheme.muted,
              fontSize: 10.5,
            ),
          ),
      ],
    );
  }
}

class _AttendanceCheckOut extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceCheckOut({required this.record});

  @override
  Widget build(BuildContext context) {
    return Text(
      record.checkOutFormatted,
      style: TextStyle(
        color: record.isCheckedOut
            ? _StaffDashTheme.primary
            : _StaffDashTheme.muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AttendanceWorkingHours extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceWorkingHours({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasDuration = record.workingDuration != null;
    return Text(
      record.workingHoursFormatted,
      style: TextStyle(
        color: hasDuration ? _StaffDashTheme.primary : _StaffDashTheme.muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AttendancePendingHours extends StatelessWidget {
  final AttendanceModel record;

  const _AttendancePendingHours({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasPending = record.displayPendingMinutes > 0;
    return Text(
      record.pendingHoursFormatted,
      style: TextStyle(
        color: hasPending ? const Color(0xFFFF5757) : const Color(0xFF00C896),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AttendancePermissionHours extends StatelessWidget {
  final AttendanceModel record;

  const _AttendancePermissionHours({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasPermission = record.permissionMinutes > 0;
    return Text(
      record.permissionHoursFormatted,
      style: TextStyle(
        color: hasPermission ? _StaffDashTheme.primary : _StaffDashTheme.muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AttendancePendingAbsence extends StatelessWidget {
  final AttendanceModel record;

  const _AttendancePendingAbsence({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasPenalty = record.pendingAbsenceLabel == 'Absent';
    return Text(
      record.pendingAbsenceLabel,
      style: TextStyle(
        color: hasPenalty ? const Color(0xFFFF5757) : const Color(0xFF00C896),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PlaceholderPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _StaffDashTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _StaffDashTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF0F766E), size: 24),
            ),
            const SizedBox(width: 14),
            Text(title,
                style: const TextStyle(
                  color: _StaffDashTheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                )),
          ]),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(
                  color: _StaffDashTheme.muted, fontSize: 15, height: 1.6)),
          const SizedBox(height: 24),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: _StaffDashTheme.soft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(Icons.workspace_premium_rounded,
                  color: _StaffDashTheme.border, size: 72),
            ),
          ),
        ],
      ),
    );
  }
}
