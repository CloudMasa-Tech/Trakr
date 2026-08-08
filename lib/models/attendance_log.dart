import 'package:cloud_firestore/cloud_firestore.dart';

enum AttendanceEventType {
  checkIn('CHECK_IN'),
  tempExit('TEMP_EXIT'),
  reEntry('RE_ENTRY'),
  finalCheckout('FINAL_CHECKOUT'),
  unauthorizedExit('UNAUTHORIZED_EXIT');

  final String firestoreValue;
  const AttendanceEventType(this.firestoreValue);
}

class AttendanceLog {
  final String id;
  final String staffId;
  final String staffName;
  final AttendanceEventType eventType;
  final DateTime timestamp;
  final bool qrValidated;
  final bool geofenceValidated;
  final String? permissionId;
  final bool? managerApproved;
  final String? deviceId;
  final int permissionMinutes;
  final int pendingMinutes;
  final String pendingAbsenceStatus;
  final double? latitude;
  final double? longitude;

  AttendanceLog({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.eventType,
    required this.timestamp,
    this.qrValidated = false,
    this.geofenceValidated = false,
    this.permissionId,
    this.managerApproved,
    this.deviceId,
    this.permissionMinutes = 0,
    this.pendingMinutes = 0,
    this.pendingAbsenceStatus = 'none',
    this.latitude,
    this.longitude,
  });

  factory AttendanceLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AttendanceLog(
      id: doc.id,
      staffId: data['staffId'] ?? '',
      staffName: data['staffName'] ?? '',
      eventType: AttendanceEventType.values.firstWhere(
        (e) => e.firestoreValue == data['eventType'],
        orElse: () => AttendanceEventType.checkIn,
      ),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      qrValidated: data['qrValidated'] ?? false,
      geofenceValidated: data['geofenceValidated'] ?? false,
      permissionId: data['permissionId'],
      managerApproved: data['managerApproved'],
      deviceId: data['deviceId'],
      permissionMinutes: (data['permissionMinutes'] as num?)?.toInt() ?? 0,
      pendingMinutes: (data['pendingMinutes'] as num?)?.toInt() ?? 0,
      pendingAbsenceStatus: data['pendingAbsenceStatus'] as String? ?? 'none',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'staffId': staffId,
      'staffName': staffName,
      'eventType': eventType.firestoreValue,
      'timestamp': Timestamp.fromDate(timestamp),
      'qrValidated': qrValidated,
      'geofenceValidated': geofenceValidated,
      'permissionId': permissionId,
      'managerApproved': managerApproved,
      'deviceId': deviceId,
      'permissionMinutes': permissionMinutes,
      'pendingMinutes': pendingMinutes,
      'pendingAbsenceStatus': pendingAbsenceStatus,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
