import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/attendance_model.dart';
import '../models/staff.dart';
import '../models/attendance_log.dart';
import '../services/attendance_log_service.dart';
import '../services/geo_fence_service.dart';
import '../services/permission_service.dart';
import 'notification_service.dart';

class AttendanceService {
  AttendanceService({FirebaseContext? context}) : _boundContext = context;

  // When no explicit context is supplied, resolve the ACTIVE Firebase context
  // live at call time. This ensures the service follows the Master ↔ tenant
  // swap even if it was constructed earlier (e.g. a dashboard widget built
  // before the tenant project was activated), so writes like `qr_tokens` /
  // `notifications` always hit the signed-in tenant project instead of the
  // Master control-plane (whose rules deny non-superadmin writes).
  final FirebaseContext? _boundContext;

  FirebaseContext get _context =>
      _boundContext ?? FirebaseContextProvider.current;

  AttendanceLogService get _logService =>
      AttendanceLogService(context: _context);

  PermissionService get _permissionService =>
      PermissionService(context: _context);

  FirebaseFirestore get _db => _context.firestore;
  static const Duration _minimumCheckOutDelay = Duration(hours: 4);
  static const Duration _missedCheckoutGracePeriod = Duration(hours: 1);
  static const int _halfDayAbsentMinutes = 180;
  static const int _fullDayAbsentMinutes = 360;
  static DateTime? _lastOverdueAttendanceSync;

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void _addRecordToStats(Map<String, int> stats, AttendanceModel record) {
    if (record.countsAsAbsent) {
      stats['absent'] = (stats['absent'] ?? 0) + 1;
    } else if (record.countsAsLate) {
      stats['late'] = (stats['late'] ?? 0) + 1;
    } else if (record.status == AttendanceStatus.wfh) {
      stats['wfh'] = (stats['wfh'] ?? 0) + 1;
    } else if (record.countsAsPresent || record.countsAsAttended) {
      stats['present'] = (stats['present'] ?? 0) + 1;
    }
  }

  // ─── Today's Stats ────────────────────────────────────────────────────
  Stream<Map<String, int>> getTodayStatsStream() {
    final today = _dateKey(DateTime.now());
    final yesterday =
        _dateKey(DateTime.now().subtract(const Duration(days: 1)));

    return _db
        .collection('attendance')
        .where('dateKey', isEqualTo: today)
        .snapshots()
        .asyncMap((snap) async {
      final todayStats = {'present': 0, 'absent': 0, 'late': 0, 'wfh': 0};
      int earlyCheckouts = 0;
      for (final doc in snap.docs) {
        final record = AttendanceModel.fromFirestore(doc);
        _addRecordToStats(todayStats, record);
        if (record.isEarlyCheckout) {
          earlyCheckouts++;
        }
      }

      // Yesterday stats
      final ySnap = await _db
          .collection('attendance')
          .where('dateKey', isEqualTo: yesterday)
          .get();
      final yesterdayStats = {'present': 0, 'absent': 0, 'late': 0, 'wfh': 0};
      int earlyY = 0;
      for (final doc in ySnap.docs) {
        final record = AttendanceModel.fromFirestore(doc);
        _addRecordToStats(yesterdayStats, record);
        if (record.isEarlyCheckout) {
          earlyY++;
        }
      }

      return {
        'present': todayStats['present']!,
        'absent': todayStats['absent']!,
        'late': todayStats['late']!,
        'wfh': todayStats['wfh']!,
        'earlyCheckouts': earlyCheckouts,
        'presentYesterday': yesterdayStats['present']!,
        'absentYesterday': yesterdayStats['absent']!,
        'lateYesterday': yesterdayStats['late']!,
        'earlyCheckoutsYesterday': earlyY,
      };
    });
  }

  Stream<Map<String, int>> getDirectoryStatsStream() {
    return _db.collection('staff').snapshots().asyncMap((staffSnap) async {
      final managerSnap = await _db.collection('managers').get();
      return {
        'totalStaff': staffSnap.docs.length,
        'totalManagers': managerSnap.docs.length,
      };
    });
  }

  Stream<Map<String, int>> getTodayStatsStreamByManager(String managerName) {
    final today = _dateKey(DateTime.now());
    final yesterday =
        _dateKey(DateTime.now().subtract(const Duration(days: 1)));

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) {
        return Stream.value({
          'present': 0,
          'absent': 0,
          'late': 0,
          'wfh': 0,
          'earlyCheckouts': 0,
          'presentYesterday': 0,
          'absentYesterday': 0,
          'lateYesterday': 0,
        });
      }

