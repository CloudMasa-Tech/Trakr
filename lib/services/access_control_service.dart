import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/permission.dart';
import '../models/user_role.dart';

/// Single source of truth for the app's permission model.
///
/// - [defaultPermissions] is the canonical catalog of every permission the UI
///   can grant. Kept in sync with the seeded `permissions` collection.
/// - Permission resolution merges a user's direct `permissionIds` with the
///   permissions of the `roles/{roleId}` they belong to, so a role assignment
///   never requires duplicating permission lists on the user document.
/// - Role CRUD lives here; the roles screen and the seeding path both go
///   through this service so UI and backend can never drift apart.
class AccessControlService {
  AccessControlService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  static const String _permissionsCollection = 'permissions';
  static const String _rolesCollection = 'roles';

  // ── Permission checks ────────────────────────────────────────────────

  Future<bool> hasPermission({
    required String userId,
    required String permissionId,
    List<String>? userPermissionIds,
  }) async {
    final ids = userPermissionIds ?? await _getUserPermissionIds(userId);
    return ids.contains(permissionId);
  }

  Future<bool> hasAnyPermission({
    required String userId,
    required List<String> permissionIds,
    List<String>? userPermissionIds,
  }) async {
    final ids = userPermissionIds ?? await _getUserPermissionIds(userId);
    return permissionIds.any((p) => ids.contains(p));
  }

  Future<bool> hasAllPermissions({
    required String userId,
    required List<String> permissionIds,
    List<String>? userPermissionIds,
  }) async {
    final ids = userPermissionIds ?? await _getUserPermissionIds(userId);
    return permissionIds.every((p) => ids.contains(p));
  }

