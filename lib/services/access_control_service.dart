import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/permission.dart';

class AccessControlService {
  AccessControlService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  static const String _permissionsCollection = 'permissions';

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

  Future<List<String>> _getUserPermissionIds(String userId) async {
    final collections = ['staff', 'managers', 'admins', 'users'];
    for (final collection in collections) {
      try {
        final doc = await _firestore.collection(collection).doc(userId).get();
        if (doc.exists && doc.data()?.containsKey('permissionIds') == true) {
          final ids = doc.data()!['permissionIds'];
          if (ids is List) return List<String>.from(ids);
        }
        final email = doc.data()?['email'] as String?;
        if (email != null) {
          final snap = await _firestore
              .collection(collection)
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final data = snap.docs.first.data();
            if (data.containsKey('permissionIds') &&
                data['permissionIds'] is List) {
              return List<String>.from(data['permissionIds']);
            }
          }
        }
      } catch (_) {}
    }
    return [];
  }

  Stream<List<AppPermission>> getAllPermissions() {
    return _firestore.collection(_permissionsCollection).snapshots().map(
        (snap) =>
            snap.docs.map((doc) => AppPermission.fromFirestore(doc)).toList());
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
      id: 'users.manage',
      name: 'Manage Users',
      description: 'Create, edit, and deactivate user accounts',
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
      id: 'notifications.send',
      name: 'Send Notifications',
      description: 'Send push notifications to users',
      category: 'notifications',
    ),
    PermissionDefinition(
      id: 'geo.manage',
      name: 'Manage Geofence',
      description: 'Configure office locations and geofence settings',
      category: 'company',
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