      final staffIdSet = staffIds.toSet();
      return _db
          .collection('attendance')
          .where('dateKey', whereIn: [today, yesterday])
          .snapshots()
          .map((snap) {
            final todayStats = {
              'present': 0,
              'absent': 0,
              'late': 0,
              'wfh': 0,
            };
            final yesterdayStats = {
              'present': 0,
              'absent': 0,
              'late': 0,
              'wfh': 0,
            };
            int earlyCheckouts = 0;

            for (final doc in snap.docs) {
              final record = AttendanceModel.fromFirestore(doc);
              if (!staffIdSet.contains(record.employeeId)) continue;

              if (record.dateKey == today) {
                _addRecordToStats(todayStats, record);
                if (record.isEarlyCheckout) {
                  earlyCheckouts++;
                }
              } else if (record.dateKey == yesterday) {
                _addRecordToStats(yesterdayStats, record);
              }
            }

            return {
              'present': todayStats['present']!,
              'absent': todayStats['absent']!,
              'late': todayStats['late']!,
              'wfh': todayStats['wfh']!,
              'earlyCheckouts': earlyCheckouts,
              'presentYesterday': yesterdayStats['present']!,
              'absentYesterday': yesterdayStats['absent']!,
              'lateYesterday': yesterdayStats['late']!,
            };
          });
    }).asBroadcastStream();
  }

  Stream<Map<String, int>> getMonthlyStatsStreamByManager(String managerName) {
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) {
        return Stream.value({
          'present': 0,
          'absent': 0,
          'late': 0,
          'wfh': 0,
          'totalRecords': 0,
        });
      }

      final staffIdSet = staffIds.toSet();
      return _db
          .collection('attendance')
          .where('dateKey', isGreaterThanOrEqualTo: '$monthPrefix-01')
          .where('dateKey', isLessThanOrEqualTo: '$monthPrefix-31')
          .snapshots()
          .map((snap) {
        final stats = {'present': 0, 'absent': 0, 'late': 0, 'wfh': 0};

        for (final doc in snap.docs) {
          final record = AttendanceModel.fromFirestore(doc);
          if (!staffIdSet.contains(record.employeeId)) continue;
          _addRecordToStats(stats, record);
        }

        return {
          'present': stats['present']!,
          'absent': stats['absent']!,
          'late': stats['late']!,
          'wfh': stats['wfh']!,
          'totalRecords': stats.values.reduce((a, b) => a + b),
        };
      });
    }).asBroadcastStream();
  }

  // ─── Today's Attendance Log ───────────────────────────────────────────
  Stream<List<AttendanceModel>> getTodayAttendanceStream() {
    final today = _dateKey(DateTime.now());
    final query =
        _db.collection('attendance').orderBy('date', descending: true);

    return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
      final records = _withCumulativeAbsence(
        snap.docs.map(fromDoc).toList(),
      ).where((record) => record.dateKey == today).toList();
      records.sort((a, b) {
        final aTime = a.checkInTime ?? a.date;
        final bTime = b.checkInTime ?? b.date;
        return aTime.compareTo(bTime);
      });
      return records;
    });
  }

  Stream<List<AttendanceModel>> getTodayAttendanceStreamForEmployee(
    String employeeId,
  ) {
    final today = _dateKey(DateTime.now());
    final query =
        _db.collection('attendance').where('employeeId', isEqualTo: employeeId);

    return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
      final records = _withCumulativeAbsence(
        snap.docs.map(fromDoc).toList(),
      ).where((record) => record.dateKey == today).toList();
      records.sort((a, b) {
        final aTime = a.checkInTime ?? a.date;
        final bTime = b.checkInTime ?? b.date;
        return aTime.compareTo(bTime);
      });
      return records;
    });
  }

  Stream<Map<String, int>> getTodayStatsStreamForEmployee(
    String employeeId,
  ) {
    final today = _dateKey(DateTime.now());
    return _db
        .collection('attendance')
        .where('dateKey', isEqualTo: today)
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map((snap) {
      final stats = {'present': 0, 'absent': 0, 'late': 0, 'wfh': 0};
      for (final doc in snap.docs) {
        _addRecordToStats(stats, AttendanceModel.fromFirestore(doc));
      }
      return {
        'present': stats['present']!,
        'absent': stats['absent']!,
        'late': stats['late']!,
        'wfh': stats['wfh']!,
      };
    });
  }

  // ─── Manager's Team Attendance ────────────────────────────────────────
  Stream<List<AttendanceModel>> getTodayAttendanceStreamByManager(
    String managerName,
  ) {
    final today = _dateKey(DateTime.now());

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) {
        return Stream.value(<AttendanceModel>[]);
      }

      final staffIdSet = staffIds.toSet();
      final query =
          _db.collection('attendance').orderBy('date', descending: true);

      return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
        final records = _withCumulativeAbsence(
          snap.docs.map(fromDoc).toList(),
        )
            .where((record) =>
                staffIdSet.contains(record.employeeId) &&
                record.dateKey == today)
            .toList();
        records.sort((a, b) {
          final aTime = a.checkInTime ?? a.date;
          final bTime = b.checkInTime ?? b.date;
          return aTime.compareTo(bTime);
        });
        return records;
      });
    }).asBroadcastStream();
  }

  Stream<List<AttendanceModel>> getAttendanceHistoryStream(
    String employeeId, {
    int? limit = 30,
  }) {
    if (employeeId.isEmpty) {
      return Stream.value(<AttendanceModel>[]);
    }

    // Keep this query staff-scoped but avoid requiring a composite Firestore
    // index for employeeId + date. The small staff result set is sorted locally.
    final query =
        _db.collection('attendance').where('employeeId', isEqualTo: employeeId);

    return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
      final Map<String, AttendanceModel> seen = {};
      for (final doc in snap.docs) {
        final record = fromDoc(doc);
        final key = '${record.employeeId}_${record.dateKey}';
        if (!seen.containsKey(key)) {
          seen[key] = record;
        }
      }

      final records = seen.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final enriched = _withCumulativeAbsence(records);
      return limit == null || limit <= 0
          ? enriched
          : enriched.take(limit).toList();
    });
  }

  Stream<List<AttendanceModel>> getAttendanceHistoryStreamByManager(
    String managerName, {
    int? limit,
  }) {
    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) {
        return Stream.value(<AttendanceModel>[]);
      }

      final staffIdSet = staffIds.toSet();
      Query<Map<String, dynamic>> query =
          _db.collection('attendance').orderBy('date', descending: true);

      return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
        final records = snap.docs
            .map(fromDoc)
            .where((record) => staffIdSet.contains(record.employeeId))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final enriched = _withCumulativeAbsence(records);
        return limit == null ? enriched : enriched.take(limit).toList();
      });
    }).asBroadcastStream();
  }

  Stream<List<AttendanceModel>> getAttendanceHistoryStreamAll({
    int? limit,
  }) {
    Query<Map<String, dynamic>> query =
        _db.collection('attendance').orderBy('date', descending: true);

    return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
      final records = snap.docs.map(fromDoc).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final enriched = _withCumulativeAbsence(records);
      return limit == null || limit <= 0
          ? enriched
          : enriched.take(limit).toList();
    });
  }

  Future<void> clearProfileIdentityFromLogs({
    required String employeeId,
    String? employeeName,
  }) async {
    final identifiers = <String>{
      employeeId.trim(),
    }..removeWhere((value) => value.isEmpty);
    final normalizedName = employeeName?.trim();

    await _clearCollectionProfileFields(
      collection: 'attendance',
      identifiers: identifiers,
      employeeName: normalizedName,
      fields: {
        'employeeName': '',
        'department': '',
        'employeePhotoUrl': FieldValue.delete(),
        'employeePhotoBase64': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoBase64': FieldValue.delete(),
        'profileRemoved': true,
      },
    );

    await _clearCollectionProfileFields(
      collection: 'checkout_requests',
      identifiers: identifiers,
      employeeName: normalizedName,
      fields: {
        'employeeName': '',
        'department': '',
        'profileRemoved': true,
      },
    );

    await _clearCollectionProfileFields(
      collection: 'attendance_logs',
      identifiers: identifiers,
      employeeName: normalizedName,
      idField: 'staffId',
      nameField: 'staffName',
      fields: {
        'staffName': '',
        'profileRemoved': true,
      },
    );
  }

  Future<void> removeProfilePhotoFromLogs({
    required String employeeId,
  }) async {
    final identifiers = <String>{employeeId.trim()}
      ..removeWhere((value) => value.isEmpty);
    if (identifiers.isEmpty) return;

    await _clearCollectionProfileFields(
      collection: 'attendance',
      identifiers: identifiers,
      fields: {
        'employeePhotoUrl': FieldValue.delete(),
        'employeePhotoBase64': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoBase64': FieldValue.delete(),
      },
    );
  }

  Future<void> _clearCollectionProfileFields({
    required String collection,
    required Set<String> identifiers,
    String? employeeName,
    String idField = 'employeeId',
    String nameField = 'employeeName',
    required Map<String, Object?> fields,
  }) async {
    final refs = <DocumentReference<Map<String, dynamic>>>{};
    for (final identifier in identifiers) {
      final snap = await _db
          .collection(collection)
          .where(idField, isEqualTo: identifier)
          .get();
      refs.addAll(snap.docs.map((doc) => doc.reference));
    }

    if (employeeName != null && employeeName.isNotEmpty) {
      final snap = await _db
          .collection(collection)
          .where(nameField, isEqualTo: employeeName)
          .get();
      refs.addAll(snap.docs.map((doc) => doc.reference));
    }

    var batch = _db.batch();
    var count = 0;
    for (final ref in refs) {
      batch.update(ref, fields);
      count++;
      if (count == 450) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }

  Stream<List<AttendanceModel>> getManagersAttendanceHistoryStreamAll({
    DateTime? date,
    int? limit,
  }) {
    return _db.collection('managers').snapshots().asyncExpand((managerSnap) {
      final managerIds = <String>{};
      final managerNames = <String>{};

      for (final doc in managerSnap.docs) {
        final data = doc.data();
        final employeeId = (data['employeeId'] as String? ?? '').trim();
        final name = (data['name'] as String? ?? '').trim().toLowerCase();
        if (employeeId.isNotEmpty) managerIds.add(employeeId);
        if (name.isNotEmpty) managerNames.add(name);
      }

      if (managerIds.isEmpty && managerNames.isEmpty) {
        return Stream.value(<AttendanceModel>[]);
      }

      Query<Map<String, dynamic>> query = _db.collection('attendance');
      if (date != null) {
        query = query.where('dateKey', isEqualTo: _dateKey(date));
      } else {
        query = query.orderBy('date', descending: true);
      }

      return _attendanceRecordsWithLiveOfficeTimes(query, (snap, fromDoc) {
        final records = snap.docs.map(fromDoc).where((record) {
          final employeeId = record.employeeId.trim();
          final name = record.employeeName.trim().toLowerCase();
          return managerIds.contains(employeeId) || managerNames.contains(name);
        }).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final enriched = _withCumulativeAbsence(records);
        return limit == null || limit <= 0
            ? enriched
            : enriched.take(limit).toList();
      });
    }).asBroadcastStream();
  }

  Stream<List<AttendanceModel>> _attendanceRecordsWithLiveOfficeTimes(
    Query<Map<String, dynamic>> query,
    List<AttendanceModel> Function(
      QuerySnapshot<Map<String, dynamic>> snap,
      AttendanceModel Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
          fromDoc,
    ) buildRecords,
  ) {
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? configSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? leaveSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? staffSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? managerSub;
    QuerySnapshot<Map<String, dynamic>>? latestSnap;
    QuerySnapshot<Map<String, dynamic>>? latestLeaveSnap;
    QuerySnapshot<Map<String, dynamic>>? latestStaffSnap;
    QuerySnapshot<Map<String, dynamic>>? latestManagerSnap;
    var officeTimes = _liveOfficeTimesFromGeoConfig(null);

    late final StreamController<List<AttendanceModel>> controller;
    controller = StreamController<List<AttendanceModel>>.broadcast(
      onListen: () {
        void emit() {
          final snap = latestSnap;
          if (snap == null || controller.isClosed) return;
          final leaveWindows = _approvedLeaveWindows(latestLeaveSnap);
          final directoryProfiles = _directoryProfiles(
            staffSnapshot: latestStaffSnap,
            managerSnapshot: latestManagerSnap,
          );

          AttendanceModel fromDoc(
            QueryDocumentSnapshot<Map<String, dynamic>> doc,
          ) {
            final recordWithTimes = _applyLiveOfficeTimes(
              AttendanceModel.fromFirestore(doc),
              officeTimes,
            );
            final recordWithDirectory = _applyDirectoryOverlay(
              recordWithTimes,
              directoryProfiles,
            );
            return _applyLeaveOverlay(recordWithDirectory, leaveWindows);
          }

          controller.add(buildRecords(snap, fromDoc));
        }

        configSub = _db
            .collection('geo_config')
            .doc('default')
            .snapshots()
            .listen((configSnap) {
          officeTimes = _liveOfficeTimesFromGeoConfig(configSnap.data());
          emit();
        }, onError: controller.addError);

        querySub = query.snapshots().listen((snap) {
          latestSnap = snap;
          emit();
        }, onError: controller.addError);

        leaveSub = _db.collection('leave_requests').snapshots().listen((snap) {
          latestLeaveSnap = snap;
          emit();
        }, onError: (_) {
          latestLeaveSnap = null;
          emit();
        });

        staffSub = _db.collection('staff').snapshots().listen((snap) {
          latestStaffSnap = snap;
          emit();
        }, onError: (_) {
          latestStaffSnap = null;
          emit();
        });

        managerSub = _db.collection('managers').snapshots().listen((snap) {
          latestManagerSnap = snap;
          emit();
        }, onError: (_) {
          latestManagerSnap = null;
          emit();
        });
      },
      onCancel: () async {
        await configSub?.cancel();
        await querySub?.cancel();
        await leaveSub?.cancel();
        await staffSub?.cancel();
        await managerSub?.cancel();
        configSub = null;
        querySub = null;
        leaveSub = null;
        staffSub = null;
        managerSub = null;
        latestSnap = null;
        latestLeaveSnap = null;
        latestStaffSnap = null;
        latestManagerSnap = null;
      },
    );

    return controller.stream;
  }

  _LiveOfficeTimes _liveOfficeTimesFromGeoConfig(Map<String, dynamic>? data) {
    return _LiveOfficeTimes(
      officeStartTime: data?['checkInEnd'] as String? ?? '10:30 AM',
      officeCheckOutStartTime: data?['checkOutStart'] as String? ?? '05:00 PM',
      officeEndTime: data?['checkOutEnd'] as String? ?? '07:30 PM',
    );
  }

  AttendanceModel _applyLiveOfficeTimes(
    AttendanceModel record,
    _LiveOfficeTimes officeTimes,
  ) {
    return record.copyWith(
      officeStartTime: officeTimes.officeStartTime,
      officeCheckOutStartTime: officeTimes.officeCheckOutStartTime,
      officeEndTime: officeTimes.officeEndTime,
    );
  }

  List<_DirectoryProfile> _directoryProfiles({
    QuerySnapshot<Map<String, dynamic>>? staffSnapshot,
    QuerySnapshot<Map<String, dynamic>>? managerSnapshot,
  }) {
    final profiles = <String, _DirectoryProfile>{};

    void addProfile(Map<String, dynamic> data, String docId) {
      final employeeId = data['employeeId']?.toString().trim() ?? '';
      final name = data['name']?.toString().trim() ?? '';
      final department = data['department']?.toString().trim() ?? '';
      final position = data['position']?.toString().trim() ?? '';
      final designation = department.isNotEmpty ? department : position;
      if (designation.isEmpty) return;

      final profile = _DirectoryProfile(
        identifiers: {
          employeeId,
          docId.trim(),
        }..removeWhere((value) => value.isEmpty),
        names: {
          name.toLowerCase(),
        }..removeWhere((value) => value.isEmpty),
        designation: designation,
      );

      void put(String key) {
        if (key.isEmpty) return;
        final existing = profiles[key];
        if (existing == null ||
            _isGenericDesignation(existing.designation) &&
                !_isGenericDesignation(profile.designation)) {
          profiles[key] = profile;
        }
      }

      for (final id in profile.identifiers) {
        put('id:${id.toLowerCase()}');
      }
      for (final profileName in profile.names) {
        put('name:$profileName');
      }
    }

    for (final doc in staffSnapshot?.docs ?? const []) {
      addProfile(doc.data(), doc.id);
    }
    for (final doc in managerSnapshot?.docs ?? const []) {
      addProfile(doc.data(), doc.id);
    }

    return profiles.values.toSet().toList();
  }

  bool _isGenericDesignation(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'management' ||
        normalized == 'manager' ||
        normalized == 'staff';
  }

  AttendanceModel _applyDirectoryOverlay(
    AttendanceModel record,
    List<_DirectoryProfile> profiles,
  ) {
    if (profiles.isEmpty) return record;

    final employeeId = record.employeeId.trim().toLowerCase();
    final employeeName = record.employeeName.trim().toLowerCase();
    for (final profile in profiles) {
      final matchesId = employeeId.isNotEmpty &&
          profile.identifiers.any((id) => id.toLowerCase() == employeeId);
      final matchesName =
          employeeName.isNotEmpty && profile.names.contains(employeeName);
      if (!matchesId && !matchesName) continue;

      final current = record.department.trim();
      if (current == profile.designation ||
          (current.isNotEmpty &&
              !_isGenericDesignation(current) &&
              _isGenericDesignation(profile.designation))) {
        return record;
      }

      return record.copyWith(department: profile.designation);
    }

    return record;
  }

  List<_ApprovedLeaveWindow> _approvedLeaveWindows(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    if (snapshot == null) return const <_ApprovedLeaveWindow>[];

    final windows = <_ApprovedLeaveWindow>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status']?.toString().trim().toLowerCase() ?? '';
      if (status == 'rejected' || status == 'cancelled') continue;
      final start = (data['startDate'] as Timestamp?)?.toDate();
      final end = (data['endDate'] as Timestamp?)?.toDate() ?? start;
      if (start == null || end == null) continue;

      final identifiers = <String>{};
      final names = <String>{};

      void addIdentifier(Object? value) {
        final text = value?.toString().trim();
        if (text == null || text.isEmpty) return;
        identifiers.add(text);
      }

      void addName(Object? value) {
        final text = value?.toString().trim().toLowerCase();
        if (text == null || text.isEmpty) return;
        names.add(text);
      }

      addIdentifier(data['employeeId']);
      addIdentifier(data['userId']);
      addName(data['userName']);
      addName(data['employeeName']);
      addName(data['name']);

      if (identifiers.isEmpty && names.isEmpty) continue;

      final type = data['type']?.toString() ?? 'Leave';
      final isHalfDay = type.toLowerCase().contains('half');
      final paidDays = (data['paidDayCount'] as num?)?.toDouble() ?? 0;
      final unpaidDays = (data['unpaidDayCount'] as num?)?.toDouble() ?? 0;
      final isPaid = data['isPaid'] == true;
      final leaveKind = paidDays > 0 && unpaidDays > 0
          ? 'Mixed Leave'
          : isPaid
              ? 'Paid Leave'
              : 'Unpaid Leave';

      windows.add(
        _ApprovedLeaveWindow(
          identifiers: identifiers,
          names: names,
          startKey: _dateKey(start),
          endKey: _dateKey(end),
          isHalfDay: isHalfDay,
          label: '${isHalfDay ? 'Half Day ' : ''}$leaveKind',
        ),
      );
    }

    return windows;
  }

  AttendanceModel _applyLeaveOverlay(
    AttendanceModel record,
    List<_ApprovedLeaveWindow> leaveWindows,
  ) {
    if (leaveWindows.isEmpty) return record;
    if (record.checkInTime != null || record.checkOutTime != null) {
      return record;
    }

    final employeeId = record.employeeId.trim();
    final employeeName = record.employeeName.trim().toLowerCase();
    final recordDateKey = record.dateKey;

    for (final leave in leaveWindows) {
      final matchesEmployee = employeeId.isNotEmpty &&
          leave.identifiers.any((id) => id.trim() == employeeId);
      final matchesName =
          employeeName.isNotEmpty && leave.names.contains(employeeName);
      if (!matchesEmployee && !matchesName) continue;
      if (recordDateKey.compareTo(leave.startKey) < 0 ||
          recordDateKey.compareTo(leave.endKey) > 0) {
        continue;
      }

      return record.copyWith(
        policyAction: leave.isHalfDay ? 'half_day_leave' : 'full_day_leave',
        policyLabel: leave.label,
        storedPendingMinutes: 0,
        pendingAbsenceStatus: 'none',
      );
    }

    return record;
  }

  List<AttendanceModel> _withCumulativeAbsence(
    List<AttendanceModel> records,
  ) {
    // ── Step 1: Deduplicate ──
    // If a user has both a present/late record AND an absent record for the
    // same day, keep only the present/late one. This handles both existing
    // duplicates in the DB and any edge-case race conditions.
    final deduped = _deduplicateRecords(records);

    // ── Step 2: Enrich with cumulative absence ──
    final grouped = <String, List<AttendanceModel>>{};
    for (final record in deduped) {
      final key = record.employeeId.trim().isNotEmpty
          ? record.employeeId.trim()
          : record.employeeName.trim().toLowerCase();
      grouped.putIfAbsent(key, () => <AttendanceModel>[]).add(record);
    }

    final enrichedById = <String, AttendanceModel>{};
    for (final employeeRecords in grouped.values) {
      employeeRecords.sort((a, b) => a.date.compareTo(b.date));
      var cumulativePending = 0;

      for (final record in employeeRecords) {
        cumulativePending += record.pendingMinutes;
        if (cumulativePending > 480) cumulativePending = 480;

        enrichedById[record.id] = record.copyWith(
          cumulativePendingMinutes: cumulativePending,
          cumulativeAbsenceStatus: _pendingAbsenceStatus(cumulativePending),
        );
      }
    }

    return deduped.map((record) => enrichedById[record.id] ?? record).toList();
  }

  /// Removes duplicate absent records when a present/late record exists for
  /// the same employee on the same date.
  List<AttendanceModel> _deduplicateRecords(List<AttendanceModel> records) {
    // Build a set of (employeeId, dateKey) pairs that have a real check-in
    final checkedInKeys = <String>{};
    for (final record in records) {
      if (record.status != AttendanceStatus.absent) {
        final empKey = record.employeeId.trim().toLowerCase();
        final dateKey = _dateKey(record.date);
        checkedInKeys.add('${empKey}_$dateKey');
      }
    }

    // Filter out absent records whose employee already has a check-in that day
    return records.where((record) {
      if (record.status != AttendanceStatus.absent) return true;
      final empKey = record.employeeId.trim().toLowerCase();
      final dateKey = _dateKey(record.date);
      return !checkedInKeys.contains('${empKey}_$dateKey');
    }).toList();
  }

  Stream<List<AttendanceModel>> getTodayAttendanceStreamAll() {
    final today = _dateKey(DateTime.now());
    final query =
        _db.collection('attendance').orderBy('date', descending: true);

    return _attendanceRecordsWithLiveOfficeTimes(
      query,
      (snap, fromDoc) => _withCumulativeAbsence(
        snap.docs.map(fromDoc).toList(),
      ).where((record) => record.dateKey == today).toList(),
    );
  }

  Stream<List<AttendanceModel>> getWeeklyAttendanceStreamAll() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final query =
        _db.collection('attendance').orderBy('date', descending: true);

    return _attendanceRecordsWithLiveOfficeTimes(
      query,
      (snap, fromDoc) => _withCumulativeAbsence(
        snap.docs.map(fromDoc).toList(),
      ).where((record) => !record.date.isBefore(startOfDate)).toList(),
    );
  }

  Stream<List<AttendanceModel>> getMonthlyAttendanceStreamAll({
    DateTime? forMonth,
  }) {
    final target = forMonth ?? DateTime.now();
    final startOfMonth = DateTime(target.year, target.month, 1);
    final endOfMonth = DateTime(target.year, target.month + 1, 0, 23, 59, 59);

    final query =
        _db.collection('attendance').orderBy('date', descending: true);

    return _attendanceRecordsWithLiveOfficeTimes(
      query,
      (snap, fromDoc) => _withCumulativeAbsence(
        snap.docs.map(fromDoc).toList(),
      )
          .where((record) =>
              !record.date.isBefore(startOfMonth) &&
              !record.date.isAfter(endOfMonth))
          .toList(),
    );
  }

  Future<List<AttendanceModel>> getAttendanceHistoryByManager(
    String managerName, {
    DateTime? date,
  }) async {
    final staffIds = await _teamEmployeeIdsStream(managerName).first;
    if (staffIds.isEmpty) {
      return <AttendanceModel>[];
    }

    final staffIdSet = staffIds.toSet();
    Query<Map<String, dynamic>> query = _db.collection('attendance');

    if (date != null) {
      query = query.where('dateKey', isEqualTo: _dateKey(date));
    } else {
      query = query.orderBy('date', descending: true);
    }

    final snapshot = await query.get();
    final records = snapshot.docs
        .map((d) => AttendanceModel.fromFirestore(d))
        .where((record) => staffIdSet.contains(record.employeeId))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return records;
  }

  Stream<List<AttendanceModel>> getWeeklyAttendanceStreamByManager(
      String managerName) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) return Stream.value(<AttendanceModel>[]);
      final staffIdSet = staffIds.toSet();

      final query = _db
          .collection('attendance')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDate))
          .orderBy('date', descending: true);

      return _attendanceRecordsWithLiveOfficeTimes(
        query,
        (snap, fromDoc) => snap.docs
            .map(fromDoc)
            .where((record) => staffIdSet.contains(record.employeeId))
            .toList(),
      );
    }).asBroadcastStream();
  }

  Stream<List<AttendanceModel>> getMonthlyAttendanceStreamByManager(
      String managerName) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) return Stream.value(<AttendanceModel>[]);
      final staffIdSet = staffIds.toSet();

      final query = _db
          .collection('attendance')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .orderBy('date', descending: true);

      return _attendanceRecordsWithLiveOfficeTimes(
        query,
        (snap, fromDoc) => snap.docs
            .map(fromDoc)
            .where((record) => staffIdSet.contains(record.employeeId))
            .toList(),
      );
    }).asBroadcastStream();
  }

  /// Parametrized variant of [getMonthlyAttendanceStreamByManager] that streams
  /// the given manager's team attendance for a specific calendar month.
  ///
  /// Reads the same `attendance` collection and applies the same manager-team
  /// scoping as every other manager data source, so no additional Firestore
  /// security rule or index is required. Backs the Manager "Monthly Analysis"
  /// view's month selector.
  Stream<List<AttendanceModel>> getMonthlyAttendanceStreamByManagerForMonth(
    String managerName,
    DateTime forMonth,
  ) {
    final startOfMonth = DateTime(forMonth.year, forMonth.month, 1);
    final endOfMonth = DateTime(forMonth.year, forMonth.month + 1, 1);

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) return Stream.value(<AttendanceModel>[]);
      final staffIdSet = staffIds.toSet();

      final query = _db
          .collection('attendance')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .where('date', isLessThan: Timestamp.fromDate(endOfMonth))
          .orderBy('date', descending: true);

      return _attendanceRecordsWithLiveOfficeTimes(
        query,
        (snap, fromDoc) => snap.docs
            .map(fromDoc)
            .where((record) => staffIdSet.contains(record.employeeId))
            .toList(),
      );
    }).asBroadcastStream();
  }

  // ─── Weekly Trend ─────────────────────────────────────────────────────
  Stream<List<WeeklyAttendance>> getWeeklyTrendStream() {
    final now = DateTime.now();
    // Start from Monday of this week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final keys = List.generate(5, (i) {
      final d = monday.add(Duration(days: i));
      return _dateKey(d);
    });

    return _db
        .collection('attendance')
        .where('dateKey', whereIn: keys)
        .snapshots()
        .map((snapshot) {
      final Map<String, Map<String, int>> dayMap = {};
      for (final k in keys) {
        dayMap[k] = {'present': 0, 'absent': 0, 'late': 0};
      }
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final key = d['dateKey'] as String? ?? '';
        final status = d['status'] as String? ?? '';
        if (dayMap.containsKey(key)) {
          dayMap[key]![status] = (dayMap[key]![status] ?? 0) + 1;
        }
      }
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
      return List.generate(5, (i) {
        final data = dayMap[keys[i]]!;
        return WeeklyAttendance(
          day: days[i],
          present: data['present']!,
          absent: data['absent']!,
          late: data['late']!,
        );
      });
    });
  }

  Stream<List<MonthlyAttendance>> getYearlyMonthlyTrendStream() {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final nextYearStart = DateTime(now.year + 1, 1, 1);
    const monthLabels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return _db
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(yearStart))
        .where('date', isLessThan: Timestamp.fromDate(nextYearStart))
        .snapshots()
        .map((snap) {
      final months = List.generate(
        12,
        (_) => {'present': 0, 'late': 0, 'absent': 0},
      );

      for (final doc in snap.docs) {
        final record = AttendanceModel.fromFirestore(doc);
        final date = record.date;
        if (date.month < 1 || date.month > 12) continue;

        final index = date.month - 1;
        if (record.countsAsAbsent) {
          months[index]['absent'] = months[index]['absent']! + 1;
        } else if (record.countsAsLate) {
          months[index]['late'] = months[index]['late']! + 1;
        } else if (record.countsAsPresent || record.countsAsAttended) {
          months[index]['present'] = months[index]['present']! + 1;
        }
      }

      return List.generate(12, (index) {
        return MonthlyAttendance(
          label: monthLabels[index],
          present: months[index]['present']!,
          late: months[index]['late']!,
          absent: months[index]['absent']!,
        );
      });
    });
  }

  Stream<List<MonthlyAttendance>> getMonthlyAnalysisStream() {
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    const int weekCount = 5;

    return _db
        .collection('attendance')
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(currentMonthStart))
        .where('date', isLessThan: Timestamp.fromDate(nextMonthStart))
        .snapshots()
        .map((snapshot) {
      final weeks = List.generate(
          weekCount, (_) => {'present': 0, 'late': 0, 'absent': 0});
      for (final doc in snapshot.docs) {
        final record = AttendanceModel.fromFirestore(doc);
        final date = record.date;
        final weekIndex = ((date.day - 1) ~/ 7).clamp(0, weekCount - 1);

        if (record.countsAsAbsent) {
          weeks[weekIndex]['absent'] = weeks[weekIndex]['absent']! + 1;
        } else if (record.countsAsLate) {
          weeks[weekIndex]['late'] = weeks[weekIndex]['late']! + 1;
        } else if (record.countsAsPresent || record.countsAsAttended) {
          weeks[weekIndex]['present'] = weeks[weekIndex]['present']! + 1;
        }
      }

      return List.generate(weekCount, (index) {
        return MonthlyAttendance(
          label: 'Wk ${index + 1}',
          present: weeks[index]['present']!,
          late: weeks[index]['late']!,
          absent: weeks[index]['absent']!,
        );
      });
    });
  }

  Stream<List<MonthlyAttendance>> getMonthlyAnalysisStreamByManager(
    String managerName,
  ) {
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    const int weekCount = 5;

    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) {
        return Stream.value(List.generate(
          weekCount,
          (index) => MonthlyAttendance(
            label: 'Wk ${index + 1}',
            present: 0,
            late: 0,
            absent: 0,
          ),
        ));
      }

      final employeeIds = staffIds.toSet();
      return _db
          .collection('attendance')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(currentMonthStart),
          )
          .where('date', isLessThan: Timestamp.fromDate(nextMonthStart))
          .snapshots()
          .map((snapshot) {
        final weeks = List.generate(
          weekCount,
          (_) => {'present': 0, 'late': 0, 'absent': 0},
        );

        for (final doc in snapshot.docs) {
          final record = AttendanceModel.fromFirestore(doc);
          if (!employeeIds.contains(record.employeeId)) continue;

          final date = record.date;
          final weekIndex = ((date.day - 1) ~/ 7).clamp(0, weekCount - 1);

          if (record.countsAsAbsent) {
            weeks[weekIndex]['absent'] = weeks[weekIndex]['absent']! + 1;
          } else if (record.countsAsLate) {
            weeks[weekIndex]['late'] = weeks[weekIndex]['late']! + 1;
          } else if (record.countsAsPresent || record.countsAsAttended) {
            weeks[weekIndex]['present'] = weeks[weekIndex]['present']! + 1;
          }
        }

        return List.generate(weekCount, (index) {
          return MonthlyAttendance(
            label: 'Wk ${index + 1}',
            present: weeks[index]['present']!,
            late: weeks[index]['late']!,
            absent: weeks[index]['absent']!,
          );
        });
      });
    }).asBroadcastStream();
  }

  Future<Staff?> getStaffByEmployeeId(String employeeId) async {
    final trimmedEmployeeId = employeeId.trim();
    if (trimmedEmployeeId.isEmpty) return null;

    final query = await _db
        .collection('staff')
        .where('employeeId', isEqualTo: trimmedEmployeeId)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      return Staff.fromFirestore(query.docs.first);
    }

    final doc = await _db.collection('staff').doc(trimmedEmployeeId).get();
    if (doc.exists) {
      return Staff.fromFirestore(doc);
    }

    final managerByEmployeeId = await _db
        .collection('managers')
        .where('employeeId', isEqualTo: trimmedEmployeeId)
        .limit(1)
        .get();
    if (managerByEmployeeId.docs.isNotEmpty) {
      return _managerDocAsStaff(managerByEmployeeId.docs.first);
    }

    final managerDoc =
        await _db.collection('managers').doc(trimmedEmployeeId).get();
    if (managerDoc.exists) {
      return _managerDocAsStaff(managerDoc);
    }

    final managerByEmail = await _db
        .collection('managers')
        .where('email', isEqualTo: trimmedEmployeeId)
        .limit(1)
        .get();
    if (managerByEmail.docs.isNotEmpty) {
      return _managerDocAsStaff(managerByEmail.docs.first);
    }

    return null;
  }

  Future<Staff?> getStaffByUserIdentity({
    required String uid,
    String? email,
  }) async {
    // Try all three queries in parallel for faster lookup
    final results = await Future.wait([
      _db.collection('staff').doc(uid).get(),
      getStaffByEmployeeId(uid),
      getStaffByEmail(email),
    ], eagerError: false);

    final byUid = results[0] as DocumentSnapshot;
    final byEmployeeId = results[1] as Staff?;
    final byEmail = results[2] as Staff?;

    if (byUid.exists) {
      return Staff.fromFirestore(byUid);
    }
    if (byEmployeeId != null) {
      return byEmployeeId;
    }
    if (byEmail != null) {
      return byEmail;
    }

    return getManagerAsStaffByUserIdentity(uid: uid, email: email);
  }

  Future<Staff?> getStaffByEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return null;

    final query = await _db
        .collection('staff')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return Staff.fromFirestore(query.docs.first);
    }

    final managerQuery = await _db
        .collection('managers')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    if (managerQuery.docs.isNotEmpty) {
      return _managerDocAsStaff(managerQuery.docs.first);
    }

    return null;
  }

  Future<Staff?> getManagerAsStaffByUserIdentity({
    required String uid,
    String? email,
  }) async {
    final byUid = await _db.collection('managers').doc(uid).get();
    if (byUid.exists) {
      return _managerDocAsStaff(byUid);
    }

    final byEmployeeId = await _db
        .collection('managers')
        .where('employeeId', isEqualTo: uid)
        .limit(1)
        .get();
    if (byEmployeeId.docs.isNotEmpty) {
      return _managerDocAsStaff(byEmployeeId.docs.first);
    }

    final trimmedEmail = email?.trim() ?? '';
    if (trimmedEmail.isNotEmpty) {
      final byEmail = await _db
          .collection('managers')
          .where('email', isEqualTo: trimmedEmail)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        return _managerDocAsStaff(byEmail.docs.first);
      }
    }

    return null;
  }

  Staff _managerDocAsStaff(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final joinDate = (data['joinDate'] as Timestamp?)?.toDate();
    final employeeId = (data['employeeId'] as String? ?? '').trim();
    final email = (data['email'] as String? ?? '').trim();

    return Staff(
      id: doc.id,
      name: (data['name'] as String? ?? '').trim(),
      email: email,
      phone: (data['phone'] as String? ?? '').trim(),
      department: (data['department'] as String? ?? '').trim(),
      position: (data['position'] as String? ?? 'Manager').trim(),
      employeeId: employeeId.isNotEmpty
          ? employeeId
          : (email.isNotEmpty ? email : doc.id),
      joinDate: joinDate ?? DateTime.now(),
      photoUrl: data['photoUrl'] as String?,
      photoBase64: data['photoBase64'] as String?,
      role: 'manager',
      isActive: (data['status'] as String? ?? 'active') != 'inactive',
      companyId: data['companyId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Future<void> syncOverdueCheckoutRequests() async {
    final now = DateTime.now();
    final lookbackStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 7));

    final snap = await _db
        .collection('attendance')
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(lookbackStart))
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['checkOutTime'] != null || data['checkInTime'] == null) {
        continue;
      }

      final employeeId = (data['employeeId'] as String? ?? '').trim();
      if (employeeId.isEmpty) continue;
      final attendanceDate =
          (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
      final dateKey = (data['dateKey'] as String?) ?? _dateKey(attendanceDate);
      final timeConfig = await _getAttendanceTimeConfig(attendanceDate);
      final missedCheckoutRequestTime =
          timeConfig.checkOutEndTime.add(_missedCheckoutGracePeriod);
      if (now.isBefore(missedCheckoutRequestTime)) continue;

      final requestRef =
          _db.collection('checkout_requests').doc('${employeeId}_$dateKey');
      final existingRequest = await requestRef.get();
      if (existingRequest.exists) continue;

      final staff = await getStaffByEmployeeId(employeeId);
      final empName = data['employeeName'] ?? staff?.name ?? '';
      final managerName =
          (data['managerName'] as String? ?? staff?.reportsTo ?? '').trim();
      await requestRef.set({
        'attendanceId': doc.id,
        'employeeId': employeeId,
        'employeeName': empName,
        'department': data['department'] ?? staff?.department ?? '',
        'email': staff?.email ?? '',
        'phone': staff?.phone ?? '',
        'managerName': managerName,
        'dateKey': dateKey,
        'checkInTime': data['checkInTime'],
        'checkoutDeadline': Timestamp.fromDate(timeConfig.checkOutEndTime),
        'checkoutGraceEndsAt': Timestamp.fromDate(missedCheckoutRequestTime),
        'status': 'pending',
        'queryMessage':
            'The employee did not check out within the configured checkout window or the one-hour grace period. Contact the employee to verify why checkout was missed before approving.',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Trigger push notification to Admin for approval and to the employee as
      // a heads-up that the missed checkout is waiting for approval.
      try {
        await NotificationService().sendCheckoutApprovalNotificationToAdmins(
          requestId: requestRef.id,
          employeeId: employeeId,
          employeeName: empName,
          dateKey: dateKey,
          checkoutEndLabel: _formatTime(timeConfig.checkOutEndTime),
          graceEndLabel: _formatTime(missedCheckoutRequestTime),
        );
        await NotificationService().sendCheckoutReminderNotificationToEmployee(
          employeeId: employeeId,
          employeeName: empName,
          requestId: requestRef.id,
          dateKey: dateKey,
          checkoutEndLabel: _formatTime(timeConfig.checkOutEndTime),
          graceEndLabel: _formatTime(missedCheckoutRequestTime),
        );
        if (managerName.isNotEmpty && managerName.toLowerCase() != 'admin') {
          await NotificationService().sendCheckoutReminderNotificationToManager(
            managerName: managerName,
            employeeId: employeeId,
            employeeName: empName,
            requestId: requestRef.id,
            dateKey: dateKey,
            checkoutEndLabel: _formatTime(timeConfig.checkOutEndTime),
            graceEndLabel: _formatTime(missedCheckoutRequestTime),
          );
        }
      } catch (e) {
        debugPrint('Failed to send forgot check-out alert: $e');
      }
    }
  }

  Future<void> syncOverdueAttendanceRecords() async {
    final now = DateTime.now();
    final lastSync = _lastOverdueAttendanceSync;
    if (lastSync != null && now.difference(lastSync).inMinutes < 10) {
      return;
    }
    _lastOverdueAttendanceSync = now;
    await syncOverdueCheckoutRequests();
    await syncMissingCheckInAbsences();
  }

  Future<void> syncMissingCheckInAbsences({
    DateTime? throughDate,
    int lookbackDays = 7,
  }) async {
    final now = DateTime.now();
    final lastDate = throughDate ?? now;
    final users = await _activeAttendanceUsers();
    if (users.isEmpty) return;

    for (var offset = lookbackDays; offset >= 0; offset--) {
      final rawDate = DateTime(lastDate.year, lastDate.month, lastDate.day)
          .subtract(Duration(days: offset));
      final timeConfig = await _getAttendanceTimeConfig(rawDate);
      if (now.isBefore(timeConfig.checkOutEndTime)) continue;
      if (!await _isWorkingDate(rawDate)) continue;

      final dateKey = _dateKey(rawDate);
      final existingSnap = await _db
          .collection('attendance')
          .where('dateKey', isEqualTo: dateKey)
          .get();

      var batch = _db.batch();
      var writeCount = 0;

      for (final user in users) {
        bool hasRecord = false;
        final userIdLower = user.id.toLowerCase();
        final userEmpIdLower = user.employeeId.toLowerCase();
        final userEmailLower = user.email.toLowerCase();

        for (final doc in existingSnap.docs) {
          final data = doc.data();
          final docEmpId =
              (data['employeeId'] as String? ?? '').trim().toLowerCase();
          final docId = doc.id.toLowerCase();

          // Match by employeeId field
          if (docEmpId == userEmpIdLower ||
              docEmpId == userIdLower ||
              docEmpId == userEmailLower) {
            hasRecord = true;
            break;
          }

          // Match by document ID parts
          final safeEmpId = _safeDocId(user.employeeId).toLowerCase();
          final safeUid = _safeDocId(user.id).toLowerCase();
          final safeEmail = _safeDocId(user.email).toLowerCase();

          if (docId.contains(safeEmpId) ||
              docId.contains(safeUid) ||
              docId.contains(safeEmail)) {
            hasRecord = true;
            break;
          }
        }

        if (hasRecord) continue;
        if (await isEmployeeOnApprovedLeave(user.employeeId, rawDate)) {
          continue;
        }

        final docId = 'missing_${_safeDocId(user.employeeId)}_$dateKey';
        final ref = _db.collection('attendance').doc(docId);
        batch.set(ref, {
          'employeeId': user.employeeId,
          'employeeName': user.name,
          'department': user.department,
          'managerName': user.reportsTo ?? '',
          'status': 'absent',
          'checkInTime': null,
          'checkOutTime': null,
          'dateKey': dateKey,
          'date': Timestamp.fromDate(rawDate),
          'workingMinutes': 0,
          'workingHours': '00:00',
          'lateMinutes': 0,
          'latePendingMinutes': 0,
          'earlyCheckoutPendingMinutes': 0,
          'permissionPendingMinutes': 0,
          'permissionMinutes': 0,
          'pendingMinutes': 0,
          'pendingAbsenceStatus': 'none',
          'arrivalBand': 'red',
          'policyAction': 'no_check_in_absent',
          'policyLabel': 'No check-in by office end',
          'officeStartTime': timeConfig.checkInEnd,
          'officeCheckOutStartTime': timeConfig.checkOutStart,
          'officeEndTime': timeConfig.checkOutEnd,
          'currentState': AttendanceState.none.name,
          'autoMarkedAbsent': true,
          'autoAbsentReason': 'No check-in recorded before office end time.',
          'companyId': user.companyId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        unawaited(_notifyMissingCheckInAbsence(user));
        writeCount++;

        if (writeCount == 450) {
          await batch.commit();
          batch = _db.batch();
          writeCount = 0;
        }
      }

      if (writeCount > 0) {
        await batch.commit();
      }
    }
  }

  Future<List<Staff>> _activeAttendanceUsers() async {
    final staffSnap = await _db.collection('staff').get();
    final managerSnap = await _db.collection('managers').get();
    final usersByEmployeeId = <String, Staff>{};

    for (final doc in staffSnap.docs) {
      final staff = Staff.fromFirestore(doc);
      final employeeId = staff.employeeId.trim().isNotEmpty
          ? staff.employeeId.trim()
          : doc.id.trim();
      if (!staff.isActive || employeeId.isEmpty) continue;
      usersByEmployeeId[employeeId] = Staff(
        id: staff.id,
        name: staff.name,
        email: staff.email,
        phone: staff.phone,
        department: staff.department,
        position: staff.position,
        employeeId: employeeId,
        joinDate: staff.joinDate,
        photoUrl: staff.photoUrl,
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
        companyId: staff.companyId,
      );
    }

    for (final doc in managerSnap.docs) {
      final data = doc.data();
      if ((data['status'] as String? ?? 'active') == 'inactive') continue;
      final manager = _managerDocAsStaff(doc);
      final employeeId = manager.employeeId.trim().isNotEmpty
          ? manager.employeeId.trim()
          : doc.id.trim();
      if (employeeId.isEmpty) continue;
      usersByEmployeeId.putIfAbsent(
        employeeId,
        () => Staff(
          id: manager.id,
          name: manager.name,
          email: manager.email,
          phone: manager.phone,
          department: manager.department,
          position: manager.position,
          employeeId: employeeId,
          joinDate: manager.joinDate,
          photoUrl: manager.photoUrl,
          photoBase64: manager.photoBase64,
          reportsTo: manager.reportsTo,
          salary: manager.salary,
          role: 'manager',
          isActive: manager.isActive,
          createdAt: manager.createdAt,
          updatedAt: manager.updatedAt,
          companyId: manager.companyId,
        ),
      );
    }

    return usersByEmployeeId.values.toList();
  }

  Future<void> _notifyMissingCheckInAbsence(Staff user) async {
    final recipients = <String>{
      'Admin',
      if (user.reportsTo?.trim().isNotEmpty == true) user.reportsTo!.trim(),
    };
    const missingTitle = 'Attendance Update';
    const missingBody = '📌 No check-in activity detected today.';

    for (final recipient in recipients) {
      await NotificationService().recordDashboardNotification(
        recipient: recipient,
        type: 'Attendance',
        title: missingTitle,
        content: missingBody,
        data: {
          'employeeId': user.employeeId,
          'employeeName': user.name,
          'managerName': user.reportsTo,
          'attendanceAction': 'missing-check-in',
        },
      );
    }

    final data = {
      'employeeId': user.employeeId,
      'employeeName': user.name,
      'managerName': user.reportsTo,
      'attendanceAction': 'missing-check-in',
    };

    await NotificationService().sendNotificationToRole(
      role: 'admin',
      title: missingTitle,
      body: missingBody,
      data: data,
    );
    if (user.reportsTo?.trim().isNotEmpty == true) {
      await NotificationService().sendNotificationToUser(
        identifier: user.reportsTo!.trim(),
        title: missingTitle,
        body: missingBody,
        data: data,
      );
    }
  }

  Future<bool> _isWorkingDate(DateTime date) async {
    final doc = await _db.collection('geo_config').doc('default').get();
    final data = doc.data() ?? const <String, dynamic>{};
    final dateKey = _dateKey(date);
    final holidayDates = (data['holidayDates'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (holidayDates.contains(dateKey)) return false;

    final sundayWorking = data['sundayWorking'] as bool? ?? false;
    if (date.weekday == DateTime.saturday) return true;
    if (date.weekday == DateTime.sunday) return sundayWorking;
    return true;
  }

  String _safeDocId(String value) {
    return value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  Stream<List<CheckoutRequest>> getCheckoutRequestsStream() {
    return _db
        .collection('checkout_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => CheckoutRequest.fromFirestore(doc))
            .toList());
  }

  /// Company-wide checkout requests restricted to a manager's reporting line.
  ///
  /// Mirrors the manager-scoping used for leave/permission: subscribe to the
  /// manager's team (staff whose `reportsTo` matches the manager), then filter
  /// the full `checkout_requests` collection client-side to only those whose
  /// `employeeId` belongs to the team. This is additive — the existing
  /// [getCheckoutRequestsStream] is untouched.
  Stream<List<CheckoutRequest>> getCheckoutRequestsForManager(
      String managerName) {
    final controller = StreamController<List<CheckoutRequest>>.broadcast();
    StreamSubscription? teamSub;
    StreamSubscription? requestSub;

    void cleanup() {
      teamSub?.cancel();
      requestSub?.cancel();
    }

    teamSub = _teamEmployeeIdsStream(managerName).listen((teamIds) {
      requestSub?.cancel();
      final normalizedTeam = teamIds.map(_normalizeIdentity).toSet();
      requestSub = _db
          .collection('checkout_requests')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs
              .map((doc) => CheckoutRequest.fromFirestore(doc))
              .where((req) =>
                  normalizedTeam.contains(_normalizeIdentity(req.employeeId)))
              .toList())
          .listen((requests) {
        if (!controller.isClosed) controller.add(requests);
      }, onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      });
    }, onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    });

    controller.onCancel = cleanup;
    return controller.stream.asBroadcastStream();
  }

  Future<void> approveCheckoutRequest(
    CheckoutRequest request, {
    required String adminNote,
  }) async {
    final batch = _db.batch();
    final requestRef = _db.collection('checkout_requests').doc(request.id);

    batch.update(requestRef, {
      'status': 'approved',
      'adminNote': adminNote,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (request.attendanceId.isNotEmpty) {
      final attendanceRef =
          _db.collection('attendance').doc(request.attendanceId);
      final timeConfig =
          await _getAttendanceTimeConfig(request.checkoutDeadline);
      final workedDuration = request.checkInTime == null
          ? Duration.zero
          : _effectiveWorkingDuration(
              checkIn: request.checkInTime!,
              checkOut: request.checkoutDeadline,
              timeConfig: timeConfig,
            );
      final latePendingMinutes = request.checkInTime == null
          ? 480
          : _pendingMinutesAfterStart(
              request.checkInTime!,
              timeConfig.checkInEndTime,
            );
      final permissionPendingMinutes = await _permissionPendingMinutesForDay(
        employeeId: request.employeeId,
        date: request.checkoutDeadline,
      );
      const earlyCheckoutPendingMinutes = 0;
      final pendingMinutes = _combinedPendingMinutes(
        latePendingMinutes: latePendingMinutes,
        earlyCheckoutPendingMinutes: earlyCheckoutPendingMinutes,
        permissionPendingMinutes: permissionPendingMinutes,
      );
      final pendingStatus = _pendingAbsenceStatus(pendingMinutes);
      batch.update(attendanceRef, {
        'checkOutTime': Timestamp.fromDate(request.checkoutDeadline),
        'workingMinutes':
            workedDuration.isNegative ? 0 : workedDuration.inMinutes,
        'workingHours': _formatWorkingHours(workedDuration),
        'isEarlyCheckout': false,
        'earlyCheckoutMinutes': 0,
        'latePendingMinutes': latePendingMinutes,
        'earlyCheckoutPendingMinutes': earlyCheckoutPendingMinutes,
        'permissionPendingMinutes': permissionPendingMinutes,
        'permissionMinutes': permissionPendingMinutes,
        'pendingMinutes': pendingMinutes,
        'pendingAbsenceStatus': pendingStatus,
        'status': latePendingMinutes > 0 ? 'late' : 'present',
        'policyAction': _policyActionForPendingStatus(
          existingAction: null,
          pendingStatus: pendingStatus,
        ),
        'officeStartTime': timeConfig.checkInEnd,
        'officeCheckOutStartTime': timeConfig.checkOutStart,
        'officeEndTime': timeConfig.checkOutEnd,
        'checkoutApprovedByAdmin': true,
        'checkoutApprovalNote': adminNote,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // Trigger push notification back to the employee
    try {
      await NotificationService().sendNotificationToUser(
        identifier: request.employeeId,
        title: 'Checkout Request Approved',
        body:
            'Your missed checkout on ${request.dateKey} was approved by Admin.',
      );
    } catch (e) {
      debugPrint('Failed to send checkout approval push notification: $e');
    }
  }

  Future<void> rejectCheckoutRequest(
    CheckoutRequest request, {
    required String adminNote,
  }) async {
    await _db.collection('checkout_requests').doc(request.id).update({
      'status': 'rejected',
      'adminNote': adminNote,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Trigger push notification back to the employee
    try {
      await NotificationService().sendNotificationToUser(
        identifier: request.employeeId,
        title: 'Checkout Request Rejected',
        body:
            'Your missed checkout on ${request.dateKey} was rejected by Admin.',
      );
    } catch (e) {
      debugPrint('Failed to send checkout rejection push notification: $e');
    }
  }

  Future<String?> getManagerNameByEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return null;
    final query = await _db
        .collection('managers')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      return query.docs.first.data()['name']?.toString().trim();
    }
    return null;
  }

  Stream<List<AttendanceAlert>> getTodayAlerts() {
    final todayKey = _dateKey(DateTime.now());
    return _db
        .collection('attendance_alerts')
        .where('dateKey', isEqualTo: todayKey)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AttendanceAlert.fromFirestore(doc))
            .toList());
  }

  Stream<List<AttendanceAlert>> getTodayAlertsByManager(String managerName) {
    final todayKey = _dateKey(DateTime.now());
    return _teamEmployeeIdsStream(managerName).asyncExpand((staffIds) {
      if (staffIds.isEmpty) {
        return Stream.value(<AttendanceAlert>[]);
      }

      final staffIdSet = staffIds.toSet();
      return _db
          .collection('attendance_alerts')
          .where('dateKey', isEqualTo: todayKey)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs
              .map((doc) => AttendanceAlert.fromFirestore(doc))
              .where((alert) => staffIdSet.contains(alert.employeeId))
              .toList());
    }).asBroadcastStream();
  }

  // ─── QR Code ──────────────────────────────────────────────────────────
  Future<String> generateQrToken(
    String tenantId, {
    Duration validFor = const Duration(days: 90),
    String refreshSource = 'manual',
  }) async {
    final token = _generateSecureToken();
    final expiresAt = DateTime.now().add(validFor);
    final geoFenceRadius = await _currentGeoFenceRadius();
    await _db.collection('qr_tokens').doc(tenantId).set({
      'token': token,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'refreshedAt': FieldValue.serverTimestamp(),
      'tenantId': tenantId,
      'geoFenceRadius': geoFenceRadius,
      'validForDays': validFor.inDays,
      'refreshSource': refreshSource,
    });
    unawaited(_notifyAdminQrTokenGenerated(
      tenantId: tenantId,
      expiresAt: expiresAt,
      refreshSource: refreshSource,
    ));
    return token;
  }

  Future<void> _notifyAdminQrTokenGenerated({
    required String tenantId,
    required DateTime expiresAt,
    required String refreshSource,
  }) async {
    try {
      final cleanSource = refreshSource.trim().toLowerCase();
      final isManual = cleanSource == 'manual';
      final title =
          isManual ? 'QR Code Manually Refreshed' : 'QR Code Auto Refreshed';
      final content = isManual
          ? 'Attendance QR code was manually refreshed by admin. Valid until ${_dateKey(expiresAt)}.'
          : 'Attendance QR code was automatically refreshed. Valid until ${_dateKey(expiresAt)}.';

      await _db.collection('notifications').add({
        'recipient': 'Admin',
        'type': 'QR Code',
        'title': title,
        'content': content,
        'status': 'Sent',
        'suppressFirestorePush': true,
        'allowFirestorePush': false,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'tenantId': tenantId,
        'qrEvent': isManual ? 'manual_refresh' : 'auto_refresh',
        'refreshSource': cleanSource.isEmpty ? 'manual' : cleanSource,
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
      await NotificationService().sendNotificationToRole(
        role: 'admin',
        title: title,
        body: content,
        data: {
          'type': 'QR Code',
          'actionType': 'qr_code',
          'tenantId': tenantId,
          'qrEvent': isManual ? 'manual_refresh' : 'auto_refresh',
          'refreshSource': cleanSource.isEmpty ? 'manual' : cleanSource,
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Error sending QR admin notification: $e');
    }
  }

  Future<double> _currentGeoFenceRadius() async {
    final geoConfig = await _db.collection('geo_config').doc('default').get();
    final geoData = geoConfig.data() ?? const <String, dynamic>{};
    final geoRadius = (geoData['radius'] as num?)?.toDouble() ??
        (geoData['geoFenceRadius'] as num?)?.toDouble();
    if (geoRadius != null) return geoRadius;

    final officeConfig = await _db.collection('offices').doc('default').get();
    final officeData = officeConfig.data() ?? const <String, dynamic>{};
    return (officeData['radius'] as num?)?.toDouble() ??
        (officeData['geoFenceRadius'] as num?)?.toDouble() ??
        50.0;
  }

  Future<bool> _validateEmployeeInfo({
    required String employeeId,
    required String employeeName,
    required String department,
  }) async {
    final snap = await _db
        .collection('staff')
        .where('employeeId', isEqualTo: employeeId)
        .limit(1)
        .get();

    Map<String, dynamic>? data;
    if (snap.docs.isNotEmpty) {
      data = snap.docs.first.data();
      if ((data['isActive'] as bool?) == false) return false;
    } else {
      final managerSnap = await _db
          .collection('managers')
          .where('employeeId', isEqualTo: employeeId)
          .limit(1)
          .get();
      if (managerSnap.docs.isNotEmpty) {
        data = managerSnap.docs.first.data();
      } else {
        final managerByEmail = await _db
            .collection('managers')
            .where('email', isEqualTo: employeeId)
            .limit(1)
            .get();
        if (managerByEmail.docs.isEmpty) return false;
        data = managerByEmail.docs.first.data();
      }
      if ((data['status'] as String? ?? 'active') == 'inactive') return false;
    }

    if (employeeName.isNotEmpty && data['name'] != null) {
      final storedName = data['name'].toString().trim().toLowerCase();
      if (storedName.isNotEmpty &&
          storedName != employeeName.trim().toLowerCase()) {
        return false;
      }
    }

    if (department.isNotEmpty && data['department'] != null) {
      final storedDept = data['department'].toString().trim().toLowerCase();
      if (storedDept.isNotEmpty &&
          storedDept != department.trim().toLowerCase()) {
        return false;
      }
    }

    return true;
  }

  Stream<Map<String, dynamic>> getQrTokenStream(String tenantId) {
    return _db
        .collection('qr_tokens')
        .doc(tenantId)
        .snapshots()
        .map((snap) => snap.data() ?? {});
  }

  Future<AttendanceSubmissionResult> validateQrToken(String qrToken) async {
    final token = qrToken.trim();
    if (token.isEmpty) {
      return AttendanceSubmissionResult(
        success: false,
        status: 'invalid-token',
        message: 'The scanned QR token is empty.',
      );
    }

    final qrDoc = await _db
        .collection('qr_tokens')
        .where('token', isEqualTo: token)
        .limit(1)
        .get();

    if (qrDoc.docs.isEmpty) {
      return AttendanceSubmissionResult(
        success: false,
        status: 'invalid-token',
        message: 'The scanned QR is not a valid admin attendance QR code.',
      );
    }

    final tokenData = qrDoc.docs.first.data();
    final expiresAt = (tokenData['expiresAt'] as Timestamp?)?.toDate();
    if (expiresAt == null) {
      return AttendanceSubmissionResult(
        success: false,
        status: 'invalid-token',
        message:
            'The scanned QR code is missing expiry details. Ask admin to refresh the QR code.',
      );
    }

    if (DateTime.now().isAfter(expiresAt)) {
      return AttendanceSubmissionResult(
        success: false,
        status: 'expired-token',
        message:
            'The scanned QR code has expired. Ask admin to refresh the QR code.',
      );
    }

    return AttendanceSubmissionResult(
      success: true,
      status: 'valid-token',
      message:
          'QR verified. Staff details matched. Tap Mark Attendance to submit.',
    );
  }

  // ─── Geo-fence Validation ─────────────────────────────────────────────
  bool isWithinGeoFence({
    required double userLat,
    required double userLng,
    required double officeLat,
    required double officeLng,
    double radiusMetres = 50,
    double userAccuracyMetres = 0,
  }) {
    const earthRadius = 6371000.0;
    final dLat = _deg2rad(userLat - officeLat);
    final dLon = _deg2rad(userLng - officeLng);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(officeLat)) *
            cos(_deg2rad(userLat)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = earthRadius * c;
    final effectiveDistance = GeoFenceService.effectiveDistance(
      distanceMetres: distance,
      accuracyMetres: userAccuracyMetres,
    );
    return effectiveDistance <=
        GeoFenceService.validationRadius(radiusMetres: radiusMetres);
  }

  // ─── Mark Attendance ──────────────────────────────────────────────────
  Future<AttendanceSubmissionResult> markAttendance({
    required String employeeId,
    required String employeeName,
    required String department,
    required String qrToken,
    required double userLat,
    required double userLng,
    required double officeLat,
    required double officeLng,
    double geoFenceRadiusMetres = 50,
    double userAccuracyMetres = 0,
    bool isWfh = false,
  }) async {
    final submittedEmployeeId = employeeId.trim();
    final submittedEmployeeName = employeeName.trim();
    final submittedDepartment = department.trim();
    final staffSnap = await _db
        .collection('staff')
        .where('employeeId', isEqualTo: submittedEmployeeId)
        .limit(1)
        .get();
    final staffData =
        staffSnap.docs.isNotEmpty ? staffSnap.docs.first.data() : null;
    Map<String, dynamic>? managerData;
    if (staffData == null) {
      final managerSnap = await _db
          .collection('managers')
          .where('employeeId', isEqualTo: submittedEmployeeId)
          .limit(1)
          .get();
      managerData =
          managerSnap.docs.isNotEmpty ? managerSnap.docs.first.data() : null;
      if (managerData == null) {
        final managerById =
            await _db.collection('managers').doc(submittedEmployeeId).get();
        managerData = managerById.data();
      }
      if (managerData == null) {
        final managerByEmail = await _db
            .collection('managers')
            .where('email', isEqualTo: submittedEmployeeId)
            .limit(1)
            .get();
        managerData = managerByEmail.docs.isNotEmpty
            ? managerByEmail.docs.first.data()
            : null;
      }
    }
    final isManagerAttendance = staffData == null && managerData != null;
    final canonicalEmployeeId = isManagerAttendance
        ? ((managerData['employeeId'] as String?)?.trim().isNotEmpty == true
            ? (managerData['employeeId'] as String).trim()
            : ((managerData['email'] as String?)?.trim().isNotEmpty == true
                ? (managerData['email'] as String).trim()
                : submittedEmployeeId))
        : submittedEmployeeId;
    final canonicalEmployeeName = isManagerAttendance
        ? ((managerData['name'] as String?)?.trim().isNotEmpty == true
            ? (managerData['name'] as String).trim()
            : submittedEmployeeName)
        : submittedEmployeeName;
    final canonicalDepartment = isManagerAttendance
        ? ((managerData['department'] as String?)?.trim().isNotEmpty == true
            ? (managerData['department'] as String).trim()
            : 'Management')
        : submittedDepartment;
    final managerName = isManagerAttendance
        ? 'Admin'
        : staffData?['reportsTo']?.toString() ??
            managerData?['reportsTo']?.toString() ??
            managerData?['name']?.toString();
    final employeePhotoUrl =
        (staffData?['photoUrl'] ?? managerData?['photoUrl'])?.toString();

    // 0. Validate staff/manager details first
    if (!await _validateEmployeeInfo(
      employeeId: canonicalEmployeeId,
      employeeName: canonicalEmployeeName,
      department: canonicalDepartment,
    )) {
      return AttendanceSubmissionResult(
        success: false,
        status: 'invalid-details',
        message: isManagerAttendance
            ? 'Manager details do not match the database.'
            : 'Employee details do not match the database.',
      );
    }

    // 1. Validate QR token
    final tokenValidation = await validateQrToken(qrToken);
    if (!tokenValidation.success) return tokenValidation;

    // 2. Validate geo-fence (skip for WFH)
    if (!isWfh) {
      final withinFence = isWithinGeoFence(
        userLat: userLat,
        userLng: userLng,
        officeLat: officeLat,
        officeLng: officeLng,
        radiusMetres: geoFenceRadiusMetres,
        userAccuracyMetres: userAccuracyMetres,
      );
      if (!withinFence) {
        return AttendanceSubmissionResult(
          success: false,
          status: 'outside-geofence',
          message:
              'You are outside the approved ${geoFenceRadiusMetres.toStringAsFixed(0)}m work zone.',
        );
      }
    }

    // 3. Determine status and policy effects
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final timeConfig = await _getAttendanceTimeConfig(now);
    final configuredThreshold = timeConfig.checkInEndTime;
    final lateMinutes =
        isWfh ? 0 : _lateMinutesWithThreshold(now, configuredThreshold);
    final status = isWfh
        ? 'wfh'
        : lateMinutes > 0
            ? 'late'
            : 'present';
    final policy = await _policyForLateArrival(
      employeeId: canonicalEmployeeId,
      now: now,
      lateMinutes: lateMinutes,
      isWfh: isWfh,
    );
    final recordStatus = status;
    final latePendingMinutes =
        isWfh ? 0 : _pendingMinutesAfterStart(now, timeConfig.checkInEndTime);
    final initialPendingStatus = _pendingAbsenceStatus(latePendingMinutes);
    final initialPolicyAction = _policyActionForPendingStatus(
      existingAction: policy.action,
      pendingStatus: initialPendingStatus,
    );
    final initialRecordStatus = recordStatus;

    final attendanceRef = _db
        .collection('attendance')
        .doc('attendance_${_safeDocId(canonicalEmployeeId)}_$todayKey');

    // ─── Pre-transaction: checks that don't need transactional reads ─────
    // Check if it's past office end and no record exists (absent case)
    final preCheckSnap = await attendanceRef.get();
    DocumentReference<Map<String, dynamic>>? legacyAttRef;
    if (!preCheckSnap.exists) {
      final legacySnap = await _db
          .collection('attendance')
          .where('employeeId', isEqualTo: canonicalEmployeeId)
          .where('dateKey', isEqualTo: todayKey)
          .limit(1)
          .get();
      if (legacySnap.docs.isNotEmpty) {
        legacyAttRef = legacySnap.docs.first.reference;
      }
    }

    final bool noRecordExists = !preCheckSnap.exists && legacyAttRef == null;

    if (noRecordExists) {
      // ─── CHECK-IN PATH ──────────────────────────────────────────────────
      if (!now.isBefore(timeConfig.checkOutEndTime) &&
          await _isWorkingDate(now)) {
        await syncMissingCheckInAbsences(throughDate: now, lookbackDays: 0);
        return AttendanceSubmissionResult(
          success: false,
          status: 'absent',
          message:
              'Check-in is closed for today. You were marked absent because no check-in was recorded before office end time.',
        );
      }

      final pendingCheckoutSnap = await _db
          .collection('checkout_requests')
          .where('employeeId', isEqualTo: canonicalEmployeeId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (pendingCheckoutSnap.docs.isNotEmpty) {
        return AttendanceSubmissionResult(
          success: false,
          status: 'pending-checkout',
          message:
              'Check-in restricted. You have a pending check-out approval request for a previous day. Please wait for admin approval before checking in.',
        );
      }

      final checkInData = <String, dynamic>{
        'employeeId': canonicalEmployeeId,
        'employeeName': canonicalEmployeeName,
        'department': canonicalDepartment,
        'managerName': managerName,
        'status': initialRecordStatus,
        'checkInTime': Timestamp.fromDate(now),
        'checkInQrToken': qrToken,
        'dateKey': todayKey,
        'date': Timestamp.fromDate(now),
        'latitude': isWfh ? null : userLat,
        'longitude': isWfh ? null : userLng,
        'employeePhotoUrl': employeePhotoUrl,
        'officeLatitude': officeLat,
        'officeLongitude': officeLng,
        'geoFenceRadiusMetres': geoFenceRadiusMetres,
        'lateMinutes': lateMinutes,
        'latePendingMinutes': latePendingMinutes,
        'earlyCheckoutPendingMinutes': 0,
        'permissionPendingMinutes': 0,
        'permissionMinutes': 0,
        'pendingMinutes': latePendingMinutes,
        'pendingAbsenceStatus': initialPendingStatus,
        'officeStartTime': timeConfig.checkInEnd,
        'officeCheckOutStartTime': timeConfig.checkOutStart,
        'officeEndTime': timeConfig.checkOutEnd,
        'arrivalBand': _arrivalBand(lateMinutes, isWfh: isWfh),
        'policyAction': initialPolicyAction,
        'policyLabel': policy.label,
        'currentState': AttendanceState.checkIn.name,
        'companyId': staffData?['companyId'] ?? managerData?['companyId'],
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Transactional check-in (unchanged — already safe)
      final created = await _db.runTransaction<bool>((transaction) async {
        final latest = await transaction.get(attendanceRef);
        if (latest.exists) return false;
        transaction.set(attendanceRef, checkInData);
        return true;
      });

      if (!created) {
        return AttendanceSubmissionResult(
          success: false,
          status: 'already-checked-in',
          message:
              'Check-in was already recorded. Refresh your attendance status before scanning again.',
        );
      }

      // Side-effects (fire-and-forget, outside transaction)
      await _logService.logEvent(
        staffId: canonicalEmployeeId,
        staffName: canonicalEmployeeName,
        eventType: AttendanceEventType.checkIn,
        qrValidated: true,
        geofenceValidated: !isWfh,
        latitude: userLat,
        longitude: userLng,
      );

      unawaited(_sendAttendancePushNotification(
        employeeId: canonicalEmployeeId,
        employeeName: canonicalEmployeeName,
        managerName: managerName,
        action: initialRecordStatus == 'late' ? 'late check-in' : 'check-in',
        detail: initialRecordStatus == 'late'
            ? '$lateMinutes'
            : initialRecordStatus,
      ));

      return AttendanceSubmissionResult(
        success: true,
        status: initialRecordStatus,
        message: initialRecordStatus == 'late'
            ? 'Late check-in recorded.'
            : 'Checked-in successfully as ${initialRecordStatus == 'present' ? 'Ontime' : initialRecordStatus.toUpperCase()}.',
        action: AttendanceSubmissionAction.checkIn,
        lateMinutes: lateMinutes,
      );
    }

    // ─── EXISTING RECORD PATH (check-out / temp-exit / re-entry) ─────────
    // Resolve which document reference to use for the transaction
    final docRef = preCheckSnap.exists ? attendanceRef : legacyAttRef!;

    // Pre-fetch permission data needed by temp-exit and re-entry branches
    // (Firestore transactions cannot do queries, only doc.get)
    final activePermission =
        await _permissionService.getActiveApprovedPermission(
      canonicalEmployeeId,
    );
    final openPermission = await _permissionService.getOpenApprovedPermission(
      canonicalEmployeeId,
    );

    // Pre-fetch checkout request for the missed-checkout guard
    final pendingCheckoutRequest = await _db
        .collection('checkout_requests')
        .doc('${canonicalEmployeeId}_$todayKey')
        .get();

    // Pre-compute permission pending minutes (requires a query)
    final permissionPendingMinutes = isWfh
        ? 0
        : await _permissionPendingMinutesForDay(
            employeeId: canonicalEmployeeId,
            date: now,
          );

    // ─── UNIFIED TRANSACTION ────────────────────────────────────────────
    // This enum-like result lets us capture what happened inside the
    // transaction so we can fire the right side-effects afterwards.
    final txResult = await _db.runTransaction<_MarkAttendanceTxResult>(
      (transaction) async {
        // Re-read the document INSIDE the transaction for consistency
        final freshSnap = await transaction.get(docRef);
        if (!freshSnap.exists) {
          return _MarkAttendanceTxResult.error(
            status: 'unknown-state',
            message:
                'Attendance record not found. Please try checking in again.',
          );
        }

        final data = freshSnap.data()!;
        final stateStr = data['currentState'] ?? 'NONE';
        final state = AttendanceState.values.firstWhere(
          (e) => e.name == stateStr,
          orElse: () => AttendanceState.none,
        );

        // ─── Already checked out ──────────────────────────────────────────
        if (state == AttendanceState.finalCheckout) {
          return _MarkAttendanceTxResult.error(
            status: data['status'] ?? 'present',
            message: 'You have already checked out for today.',
          );
        }

        // ─── Absent record ───────────────────────────────────────────────
        if (state == AttendanceState.none &&
            data['checkInTime'] == null &&
            (data['status'] as String? ?? '') == 'absent') {
          final pa = data['policyAction'] as String? ?? '';
          return _MarkAttendanceTxResult.error(
            status: 'absent',
            message: pa == 'no_check_in_absent'
                ? 'Check-in is closed for today. You were marked absent because no check-in was recorded before office end time.'
                : 'Attendance is already marked absent for today.',
          );
        }

        // ─── CHECK_IN or RE_ENTRY → either TEMP_EXIT or FINAL_CHECKOUT ──
        if (state == AttendanceState.checkIn ||
            state == AttendanceState.reEntry) {
          // ── TEMP_EXIT ─────────────────────────────────────────────────
          if (activePermission != null) {
            if (!isWfh &&
                !isWithinGeoFence(
                    userLat: userLat,
                    userLng: userLng,
                    officeLat: officeLat,
                    officeLng: officeLng,
                    radiusMetres: geoFenceRadiusMetres,
                    userAccuracyMetres: userAccuracyMetres)) {
              return _MarkAttendanceTxResult.error(
                status: 'outside-geofence',
                message: 'You must be at the office to mark a temporary exit.',
              );
            }

            transaction.update(docRef, {
              'currentState': AttendanceState.tempExit.name,
              'lastExitTime': Timestamp.fromDate(now),
              'permissionId': activePermission.id,
              'permissionApprovedUntil': activePermission.returnTime != null
                  ? Timestamp.fromDate(activePermission.returnTime!)
                  : null,
              'permissionDelayMinutes': 0,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            return _MarkAttendanceTxResult.tempExit(
              docStatus: data['status'] ?? 'present',
              permissionId: activePermission.id,
              permissionReturnTime: activePermission.returnTime,
            );
          }

          // ── FINAL_CHECKOUT ────────────────────────────────────────────
          final checkInTime = (data['checkInTime'] as Timestamp).toDate();
          final rawWorkedDuration = now.difference(checkInTime);

          if (rawWorkedDuration < _minimumCheckOutDelay) {
            return _MarkAttendanceTxResult.error(
              status: 'checkout-too-early',
              message:
                  'Check-out is not permitted at this time. Employees must complete a minimum of 4 hours of work before checking out.',
              action: AttendanceSubmissionAction.checkOutBlocked,
              earlyCheckoutMinutes:
                  (_minimumCheckOutDelay - rawWorkedDuration).inMinutes,
            );
          }

          final missedCheckoutRequestTime =
              timeConfig.checkOutEndTime.add(_missedCheckoutGracePeriod);
          if (now.isAfter(missedCheckoutRequestTime) &&
              pendingCheckoutRequest.exists &&
              (pendingCheckoutRequest.data()?['status'] as String? ?? '')
                      .toLowerCase() ==
                  'pending') {
            return _MarkAttendanceTxResult.error(
              status: 'pending-checkout',
              message:
                  'Your check-out window has closed and the missed check-out request is already waiting for admin approval.',
              action: AttendanceSubmissionAction.checkOutBlocked,
            );
          }

          final storedLatePending =
              (data['latePendingMinutes'] as num?)?.toInt() ??
                  (isWfh
                      ? 0
                      : _pendingMinutesAfterStart(
                          checkInTime, timeConfig.checkInEndTime));
          final earlyPendingMinutes = isWfh
              ? 0
              : _earlyCheckoutMinutesBeforeStart(
                  now,
                  timeConfig.checkOutStartTime,
                );
          final isEarlyCheckout = earlyPendingMinutes > 0;
          final checkoutWindowStatus = isEarlyCheckout
              ? 'early'
              : now.isAfter(timeConfig.checkOutEndTime)
                  ? 'after_window'
                  : 'within_window';
          final earlyCheckoutMinutes = earlyPendingMinutes;
          final pendingMinutes = isWfh
              ? 0
              : _combinedPendingMinutes(
                  latePendingMinutes: storedLatePending,
                  earlyCheckoutPendingMinutes: earlyPendingMinutes,
                  permissionPendingMinutes: permissionPendingMinutes,
                );
          final pendingStatus = _pendingAbsenceStatus(pendingMinutes);
          final existingPolicyAction =
              data['policyAction'] as String? ?? 'none';
          final updatedPolicyAction = _policyActionForPendingStatus(
            existingAction: existingPolicyAction,
            pendingStatus: pendingStatus,
          );
          final updatedStatus = data['status'] as String? ?? status;
          final workedDuration = _effectiveWorkingDuration(
            checkIn: checkInTime,
            checkOut: now,
            timeConfig: timeConfig,
          );

          transaction.update(docRef, {
            'status': updatedStatus,
            'checkOutTime': Timestamp.fromDate(now),
            'currentState': AttendanceState.finalCheckout.name,
            'workingMinutes': workedDuration.inMinutes,
            'workingHours': _formatWorkingHours(workedDuration),
            'isEarlyCheckout': isEarlyCheckout,
            'checkoutWindowStatus': checkoutWindowStatus,
            'earlyCheckoutMinutes': earlyCheckoutMinutes,
            'latePendingMinutes': storedLatePending,
            'earlyCheckoutPendingMinutes': earlyPendingMinutes,
            'permissionPendingMinutes': permissionPendingMinutes,
            'permissionMinutes': permissionPendingMinutes,
            'pendingMinutes': pendingMinutes,
            'pendingAbsenceStatus': pendingStatus,
            'policyAction': updatedPolicyAction,
            'officeStartTime': timeConfig.checkInEnd,
            'officeCheckOutStartTime': timeConfig.checkOutStart,
            'officeEndTime': timeConfig.checkOutEnd,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return _MarkAttendanceTxResult.finalCheckout(
            updatedStatus: updatedStatus,
            isEarlyCheckout: isEarlyCheckout,
            earlyCheckoutMinutes: earlyCheckoutMinutes,
            pendingMinutes: pendingMinutes,
            pendingStatus: pendingStatus,
            storedLatePending: storedLatePending,
            permissionPendingMinutes: permissionPendingMinutes,
          );
        }

        // ─── TEMP_EXIT → RE_ENTRY ─────────────────────────────────────────
        if (state == AttendanceState.tempExit) {
          if (!isWfh &&
              !isWithinGeoFence(
                  userLat: userLat,
                  userLng: userLng,
                  officeLat: officeLat,
                  officeLng: officeLng,
                  radiusMetres: geoFenceRadiusMetres,
                  userAccuracyMetres: userAccuracyMetres)) {
            return _MarkAttendanceTxResult.error(
              status: 'outside-geofence',
              message: 'You must be at the office to mark re-entry.',
            );
          }

          final approvedReturnTime =
              openPermission?.approvedReturnTime ?? openPermission?.returnTime;
          final delayMinutes =
              approvedReturnTime != null && now.isAfter(approvedReturnTime)
                  ? now.difference(approvedReturnTime).inMinutes
                  : 0;

          final storedLatePending =
              (data['latePendingMinutes'] as num?)?.toInt() ??
                  _pendingMinutesAfterStart(
                    ((data['checkInTime'] as Timestamp?)?.toDate()) ?? now,
                    timeConfig.checkInEndTime,
                  );
          final pendingMinutes = _combinedPendingMinutes(
            latePendingMinutes: storedLatePending,
            earlyCheckoutPendingMinutes:
                (data['earlyCheckoutPendingMinutes'] as num?)?.toInt() ?? 0,
            permissionPendingMinutes: permissionPendingMinutes,
          );
          final pendingStatus = _pendingAbsenceStatus(pendingMinutes);
          final updatedPolicyAction = _policyActionForPendingStatus(
            existingAction: data['policyAction'] as String? ?? 'none',
            pendingStatus: pendingStatus,
          );

          // Single atomic update (no double-update)
          transaction.update(docRef, {
            'currentState': AttendanceState.reEntry.name,
            'lastReturnTime': Timestamp.fromDate(now),
            'permissionId': openPermission?.id ?? data['permissionId'],
            'permissionApprovedUntil': approvedReturnTime != null
                ? Timestamp.fromDate(approvedReturnTime)
                : data['permissionApprovedUntil'],
            'permissionDelayMinutes': delayMinutes,
            'permissionPendingMinutes': permissionPendingMinutes,
            'permissionMinutes': permissionPendingMinutes,
            'pendingMinutes': pendingMinutes,
            'pendingAbsenceStatus': pendingStatus,
            'policyAction': updatedPolicyAction,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return _MarkAttendanceTxResult.reEntry(
            docStatus: data['status'] ?? 'present',
            permissionId: openPermission?.id,
            delayMinutes: delayMinutes,
            pendingMinutes: pendingMinutes,
            pendingStatus: pendingStatus,
            permissionPendingMinutes: permissionPendingMinutes,
          );
        }

        return _MarkAttendanceTxResult.error(
          status: 'unknown-state',
          message: 'Unable to determine attendance action.',
        );
      },
    );

    // ─── POST-TRANSACTION: side-effects & return result ──────────────────
    // If the transaction returned an error, surface it immediately.
    if (txResult.isError) {
      return AttendanceSubmissionResult(
        success: false,
        status: txResult.status,
        message: txResult.message,
        action: txResult.action ?? AttendanceSubmissionAction.none,
        earlyCheckoutMinutes: txResult.earlyCheckoutMinutes,
      );
    }

    // ── TEMP_EXIT side-effects ───────────────────────────────────────────
    if (txResult.type == _TxAction.tempExit) {
      // Update permission request with exit time
      if (txResult.permissionId != null) {
        await _db
            .collection('permission_requests')
            .doc(txResult.permissionId)
            .update({
          'exitTime': Timestamp.fromDate(now),
        });
      }

      await _logService.logEvent(
        staffId: canonicalEmployeeId,
        staffName: canonicalEmployeeName,
        eventType: AttendanceEventType.tempExit,
        qrValidated: true,
        geofenceValidated: !isWfh,
        permissionId: txResult.permissionId,
        latitude: userLat,
        longitude: userLng,
      );

      await _createAttendanceAlert(
        employeeId: canonicalEmployeeId,
        employeeName: canonicalEmployeeName,
        department: canonicalDepartment,
        managerName: managerName,
        status: 'temp-exit',
        lateMinutes: 0,
        policyAction: 'permission_temp_exit',
        message:
            '$canonicalEmployeeName has marked a temporary exit under an approved permission request. Expected return: ${_formatTime(txResult.permissionReturnTime)}.',
      );

      unawaited(_sendAttendancePushNotification(
        employeeId: canonicalEmployeeId,
        employeeName: canonicalEmployeeName,
        managerName: managerName,
        action: 'temporary exit',
        detail: _formatTime(txResult.permissionReturnTime),
      ));

      return AttendanceSubmissionResult(
        success: true,
        status: txResult.status,
        message: 'Your temporary exit has been registered successfully.',
        action: AttendanceSubmissionAction.tempExit,
      );
    }

    // ── FINAL_CHECKOUT side-effects ──────────────────────────────────────
    if (txResult.type == _TxAction.finalCheckout) {
      final isEarlyCheckout = txResult.isEarlyCheckout;
      final earlyCheckoutMinutes = txResult.earlyCheckoutMinutes;
      final pendingStatus = txResult.pendingStatus ?? 'none';
      final pendingMinutes = txResult.pendingMinutes;

      if (isEarlyCheckout) {
        await _createAttendanceAlert(
          employeeId: canonicalEmployeeId,
          employeeName: canonicalEmployeeName,
          department: canonicalDepartment,
          managerName: managerName,
          status: 'early-checkout',
          lateMinutes: earlyCheckoutMinutes,
          policyAction: 'early_checkout',
          message:
              '$canonicalEmployeeName checked out ${_formatDuration(Duration(minutes: earlyCheckoutMinutes))} before check-out start time (${timeConfig.checkOutStart}).',
        );
      }

      if (pendingStatus != 'none') {
        await _createAttendanceAlert(
          employeeId: canonicalEmployeeId,
          employeeName: canonicalEmployeeName,
          department: canonicalDepartment,
          managerName: managerName,
          status: 'pending-hours',
          lateMinutes: lateMinutes,
          policyAction: pendingStatus,
          message:
              '$canonicalEmployeeName has ${_formatDuration(Duration(minutes: pendingMinutes))} pending hours. '
              '${_pendingAbsenceLabel(pendingMinutes)} marked from late check-in, early check-out, and permission hours.',
        );
      }

      await _logService.logEvent(
        staffId: canonicalEmployeeId,
        staffName: canonicalEmployeeName,
        eventType: AttendanceEventType.finalCheckout,
        qrValidated: true,
        geofenceValidated: !isWfh,
        permissionMinutes: txResult.permissionPendingMinutes,
        pendingMinutes: pendingMinutes,
        pendingAbsenceStatus: pendingStatus,
        latitude: userLat,
        longitude: userLng,
      );

      unawaited(_sendAttendancePushNotification(
        employeeId: canonicalEmployeeId,
        employeeName: canonicalEmployeeName,
        managerName: managerName,
        action: isEarlyCheckout ? 'early check-out' : 'check-out',
        detail: _formatTime(now),
        notifyAdmin: true,
        notifyManager: true,
        notifyEmployee: isManagerAttendance && isEarlyCheckout,
      ));

      return AttendanceSubmissionResult(
        success: true,
        status: txResult.status,
        message:
            'Check-out completed successfully. Your attendance record has been updated.',
        action: isEarlyCheckout
            ? AttendanceSubmissionAction.earlyCheckOut
            : AttendanceSubmissionAction.checkOut,
        earlyCheckoutMinutes: earlyCheckoutMinutes,
      );
    }

    // ── RE_ENTRY side-effects ────────────────────────────────────────────
    if (txResult.type == _TxAction.reEntry) {
      final delayMinutes = txResult.delayMinutes;

      // Update the permission request
      if (txResult.permissionId != null) {
        await _db
            .collection('permission_requests')
            .doc(txResult.permissionId)
            .update({
          'actualReturnTime': Timestamp.fromDate(now),
          'returnedToOffice': true,
          'reEntryDelayMinutes': delayMinutes,
        });
      }

      await _logService.logEvent(
        staffId: canonicalEmployeeId,
        staffName: canonicalEmployeeName,
        eventType: AttendanceEventType.reEntry,
        qrValidated: true,
        geofenceValidated: !isWfh,
        permissionMinutes: txResult.permissionPendingMinutes,
        pendingMinutes: txResult.pendingMinutes,
        pendingAbsenceStatus: txResult.pendingStatus ?? 'none',
        latitude: userLat,
        longitude: userLng,
      );

      await _createAttendanceAlert(
        employeeId: canonicalEmployeeId,
        employeeName: canonicalEmployeeName,
        department: canonicalDepartment,
        managerName: managerName,
        status: delayMinutes > 0 ? 're-entry-delay' : 're-entry',
        lateMinutes: delayMinutes,
        policyAction:
            delayMinutes > 0 ? 'permission_reentry_late' : 'permission_reentry',
        message: delayMinutes > 0
            ? '$canonicalEmployeeName returned $delayMinutes minutes after the approved permission return time. Please review the permission record.'
            : '$canonicalEmployeeName has re-entered within the approved permission time.',
      );

      unawaited(_sendAttendancePushNotification(
        employeeId: canonicalEmployeeId,
        employeeName: canonicalEmployeeName,
        managerName: managerName,
        action: delayMinutes > 0 ? 'delayed re-entry' : 're-entry',
        detail: delayMinutes > 0
            ? '$delayMinutes minutes after approved return time'
            : 'within approved permission time',
        notifyAdmin: true,
        notifyEmployee: delayMinutes > 0,
      ));

      return AttendanceSubmissionResult(
        success: true,
        status: txResult.status,
        message: delayMinutes > 0
            ? 'Re-entry recorded, but you are $delayMinutes minutes late from the approved permission time.'
            : 'Welcome Back, Your re-entry has been recorded successfully.',
        action: AttendanceSubmissionAction.reEntry,
      );
    }

    // Fallback (should never reach here)
    return AttendanceSubmissionResult(
      success: false,
      status: 'unknown-state',
      message: 'Unable to determine attendance action.',
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    final period = ist.hour >= 12 ? 'PM' : 'AM';
    final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:'
        '${ist.minute.toString().padLeft(2, '0')} $period';
  }

  // ─── Unauthorized Exit Detection ──────────────────────────────────────
  Future<void> markUnauthorizedExit({
    required String employeeId,
    required String employeeName,
    required String department,
    required double userLat,
    required double userLng,
  }) async {
    final todayKey = _dateKey(DateTime.now());
    final snap = await _db
        .collection('attendance')
        .where('employeeId', isEqualTo: employeeId)
        .where('dateKey', isEqualTo: todayKey)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return;
    final doc = snap.docs.first;
    final data = doc.data();
    final currentState = data['currentState'] ?? 'NONE';

    // Only mark unauthorized if currently CHECK_IN or RE_ENTRY
    if (currentState == AttendanceState.checkIn.name ||
        currentState == AttendanceState.reEntry.name) {
      // Check if they have an approved permission (they shouldn't if this is called)
      final activePermission =
          await _permissionService.getActiveApprovedPermission(employeeId);
      if (activePermission != null) return; // False positive

      await doc.reference.update({
        'currentState': AttendanceState.unauthorizedExit.name,
        'unauthorizedExitTime': FieldValue.serverTimestamp(),
        'policyAction': 'unauthorized_exit_penalty',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _logService.logEvent(
        staffId: employeeId,
        staffName: employeeName,
        eventType: AttendanceEventType.unauthorizedExit,
        geofenceValidated: true,
        latitude: userLat,
        longitude: userLng,
      );

      final staffData = await _db
          .collection('staff')
          .where('employeeId', isEqualTo: employeeId)
          .limit(1)
          .get();
      final managerName = staffData.docs.isNotEmpty
          ? staffData.docs.first.data()['reportsTo']
          : null;

      await _createAttendanceAlert(
        employeeId: employeeId,
        employeeName: employeeName,
        department: department,
        managerName: managerName,
        status: 'unauthorized-exit',
        lateMinutes: 0,
        policyAction: 'penalty',
        message:
            'Unauthorized Exit Detected: $employeeName left the office geofence without approved permission.',
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────
  double _deg2rad(double deg) => deg * pi / 180;

  String _formatDuration(Duration duration) {
    final totalMinutes =
        duration.inMinutes + (duration.inSeconds % 60 == 0 ? 0 : 1);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }

  String _formatWorkingHours(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final h = safe.inHours;
    final m = safe.inMinutes.remainder(60);
    if (h == 0 && m == 0) return '0 hrs';
    if (m == 0) return '$h hrs';
    final total = h + m / 60.0;
    return '${total.toStringAsFixed(1)} hrs';
  }

  Duration _effectiveWorkingDuration({
    required DateTime checkIn,
    required DateTime checkOut,
    required _AttendanceTimeConfig timeConfig,
  }) {
    final effectiveCheckIn = checkIn.isAfter(timeConfig.checkInEndTime)
        ? checkIn
        : timeConfig.checkInEndTime;
    final effectiveCheckOut = checkOut.isBefore(timeConfig.checkOutEndTime)
        ? checkOut
        : timeConfig.checkOutEndTime;
    final duration = effectiveCheckOut.difference(effectiveCheckIn);
    return duration.isNegative ? Duration.zero : duration;
  }

  /// Parse time string like "08:30 AM" or "5:45 PM" to TimeOfDay values
  Future<_AttendanceTimeConfig> _getAttendanceTimeConfig(
    DateTime baseDate,
  ) async {
    try {
      final doc = await _db.collection('geo_config').doc('default').get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final checkInStartStr = data['checkInStart'] as String? ?? '08:30 AM';
        final checkInEndStr = data['checkInEnd'] as String? ?? '10:30 AM';
        final checkOutStartStr = data['checkOutStart'] as String? ?? '05:00 PM';
        final checkOutEndStr = data['checkOutEnd'] as String? ?? '07:30 PM';
        return _AttendanceTimeConfig(
          checkInStart: checkInStartStr,
          checkInEnd: checkInEndStr,
          checkOutStart: checkOutStartStr,
          checkOutEnd: checkOutEndStr,
          checkInStartTime: _dateTimeForTimeString(baseDate, checkInStartStr),
          checkInEndTime: _dateTimeForTimeString(baseDate, checkInEndStr),
          checkOutStartTime: _dateTimeForTimeString(baseDate, checkOutStartStr),
          checkOutEndTime: _dateTimeForTimeString(baseDate, checkOutEndStr),
        );
      }
    } catch (e) {
      // Fallback to default if Firestore fetch fails
    }
    return _AttendanceTimeConfig(
      checkInStart: '08:30 AM',
      checkInEnd: '10:30 AM',
      checkOutStart: '05:00 PM',
      checkOutEnd: '07:30 PM',
      checkInStartTime:
          DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 30),
      checkInEndTime:
          DateTime(baseDate.year, baseDate.month, baseDate.day, 10, 30),
      checkOutStartTime:
          DateTime(baseDate.year, baseDate.month, baseDate.day, 17),
      checkOutEndTime:
          DateTime(baseDate.year, baseDate.month, baseDate.day, 19, 30),
    );
  }

  DateTime _dateTimeForTimeString(DateTime baseDate, String timeStr) {
    final time = _parseTimeString(timeStr);
    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      time['hour'] as int,
      time['minute'] as int,
    );
  }

  /// Parse "HH:MM AM/PM" format to {hour, minute}
  Map<String, int> _parseTimeString(String timeStr) {
    try {
      final isPM = timeStr.contains('PM') || timeStr.contains('pm');
      final cleanStr = timeStr.replaceAll(RegExp(r'[APap][Mm]'), '').trim();
      final parts = cleanStr.split(':');
      if (parts.length == 2) {
        var hour = int.parse(parts[0].trim());
        final minute = int.parse(parts[1].trim());
        if (isPM && hour != 12) hour += 12;
        if (!isPM && hour == 12) hour = 0;
        return {'hour': hour, 'minute': minute};
      }
    } catch (e) {
      // Fall through to default
    }
    return {'hour': 10, 'minute': 30}; // Default: 10:30 AM
  }

  int _lateMinutesWithThreshold(DateTime now, DateTime threshold) {
    if (!now.isAfter(threshold)) return 0;
    return now.difference(threshold).inMinutes;
  }

  int _pendingMinutesAfterStart(DateTime now, DateTime officeStart) {
    if (!now.isAfter(officeStart)) return 0;
    return now.difference(officeStart).inMinutes;
  }

  int _earlyCheckoutMinutesBeforeStart(
      DateTime checkout, DateTime officeStart) {
    if (!checkout.isBefore(officeStart)) return 0;
    return officeStart.difference(checkout).inMinutes;
  }

  int _combinedPendingMinutes({
    required int latePendingMinutes,
    required int earlyCheckoutPendingMinutes,
    required int permissionPendingMinutes,
  }) {
    final total = _safeMinutes(latePendingMinutes) +
        _safeMinutes(earlyCheckoutPendingMinutes) +
        _safeMinutes(permissionPendingMinutes);
    return total > 480 ? 480 : total;
  }

  int _safeMinutes(int value) => value > 0 ? value : 0;

  String _policyActionForPendingStatus({
    required String? existingAction,
    required String pendingStatus,
  }) {
    if (pendingStatus == 'full_absent') return 'full_day_absent';
    if (pendingStatus == 'half_absent') return 'half_day_absent';
    final action = existingAction?.trim();
    return action == null || action.isEmpty ? 'none' : action;
  }

  Future<int> _permissionPendingMinutesForDay({
    required String employeeId,
    required DateTime date,
  }) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final snap = await _db
        .collection('permission_requests')
        .where('employeeId', isEqualTo: employeeId)
        .get();

    var total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if ((data['status'] as String? ?? '').toLowerCase() != 'approved') {
        continue;
      }

      final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
      final permissionDate = (data['date'] as Timestamp?)?.toDate();
      final start = (data['exitTime'] as Timestamp?)?.toDate() ??
          (data['fromTime'] as Timestamp?)?.toDate();
      final end = (data['actualReturnTime'] as Timestamp?)?.toDate() ??
          (data['returnTime'] as Timestamp?)?.toDate() ??
          (data['approvedReturnTime'] as Timestamp?)?.toDate() ??
          (data['toTime'] as Timestamp?)?.toDate();

      final belongsToDay = _sameDay(permissionDate, date) ||
          _sameDay(requestedAt, date) ||
          _intervalOverlapsDay(start, end, dayStart, dayEnd);
      if (!belongsToDay ||
          start == null ||
          end == null ||
          !end.isAfter(start)) {
        continue;
      }

      final clampedStart = start.isBefore(dayStart) ? dayStart : start;
      final clampedEnd = end.isAfter(dayEnd) ? dayEnd : end;
      if (clampedEnd.isAfter(clampedStart)) {
        total += clampedEnd.difference(clampedStart).inMinutes;
      }
    }

    return total > 480 ? 480 : total;
  }

  bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _intervalOverlapsDay(
    DateTime? start,
    DateTime? end,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    if (start == null || end == null || !end.isAfter(start)) return false;
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }

  String _pendingAbsenceStatus(int pendingMinutes) {
    if (pendingMinutes >= _fullDayAbsentMinutes) return 'full_absent';
    if (pendingMinutes >= _halfDayAbsentMinutes) return 'half_absent';
    return 'none';
  }

  String _pendingAbsenceLabel(int pendingMinutes) {
    if (pendingMinutes >= _fullDayAbsentMinutes) return 'Fully Absent';
    if (pendingMinutes >= _halfDayAbsentMinutes) return 'Half Absent';
    return 'No absence';
  }

  String _arrivalBand(int lateMinutes, {required bool isWfh}) {
    if (isWfh) return 'blue';
    if (lateMinutes <= 0) return 'green';
    if (lateMinutes <= 15) return 'orange';
    return 'red';
  }

  Future<_AttendancePolicy> _policyForLateArrival({
    required String employeeId,
    required DateTime now,
    required int lateMinutes,
    required bool isWfh,
  }) async {
    if (isWfh || lateMinutes <= 0) {
      return const _AttendancePolicy(action: 'none', label: '');
    }

    if (lateMinutes >= 120) {
      return const _AttendancePolicy(
        action: 'full_day_absent',
        label: '2+ hours late -> 1 day absent',
      );
    }

    if (lateMinutes >= 60) {
      final startOfMonth = DateTime(now.year, now.month, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);

      // Keep the staff-scoped late policy query index-free. Firestore requires
      // a composite index for employeeId + date range, so fetch this employee's
      // attendance records and filter the current month locally.
      final monthLateSnap = await _db
          .collection('attendance')
          .where('employeeId', isEqualTo: employeeId)
          .get();

      final priorLateDays = monthLateSnap.docs.where((doc) {
        final data = doc.data();
        final recordDate = (data['date'] as Timestamp?)?.toDate();
        if (recordDate == null ||
            recordDate.isBefore(startOfMonth) ||
            !recordDate.isBefore(nextMonth)) {
          return false;
        }
        final existingLateMinutes = (data['lateMinutes'] as num?)?.toInt() ?? 0;
        return existingLateMinutes >= 60;
      }).length;

      if (priorLateDays + 1 >= 4) {
        return const _AttendancePolicy(
          action: 'half_day_absent',
          label: '4th 1-hour late -> half day absent',
        );
      }
    }

    return const _AttendancePolicy(action: 'none', label: '');
  }

  Future<void> _createAttendanceAlert({
    required String employeeId,
    required String employeeName,
    required String department,
    required String? managerName,
    required String status,
    required int lateMinutes,
    required String policyAction,
    String? message,
  }) async {
    String alertMessage = message ?? '';
    if (alertMessage.isEmpty) {
      alertMessage = status == 'late'
          ? 'Late clock-in alert for your review.'
          : 'Needs manager attention: absent/penalty applied.';
    }

    await _db.collection('attendance_alerts').add({
      'employeeId': employeeId,
      'employeeName': employeeName,
      'department': department,
      'managerName': managerName,
      'status': status,
      'lateMinutes': lateMinutes,
      'policyAction': policyAction,
      'dateKey': _dateKey(DateTime.now()),
      'date': Timestamp.fromDate(DateTime.now()),
      'createdAt': FieldValue.serverTimestamp(),
      'message': alertMessage,
    });

    const notificationStatuses = {
      'early-checkout',
      'pending-hours',
      'temp-exit',
      're-entry',
      're-entry-delay',
      'unauthorized-exit',
    };

    if (notificationStatuses.contains(status)) {
      final recipients = _attendanceAlertRecipients(
        status: status,
        employeeId: employeeId,
        managerName: managerName,
      );
      final title = _attendanceAlertTitle(status);

      for (final recipient in recipients) {
        await _db.collection('notifications').add({
          'recipient': recipient,
          'type': 'Attendance Alert',
          'title': title,
          'content': alertMessage,
          'status': 'Sent',
          'suppressFirestorePush': true,
          'allowFirestorePush': false,
          'timestamp': FieldValue.serverTimestamp(),
          'employeeId': employeeId,
          'employeeName': employeeName,
          'department': department,
          'managerName': managerName,
          'alertStatus': status,
          'policyAction': policyAction,
        });
      }
    }
  }

  Set<String> _attendanceAlertRecipients({
    required String status,
    required String employeeId,
    required String? managerName,
  }) {
    final manager = managerName?.trim();

    switch (status) {
      case 'temp-exit':
      case 're-entry':
        return {
          'Admin',
          if (manager != null && manager.isNotEmpty) manager,
        };
      case 're-entry-delay':
        return {
          'Admin',
          employeeId,
          if (manager != null && manager.isNotEmpty) manager,
        };
      default:
        return {
          'Admin',
          employeeId,
          if (manager != null && manager.isNotEmpty) manager,
        };
    }
  }

  String _attendanceAlertTitle(String status) {
    switch (status) {
      case 'temp-exit':
        return 'Temporary Exit Approved';
      case 're-entry':
        return 'Re-Entry Verified';
      case 're-entry-delay':
        return 'Attendance Alert';
      case 'early-checkout':
        return 'Attendance Alert';
      case 'pending-hours':
        return 'Attendance Alert';
      case 'unauthorized-exit':
        return 'Attendance Alert';
      default:
        return 'Attendance Alert';
    }
  }

  String _generateSecureToken() {
    final rng = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _normalizeIdentity(String value) {
    return value.trim().toLowerCase();
  }

  void _addAlias(Set<String> aliases, String? value) {
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    aliases.add(_normalizeIdentity(trimmed));
    aliases.add(_normalizeIdentity(trimmed.replaceAll(' ', '')));

    if (trimmed.contains('@')) {
      aliases.add(_normalizeIdentity(trimmed.split('@').first));
    }
  }

  Stream<List<String>> _teamEmployeeIdsStream(String managerIdentifier) {
    debugPrint(
        '🔍 DEBUG: _teamEmployeeIdsStream - Finding team for manager: "$managerIdentifier"');

    return _db
        .collection('staff')
        .snapshots()
        .asyncMap((allStaffSnapshot) async {
      final managerAliases = <String>{};
      _addAlias(managerAliases, managerIdentifier);

      String? managerEmployeeId;
      String? managerResolvedName;

      final managerSnapshot = await _db.collection('managers').get();

      bool matchesManagerIdentifier(String value) {
        final normalized = _normalizeIdentity(value);
        final compact = _normalizeIdentity(value.replaceAll(' ', ''));
        return normalized.isNotEmpty &&
            (managerAliases.contains(normalized) ||
                managerAliases.contains(compact));
      }

      for (final doc in managerSnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        final email = (data['email'] as String? ?? '').trim();
        final employeeId = (data['employeeId'] as String? ?? '').trim();

        if (matchesManagerIdentifier(doc.id) ||
            matchesManagerIdentifier(name) ||
            matchesManagerIdentifier(email) ||
            matchesManagerIdentifier(employeeId)) {
          _addAlias(managerAliases, doc.id);
          _addAlias(managerAliases, name);
          _addAlias(managerAliases, email);
          _addAlias(managerAliases, employeeId);
          managerEmployeeId ??= employeeId.isNotEmpty ? employeeId : null;
          managerResolvedName ??= name.isNotEmpty ? name : email;
        }
      }

      for (final doc in allStaffSnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        final email = (data['email'] as String? ?? '').trim();
        final empId = (data['employeeId'] as String? ?? '').trim();

        if (matchesManagerIdentifier(doc.id) ||
            matchesManagerIdentifier(name) ||
            matchesManagerIdentifier(email) ||
            matchesManagerIdentifier(empId)) {
          final managerStaff = Staff.fromFirestore(doc);
          _addAlias(managerAliases, doc.id);
          _addAlias(managerAliases, managerStaff.name);
          _addAlias(managerAliases, managerStaff.email);
          _addAlias(managerAliases, managerStaff.employeeId);
          managerEmployeeId ??= managerStaff.employeeId.trim().isNotEmpty
              ? managerStaff.employeeId.trim()
              : null;
          managerResolvedName ??=
              managerStaff.name.trim().isNotEmpty ? managerStaff.name : email;
        }
      }

      if (managerAliases.isEmpty ||
          managerAliases.every((alias) => alias.isEmpty)) {
        debugPrint(
            '❌ DEBUG: Manager not found with identifier: "$managerIdentifier"');
        debugPrint('📋 DEBUG: Available manager emails for matching:');
        for (final doc in managerSnapshot.docs.take(5)) {
          final data = doc.data();
          debugPrint(
              '   - ${data['name'] ?? 'Unknown'} (${data['email'] ?? 'No email'})');
        }
        debugPrint('📋 DEBUG: Available staff for matching:');
        for (final doc in allStaffSnapshot.docs.take(5)) {
          final data = doc.data();
          debugPrint(
              '   - ${data['name']?.toString().trim()} (${data['employeeId']?.toString().trim()})');
        }
        return <String>[];
      }

      debugPrint(
          '✅ DEBUG: Found manager aliases for ${managerResolvedName ?? managerIdentifier}');

      // Now find all staff who report to this manager by employee ID, name, email, or email local-part.
      final teamIds = allStaffSnapshot.docs
          .where((doc) {
            final data = doc.data();
            final reportsTo = (data['reportsTo'] as String? ?? '').trim();
            final staffName = (data['name'] as String? ?? '').trim();
            final normalizedReportsTo = _normalizeIdentity(reportsTo);
            final compactReportsTo =
                _normalizeIdentity(reportsTo.replaceAll(' ', ''));

            final staffEmpId = (data['employeeId'] as String? ?? '').trim();
            final staffEmail = (data['email'] as String? ?? '').trim();
            if ((managerEmployeeId != null &&
                    staffEmpId == managerEmployeeId) ||
                managerAliases.contains(_normalizeIdentity(staffEmail))) {
              return false;
            }

            final matches =
                (managerEmployeeId != null && reportsTo == managerEmployeeId) ||
                    managerAliases.contains(normalizedReportsTo) ||
                    managerAliases.contains(compactReportsTo);

            if (matches) {
              debugPrint(
                  '   ✓ Team member: $staffName (ID: $staffEmpId) reports to ${managerResolvedName ?? managerIdentifier}');
            }
            return matches;
          })
          .map((doc) {
            final data = doc.data();
            final empId = (data['employeeId'] as String? ?? '').trim();
            return empId;
          })
          .where((id) => id.isNotEmpty)
          .toSet();
      final sortedTeamIds = teamIds.toList()..sort();

      debugPrint('📊 DEBUG: Team has ${sortedTeamIds.length} employees');
      if (sortedTeamIds.isEmpty) {
        debugPrint(
            '⚠️  WARNING: Manager has no team members. Check reportsTo field in Firestore.');
      }
      return sortedTeamIds;
    }).asBroadcastStream();
  }

  /// Centralized push notification dispatcher for attendance actions (check-in, check-out, exits, re-entries).
  /// Respects custom routing rules:
  /// - If the employee is a manager: Sends a notification to all Admin phones.
  /// - If the employee is a staff: Sends a notification to all Admin phones AND the specific manager's phone.
  Future<void> _sendAttendancePushNotification({
    required String employeeId,
    required String employeeName,
    String? managerName,
    required String action,
    required String detail,
    bool notifyAdmin = true,
    bool notifyManager = true,
    bool notifyEmployee = false,
  }) async {
    try {
      // 1. Determine if this user is a manager
      final managerSnap = await _db
          .collection('managers')
          .where('employeeId', isEqualTo: employeeId)
          .limit(1)
          .get();
      final userSnap = await _db.collection('users').doc(employeeId).get();
      final isManager =
          managerSnap.docs.isNotEmpty || userSnap.data()?['role'] == 'manager';

      final title = _attendancePushTitle(
        isManager: isManager,
        action: action,
      );
      final body = _attendancePushBody(
        employeeName: employeeName,
        action: action,
        detail: detail,
      );
      final recipients = <String>{
        if (notifyAdmin) 'Admin',
        if (notifyManager &&
            !isManager &&
            managerName != null &&
            managerName.trim().isNotEmpty)
          managerName.trim(),
        if (notifyEmployee) employeeId,
      };
      final data = {
        'employeeId': employeeId,
        'employeeName': employeeName,
        'managerName': managerName,
        'attendanceAction': action,
        'attendanceDetail': detail,
      };

      for (final recipient in recipients) {
        // Route physical attendance pushes through the actively deployed
        // endpoint; the Firestore push trigger may still carry legacy text.
        await NotificationService().sendNotificationToUser(
          identifier: recipient,
          title: title,
          body: body,
          data: data,
        );
      }
    } catch (e) {
      debugPrint('Error sending attendance push notification: $e');
    }
  }

  String _attendancePushTitle({
    required bool isManager,
    required String action,
  }) {
    switch (action) {
      case 'temporary exit':
        return 'Attendance Update';
      case 're-entry':
        return 'Attendance Update';
      case 'delayed re-entry':
        return 'Attendance Alert';
      case 'early check-out':
        return 'Early Check-out Recorded';
      case 'check-in':
        return 'Secure Check-In';
      case 'late check-in':
        return 'Late Check-In Recorded';
      case 'check-out':
        return 'Work Session Closed';
      default:
        return 'Attendance Alert';
    }
  }

  String _attendancePushBody({
    required String employeeName,
    required String action,
    required String detail,
  }) {
    switch (action) {
      case 'temporary exit':
        return '$employeeName temporary exit recorded. Permission active until $detail.';
      case 're-entry':
        return '$employeeName re-entry recorded successfully.';
      case 'delayed re-entry':
        return '$employeeName delayed re-entry recorded: $detail.';
      case 'early check-out':
        return 'Staff member $employeeName has checked out early. Status: present.';
      case 'check-in':
        return '📍 $employeeName checked in successfully.';
      case 'late check-in':
        return '⚠️ $employeeName checked in late. Late by $detail minutes.';
      case 'check-out':
        return '👋 $employeeName checked out successfully';
      default:
        return '$employeeName attendance update: $action.';
    }
  }

  static final Map<String, bool> _leaveCache = {};

  static void clearLeaveCache() {
    _leaveCache.clear();
  }

  Future<bool> isEmployeeOnApprovedLeave(String empId, DateTime date) async {
    if (empId.isEmpty) return false;
    final targetDate = DateTime(date.year, date.month, date.day);
    final cacheKey = "${empId.trim()}-${targetDate.millisecondsSinceEpoch}";
    if (_leaveCache.containsKey(cacheKey)) {
      return _leaveCache[cacheKey]!;
    }
    try {
      // Query by userId
      final snapByUserId = await _db
          .collection('leave_requests')
          .where('userId', isEqualTo: empId.trim())
          .where('status', isEqualTo: 'approved')
          .get();

      for (final doc in snapByUserId.docs) {
        final data = doc.data();
        final startTs = data['startDate'];
        final endTs = data['endDate'];
        if (startTs == null || endTs == null) continue;
        final start = (startTs as Timestamp).toDate();
        final end = (endTs as Timestamp).toDate();
        final type = data['type']?.toString().toLowerCase() ?? '';
        if (type.contains('half')) continue;
        final startDay = DateTime(start.year, start.month, start.day);
        final endDay = DateTime(end.year, end.month, end.day);
        if (!targetDate.isBefore(startDay) && !targetDate.isAfter(endDay)) {
          _leaveCache[cacheKey] = true;
          return true;
        }
      }

      // Query by employeeId
      final snapByEmpId = await _db
          .collection('leave_requests')
          .where('employeeId', isEqualTo: empId.trim())
          .where('status', isEqualTo: 'approved')
          .get();

      for (final doc in snapByEmpId.docs) {
        final data = doc.data();
        final startTs = data['startDate'];
        final endTs = data['endDate'];
        if (startTs == null || endTs == null) continue;
        final start = (startTs as Timestamp).toDate();
        final end = (endTs as Timestamp).toDate();
        final type = data['type']?.toString().toLowerCase() ?? '';
        if (type.contains('half')) continue;
        final startDay = DateTime(start.year, start.month, start.day);
        final endDay = DateTime(end.year, end.month, end.day);
        if (!targetDate.isBefore(startDay) && !targetDate.isAfter(endDay)) {
          _leaveCache[cacheKey] = true;
          return true;
        }
      }
    } catch (_) {}
    _leaveCache[cacheKey] = false;
    return false;
  }
}

enum AttendanceSubmissionAction {
  checkIn,
  checkOut,
  earlyCheckOut,
  checkOutBlocked,
  tempExit,
  reEntry,
  unauthorizedExit,
  none,
}

class AttendanceSubmissionResult {
  final bool success;
  final String status;
  final String message;
  final int lateMinutes;
  final String policyAction;
  final String policyLabel;
  final AttendanceSubmissionAction action;
  final int earlyCheckoutMinutes;

  AttendanceSubmissionResult({
    required this.success,
    required this.status,
    required this.message,
    this.lateMinutes = 0,
    this.policyAction = 'none',
    this.policyLabel = '',
    this.action = AttendanceSubmissionAction.none,
    this.earlyCheckoutMinutes = 0,
  });

  String get statusLabel {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'wfh':
        return 'Work from home';
      case 'leave':
        return 'Leave';
      default:
        return 'Absent';
    }
  }
}

class AttendanceAlert {
  final String id;
  final String employeeId;
  final String employeeName;
  final String department;
  final String status;
  final int lateMinutes;
  final String message;
  final DateTime createdAt;

  AttendanceAlert({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.department,
    required this.status,
    required this.lateMinutes,
    required this.message,
    required this.createdAt,
  });

  factory AttendanceAlert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AttendanceAlert(
      id: doc.id,
      employeeId: data['employeeId'] ?? '',
      employeeName: data['employeeName'] ?? '',
      department: data['department'] ?? '',
      status: data['status'] ?? '',
      lateMinutes: (data['lateMinutes'] as num?)?.toInt() ?? 0,
      message: data['message'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class _AttendancePolicy {
  final String action;
  final String label;

  const _AttendancePolicy({
    required this.action,
    required this.label,
  });
}

class _AttendanceTimeConfig {
  final String checkInStart;
  final String checkInEnd;
  final String checkOutStart;
  final String checkOutEnd;
  final DateTime checkInStartTime;
  final DateTime checkInEndTime;
  final DateTime checkOutStartTime;
  final DateTime checkOutEndTime;

  const _AttendanceTimeConfig({
    required this.checkInStart,
    required this.checkInEnd,
    required this.checkOutStart,
    required this.checkOutEnd,
    required this.checkInStartTime,
    required this.checkInEndTime,
    required this.checkOutStartTime,
    required this.checkOutEndTime,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'checkInStart': checkInStart,
      'checkInEnd': checkInEnd,
      'checkOutStart': checkOutStart,
      'checkOutEnd': checkOutEnd,
    };
  }
}

class _LiveOfficeTimes {
  final String officeStartTime;
  final String officeCheckOutStartTime;
  final String officeEndTime;

  const _LiveOfficeTimes({
    required this.officeStartTime,
    required this.officeCheckOutStartTime,
    required this.officeEndTime,
  });
}

class _ApprovedLeaveWindow {
  final Set<String> identifiers;
  final Set<String> names;
  final String startKey;
  final String endKey;
  final bool isHalfDay;
  final String label;

  const _ApprovedLeaveWindow({
    required this.identifiers,
    required this.names,
    required this.startKey,
    required this.endKey,
    required this.isHalfDay,
    required this.label,
  });
}

class _DirectoryProfile {
  final Set<String> identifiers;
  final Set<String> names;
  final String designation;

  const _DirectoryProfile({
    required this.identifiers,
    required this.names,
    required this.designation,
  });
}

// ─── Transaction result types for markAttendance ─────────────────────────────

enum _TxAction { error, tempExit, finalCheckout, reEntry }

class _MarkAttendanceTxResult {
  final _TxAction type;
  final String status;
  final String message;
  final AttendanceSubmissionAction? action;
  final int earlyCheckoutMinutes;
  final bool isEarlyCheckout;
  final int pendingMinutes;
  final String? pendingStatus;
  final int storedLatePending;
  final int permissionPendingMinutes;
  final String? permissionId;
  final DateTime? permissionReturnTime;
  final int delayMinutes;

  const _MarkAttendanceTxResult._({
    required this.type,
    required this.status,
    required this.message,
    this.action,
    this.earlyCheckoutMinutes = 0,
    this.isEarlyCheckout = false,
    this.pendingMinutes = 0,
    this.pendingStatus,
    this.storedLatePending = 0,
    this.permissionPendingMinutes = 0,
    this.permissionId,
    this.permissionReturnTime,
    this.delayMinutes = 0,
  });

  bool get isError => type == _TxAction.error;

  factory _MarkAttendanceTxResult.error({
    required String status,
    required String message,
    AttendanceSubmissionAction? action,
    int earlyCheckoutMinutes = 0,
  }) =>
      _MarkAttendanceTxResult._(
        type: _TxAction.error,
        status: status,
        message: message,
        action: action,
        earlyCheckoutMinutes: earlyCheckoutMinutes,
      );

  factory _MarkAttendanceTxResult.tempExit({
    required String docStatus,
    required String permissionId,
    DateTime? permissionReturnTime,
  }) =>
      _MarkAttendanceTxResult._(
        type: _TxAction.tempExit,
        status: docStatus,
        message: '',
        permissionId: permissionId,
        permissionReturnTime: permissionReturnTime,
      );

  factory _MarkAttendanceTxResult.finalCheckout({
    required String updatedStatus,
    required bool isEarlyCheckout,
    required int earlyCheckoutMinutes,
    required int pendingMinutes,
    required String pendingStatus,
    required int storedLatePending,
    required int permissionPendingMinutes,
  }) =>
      _MarkAttendanceTxResult._(
        type: _TxAction.finalCheckout,
        status: updatedStatus,
        message: '',
        isEarlyCheckout: isEarlyCheckout,
        earlyCheckoutMinutes: earlyCheckoutMinutes,
        pendingMinutes: pendingMinutes,
        pendingStatus: pendingStatus,
        storedLatePending: storedLatePending,
        permissionPendingMinutes: permissionPendingMinutes,
      );

  factory _MarkAttendanceTxResult.reEntry({
    required String docStatus,
    String? permissionId,
    required int delayMinutes,
    required int pendingMinutes,
    required String pendingStatus,
    required int permissionPendingMinutes,
  }) =>
      _MarkAttendanceTxResult._(
        type: _TxAction.reEntry,
        status: docStatus,
        message: '',
        permissionId: permissionId,
        delayMinutes: delayMinutes,
        pendingMinutes: pendingMinutes,
        pendingStatus: pendingStatus,
        permissionPendingMinutes: permissionPendingMinutes,
      );
}
