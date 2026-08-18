import 'package:cloud_firestore/cloud_firestore.dart';

/// A named bundle of permissions assigned to users within a tenant.
///
/// System roles (`isSystem == true`) such as `super_admin` and `company_admin`
/// cannot be edited or deleted through the UI. Custom roles are fully
/// user-manageable. Permission resolution at runtime merges a user's `roleId`
/// permissions with any direct `permissionIds` on their account document.
class UserRole {
  final String id;
  final String name;
  final String description;
  final List<String> permissionIds;
  final bool isSystem;
  final bool isManagerial;
  final String? companyId;
  final int level;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserRole({
    required this.id,
    required this.name,
    this.description = '',
    this.permissionIds = const [],
    this.isSystem = false,
    this.isManagerial = false,
    this.companyId,
    this.level = 10,
    this.createdAt,
    this.updatedAt,
  });

  factory UserRole.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserRole.fromMap(data, id: doc.id);
  }

  factory UserRole.fromMap(Map<String, dynamic> data, {required String id}) {
    final rawLevel = data['level'];
    final level = rawLevel is int
        ? rawLevel
        : rawLevel is num
            ? rawLevel.toInt()
            : int.tryParse('${rawLevel ?? ''}') ?? 10;
    return UserRole(
      id: id,
      name: data['name']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      permissionIds: data['permissionIds'] is List
          ? (data['permissionIds'] as List)
              .map((e) => e.toString())
              .toList()
          : const [],
      isSystem: data['isSystem'] == true,
      isManagerial: data['isManagerial'] == true,
      companyId: data['companyId'] is String ? data['companyId'] as String : null,
      level: level,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'permissionIds': permissionIds,
      'isSystem': isSystem,
      'isManagerial': isManagerial,
      'companyId': companyId,
      'level': level,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserRole copyWith({
    String? name,
    String? description,
    List<String>? permissionIds,
    bool? isManagerial,
  }) {
    return UserRole(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      permissionIds: permissionIds ?? this.permissionIds,
      isSystem: isSystem,
      isManagerial: isManagerial ?? this.isManagerial,
      companyId: companyId,
      level: level,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
