import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/scan_sound_stub.dart'
    if (dart.library.html) '../../utils/scan_sound_web.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../models/attendance_model.dart';
import '../../models/staff.dart';
import '../../services/attendance_service.dart';
import '../../services/geo_fence_service.dart';
import '../../utils/responsive.dart';

// Fixed-dark palette for the QR scanner screen (force-dark regardless of the
// app theme). Intentional exception: file-scoped brand constants.
class _StaffScanTheme {
  static const surface = AppThemeColors.darkSurface;
  static const soft = AppThemeColors.darkCanvas;
  static const border = AppThemeColors.darkBorder;
  static const text = AppThemeColors.darkText;
  static const muted = AppThemeColors.darkMuted;
  static const primary = Color(0xFF0F766E);
  static const success = Color(0xFF00A96B);
  static const warning = Color(0xFFFF9F1C);
  static const shadow = Color(0x126B7897);
  static const present = Color(0xFF00C896);
  static const late = Color(0xFFFFB800);
  static const absent = Color(0xFFFF5C7A);
  static const absentSoft = Color(0xFFFF8AA0);
  static const absentFaint = Color(0xFFFFAFC0);
  static const info = Color(0xFF0EA5E9);
  static const infoBorder = Color(0xFFAFC0FF);
  static const disabled = Color(0xFFB7C5DD);
  static const grey = Color(0xFF9E9E9E);
  static const greyLight = Color(0xFFBDBDBD);
  static const chipAmber = Color(0xFF2B2411);
  static const chipAmberBorder = Color(0xFF6B551E);
  static const chipGreen = Color(0xFF0D2E27);
  static const chipGreenBorder = Color(0xFF1E6B56);
  static const white = Color(0xFFFFFFFF);
  static const white70 = Color(0xB3FFFFFF);
  static const black = Color(0xFF000000);
  static const blackShade = Color(0x66000000);
}

class StaffScanQRScreen extends StatefulWidget {
  final bool autoStart;
  const StaffScanQRScreen({super.key, this.autoStart = false});

  @override
  State<StaffScanQRScreen> createState() => _StaffScanQRScreenState();
}

