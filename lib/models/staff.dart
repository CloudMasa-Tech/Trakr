import 'package:cloud_firestore/cloud_firestore.dart';
import 'attendance_model.dart';

class Staff {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String department;
  final String position;
  final String employeeId;
  final DateTime joinDate;
  final String? photoUrl;
  final String? photoBase64;
  final String? reportsTo;
  final double? salary;
  final String? role;
  final String? password;
  final bool isActive;
  final bool hasRegistered;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Company & hierarchy fields
  final String? companyId;
  final String? designation;
  final String? reportsToUserId;
  final List<String>? permissionIds;

  // Demographic Fields
  final String? bloodGroup;
  final String? gender;
  final String? nationality;
  final DateTime? dob;
  final String? address;

  Staff({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    required this.position,
    required this.employeeId,
    required this.joinDate,
    this.photoUrl,
    this.photoBase64,
    this.reportsTo,
    this.salary,
    this.role,
    this.password,
    this.isActive = true,
    this.hasRegistered = false,
    this.createdAt,
    this.updatedAt,
    this.companyId,
    this.designation,
    this.reportsToUserId,
    this.permissionIds,
    this.bloodGroup,
    this.gender,
    this.nationality,
    this.dob,
    this.address,
  });

  factory Staff.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Staff(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      department: data['department'] ?? '',
      position: data['position'] ?? '',
      employeeId: data['employeeId'] ?? '',
      joinDate: (data['joinDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      photoUrl: data['photoUrl'],
      photoBase64: data['photoBase64'] as String?,
      reportsTo: data['reportsTo'],
      salary:
          data['salary'] != null ? (data['salary'] as num).toDouble() : null,
      role: data['role'],
      password: data['password'],
      isActive: data['isActive'] ?? true,
      hasRegistered: data['hasRegistered'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      companyId: data['companyId'] as String?,
      designation: data['designation'] as String?,
      reportsToUserId: data['reportsToUserId'] as String?,
      permissionIds: data['permissionIds'] != null
          ? List<String>.from(data['permissionIds'])
          : null,
      bloodGroup: data['bloodGroup'] as String?,
      gender: data['gender'] as String?,
      nationality: data['nationality'] as String?,
      dob: (data['dob'] as Timestamp?)?.toDate(),
      address: data['address'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'department': department,
      'position': position,
      'employeeId': employeeId,
      'joinDate': Timestamp.fromDate(joinDate),
      'photoUrl': photoUrl,
      'photoBase64': photoBase64,
      'reportsTo': reportsTo,
      'salary': salary,
      'role': role,
      'password': password,
      'isActive': isActive,
      'hasRegistered': hasRegistered,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'companyId': companyId,
      'designation': designation,
      'reportsToUserId': reportsToUserId,
      'permissionIds': permissionIds,
      'bloodGroup': bloodGroup,
      'gender': gender,
      'nationality': nationality,
      'dob': dob != null ? Timestamp.fromDate(dob!) : null,
      'address': address,
    };
  }

  AttendanceModel toAttendanceModelPlaceholder() {
    return AttendanceModel(
      id: id,
      employeeId: employeeId,
      employeeName: name,
      department: department,
      status: isActive ? AttendanceStatus.present : AttendanceStatus.absent,
      checkInTime: joinDate,
      date: joinDate,
    );
  }
}
