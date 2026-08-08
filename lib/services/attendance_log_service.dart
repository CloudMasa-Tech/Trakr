import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/attendance_log.dart';

class AttendanceLogService {
  AttendanceLogService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _db => _context.firestore;

  Future<void> logEvent({
    required String staffId,
    required String staffName,
    required AttendanceEventType eventType,
    bool qrValidated = false,
    bool geofenceValidated = false,
    String? permissionId,
    bool? managerApproved,
    int permissionMinutes = 0,
    int pendingMinutes = 0,
    String pendingAbsenceStatus = 'none',
    double? latitude,
    double? longitude,
  }) async {
    final log = AttendanceLog(
      id: '',
      staffId: staffId,
      staffName: staffName,
      eventType: eventType,
      timestamp: DateTime.now(),
      qrValidated: qrValidated,
      geofenceValidated: geofenceValidated,
      permissionId: permissionId,
      managerApproved: managerApproved,
      permissionMinutes: permissionMinutes,
      pendingMinutes: pendingMinutes,
      pendingAbsenceStatus: pendingAbsenceStatus,
      latitude: latitude,
      longitude: longitude,
    );

    await _db.collection('attendance_logs').add(log.toMap());
  }

  Stream<List<AttendanceLog>> getLogsForStaff(String staffId) {
    return _db
        .collection('attendance_logs')
        .where('staffId', isEqualTo: staffId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => AttendanceLog.fromFirestore(doc)).toList());
  }

  Stream<List<AttendanceLog>> getTodayLogs() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return _db
        .collection('attendance_logs')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => AttendanceLog.fromFirestore(doc)).toList());
  }
}