class _StaffScanQRScreenState extends State<StaffScanQRScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _googleCodeScannerChannel =
      MethodChannel('attendqr/google_code_scanner');
  static const double _initialAutoZoomScale = 0.35;

  final AttendanceService _attendanceService = AttendanceService();
  final GeoFenceService _geoFenceService = GeoFenceService();
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 900,
    formats: const [BarcodeFormat.qrCode],
  );
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rulesSub;
  StreamSubscription<List<AttendanceModel>>? _todayAttendanceSub;
  Timer? _overdueSyncTimer;

  late DateTime selectedDate;
  bool _locationEnabled = false;
  bool _withinRadius = false;
  bool _isLoading = false;
  bool _scanSessionOpen = false;
  bool _scannerActive = false;
  bool _useEmbeddedScanner = false;
  bool _nativeScanInProgress = false;
  bool _embeddedScannerStarting = false;
  bool _cameraPermissionGranted = false;
  bool _localCheckInRecorded = false;
  bool _localCheckOutRecorded = false;
  bool _scanLocking = false;
  bool _resumeScannerOnForeground = false;
  Position? _currentPosition;
  _OfficeConfig? _verifiedOfficeConfig;
  Staff? _scannedStaff;
  AttendanceModel? _todayRecord;
  AttendanceSubmissionResult? _lastSubmissionResult;
  DateTime? _lastSubmissionTime;
  DateTime? _lastScanTime;
  String? _lastRejectedRawValue;
  DateTime? _lastRejectedScanTime;
  String? _scannedToken;
  String? _errorMessage;
  String? _infoMessage;
  double? _lastOfficeDistance;
  double? _lastLocationAccuracy;
  double? _lastOfficeRadius;
  double? _lastRecommendedRadius;
  double _zoomScale = _initialAutoZoomScale;
  double _zoomScaleAtGestureStart = _initialAutoZoomScale;

  double _radiusInMeters = 50.0;
  String _checkInStart = '08:30 AM';
  String _checkInEnd = '10:30 AM';
  String _checkOutStart = '05:00 PM';
  String _checkOutEnd = '07:30 PM';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selectedDate = DateTime.now();
    unawaited(_attendanceService.syncOverdueAttendanceRecords());
    _overdueSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_attendanceService.syncOverdueAttendanceRecords()),
    );
    _listenAttendanceRules();
    _bindTodayAttendance();

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startScanFlow();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rulesSub?.cancel();
    _todayAttendanceSub?.cancel();
    _overdueSyncTimer?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      setState(() {
        selectedDate = DateTime.now();
      });

      if (_resumeScannerOnForeground &&
          _scanSessionOpen &&
          _scannerActive &&
          _useEmbeddedScanner &&
          _scannedToken == null) {
        _resumeScannerOnForeground = false;
        unawaited(_startEmbeddedScannerSafely());
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _resumeScannerOnForeground =
          _scannerActive && _useEmbeddedScanner && _scannedToken == null;
      if (_scannerController.value.isRunning) {
        unawaited(_scannerController.stop());
      }
    }
  }

  bool get _hasCheckedInToday =>
      _localCheckInRecorded || _todayRecord?.checkInTime != null;
  bool get _hasCheckedOutToday =>
      _localCheckOutRecorded || _todayRecord?.isCheckedOut == true;
  bool get _isReadyForCheckOut => _hasCheckedInToday && !_hasCheckedOutToday;
  bool get _canUseGoogleCodeScanner =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _scannerZoomSupported => !kIsWeb;
  bool get _showActiveScannerOnly =>
      _scanSessionOpen && _scannedToken == null && _useEmbeddedScanner;

  String get _startScanLabel {
    if (_hasCheckedOutToday) return 'Attendance Completed';
    return _isReadyForCheckOut ? 'Check-Out Now' : 'Start Scan';
  }

  String get _markAttendanceLabel {
    return _isReadyForCheckOut ? 'Mark Check-Out' : 'Mark Attendance';
  }

  Future<void> _bindTodayAttendance() async {
    final staff = await _loadCurrentStaff();
    if (!mounted || staff == null) return;

    _subscribeTodayAttendance(staff, keepExistingStaff: true);
  }

  void _subscribeTodayAttendance(
    Staff staff, {
    bool keepExistingStaff = false,
  }) {
    _todayAttendanceSub?.cancel();
    _todayAttendanceSub = _attendanceService
        .getTodayAttendanceStreamForEmployee(staff.employeeId)
        .listen((records) {
      if (!mounted) return;
      setState(() {
        _todayRecord = records.isNotEmpty ? records.first : null;
        _localCheckInRecorded = _todayRecord?.checkInTime != null;
        _localCheckOutRecorded = _todayRecord?.isCheckedOut == true;
        _scannedStaff = keepExistingStaff ? (_scannedStaff ?? staff) : staff;
      });
    }, onError: (Object error) {
      if (!mounted || !_scanSessionOpen) return;
      setState(() {
        _infoMessage =
            'Attendance status sync is temporarily unavailable. Please try again when Firebase is reachable.';
        _errorMessage = _friendlyScanError(error);
      });
    });
  }

  void _listenAttendanceRules() {
    _rulesSub = FirebaseContextProvider.current.firestore
        .collection('geo_config')
        .doc('default')
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      _applyAttendanceRules(doc.data() ?? const <String, dynamic>{});
    }, onError: (Object error) {
      if (!mounted || !_scanSessionOpen) return;
      setState(() {
        _infoMessage =
            'Attendance rules are temporarily unavailable. Saved office times will be used when possible.';
        _errorMessage = _friendlyScanError(error);
      });
    });
  }

  void _applyAttendanceRules(Map<String, dynamic> data) {
    setState(() {
      _checkInStart = data['checkInStart']?.toString() ?? _checkInStart;
      _checkInEnd = data['checkInEnd']?.toString() ?? _checkInEnd;
      _checkOutStart = data['checkOutStart']?.toString() ?? _checkOutStart;
      _checkOutEnd = data['checkOutEnd']?.toString() ?? _checkOutEnd;
    });
  }

  Future<void> _startScanFlow() async {
    try {
      if (mounted) {
        setState(() {
          selectedDate = DateTime.now();
          _isLoading = true;
          _scanSessionOpen = true;
          _scannerActive = false;
          _cameraPermissionGranted = false;
          _errorMessage = null;
          _infoMessage = null;
          _clearGeofenceGuidance();
          _scannedToken = null;
          _scannedStaff = null;
          _verifiedOfficeConfig = null;
          _lastSubmissionResult = null;
          _lastSubmissionTime = null;
          _lastScanTime = null;
          _lastRejectedRawValue = null;
          _lastRejectedScanTime = null;
          _scanLocking = false;
        });
      }

      if (_hasCheckedOutToday) {
        setState(() {
          _isLoading = false;
          _scanSessionOpen = false;
          _infoMessage = 'Attendance is already completed for today.';
        });
        return;
      }

      if (!await _ensureCameraIsActive()) {
        return;
      }

      final access = await _geoFenceService.ensureLocationAccess();
      if (!access.granted) {
        setState(() {
          _locationEnabled = false;
          _withinRadius = false;
          _errorMessage = access.message;
          _infoMessage =
              'Camera is ready. Enable location to verify and mark attendance.';
          _isLoading = false;
        });
        return;
      }

      final position = await _geoFenceService.getCurrentPosition();
      if (position == null) {
        setState(() {
          _locationEnabled = false;
          _withinRadius = false;
          _errorMessage =
              'Unable to read your current location. Please try again.';
          _infoMessage =
              'Camera is ready. Enable location to verify and ${_isReadyForCheckOut ? 'mark check-out' : 'mark attendance'}.';
          _isLoading = false;
        });
        return;
      }

      final office = await _loadOfficeConfig();
      final distance = Geolocator.distanceBetween(
        office.latitude,
        office.longitude,
        position.latitude,
        position.longitude,
      );
      final accuracyAllowance =
          position.accuracy.isFinite && position.accuracy > 0
              ? position.accuracy
              : 0.0;
      final effectiveDistance =
          (distance - accuracyAllowance).clamp(0.0, double.infinity);

      final currentStaff = await _loadCurrentStaff();
      if (currentStaff == null) {
        setState(() {
          _currentPosition = position;
          _locationEnabled = true;
          _withinRadius = true;
          _scannedStaff = null;
          _errorMessage = 'No staff profile found for the logged-in user.';
          _infoMessage =
              'Camera is active. Please sign in with a valid staff account.';
          _isLoading = false;
          _scannerActive = true;
        });
        return;
      }

      setState(() {
        _currentPosition = position;
        _locationEnabled = true;
        _radiusInMeters = office.radius;
        _checkInStart = office.checkInStart;
        _checkInEnd = office.checkInEnd;
        _checkOutStart = office.checkOutStart;
        _checkOutEnd = office.checkOutEnd;
        _scannedStaff = currentStaff;
      });
      _subscribeTodayAttendance(currentStaff);

      if (effectiveDistance > _validationRadius(office.radius)) {
        setState(() {
          _withinRadius = false;
          _verifiedOfficeConfig = null;
          _scannerActive = true;
          _useEmbeddedScanner = !_canUseGoogleCodeScanner;
          _setOutsideGeofenceError(
            distance: distance,
            accuracy: position.accuracy,
            officeRadius: office.radius,
          );
          _infoMessage =
              'Camera is active. Scan the QR code while you move closer to the office.';
          _isLoading = false;
        });
        return;
      }

      if (_officeIsClosedToday(office)) {
        setState(() {
          _isLoading = false;
          _scanSessionOpen = false;
          _scannerActive = false;
          _withinRadius = true;
          _infoMessage = null;
        });
        await _showHolidayPopup(office);
        return;
      }

      setState(() {
        _withinRadius = true;
        _verifiedOfficeConfig = office;
        _scannerActive = true;
        _useEmbeddedScanner = !_canUseGoogleCodeScanner;
        _infoMessage =
            'Location verified. Scan the QR code shown on the admin panel to ${_isReadyForCheckOut ? 'check out' : 'check in'}.';
        _isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyScanError(error);
          _isLoading = false;
          _scanSessionOpen = false;
        });
      }
    }
  }

  Future<void> _markAttendance() async {
    try {
      final scannedToken = _scannedToken;
      if (scannedToken == null) {
        setState(() {
          _errorMessage = 'Scan the admin QR before marking attendance.';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _infoMessage =
            'Checking verification and ${_isReadyForCheckOut ? 'marking check-out' : 'marking attendance'}...';
      });

      final staff = _scannedStaff ?? await _loadCurrentStaff();
      if (staff == null) {
        setState(() {
          _errorMessage = 'No staff profile found for the logged-in user.';
          _infoMessage = null;
          _isLoading = false;
        });
        return;
      }

      final useVerifiedScanPosition = _withinRadius && _currentPosition != null;
      final position = useVerifiedScanPosition
          ? _currentPosition!
          : await _geoFenceService.getCurrentPosition();
      if (position == null) {
        setState(() {
          _errorMessage =
              'Unable to read your current location. Please try again.';
          _isLoading = false;
        });
        return;
      }

      final office = useVerifiedScanPosition && _verifiedOfficeConfig != null
          ? _verifiedOfficeConfig!
          : await _loadOfficeConfig();
      final currentDistance = Geolocator.distanceBetween(
        office.latitude,
        office.longitude,
        position.latitude,
        position.longitude,
      );
      final effectiveDistance = _effectiveDistance(
        distance: currentDistance,
        accuracy: position.accuracy,
      );

      if (effectiveDistance > _validationRadius(office.radius)) {
        setState(() {
          _setOutsideGeofenceError(
            distance: currentDistance,
            accuracy: position.accuracy,
            officeRadius: office.radius,
          );
          _infoMessage = null;
          _isLoading = false;
        });
        return;
      }

      final result = await _attendanceService.markAttendance(
        employeeId: staff.employeeId,
        employeeName: staff.name,
        department: staff.department,
        qrToken: scannedToken,
        userLat: position.latitude,
        userLng: position.longitude,
        officeLat: office.latitude,
        officeLng: office.longitude,
        geoFenceRadiusMetres: office.radius,
        userAccuracyMetres: position.accuracy,
        isWfh: false,
      );

      if (!mounted) return;

      setState(() {
        _scannedStaff = staff;
        _currentPosition = position;
        _radiusInMeters = office.radius;
        if (result.success) {
          _scannedToken = null;
          _scannerActive = false;
          _lastSubmissionResult = result;
          _lastSubmissionTime = DateTime.now();
          if (result.action == AttendanceSubmissionAction.checkIn) {
            _localCheckInRecorded = true;
          } else if (result.action == AttendanceSubmissionAction.checkOut ||
              result.action == AttendanceSubmissionAction.earlyCheckOut) {
            _localCheckInRecorded = true;
            _localCheckOutRecorded = true;
          }
        }
        _isLoading = false;
      });

      if (result.success) {
        setState(() {
          _infoMessage = result.message;
        });

        final snackBarColor =
            result.action == AttendanceSubmissionAction.earlyCheckOut
                ? _StaffScanTheme.warning
                : _getStatusColor(result.status);
        final snackBarMessage =
            result.action == AttendanceSubmissionAction.earlyCheckOut
                ? 'Early Check-out Recorded with Warning'
                : result.action == AttendanceSubmissionAction.checkOut
                    ? 'Check-out completed successfully'
                    : result.action == AttendanceSubmissionAction.tempExit ||
                            result.action == AttendanceSubmissionAction.reEntry
                        ? result.message
                        : 'Attendance marked as ${result.status.toUpperCase()}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              snackBarMessage,
              style: const TextStyle(color: _StaffScanTheme.white),
            ),
            backgroundColor: snackBarColor,
            duration: const Duration(seconds: 4),
          ),
        );
        await _showAttendanceResultDialog(result);
      } else {
        setState(() {
          _errorMessage = result.message;
          _infoMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: _StaffScanTheme.absent,
            duration: const Duration(seconds: 4),
          ),
        );
        await _showAttendanceResultDialog(result);
      }
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyScanError(error);
      setState(() {
        _errorMessage = message;
        _infoMessage = null;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _StaffScanTheme.absent,
        ),
      );
    }
  }

  Future<void> _showAttendanceResultDialog(
    AttendanceSubmissionResult result,
  ) async {
    if (!mounted) return;

    final isCheckIn = result.action == AttendanceSubmissionAction.checkIn;
    final isCheckOut = result.action == AttendanceSubmissionAction.checkOut;
    final isEarlyCheckOut =
        result.action == AttendanceSubmissionAction.earlyCheckOut;
    final isBlocked =
        result.action == AttendanceSubmissionAction.checkOutBlocked;
    final color = isEarlyCheckOut
        ? _StaffScanTheme.warning
        : result.success
            ? _StaffScanTheme.success
            : _StaffScanTheme.absent;
    final icon = isCheckIn
        ? Icons.login_rounded
        : isCheckOut
            ? Icons.logout_rounded
            : isEarlyCheckOut
                ? Icons.warning_rounded
                : isBlocked
                    ? Icons.lock_clock_rounded
                    : Icons.error_rounded;
    final title = isCheckIn
        ? 'Check-in Recorded'
        : isCheckOut
            ? 'Check-out Successful'
            : isEarlyCheckOut
                ? 'Early Check-out Warning'
                : isBlocked
                    ? 'Check-out Not Allowed Yet'
                    : 'Attendance Not Marked';
    final submittedAt = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Theme(
          data: ThemeData.dark().copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: AppThemeColors.darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(
                    color: AppThemeColors.darkBorder, width: 1),
              ),
            ),
          ),
          child: AlertDialog(
            backgroundColor: AppThemeColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side:
                  const BorderSide(color: AppThemeColors.darkBorder, width: 1),
            ),
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _StaffScanTheme.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _DialogDetailLine(
                  icon: Icons.today_rounded,
                  label: 'Day',
                  value: DateFormat('EEEE').format(submittedAt),
                ),
                const SizedBox(height: 8),
                _DialogDetailLine(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value: DateFormat('MMM d, y').format(submittedAt),
                ),
                const SizedBox(height: 8),
                _DialogDetailLine(
                  icon: Icons.schedule_rounded,
                  label: 'Time',
                  value: DateFormat('hh:mm a').format(submittedAt),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'OK',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _resetScanner() async {
    if (_hasCheckedOutToday) {
      setState(() {
        _scanSessionOpen = false;
        _scannerActive = false;
        _scannedToken = null;
        _infoMessage = 'Attendance is already completed for today.';
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _scanSessionOpen = true;
      _verifiedOfficeConfig = null;
      _lastSubmissionResult = null;
      _lastSubmissionTime = null;
      _lastScanTime = null;
      _lastRejectedRawValue = null;
      _lastRejectedScanTime = null;
      _scanLocking = false;
      selectedDate = DateTime.now();
    });

    if (!_cameraPermissionGranted) {
      await _ensureCameraIsActive(forceEmbedded: _useEmbeddedScanner);
    } else {
      if (_useEmbeddedScanner) {
        await _startEmbeddedScannerSafely();
      }
    }

    setState(() {
      _scannerActive = _cameraPermissionGranted;
      _scannedToken = null;
      _errorMessage = null;
      _infoMessage = _withinRadius
          ? 'Location verified. Scan the QR code shown on the admin panel to ${_isReadyForCheckOut ? 'check out' : 'check in'}.'
          : 'Camera is ready. Enable location to ${_isReadyForCheckOut ? 'check out' : 'complete attendance'}.';
    });
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (!_scannerActive ||
        _isLoading ||
        _scannedToken != null ||
        _scanLocking) {
      return;
    }
    if (capture.barcodes.isEmpty) return;

    final rawValue = capture.barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;
    if (_recentlyRejectedSameScan(rawValue)) return;

    setState(() {
      _scanLocking = true;
      _infoMessage = 'QR detected. Locking focus...';
    });
    _playScanFeedback(candidate: true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    await _handleScannedRawValue(rawValue);
    if (mounted && _scannedToken == null) {
      setState(() {
        _scanLocking = false;
      });
    }
  }

  Future<void> _handleScannedRawValue(String rawValue) async {
    if (!_scannerActive || _isLoading || _scannedToken != null) return;
    final token = _parseQrToken(rawValue);
    if (token == null || token.isEmpty) {
      _rememberRejectedScan(rawValue);
      setState(() {
        _errorMessage = 'The scanned QR code is not a valid attendance token.';
        _infoMessage =
            'Keep the QR inside the frame, avoid glare, and try again.';
      });
      return;
    }

    AttendanceSubmissionResult tokenValidation;
    try {
      tokenValidation = await _attendanceService.validateQrToken(token);
    } catch (error) {
      _rememberRejectedScan(rawValue);
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyScanError(error);
        _infoMessage = 'Network check failed. Keep the scanner open and retry.';
      });
      return;
    }

    if (!tokenValidation.success) {
      _rememberRejectedScan(rawValue);
      setState(() {
        _errorMessage = tokenValidation.message;
        _infoMessage = 'Ask admin to refresh the QR if this keeps happening.';
      });
      return;
    }

    if (_useEmbeddedScanner) {
      await _scannerController.stop();
    }

    setState(() {
      _scannedToken = token;
      _lastScanTime = DateTime.now();
      _scanSessionOpen = false;
      _scannerActive = false;
      _errorMessage = null;
      _infoMessage = tokenValidation.message;
      _scanLocking = false;
    });
    _playScanFeedback();
  }

  void _playScanFeedback({bool candidate = false}) {
    if (kIsWeb) {
      playScanBeep(short: candidate);
    } else {
      unawaited(
        candidate ? HapticFeedback.selectionClick() : HapticFeedback.vibrate(),
      );
    }
  }

  bool _recentlyRejectedSameScan(String rawValue) {
    final lastRejectedAt = _lastRejectedScanTime;
    if (_lastRejectedRawValue != rawValue || lastRejectedAt == null) {
      return false;
    }

    return DateTime.now().difference(lastRejectedAt) <
        const Duration(seconds: 2);
  }

  void _rememberRejectedScan(String rawValue) {
    _lastRejectedRawValue = rawValue;
    _lastRejectedScanTime = DateTime.now();
  }

  Future<bool> _ensureCameraIsActive({bool forceEmbedded = false}) async {
    if (_canUseGoogleCodeScanner && !forceEmbedded) {
      setState(() {
        _cameraPermissionGranted = true;
        _scannerActive = true;
        _useEmbeddedScanner = false;
      });
      return true;
    }

    // On web, permission_handler_html's `_toPermissionStatus` maps the
    // Permissions API's `'prompt'` (Ask/undecided) state AND unknown states to
    // `PermissionStatus.denied`, and `'denied'` to `permanentlyDenied`
    // (permission_handler_html web_delegate.dart). So a `.status` query cannot
    // be trusted as "is it really blocked" — and on some targets (e.g. Android
    // Chrome) it can report `permanentlyDenied` for a camera that is actually
    // requestable. Pre-checking it would short-circuit to the blocked UI before
    // Chrome's native prompt (triggered by getUserMedia) ever appears.
    //
    // Instead, treat `Permission.camera.request()` (which on web calls
    // getUserMedia and drives the real allow/block prompt) as the sole
    // authority: only a request that resolves to a denied/permanentlyDenied
    // status — i.e. a real getUserMedia failure such as NotAllowedError — is a
    // genuine block. Undecided ("Ask") falls through and triggers the prompt.
    // ---- DIAGNOSTIC LOGGING (temporary) -------------------------------------
    // Log the RAW permission_handler result (every enum value, not just
    // booleans) so we can see exactly what permission_handler reports when all
    // OS/browser settings look fine yet the app still resolves to blocked.
    debugPrint(
      '[CameraPerm] kIsWeb=$kIsWeb, forceEmbedded=$forceEmbedded, '
      'canUseGoogle=$_canUseGoogleCodeScanner',
    );
    final cameraStatus = await Permission.camera.request();
    debugPrint(
      '[CameraPerm] Permission.camera.request() raw: status=$cameraStatus '
      '(name=${cameraStatus.name}), '
      'isGranted=${cameraStatus.isGranted}, '
      'isDenied=${cameraStatus.isDenied}, '
      'isPermanentlyDenied=${cameraStatus.isPermanentlyDenied}, '
      'isRestricted=${cameraStatus.isRestricted}, '
      'isLimited=${cameraStatus.isLimited}, '
      'isProvisional=${cameraStatus.isProvisional}',
    );
    if (cameraStatus.isDenied) {
      setState(() {
        _cameraPermissionGranted = false;
        _scanSessionOpen = false;
        _errorMessage = kIsWeb
            ? 'Camera access was blocked. Click the camera icon in the browser\u2019s address bar, choose \u201cAllow\u201d, then restart the scan.'
            : 'Camera permission denied. Please allow camera access to scan the QR code.';
        _infoMessage = null;
        _isLoading = false;
      });
      return false;
    }

    if (cameraStatus.isPermanentlyDenied) {
      setState(() {
        _cameraPermissionGranted = false;
        _scanSessionOpen = false;
        _errorMessage = kIsWeb
            ? 'Camera access is blocked. Click the camera icon in your browser\u2019s address bar, choose \u201cAllow\u201d, then reload the page to continue.'
            : 'Camera permission is permanently denied. Enable it from app settings to continue.';
        _infoMessage = null;
        _isLoading = false;
      });
      if (!kIsWeb) {
        openAppSettings();
      }
      return false;
    }

    try {
      setState(() {
        _cameraPermissionGranted = true;
        _scannerActive = true;
        _useEmbeddedScanner = true;
      });

      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return false;

      await _startEmbeddedScannerSafely();
      await _applyInitialScannerZoom();
      return true;
    } catch (error) {
      setState(() {
        _cameraPermissionGranted = false;
        _scanSessionOpen = false;
        _errorMessage = 'Unable to start camera scanner: $error';
        _infoMessage = null;
        _isLoading = false;
      });
      return false;
    }
  }

  Future<void> _startEmbeddedScannerSafely() async {
    if (_embeddedScannerStarting || _scannerController.value.isRunning) {
      if (_scannerController.value.isRunning) {
        await _applyInitialScannerZoom();
      }
      return;
    }

    _embeddedScannerStarting = true;
    try {
      try {
        await _scannerController.start();
      } on MobileScannerException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!_scannerController.value.isRunning) {
          await _scannerController.start();
        }
      } on PlatformException {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!_scannerController.value.isRunning) {
          await _scannerController.start();
        }
      }
      await _applyInitialScannerZoom();
    } finally {
      _embeddedScannerStarting = false;
    }
  }

  Future<void> _openGoogleCodeScannerIfAvailable() async {
    if (!_canUseGoogleCodeScanner ||
        !_scannerActive ||
        _useEmbeddedScanner ||
        _nativeScanInProgress ||
        _isLoading ||
        _scannedToken != null) {
      return;
    }

    setState(() {
      _nativeScanInProgress = true;
      _infoMessage =
          'Opening Google scanner. Use the camera view to scan the admin QR code.';
    });

    try {
      final rawValue =
          await _googleCodeScannerChannel.invokeMethod<String>('scanQr');
      if (!mounted) return;
      if (rawValue == null || rawValue.trim().isEmpty) {
        setState(() {
          _scanLocking = false;
          _infoMessage =
              'Google scanner was closed. Tap the scanner area to try again.';
          _errorMessage = null;
        });
        return;
      }
      await _handleScannedRawValue(rawValue.trim());
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _useEmbeddedScanner = true;
        _cameraPermissionGranted = false;
        _infoMessage =
            'Google scanner is unavailable on this device, so the in-app scanner is ready instead.';
        _errorMessage = error.message;
      });
      await _ensureCameraIsActive(forceEmbedded: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _useEmbeddedScanner = true;
        _cameraPermissionGranted = false;
        _infoMessage =
            'Google scanner is unavailable on this device, so the in-app scanner is ready instead.';
        _errorMessage = _friendlyScanError(error);
      });
      await _ensureCameraIsActive(forceEmbedded: true);
    } finally {
      if (mounted) {
        setState(() {
          _nativeScanInProgress = false;
          _scanLocking = false;
        });
      }
    }
  }

  Future<void> _setScannerZoom(double value) async {
    final nextValue = value.clamp(0.0, 1.0);
    setState(() {
      _zoomScale = nextValue;
    });
    if (_scannerController.value.isInitialized &&
        _scannerController.value.isRunning) {
      await _applyScannerZoom(nextValue);
    }
  }

  Future<void> _applyScannerZoom(double value) async {
    if (!_scannerZoomSupported) return;
    try {
      await _scannerController.setZoomScale(value);
    } on UnsupportedError {
      // Some platforms expose the camera preview but do not support zoom.
    } on PlatformException catch (error) {
      final message = error.message ?? '';
      if (!message.toLowerCase().contains('zoom')) rethrow;
    }
  }

  Future<void> _applyInitialScannerZoom() async {
    if (!_scannerZoomSupported ||
        !_scannerController.value.isInitialized ||
        !_scannerController.value.isRunning) {
      return;
    }

    await _applyScannerZoom(_zoomScale);
  }

  String? _parseQrToken(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        final token = decoded['token']?.toString().trim();
        if (token != null && token.isNotEmpty) {
          return token;
        }
      }
    } catch (_) {
      // Continue to non-JSON parsing.
    }

    final uri = Uri.tryParse(raw);
    final uriToken = uri?.queryParameters['token']?.trim();
    if (uriToken != null && uriToken.isNotEmpty) {
      return uriToken;
    }

    if (raw.contains('=')) {
      final queryText = raw.startsWith('?') ? raw.substring(1) : raw;
      final params = Uri.splitQueryString(queryText);
      final token = params['token']?.trim();
      if (token != null && token.isNotEmpty) return token;
    }

    if (!raw.contains(' ') && raw.length >= 16) {
      return raw;
    }

    return null;
  }

  Future<Staff?> _loadCurrentStaff() async {
    final user = FirebaseContextProvider.current.auth.currentUser;
    if (user == null) return null;
    final profile = await _attendanceService.getStaffByUserIdentity(
      uid: user.uid,
      email: user.email,
    );
    if (profile == null) return null;

    final directoryProfile =
        await _attendanceService.getStaffByEmployeeId(profile.employeeId);
    if (directoryProfile != null) return directoryProfile;

    final emailProfile =
        await _attendanceService.getStaffByEmail(profile.email);
    return emailProfile ?? profile;
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
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final dateValue = item['date'];
            DateTime? parsedDate;
            if (dateValue is Timestamp) {
              parsedDate = dateValue.toDate();
            } else if (dateValue is String) {
              parsedDate = DateTime.tryParse(dateValue);
            }
            if (parsedDate == null) return null;
            return _HolidayEvent(
              date: parsedDate,
              title: item['title'] as String? ?? 'Holiday',
              category:
                  item['category'] as String? ?? _HolidayEvent.categoryOther,
              reason: item['reason'] as String? ?? 'Marked by admin.',
            );
          })
          .whereType<_HolidayEvent>()
          .toList();
    }
    return [];
  }

  bool _officeIsClosedToday(_OfficeConfig office) {
    final now = DateTime.now();
    return office.isHoliday(now) || office.isWeekendClosed(now);
  }

  Future<void> _showHolidayPopup(_OfficeConfig office) async {
    if (!mounted) return;
    final now = DateTime.now();
    final event = office.holidayEvent(now);
    final message = event != null
        ? 'Today is marked as ${event.title}. ${event.reason} Attendance cannot be recorded today.'
        : office.isHoliday(now)
            ? 'Today is marked as a holiday. Attendance cannot be recorded today.'
            : 'Today is a non-working weekend day. Attendance cannot be recorded today.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Theme(
          data: ThemeData.dark().copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: AppThemeColors.darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(
                    color: AppThemeColors.darkBorder, width: 1),
              ),
            ),
          ),
          child: AlertDialog(
            backgroundColor: AppThemeColors.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side:
                  const BorderSide(color: AppThemeColors.darkBorder, width: 1),
            ),
            title: const Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    color: _StaffScanTheme.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Holiday Notice',
                    style: TextStyle(
                      color: _StaffScanTheme.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: const TextStyle(
                color: AppThemeColors.darkMuted,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: _StaffScanTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_OfficeConfig> _loadOfficeConfig() async {
    String checkInStart = '08:30 AM';
    String checkInEnd = '10:30 AM';
    String checkOutStart = '05:00 PM';
    String checkOutEnd = '07:30 PM';

    final geoDoc = await FirebaseContextProvider.current.firestore
        .collection('geo_config')
        .doc('default')
        .get();
    if (geoDoc.exists) {
      final data = geoDoc.data()!;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        checkInStart = data['checkInStart'] ?? checkInStart;
        checkInEnd = data['checkInEnd'] ?? checkInEnd;
        checkOutStart = data['checkOutStart'] ?? checkOutStart;
        checkOutEnd = data['checkOutEnd'] ?? checkOutEnd;

        return _OfficeConfig(
          latitude: lat,
          longitude: lng,
          radius: (data['radius'] as num?)?.toDouble() ?? 50,
          checkInStart: checkInStart,
          checkInEnd: checkInEnd,
          checkOutStart: checkOutStart,
          checkOutEnd: checkOutEnd,
          saturdayWorking: data['saturdayWorking'] as bool? ?? true,
          sundayWorking: data['sundayWorking'] as bool? ?? false,
          holidayDates: _parseHolidayDates(data['holidayDates']),
          holidayEvents: _parseHolidayEvents(data['holidayEvents']),
        );
      }
    }

    final officesDoc = await FirebaseContextProvider.current.firestore
        .collection('offices')
        .doc('default')
        .get();
    if (officesDoc.exists) {
      final data = officesDoc.data()!;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        checkInStart = data['checkInStart'] ?? checkInStart;
        checkInEnd = data['checkInEnd'] ?? checkInEnd;
        checkOutStart = data['checkOutStart'] ?? checkOutStart;
        checkOutEnd = data['checkOutEnd'] ?? checkOutEnd;

        return _OfficeConfig(
          latitude: lat,
          longitude: lng,
          radius: (data['radius'] as num?)?.toDouble() ??
              (data['geoFenceRadius'] as num?)?.toDouble() ??
              50,
          checkInStart: checkInStart,
          checkInEnd: checkInEnd,
          checkOutStart: checkOutStart,
          checkOutEnd: checkOutEnd,
          saturdayWorking: data['saturdayWorking'] as bool? ?? true,
          sundayWorking: data['sundayWorking'] as bool? ?? false,
          holidayDates: _parseHolidayDates(data['holidayDates']),
          holidayEvents: _parseHolidayEvents(data['holidayEvents']),
        );
      }
    }

    throw const _OfficeConfigException(
      'Office location is not configured. Ask admin to set latitude and longitude before scanning attendance.',
    );
  }

  double _effectiveDistance({
    required double distance,
    required double accuracy,
  }) =>
      GeoFenceService.effectiveDistance(
        distanceMetres: distance,
        accuracyMetres: accuracy,
      );

  double _validationRadius(double officeRadius) =>
      GeoFenceService.validationRadius(radiusMetres: officeRadius);

  void _setOutsideGeofenceError({
    required double distance,
    required double accuracy,
    required double officeRadius,
  }) {
    final recommendedRadius = GeoFenceService.recommendedRadiusForScan(
      distanceMetres: distance,
      accuracyMetres: accuracy,
    );
    _lastOfficeDistance = distance;
    _lastLocationAccuracy = accuracy;
    _lastOfficeRadius = officeRadius;
    _lastRecommendedRadius = recommendedRadius;
    _errorMessage =
        'You are ${distance.toStringAsFixed(1)}m from the office, which is outside the ${officeRadius.toStringAsFixed(0)}m geofence.';
  }

  void _clearGeofenceGuidance() {
    _lastOfficeDistance = null;
    _lastLocationAccuracy = null;
    _lastOfficeRadius = null;
    _lastRecommendedRadius = null;
  }

  bool get _showGeofenceRecovery =>
      _lastOfficeDistance != null &&
      _lastLocationAccuracy != null &&
      _lastOfficeRadius != null &&
      _lastRecommendedRadius != null;

  Future<void> _openDeviceLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return _StaffScanTheme.present;
      case 'late':
        return _StaffScanTheme.late;
      case 'absent':
        return _StaffScanTheme.absent;
      case 'wfh':
        return _StaffScanTheme.primary;
      default:
        return _StaffScanTheme.primary;
    }
  }

  String _friendlyScanError(Object error) {
    if (error is _OfficeConfigException) {
      return error.message;
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'failed-precondition':
          return 'Attendance validation is temporarily unavailable. Please ask admin to update the database index, then try again.';
        case 'permission-denied':
          return 'You do not have access to mark attendance with this account.';
        case 'unavailable':
          return 'Unable to reach Firebase right now. Check your network and try again.';
      }
    }

    final text = error.toString();
    if (text.contains('failed-precondition') ||
        text.contains('requires an index')) {
      return 'Attendance validation is temporarily unavailable. Please ask admin to update the database index, then try again.';
    }

    return 'Unable to complete attendance validation. Please try again.';
  }

  Widget _buildActiveScannerExperience(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : media.size.height - media.padding.vertical;
        final scannerHeight = availableHeight.clamp(360.0, 1200.0).toDouble();

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: _StaffScanTheme.white,
            systemNavigationBarColor: _StaffScanTheme.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: SizedBox.expand(
            child: _buildScannerCameraFrame(
              height: scannerHeight,
              fullScreen: true,
            ),
          ),
        );
      },
    );
  }

  Widget _buildScannerCameraFrame({
    required double height,
    bool fullScreen = false,
  }) {
    final radius = fullScreen ? 0.0 : 24.0;

    return GestureDetector(
      onTap: _scannerActive &&
              !_useEmbeddedScanner &&
              !_nativeScanInProgress &&
              !_isLoading
          ? _openGoogleCodeScannerIfAvailable
          : null,
      onScaleStart:
          _scannerActive && _useEmbeddedScanner && _scannerZoomSupported
              ? (_) {
                  _zoomScaleAtGestureStart = _zoomScale;
                }
              : null,
      onScaleUpdate:
          _scannerActive && _useEmbeddedScanner && _scannerZoomSupported
              ? (details) {
                  if (details.scale == 1.0) return;
                  final nextZoom = _zoomScaleAtGestureStart * details.scale;
                  unawaited(_setScannerZoom(nextZoom));
                }
              : null,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: _StaffScanTheme.black,
          borderRadius: BorderRadius.circular(radius),
          border:
              fullScreen ? null : Border.all(color: _StaffScanTheme.infoBorder),
          boxShadow: fullScreen
              ? null
              : const [
                  BoxShadow(
                    color: _StaffScanTheme.shadow,
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _scannerActive
                  ? _useEmbeddedScanner
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final cameraWidth = constraints.maxWidth;
                            final cameraHeight = constraints.maxHeight;
                            final side = ((fullScreen ? 0.62 : 0.54) *
                                        cameraWidth)
                                    .clamp(0.0, cameraHeight)
                                    .toDouble();
                            final scanWindow = Rect.fromCenter(
                              center: Offset(
                                cameraWidth / 2,
                                cameraHeight / 2,
                              ),
                              width: side,
                              height: side,
                            );
                            return MobileScanner(
                              key: ValueKey(
                                'staff_qr_embedded_scanner_$_scanSessionOpen',
                              ),
                              controller: _scannerController,
                              fit: BoxFit.cover,
                              scanWindow: scanWindow,
                              onDetect: _handleBarcode,
                            );
                          },
                        )
                      : Container(
                          color: _StaffScanTheme.black,
                          child: Center(
                            child: _nativeScanInProgress
                                ? const SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _StaffScanTheme.white,
                                      ),
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 96,
                                        height: 96,
                                        decoration: BoxDecoration(
                                          color: _StaffScanTheme.white
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(28),
                                        ),
                                        child: const Icon(
                                          Icons.qr_code_scanner_rounded,
                                          color: _StaffScanTheme.white,
                                          size: 54,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Open Google Scanner',
                                        style: TextStyle(
                                          color: _StaffScanTheme.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Auto zoom is enabled',
                                        style: TextStyle(
                                          color: _StaffScanTheme.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        )
                  : Container(color: _StaffScanTheme.soft),
              if (_scannerActive) ...[
                Container(color: _StaffScanTheme.black.withValues(alpha: 0.14)),
                if (_useEmbeddedScanner) _buildBarcodeTrackingOverlay(),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: fullScreen ? 0.62 : 0.54,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _GoogleScannerFrame(isLocking: _scanLocking),
                          if (_useEmbeddedScanner &&
                              !_scanLocking &&
                              _scannedToken == null)
                            const IgnorePointer(
                              child: _ScanSweepOverlay(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (fullScreen) ...[
                  Positioned(
                    top: 42,
                    left: 48,
                    child: _ScannerCircleButton(
                      icon: Icons.close_rounded,
                      label: 'Close',
                      onTap: () {
                        unawaited(() async {
                          if (_scannerController.value.isRunning) {
                            await _scannerController.stop();
                          }
                          if (!mounted) return;
                          setState(() {
                            _scanSessionOpen = false;
                            _scannerActive = false;
                            _scannedToken = null;
                            _scanLocking = false;
                          });
                        }());
                      },
                    ),
                  ),
                  const Positioned(
                    top: 58,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Scan code',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _StaffScanTheme.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (!kIsWeb)
                    Positioned(
                      top: 42,
                      right: 48,
                      child: _ScannerCircleButton(
                        icon: Icons.flash_off_rounded,
                        label: 'Torch',
                        onTap: _useEmbeddedScanner
                            ? _scannerController.toggleTorch
                            : null,
                      ),
                    ),
                  const Positioned(
                    left: 54,
                    right: 54,
                    bottom: 58,
                    child: _GoogleScannerAttribution(),
                  ),
                ] else ...[
                  if (!kIsWeb)
                    Positioned(
                      top: 18,
                      right: 80,
                      child: _ScannerIconPill(
                        icon: Icons.flash_off_rounded,
                        label: 'Torch',
                        onTap: _useEmbeddedScanner
                            ? _scannerController.toggleTorch
                            : null,
                      ),
                    ),
                  const Positioned(
                    top: 18,
                    right: 22,
                    child: _ScannerIconPill(
                      icon: Icons.qr_code_2_rounded,
                      label: 'QR',
                    ),
                  ),
                ],
                if (_errorMessage != null)
                  Positioned(
                    left: fullScreen ? 48 : 18,
                    right: fullScreen ? 48 : 18,
                    top: fullScreen ? 116 : 76,
                    child: _ScannerMessagePill(
                      icon: Icons.error_rounded,
                      message: _errorMessage!,
                      color: _StaffScanTheme.absent,
                    ),
                  )
                else if (_infoMessage != null && !fullScreen)
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 76,
                    child: _ScannerMessagePill(
                      icon: Icons.info_rounded,
                      message: _infoMessage!,
                      color: _StaffScanTheme.white,
                    ),
                  ),
                if (!fullScreen)
                  Positioned(
                    left: 56,
                    right: 56,
                    bottom: 36,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _StaffScanTheme.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: _StaffScanTheme.blackShade,
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Scan the admin QR code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _StaffScanTheme.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                const Positioned(
                  top: 20,
                  left: 20,
                  child: _CornerBracket(color: _StaffScanTheme.primary),
                ),
                Positioned(
                  top: 20,
                  right: 20,
                  child: Transform.rotate(
                    angle: 1.5708,
                    child: const _CornerBracket(color: _StaffScanTheme.primary),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: Transform.rotate(
                    angle: -1.5708,
                    child: const _CornerBracket(color: _StaffScanTheme.primary),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Transform.rotate(
                    angle: 3.14159,
                    child: const _CornerBracket(color: _StaffScanTheme.primary),
                  ),
                ),
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: _StaffScanTheme.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.qr_code_rounded,
                      color: _StaffScanTheme.white,
                      size: 64,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarcodeTrackingOverlay() {
    return ValueListenableBuilder(
      valueListenable: _scannerController,
      builder: (context, value, child) {
        if (!value.isInitialized || !value.isRunning || value.error != null) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<BarcodeCapture>(
          stream: _scannerController.barcodes,
          builder: (context, snapshot) {
            final capture = snapshot.data;
            if (capture == null || capture.barcodes.isEmpty) {
              return const SizedBox.shrink();
            }

            final barcode = capture.barcodes.first;
            if (barcode.corners.isEmpty ||
                capture.size.isEmpty ||
                value.size.isEmpty) {
              return const SizedBox.shrink();
            }

            return CustomPaint(
              painter: _LensBarcodeTrackerPainter(
                barcodeCorners: barcode.corners,
                barcodeSize: capture.size,
                cameraPreviewSize: value.size,
                isLocking: _scanLocking,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildErrorPanel() {
    final showRecovery = _showGeofenceRecovery;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _StaffScanTheme.absent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: _StaffScanTheme.absent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_rounded,
                color: _StaffScanTheme.absent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: _StaffScanTheme.absent,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (showRecovery) ...[
            const SizedBox(height: 14),
            _buildGeoRecoveryDetails(),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _startScanFlow,
                  icon: const Icon(Icons.gps_fixed_rounded, size: 17),
                  label: const Text('Retry GPS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _StaffScanTheme.absentSoft,
                    side: const BorderSide(color: _StaffScanTheme.absentSoft),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openDeviceLocationSettings,
                  icon: const Icon(Icons.settings_rounded, size: 17),
                  label: const Text('Location Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _StaffScanTheme.absentSoft,
                    side: const BorderSide(color: _StaffScanTheme.absentSoft),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeoRecoveryDetails() {
    final distance = _lastOfficeDistance ?? 0;
    final accuracy = _lastLocationAccuracy ?? 0;
    final radius = _lastOfficeRadius ?? 0;
    final recommended = _lastRecommendedRadius ?? 0;
    final safety = (recommended - distance - accuracy).clamp(0, recommended);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _recoveryLine(
          'Radius check',
          '${distance.toStringAsFixed(1)}m distance > ${radius.toStringAsFixed(0)}m allowed radius',
        ),
        _recoveryLine(
          'GPS accuracy',
          '${accuracy.toStringAsFixed(1)}m. Turn on high accuracy and retry.',
        ),
        _recoveryLine(
          'If admin wants to allow this point',
          'minimum radius is about ${recommended.toStringAsFixed(0)}m (${distance.toStringAsFixed(1)} + ${accuracy.toStringAsFixed(1)} + ${safety.toStringAsFixed(0)} safety).',
        ),
        const SizedBox(height: 8),
        const Text(
          'To keep radius strict: move closer to the office pin, stand near the entrance/window, enable high accuracy GPS, then tap Retry GPS.',
          style: TextStyle(
            color: _StaffScanTheme.absentFaint,
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _recoveryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: _StaffScanTheme.absentFaint,
            fontSize: 12,
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.isMobile(context);

    if (_showActiveScannerOnly) {
      return _buildActiveScannerExperience(context);
    }

    if (_lastSubmissionResult?.success == true) {
      return _buildScrollableScanContent(
        _buildCompletedAttendanceView(_lastSubmissionResult!),
      );
    }

    return _buildScrollableScanContent(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_StaffScanTheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _infoMessage ?? 'Verifying location...',
                    style: const TextStyle(color: _StaffScanTheme.muted),
                  ),
                ],
              ),
            )
          else if (_errorMessage != null)
            _buildErrorPanel()
          else if (!_locationEnabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _StaffScanTheme.chipAmber,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _StaffScanTheme.chipAmberBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.location_off_rounded,
                      color: _StaffScanTheme.warning, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Location not enabled. Enable location to proceed with attendance.',
                      style: TextStyle(
                        color: _StaffScanTheme.warning,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_withinRadius)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _StaffScanTheme.chipGreen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _StaffScanTheme.chipGreenBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: _StaffScanTheme.present, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Location verified! You are within ${_radiusInMeters.toStringAsFixed(0)}m of the office.',
                      style: const TextStyle(
                        color: _StaffScanTheme.present,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_scannedToken == null) ...[
            const SizedBox(height: 12),
            _buildScannerCameraFrame(
              height: isMobile ? 520 : 640,
            ),
          ] else ...[
            const SizedBox(height: 12),
            _buildQrReadyPanel(),
            const SizedBox(height: 20),
            _buildVerificationDetailsPanel(),
          ],
          if (_infoMessage != null && _scannedToken == null) ...[
            const SizedBox(height: 20),
            _buildInfoPanel(_infoMessage!),
          ],
          const SizedBox(height: 24),
          if (_scannedToken == null)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _hasCheckedOutToday
                    ? null
                    : (!_isLoading ? _startScanFlow : null),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(_startScanLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _StaffScanTheme.success,
                  disabledBackgroundColor: _StaffScanTheme.disabled,
                  foregroundColor: _StaffScanTheme.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: !_isLoading ? _markAttendance : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _StaffScanTheme.success,
                  disabledBackgroundColor: _StaffScanTheme.disabled,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(_StaffScanTheme.white),
                        ),
                      )
                    : Text(
                        _markAttendanceLabel,
                        style: const TextStyle(
                          color: _StaffScanTheme.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          if (_scannedToken != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: !_isLoading ? _resetScanner : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _StaffScanTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Scan Again',
                    style: TextStyle(
                      color: _StaffScanTheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildScrollableScanContent(Widget child) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      child: child,
    );
  }

  Widget _buildInfoPanel(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _StaffScanTheme.soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StaffScanTheme.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_rounded,
            color: _StaffScanTheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _StaffScanTheme.primary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrReadyPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _StaffScanTheme.chipGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _StaffScanTheme.chipGreenBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_rounded,
              color: _StaffScanTheme.present, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'QR verified. Review the details, then tap the button below to submit.',
              style: TextStyle(
                color: _StaffScanTheme.present,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationDetailsPanel() {
    final staff = _scannedStaff;
    final scanTime = _lastScanTime ?? DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _StaffScanTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _StaffScanTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verification Details',
            style: TextStyle(
              color: _StaffScanTheme.text,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow(
            label: 'Name',
            value: staff?.name.isNotEmpty == true ? staff!.name : '-',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 14),
          _DetailRow(
            label: 'Employee ID',
            value:
                staff?.employeeId.isNotEmpty == true ? staff!.employeeId : '-',
            icon: Icons.badge_rounded,
          ),
          const SizedBox(height: 14),
          _DetailRow(
            label: 'Position',
            value: staff?.position.isNotEmpty == true
                ? staff!.position
                : (staff?.role?.isNotEmpty == true ? staff!.role! : '-'),
            icon: Icons.work_rounded,
          ),
          const SizedBox(height: 14),
          _DetailRow(
            label: 'Designation',
            value:
                staff?.department.isNotEmpty == true ? staff!.department : '-',
            icon: Icons.domain_rounded,
          ),
          const SizedBox(height: 14),
          _DetailRow(
            label: 'Date',
            value: DateFormat('MMM d, y').format(scanTime),
            icon: Icons.calendar_today_rounded,
          ),
          const SizedBox(height: 14),
          _DetailRow(
            label: 'Scan Time',
            value: DateFormat('hh:mm a').format(scanTime),
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedAttendanceView(AttendanceSubmissionResult result) {
    final isCheckOut = result.action == AttendanceSubmissionAction.checkOut ||
        result.action == AttendanceSubmissionAction.earlyCheckOut;
    final actionLabel = isCheckOut
        ? 'Check-out'
        : result.action == AttendanceSubmissionAction.tempExit
            ? 'Temporary exit'
            : result.action == AttendanceSubmissionAction.reEntry
                ? 'Re-entry'
                : 'Check-in';
    final statusColor =
        result.action == AttendanceSubmissionAction.earlyCheckOut
            ? _StaffScanTheme.warning
            : _getStatusColor(result.status);
    final submittedAt = _lastSubmissionTime ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _StaffScanTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _StaffScanTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCheckOut ? Icons.logout_rounded : Icons.login_rounded,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$actionLabel recorded',
                          style: const TextStyle(
                            color: _StaffScanTheme.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.message,
                          style: const TextStyle(
                            color: _StaffScanTheme.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 520;
                  final columns = isNarrow
                      ? 1
                      : constraints.maxWidth < 760
                          ? 2
                          : 4;
                  final itemWidth =
                      (constraints.maxWidth - (12 * (columns - 1))) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _AttendanceStat(
                          label: 'Action',
                          value: actionLabel,
                          color: statusColor,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _AttendanceStat(
                          label: 'Time',
                          value: DateFormat('hh:mm a').format(submittedAt),
                          color: _StaffScanTheme.present,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _AttendanceStat(
                          label: 'Day',
                          value: DateFormat('EEEE').format(submittedAt),
                          color: _StaffScanTheme.info,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _AttendanceStat(
                          label: 'Date',
                          value: DateFormat('MMM d, y').format(submittedAt),
                          color: _StaffScanTheme.primary,
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (_scannedStaff != null) ...[
                const SizedBox(height: 22),
                _DetailRow(
                  label: 'Name',
                  value: _scannedStaff!.name,
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 14),
                _DetailRow(
                  label: 'Employee ID',
                  value: _scannedStaff!.employeeId,
                  icon: Icons.badge_rounded,
                ),
                const SizedBox(height: 14),
                _DetailRow(
                  label: 'Designation',
                  value: _scannedStaff!.department.isNotEmpty
                      ? _scannedStaff!.department
                      : '-',
                  icon: Icons.domain_rounded,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _hasCheckedOutToday ? null : _resetScanner,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan Again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _StaffScanTheme.primary,
              side: const BorderSide(color: _StaffScanTheme.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _DialogDetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DialogDetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppThemeColors.darkMuted, size: 18),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppThemeColors.darkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _StaffScanTheme.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _OfficeConfig {
  final double latitude;
  final double longitude;
  final double radius;
  final String checkInStart;
  final String checkInEnd;
  final String checkOutStart;
  final String checkOutEnd;
  final bool saturdayWorking;
  final bool sundayWorking;
  final Set<String> holidayDates;
  final List<_HolidayEvent> holidayEvents;

  const _OfficeConfig({
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.checkInStart = '08:30 AM',
    this.checkInEnd = '10:30 AM',
    this.checkOutStart = '05:00 PM',
    this.checkOutEnd = '07:30 PM',
    this.saturdayWorking = true,
    this.sundayWorking = false,
    this.holidayDates = const {},
    this.holidayEvents = const [],
  });

  bool isHoliday(DateTime date) {
    final key = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return holidayDates.contains(key) ||
        holidayEvents.any((event) => event.isSameDate(date));
  }

  _HolidayEvent? holidayEvent(DateTime date) {
    for (final event in holidayEvents) {
      if (event.isSameDate(date)) return event;
    }
    return null;
  }

  bool isWeekendClosed(DateTime date) {
    if (date.weekday == DateTime.saturday) return !saturdayWorking;
    if (date.weekday == DateTime.sunday) return !sundayWorking;
    return false;
  }
}

class _OfficeConfigException implements Exception {
  final String message;

  const _OfficeConfigException(this.message);
}

class _HolidayEvent {
  final DateTime date;
  final String title;
  final String category;
  final String reason;

  static const String categoryOther = 'Other';

  const _HolidayEvent({
    required this.date,
    required this.title,
    required this.category,
    required this.reason,
  });

  bool isSameDate(DateTime other) {
    return date.year == other.year &&
        date.month == other.month &&
        date.day == other.day;
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _StaffScanTheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _StaffScanTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: _StaffScanTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScannerCornerArcs {
  static const _topLeftColor = AppThemeColors.googleBlue;
  static const _topRightColor = AppThemeColors.googleYellow;
  static const _bottomLeftColor = AppThemeColors.googleGreen;
  static const _bottomRightColor = AppThemeColors.googleRed;

  static void draw(
    Canvas canvas, {
    required Rect topLeft,
    required Rect topRight,
    required Rect bottomLeft,
    required Rect bottomRight,
    required double strokeWidth,
    required double opacity,
  }) {
    Paint paint(Color color) {
      return Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.square;
    }

    canvas.drawArc(
      topLeft,
      3.14159,
      1.5708,
      false,
      paint(_topLeftColor),
    );
    canvas.drawArc(
      topRight,
      4.71239,
      1.5708,
      false,
      paint(_topRightColor),
    );
    canvas.drawArc(
      bottomLeft,
      1.5708,
      1.5708,
      false,
      paint(_bottomLeftColor),
    );
    canvas.drawArc(
      bottomRight,
      0,
      1.5708,
      false,
      paint(_bottomRightColor),
    );
  }
}

class _LensBarcodeTrackerPainter extends CustomPainter {
  final List<Offset> barcodeCorners;
  final Size barcodeSize;
  final Size cameraPreviewSize;
  final bool isLocking;

  const _LensBarcodeTrackerPainter({
    required this.barcodeCorners,
    required this.barcodeSize,
    required this.cameraPreviewSize,
    required this.isLocking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barcodeCorners.isEmpty ||
        barcodeSize.isEmpty ||
        cameraPreviewSize.isEmpty) {
      return;
    }

    final fitted = applyBoxFit(BoxFit.cover, cameraPreviewSize, size);
    final horizontalPadding = (size.width - fitted.destination.width) / 2;
    final verticalPadding = (size.height - fitted.destination.height) / 2;

    final ratioWidth = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? barcodeSize.width / fitted.destination.width
        : cameraPreviewSize.width / fitted.destination.width;
    final ratioHeight = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? barcodeSize.height / fitted.destination.height
        : cameraPreviewSize.height / fitted.destination.height;

    final points = [
      for (final point in barcodeCorners)
        Offset(
          point.dx / ratioWidth + horizontalPadding,
          point.dy / ratioHeight + verticalPadding,
        ),
    ];

    if (points.length < 4) return;

    final rawBounds = (Path()..addPolygon(points, true)).getBounds();
    final bounds = rawBounds.inflate(14).intersect(Offset.zero & size);
    if (bounds.isEmpty) return;

    final glowPaint = Paint()
      ..color = _StaffScanTheme.white.withValues(alpha: isLocking ? 0.32 : 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    _drawCornerArcs(canvas, bounds, glowPaint);
    _drawColoredCornerArcs(canvas, bounds);
  }

  void _drawCornerArcs(Canvas canvas, Rect bounds, Paint paint) {
    final arcSize = bounds.shortestSide.clamp(42.0, 92.0);
    final topLeft = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      arcSize,
      arcSize,
    );
    final topRight = Rect.fromLTWH(
      bounds.right - arcSize,
      bounds.top,
      arcSize,
      arcSize,
    );
    final bottomLeft = Rect.fromLTWH(
      bounds.left,
      bounds.bottom - arcSize,
      arcSize,
      arcSize,
    );
    final bottomRight = Rect.fromLTWH(
      bounds.right - arcSize,
      bounds.bottom - arcSize,
      arcSize,
      arcSize,
    );

    canvas.drawArc(topLeft, 3.14159, 1.5708, false, paint);
    canvas.drawArc(topRight, 4.71239, 1.5708, false, paint);
    canvas.drawArc(bottomLeft, 1.5708, 1.5708, false, paint);
    canvas.drawArc(bottomRight, 0, 1.5708, false, paint);
  }

  void _drawColoredCornerArcs(Canvas canvas, Rect bounds) {
    final arcSize = bounds.shortestSide.clamp(42.0, 92.0);
    final topLeft = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      arcSize,
      arcSize,
    );
    final topRight = Rect.fromLTWH(
      bounds.right - arcSize,
      bounds.top,
      arcSize,
      arcSize,
    );
    final bottomLeft = Rect.fromLTWH(
      bounds.left,
      bounds.bottom - arcSize,
      arcSize,
      arcSize,
    );
    final bottomRight = Rect.fromLTWH(
      bounds.right - arcSize,
      bounds.bottom - arcSize,
      arcSize,
      arcSize,
    );

    _ScannerCornerArcs.draw(
      canvas,
      topLeft: topLeft,
      topRight: topRight,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
      strokeWidth: isLocking ? 5 : 4,
      opacity: 1,
    );
  }

  @override
  bool shouldRepaint(covariant _LensBarcodeTrackerPainter oldDelegate) {
    return oldDelegate.barcodeCorners != barcodeCorners ||
        oldDelegate.barcodeSize != barcodeSize ||
        oldDelegate.cameraPreviewSize != cameraPreviewSize ||
        oldDelegate.isLocking != isLocking;
  }
}

class _CornerBracket extends StatelessWidget {
  final Color color;

  const _CornerBracket({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _CornerBracketPainter(color: color),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;

  const _CornerBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(0, 0),
      const Offset(25, 0),
      paint,
    );
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, 25),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GoogleScannerFrame extends StatefulWidget {
  final bool isLocking;

  const _GoogleScannerFrame({this.isLocking = false});

  @override
  State<_GoogleScannerFrame> createState() => _GoogleScannerFrameState();
}

class _GoogleScannerFrameState extends State<_GoogleScannerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);
  late final Animation<double> _breath = CurvedAnimation(
    parent: _breathController,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        return CustomPaint(
          painter: _GoogleScannerFramePainter(
            breath: _breath.value,
            isLocking: widget.isLocking,
          ),
        );
      },
    );
  }
}

class _GoogleScannerFramePainter extends CustomPainter {
  static const _topLeft = AppThemeColors.googleBlue;
  static const _topRight = AppThemeColors.googleYellow;
  static const _bottomLeft = AppThemeColors.googleGreenDark;
  static const _bottomRight = AppThemeColors.googleRed;

  final double breath;
  final bool isLocking;

  const _GoogleScannerFramePainter({
    this.breath = 0.5,
    this.isLocking = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final breathe = 0.82 + 0.18 * breath;
    final strokeWidth =
        (size.shortestSide * 0.018).clamp(6.0, 10.0) * (isLocking ? 1.35 : 1.0);
    final radius = size.shortestSide * 0.14;
    final arm = size.shortestSide * 0.31;

    Paint paint(Color color) => Paint()
      ..color = color.withValues(alpha: breathe)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round;

    final topLeft = Path()
      ..moveTo(arm, 0)
      ..lineTo(radius, 0)
      ..quadraticBezierTo(0, 0, 0, radius)
      ..lineTo(0, arm);
    final topRight = Path()
      ..moveTo(size.width - arm, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, arm);
    final bottomLeft = Path()
      ..moveTo(0, size.height - arm)
      ..lineTo(0, size.height - radius)
      ..quadraticBezierTo(0, size.height, radius, size.height)
      ..lineTo(arm, size.height);
    final bottomRight = Path()
      ..moveTo(size.width, size.height - arm)
      ..lineTo(size.width, size.height - radius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - radius,
        size.height,
      )
      ..lineTo(size.width - arm, size.height);

    if (isLocking) {
      _drawSuccessGlow(
        canvas,
        strokeWidth * 3.2,
        size,
        topLeft,
        topRight,
        bottomLeft,
        bottomRight,
      );
    }

    canvas.drawPath(topLeft, paint(_topLeft));
    canvas.drawPath(topRight, paint(_topRight));
    canvas.drawPath(bottomLeft, paint(_bottomLeft));
    canvas.drawPath(bottomRight, paint(_bottomRight));
  }

  void _drawSuccessGlow(
    Canvas canvas,
    double strokeWidth,
    Size size,
    Path topLeft,
    Path topRight,
    Path bottomLeft,
    Path bottomRight,
  ) {
    final glow = Paint()
      ..color = _StaffScanTheme.success.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    canvas.drawPath(topLeft, glow);
    canvas.drawPath(topRight, glow);
    canvas.drawPath(bottomLeft, glow);
    canvas.drawPath(bottomRight, glow);
  }

  @override
  bool shouldRepaint(covariant _GoogleScannerFramePainter oldDelegate) {
    return oldDelegate.breath != breath || oldDelegate.isLocking != isLocking;
  }
}

class _ScanSweepOverlay extends StatefulWidget {
  const _ScanSweepOverlay();

  @override
  State<_ScanSweepOverlay> createState() => _ScanSweepOverlayState();
}

class _ScanSweepOverlayState extends State<_ScanSweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ScanSweepPainter(position: _controller.value),
        );
      },
    );
  }
}

class _ScanSweepPainter extends CustomPainter {
  final double position;

  const _ScanSweepPainter({required this.position});

  @override
  void paint(Canvas canvas, Size size) {
    final fadeSpan = size.height * 0.12;
    final y = position * size.height;

    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _StaffScanTheme.success.withValues(alpha: 0.0),
        _StaffScanTheme.success.withValues(alpha: 0.9),
        _StaffScanTheme.success.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(
      Rect.fromLTWH(0, y - fadeSpan, size.width, fadeSpan * 2),
    );

    final band = Paint()..shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, y - fadeSpan, size.width, fadeSpan * 2),
      band,
    );

    final core = Paint()
      ..color = _StaffScanTheme.success.withValues(alpha: 0.95)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), core);
  }

  @override
  bool shouldRepaint(covariant _ScanSweepPainter oldDelegate) {
    return oldDelegate.position != position;
  }
}

class _ScannerCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ScannerCircleButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 78,
      height: 78,
      decoration: const BoxDecoration(
        color: _StaffScanTheme.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _StaffScanTheme.black, size: 52),
    );

    return Tooltip(
      message: label,
      child: onTap == null
          ? button
          : InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: button,
            ),
    );
  }
}

class _GoogleScannerAttribution extends StatelessWidget {
  const _GoogleScannerAttribution();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.shield_outlined,
          color: _StaffScanTheme.grey,
          size: 42,
        ),
        const SizedBox(width: 18),
        const Expanded(
          child: Text(
            'Scanned by Google on behalf of TRAKR',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _StaffScanTheme.greyLight,
              fontSize: 24,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: _StaffScanTheme.greyLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.info_rounded,
            color: _StaffScanTheme.black,
            size: 28,
          ),
        ),
      ],
    );
  }
}

class _ScannerIconPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ScannerIconPill({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _StaffScanTheme.black.withValues(alpha: 0.58),
        shape: BoxShape.circle,
        border:
            Border.all(color: _StaffScanTheme.white.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: _StaffScanTheme.white, size: 23),
    );

    return Tooltip(
      message: label,
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: child,
            ),
    );
  }
}

class _ScannerMessagePill extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _ScannerMessagePill({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _StaffScanTheme.black.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AttendanceStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _StaffScanTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
