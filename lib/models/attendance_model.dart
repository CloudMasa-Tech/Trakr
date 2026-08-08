import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

enum AttendanceStatus { present, absent, late, wfh, leave }

enum AttendanceState {
  none('NONE'),
  checkIn('CHECK_IN'),
  tempExit('TEMP_EXIT'),
  reEntry('RE_ENTRY'),
  finalCheckout('FINAL_CHECKOUT'),
  unauthorizedExit('UNAUTHORIZED_EXIT');

  final String firestoreValue;
  const AttendanceState(this.firestoreValue);
}

class AttendanceModel {
  static const int halfDayAbsentMinutes = 180;
  static const int fullDayAbsentMinutes = 360;

  final String id;
  final String employeeId;
  final String employeeName;
  final String department;
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final double? latitude;
  final double? longitude;
  final String? employeePhotoUrl;
  final String? employeePhotoBase64;
  final bool geoTagRequired;
  final DateTime date;
  final int lateMinutes;
  final String arrivalBand;
  final String policyAction;
  final String policyLabel;
  final int? storedWorkingMinutes;
  final String? storedWorkingHours;
  final bool _storedIsEarlyCheckout;
  final int earlyCheckoutMinutes;
  final int latePendingMinutes;
  final int earlyCheckoutPendingMinutes;
  final int permissionPendingMinutes;
  final int storedPendingMinutes;
  final String pendingAbsenceStatus;
  final int cumulativePendingMinutes;
  final String cumulativeAbsenceStatus;
  final String? officeStartTime;
  final String? officeCheckOutStartTime;
  final String? officeEndTime;
  final AttendanceState currentState;
  final String managerName;
  final String? permissionId;
  final DateTime? permissionApprovedUntil;
  final DateTime? lastExitTime;
  final DateTime? lastReturnTime;
  final int permissionDelayMinutes;
  final bool profileRemoved;

