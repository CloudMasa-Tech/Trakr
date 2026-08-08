// lib/models/leave_request.dart

// 1. ADD THIS IMPORT
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaveRequest {
  final String id;
  final String userId;
  final String? employeeId;
  final String userName;
  final String? userPhotoUrl;
  final String? managerName;
  final String type; // Sick Leave, Annual, etc.
  final String department;
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'pending', 'approved', 'rejected'
  final bool isPaid;
  final double leaveDayCount;
  final double paidDayCount;
  final double unpaidDayCount;
  final String reason;
  final String? managerResponseReason;
  final String? rejectionReason;
  final String? respondedBy;
  final DateTime? respondedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LeaveRequest({
    required this.id,
    required this.userId,
    this.employeeId,
    required this.userName,
    this.userPhotoUrl,
    this.managerName,
    required this.type,
    required this.department,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.isPaid = false,
    this.leaveDayCount = 1,
    this.paidDayCount = 0,
    this.unpaidDayCount = 1,
    this.reason = '',
    this.managerResponseReason,
    this.rejectionReason,
    this.respondedBy,
    this.respondedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory LeaveRequest.fromFirestore(Map<String, dynamic> data, String id) {
    return LeaveRequest(
      id: id,
      userId: data['userId']?.toString() ?? '',
      employeeId: data['employeeId']?.toString(),
      userName: data['userName']?.toString() ?? 'Unknown User',
      userPhotoUrl: data['userPhotoUrl']?.toString(),
      managerName: data['managerName']?.toString(),
      type: data['type']?.toString() ?? 'General',
      department: data['department']?.toString() ?? 'Staff',
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status']?.toString() ?? 'pending',
      isPaid: data['isPaid'] ?? false,
      leaveDayCount: (data['leaveDayCount'] as num?)?.toDouble() ??
          _legacyDayCount(data['startDate'], data['endDate']),
      paidDayCount: (data['paidDayCount'] as num?)?.toDouble() ??
          ((data['isPaid'] == true)
              ? _legacyDayCount(data['startDate'], data['endDate'])
              : 0),
      unpaidDayCount: (data['unpaidDayCount'] as num?)?.toDouble() ??
          ((data['isPaid'] == true)
              ? 0
              : _legacyDayCount(data['startDate'], data['endDate'])),
      reason: data['reason']?.toString() ?? '',
      managerResponseReason: data['managerResponseReason']?.toString(),
      rejectionReason: data['rejectionReason']?.toString(),
      respondedBy: data['respondedBy']?.toString(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'employeeId': employeeId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'managerName': managerName,
      'type': type,
      'department': department,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status,
      'isPaid': isPaid,
      'leaveDayCount': leaveDayCount,
      'paidDayCount': paidDayCount,
      'unpaidDayCount': unpaidDayCount,
      'reason': reason,
      'managerResponseReason': managerResponseReason,
      'rejectionReason': rejectionReason,
      'respondedBy': respondedBy,
      'respondedAt':
          respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  bool get isHalfDay => type.toLowerCase().contains('half');

  static double _legacyDayCount(Object? startValue, Object? endValue) {
    final start = startValue is Timestamp ? startValue.toDate() : null;
    final end = endValue is Timestamp ? endValue.toDate() : start;
    if (start == null || end == null) return 1;
    return (end.difference(start).inDays + 1).toDouble();
  }
}