  /// Resolves the effective permission set for [userId] across all four user
  /// collections (staff, managers, admins, users). For every matching document
  /// it unions the direct `permissionIds` with the `permissionIds` of the
  /// `roles/{roleId}` the document references — role inheritance means a role
  /// assignment is the single source of truth and users never need their own
  /// permission list duplicated.
  Future<List<String>> _getUserPermissionIds(String userId) async {
    final resolved = <String>{};
    final collections = ['staff', 'managers', 'admins', 'users'];
    for (final collection in collections) {
      try {
        final doc = await _firestore.collection(collection).doc(userId).get();
        if (doc.exists && doc.data() != null) {
          await _addPermissionsFromData(doc.data()!, resolved);
          continue;
        }
        final email = doc.data()?['email'] as String?;
        if (email != null) {
          final snap = await _firestore
              .collection(collection)
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            await _addPermissionsFromData(snap.docs.first.data(), resolved);
          }
        }
      } catch (_) {}
    }
    return resolved.toList();
  }

  /// Unions direct `permissionIds` with the role permissions for a single user
  /// document's data map.
  Future<void> _addPermissionsFromData(
      Map<String, dynamic> data, Set<String> into) async {
    final direct = data['permissionIds'];
    if (direct is List) {
      into.addAll(direct.whereType<String>());
    }
    final roleId = data['roleId'];
    if (roleId is String && roleId.isNotEmpty) {
      try {
        final roleSnap =
            await _firestore.collection(_rolesCollection).doc(roleId).get();
        if (roleSnap.exists) {
          final roleData = roleSnap.data() as Map<String, dynamic>;
          final rolePerms = roleData['permissionIds'];
          if (rolePerms is List) {
            into.addAll(rolePerms.whereType<String>());
          }
        }
      } catch (_) {}
    }
  }

  // ── Permissions catalog ─────────────────────────────────────────────

  Stream<List<AppPermission>> getAllPermissions() {
    return _firestore.collection(_permissionsCollection).snapshots().map(
        (snap) =>
            snap.docs.map((doc) => AppPermission.fromFirestore(doc)).toList());
  }

  // ── Roles ───────────────────────────────────────────────────────────

  Stream<List<UserRole>> getAllRoles() {
    return _firestore
        .collection(_rolesCollection)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => UserRole.fromFirestore(doc)).toList());
  }

  Future<UserRole?> getRoleById(String roleId) async {
    final doc = await _firestore.collection(_rolesCollection).doc(roleId).get();
    if (!doc.exists) return null;
    return UserRole.fromFirestore(doc);
  }

  Future<String> createRole({
    required String name,
    String description = '',
    required List<String> permissionIds,
    String? companyId,
    int level = 10,
    bool isManagerial = false,
    bool canBeReportingManager = false,
  }) async {
    final resolvedCompanyId = companyId ?? await _resolveCompanyId();
    final ref = _firestore.collection(_rolesCollection).doc();
    await ref.set({
      'name': name,
      'description': description,
      'permissionIds': permissionIds,
      'isSystem': false,
      'isManagerial': isManagerial,
      'canBeReportingManager': canBeReportingManager,
      'companyId': resolvedCompanyId,
      'level': level,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Resolves the signed-in user's tenant company id from their `users` doc.
  Future<String?> _resolveCompanyId() async {
    try {
      final user = _context.auth.currentUser;
      if (user == null) return null;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;
      final companyId = doc.data()?['companyId'] as String?;
      if (companyId == null || companyId.trim().isEmpty) return null;
      return companyId.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> updateRole({
    required String roleId,
    String? name,
    String? description,
    List<String>? permissionIds,
    int? level,
    bool? isManagerial,
    bool? canBeReportingManager,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (permissionIds != null) data['permissionIds'] = permissionIds;
    if (level != null) data['level'] = level;
    if (isManagerial != null) data['isManagerial'] = isManagerial;
    if (canBeReportingManager != null) {
      data['canBeReportingManager'] = canBeReportingManager;
    }
    await _firestore.collection(_rolesCollection).doc(roleId).update(data);
  }

  Future<void> deleteRole(String roleId) async {
    await _firestore.collection(_rolesCollection).doc(roleId).delete();
  }

  /// Assigns [roleId] to a user's canonical `users` document. The role's
  /// permissions are inherited automatically by [_addPermissionsFromData].
  Future<void> assignRoleToUser({
    required String userId,
    required String roleId,
  }) async {
    await _firestore.collection('users').doc(userId).set({
      'roleId': roleId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Removes a role assignment, keeping any direct permissions untouched.
  Future<void> unassignRoleFromUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'roleId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream of every user in the tenant (canonical `users` collection) plus
  /// their current `roleId`, for the assign-role pickers.
  Stream<List<Map<String, dynamic>>> getAllUsersWithRoles() {
    return _firestore.collection('users').snapshots().map((snap) => snap.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList());
  }

  static const List<PermissionDefinition> defaultPermissions = [
    PermissionDefinition(
      id: 'attendance.view_own',
      name: 'View Own Attendance',
      description: 'View personal attendance records',
      category: 'attendance',
    ),
    PermissionDefinition(
      id: 'attendance.view_team',
      name: 'View Team Attendance',
      description: 'View attendance records of team members',
      category: 'attendance',
    ),
    PermissionDefinition(
      id: 'attendance.view_all',
      name: 'View All Attendance',
      description: 'View attendance records across the organization',
      category: 'attendance',
    ),
    PermissionDefinition(
      id: 'attendance.check_in_out',
      name: 'Check In/Out',
      description: 'Scan QR code to check in and out',
      category: 'attendance',
    ),
    PermissionDefinition(
      id: 'attendance.manage',
      name: 'Manage Attendance',
      description: 'Correct or override attendance records',
      category: 'attendance',
    ),
    PermissionDefinition(
      id: 'team.view',
      name: 'View Team',
      description: 'View team members and their profiles',
      category: 'team',
    ),
    PermissionDefinition(
      id: 'team.manage',
      name: 'Manage Team',
      description: 'Add, edit, and remove team members',
      category: 'team',
    ),
    PermissionDefinition(
      id: 'leave.apply',
      name: 'Apply Leave',
      description: 'Submit leave requests',
      category: 'leave',
    ),
    PermissionDefinition(
      id: 'leave.view',
      name: 'View Leave Requests',
      description: 'View all leave requests',
      category: 'leave',
    ),
    PermissionDefinition(
      id: 'leave.approve',
      name: 'Approve Leave',
      description: 'Approve or reject leave requests from team members',
      category: 'leave',
    ),
    PermissionDefinition(
      id: 'permission.apply',
      name: 'Request Permission',
      description: 'Submit permission-to-exit requests',
      category: 'permission',
    ),
    PermissionDefinition(
      id: 'permission.view',
      name: 'View Permission Requests',
      description: 'View all permission-to-exit requests',
      category: 'permission',
    ),
    PermissionDefinition(
      id: 'permission.approve',
      name: 'Approve Permission',
      description: 'Approve or reject permission requests from team members',
      category: 'permission',
    ),
    PermissionDefinition(
      id: 'reports.view',
      name: 'View Reports',
      description: 'Access attendance reports and analytics',
      category: 'reports',
    ),
    PermissionDefinition(
      id: 'reports.export',
      name: 'Export Reports',
      description: 'Export reports as CSV, PDF, or Excel',
      category: 'reports',
    ),
    PermissionDefinition(
      id: 'payroll.view',
      name: 'View Payroll',
      description: 'View payroll information',
      category: 'payroll',
    ),
    PermissionDefinition(
      id: 'payroll.manage',
      name: 'Manage Payroll',
      description: 'Configure and process payroll',
      category: 'payroll',
    ),
    PermissionDefinition(
      id: 'users.view',
      name: 'View Users',
      description: 'View the user directory',
      category: 'users',
    ),
    PermissionDefinition(
      id: 'users.create',
      name: 'Create Users',
      description: 'Onboard new users into the organization',
      category: 'users',
    ),
    PermissionDefinition(
      id: 'users.edit',
      name: 'Edit Users',
      description: 'Edit user profile details',
      category: 'users',
    ),
    PermissionDefinition(
      id: 'users.disable',
      name: 'Disable Users',
      description: 'Deactivate user accounts',
      category: 'users',
    ),
    PermissionDefinition(
      id: 'company.settings',
      name: 'Company Settings',
      description: 'Configure company-wide settings and branding',
      category: 'company',
    ),
    PermissionDefinition(
      id: 'holidays.manage',
      name: 'Manage Holidays',
      description: 'Configure weekends and holidays',
      category: 'company',
    ),
    PermissionDefinition(
      id: 'notifications.view',
      name: 'View Notifications',
      description: 'View notification history',
      category: 'notifications',
    ),
    PermissionDefinition(
      id: 'notifications.send',
      name: 'Send Notifications',
      description: 'Send push notifications to users',
      category: 'notifications',
    ),
    PermissionDefinition(
      id: 'qr.manage',
      name: 'Manage QR Codes',
      description: 'Generate and manage QR tokens for check-in',
      category: 'qr',
    ),
    PermissionDefinition(
      id: 'geo.manage',
      name: 'Manage Geofence',
      description: 'Configure office locations and geofence settings',
      category: 'company',
    ),
    PermissionDefinition(
      id: 'roles.manage',
      name: 'Manage Roles',
      description: 'Create, edit, and assign user roles',
      category: 'users',
    ),
  ];
}

class PermissionDefinition {
  final String id;
  final String name;
  final String description;
  final String category;

  const PermissionDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
  });
}
