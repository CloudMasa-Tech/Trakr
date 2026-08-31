import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:csv/csv.dart';
// import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/attendance_model.dart';
import '../../models/leave_request.dart';
import '../../models/permission_request.dart';
import '../../models/staff.dart';
import '../../providers/white_label_provider.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../services/anniversary_greeting_service.dart';
import '../../services/attendance_service.dart';
import '../../services/leave_service.dart';
import '../../services/notification_service.dart';
import '../../services/permission_service.dart';
import '../../services/profile_photo_sync_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/profile_photo_picker.dart';
import '../../widgets/anniversary_greeting_dialog.dart';
import '../../widgets/common/firestore_notification_banner.dart';
import '../staff/staff_scan_qr_screen.dart';
import '../approve_requests/approve_requests_screen.dart';
import '../admin/monthly_employee_analysis_screen.dart';
import 'manager_team_members_screen.dart';
import '../../widgets/dashboard/export_dropdown.dart';
import '../../widgets/dashboard/holiday_calendar_widget.dart';

class _ProfileDetailItem {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileDetailItem(this.icon, this.label, this.value);
}

class _ManagerDashTheme {
//   static const Color page = AppThemeColors.backgroundDark;
  static const Color surface = AppThemeColors.darkSurface;
  static const Color header = AppThemeColors.darkCanvas;
  static const Color border = AppThemeColors.darkBorder;
  static const Color text = AppThemeColors.darkText;
  static const Color muted = AppThemeColors.darkMuted;
  static const Color primary = Color(0xFF0F766E);
  static const Color success = Color(0xFF16B86A);
//   static const Color present = Color(0xFF16B86A);
  static const Color warning = Color(0xFFFFA400);
//   static const Color late = Color(0xFFFFA400);
  static const Color danger = Color(0xFFFF3D4F);
//   static const Color absent = Color(0xFFFF3D4F);
  static const Color info = Color(0xFF0EA5E9);
  static const Color cardBlue = Color(0xFFEAF6FF);
  static const Color cardGreen = Color(0xFFE9F8F0);
  static const Color cardAmber = Color(0xFFFFF4DE);
  static const Color cardRed = Color(0xFFFFECEC);
//   static const Color governmentHoliday = Color(0xFFFFD9D9);
//   static const Color hinduHoliday = Color(0xFFFF9A2F);
//   static const Color muslimHoliday = Color(0xFF16B86A);
//   static const Color christianHoliday = Color(0xFF155E75);
  static const Color shadow = Color(0x1A6B7897);

  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF1E3A8A)],
  );

  static const LinearGradient actionGradient = LinearGradient(
    colors: [danger, Color(0xFFFF9A2F)],
  );
}

class ManagerDashboardScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const ManagerDashboardScreen({super.key, required this.onLogout});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final LeaveService _leaveService = LeaveService();
  final AnniversaryGreetingService _anniversaryGreetingService =
      AnniversaryGreetingService();
  final TextEditingController _attendanceSearchController =
      TextEditingController();
  StreamSubscription<Map<String, int>>? _todayStatsSub;
  StreamSubscription<List<AttendanceModel>>? _lateAbsentSub;
  StreamSubscription<QuerySnapshot>? _teamSub;
  StreamSubscription<Map<String, int>>? _monthlyStatsSub;
  Timer? _overdueSyncTimer;

  int _selectedIndex = 0;
  DateTime _monthlyAnalysisMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  final TextEditingController _monthlyAnalysisSearchController =
      TextEditingController();
  String _monthlyAnalysisSearchQuery = '';
  _ManagerMonthlyRowData? _monthlySelectedRow;
  int _present = 0;
  int _absent = 0;
  int _late = 0;
  int _wfh = 0;
  int _earlyCheckouts = 0;
  int _totalAssignedStaff = 0;

  int _monthlyPresent = 0;
  int _monthlyAbsent = 0;
  int _monthlyLate = 0;
  int _monthlyWfh = 0;
  int _monthlyTotalRecords = 0;
  List<AttendanceModel> _lateAbsent = [];
  DateTime? _selectedAttendanceDate;
  DateTime? _attendanceCalendarMonth;
  DateTime? _selectedOwnRecordDate;
  DateTime? _ownRecordCalendarMonth;
  String _attendanceSearchQuery = '';
  String? _managerIdentifier;
  String? _managerEmployeeId;
  String _managerDisplayName = 'Manager';
  String? _managerPhotoUrl;
  String? _managerDocId;
  Map<String, dynamic>? _managerDocData;
  bool _isResolvingManager = true;
  bool _isUploadingProfilePhoto = false;
  bool _anniversaryGreetingChecked = false;

  /// The signed-in user on the ACTIVE Firebase context (tenant, not master).
  ///
  /// During a tenant session the manager is authenticated against the tenant
  /// project's own `FirebaseAuth` instance, exposed via
  /// `FirebaseContextProvider.current.auth`. The raw `FirebaseAuth.instance`
  /// singleton resolves to the default (master control-plane) project, which
  /// has no signed-in user, so every screen would appear logged-out. This
  /// getter is the single source of truth for the current manager.
  User? get _activeUser => FirebaseContextProvider.current.auth.currentUser;

  // Fields for Manager's own leave & permission applications
  final TextEditingController _managerLeaveReasonController =
      TextEditingController();
  final TextEditingController _managerPermissionReasonController =
      TextEditingController();
  String _managerLeaveType = '';
  DateTime _managerLeaveStart = DateTime.now().add(const Duration(hours: 2));
  DateTime _managerLeaveEnd = DateTime.now().add(const Duration(hours: 2));
  bool _isSubmittingManagerLeave = false;
  String _managerPermissionType = '';
  DateTime _managerPermissionDate = DateTime.now();
  DateTime? _managerPermissionFrom;
  DateTime? _managerPermissionTo;
  bool _isSubmittingManagerPermission = false;
  int _managerRequestSubTab = 0; // 0 = Leave, 1 = Permission

  DateTime get _safeAttendanceCalendarMonth {
    final month = _attendanceCalendarMonth;
    if (month != null) {
      return month;
    }
    final selected = _selectedAttendanceDate;
    if (selected != null) {
      return DateTime(selected.year, selected.month);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime get _safeOwnRecordCalendarMonth {
    final month = _ownRecordCalendarMonth;
    if (month != null) {
      return month;
    }
    final selected = _selectedOwnRecordDate;
    if (selected != null) {
      return DateTime(selected.year, selected.month);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_attendanceService.syncOverdueAttendanceRecords());
    _overdueSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_attendanceService.syncOverdueAttendanceRecords()),
    );
    _resolveManagerContext();
  }

  @override
  void dispose() {
    _todayStatsSub?.cancel();
    _lateAbsentSub?.cancel();
    _teamSub?.cancel();
    _monthlyStatsSub?.cancel();
    _overdueSyncTimer?.cancel();
    _attendanceSearchController.dispose();
    _monthlyAnalysisSearchController.dispose();
    super.dispose();
  }

  Future<void> _resolveManagerContext() async {
    final user = _activeUser;
    final fallbackIdentifier = user?.email?.trim().isNotEmpty == true
        ? user!.email!.trim()
        : user?.uid ?? user?.displayName ?? 'Manager';

    try {
      final Staff? managerStaff = user == null
          ? null
          : await _attendanceService.getStaffByUserIdentity(
              uid: user.uid,
              email: user.email,
            );

      String resolvedIdentifier = fallbackIdentifier;
      String resolvedName = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'Manager';
      String? resolvedPhotoUrl = user?.photoURL;
      String? resolvedDocId;
      Map<String, dynamic>? resolvedDocData;

      if (_managerDocId?.trim().isNotEmpty == true) {
        final docSnap = await FirebaseContextProvider.current.firestore
            .collection('managers')
            .doc(_managerDocId!.trim())
            .get();
        if (docSnap.exists) {
          resolvedDocId = docSnap.id;
          resolvedDocData = docSnap.data();
        }
      }

      if (resolvedDocData == null && user?.email != null) {
        final querySnap = await FirebaseContextProvider.current.firestore
            .collection('managers')
            .where('email', isEqualTo: user!.email!.trim().toLowerCase())
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          resolvedDocId = querySnap.docs.first.id;
          resolvedDocData = querySnap.docs.first.data();
        }
      }

      if (resolvedDocData != null) {
        final docEmployeeId = resolvedDocData['employeeId']?.toString().trim();
        final docEmail = resolvedDocData['email']?.toString().trim();
        final docName = resolvedDocData['name']?.toString().trim();
        final docPhoto = resolvedDocData['photoUrl']?.toString().trim();
        resolvedIdentifier = docEmployeeId?.isNotEmpty == true
            ? docEmployeeId!
            : docEmail?.isNotEmpty == true
                ? docEmail!
                : resolvedIdentifier;
        if (docName?.isNotEmpty == true) resolvedName = docName!;
        if (docPhoto?.isNotEmpty == true) resolvedPhotoUrl = docPhoto;
      }

      if (managerStaff != null && resolvedDocData == null) {
        resolvedIdentifier = managerStaff.employeeId.trim().isNotEmpty == true
            ? managerStaff.employeeId.trim()
            : fallbackIdentifier;
        resolvedName = managerStaff.name.trim().isNotEmpty == true
            ? managerStaff.name.trim()
            : resolvedName;
        resolvedPhotoUrl = managerStaff.photoUrl?.trim().isNotEmpty == true
            ? managerStaff.photoUrl!.trim()
            : resolvedPhotoUrl;
        resolvedDocData = {
          ...?resolvedDocData,
          'name': managerStaff.name,
          'email': managerStaff.email,
          'phone': managerStaff.phone,
          'employeeId': managerStaff.employeeId,
          'department': managerStaff.department,
          'position': managerStaff.position,
          'joinDate': Timestamp.fromDate(managerStaff.joinDate),
          'photoUrl': managerStaff.photoUrl ?? resolvedPhotoUrl,
          'bloodGroup': managerStaff.bloodGroup,
          'gender': managerStaff.gender,
          'nationality': managerStaff.nationality,
          'dob': managerStaff.dob != null
              ? Timestamp.fromDate(managerStaff.dob!)
              : null,
          'address': managerStaff.address,
        };
      } else if (resolvedDocData == null && user != null) {
        final canonicalName =
            await _attendanceService.getManagerNameByEmail(user.email);
        if (canonicalName != null && canonicalName.isNotEmpty) {
          resolvedIdentifier = canonicalName;
          resolvedName = canonicalName;
        }
      }

      if (!mounted) return;
      setState(() {
        _managerIdentifier = resolvedIdentifier;
        _managerEmployeeId = managerStaff?.employeeId.trim().isNotEmpty == true
            ? managerStaff!.employeeId.trim()
            : null;
        _managerDisplayName = resolvedName;
        _managerPhotoUrl = resolvedPhotoUrl;
        _managerDocId = resolvedDocId;
        _managerDocData = resolvedDocData;
        _isResolvingManager = false;
      });
      unawaited(_showManagerAnniversaryGreetingIfDue(
        profileId: user?.uid ?? resolvedIdentifier,
        recipient: resolvedIdentifier,
        employeeName: resolvedName,
        joinDate: _timestampFromObject(resolvedDocData?['joinDate']),
        audienceIds: {
          resolvedIdentifier,
          resolvedName,
          resolvedDocData?['employeeId']?.toString() ?? '',
          resolvedDocData?['email']?.toString() ?? user?.email ?? '',
          user?.uid ?? '',
        },
      ));
      _bindManagerStreams(resolvedIdentifier);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _managerIdentifier = fallbackIdentifier;
        _managerEmployeeId = null;
        _managerDocId = null;
        _managerDisplayName = user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'Manager';
        _managerPhotoUrl = user?.photoURL;
        _isResolvingManager = false;
      });
      _bindManagerStreams(fallbackIdentifier);
    }
  }

  Future<void> _showManagerAnniversaryGreetingIfDue({
    required String profileId,
    required String recipient,
    required String employeeName,
    required DateTime? joinDate,
    required Iterable<String> audienceIds,
  }) async {
    if (_anniversaryGreetingChecked || joinDate == null) return;
    _anniversaryGreetingChecked = true;

    final companyName =
        context.read<WhiteLabelProvider>().config.displayCompanyName;
    final greeting = await _anniversaryGreetingService.createTodayGreetingIfDue(
      profileId: profileId,
      recipient: recipient,
      employeeName: employeeName,
      joinDate: joinDate,
      companyName: companyName,
      role: 'manager',
      audienceIds: audienceIds,
    );

    if (!mounted || greeting == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    unawaited(showAnniversaryGreetingDialog(context, greeting));
  }

  DateTime? _timestampFromObject(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Future<void> _pickAndUploadManagerPhoto() async {
    if (_isUploadingProfilePhoto) return;

    final user = _activeUser;
    if (user == null) return;

    try {
      final photoUrl = await pickProfilePhotoDataUrl();
      if (photoUrl == null) return;

      setState(() => _isUploadingProfilePhoto = true);
      await _saveManagerPhotoUrl(photoUrl);

      if (!mounted) return;
      setState(() {
        _managerPhotoUrl = photoUrl;
        _isUploadingProfilePhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manager profile photo updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isUploadingProfilePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to upload profile photo: $error')),
      );
    }
  }

  Future<void> _saveManagerPhotoUrl(String photoUrl) async {
    final user = _activeUser;
    final db = FirebaseContextProvider.current.firestore;
    final batch = db.batch();
    var hasWrite = false;

    if (user != null) {
      batch.set(
        db.collection('users').doc(user.uid),
        {'photoUrl': photoUrl, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      hasWrite = true;

      final managerByUid = db.collection('managers').doc(user.uid);
      final managerByUidSnap = await managerByUid.get();
      if (managerByUidSnap.exists) {
        batch.update(managerByUid, {'photoUrl': photoUrl});
        hasWrite = true;
      }
    }

    if (_managerDocId?.trim().isNotEmpty == true) {
      final managerByDocId =
          db.collection('managers').doc(_managerDocId!.trim());
      final managerByDocIdSnap = await managerByDocId.get();
      if (managerByDocIdSnap.exists) {
        batch.update(managerByDocId, {'photoUrl': photoUrl});
        hasWrite = true;
      }
    }

    final identifiers = <String>{
      if (_managerEmployeeId != null && _managerEmployeeId!.trim().isNotEmpty)
        _managerEmployeeId!.trim(),
      if (_managerIdentifier != null && _managerIdentifier!.trim().isNotEmpty)
        _managerIdentifier!.trim(),
      if (user?.email?.trim().isNotEmpty == true) user!.email!.trim(),
    };

    for (final identifier in identifiers) {
      final managers = await db
          .collection('managers')
          .where('employeeId', isEqualTo: identifier)
          .get();
      for (final doc in managers.docs) {
        batch.update(doc.reference, {'photoUrl': photoUrl});
        hasWrite = true;
      }

      final managersByEmail = await db
          .collection('managers')
          .where('email', isEqualTo: identifier)
          .get();
      for (final doc in managersByEmail.docs) {
        batch.update(doc.reference, {'photoUrl': photoUrl});
        hasWrite = true;
      }

      final staff = await db
          .collection('staff')
          .where('employeeId', isEqualTo: identifier)
          .get();
      for (final doc in staff.docs) {
        batch.update(doc.reference, {'photoUrl': photoUrl});
        hasWrite = true;
      }
    }

    if (hasWrite) await batch.commit();
    await ProfilePhotoSyncService.updateAttendancePhoto(
      photoUrl: photoUrl,
      employeeIds: identifiers,
    );
  }

  Future<void> _removeManagerPhoto() async {
    if (_isUploadingProfilePhoto) return;

    try {
      setState(() => _isUploadingProfilePhoto = true);
      await _saveManagerPhotoUrl('');
      if (!mounted) return;
      setState(() {
        _managerPhotoUrl = null;
        _isUploadingProfilePhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manager profile photo removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isUploadingProfilePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to remove profile photo: $error')),
      );
    }
  }

  void _bindManagerStreams(String managerIdentifier) {
    _todayStatsSub?.cancel();
    _lateAbsentSub?.cancel();
    _teamSub?.cancel();
    _monthlyStatsSub?.cancel();

    _todayStatsSub = _attendanceService
        .getTodayStatsStreamByManager(managerIdentifier)
        .listen((stats) {
      if (!mounted) return;
      setState(() {
        _present = stats['present'] ?? 0;
        _absent = stats['absent'] ?? 0;
        _late = stats['late'] ?? 0;
        _wfh = stats['wfh'] ?? 0;
        _earlyCheckouts = stats['earlyCheckouts'] ?? 0;
      });
    });

    _monthlyStatsSub = _attendanceService
        .getMonthlyStatsStreamByManager(managerIdentifier)
        .listen((stats) {
      if (!mounted) return;
      setState(() {
        _monthlyPresent = stats['present'] ?? 0;
        _monthlyAbsent = stats['absent'] ?? 0;
        _monthlyLate = stats['late'] ?? 0;
        _monthlyWfh = stats['wfh'] ?? 0;
        _monthlyTotalRecords = stats['totalRecords'] ?? 0;
      });
    });

    _lateAbsentSub = _attendanceService
        .getTodayAttendanceStreamByManager(managerIdentifier)
        .listen((records) {
      if (!mounted) return;
      setState(() {
        _lateAbsent = records.take(5).toList();
      });
    });

    final name = _managerDisplayName.trim();
    final email = _activeUser?.email?.trim() ?? '';
    List<String> identifiers = [name];
    if (email.isNotEmpty && email != name) {
      identifiers.add(email);
    }

    _teamSub = FirebaseContextProvider.current.firestore
        .collection('staff')
        .where('reportsTo', whereIn: identifiers)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _totalAssignedStaff = snapshot.docs.length;
      });
    }, onError: (Object e, StackTrace st) {
      debugPrint('ManagerDashboard team stream error: $e\n$st');
    });
  }

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

  String get _attendanceManagerScope {
    final identifier = _managerIdentifier?.trim() ?? '';
    if (identifier.isNotEmpty) {
      return identifier;
    }
    return _managerDisplayName.trim();
  }

  bool get _managerHasProfilePhoto =>
      _managerPhotoUrl?.trim().isNotEmpty == true;

  String get _managerDesignation {
    final department = _managerDocData?['department']?.toString().trim();
    if (department != null && department.isNotEmpty) return department;
    final position = _managerDocData?['position']?.toString().trim();
    if (position != null && position.isNotEmpty) return position;
    return 'Manager';
  }

  ImageProvider? _managerProfileImageProvider() {
    final raw = _managerPhotoUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    final dataImageBytes = _decodeDataImage(raw);
    if (dataImageBytes != null) return MemoryImage(dataImageBytes);
    return NetworkImage(raw);
  }

  List<String> _managerNotificationIdentities() {
    final user = _activeUser;
    return [
      _managerDisplayName,
      _attendanceManagerScope,
      if (_managerDocId?.trim().isNotEmpty == true) _managerDocId!.trim(),
      if (_managerEmployeeId?.trim().isNotEmpty == true)
        _managerEmployeeId!.trim(),
      if (_managerDocData?['email']?.toString().trim().isNotEmpty == true)
        _managerDocData!['email'].toString().trim(),
      if (user?.uid.trim().isNotEmpty == true) user!.uid.trim(),
      if (user?.email?.trim().isNotEmpty == true) user!.email!.trim(),
    ];
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;
        final contentPadding = isMobile
            ? const EdgeInsets.fromLTRB(16, 20, 16, 104)
            : const EdgeInsets.symmetric(horizontal: 26, vertical: 28);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: isMobile
              ? AppBar(
                  backgroundColor: _ManagerDashTheme.surface,
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  title: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showManagerProfilePopup(context),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              _ManagerDashTheme.primary.withValues(alpha: 0.2),
                          backgroundImage: _managerProfileImageProvider(),
                          child: !_managerHasProfilePhoto
                              ? Text(
                                  _managerDisplayName.isNotEmpty
                                      ? _managerDisplayName[0].toUpperCase()
                                      : 'M',
                                  style: const TextStyle(
                                    color: _ManagerDashTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showManagerProfilePopup(context),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _managerDisplayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _ManagerDashTheme.text,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _managerDesignation,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _ManagerDashTheme.muted
                                      .withValues(alpha: 0.85),
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
                      icon: const Icon(Icons.logout_rounded,
                          color: _ManagerDashTheme.danger),
                      onPressed: _showLogoutConfirmation,
                    ),
                  ],
                )
              : null,
          body: Stack(
            children: [
              AppBackground(
                forceDark: true,
                child: isMobile
                    ? SafeArea(
                        bottom: false,
                        child: _selectedIndex == 6 || _selectedIndex == 10
                            ? _buildPageContent()
                            : SingleChildScrollView(
                                padding: contentPadding,
                                child: _buildPageContent(),
                              ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ManagerSidebar(
                            selectedIndex: _selectedIndex,
                            onItemSelected: (index) =>
                                setState(() => _selectedIndex = index),
                            onLogout: _showLogoutConfirmation,
                            managerName: _managerDisplayName,
                            managerDesignation: _managerDesignation,
                            photoUrl: _managerPhotoUrl,
                            isUploadingPhoto: _isUploadingProfilePhoto,
                            onUploadPhoto: _pickAndUploadManagerPhoto,
                            onRemovePhoto: _removeManagerPhoto,
                            onProfileTap: () =>
                                _showManagerProfilePopup(context),
                          ),
                          Expanded(
                            child: _selectedIndex == 6 || _selectedIndex == 10
                                ? _buildPageContent()
                                : SingleChildScrollView(
                                    padding: contentPadding,
                                    child: _buildPageContent(),
                                  ),
                          ),
                        ],
                      ),
              ),
              FirestoreNotificationBanner(
                identities: _managerNotificationIdentities(),
              ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? _ManagerBottomNavigation(
                  selectedIndex: _selectedIndex,
                  onItemSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  onLogout: _showLogoutConfirmation,
                )
              : null,
        );
      },
    );
  }

  Widget _responsiveTwoColumnCards(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final columns = availableWidth >= 700
            ? cards.length.clamp(1, 4).toInt()
            : availableWidth >= 260
                ? 2
                : 1;
        final cardWidth =
            (availableWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: cardWidth,
                child: card,
              ),
          ],
        );
      },
    );
  }

  Widget _buildPageContent() {
    switch (_selectedIndex) {
      case 1:
        return _buildAttendanceLogPage();
      case 2:
        return _buildOwnRecordPage();
      case 3:
        return _buildOwnLeaveAndPermissionPage();
      case 5:
        return ManagerTeamMembersScreen(
          managerName: _managerDisplayName,
          managerEmail: _activeUser?.email ?? '',
        );
      case 6:
        return const StaffScanQRScreen(autoStart: true);
      case 7:
        return _buildNotificationsPage();
      case 8:
        return _buildOwnLeaveAndPermissionPage();
      case 9:
        return _buildMonthlyAnalysisPage();
      case 10:
        return ApproveRequestsScreen(
          isCompanyWide: false,
          managerScope: _attendanceManagerScope,
        );
      default:
        return _ManagerHomeDashboard(
          managerName: _managerDisplayName,
          present: _present,
          late: _late,
          absent: _absent,
          wfh: _wfh,
          earlyCheckouts: _earlyCheckouts,
          totalStaff: _totalAssignedStaff,
          monthlyPresent: _monthlyPresent,
          monthlyLate: _monthlyLate,
          monthlyAbsent: _monthlyAbsent,
          monthlyWfh: _monthlyWfh,
          monthlyTotalRecords: _monthlyTotalRecords,
          recentRecords: _lateAbsent,
        );
    }
  }

  Widget _buildAttendanceLogPage() {
    if (_isResolvingManager && _managerIdentifier == null) {
      return SizedBox(
        width: double.infinity,
        child: Container(
          margin: const EdgeInsets.only(top: 32, right: 32),
          padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ManagerDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _ManagerDashTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: CircularProgressIndicator(color: _ManagerDashTheme.primary),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).size.width < 800 ? 8 : 32,
          right: MediaQuery.of(context).size.width < 800 ? 0 : 32,
        ),
        child: Column(
          children: [
            _AttendanceSearchField(
              controller: _attendanceSearchController,
              onChanged: (value) {
                setState(() => _attendanceSearchQuery = value.trim());
              },
              onClear: _attendanceSearchQuery.isEmpty
                  ? null
                  : () {
                      _attendanceSearchController.clear();
                      setState(() => _attendanceSearchQuery = '');
                    },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final visibleCalendarMonth = _safeAttendanceCalendarMonth;
                final calendar = HolidayCalendarWidget(
                  visibleMonth: visibleCalendarMonth,
                  selectedDate: _selectedAttendanceDate,
                  onPreviousMonth: () {
                    setState(() {
                      _attendanceCalendarMonth = DateTime(
                        visibleCalendarMonth.year,
                        visibleCalendarMonth.month - 1,
                      );
                    });
                  },
                  onNextMonth: () {
                    setState(() {
                      _attendanceCalendarMonth = DateTime(
                        visibleCalendarMonth.year,
                        visibleCalendarMonth.month + 1,
                      );
                    });
                  },
                  onDateSelected: (date) {
                    setState(() {
                      _selectedAttendanceDate = date;
                      _attendanceCalendarMonth =
                          DateTime(date.year, date.month);
                    });
                  },
                );
                final table = _ManagerAttendanceLogTable(
                  attendanceService: _attendanceService,
                  managerIdentifier: _attendanceManagerScope,
                  title: 'Attendance Log',
                  emptyMessage: 'No attendance records found.',
                  selectedDate: _selectedAttendanceDate,
                  searchQuery: _attendanceSearchQuery,
                  onClearDateFilter: _selectedAttendanceDate == null
                      ? null
                      : () => setState(() => _selectedAttendanceDate = null),
                );

                if (constraints.maxWidth < 980) {
                  return Column(
                    children: [
                      calendar,
                      const SizedBox(height: 16),
                      table,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 360, child: calendar),
                    const SizedBox(width: 16),
                    Expanded(child: table),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyAnalysisPage() {
    if (_isResolvingManager && _managerIdentifier == null) {
      return SizedBox(
        width: double.infinity,
        child: Container(
          margin: const EdgeInsets.only(top: 32, right: 32),
          padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ManagerDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _ManagerDashTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: CircularProgressIndicator(color: _ManagerDashTheme.primary),
          ),
        ),
      );
    }

    final selectedSummary = _monthlySelectedRow;
    if (selectedSummary != null) {
      final selected = _monthlyAnalysisMonth;
      // Mirror the Admin per-employee drill-down. Bounded height is required
      // because the page content sits inside the dashboard's outer scroll view
      // while the drill-down screen uses an internal Expanded.
      return SizedBox(
        height: MediaQuery.of(context).size.height -
            (MediaQuery.of(context).size.width < 800 ? 130 : 190),
        child: MonthlyEmployeeAnalysisScreen(
          staff: selectedSummary.staff,
          month: selected.month,
          year: selected.year,
          totalApprovedLeaves: selectedSummary.totalLeaveCount.round(),
          onBack: () => setState(() => _monthlySelectedRow = null),
        ),
      );
    }

    final selected = _monthlyAnalysisMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = MediaQuery.of(context).size.width < 650;
            const title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Analysis',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppThemeColors.darkText,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Overall and monthly results of attendance records',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.darkMuted,
                  ),
                ),
              ],
            );

            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 14),
                  _buildMonthlyDateSelectors(),
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                title,
                _buildMonthlyDateSelectors(),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<AttendanceModel>>(
          stream: _attendanceService
              .getMonthlyAttendanceStreamByManagerForMonth(
                _attendanceManagerScope,
                selected,
              ),
          builder: (context, attendanceSnapshot) {
            return StreamBuilder<List<Staff>>(
              stream: StaffService()
                  .getTeamMembersByManager(_attendanceManagerScope),
              builder: (context, staffSnapshot) {
                return StreamBuilder<List<LeaveRequest>>(
                  stream: _leaveService
                      .getRequestsForManager(_attendanceManagerScope),
                  builder: (context, leaveSnapshot) {
                    final rows = _buildMonthlyRows(
                      attendanceSnapshot.data ?? const <AttendanceModel>[],
                      staffSnapshot.data ?? const <Staff>[],
                      leaveSnapshot.data ?? const <LeaveRequest>[],
                      selected,
                    );

                    return _buildMonthlySummaryTable(
                      rows: rows,
                      waiting: attendanceSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          !attendanceSnapshot.hasData,
                      errorText: attendanceSnapshot.hasError
                          ? 'Unable to load monthly analysis.'
                          : null,
                      emptyText: 'No attendance records for '
                          '${DateFormat('MMMM yyyy').format(selected)}.',
                      onRowTap: (row) =>
                          setState(() => _monthlySelectedRow = row),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildMonthlySummaryTable({
    required List<_ManagerMonthlyRowData> rows,
    required bool waiting,
    required String? errorText,
    required String emptyText,
    required ValueChanged<_ManagerMonthlyRowData> onRowTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _maShadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthlyTableHeaderSection(),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 800;
              if (isMobile) return const SizedBox.shrink();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                decoration: const BoxDecoration(
                  color: AppThemeColors.darkCanvas,
                  border: Border(
                    bottom: BorderSide(color: AppThemeColors.darkBorder),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 18, child: _ManagerMonthlyHeaderText('EMPLOYEE')),
                    Expanded(flex: 14, child: _ManagerMonthlyHeaderText('DESIGNATION')),
                    Expanded(flex: 14, child: _ManagerMonthlyHeaderText('POSITION')),
                    Expanded(flex: 8, child: _ManagerMonthlyHeaderText('PRESENT')),
                    Expanded(flex: 8, child: _ManagerMonthlyHeaderText('ABSENT')),
                    Expanded(flex: 16, child: _ManagerMonthlyHeaderText('PENDING')),
                    Expanded(flex: 16, child: _ManagerMonthlyHeaderText('PERMISSION')),
                    Expanded(flex: 16, child: _ManagerMonthlyHeaderText('TOTAL PENDING')),
                    Expanded(flex: 12, child: _ManagerMonthlyHeaderText('LEAVE')),
                  ],
                ),
              );
            },
          ),
          if (waiting)
            const SizedBox(
              height: 180,
              child: Center(
                child: CircularProgressIndicator(color: _maPrimary),
              ),
            )
          else if (errorText != null)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  errorText,
                  style: const TextStyle(
                    color: _maRed,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else if (rows.isEmpty)
            SizedBox(
              height: 152,
              child: Center(
                child: Text(
                  emptyText,
                  textAlign: TextAlign.center,
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
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppThemeColors.darkBorder),
              itemBuilder: (context, index) => _ManagerMonthlyRow(
                summary: rows[index],
                formatTime: _formatMonthlyHours,
                onTap: () => onRowTap(rows[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTableHeaderSection() {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          const titleWidget = Text(
            'Monthly Summary Report',
            style: TextStyle(
              color: AppThemeColors.darkText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          );
          final searchWidget = SizedBox(
            width: isMobile ? double.infinity : 240,
            height: 38,
            child: TextField(
              controller: _monthlyAnalysisSearchController,
              onChanged: (val) =>
                  setState(() => _monthlyAnalysisSearchQuery = val),
              style: const TextStyle(color: _maWhite, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppThemeColors.darkCanvas,
                hintText: 'Search employee...',
                hintStyle: TextStyle(
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: AppThemeColors.darkMuted.withValues(alpha: 0.6),
                ),
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
                  borderSide: const BorderSide(color: _maPrimary),
                ),
              ),
            ),
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget,
                const SizedBox(height: 12),
                searchWidget,
              ],
            );
          }

          return Row(
            children: [
              titleWidget,
              const Spacer(),
              searchWidget,
            ],
          );
        },
      ),
    );
  }

  Widget _buildMonthlyDateSelectors() {
    final selected = _monthlyAnalysisMonth;
    return Row(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppThemeColors.darkBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selected.month,
              dropdownColor: AppThemeColors.darkSurface,
              icon: const Icon(Icons.arrow_drop_down,
                  color: AppThemeColors.darkMuted),
              style: const TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: List.generate(12, (index) {
                return DropdownMenuItem<int>(
                  value: index + 1,
                  child: Text(_kMonthlyMonths[index]),
                );
              }),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _monthlyAnalysisMonth = DateTime(selected.year, val);
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppThemeColors.darkBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selected.year,
              dropdownColor: AppThemeColors.darkSurface,
              icon: const Icon(Icons.arrow_drop_down,
                  color: AppThemeColors.darkMuted),
              style: const TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: _monthlyYearOptions.map((year) {
                return DropdownMenuItem<int>(
                  value: year,
                  child: Text(year.toString()),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _monthlyAnalysisMonth = DateTime(val, selected.month);
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  List<int> get _monthlyYearOptions {
    final currentYear = DateTime.now().year;
    return List.generate(11, (index) => currentYear - 5 + index);
  }

  List<_ManagerMonthlyRowData> _buildMonthlyRows(
    List<AttendanceModel> records,
    List<Staff> team,
    List<LeaveRequest> requests,
    DateTime month,
  ) {
    final staffByKey = <String, Staff>{};
    for (final staff in team) {
      final key = staff.employeeId.trim().isNotEmpty
          ? staff.employeeId.trim()
          : staff.id;
      staffByKey[key] = staff;
    }

    final summaries = <String, _ManagerMonthlyRowData>{};
    for (final staff in team) {
      if (staff.employeeId.trim().isEmpty) continue;
      summaries[staff.employeeId.trim()] = _ManagerMonthlyRowData(staff);
    }

    final approvedLeaves =
        requests.where((request) => request.status == 'approved').toList();
    for (final summary in summaries.values) {
      _calculateMonthlyLeavesInMonth(summary, approvedLeaves, month);
    }

    for (final record in records) {
      final employeeId = record.employeeId.trim();
      var summary = summaries[employeeId];
      if (summary == null) {
        final fallbackStaff = staffByKey[employeeId] ??
            Staff(
              id: record.employeeId,
              name: record.employeeName.trim().isEmpty
                  ? 'Unknown'
                  : record.employeeName.trim(),
              email: '',
              phone: '',
              department: '',
              position: '',
              employeeId: record.employeeId,
              joinDate: DateTime.now(),
            );
        summary = _ManagerMonthlyRowData(fallbackStaff);
        summaries[employeeId] = summary;
        _calculateMonthlyLeavesInMonth(summary, approvedLeaves, month);
      }

      if (record.countsAsAbsent) {
        summary.absentCount++;
      } else if (record.countsAsAttended) {
        summary.presentCount++;
      }
      summary.pendingMinutes += record.displayPendingMinutes;
      summary.permissionMinutes += record.permissionMinutes;
    }

    var rows = summaries.values.toList();
    final query = _monthlyAnalysisSearchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where((row) {
        return row.staff.name.toLowerCase().contains(query) ||
            row.staff.employeeId.toLowerCase().contains(query) ||
            row.staff.department.toLowerCase().contains(query);
      }).toList();
    }
    rows.sort(
        (a, b) => a.staff.name.toLowerCase().compareTo(b.staff.name.toLowerCase()));
    return rows;
  }

  void _calculateMonthlyLeavesInMonth(
    _ManagerMonthlyRowData summary,
    List<LeaveRequest> requests,
    DateTime month,
  ) {
    final empId = summary.staff.employeeId;
    for (final request in requests) {
      if (request.userId != empId && request.employeeId != empId) continue;

      final start = request.startDate;
      final end = request.endDate;
      final isPaid = request.isPaid;
      final isHalfDay = request.type.toLowerCase().contains('half');
      final paidPerRequest = request.paidDayCount;
      final unpaidPerRequest = request.unpaidDayCount;
      final requestDays = request.leaveDayCount > 0
          ? request.leaveDayCount
          : (isHalfDay
              ? (end.difference(start).inDays + 1) * 0.5
              : (end.difference(start).inDays + 1).toDouble());

      var current = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);

      while (!current.isAfter(last)) {
        if (current.month == month.month && current.year == month.year) {
          final dayValue = isHalfDay ? 0.5 : 1.0;
          if (paidPerRequest != 0 || unpaidPerRequest != 0) {
            final paidRatio =
                requestDays == 0 ? 0.0 : paidPerRequest / requestDays;
            final unpaidRatio =
                requestDays == 0 ? 0.0 : unpaidPerRequest / requestDays;
            summary.paidLeaveCount += dayValue * paidRatio;
            summary.unpaidLeaveCount += dayValue * unpaidRatio;
          } else if (isPaid) {
            summary.paidLeaveCount += dayValue;
          } else {
            summary.unpaidLeaveCount += dayValue;
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }
  }

  Widget _buildOwnRecordPage() {
    if (_isResolvingManager && _managerIdentifier == null) {
      return SizedBox(
        width: double.infinity,
        child: Container(
          margin: const EdgeInsets.only(top: 32, right: 32),
          padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ManagerDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _ManagerDashTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: CircularProgressIndicator(color: _ManagerDashTheme.primary),
          ),
        ),
      );
    }

    final employeeId = _managerEmployeeId?.trim() ?? '';
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).size.width < 800 ? 8 : 32,
          right: MediaQuery.of(context).size.width < 800 ? 0 : 32,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visibleCalendarMonth = _safeOwnRecordCalendarMonth;
            final calendar = HolidayCalendarWidget(
              visibleMonth: visibleCalendarMonth,
              selectedDate: _selectedOwnRecordDate,
              onPreviousMonth: () {
                setState(() {
                  _ownRecordCalendarMonth = DateTime(
                    visibleCalendarMonth.year,
                    visibleCalendarMonth.month - 1,
                  );
                });
              },
              onNextMonth: () {
                setState(() {
                  _ownRecordCalendarMonth = DateTime(
                    visibleCalendarMonth.year,
                    visibleCalendarMonth.month + 1,
                  );
                });
              },
              onDateSelected: (date) {
                setState(() {
                  _selectedOwnRecordDate = date;
                  _ownRecordCalendarMonth = DateTime(date.year, date.month);
                });
              },
            );
            final table = _ManagerOwnAttendanceLogTable(
              attendanceService: _attendanceService,
              employeeId: employeeId,
              title: 'Own Attendance Record',
              emptyMessage: employeeId.isEmpty
                  ? 'Manager employee ID not found.'
                  : 'No attendance records found.',
              selectedDate: _selectedOwnRecordDate,
              onClearDateFilter: _selectedOwnRecordDate == null
                  ? null
                  : () => setState(() => _selectedOwnRecordDate = null),
            );

            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  calendar,
                  const SizedBox(height: 16),
                  table,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 360, child: calendar),
                const SizedBox(width: 16),
                Expanded(child: table),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _approvalStatCard(
      {required String title, required String value, required Color color}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ManagerDashTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ManagerDashTheme.border),
        boxShadow: const [
          BoxShadow(
            color: _ManagerDashTheme.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _ManagerDashTheme.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 28, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildNotificationsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Team Notifications',
          style: TextStyle(
            color: _ManagerDashTheme.text,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Real-time overview of your team's activities and requests.",
          style: TextStyle(
            color: _ManagerDashTheme.muted,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 32),
        _ManagerNotificationsPanel(
          attendanceService: _attendanceService,
          leaveService: _leaveService,
          permissionService: PermissionService(),
          managerIdentifier: _attendanceManagerScope,
          managerEmployeeId: _managerEmployeeId,
          managerEmail: _managerDocData?['email']?.toString(),
          managerName: _managerDisplayName,
        ),
      ],
    );
  }

  // ─── MANAGER OWN REQUESTS UI AND LOGIC ──────────────────────────────────────

  Widget _buildOwnLeaveAndPermissionPage() {
    final user = _activeUser;
    final userId = user?.uid;
    if (userId == null) {
      return const Center(
          child: Text('Please log in again.',
              style: TextStyle(color: Colors.white)));
    }

    final isMobile = MediaQuery.of(context).size.width < 800;

    return Container(
      margin: EdgeInsets.only(
        top: isMobile ? 8 : 32,
        right: isMobile ? 0 : 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Title
          Text(
            'Apply Leave / Permission',
            style: TextStyle(
              color: _ManagerDashTheme.text,
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Submit a request for personal leaves or short-duration permissions and track their statuses.',
            style: TextStyle(
              color: _ManagerDashTheme.muted,
              fontSize: isMobile ? 13 : 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),

          // Custom Premium Segmented Toggles
          Container(
            decoration: BoxDecoration(
              color: _ManagerDashTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _ManagerDashTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _managerRequestSubTab = 0),
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(15)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _managerRequestSubTab == 0
                            ? _ManagerDashTheme.primary
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(15)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Apply Leave',
                        style: TextStyle(
                          color: _managerRequestSubTab == 0
                              ? Colors.white
                              : _ManagerDashTheme.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _managerRequestSubTab = 1),
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(15)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _managerRequestSubTab == 1
                            ? _ManagerDashTheme.primary
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(15)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Apply Permission',
                        style: TextStyle(
                          color: _managerRequestSubTab == 1
                              ? Colors.white
                              : _ManagerDashTheme.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Render active sub-tab view
          if (_managerRequestSubTab == 0) ...[
            // Leave Balance Summary
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

                return _responsiveTwoColumnCards([
                  _approvalStatCard(
                    title: 'Leave Balance (Remaining)',
                    value:
                        '${_leaveService.formatLeaveDays(balance.remainingDays)} Days',
                    color: _ManagerDashTheme.info,
                  ),
                  _approvalStatCard(
                    title: 'Approved Leaves',
                    value:
                        '${_leaveService.formatLeaveDays(balance.approvedDays)} Days',
                    color: _ManagerDashTheme.success,
                  ),
                ]);
              },
            ),
            const SizedBox(height: 24),

            // Form
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _ManagerDashTheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _ManagerDashTheme.border),
                boxShadow: const [
                  BoxShadow(
                    color: _ManagerDashTheme.shadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: _buildOwnLeaveForm(userId),
            ),
            const SizedBox(height: 24),

            // History
            const Text(
              'Leave History',
              style: TextStyle(
                color: _ManagerDashTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<LeaveRequest>>(
              stream: _leaveService.getRequestsForUser(userId, limit: 10),
              builder: (context, snapshot) {
                final requests = snapshot.data ?? const <LeaveRequest>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(
                          color: _ManagerDashTheme.primary),
                    ),
                  );
                }
                if (requests.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    decoration: BoxDecoration(
                      color: _ManagerDashTheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _ManagerDashTheme.border),
                    ),
                    child: const Center(
                      child: Text(
                        'No leave requests submitted yet.',
                        style: TextStyle(
                            color: _ManagerDashTheme.muted, fontSize: 14),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: _ManagerDashTheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _ManagerDashTheme.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _buildLeaveHistoryTable(requests),
                  ),
                );
              },
            ),
          ] else ...[
            // Permission Form
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _ManagerDashTheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _ManagerDashTheme.border),
                boxShadow: const [
                  BoxShadow(
                    color: _ManagerDashTheme.shadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: _buildOwnPermissionForm(userId),
            ),
            const SizedBox(height: 24),

            // History
            const Text(
              'Permission History',
              style: TextStyle(
                color: _ManagerDashTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<PermissionRequest>>(
              stream: PermissionService().getPermissionRequestsForEmployee(
                  _managerEmployeeId ?? userId),
              builder: (context, snapshot) {
                final requests = snapshot.data ?? const <PermissionRequest>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(
                          color: _ManagerDashTheme.primary),
                    ),
                  );
                }
                if (requests.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    decoration: BoxDecoration(
                      color: _ManagerDashTheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _ManagerDashTheme.border),
                    ),
                    child: const Center(
                      child: Text(
                        'No permission requests submitted yet.',
                        style: TextStyle(
                            color: _ManagerDashTheme.muted, fontSize: 14),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: _ManagerDashTheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _ManagerDashTheme.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _buildPermissionHistoryTable(requests),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOwnLeaveForm(String userId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Submit a Leave Request',
          style: TextStyle(
            color: _ManagerDashTheme.text,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final typeField = _buildDropdownField(
              label: 'Leave Type',
              value: _managerLeaveType,
              hint: 'Select Leave Type',
              items: const [
                'Sick Leave',
                'Casual Leave',
                'Half Day Leave',
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _managerLeaveType = val);
                }
              },
            );

            final dateRangeField = _buildDateRangeField(
              startDate: _managerLeaveStart,
              endDate: _managerLeaveEnd,
              onPickStart: () => _pickManagerLeaveDate(isStart: true),
              onPickEnd: () => _pickManagerLeaveDate(isStart: false),
            );

            if (compact) {
              return Column(
                children: [
                  typeField,
                  const SizedBox(height: 16),
                  dateRangeField,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: typeField),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: dateRangeField),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _buildTextInputField(
          label: 'Reason for Leave',
          controller: _managerLeaveReasonController,
          hintText: 'Please detail the reason for your time off...',
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSubmittingManagerLeave
                ? null
                : () => _submitManagerLeave(userId),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(
                _isSubmittingManagerLeave ? 'Submitting...' : 'Submit Request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _ManagerDashTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

//   Widget _buildOwnPermissionPage() {
//     final user = FirebaseAuth.instance.currentUser;
//     final userId = user?.uid;
//     if (userId == null) {
//       return const Center(
//           child: Text('Please log in again.',
//               style: TextStyle(color: Colors.white)));
//     }
//
//     final isMobile = MediaQuery.of(context).size.width < 800;
//
//     return Container(
//       margin: EdgeInsets.only(
//         top: isMobile ? 8 : 32,
//         right: isMobile ? 0 : 32,
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Apply Permission',
//             style: TextStyle(
//               color: _ManagerDashTheme.text,
//               fontSize: isMobile ? 22 : 28,
//               fontWeight: FontWeight.w800,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             'Request short-duration out-of-office permissions and view request history.',
//             style: TextStyle(
//               color: _ManagerDashTheme.muted,
//               fontSize: isMobile ? 13 : 14,
//               height: 1.6,
//             ),
//           ),
//           const SizedBox(height: 24),
//           // Form Container
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(22),
//             decoration: BoxDecoration(
//               color: _ManagerDashTheme.surface,
//               borderRadius: BorderRadius.circular(22),
//               border: Border.all(color: _ManagerDashTheme.border),
//               boxShadow: const [
//                 BoxShadow(
//                   color: _ManagerDashTheme.shadow,
//                   blurRadius: 18,
//                   offset: Offset(0, 8),
//                 ),
//               ],
//             ),
//             child: _buildOwnPermissionForm(userId),
//           ),
//           const SizedBox(height: 24),
//           // History Table
//           Text(
//             'Permission History',
//             style: TextStyle(
//               color: _ManagerDashTheme.text,
//               fontSize: 20,
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//           const SizedBox(height: 12),
//           StreamBuilder<List<PermissionRequest>>(
//             stream: PermissionService()
//                 .getPermissionRequestsForEmployee(_managerEmployeeId ?? userId),
//             builder: (context, snapshot) {
//               final requests = snapshot.data ?? const <PermissionRequest>[];
//               if (snapshot.connectionState == ConnectionState.waiting) {
//                 return const Center(
//                   child: Padding(
//                     padding: EdgeInsets.all(32.0),
//                     child: CircularProgressIndicator(
//                         color: _ManagerDashTheme.primary),
//                   ),
//                 );
//               }
//               if (requests.isEmpty) {
//                 return Container(
//                   width: double.infinity,
//                   padding: const EdgeInsets.symmetric(vertical: 48),
//                   decoration: BoxDecoration(
//                     color: _ManagerDashTheme.surface,
//                     borderRadius: BorderRadius.circular(22),
//                     border: Border.all(color: _ManagerDashTheme.border),
//                   ),
//                   child: const Center(
//                     child: Text(
//                       'No permission requests submitted yet.',
//                       style: TextStyle(
//                           color: _ManagerDashTheme.muted, fontSize: 14),
//                     ),
//                   ),
//                 );
//               }
//
//               return Container(
//                 decoration: BoxDecoration(
//                   color: _ManagerDashTheme.surface,
//                   borderRadius: BorderRadius.circular(22),
//                   border: Border.all(color: _ManagerDashTheme.border),
//                 ),
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(22),
//                   child: _buildPermissionHistoryTable(requests),
//                 ),
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }

  Widget _buildOwnPermissionForm(String userId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Submit a Permission Request',
          style: TextStyle(
            color: _ManagerDashTheme.text,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final typeField = _buildDropdownField(
              label: 'Permission Type',
              value: _managerPermissionType,
              hint: 'Select Permission Type',
              items: const ['Late Arrival', 'Medical Appointment', 'Emergency'],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _managerPermissionType = val);
                }
              },
            );

            final dateField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Date',
                  style: TextStyle(
                    color: _ManagerDashTheme.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickManagerPermissionDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: _ManagerDashTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _ManagerDashTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 16, color: _ManagerDashTheme.muted),
                        const SizedBox(width: 8),
                        Text(
                            DateFormat('MMM dd, yyyy')
                                .format(_managerPermissionDate),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                children: [
                  typeField,
                  const SizedBox(height: 16),
                  dateField,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: typeField),
                const SizedBox(width: 24),
                Expanded(child: dateField),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        // Time Pickers
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('From Time',
                      style: TextStyle(
                          color: _ManagerDashTheme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _pickManagerPermissionTime(isFrom: true),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: _ManagerDashTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _ManagerDashTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 16, color: _ManagerDashTheme.muted),
                          const SizedBox(width: 8),
                          Text(
                            _managerPermissionFrom == null
                                ? 'Select Time'
                                : DateFormat('hh:mm a')
                                    .format(_managerPermissionFrom!),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('To Time',
                      style: TextStyle(
                          color: _ManagerDashTheme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _pickManagerPermissionTime(isFrom: false),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: _ManagerDashTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _ManagerDashTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 16, color: _ManagerDashTheme.muted),
                          const SizedBox(width: 8),
                          Text(
                            _managerPermissionTo == null
                                ? 'Select Time'
                                : DateFormat('hh:mm a')
                                    .format(_managerPermissionTo!),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextInputField(
          label: 'Reason for Permission',
          controller: _managerPermissionReasonController,
          hintText: 'Please detail the reason for your out-of-office exit...',
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSubmittingManagerPermission
                ? null
                : () => _submitManagerPermission(userId),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(_isSubmittingManagerPermission
                ? 'Submitting...'
                : 'Submit Request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _ManagerDashTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _ManagerDashTheme.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _ManagerDashTheme.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value.isEmpty ? null : value,
              hint: hint == null
                  ? null
                  : Text(
                      hint,
                      style: const TextStyle(
                        color: _ManagerDashTheme.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              items: items
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ))
                  .toList(),
              onChanged: onChanged,
              dropdownColor: _ManagerDashTheme.surface,
              iconEnabledColor: _ManagerDashTheme.primary,
              isExpanded: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeField({
    required DateTime startDate,
    required DateTime endDate,
    required VoidCallback onPickStart,
    required VoidCallback onPickEnd,
  }) {
    final startStr = DateFormat('MMM dd, yyyy').format(startDate);
    final endStr = DateFormat('MMM dd, yyyy').format(endDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date Range',
          style: TextStyle(
            color: _ManagerDashTheme.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPickStart,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _ManagerDashTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ManagerDashTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: _ManagerDashTheme.muted),
                      const SizedBox(width: 8),
                      Text(startStr,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text('to', style: TextStyle(color: _ManagerDashTheme.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: onPickEnd,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _ManagerDashTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ManagerDashTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: _ManagerDashTheme.muted),
                      const SizedBox(width: 8),
                      Text(endStr,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextInputField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _ManagerDashTheme.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _ManagerDashTheme.border),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle:
                  const TextStyle(color: _ManagerDashTheme.muted, fontSize: 13),
              border: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickManagerLeaveDate({required bool isStart}) async {
    final initialDate = isStart ? _managerLeaveStart : _managerLeaveEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _managerLeaveStart = picked;
        if (_managerLeaveEnd.isBefore(_managerLeaveStart)) {
          _managerLeaveEnd = _managerLeaveStart;
        }
      } else {
        _managerLeaveEnd =
            picked.isBefore(_managerLeaveStart) ? _managerLeaveStart : picked;
      }
    });
  }

  Future<void> _submitManagerLeave(String userId) async {
    if (_managerLeaveType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a leave type.')),
      );
      return;
    }

    if (_managerLeaveReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a reason for your leave request.')),
      );
      return;
    }

    // Leave must be requested before office start on the selected date.
    final officeStart = DateTime(_managerLeaveStart.year,
        _managerLeaveStart.month, _managerLeaveStart.day, 10, 0);
    if (!DateTime.now().isBefore(officeStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Leave must be applied before office start time (10:00 AM) on the start date.')),
      );
      return;
    }

    setState(() => _isSubmittingManagerLeave = true);

    try {
      await _leaveService.submitManagerLeaveRequest(
        userId: userId,
        userName: _managerDisplayName,
        userPhotoUrl: _managerPhotoUrl,
        department: 'Management',
        type: _managerLeaveType,
        startDate: _managerLeaveStart,
        endDate: _managerLeaveEnd,
        reason: _managerLeaveReasonController.text.trim(),
        employeeId: _managerEmployeeId ?? userId,
      );

      if (!mounted) return;
      _managerLeaveReasonController.clear();
      setState(() {
        _managerLeaveType = '';
        _managerLeaveStart = DateTime.now().add(const Duration(hours: 2));
        _managerLeaveEnd = DateTime.now().add(const Duration(hours: 2));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Leave request submitted to Admin successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingManagerLeave = false);
    }
  }

  Widget _buildLeaveHistoryTable(List<LeaveRequest> requests) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(120),
          1: FixedColumnWidth(180),
          2: FixedColumnWidth(100),
          3: FixedColumnWidth(124),
          4: FixedColumnWidth(180),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              color: _ManagerDashTheme.header,
            ),
            children: [
              _buildTableHeaderCell('Type'),
              _buildTableHeaderCell('Dates'),
              _buildTableHeaderCell('Days'),
              _buildTableHeaderCell('Status'),
              _buildTableHeaderCell('Reason'),
            ],
          ),
          ...requests.map((req) {
            final days = req.endDate.difference(req.startDate).inDays + 1;
            final dateStr =
                '${DateFormat('MMM dd').format(req.startDate)} - ${DateFormat('MMM dd, yy').format(req.endDate)}';
            return TableRow(
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: _ManagerDashTheme.border)),
              ),
              children: [
                _buildTableCellText(req.type),
                _buildTableCellText(dateStr),
                _buildTableCellText('$days Day${days > 1 ? "s" : ""}'),
                _buildTableStatusCell(req.status),
                _buildTableCellText(req.reason),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _pickManagerPermissionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _managerPermissionDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _managerPermissionDate = picked;
      if (_managerPermissionFrom != null) {
        _managerPermissionFrom = DateTime(picked.year, picked.month, picked.day,
            _managerPermissionFrom!.hour, _managerPermissionFrom!.minute);
      }
      if (_managerPermissionTo != null) {
        _managerPermissionTo = DateTime(picked.year, picked.month, picked.day,
            _managerPermissionTo!.hour, _managerPermissionTo!.minute);
      }
    });
  }

  Future<void> _pickManagerPermissionTime({required bool isFrom}) async {
    final initialTime = isFrom
        ? TimeOfDay.fromDateTime(_managerPermissionFrom ?? DateTime.now())
        : TimeOfDay.fromDateTime(_managerPermissionTo ?? DateTime.now());

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked == null) return;
    setState(() {
      final dt = DateTime(
          _managerPermissionDate.year,
          _managerPermissionDate.month,
          _managerPermissionDate.day,
          picked.hour,
          picked.minute);
      if (isFrom) {
        _managerPermissionFrom = dt;
      } else {
        _managerPermissionTo = dt;
      }
    });
  }

  Future<void> _submitManagerPermission(String userId) async {
    if (_managerPermissionType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a permission type.')),
      );
      return;
    }

    if (_managerPermissionFrom == null || _managerPermissionTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both From and To times.')),
      );
      return;
    }

    if (_managerPermissionTo!.isBefore(_managerPermissionFrom!) ||
        _managerPermissionTo!.isAtSameMomentAs(_managerPermissionFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('To Time must be after From Time.')),
      );
      return;
    }

    // 1. Enforce permission start time is in the future
    if (_managerPermissionFrom!.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permission start time cannot be in the past.')),
      );
      return;
    }

    // 2. Enforce permission is within standard office hours (10:00 AM to 06:00 PM)
    final officeStart = DateTime(_managerPermissionFrom!.year,
        _managerPermissionFrom!.month, _managerPermissionFrom!.day, 10, 0);
    final officeEnd = DateTime(_managerPermissionFrom!.year,
        _managerPermissionFrom!.month, _managerPermissionFrom!.day, 18, 0);
    if (_managerPermissionFrom!.isBefore(officeStart) ||
        _managerPermissionTo!.isAfter(officeEnd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Permission must be within standard office hours (10:00 AM to 06:00 PM).')),
      );
      return;
    }

    if (_managerPermissionReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Please enter a reason for your permission request.')),
      );
      return;
    }

    setState(() => _isSubmittingManagerPermission = true);
    try {
      await PermissionService().submitPermissionRequest(
        employeeId: _managerEmployeeId ?? userId,
        employeeName: _managerDisplayName,
        department: 'Management',
        managerName: 'Admin',
        reason: _managerPermissionReasonController.text.trim(),
        permissionType: _managerPermissionType,
        isManager: true,
        requesterUserId: userId,
        date: _managerPermissionDate,
        fromTime: _managerPermissionFrom,
        toTime: _managerPermissionTo,
      );

      if (!mounted) return;
      _managerPermissionReasonController.clear();
      setState(() {
        _managerPermissionFrom = null;
        _managerPermissionTo = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Your permission request has been submitted successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingManagerPermission = false);
    }
  }

  Widget _buildPermissionHistoryTable(List<PermissionRequest> requests) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(120),
          1: FixedColumnWidth(120),
          2: FixedColumnWidth(160),
          3: FixedColumnWidth(100),
          4: FixedColumnWidth(180),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              color: _ManagerDashTheme.header,
            ),
            children: [
              _buildTableHeaderCell('Type'),
              _buildTableHeaderCell('Date'),
              _buildTableHeaderCell('Duration'),
              _buildTableHeaderCell('Status'),
              _buildTableHeaderCell('Reason'),
            ],
          ),
          ...requests.map((req) {
            final dateStr = req.date != null
                ? DateFormat('MMM dd, yyyy').format(req.date!)
                : '-';
            final timeStr = (req.fromTime != null && req.toTime != null)
                ? '${DateFormat('hh:mm a').format(req.fromTime!)} - ${DateFormat('hh:mm a').format(req.toTime!)}'
                : '-';
            return TableRow(
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: _ManagerDashTheme.border)),
              ),
              children: [
                _buildTableCellText(req.permissionType ?? 'General'),
                _buildTableCellText(dateStr),
                _buildTableCellText(timeStr),
                _buildTableStatusCell(req.status),
                _buildTableCellText(req.reason, maxLines: 2),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: _ManagerDashTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTableCellText(String text, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildTableStatusCell(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'approved':
        bg = _ManagerDashTheme.success.withValues(alpha: 0.15);
        fg = _ManagerDashTheme.success;
        break;
      case 'rejected':
        bg = _ManagerDashTheme.danger.withValues(alpha: 0.15);
        fg = _ManagerDashTheme.danger;
        break;
      default:
        bg = _ManagerDashTheme.warning.withValues(alpha: 0.15);
        fg = _ManagerDashTheme.warning;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _formatRequestStatus(status),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String _formatRequestStatus(String status) {
    final normalized = status.trim();
    if (normalized.isEmpty) return '-';
    return normalized[0].toUpperCase() + normalized.substring(1).toLowerCase();
  }

  void _showManagerProfilePopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final doc = _managerDocData;
        final activeUser = _activeUser;
        final name = doc?['name']?.toString() ?? _managerDisplayName;
        final designation = _managerDesignation;
        final email = doc?['email']?.toString() ??
            activeUser?.email ??
            'N/A';

        String joinDateStr = 'N/A';
        if (doc?['joinDate'] is Timestamp) {
          joinDateStr = DateFormat('dd MMM yyyy')
              .format((doc!['joinDate'] as Timestamp).toDate());
        } else if (doc?['createdAt'] is Timestamp) {
          joinDateStr = DateFormat('dd MMM yyyy')
              .format((doc!['createdAt'] as Timestamp).toDate());
        } else if (activeUser?.metadata.creationTime != null) {
          joinDateStr = DateFormat('dd MMM yyyy')
              .format(activeUser!.metadata.creationTime!);
        }
        final detailItems = <_ProfileDetailItem>[
          _ProfileDetailItem(Icons.email_outlined, 'Email Address', email),
          _ProfileDetailItem(
              Icons.calendar_today_outlined, 'Joined Date', joinDateStr),
          if (doc?['phone'] != null && doc!['phone'].toString().isNotEmpty)
            _ProfileDetailItem(
                Icons.phone_outlined, 'Phone Number', doc['phone'].toString()),
          if (doc?['bloodGroup'] != null &&
              doc!['bloodGroup'].toString().isNotEmpty)
            _ProfileDetailItem(Icons.bloodtype_outlined, 'Blood Group',
                doc['bloodGroup'].toString()),
          if (doc?['gender'] != null && doc!['gender'].toString().isNotEmpty)
            _ProfileDetailItem(
                Icons.transgender_outlined, 'Gender', doc['gender'].toString()),
          if (doc?['nationality'] != null &&
              doc!['nationality'].toString().isNotEmpty)
            _ProfileDetailItem(Icons.flag_outlined, 'Nationality',
                doc['nationality'].toString()),
          if (doc?['dob'] is Timestamp)
            _ProfileDetailItem(
              Icons.cake_outlined,
              'Date of Birth',
              DateFormat('dd MMM yyyy')
                  .format((doc!['dob'] as Timestamp).toDate()),
            ),
          if (doc?['address'] != null && doc!['address'].toString().isNotEmpty)
            _ProfileDetailItem(Icons.location_on_outlined, 'Address',
                doc['address'].toString()),
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
                          colors: [Color(0xFF2563EB), Color(0xFF00FFCC)],
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
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              designation.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF60A5FA),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          StatefulBuilder(
                            builder: (ctx, setInnerState) {
                              final profileImage =
                                  _managerProfileImageProvider();
                              final hasPhoto = _managerHasProfilePhoto;
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
                                              Color(0xFF2563EB),
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
                                                      : 'M',
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
                                              Icons.photo_camera_rounded,
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
                                          if (hasPhoto) ...[
                                            _profilePhotoActionButton(
                                              icon: Icons.visibility_outlined,
                                              label: 'View photo',
                                              color: const Color(0xFF60A5FA),
                                              onTap: () {
                                                Navigator.of(ctx).pop();
                                                _showManagerProfilePhotoPreview(
                                                    context);
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                          _profilePhotoActionButton(
                                            icon: Icons.photo_camera_rounded,
                                            label: hasPhoto
                                                ? 'Change photo'
                                                : 'Upload photo',
                                            color: const Color(0xFF00FFCC),
                                            onTap: _isUploadingProfilePhoto
                                                ? null
                                                : () {
                                                    Navigator.of(ctx).pop();
                                                    _pickAndUploadManagerPhoto();
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
                                                      _removeManagerPhoto();
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

  void _showManagerProfilePhotoPreview(BuildContext context) {
    final image = _managerProfileImageProvider();
    if (image == null) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image(
                      image: image,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ManagerHomeDashboard extends StatelessWidget {
  final String managerName;
  final int present;
  final int late;
  final int absent;
  final int wfh;
  final int earlyCheckouts;
  final int totalStaff;
  final int monthlyPresent;
  final int monthlyLate;
  final int monthlyAbsent;
  final int monthlyWfh;
  final int monthlyTotalRecords;
  final List<AttendanceModel> recentRecords;

  const _ManagerHomeDashboard({
    required this.managerName,
    required this.present,
    required this.late,
    required this.absent,
    required this.wfh,
    required this.earlyCheckouts,
    required this.totalStaff,
    required this.monthlyPresent,
    required this.monthlyLate,
    required this.monthlyAbsent,
    required this.monthlyWfh,
    required this.monthlyTotalRecords,
    required this.recentRecords,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ManagerHomeHeader(managerName: managerName, date: now),
        const SizedBox(height: 36),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final columns = constraints.maxWidth >= 1100
                ? 5
                : constraints.maxWidth >= 760
                    ? 3
                    : constraints.maxWidth >= 260
                        ? 2
                        : 1;
            final cardWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _ManagerSummaryCard(
                  width: cardWidth,
                  icon: Icons.groups_2_rounded,
                  label: 'Total Staff',
                  value: totalStaff,
                  caption: 'Active Employees',
                  color: const Color(0xFF7C57F5),
                  background: _ManagerDashTheme.cardBlue,
                  sparkline: const [0.15, 0.28, 0.36, 0.32, 0.48, 0.62, 0.58],
                ),
                _ManagerSummaryCard(
                  width: cardWidth,
                  icon: Icons.check_circle_rounded,
                  label: 'Present',
                  value: present,
                  caption: '${_percentage(present)}% of total',
                  color: _ManagerDashTheme.success,
                  background: _ManagerDashTheme.cardGreen,
                  sparkline: const [0.1, 0.18, 0.42, 0.36, 0.72, 0.58, 0.64],
                ),
                _ManagerSummaryCard(
                  width: cardWidth,
                  icon: Icons.schedule_rounded,
                  label: 'Late',
                  value: late,
                  caption: '${_percentage(late)}% of total',
                  color: _ManagerDashTheme.warning,
                  background: _ManagerDashTheme.cardAmber,
                  sparkline: const [0.05, 0.18, 0.3, 0.24, 0.42, 0.26, 0.2],
                ),
                _ManagerSummaryCard(
                  width: cardWidth,
                  icon: Icons.logout_rounded,
                  label: 'Early Checkout',
                  value: earlyCheckouts,
                  caption: 'Checked out before end time',
                  color: _ManagerDashTheme.warning,
                  background: _ManagerDashTheme.cardAmber,
                  sparkline: const [0.12, 0.24, 0.3, 0.16, 0.38, 0.22, 0.18],
                ),
                _ManagerSummaryCard(
                  width: cardWidth,
                  icon: Icons.person_remove_rounded,
                  label: 'Absent',
                  value: absent,
                  caption: '${_percentage(absent)}% of total',
                  color: _ManagerDashTheme.danger,
                  background: _ManagerDashTheme.cardRed,
                  sparkline: const [0.08, 0.2, 0.12, 0.34, 0.22, 0.42, 0.28],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final overview = _ManagerAttendanceOverviewCard(
              totalRecords: monthlyTotalRecords,
              present: monthlyPresent,
              late: monthlyLate,
              absent: monthlyAbsent,
              wfh: monthlyWfh,
            );
            final recent = _ManagerRecentAttendanceCard(records: recentRecords);

            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  overview,
                  const SizedBox(height: 16),
                  recent,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: overview),
                const SizedBox(width: 18),
                Expanded(child: recent),
              ],
            );
          },
        ),
      ],
    );
  }

  String _percentage(int value) {
    if (totalStaff == 0) return '0';
    return ((value / totalStaff) * 100).toStringAsFixed(2);
  }
}

class _ManagerHomeHeader extends StatelessWidget {
  final String managerName;
  final DateTime date;

  const _ManagerHomeHeader({
    required this.managerName,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = date.hour < 12
        ? 'Good morning'
        : date.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final displayName = managerName.trim().isEmpty ? 'Manager' : managerName;
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting, $displayName! 👋',
              style: TextStyle(
                color: _ManagerDashTheme.text,
                fontSize: constraints.maxWidth < 400 ? 18 : 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Here's an overview of attendance activities.",
              style: TextStyle(
                color: _ManagerDashTheme.muted,
                fontSize: constraints.maxWidth < 400 ? 13 : 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
        final chips = Wrap(
          spacing: 0,
          runSpacing: 12,
          children: [
            _ManagerDateChip(date: date),
          ],
        );

        if (constraints.maxWidth < 780) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 18),
              chips,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            chips,
          ],
        );
      },
    );
  }
}

class _ManagerDateChip extends StatelessWidget {
  final DateTime date;

  const _ManagerDateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _managerHomeCardDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.calendar_month_rounded,
                color: _ManagerDashTheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ManagerDashTheme.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  DateFormat('EEEE').format(date),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ManagerDashTheme.muted,
                    fontSize: 12,
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

class _ManagerSummaryCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final int value;
  final String caption;
  final Color color;
  final Color background;
  final List<double> sparkline;

  const _ManagerSummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.background,
    required this.sparkline,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = width < 180;
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 130),
        padding: EdgeInsets.all(isSmall ? 12 : 18),
        decoration: _managerHomeCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -4,
              width: 118,
              height: 56,
              child: CustomPaint(
                painter: _SparklinePainter(color: color, values: sparkline),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: isSmall ? 40 : 62,
                  height: isSmall ? 40 : 62,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(isSmall ? 10 : 16),
                  ),
                  child: Icon(icon, color: color, size: isSmall ? 22 : 32),
                ),
                SizedBox(width: isSmall ? 10 : 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ManagerDashTheme.muted,
                          fontSize: isSmall ? 11 : 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$value',
                        style: TextStyle(
                          color: _ManagerDashTheme.text,
                          fontSize: isSmall ? 22 : 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        caption,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ManagerDashTheme.muted,
                          fontSize: isSmall ? 10 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _ManagerAttendanceOverviewCard extends StatelessWidget {
  final int totalRecords;
  final int present;
  final int late;
  final int absent;
  final int wfh;

  const _ManagerAttendanceOverviewCard({
    required this.totalRecords,
    required this.present,
    required this.late,
    required this.absent,
    required this.wfh,
  });

  @override
  Widget build(BuildContext context) {
    final values = [
      _ManagerDonutValue('Present', present, _ManagerDashTheme.success),
      _ManagerDonutValue('Late', late, _ManagerDashTheme.warning),
      _ManagerDonutValue('Absent', absent, _ManagerDashTheme.danger),
      _ManagerDonutValue('Working From Home', wfh, const Color(0xFF7B5CF4)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _managerHomeCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance Overview (This Month)',
            style: TextStyle(
              color: _ManagerDashTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final donutSize = constraints.maxWidth < 320 ? 180.0 : 260.0;
              final paintSize = constraints.maxWidth < 320 ? 170.0 : 250.0;
              final donut = SizedBox(
                width: donutSize,
                height: donutSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(paintSize),
                      painter: _ManagerDonutPainter(values: values),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$totalRecords',
                          style: TextStyle(
                            color: _ManagerDashTheme.text,
                            fontSize: constraints.maxWidth < 320 ? 24 : 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Total Logs',
                          style: TextStyle(
                            color: _ManagerDashTheme.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              final legend = Column(
                children: values
                    .map((item) => _ManagerDonutLegend(
                          item: item,
                          total: totalRecords,
                        ))
                    .toList(),
              );

              if (constraints.maxWidth < 640) {
                return Column(
                  children: [
                    Center(child: donut),
                    const SizedBox(height: 24),
                    legend,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: Center(child: donut)),
                  const SizedBox(width: 22),
                  Expanded(child: legend),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _ManagerDashTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _ManagerDashTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    color: Color(0xFF22D3EE), size: 22),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Attendance rate this month',
                    style: TextStyle(
                      color: _ManagerDashTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_percentage(present)}%',
                  style: const TextStyle(
                    color: Color(0xFF22D3EE),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _percentage(int value) {
    if (totalRecords == 0) return '0';
    return ((value / totalRecords) * 100).toStringAsFixed(2);
  }
}

class _ManagerRecentAttendanceCard extends StatelessWidget {
  final List<AttendanceModel> records;

  const _ManagerRecentAttendanceCard({required this.records});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _managerHomeCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Attendance Log',
                  style: TextStyle(
                    color: _ManagerDashTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'View All',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 78),
              child: Center(
                child: Text(
                  'No attendance records yet.',
                  style: TextStyle(color: _ManagerDashTheme.muted),
                ),
              ),
            )
          else
            Column(
              children: records
                  .map((record) => _ManagerRecentAttendanceRow(record: record))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ManagerRecentAttendanceRow extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerRecentAttendanceRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final color = switch (record.status) {
      AttendanceStatus.present => _ManagerDashTheme.success,
      AttendanceStatus.late => _ManagerDashTheme.warning,
      AttendanceStatus.absent => _ManagerDashTheme.danger,
      AttendanceStatus.wfh => _ManagerDashTheme.info,
      AttendanceStatus.leave => _ManagerDashTheme.info,
    };
    final action = record.isCheckedOut ? 'Checked out' : 'Checked in';
    final time = record.isCheckedOut
        ? record.checkOutFormatted
        : record.checkInFormatted;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 800;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _ManagerDashTheme.border)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: isNarrow ? 16 : 18,
            backgroundColor: color,
            child: Text(
              _initial(record.employeeName),
              style: TextStyle(
                color: Colors.white,
                fontSize: isNarrow ? 12 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: isNarrow ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.employeeName.isEmpty
                      ? 'Staff Member'
                      : record.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ManagerDashTheme.text,
                    fontSize: isNarrow ? 13 : 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$action · $time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ManagerDashTheme.muted,
                    fontSize: isNarrow ? 11 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (record.isEarlyCheckout)
            const _ManagerRecentStatusPill(
              label: 'Early checkout',
              color: _ManagerDashTheme.warning,
            ),
          const SizedBox(width: 8),
          _ManagerRecentStatusPill(label: record.statusLabel, color: color),
        ],
      ),
    );
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'S' : trimmed[0].toUpperCase();
  }
}

class _ManagerRecentStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _ManagerRecentStatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ManagerDonutValue {
  final String label;
  final int value;
  final Color color;

  const _ManagerDonutValue(this.label, this.value, this.color);
}

class _ManagerDonutLegend extends StatelessWidget {
  final _ManagerDonutValue item;
  final int total;

  const _ManagerDonutLegend({
    required this.item,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent =
        total == 0 ? '0' : ((item.value / total) * 100).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration:
                BoxDecoration(color: item.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              item.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ManagerDashTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${item.value} ($percent%)',
            style: const TextStyle(
              color: _ManagerDashTheme.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerDonutPainter extends CustomPainter {
  final List<_ManagerDonutValue> values;

  const _ManagerDonutPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final total =
        values.fold<int>(0, (totalSum, item) => totalSum + item.value);
    final stroke = size.width * 0.35;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    if (total == 0) {
      paint.color = _ManagerDashTheme.border;
      canvas.drawCircle(
          size.center(Offset.zero), (size.width - stroke) / 2, paint);
      return;
    }

    var start = -1.5708;
    for (final item in values) {
      if (item.value == 0) continue;
      final sweep = (item.value / total) * 6.28318;
      paint.color = item.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _ManagerDonutPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  final List<double> values;

  const _SparklinePainter({
    required this.color,
    required this.values,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - (values[i].clamp(0.0, 1.0) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.values != values;
  }
}

BoxDecoration _managerHomeCardDecoration() {
  return BoxDecoration(
    color: _ManagerDashTheme.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: _ManagerDashTheme.border),
    boxShadow: const [
      BoxShadow(
        color: _ManagerDashTheme.shadow,
        blurRadius: 22,
        offset: Offset(0, 10),
      ),
    ],
  );
}

class _ManagerBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Future<void> Function() onLogout;

  const _ManagerBottomNavigation({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          gradient: _ManagerDashTheme.sidebarGradient,
          boxShadow: [
            BoxShadow(
              color: Color(0x332F66F6),
              blurRadius: 20,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: [
            _ManagerBottomNavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: selectedIndex == 0,
              onPressed: () => onItemSelected(0),
            ),
            _ManagerBottomNavItem(
              icon: Icons.calendar_month_rounded,
              label: 'Log',
              selected: selectedIndex == 1,
              onPressed: () => onItemSelected(1),
            ),
            _ManagerBottomNavItem(
              icon: Icons.badge_rounded,
              label: 'Own',
              selected: selectedIndex == 2,
              onPressed: () => onItemSelected(2),
            ),
            _ManagerBottomNavItem(
              icon: Icons.request_page_rounded,
              label: 'Leave',
              selected: selectedIndex == 3,
              onPressed: () => onItemSelected(3),
            ),
            _ManagerBottomNavItem(
              icon: Icons.fact_check_outlined,
              label: 'Approvals',
              selected: selectedIndex == 10,
              onPressed: () => onItemSelected(10),
            ),
            _ManagerBottomNavItem(
              icon: Icons.people_alt_rounded,
              label: 'Team',
              selected: selectedIndex == 5,
              onPressed: () => onItemSelected(5),
            ),
            _ManagerBottomNavItem(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan QR',
              selected: selectedIndex == 6,
              onPressed: () => onItemSelected(6),
            ),
            _ManagerBottomNavItem(
              icon: Icons.notifications_active_rounded,
              label: 'Alerts',
              selected: selectedIndex == 7,
              onPressed: () => onItemSelected(7),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerBottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool danger;

  const _ManagerBottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  }) : danger = false;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? Colors.white
        : selected
            ? Colors.white
            : Colors.white.withValues(alpha: 0.78);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? AppThemeColors.actionEnd : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 58,
              decoration: danger
                  ? BoxDecoration(
                      gradient: _ManagerDashTheme.actionGradient,
                      borderRadius: BorderRadius.circular(14),
                    )
                  : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 21),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 10,
                      fontWeight: selected || danger
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagerSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Future<void> Function() onLogout;
  final String managerName;
  final String managerDesignation;
  final String? photoUrl;
  final bool isUploadingPhoto;
  final VoidCallback onUploadPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onProfileTap;

  const _ManagerSidebar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
    required this.managerName,
    required this.managerDesignation,
    required this.photoUrl,
    required this.isUploadingPhoto,
    required this.onUploadPhoto,
    required this.onRemovePhoto,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 16),
      decoration: const BoxDecoration(
        gradient: _ManagerDashTheme.sidebarGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x332F66F6),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ManagerBrandHeader(
                    managerName: managerName,
                    managerDesignation: managerDesignation,
                    photoUrl: photoUrl,
                    isUploadingPhoto: isUploadingPhoto,
                    onUploadPhoto: onUploadPhoto,
                    onRemovePhoto: onRemovePhoto,
                    onProfileTap: onProfileTap,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'MANAGER MENU',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SidebarNavItem(
                    icon: Icons.home_rounded,
                    label: 'Analytics',
                    selected: selectedIndex == 0,
                    onPressed: () => onItemSelected(0),
                  ),
                  _ExpandableNavGroup(
                    icon: Icons.calendar_month_rounded,
                    label: 'Attendance Monitoring',
                    active: selectedIndex == 1 || selectedIndex == 9,
                    children: [
                      _SidebarNavItem(
                        icon: Icons.receipt_long_rounded,
                        label: 'Attendance Log',
                        selected: selectedIndex == 1,
                        onPressed: () => onItemSelected(1),
                      ),
                      _SidebarNavItem(
                        icon: Icons.bar_chart_rounded,
                        label: 'Monthly Analysis',
                        selected: selectedIndex == 9,
                        onPressed: () => onItemSelected(9),
                      ),
                    ],
                  ),
                  _SidebarNavItem(
                    icon: Icons.badge_rounded,
                    label: 'Own Record',
                    selected: selectedIndex == 2,
                    onPressed: () => onItemSelected(2),
                  ),
                  _SidebarNavItem(
                    icon: Icons.inbox_rounded,
                    label: 'Requests',
                    selected: selectedIndex == 3,
                    onPressed: () => onItemSelected(3),
                  ),
                  _SidebarNavItem(
                    icon: Icons.fact_check_outlined,
                    label: 'Approve Requests',
                    selected: selectedIndex == 10,
                    onPressed: () => onItemSelected(10),
                  ),
                  _SidebarNavItem(
                    icon: Icons.people_alt_rounded,
                    label: 'Team Members',
                    selected: selectedIndex == 5,
                    onPressed: () => onItemSelected(5),
                  ),
                  _SidebarNavItem(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan QR',
                    selected: selectedIndex == 6,
                    onPressed: () => onItemSelected(6),
                  ),
                  _SidebarNavItem(
                    icon: Icons.notifications_active_rounded,
                    label: 'Notifications',
                    selected: selectedIndex == 7,
                    onPressed: () => onItemSelected(7),
                  ),
                  _SidebarNavItem(
                    icon: Icons.assignment_turned_in_rounded,
                    label: 'Apply Leave / Permission',
                    selected: selectedIndex == 8,
                    onPressed: () => onItemSelected(8),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                decoration: BoxDecoration(
                  gradient: _ManagerDashTheme.actionGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33FF3D4F),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.power_settings_new_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('Logout',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableNavGroup extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final List<Widget> children;

  const _ExpandableNavGroup({
    required this.icon,
    required this.label,
    required this.active,
    required this.children,
  });

  @override
  State<_ExpandableNavGroup> createState() => _ExpandableNavGroupState();
}

class _ExpandableNavGroupState extends State<_ExpandableNavGroup> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.active;
  }

  @override
  void didUpdateWidget(_ExpandableNavGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SidebarSectionHeader(
          icon: widget.icon,
          label: widget.label,
          expanded: _expanded,
          highlighted: widget.active,
          onPressed: () => setState(() => _expanded = !_expanded),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool expanded;
  final bool highlighted;
  final VoidCallback onPressed;

  const _SidebarSectionHeader({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.highlighted,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: highlighted ? AppThemeColors.actionEnd : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: highlighted
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
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

class _ManagerBrandHeader extends StatelessWidget {
  final String managerName;
  final String managerDesignation;
  final String? photoUrl;
  final bool isUploadingPhoto;
  final VoidCallback onUploadPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onProfileTap;

  const _ManagerBrandHeader({
    required this.managerName,
    required this.managerDesignation,
    required this.photoUrl,
    required this.isUploadingPhoto,
    required this.onUploadPhoto,
    required this.onRemovePhoto,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ManagerProfilePhoto(
          managerName: managerName,
          photoUrl: photoUrl,
          isUploading: isUploadingPhoto,
          onUpload: onUploadPhoto,
          onRemove: onRemovePhoto,
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
                    managerName.trim().isEmpty ? 'Manager' : managerName.trim(),
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
                    managerDesignation.trim().isEmpty
                        ? 'Manager'
                        : managerDesignation.trim(),
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
}

class _ManagerProfilePhoto extends StatelessWidget {
  final String managerName;
  final String? photoUrl;
  final bool isUploading;
  final VoidCallback onUpload;
  final VoidCallback onRemove;

  const _ManagerProfilePhoto({
    required this.managerName,
    required this.photoUrl,
    required this.isUploading,
    required this.onUpload,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final initial = managerName.trim().isEmpty
        ? 'M'
        : managerName.trim().characters.first.toUpperCase();
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;
    final photoBytes = _decodeDataImage(photoUrl);
    ImageProvider? profileImage;
    if (photoBytes != null) {
      profileImage = MemoryImage(photoBytes);
    } else if (hasPhoto) {
      profileImage = NetworkImage(photoUrl!.trim());
    }

    return Tooltip(
      message:
          hasPhoto ? 'Update or remove manager photo' : 'Upload manager photo',
      child: InkWell(
        onTap: isUploading
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
              child: hasPhoto
                  ? null
                  : Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
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
                  color: AppThemeColors.actionEnd,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: isUploading
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

    if (action == 'update') onUpload();
    if (action == 'remove') onRemove();
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

class _AttendanceSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const _AttendanceSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ManagerDashTheme.primary),
            boxShadow: const [
              BoxShadow(
                color: _ManagerDashTheme.shadow,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            cursorColor: _ManagerDashTheme.primary,
            style: const TextStyle(
              color: _ManagerDashTheme.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Search by employee name...',
              hintStyle: const TextStyle(
                color: _ManagerDashTheme.muted,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: _ManagerDashTheme.primary,
              ),
              suffixIcon: onClear == null
                  ? null
                  : IconButton(
                      onPressed: onClear,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: _ManagerDashTheme.primary,
                      ),
                    ),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// internal holiday panel removed

class _ManagerAttendanceLogTable extends StatelessWidget {
  final AttendanceService attendanceService;
  final String managerIdentifier;
  final String title;
  final String emptyMessage;
  final DateTime? selectedDate;
  final String searchQuery;
  final VoidCallback? onClearDateFilter;

  const _ManagerAttendanceLogTable({
    required this.attendanceService,
    required this.managerIdentifier,
    required this.title,
    required this.emptyMessage,
    this.selectedDate,
    this.searchQuery = '',
    this.onClearDateFilter,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceModel>>(
      stream: attendanceService.getAttendanceHistoryStreamByManager(
        managerIdentifier,
        limit: selectedDate == null ? 50 : null,
      ),
      builder: (context, snapshot) {
        final allRecords = snapshot.data ?? const <AttendanceModel>[];
        final normalizedSearch = searchQuery.trim().toLowerCase();
        final records = allRecords.where((record) {
          final matchesDate =
              selectedDate == null || _isSameDate(record.date, selectedDate!);
          final matchesName = normalizedSearch.isEmpty ||
              record.displayEmployeeName
                  .toLowerCase()
                  .contains(normalizedSearch);
          return matchesDate && matchesName;
        }).toList();
        final dateFilterLabel = selectedDate == null
            ? null
            : DateFormat('dd/MM/yyyy').format(selectedDate!);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ManagerDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _ManagerDashTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, tableConstraints) {
              final isMobileTable = tableConstraints.maxWidth < 600;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobileTable ? 16 : 26,
                      isMobileTable ? 16 : 28,
                      isMobileTable ? 16 : 26,
                      isMobileTable ? 12 : 24,
                    ),
                    child: isMobileTable
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dateFilterLabel == null)
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: const TextStyle(
                                    color: _ManagerDashTheme.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _ManagerDashTheme.primary
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Date: $dateFilterLabel',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _ManagerDashTheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (onClearDateFilter != null) ...[
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: onClearDateFilter,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            color: _ManagerDashTheme.primary,
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _ManagerDashTheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${records.length} records',
                                  style: const TextStyle(
                                    color: _ManagerDashTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ExportDropdown(
                                records: records,
                                fileNamePrefix: 'Manager_Attendance',
                                primaryColorOverride: _ManagerDashTheme.primary,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              if (dateFilterLabel == null)
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: const TextStyle(
                                      color: _ManagerDashTheme.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _ManagerDashTheme.primary
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Filtered by date: $dateFilterLabel',
                                        style: const TextStyle(
                                          color: _ManagerDashTheme.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (onClearDateFilter != null) ...[
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: onClearDateFilter,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            color: _ManagerDashTheme.primary,
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (dateFilterLabel != null) const Spacer(),
                              ExportDropdown(
                                records: records,
                                fileNamePrefix: 'Manager_Attendance',
                                primaryColorOverride: _ManagerDashTheme.primary,
                              ),
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _ManagerDashTheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  '${records.length} records found',
                                  style: const TextStyle(
                                    color: _ManagerDashTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (!isMobileTable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: _ManagerDashTheme.header,
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: _ManagerDashTheme.border,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          _ManagerTableHeader('EMPLOYEE', flex: 24),
                          _ManagerTableHeader('DATE', flex: 14),
                          _ManagerTableHeader('DESIG.', flex: 16),
                          _ManagerTableHeader('STATUS', flex: 15),
                          _ManagerTableHeader('IN', flex: 13),
                          _ManagerTableHeader('OUT', flex: 13),
                          _ManagerTableHeader('WORK HR', flex: 16),
                          _ManagerTableHeader('PEND HR', flex: 15),
                          _ManagerTableHeader('ABS/PRES', flex: 16),
                          _ManagerTableHeader('PERMISSION', flex: 18),
                        ],
                      ),
                    ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _ManagerDashTheme.primary,
                        ),
                      ),
                    )
                  else if (records.isEmpty)
                    SizedBox(
                      height: 152,
                      child: Center(
                        child: Text(
                          emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                _ManagerDashTheme.muted.withValues(alpha: 0.75),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    isMobileTable
                        ? ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: records.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: _ManagerDashTheme.border,
                            ),
                            itemBuilder: (context, index) =>
                                _ManagerAttendanceMobileCard(
                                    record: records[index]),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: records.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: _ManagerDashTheme.border,
                            ),
                            itemBuilder: (context, index) =>
                                _ManagerAttendanceRow(record: records[index]),
                          ),
                ],
              );
            },
          ),
        );
      },
    );
  }

//   Widget _buildExportButton({
//     required BuildContext context,
//     required bool enabled,
//     bool compact = false,
//   }) {
//     final disabledColor =
//         _ManagerDashTheme.muted.withAlpha((255 * 0.55).round());
//
//     return OutlinedButton(
//       style: OutlinedButton.styleFrom(
//         side: BorderSide(
//           color: enabled ? _ManagerDashTheme.primary : _ManagerDashTheme.border,
//         ),
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(8),
//         ),
//         padding: EdgeInsets.symmetric(
//           horizontal: compact ? 12 : 16,
//           vertical: compact ? 9 : 10,
//         ),
//       ),
//       onPressed: enabled ? () => _exportAttendance(context) : null,
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(
//             Icons.upload_rounded,
//             color: enabled ? _ManagerDashTheme.primary : disabledColor,
//             size: 19,
//           ),
//           const SizedBox(width: 6),
//           Text(
//             'Export',
//             style: TextStyle(
//               color: enabled ? _ManagerDashTheme.primary : disabledColor,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//           const SizedBox(width: 4),
//           Icon(
//             Icons.keyboard_arrow_down_rounded,
//             color: enabled ? _ManagerDashTheme.primary : disabledColor,
//             size: 20,
//           ),
//         ],
//       ),
//     );
//   }

//   Future<void> _exportAttendance(BuildContext context) async {
//     try {
//       final normalizedSearch = searchQuery.trim().toLowerCase();
//       final fetchedRecords =
//           await attendanceService.getAttendanceHistoryByManager(
//         managerIdentifier,
//         date: selectedDate,
//       );
//       final records = fetchedRecords.where((record) {
//         return normalizedSearch.isEmpty ||
//             record.displayEmployeeName.toLowerCase().contains(normalizedSearch);
//       }).toList();
//
//       if (records.isEmpty) {
//         if (context.mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(
//               content: Text('No attendance records available to export.'),
//             ),
//           );
//         }
//         return;
//       }
//
//       final csvData = <List<dynamic>>[
//         [
//           'Employee',
//           'Emp ID',
//           'Date',
//           'Designation',
//           'Status',
//           'Check-In',
//           'Check-Out',
//           'Working Hr',
//           'Pending Hr',
//           'Absence',
//         ],
//         ...records.map((record) => [
//               record.displayEmployeeName,
//               record.displayEmployeeId,
//               DateFormat('dd/MM/yyyy').format(record.date),
//               record.displayDepartment,
//               record.statusLabel,
//               record.checkInTime == null
//                   ? ''
//                   : DateFormat('HH:mm').format(record.checkInTime!),
//               record.checkOutTime == null ? '' : record.checkOutFormatted,
//               record.storedWorkingHours ?? record.workingHoursFormatted,
//               record.pendingHoursFormatted,
//               record.pendingAbsenceLabel,
//               record.permissionActivityLabel,
//             ]),
//       ];
//
//       final csv = const ListToCsvConverter().convert(csvData);
//       final bytes = Uint8List.fromList(csv.codeUnits);
//       final suffix = selectedDate == null
//           ? 'overall'
//           : DateFormat('yyyyMMdd').format(selectedDate!);
//       await FileSaver.instance.saveFile(
//         name:
//             'manager_attendance_${suffix}_${DateFormat('HHmmss').format(DateTime.now())}',
//         bytes: bytes,
//         ext: 'csv',
//         mimeType: MimeType.csv,
//       );
//
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Attendance report exported successfully.'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       }
//     } catch (e) {
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Export failed: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _ManagerOwnAttendanceLogTable extends StatelessWidget {
  final AttendanceService attendanceService;
  final String employeeId;
  final String title;
  final String emptyMessage;
  final DateTime? selectedDate;
  final VoidCallback? onClearDateFilter;

  const _ManagerOwnAttendanceLogTable({
    required this.attendanceService,
    required this.employeeId,
    required this.title,
    required this.emptyMessage,
    this.selectedDate,
    this.onClearDateFilter,
  });

  @override
  Widget build(BuildContext context) {
    if (employeeId.isEmpty) {
      return _ManagerEmptyAttendanceShell(message: emptyMessage);
    }

    return StreamBuilder<List<AttendanceModel>>(
      stream:
          attendanceService.getAttendanceHistoryStream(employeeId, limit: null),
      builder: (context, snapshot) {
        final records = (snapshot.data ?? const <AttendanceModel>[])
            .where((record) =>
                selectedDate == null ||
                _isSameRecordDate(record.date, selectedDate!))
            .toList();
        final dateFilterLabel = selectedDate == null
            ? null
            : DateFormat('dd/MM/yyyy').format(selectedDate!);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _ManagerDashTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ManagerDashTheme.border),
            boxShadow: const [
              BoxShadow(
                color: _ManagerDashTheme.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, tableConstraints) {
              final isMobileTable = tableConstraints.maxWidth < 600;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobileTable ? 16 : 26,
                      isMobileTable ? 16 : 28,
                      isMobileTable ? 16 : 26,
                      isMobileTable ? 12 : 24,
                    ),
                    child: isMobileTable
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dateFilterLabel == null
                                          ? title
                                          : 'Filtered by date: $dateFilterLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: dateFilterLabel == null
                                            ? _ManagerDashTheme.text
                                            : _ManagerDashTheme.primary,
                                        fontSize:
                                            dateFilterLabel == null ? 16 : 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (onClearDateFilter != null)
                                    IconButton(
                                      tooltip: 'Clear date filter',
                                      onPressed: onClearDateFilter,
                                      icon: const Icon(Icons.close_rounded),
                                      color: _ManagerDashTheme.primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (records.isNotEmpty)
                                    ExportDropdown(
                                      records: records,
                                      fileNamePrefix: 'Manager_Own_Attendance',
                                      primaryColorOverride:
                                          _ManagerDashTheme.primary,
                                    ),
                                  _ManagerRecordCountBadge(
                                      count: records.length),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dateFilterLabel == null
                                      ? title
                                      : 'Filtered by date: $dateFilterLabel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: dateFilterLabel == null
                                        ? _ManagerDashTheme.text
                                        : _ManagerDashTheme.primary,
                                    fontSize: dateFilterLabel == null ? 16 : 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (onClearDateFilter != null)
                                IconButton(
                                  tooltip: 'Clear date filter',
                                  onPressed: onClearDateFilter,
                                  icon: const Icon(Icons.close_rounded),
                                  color: _ManagerDashTheme.primary,
                                ),
                              if (records.isNotEmpty) ...[
                                ExportDropdown(
                                  records: records,
                                  fileNamePrefix: 'Manager_Own_Attendance',
                                  primaryColorOverride:
                                      _ManagerDashTheme.primary,
                                ),
                                const SizedBox(width: 12),
                              ],
                              _ManagerRecordCountBadge(count: records.length),
                            ],
                          ),
                  ),
                  if (!isMobileTable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 18,
                      ),
                      decoration: const BoxDecoration(
                        color: _ManagerDashTheme.header,
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: _ManagerDashTheme.border,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          _ManagerTableHeader('EMPLOYEE', flex: 30),
                          _ManagerTableHeader('DATE', flex: 20),
                          _ManagerTableHeader('DESIGNATION', flex: 20),
                          _ManagerTableHeader('STATUS', flex: 20),
                          _ManagerTableHeader('CHECK-IN', flex: 15),
                          _ManagerTableHeader('CHECK-OUT', flex: 15),
                          _ManagerTableHeader('WORKING HR', flex: 18),
                          _ManagerTableHeader('PENDING HR', flex: 16),
                          _ManagerTableHeader('ABSENT / PRESENT', flex: 16),
                          _ManagerTableHeader('PERMISSION', flex: 22),
                        ],
                      ),
                    ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _ManagerDashTheme.primary,
                        ),
                      ),
                    )
                  else if (records.isEmpty)
                    SizedBox(
                      height: 152,
                      child: Center(
                        child: Text(
                          emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                _ManagerDashTheme.muted.withValues(alpha: 0.75),
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
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: _ManagerDashTheme.border,
                      ),
                      itemBuilder: (context, index) => isMobileTable
                          ? _ManagerAttendanceMobileCard(record: records[index])
                          : _ManagerAttendanceRow(record: records[index]),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  bool _isSameRecordDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _ManagerEmptyAttendanceShell extends StatelessWidget {
  final String message;

  const _ManagerEmptyAttendanceShell({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
      decoration: BoxDecoration(
        color: _ManagerDashTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _ManagerDashTheme.border),
        boxShadow: const [
          BoxShadow(
            color: _ManagerDashTheme.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            color: _ManagerDashTheme.muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ManagerTableHeader extends StatelessWidget {
  final String label;
  final int flex;

  const _ManagerTableHeader(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _ManagerDashTheme.muted.withValues(alpha: 0.78),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ManagerAttendanceRow extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerAttendanceRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AttendanceService()
          .isEmployeeOnApprovedLeave(record.employeeId, record.date),
      builder: (context, snapshot) {
        final isOnLeave = snapshot.data == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                flex: 24,
                child: Row(
                  children: [
                    _ManagerAttendanceAvatar(record: record, radius: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.displayEmployeeName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ManagerDashTheme.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.05,
                            ),
                          ),
                          Text(
                            record.displayEmployeeId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ManagerDashTheme.muted
                                  .withValues(alpha: 0.8),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 14,
                child: _ManagerCellText(record.dateFormatted),
              ),
              Expanded(
                flex: 16,
                child: _ManagerCellText(record.displayDepartment),
              ),
              Expanded(
                flex: 15,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: isOnLeave
                      ? const SizedBox.shrink()
                      : _ManagerStatusBadge(record: record),
                ),
              ),
              Expanded(
                flex: 13,
                child: isOnLeave
                    ? const SizedBox.shrink()
                    : _ManagerCellText(
                        record.checkInFormatted,
                        color: _checkInColor(record),
                        fontWeight: FontWeight.w600,
                      ),
              ),
              Expanded(
                flex: 13,
                child: isOnLeave
                    ? const SizedBox.shrink()
                    : _ManagerCellText(
                        record.checkOutFormatted,
                        color: record.isCheckedOut
                            ? _ManagerDashTheme.primary
                            : _ManagerDashTheme.muted,
                        fontWeight: FontWeight.w600,
                      ),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave
                    ? const SizedBox.shrink()
                    : _ManagerCellText(
                        record.workingHoursFormatted,
                        color: record.workingDuration == null
                            ? _ManagerDashTheme.muted.withValues(alpha: 0.75)
                            : _ManagerDashTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
              ),
              Expanded(
                flex: 15,
                child: isOnLeave
                    ? const SizedBox.shrink()
                    : _ManagerPendingText(record: record),
              ),
              Expanded(
                flex: 16,
                child: isOnLeave
                    ? const _ManagerCellText(
                        'Absent',
                        color: _ManagerDashTheme.danger,
                        fontWeight: FontWeight.w700,
                      )
                    : _ManagerPendingAbsenceText(record: record),
              ),
              Expanded(
                flex: 18,
                child: isOnLeave
                    ? const SizedBox.shrink()
                    : _ManagerPermissionActivityText(record: record),
              ),
            ],
          ),
        );
      },
    );
  }

//   String _initials(String name) {
//     final parts = name.trim().split(' ');
//     return parts
//         .map((part) => part.isNotEmpty ? part[0] : '')
//         .take(2)
//         .join()
//         .toUpperCase();
//   }

//   Color _avatarColor(String name) {
//     const colors = [
//       Color(0xFF5B6EF5),
//       _ManagerDashTheme.success,
//       _ManagerDashTheme.warning,
//       _ManagerDashTheme.danger,
//       _ManagerDashTheme.info,
//     ];
//     return colors[name.length % colors.length];
//   }

  Color _checkInColor(AttendanceModel record) {
    switch (record.arrivalBand) {
      case 'green':
        return _ManagerDashTheme.success;
      case 'orange':
        return _ManagerDashTheme.warning;
      case 'red':
        return _ManagerDashTheme.danger;
      case 'blue':
        return _ManagerDashTheme.info;
      default:
        return _ManagerDashTheme.muted;
    }
  }
}

class _ManagerStatusBadge extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerStatusBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    final label = _managerStatusLabel(record);
    if (label.isEmpty) return const SizedBox.shrink();
    final foreground = _managerStatusColor(record);
    final icon = _managerStatusIcon(record);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground, size: 10),
            const SizedBox(width: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _managerStatusLabel(AttendanceModel record) {
  if (record.policyAction == 'half_day_leave') return 'Half Day';
  if (record.statusLabel == 'Leave') return 'Leave';
  if (record.countsAsAbsent || record.statusLabel == 'Absent') return 'Absent';
  if (record.countsAsLate) return 'Late';
  if (record.countsAsPresent || record.checkInTime != null) return 'Present';
  return '';
}

Color _managerStatusColor(AttendanceModel record) {
  if (record.policyAction == 'half_day_leave') return const Color(0xFF22D3EE);
  if (record.statusLabel == 'Leave') return const Color(0xFF38BDF8);
  if (record.countsAsAbsent || record.statusLabel == 'Absent') {
    return _ManagerDashTheme.danger;
  }
  if (record.countsAsLate) return _ManagerDashTheme.warning;
  return _ManagerDashTheme.success;
}

IconData _managerStatusIcon(AttendanceModel record) {
  if (record.policyAction == 'half_day_leave' ||
      record.statusLabel == 'Leave') {
    return Icons.event_available_rounded;
  }
  if (record.countsAsAbsent || record.statusLabel == 'Absent') {
    return Icons.cancel_outlined;
  }
  if (record.countsAsLate) return Icons.access_time;
  return Icons.check;
}

class _ManagerCellText extends StatelessWidget {
  final String value;
  final Color? color;
  final FontWeight fontWeight;

  const _ManagerCellText(
    this.value, {
    this.color,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? _ManagerDashTheme.muted,
          fontSize: 11.5,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
    );
  }
}

class _ManagerAttendanceMobileCard extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerAttendanceMobileCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ManagerAttendanceAvatar(record: record, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.displayEmployeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ManagerDashTheme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      record.displayEmployeeId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ManagerDashTheme.muted.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ManagerStatusBadge(record: record),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _mobileMeta('Date', record.dateFormatted),
              _mobileMeta('Designation', record.displayDepartment),
              _mobileMeta('Check-in', record.checkInFormatted),
              _mobileMeta('Check-out', record.checkOutFormatted),
              _mobileMeta('Working Hr', record.workingHoursFormatted),
              _mobileMeta('Pending Hr', record.pendingHoursFormatted),
              _mobileMeta(
                'Absence',
                record.pendingAbsenceLabel,
                valueColor: _absenceLabelColor(record.pendingAbsenceLabel),
              ),
              _mobileMeta('Permission', record.permissionActivityLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileMeta(String label, String value, {Color? valueColor}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              color: _ManagerDashTheme.muted.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: valueColor ?? _ManagerDashTheme.text,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

//   String _initials(String name) {
//     final parts = name.trim().split(' ');
//     return parts
//         .map((part) => part.isNotEmpty ? part[0] : '')
//         .take(2)
//         .join()
//         .toUpperCase();
//   }

//   Color _avatarColor(String name) {
//     const colors = [
//       Color(0xFF5B6EF5),
//       _ManagerDashTheme.success,
//       _ManagerDashTheme.warning,
//       _ManagerDashTheme.danger,
//       _ManagerDashTheme.info,
//     ];
//     return colors[name.length % colors.length];
//   }

  Color _absenceLabelColor(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('absent')) return _ManagerDashTheme.danger;
    if (normalized.contains('late')) return _ManagerDashTheme.warning;
    if (normalized.contains('leave')) return const Color(0xFF38BDF8);
    if (normalized.contains('present') || normalized == 'none') {
      return _ManagerDashTheme.success;
    }
    return _ManagerDashTheme.text;
  }
}

class _ManagerPendingText extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerPendingText({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasPending = record.displayPendingMinutes > 0;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        record.pendingHoursFormatted,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color:
              hasPending ? _ManagerDashTheme.danger : _ManagerDashTheme.success,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ManagerRecordCountBadge extends StatelessWidget {
  final int count;

  const _ManagerRecordCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: _ManagerDashTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '$count records found',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: _ManagerDashTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ManagerAttendanceAvatar extends StatelessWidget {
  final AttendanceModel record;
  final double radius;

  const _ManagerAttendanceAvatar({
    required this.record,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final photoBytes = record.employeePhotoBytes;
    final photoUrl = record.employeePhotoUrl?.trim();
    final hasNetworkPhoto = photoUrl != null &&
        photoUrl.isNotEmpty &&
        !photoUrl.startsWith('data:image');
    ImageProvider? profileImage;
    if (photoBytes != null) {
      profileImage = MemoryImage(photoBytes);
    } else if (hasNetworkPhoto) {
      profileImage = NetworkImage(photoUrl);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: record.identityCleared
          ? _ManagerDashTheme.header
          : _avatarColor(record.employeeName),
      backgroundImage: profileImage,
      child: record.identityCleared || photoBytes != null || hasNetworkPhoto
          ? null
          : Text(
              _initials(record.employeeName),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius <= 16 ? 10 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    return parts
        .map((part) => part.isNotEmpty ? part[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF5B6EF5),
      _ManagerDashTheme.success,
      _ManagerDashTheme.warning,
      _ManagerDashTheme.danger,
      _ManagerDashTheme.info,
    ];
    return colors[name.length % colors.length];
  }
}

class _ManagerPendingAbsenceText extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerPendingAbsenceText({required this.record});

  @override
  Widget build(BuildContext context) {
    final normalized = record.pendingAbsenceLabel.toLowerCase();
    final color = normalized.contains('absent')
        ? _ManagerDashTheme.danger
        : normalized.contains('late')
            ? _ManagerDashTheme.warning
            : normalized.contains('leave')
                ? const Color(0xFF38BDF8)
                : _ManagerDashTheme.success;
    return Text(
      record.pendingAbsenceLabel,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ManagerPermissionActivityText extends StatelessWidget {
  final AttendanceModel record;

  const _ManagerPermissionActivityText({required this.record});

  @override
  Widget build(BuildContext context) {
    final startOfDay =
        DateTime(record.date.year, record.date.month, record.date.day);
    final endOfDay = DateTime(
        record.date.year, record.date.month, record.date.day, 23, 59, 59);

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseContextProvider.current.firestore
          .collection('permission_requests')
          .where('employeeId', isEqualTo: record.employeeId)
          .where('status', isEqualTo: 'approved')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data!.docs.isNotEmpty) {
          final doc = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          final type = doc['permissionType'] ?? 'Permission';
          final fromTimestamp = doc['fromTime'] as Timestamp?;
          final toTimestamp = doc['toTime'] as Timestamp?;

          String durationStr = '';
          if (fromTimestamp != null && toTimestamp != null) {
            final from = fromTimestamp.toDate();
            final to = toTimestamp.toDate();
            final diff = to.difference(from);
            final hours = diff.inMinutes / 60.0;
            durationStr = ' (${hours.toStringAsFixed(1)} hrs)';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$type$durationStr',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ManagerDashTheme.info,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Permission Approved',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }

        final hasPermission = record.hasPermissionActivity;
        final color = !hasPermission
            ? _ManagerDashTheme.muted.withValues(alpha: 0.75)
            : record.isPermissionReEntryDelayed
                ? _ManagerDashTheme.danger
                : record.isTemporaryExit
                    ? _ManagerDashTheme.warning
                    : _ManagerDashTheme.info;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.permissionActivityLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasPermission)
              Text(
                record.permissionActivityDetail,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ManagerDashTheme.muted.withValues(alpha: 0.75),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ManagerNotificationsPanel extends StatelessWidget {
  final AttendanceService attendanceService;
  final LeaveService leaveService;
  final PermissionService permissionService;
  final String managerIdentifier;
  final String? managerEmployeeId;
  final String? managerEmail;
  final String managerName;

  const _ManagerNotificationsPanel({
    required this.attendanceService,
    required this.leaveService,
    required this.permissionService,
    required this.managerIdentifier,
    this.managerEmployeeId,
    this.managerEmail,
    required this.managerName,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AttendanceModel>>(
      stream: attendanceService.getAttendanceHistoryStreamByManager(
        managerIdentifier,
        limit: 50,
      ),
      builder: (context, attendanceSnapshot) {
        return StreamBuilder<List<LeaveRequest>>(
          stream: leaveService.getRequestsForManager(managerIdentifier),
          builder: (context, leaveSnapshot) {
            return StreamBuilder<List<PermissionRequest>>(
              stream: permissionService
                  .getPermissionRequestsForManager(managerIdentifier),
              builder: (context, permissionSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _anniversaryNotificationStream(),
                  builder: (context, anniversarySnapshot) {
                    final items = <_ManagerNotificationItem>[
                      ..._anniversaryItems(
                          anniversarySnapshot.data?.docs ?? const []),
                      ..._attendanceItems(attendanceSnapshot.data ?? const []),
                      ..._leaveItems(leaveSnapshot.data ?? const []),
                      ..._permissionItems(permissionSnapshot.data ?? const []),
                    ]..sort((a, b) => b.time.compareTo(a.time));

                    if (items.isEmpty) {
                      return _placeholder();
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _notificationCard(context, items[index]);
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _anniversaryNotificationStream() {
    final identities = <String>{
      managerIdentifier,
      managerName,
      if (managerEmployeeId?.trim().isNotEmpty == true)
        managerEmployeeId!.trim(),
      if (managerEmail?.trim().isNotEmpty == true) managerEmail!.trim(),
    }.where((value) => value.trim().isNotEmpty).take(10).toList();

    return FirebaseContextProvider.current.firestore
        .collection('notifications')
        .where('recipient', whereIn: identities)
        .snapshots();
  }

  List<_ManagerNotificationItem> _anniversaryItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      return doc.data()['actionType'] == 'work_anniversary';
    }).map((doc) {
      final data = doc.data();
      final title = NotificationService.cleanNotificationText(
        (data['title'] ?? 'Work Anniversary').toString(),
      );
      return _ManagerNotificationItem(
        type: 'anniversary',
        title: title,
        message: (data['content'] ?? '').toString(),
        time: _timestampFrom(data['timestamp']) ?? DateTime.now(),
        userName: (data['employeeName'] ?? managerName).toString(),
        status: 'ANNIVERSARY',
        statusColor: const Color(0xFFFFA400),
        icon: Icons.celebration_rounded,
        iconColor: const Color(0xFFFFA400),
        anniversaryGreeting: AnniversaryGreeting(
          id: doc.id,
          recipient: (data['recipient'] ?? managerIdentifier).toString(),
          employeeName:
              (data['employeeName'] ?? data['userName'] ?? managerName)
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

  DateTime? _timestampFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  List<_ManagerNotificationItem> _attendanceItems(List<AttendanceModel> data) {
    return data.map((record) {
      final isCheckout = record.isCheckedOut;
      final hasPermission = record.hasPermissionActivity;
      final DateTime time = isCheckout
          ? (record.checkOutTime ?? record.checkInTime ?? record.date)
          : (record.checkInTime ?? record.date);
      final activityTime = record.lastReturnTime ?? record.lastExitTime ?? time;

      return _ManagerNotificationItem(
        type: 'attendance',
        title: record.isPermissionReEntryDelayed
            ? 'Delayed Re-entry Alert'
            : record.isTemporaryExit
                ? 'Temporary Exit'
                : hasPermission
                    ? 'Permission Re-entry'
                    : record.isEarlyCheckout
                        ? 'Early Checkout Alert'
                        : isCheckout
                            ? 'Checked Out'
                            : 'Checked In',
        message: record.isPermissionReEntryDelayed
            ? '${record.employeeName} returned ${record.permissionDelayMinutes} minutes after the permission time.'
            : hasPermission
                ? '${record.employeeName}: ${record.permissionActivityDetail}.'
                : record.isEarlyCheckout
                    ? '${record.employeeName} checked out early. Please review the recent attendance log.'
                    : '${record.employeeName} has ${isCheckout ? 'checked out' : 'checked in'} for the day.',
        time: activityTime,
        userName: record.employeeName,
        status: hasPermission
            ? record.permissionActivityLabel.toUpperCase()
            : record.isEarlyCheckout
                ? 'EARLY CHECKOUT'
                : record.statusLabel,
        statusColor: record.isPermissionReEntryDelayed
            ? _ManagerDashTheme.danger
            : record.isTemporaryExit
                ? _ManagerDashTheme.warning
                : hasPermission
                    ? _ManagerDashTheme.info
                    : record.isEarlyCheckout
                        ? _ManagerDashTheme.warning
                        : _statusColor(record.status),
        icon: record.isPermissionReEntryDelayed
            ? Icons.error_outline_rounded
            : record.isTemporaryExit
                ? Icons.directions_walk_rounded
                : hasPermission
                    ? Icons.assignment_turned_in_rounded
                    : record.isEarlyCheckout
                        ? Icons.warning_amber_rounded
                        : isCheckout
                            ? Icons.logout_rounded
                            : Icons.login_rounded,
        iconColor: record.isPermissionReEntryDelayed
            ? _ManagerDashTheme.danger
            : record.isTemporaryExit
                ? _ManagerDashTheme.warning
                : hasPermission
                    ? _ManagerDashTheme.info
                    : record.isEarlyCheckout
                        ? _ManagerDashTheme.warning
                        : _ManagerDashTheme.primary,
      );
    }).toList();
  }

  List<_ManagerNotificationItem> _leaveItems(List<LeaveRequest> data) {
    return data.map((request) {
      return _ManagerNotificationItem(
        type: 'leave',
        title: 'Leave Request',
        message:
            '${request.userName} requested leave from ${DateFormat('MMM dd').format(request.startDate)} to ${DateFormat('MMM dd').format(request.endDate)}.',
        time: request.createdAt ?? DateTime.now(),
        userName: request.userName,
        status: request.status.toUpperCase(),
        statusColor: _leaveStatusColor(request.status),
        icon: Icons.event_note_rounded,
        iconColor: _ManagerDashTheme.warning,
      );
    }).toList();
  }

  List<_ManagerNotificationItem> _permissionItems(
      List<PermissionRequest> data) {
    return data.map((request) {
      return _ManagerNotificationItem(
        type: 'permission',
        title: 'Permission Request',
        message:
            '${request.employeeName} requested permission for ${request.permissionType ?? 'General'}.',
        time: request.requestedAt,
        userName: request.employeeName,
        status: request.status.toUpperCase(),
        statusColor: _leaveStatusColor(request.status),
        icon: Icons.vpn_key_rounded,
        iconColor: _ManagerDashTheme.info,
      );
    }).toList();
  }

  Color _statusColor(AttendanceStatus status) {
    return switch (status) {
      AttendanceStatus.present => _ManagerDashTheme.success,
      AttendanceStatus.late => _ManagerDashTheme.warning,
      AttendanceStatus.absent => _ManagerDashTheme.danger,
      AttendanceStatus.wfh => _ManagerDashTheme.info,
      AttendanceStatus.leave => _ManagerDashTheme.info,
    };
  }

  Color _leaveStatusColor(String status) {
    return switch (status.toLowerCase()) {
      'approved' => _ManagerDashTheme.success,
      'rejected' => _ManagerDashTheme.danger,
      _ => _ManagerDashTheme.warning,
    };
  }

  Widget _notificationCard(
      BuildContext context, _ManagerNotificationItem item) {
    final child = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ManagerDashTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ManagerDashTheme.border),
        boxShadow: const [
          BoxShadow(
            color: _ManagerDashTheme.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: _ManagerDashTheme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      _formatRelativeTime(item.time),
                      style: const TextStyle(
                        color: _ManagerDashTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.message,
                  style: const TextStyle(
                    color: _ManagerDashTheme.muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor:
                          _ManagerDashTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        item.userName.isNotEmpty ? item.userName[0] : 'U',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: _ManagerDashTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.userName,
                      style: const TextStyle(
                        color: _ManagerDashTheme.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.status,
                        style: TextStyle(
                          color: item.statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final greeting = item.anniversaryGreeting;
    if (greeting == null) return child;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showAnniversaryGreetingDialog(context, greeting),
      child: child,
    );
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM dd').format(time);
  }

  Widget _placeholder() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 64,
            color: _ManagerDashTheme.muted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 22),
          const Text(
            'No notifications yet',
            style: TextStyle(
              color: _ManagerDashTheme.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Activity from your team will appear here.',
            style: TextStyle(
              color: _ManagerDashTheme.muted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerNotificationItem {
  final String type;
  final String title;
  final String message;
  final DateTime time;
  final String userName;
  final String status;
  final Color statusColor;
  final IconData icon;
  final Color iconColor;
  final AnniversaryGreeting? anniversaryGreeting;

  _ManagerNotificationItem({
    required this.type,
    required this.title,
    required this.message,
    required this.time,
    required this.userName,
    required this.status,
    required this.statusColor,
    required this.icon,
    required this.iconColor,
    this.anniversaryGreeting,
  });
}

// Fixed-brand palette for the Manager "Monthly Analysis" screen (force-dark),
// kept in lock-step with the Admin monthly analysis screen.
const Color _maPrimary = Color(0xFF0F766E);
const Color _maAmber = Color(0xFFFFB800);
const Color _maRed = Color(0xFFFF5757);
const Color _maGreen = Color(0xFF00C896);
const Color _maCyan = Color(0xFF22D3EE);
const Color _maShadow = Color(0x1A6B7897);
const Color _maWhite = Color(0xFFFFFFFF);

const List<String> _kMonthlyMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

class _ManagerMonthlyRowData {
  final Staff staff;
  int presentCount = 0;
  int absentCount = 0;
  int pendingMinutes = 0;
  int permissionMinutes = 0;
  double paidLeaveCount = 0;
  double unpaidLeaveCount = 0;

  int get totalPendingMinutes => pendingMinutes + permissionMinutes;
  double get totalLeaveCount => paidLeaveCount + unpaidLeaveCount;

  _ManagerMonthlyRowData(this.staff);
}

String _formatMonthlyHours(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final mins = totalMinutes % 60;
  return '$hours hrs ${mins.toString().padLeft(2, '0')} min';
}

String _formatMonthlyLeaveDays(double days) {
  if (days == days.roundToDouble()) return days.toInt().toString();
  return days.toStringAsFixed(1);
}

class _ManagerMonthlyHeaderText extends StatelessWidget {
  final String label;

  const _ManagerMonthlyHeaderText(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppThemeColors.darkMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}



class _ManagerMonthlyRow extends StatelessWidget {
  final _ManagerMonthlyRowData summary;
  final String Function(int) formatTime;
  final VoidCallback onTap;

  const _ManagerMonthlyRow({
    required this.summary,
    required this.formatTime,
    required this.onTap,
  });

  Widget _buildMobileDetailItem(IconData icon, String label, String value,
      {Color? textColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppThemeColors.darkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                    color: textColor ?? AppThemeColors.darkText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApprovedLeaveDetailItem(_ManagerMonthlyRowData summary) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.calendar_today_outlined,
            size: 16, color: AppThemeColors.darkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Approved Leave',
                style: TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              if (summary.totalLeaveCount == 0)
                const Text(
                  '0',
                  style: TextStyle(
                      color: AppThemeColors.darkMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary.paidLeaveCount > 0)
                      Text(
                        'Paid: ${_formatMonthlyLeaveDays(summary.paidLeaveCount)}',
                        style: const TextStyle(
                            color: _maCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    if (summary.unpaidLeaveCount > 0)
                      Text(
                        'Unpaid: ${_formatMonthlyLeaveDays(summary.unpaidLeaveCount)}',
                        style: const TextStyle(
                            color: _maAmber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final isMobile = mediaWidth < 800;

    if (isMobile) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _maPrimary.withValues(alpha: 0.2),
                    child: Text(
                      summary.staff.name.isNotEmpty
                          ? summary.staff.name[0].toUpperCase()
                          : 'E',
                      style: const TextStyle(
                        color: _maPrimary,
                        fontSize: 13,
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
                          summary.staff.name,
                          style: const TextStyle(
                            color: AppThemeColors.darkText,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          summary.staff.employeeId,
                          style: TextStyle(
                            color:
                                AppThemeColors.darkMuted.withValues(alpha: 0.7),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppThemeColors.darkCanvas,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppThemeColors.darkBorder),
                    ),
                    child: Text(
                      summary.staff.position.isNotEmpty
                          ? summary.staff.position
                          : '-',
                      style: const TextStyle(
                        color: AppThemeColors.darkMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppThemeColors.darkBorder, height: 1),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.business_outlined,
                          'Designation',
                          summary.staff.department,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.check_circle_outline,
                          'Present Days',
                          '${summary.presentCount}',
                          textColor: _maGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.cancel_outlined,
                          'Absent Days',
                          '${summary.absentCount}',
                          textColor: _maRed,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.hourglass_empty_outlined,
                          'Pending Hours',
                          formatTime(summary.pendingMinutes),
                          textColor:
                              summary.pendingMinutes > 0 ? _maAmber : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildMobileDetailItem(
                          Icons.vpn_key_outlined,
                          'Permission Hours',
                          formatTime(summary.permissionMinutes),
                          textColor:
                              summary.permissionMinutes > 0 ? _maPrimary : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _buildApprovedLeaveDetailItem(summary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildMobileDetailItem(
                    Icons.calculate_outlined,
                    'Total Pending Hours',
                    formatTime(summary.totalPendingMinutes),
                    textColor: summary.totalPendingMinutes > 0 ? _maRed : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 18,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _maPrimary.withValues(alpha: 0.2),
                    child: Text(
                      summary.staff.name.isNotEmpty
                          ? summary.staff.name[0].toUpperCase()
                          : 'E',
                      style: const TextStyle(
                        color: _maPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.staff.name,
                          style: const TextStyle(
                            color: AppThemeColors.darkText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          summary.staff.employeeId,
                          style: TextStyle(
                            color:
                                AppThemeColors.darkMuted.withValues(alpha: 0.7),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 14,
              child: Text(
                summary.staff.department,
                style: const TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 14,
              child: Text(
                summary.staff.position.isNotEmpty
                    ? summary.staff.position
                    : '-',
                style: const TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _maGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${summary.presentCount}',
                    style: const TextStyle(
                      color: _maGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _maRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${summary.absentCount}',
                    style: const TextStyle(
                      color: _maRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 16,
              child: Text(
                formatTime(summary.pendingMinutes),
                style: TextStyle(
                  color: summary.pendingMinutes > 0
                      ? _maAmber
                      : AppThemeColors.darkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              flex: 16,
              child: Text(
                formatTime(summary.permissionMinutes),
                style: TextStyle(
                  color: summary.permissionMinutes > 0
                      ? _maPrimary
                      : AppThemeColors.darkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              flex: 16,
              child: Text(
                formatTime(summary.totalPendingMinutes),
                style: TextStyle(
                  color: summary.totalPendingMinutes > 0
                      ? _maRed
                      : AppThemeColors.darkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: summary.totalLeaveCount == 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              AppThemeColors.darkMuted.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '0',
                          style: TextStyle(
                            color: AppThemeColors.darkMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (summary.paidLeaveCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: _maPrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Paid: ${_formatMonthlyLeaveDays(summary.paidLeaveCount)}',
                                style: const TextStyle(
                                    color: _maCyan,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (summary.unpaidLeaveCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _maAmber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Unpaid: ${_formatMonthlyLeaveDays(summary.unpaidLeaveCount)}',
                                style: const TextStyle(
                                    color: _maAmber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


