// lib/models/manager_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ManagerModel {
  final String id;
  final String name;
  final String email;
  final String employeeId;
  final String department;
  final String phone;
  final String position;
  final int staffCount;
  final int maxStaff;
  final String status;
  final String? photoUrl;
  final DateTime? joinDate;
  final double? salary;

  // Company & hierarchy fields
  final String? companyId;
  final String? designation;
  final String? reportsToUserId;
  final List<String>? permissionIds;
  final String? roleName;
  final int? roleLevel;

  // Demographic Fields
  final String? bloodGroup;
  final String? gender;
  final String? nationality;
  final DateTime? dob;
  final String? address;

  const ManagerModel({
    required this.id,
    required this.name,
    required this.email,
    required this.employeeId,
    required this.department,
    this.phone = '',
    this.position = '',
    required this.staffCount,
    this.maxStaff = 20,
    required this.status,
    this.photoUrl,
    this.joinDate,
    this.salary,
    this.companyId,
    this.designation,
    this.reportsToUserId,
    this.permissionIds,
    this.roleName,
    this.roleLevel,
    this.bloodGroup,
    this.gender,
    this.nationality,
    this.dob,
    this.address,
  });

  factory ManagerModel.fromFirestore(Map<String, dynamic> data, String id) {
    return ManagerModel(
      id: id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      employeeId: data['employeeId'] as String? ??
          'MNG-${id.substring(0, 4).toUpperCase()}',
      department: data['department'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      position: data['position'] as String? ?? '',
      staffCount: (data['staffCount'] as num?)?.toInt() ?? 0,
      maxStaff: (data['maxStaff'] as num?)?.toInt() ?? 20,
      status: data['status'] as String? ?? 'active',
      photoUrl: data['photoUrl'] as String?,
      joinDate: data['joinDate'] != null
          ? (data['joinDate'] as Timestamp).toDate()
          : null,
      salary:
          data['salary'] != null ? (data['salary'] as num).toDouble() : null,
      companyId: data['companyId'] as String?,
      designation: data['designation'] as String?,
      reportsToUserId: data['reportsToUserId'] as String?,
      permissionIds: data['permissionIds'] != null
          ? List<String>.from(data['permissionIds'])
          : null,
      roleName: data['roleName'] as String?,
      roleLevel: data['roleLevel'] as int?,
      bloodGroup: data['bloodGroup'] as String?,
      gender: data['gender'] as String?,
      nationality: data['nationality'] as String?,
      dob: data['dob'] != null ? (data['dob'] as Timestamp).toDate() : null,
      address: data['address'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'employeeId': employeeId,
        'department': department,
        'phone': phone,
        'position': position,
        'staffCount': staffCount,
        'maxStaff': maxStaff,
        'status': status,
        'photoUrl': photoUrl,
        'joinDate': joinDate != null ? Timestamp.fromDate(joinDate!) : null,
        'salary': salary,
        'companyId': companyId,
        'designation': designation,
        'reportsToUserId': reportsToUserId,
        'permissionIds': permissionIds,
        'roleName': roleName,
        'roleLevel': roleLevel,
        'bloodGroup': bloodGroup,
        'gender': gender,
        'nationality': nationality,
        'dob': dob != null ? Timestamp.fromDate(dob!) : null,
        'address': address,
      };
}