  AttendanceModel({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.department,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.latitude,
    this.longitude,
    this.employeePhotoUrl,
    this.employeePhotoBase64,
    this.geoTagRequired = true,
    required this.date,
    this.lateMinutes = 0,
    this.arrivalBand = 'green',
    this.policyAction = 'none',
    this.policyLabel = '',
    this.storedWorkingMinutes,
    this.storedWorkingHours,
    bool isEarlyCheckout = false,
    this.earlyCheckoutMinutes = 0,
    this.latePendingMinutes = 0,
    this.earlyCheckoutPendingMinutes = 0,
    this.permissionPendingMinutes = 0,
    this.storedPendingMinutes = 0,
    this.pendingAbsenceStatus = 'none',
    this.cumulativePendingMinutes = 0,
    this.cumulativeAbsenceStatus = 'none',
    this.officeStartTime,
    this.officeCheckOutStartTime,
    this.officeEndTime,
    this.currentState = AttendanceState.none,
    this.managerName = '',
    this.permissionId,
    this.permissionApprovedUntil,
    this.lastExitTime,
    this.lastReturnTime,
    this.permissionDelayMinutes = 0,
    this.profileRemoved = false,
  }) : _storedIsEarlyCheckout = isEarlyCheckout;

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AttendanceModel(
      id: doc.id,
      employeeId: d['employeeId'] ?? '',
      employeeName: d['employeeName'] ?? '',
      department: d['department'] ?? '',
      status: _status(d['status'] ?? 'absent'),
      checkInTime: d['checkInTime'] != null
          ? (d['checkInTime'] as Timestamp).toDate()
          : null,
      checkOutTime: d['checkOutTime'] != null
          ? (d['checkOutTime'] as Timestamp).toDate()
          : null,
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      employeePhotoUrl:
          d['employeePhotoUrl'] as String? ?? d['photoUrl'] as String?,
      employeePhotoBase64:
          d['employeePhotoBase64'] as String? ?? d['photoBase64'] as String?,
      geoTagRequired: d['geoTagRequired'] ?? true,
      date: d['date'] != null
          ? (d['date'] as Timestamp).toDate()
          : DateTime.now(),
      lateMinutes: (d['lateMinutes'] as num?)?.toInt() ?? 0,
      arrivalBand: d['arrivalBand'] ?? 'green',
      policyAction: d['policyAction'] ?? 'none',
      policyLabel: d['policyLabel'] ?? '',
      storedWorkingMinutes: (d['workingMinutes'] as num?)?.toInt(),
      storedWorkingHours: d['workingHours'] as String?,
      isEarlyCheckout: d['isEarlyCheckout'] as bool? ?? false,
      earlyCheckoutMinutes: (d['earlyCheckoutMinutes'] as num?)?.toInt() ?? 0,
      latePendingMinutes: (d['latePendingMinutes'] as num?)?.toInt() ?? 0,
      earlyCheckoutPendingMinutes:
          (d['earlyCheckoutPendingMinutes'] as num?)?.toInt() ?? 0,
      permissionPendingMinutes:
          (d['permissionPendingMinutes'] as num?)?.toInt() ??
              (d['permissionMinutes'] as num?)?.toInt() ??
              0,
      storedPendingMinutes: (d['pendingMinutes'] as num?)?.toInt() ?? 0,
      pendingAbsenceStatus: d['pendingAbsenceStatus'] as String? ?? 'none',
      cumulativePendingMinutes:
          (d['cumulativePendingMinutes'] as num?)?.toInt() ?? 0,
      cumulativeAbsenceStatus:
          d['cumulativeAbsenceStatus'] as String? ?? 'none',
      officeStartTime: d['officeStartTime'] as String?,
      officeCheckOutStartTime: d['officeCheckOutStartTime'] as String?,
      officeEndTime: d['officeEndTime'] as String?,
      currentState: _state(d['currentState'] ?? 'NONE'),
      managerName: d['managerName'] as String? ?? '',
      permissionId: d['permissionId'] as String?,
      permissionApprovedUntil:
          (d['permissionApprovedUntil'] as Timestamp?)?.toDate(),
      lastExitTime: (d['lastExitTime'] as Timestamp?)?.toDate(),
      lastReturnTime: (d['lastReturnTime'] as Timestamp?)?.toDate(),
      permissionDelayMinutes:
          (d['permissionDelayMinutes'] as num?)?.toInt() ?? 0,
      profileRemoved: d['profileRemoved'] as bool? ?? false,
    );
  }

  static AttendanceState _state(String s) {
    return AttendanceState.values.firstWhere(
      (e) => e.firestoreValue == s,
      orElse: () => AttendanceState.none,
    );
  }

  static AttendanceStatus _status(String s) {
    switch (s.trim().toLowerCase()) {
      case 'present':
        return AttendanceStatus.present;
      case 'late':
        return AttendanceStatus.late;
      case 'wfh':
        return AttendanceStatus.wfh;
      case 'leave':
        return AttendanceStatus.leave;
      default:
        return AttendanceStatus.absent;
    }
  }

  String get checkInFormatted {
    if (checkInTime == null) return '-';
    return _formatIndianTime(checkInTime!);
  }

  String get checkOutFormatted {
    if (checkOutTime == null) return '-';
    return _formatIndianTime(checkOutTime!);
  }

  bool get isCheckedOut => checkOutTime != null;

  bool get identityCleared =>
      profileRemoved ||
      (employeeName.trim().isEmpty && department.trim().isEmpty);

  String get displayEmployeeName => identityCleared ? '' : employeeName;
  String get displayEmployeeId => identityCleared ? '' : employeeId;
  String get displayDepartment => identityCleared ? '' : department;

  Uint8List? get employeePhotoBytes {
    final raw = employeePhotoBase64?.trim().isNotEmpty == true
        ? employeePhotoBase64!.trim()
        : employeePhotoUrl?.trim();
    final value = raw;
    if (value == null || value.isEmpty) return null;
    if (!value.startsWith('data:image') && employeePhotoBase64 == null) {
      return null;
    }
    final payload = value.contains(',') ? value.split(',').last : value;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  Duration? get workingDuration {
    if (checkInTime == null || checkOutTime == null) {
      return _storedWorkingDuration;
    }

    final checkInIndian = _toIndianTime(checkInTime!);
    final checkOutIndian = _toIndianTime(checkOutTime!);
    final effectiveCheckIn = _laterOf(
      checkInIndian,
      _timeOnDate(checkInIndian, officeStartTime ?? '10:30 AM'),
    );
    final effectiveCheckOut = _earlierOf(
      checkOutIndian,
      _timeOnDate(checkOutIndian, officeEndTime ?? '07:30 PM'),
    );
    final duration = effectiveCheckOut.difference(effectiveCheckIn);
    if (duration.isNegative) return Duration.zero;
    return duration;
  }

  String get workingHoursFormatted {
    final duration = workingDuration;
    if (duration == null && storedWorkingHours != null) {
      return _toHrsBased(storedWorkingHours!);
    }
    if (duration == null) return '0 min';
    return _durationToHrsBased(duration);
  }

  int get pendingMinutes {
    if (_hasCorruptedAttendedAbsentStatus) return 0;
    if (policyAction == 'half_day_leave' || _isApprovedFullDayLeave) return 0;
    if (policyAction == 'no_check_in_absent') return 0;

    if (checkInTime != null && checkOutTime != null) {
      final total = _dynamicAttendancePendingMinutes + permissionPendingMinutes;
      final maxPending = _configuredWorkingMinutes;
      return total > maxPending ? maxPending : total;
    }

    final attendancePending =
        latePendingMinutes + _effectiveEarlyCheckoutPendingMinutes;
    final componentPending = attendancePending + permissionPendingMinutes;
    if (_checkoutIsInsideConfiguredWindow) {
      return componentPending > 480 ? 480 : componentPending;
    }
    if (storedPendingMinutes > 0 || componentPending > 0) {
      if (storedPendingMinutes > 0 &&
          permissionPendingMinutes > 0 &&
          attendancePending == 0 &&
          storedPendingMinutes != componentPending) {
        final total = storedPendingMinutes + permissionPendingMinutes;
        return total > 480 ? 480 : total;
      }
      return storedPendingMinutes > componentPending
          ? storedPendingMinutes
          : componentPending;
    }

    if (status == AttendanceStatus.absent ||
        policyAction == 'full_day_absent') {
      return _configuredWorkingMinutes;
    }

    var total = latePendingMinutes;
    if (total > 0) return total;

    if (checkInTime != null) {
      final checkInIndian = _toIndianTime(checkInTime!);
      final officeStart =
          _timeOnDate(checkInIndian, officeStartTime ?? '10:00 AM');
      if (checkInIndian.isAfter(officeStart)) {
        total += checkInIndian.difference(officeStart).inMinutes;
      }
    }

    return total < 0 ? 0 : total;
  }

  int get displayPendingMinutes {
    if (_hasCorruptedAttendedAbsentStatus) return 0;
    if (policyAction == 'half_day_leave' || _isApprovedFullDayLeave) return 0;
    if (policyAction == 'no_check_in_absent') return 0;

    if (checkInTime != null && checkOutTime != null) {
      return _dynamicAttendancePendingMinutes;
    }

    final attendancePending =
        latePendingMinutes + _effectiveEarlyCheckoutPendingMinutes;
    if (_checkoutIsInsideConfiguredWindow) return attendancePending;
    if (storedPendingMinutes > 0 || attendancePending > 0) {
      return storedPendingMinutes > attendancePending
          ? storedPendingMinutes
          : attendancePending;
    }

    if (status == AttendanceStatus.absent ||
        policyAction == 'full_day_absent') {
      return _configuredWorkingMinutes;
    }

    var total = latePendingMinutes;
    if (total > 0) return total;

    if (checkInTime != null) {
      final checkInIndian = _toIndianTime(checkInTime!);
      final officeStart =
          _timeOnDate(checkInIndian, officeStartTime ?? '10:00 AM');
      if (checkInIndian.isAfter(officeStart)) {
        total += checkInIndian.difference(officeStart).inMinutes;
      }
    }

    return total < 0 ? 0 : total;
  }

  String get pendingHoursFormatted {
    return _formatHoursMinutes(Duration(minutes: displayPendingMinutes));
  }

  int get permissionMinutes {
    if (permissionPendingMinutes > 0) return permissionPendingMinutes;
    if (!hasPermissionActivity) return 0;
    final start = lastExitTime;
    final end = lastReturnTime ?? permissionApprovedUntil;
    if (start == null || end == null || !end.isAfter(start)) return 0;
    return end.difference(start).inMinutes;
  }

  String get permissionHoursFormatted {
    return _formatHoursMinutes(Duration(minutes: permissionMinutes));
  }

  String get pendingAbsenceLabel {
    if (policyAction == 'half_day_leave') {
      return 'Half Day Leave';
    }
    if (_isApprovedFullDayLeave) {
      return 'Leave';
    }
    if (checkInTime != null) {
      return 'Present';
    }
    return 'Absent';
  }

  String get pendingAbsenceCode {
    if (policyAction == 'half_day_leave' || _isApprovedFullDayLeave) {
      return 'none';
    }
    return _absenceStatusForDisplay;
  }

  String get _absenceStatusForDisplay {
    final cumulativeStatus = cumulativeAbsenceStatus.trim().toLowerCase();
    if (cumulativeStatus == 'full_absent' ||
        cumulativeStatus == 'half_absent') {
      return cumulativeStatus;
    }

    final storedStatus = pendingAbsenceStatus.trim().toLowerCase();
    if (storedStatus == 'full_absent' || storedStatus == 'half_absent') {
      return storedStatus;
    }

    final totalForRule = cumulativePendingMinutes > 0
        ? cumulativePendingMinutes
        : pendingMinutes;
    if (totalForRule >= fullDayAbsentMinutes) return 'full_absent';
    if (totalForRule >= halfDayAbsentMinutes) return 'half_absent';
    return 'none';
  }

  AttendanceModel copyWith({
    String? department,
    AttendanceStatus? status,
    String? policyAction,
    String? policyLabel,
    int? storedPendingMinutes,
    String? pendingAbsenceStatus,
    int? cumulativePendingMinutes,
    String? cumulativeAbsenceStatus,
    String? officeStartTime,
    String? officeCheckOutStartTime,
    String? officeEndTime,
  }) {
    return AttendanceModel(
      id: id,
      employeeId: employeeId,
      employeeName: employeeName,
      department: department ?? this.department,
      status: status ?? this.status,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      latitude: latitude,
      longitude: longitude,
      employeePhotoUrl: employeePhotoUrl,
      employeePhotoBase64: employeePhotoBase64,
      geoTagRequired: geoTagRequired,
      date: date,
      lateMinutes: lateMinutes,
      arrivalBand: arrivalBand,
      policyAction: policyAction ?? this.policyAction,
      policyLabel: policyLabel ?? this.policyLabel,
      storedWorkingMinutes: storedWorkingMinutes,
      storedWorkingHours: storedWorkingHours,
      isEarlyCheckout: isEarlyCheckout,
      earlyCheckoutMinutes: earlyCheckoutMinutes,
      latePendingMinutes: latePendingMinutes,
      earlyCheckoutPendingMinutes: earlyCheckoutPendingMinutes,
      permissionPendingMinutes: permissionPendingMinutes,
      storedPendingMinutes: storedPendingMinutes ?? this.storedPendingMinutes,
      pendingAbsenceStatus: pendingAbsenceStatus ?? this.pendingAbsenceStatus,
      cumulativePendingMinutes:
          cumulativePendingMinutes ?? this.cumulativePendingMinutes,
      cumulativeAbsenceStatus:
          cumulativeAbsenceStatus ?? this.cumulativeAbsenceStatus,
      officeStartTime: officeStartTime ?? this.officeStartTime,
      officeCheckOutStartTime:
          officeCheckOutStartTime ?? this.officeCheckOutStartTime,
      officeEndTime: officeEndTime ?? this.officeEndTime,
      currentState: currentState,
      managerName: managerName,
      permissionId: permissionId,
      permissionApprovedUntil: permissionApprovedUntil,
      lastExitTime: lastExitTime,
      lastReturnTime: lastReturnTime,
      permissionDelayMinutes: permissionDelayMinutes,
      profileRemoved: profileRemoved,
    );
  }

  DateTime _timeOnDate(DateTime baseDate, String value) {
    final time = _parseTimeString(value);
    if (baseDate.isUtc) {
      return DateTime.utc(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        time.$1,
        time.$2,
      );
    }
    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      time.$1,
      time.$2,
    );
  }

  static (int, int) _parseTimeString(String value) {
    try {
      final isPm = value.toUpperCase().contains('PM');
      final clean = value.replaceAll(RegExp(r'[APap][Mm]'), '').trim();
      final parts = clean.split(':');
      if (parts.length == 2) {
        var hour = int.parse(parts[0].trim());
        final minute = int.parse(parts[1].trim());
        if (isPm && hour != 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
        return (hour, minute);
      }
    } catch (_) {}
    return (10, 0);
  }

  /// Converts a stored "HH:MM" string to a human-readable "X hrs Y min" label.
  static String _toHrsBased(String hhMm) {
    final parts = hhMm.split(':');
    if (parts.length != 2) return hhMm;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return _formatHoursMinutes(Duration(hours: h, minutes: m));
  }

  /// Converts a [Duration] to a human-readable "X hrs Y min" label.
  static String _durationToHrsBased(Duration d) {
    final safe = d.isNegative ? Duration.zero : d;
    return _formatHoursMinutes(safe);
  }

  String get dateFormatted {
    final indianDate = _toIndianTime(date);
    final month = indianDate.month.toString().padLeft(2, '0');
    final day = indianDate.day.toString().padLeft(2, '0');
    return '$day/$month/${indianDate.year}';
  }

  static DateTime _toIndianTime(DateTime value) {
    return value.toUtc().add(const Duration(hours: 5, minutes: 30));
  }

  static String _formatIndianTime(DateTime value) {
    final indianTime = _toIndianTime(value);
    final period = indianTime.hour >= 12 ? 'PM' : 'AM';
    final hour12 = indianTime.hour % 12 == 0 ? 12 : indianTime.hour % 12;
    final hour = hour12.toString().padLeft(2, '0');
    final minute = indianTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  static String _formatHoursMinutes(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours == 0 && minutes == 0) return '0 min';
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours hrs';
    return '$hours hrs $minutes min';
  }

  String get geoTagFormatted {
    if (!geoTagRequired) return 'Not required';
    if (latitude == null || longitude == null) return 'N/A';
    return '${latitude!.toStringAsFixed(4)},\n${longitude!.toStringAsFixed(4)}';
  }

  String get statusLabel {
    if (policyAction == 'half_day_leave') {
      return 'Half Day Leave';
    }
    if (_isApprovedFullDayLeave) {
      return 'Leave';
    }
    if ((policyAction == 'full_day_absent' ||
            policyAction == 'no_check_in_absent') &&
        checkInTime == null) {
      return 'Absent';
    }
    if (_hasCorruptedAttendedAbsentStatus) {
      return 'Ontime';
    }
    switch (status) {
      case AttendanceStatus.leave:
        return 'Leave';
      case AttendanceStatus.present:
        return 'Ontime';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.wfh:
        return 'Ontime';
      case AttendanceStatus.absent:
        return 'Absent';
    }
  }

  bool get countsAsAbsent {
    if (policyAction == 'half_day_leave') return false;
    if (_isApprovedFullDayLeave) return false;
    if (status == AttendanceStatus.leave) return false;
    if (policyAction == 'full_day_absent' && checkInTime == null) return true;
    if (_hasCorruptedAttendedAbsentStatus) return false;
    return status == AttendanceStatus.absent;
  }

  bool get countsAsLate => !countsAsAbsent && status == AttendanceStatus.late;

  bool get countsAsPresent =>
      !countsAsAbsent &&
      (status == AttendanceStatus.present ||
          status == AttendanceStatus.wfh ||
          _hasCorruptedAttendedAbsentStatus);

  bool get countsAsAttended =>
      !countsAsAbsent &&
      !_isApprovedFullDayLeave &&
      status != AttendanceStatus.leave;

  bool get _isApprovedFullDayLeave {
    if (status == AttendanceStatus.leave) return true;
    if (policyAction == 'full_day_leave') return true;
    return checkInTime == null &&
        policyAction == 'full_day_absent' &&
        policyLabel.toLowerCase().contains('leave');
  }

  bool get hasPermissionActivity =>
      permissionId != null ||
      currentState == AttendanceState.tempExit ||
      lastExitTime != null ||
      lastReturnTime != null;

  bool get isTemporaryExit => currentState == AttendanceState.tempExit;

  bool get _hasCorruptedAttendedAbsentStatus =>
      checkInTime != null && status == AttendanceStatus.absent;

  bool get isPermissionReEntryDelayed => permissionDelayMinutes > 0;

  bool get isEarlyCheckout {
    return _storedIsEarlyCheckout &&
        earlyCheckoutMinutes > 0 &&
        _checkoutIsBeforeConfiguredStart;
  }

  String get permissionActivityLabel {
    if (!hasPermissionActivity) return 'No permission';
    if (isTemporaryExit) return 'Temporary exit';
    if (isPermissionReEntryDelayed) return 'Delayed re-entry';
    if (lastReturnTime != null) return 'Returned on time';
    return 'Permission approved';
  }

  String get permissionActivityDetail {
    if (!hasPermissionActivity) return '-';
    final parts = <String>[];
    if (lastExitTime != null) {
      parts.add('Exit ${_formatIndianTime(lastExitTime!)}');
    }
    if (permissionApprovedUntil != null) {
      parts.add('Due ${_formatIndianTime(permissionApprovedUntil!)}');
    }
    if (lastReturnTime != null) {
      parts.add('Back ${_formatIndianTime(lastReturnTime!)}');
    }
    if (permissionDelayMinutes > 0) {
      parts.add('$permissionDelayMinutes min delayed');
    }
    return parts.isEmpty ? permissionActivityLabel : parts.join(' | ');
  }

  bool get isPenaltyApplied => policyAction != 'none';

  String get dateKey {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'department': department,
      'status': status.name,
      'checkInTime':
          checkInTime != null ? Timestamp.fromDate(checkInTime!) : null,
      'checkOutTime':
          checkOutTime != null ? Timestamp.fromDate(checkOutTime!) : null,
      'latitude': latitude,
      'longitude': longitude,
      'employeePhotoUrl': employeePhotoUrl,
      'employeePhotoBase64': employeePhotoBase64,
      'geoTagRequired': geoTagRequired,
      'date': Timestamp.fromDate(date),
      'dateKey': dateKey,
      'lateMinutes': lateMinutes,
      'arrivalBand': arrivalBand,
      'policyAction': policyAction,
      'policyLabel': policyLabel,
      'workingMinutes': storedWorkingMinutes,
      'workingHours': storedWorkingHours,
      'isEarlyCheckout': isEarlyCheckout,
      'earlyCheckoutMinutes': earlyCheckoutMinutes,
      'latePendingMinutes': latePendingMinutes,
      'earlyCheckoutPendingMinutes': earlyCheckoutPendingMinutes,
      'pendingMinutes': pendingMinutes,
      'pendingAbsenceStatus': pendingAbsenceCode,
      'officeStartTime': officeStartTime,
      'officeCheckOutStartTime': officeCheckOutStartTime,
      'officeEndTime': officeEndTime,
      'currentState': currentState.firestoreValue,
      'managerName': managerName,
      'permissionId': permissionId,
      'permissionApprovedUntil': permissionApprovedUntil != null
          ? Timestamp.fromDate(permissionApprovedUntil!)
          : null,
      'lastExitTime':
          lastExitTime != null ? Timestamp.fromDate(lastExitTime!) : null,
      'lastReturnTime':
          lastReturnTime != null ? Timestamp.fromDate(lastReturnTime!) : null,
      'permissionDelayMinutes': permissionDelayMinutes,
    };
  }

  bool get _checkoutIsInsideConfiguredWindow {
    if (checkOutTime == null) return false;
    final checkoutIndian = _toIndianTime(checkOutTime!);
    final checkoutStart =
        _timeOnDate(checkoutIndian, officeCheckOutStartTime ?? '05:00 PM');
    final checkoutEnd =
        _timeOnDate(checkoutIndian, officeEndTime ?? '07:30 PM');
    return !checkoutIndian.isBefore(checkoutStart) &&
        !checkoutIndian.isAfter(checkoutEnd);
  }

  int get _effectiveEarlyCheckoutPendingMinutes {
    if (!_checkoutIsBeforeConfiguredStart) return 0;
    return earlyCheckoutPendingMinutes;
  }

  bool get _checkoutIsBeforeConfiguredStart {
    if (checkOutTime == null) return false;
    final checkoutIndian = _toIndianTime(checkOutTime!);
    final checkoutStart =
        _timeOnDate(checkoutIndian, officeCheckOutStartTime ?? '05:00 PM');
    return checkoutIndian.isBefore(checkoutStart);
  }

  int get _configuredWorkingMinutes {
    final base = _toIndianTime(date);
    final start = _timeOnDate(base, officeStartTime ?? '10:30 AM');
    final end = _timeOnDate(base, officeEndTime ?? '07:30 PM');
    final minutes = end.difference(start).inMinutes;
    return minutes > 0 ? minutes : 480;
  }

  Duration? get _storedWorkingDuration {
    if (storedWorkingMinutes == null) return null;
    final safeMinutes = storedWorkingMinutes! < 0
        ? 0
        : storedWorkingMinutes! > 24 * 60
            ? 24 * 60
            : storedWorkingMinutes!;
    return Duration(minutes: safeMinutes);
  }

  int get _dynamicAttendancePendingMinutes {
    if (checkInTime == null || checkOutTime == null) return 0;

    final checkInIndian = _toIndianTime(checkInTime!);
    final checkOutIndian = _toIndianTime(checkOutTime!);
    final officeStart =
        _timeOnDate(checkInIndian, officeStartTime ?? '10:30 AM');
    final checkOutStart =
        _timeOnDate(checkOutIndian, officeCheckOutStartTime ?? '05:00 PM');

    final lateMinutes = checkInIndian.isAfter(officeStart)
        ? checkInIndian.difference(officeStart).inMinutes
        : 0;
    final earlyMinutes = checkOutIndian.isBefore(checkOutStart)
        ? checkOutStart.difference(checkOutIndian).inMinutes
        : 0;
    final total = lateMinutes + earlyMinutes;
    final maxPending = _configuredWorkingMinutes;
    return total > maxPending ? maxPending : total;
  }

  DateTime _laterOf(DateTime first, DateTime second) {
    return first.isAfter(second) ? first : second;
  }

  DateTime _earlierOf(DateTime first, DateTime second) {
    return first.isBefore(second) ? first : second;
  }
}

