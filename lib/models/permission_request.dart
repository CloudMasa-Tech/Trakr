import 'package:cloud_firestore/cloud_firestore.dart';

class PermissionRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String department;
  final String managerName;
  final String reason;
  final String status; // 'pending', 'approved', 'rejected'
  final String? permissionType;
  final bool isPaid;
  final String? managerResponse;
  final String? rejectionReason;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final DateTime? respondedAt;
  final String? respondedBy;
  final DateTime? exitTime;
  final DateTime? returnTime;
  final DateTime? approvedReturnTime;
  final DateTime? actualReturnTime;
  final bool returnedToOffice;
  final double deductionAmount;
  final DateTime? date;
  final DateTime? fromTime;
  final DateTime? toTime;

  PermissionRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.department,
    required this.managerName,
    required this.reason,
    required this.status,
    this.permissionType,
    this.isPaid = false,
    this.managerResponse,
    this.rejectionReason,
    required this.requestedAt,
    this.approvedAt,
    this.respondedAt,
    this.respondedBy,
    this.exitTime,
    this.returnTime,
    this.approvedReturnTime,
    this.actualReturnTime,
    this.returnedToOffice = false,
    this.deductionAmount = 0.0,
    this.date,
    this.fromTime,
    this.toTime,
  });

  factory PermissionRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PermissionRequest(
      id: doc.id,
      employeeId: data['employeeId'] ?? '',
      employeeName: data['employeeName'] ?? '',
      department: data['department'] ?? '',
      managerName: data['managerName'] ?? '',
      reason: data['reason'] ?? '',
      status: data['status'] ?? 'pending',
      permissionType: data['permissionType'],
      isPaid: data['isPaid'] ?? false,
      managerResponse: data['managerResponse'],
      rejectionReason: data['rejectionReason'],
      requestedAt:
          (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      respondedBy: data['respondedBy'],
      exitTime: (data['exitTime'] as Timestamp?)?.toDate(),
      returnTime: (data['returnTime'] as Timestamp?)?.toDate(),
      approvedReturnTime: (data['approvedReturnTime'] as Timestamp?)?.toDate(),
      actualReturnTime: (data['actualReturnTime'] as Timestamp?)?.toDate(),
      returnedToOffice: data['returnedToOffice'] ?? false,
      deductionAmount: (data['deductionAmount'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate(),
      fromTime: (data['fromTime'] as Timestamp?)?.toDate(),
      toTime: (data['toTime'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'department': department,
      'managerName': managerName,
      'reason': reason,
      'status': status,
      'permissionType': permissionType,
      'isPaid': isPaid,
      'managerResponse': managerResponse,
      'rejectionReason': rejectionReason,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'respondedAt':
          respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'respondedBy': respondedBy,
      'exitTime': exitTime != null ? Timestamp.fromDate(exitTime!) : null,
      'returnTime': returnTime != null ? Timestamp.fromDate(returnTime!) : null,
      'approvedReturnTime': approvedReturnTime != null
          ? Timestamp.fromDate(approvedReturnTime!)
          : null,
      'actualReturnTime': actualReturnTime != null
          ? Timestamp.fromDate(actualReturnTime!)
          : null,
      'returnedToOffice': returnedToOffice,
      'deductionAmount': deductionAmount,
      'date': date != null ? Timestamp.fromDate(date!) : null,
      'fromTime': fromTime != null ? Timestamp.fromDate(fromTime!) : null,
      'toTime': toTime != null ? Timestamp.fromDate(toTime!) : null,
    };
  }
}
