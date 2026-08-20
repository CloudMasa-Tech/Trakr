import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/firebase_context.dart';
import '../../services/access_control_service.dart';
import 'tenant_defaults.dart';

/// What a single atomic tenant seed batch wrote, so a failed provisioning run
/// can remove it again (best-effort, in reverse order).
class TenantSeedResult {
  TenantSeedResult(this.documentPaths, {Set<String>? preExisting})
      : preExisting = preExisting ?? const <String>{};

  /// Every document path created by the seed batch, in write order.
  final List<String> documentPaths;

  /// Document paths (e.g. `settings/white_label`) that already existed before
  /// the seed ran — typically leftovers of a crashed earlier provisioning run.
  /// A rollback must NOT delete these; it only removes documents this run created.
  final Set<String> preExisting;
}

/// Seeds a freshly-provisioned tenant (data plane) project with all the
/// defaults the app needs to work out of the box.
///
/// Everything is written through individual set() calls to Cloud Firestore.
/// The [companyId]/[adminUid] must already exist (created by
/// [TenantProvisioner.provision]) before this runs.
class TenantSeeder {
  TenantSeeder({required FirebaseContext context}) : _context = context;

  final FirebaseContext _context;

  static const int _qrTokenValidForDays = 90;

  Future<TenantSeedResult> seed({
    required String companyId,
    required String adminUid,
    required String adminEmail,
    required String companyName,
    String? supportEmail,
  }) async {
    final db = _context.firestore;
    final created = <String>[];
    final dataMap = <String, Map<String, dynamic>>{};

    void add(String path, Map<String, dynamic> data) {
      db.doc(path);
      created.add(path);
      dataMap[path] = data;
    }

    final geoConfig = <String, dynamic>{
      'name': '$companyName Office',
      'latitude': null,
      'longitude': null,
      'radius': kTenantDefaultGeoFenceRadius,
      'geoFenceRadius': kTenantDefaultGeoFenceRadius,
      'checkInStart': kTenantDefaultCheckInStart,
      'checkInEnd': kTenantDefaultCheckInEnd,
      'checkOutStart': kTenantDefaultCheckOutStart,
      'checkOutEnd': kTenantDefaultCheckOutEnd,
      ...kTenantDefaultHolidayCalendar,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Company profile branding consumed by WhiteLabelProvider.
    add('settings/white_label', <String, dynamic>{
      'companyName': companyName,
      'primaryColorHex': kTenantDefaultPrimaryColorHex,
      'supportEmail': supportEmail ?? adminEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Admin email whitelist consumed during sign-in (app_config/admin_access).
    add('app_config/admin_access', <String, dynamic>{
      'primaryAdminEmail': adminEmail,
      'adminEmails': <String>[adminEmail],
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Attendance settings + office geofence.
    add('geo_config/default', geoConfig);
    add('offices/default', geoConfig);

    // Initial QR token so staff can scan immediately.
    final expiresAt =
        DateTime.now().add(const Duration(days: _qrTokenValidForDays));
    add('qr_tokens/$companyId', <String, dynamic>{
      'token': _generateSecureToken(),
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'refreshedAt': FieldValue.serverTimestamp(),
      'tenantId': companyId,
      'geoFenceRadius': kTenantDefaultGeoFenceRadius,
      'validForDays': _qrTokenValidForDays,
      'refreshSource': 'provisioning',
    });

    // Departments catalog.
    for (final name in kTenantDefaultDepartments) {
      final slug = _slugify(name);
      add('departments/$slug', <String, dynamic>{
        'name': name,
        'slug': slug,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Designations catalog.
    for (final name in kTenantDefaultDesignations) {
      final slug = _slugify(name);
      add('designations/$slug', <String, dynamic>{
        'name': name,
        'slug': slug,
        'isActive': true,
        'companyId': companyId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Leave policies.
    for (final policy in kTenantDefaultLeavePolicies) {
      add('leave_policies/${policy['id']}', <String, dynamic>{
        'name': policy['name'],
        'monthlyLeaveAllowance': policy['monthlyLeaveAllowance'],
        'isDefault': policy['isDefault'],
        'isActive': policy['isActive'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Holiday calendar catalog.
    add('holidays/default', <String, dynamic>{
      'name': 'Default Holiday Calendar',
      ...kTenantDefaultHolidayCalendar,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Roles/permissions: seed the catalog plus the protected system roles and
    // the editable starter roles. The initial Company Admin is bound to the
    // `company_admin` system role.
    const permissions = AccessControlService.defaultPermissions;
    final permissionIds = <String>[];
    for (final permission in permissions) {
      add('permissions/${permission.id}', <String, dynamic>{
        'name': permission.name,
        'description': permission.description,
        'category': permission.category,
        'isSystem': true,
      });
      permissionIds.add(permission.id);
    }

    const companyAdminRoleId = 'company_admin';
    add('roles/$companyAdminRoleId', <String, dynamic>{
      'name': 'Company Admin',
      'description': 'Administers the company and all of its modules.',
      'permissionIds': permissionIds,
      'isSystem': true,
      'isManagerial': true,
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    add('roles/manager', <String, dynamic>{
      'name': 'Manager',
      'description': 'Manages a team and approves leave/permission requests.',
      'permissionIds': [
        'attendance.view_own',
        'attendance.view_team',
        'attendance.check_in_out',
        'team.view',
        'leave.apply',
        'leave.view',
        'leave.approve',
        'permission.apply',
        'permission.view',
        'permission.approve',
        'reports.view',
      ],
      'isSystem': false,
      'isManagerial': true,
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    add('roles/employee', <String, dynamic>{
      'name': 'Employee',
      'description': 'Standard staff member with personal attendance access.',
      'permissionIds': [
        'attendance.view_own',
        'attendance.check_in_out',
        'leave.apply',
        'permission.apply',
      ],
      'isSystem': false,
      'isManagerial': false,
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    add('roles/hr', <String, dynamic>{
      'name': 'HR',
      'description': 'Handles people operations, leave, and attendance reports.',
      'permissionIds': [
        'attendance.view_own',
        'attendance.view_team',
        'attendance.view_all',
        'attendance.manage',
        'team.view',
        'leave.apply',
        'leave.view',
        'leave.approve',
        'permission.apply',
        'permission.view',
        'permission.approve',
        'reports.view',
        'reports.export',
        'users.view',
        'users.edit',
        'users.disable',
        'notifications.view',
        'notifications.send',
      ],
      'isSystem': false,
      'isManagerial': false,
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    add('roles/payroll_admin', <String, dynamic>{
      'name': 'Payroll Admin',
      'description': 'Manages payroll configuration and processing.',
      'permissionIds': [
        'attendance.view_own',
        'attendance.view_all',
        'reports.view',
        'reports.export',
        'payroll.view',
        'payroll.manage',
        'users.view',
      ],
      'isSystem': false,
      'isManagerial': false,
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Probe which documents already exist (left over from a crashed earlier
    // run) so rollback is conservative and never deletes them.
    final preExisting = <String>{};
    try {
      final snapshots = await Future.wait(created.map((path) => _context.firestore.doc(path).get()));
      for (var i = 0; i < created.length; i++) {
        if (snapshots[i].exists) preExisting.add(created[i]);
      }
    } catch (_) {
      // Under locked/default rules the probe reads are denied; treat every
      // node as new so rollback remains best-effort and harmless.
    }

    // Commit all writes using a batch
    final batch = _context.firestore.batch();
    for (final path in created) {
      batch.set(_context.firestore.doc(path), dataMap[path]!);
    }
    await batch.commit();

    return TenantSeedResult(created, preExisting: preExisting);
  }

  /// Best-effort removal of the documents written by [seed].
  ///
  /// Only documents that did NOT pre-exist are deleted — retrying a partially
  /// provisioned tenant can never wipe data left behind by an earlier run.
  Future<void> rollback(TenantSeedResult result) async {
    final batch = _context.firestore.batch();
    for (final path in result.documentPaths.reversed) {
      if (result.preExisting.contains(path)) continue;
      try {
        batch.delete(_context.firestore.doc(path));
      } catch (_) {
        // Deletion is best-effort; the orchestrator's registry/allocation
        // handling continues regardless.
      }
    }
    await batch.commit();
  }

  String _generateSecureToken() {
    final rng = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'item' : slug;
  }
}