class WeeklyAttendance {
  final String day;
  final int present, absent, late;
  WeeklyAttendance(
      {required this.day,
      required this.present,
      required this.absent,
      required this.late});
}

class MonthlyAttendance {
  final String label;
  final int present;
  final int late;
  final int absent;

  MonthlyAttendance({
    required this.label,
    required this.present,
    required this.late,
    required this.absent,
  });

  int get total => present + late + absent;
}

class CheckoutRequest {
  final String id;
  final String attendanceId;
  final String employeeId;
  final String employeeName;
  final String department;
  final String email;
  final String phone;
  final String managerName;
  final String dateKey;
  final DateTime? checkInTime;
  final DateTime checkoutDeadline;
  final DateTime? checkoutGraceEndsAt;
  final String status;
  final String queryMessage;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  CheckoutRequest({
    required this.id,
    required this.attendanceId,
    required this.employeeId,
    required this.employeeName,
    required this.department,
    required this.email,
    required this.phone,
    this.managerName = '',
    required this.dateKey,
    this.checkInTime,
    required this.checkoutDeadline,
    this.checkoutGraceEndsAt,
    required this.status,
    required this.queryMessage,
    this.adminNote,
    required this.createdAt,
    this.resolvedAt,
  });

  factory CheckoutRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CheckoutRequest(
      id: doc.id,
      attendanceId: data['attendanceId'] ?? '',
      employeeId: data['employeeId'] ?? '',
      employeeName: data['employeeName'] ?? '',
      department: data['department'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      managerName: data['managerName'] ?? '',
      dateKey: data['dateKey'] ?? '',
      checkInTime: (data['checkInTime'] as Timestamp?)?.toDate(),
      checkoutDeadline:
          (data['checkoutDeadline'] as Timestamp?)?.toDate() ?? DateTime.now(),
      checkoutGraceEndsAt:
          (data['checkoutGraceEndsAt'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'pending',
      queryMessage: data['queryMessage'] ?? '',
      adminNote: data['adminNote'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
}
