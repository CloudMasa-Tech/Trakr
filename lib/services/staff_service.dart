import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../control_plane/control_plane_firebase.dart';
import '../control_plane/models/tenant_identity.dart';
import '../control_plane/repositories/tenant_identity_repository.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/manager_model.dart';
import '../models/staff.dart';
import 'attendance_service.dart';

class StaffService {
  StaffService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  final String collectionName = 'staff';

  Future<String> addStaff(Staff staff) async {
    try {
      // Register the Master login index BEFORE creating any account/doc so a
      // registration failure surfaces to the inviting admin cleanly instead of
      // leaving a half-made invite whose member cannot log in. Inactive
      // employees get no password, hence no login to register.
      if (staff.password != null && staff.password!.isNotEmpty) {
        await TenantIdentityRepository.registerFromTenantContext(
          context: _context,
          email: staff.email,
          role: TenantIdentityRole.user,
          name: staff.name,
        );
      }

      // 1. Create Firebase Auth account using secondary app instance
      // This prevents the current admin user from being logged out
      String secondaryAppName =
          'StaffCreation_${DateTime.now().millisecondsSinceEpoch}';
      FirebaseApp secondaryApp = await Firebase.initializeApp(
        name: secondaryAppName,
        options: _context.app.options,
      );

      FirebaseAuth secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      UserCredential? cred;
      if (staff.password != null && staff.password!.isNotEmpty) {
        cred = await secondaryAuth.createUserWithEmailAndPassword(
          email: staff.email,
          password: staff.password!,
        );
      }

      // 2. Create record in 'users' collection for roles
      if (cred != null && cred.user != null) {
        await _firestore.collection('users').doc(cred.user!.uid).set({
          'name': staff.name,
          'email': staff.email,
          'role': staff.role ?? 'staff',
          'roleId': staff.roleId ?? 'employee',
          'roleName': staff.roleName,
          'roleLevel': staff.roleLevel,
          'reportsToUserId': staff.reportsToUserId,
          'companyId': staff.companyId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Clean up secondary app
      await secondaryApp.delete();

      // 3. Save staff record to Firestore. The `salary` and `position` fields
      // are intentionally excluded from new-employee writes: they are no
      // longer captured during onboarding. The Staff model keeps reading them
      // for backward compatibility with existing documents. (Payroll still
      // reads `salary` from this doc for existing records.)
      final staffMap = staff.toMap()
        ..remove('salary')
        ..remove('position');
      final docRef =
          await _firestore.collection(collectionName).add(staffMap);

      return docRef.id;
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      throw Exception('Failed to add staff: $e');
    }
  }

  String _friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'A login account already exists for this email. Use Forgot Password or choose another email.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Authentication.';
      case 'network-request-failed':
        return 'Network error while contacting Firebase. Check your connection and try again.';
      default:
        return e.message ?? 'Firebase rejected the account creation request.';
    }
  }

  Stream<List<Staff>> getAllStaff() {
    return _firestore
        .collection(collectionName)
        .orderBy('name')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Staff.fromFirestore(doc)).toList());
  }

  Stream<Staff?> getStaffById(String id) {
    return _firestore
        .collection(collectionName)
        .doc(id)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      return Staff.fromFirestore(snapshot);
    });
  }

  Future<Staff?> getStaffByEmployeeId(String employeeId) async {
    final trimmed = employeeId.trim();
    if (trimmed.isEmpty) return null;

    final query = await _firestore
        .collection(collectionName)
        .where('employeeId', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      return Staff.fromFirestore(query.docs.first);
    }

    final doc = await _firestore.collection(collectionName).doc(trimmed).get();
    if (doc.exists) {
      return Staff.fromFirestore(doc);
    }

    return null;
  }

  Future<Staff?> getStaffByEmail(String? email) async {
    final trimmed = email?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final query = await _firestore
        .collection(collectionName)
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return Staff.fromFirestore(query.docs.first);
  }

  Future<Staff?> getStaffByUserIdentity({
    required String uid,
    String? email,
  }) async {
    final byUid = await _firestore.collection(collectionName).doc(uid).get();
    if (byUid.exists) {
      return Staff.fromFirestore(byUid);
    }

    final byEmployeeId = await getStaffByEmployeeId(uid);
    if (byEmployeeId != null) {
      return byEmployeeId;
    }

    return getStaffByEmail(email);
  }

  Future<void> updateStaff(String id, Map<String, dynamic> data) async {
    try {
      await _firestore.collection(collectionName).doc(id).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update staff: $e');
    }
  }

  Future<void> deleteStaff(String id) async {
    Staff staff;
    try {
      final doc = await _firestore.collection(collectionName).doc(id).get();
      if (!doc.exists) {
        throw Exception('This employee no longer exists in the directory.');
      }
      staff = Staff.fromFirestore(doc);
      // Delete the directory record FIRST so a best-effort cleanup failure can
      // never leave an employee that looks "deleted" but is still listed.
      await _firestore.collection(collectionName).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete staff: $e');
    }

    await _cleanupDeletedStaff(staff);
  }

  /// Removes a manager the same way an employee is deleted: directory record
  /// first, then best-effort cleanup of audit logs, role docs, the control-plane
  /// identity index, and finally the Auth account in the tenant Firebase project.
  Future<void> deleteManager(ManagerModel manager) async {
    await _firestore.collection('managers').doc(manager.id).delete();

    try {
      await AttendanceService(context: _context).clearProfileIdentityFromLogs(
        employeeId: manager.employeeId,
        employeeName: manager.name,
      );
    } catch (_) {
      // Non-blocking: the manager entry is already gone.
    }

    final removedAuthUids = await _deleteRoleRecordsByEmail(manager.email);

    try {
      await TenantIdentityRepository().remove(manager.email);
    } catch (_) {
      // Control-plane index cleanup is best-effort by design.
    }

    await _deleteAuthUserInTenantProject(
      authUid: removedAuthUids.isNotEmpty ? removedAuthUids.first : null,
      email: manager.email,
    );
  }

  /// Best-effort post-delete cleanup. Each step is individually guarded so an
  /// audit-log or role-record failure never undoes the directory removal.
  Future<void> _cleanupDeletedStaff(Staff staff) async {
    try {
      await AttendanceService(context: _context).clearProfileIdentityFromLogs(
        employeeId: staff.employeeId,
        employeeName: staff.name,
      );
    } catch (_) {
      // Non-blocking: the directory entry is already gone.
    }

    // Capture the auth UIDs BEFORE the role records are removed so the
    // cross-project Auth deletion still knows which account to target.
    final removedAuthUids = await _deleteRoleRecordsByEmail(staff.email);

    // Remove the Master login-redirection index entry so the deleted employee's
    // email stops routing to this tenant (best-effort, never blocks).
    try {
      await TenantIdentityRepository().remove(staff.email);
    } catch (_) {
      // Control-plane index cleanup is best-effort by design.
    }

    // Properly delete the Firebase Auth account in the tenant Firebase project
    // via the master-project deleteTenantUser Cloud Function (best-effort).
    await _deleteAuthUserInTenantProject(
      authUid: removedAuthUids.isNotEmpty ? removedAuthUids.first : null,
      email: staff.email,
    );
  }

  /// Removes the `users/{uid}` role records created during onboarding so the
  /// deleted person loses their tenant access. Returns the removed UIDs so the
  /// caller can still target the tenant Auth account afterwards.
  Future<List<String>> _deleteRoleRecordsByEmail(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (email.isEmpty) return const <String>[];
    final uids = <String>[];
    try {
      final snap = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      if (snap.docs.isEmpty) return uids;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        uids.add(doc.id);
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {
      // Best-effort: never block the directory removal on role cleanup.
    }
    return uids;
  }

  /// Best-effort deletion of the employee's Firebase Auth account in the
  /// tenant Firebase project. The client SDK cannot delete another user's Auth
  /// record, so this delegates to the master-project `deleteTenantUser` Cloud
  /// Function (the master SA scoped to the tenant project + `roles/firebaseauth
  /// .admin` IAM grant). Never blocks or fails the directory deletion.
  Future<void> _deleteAuthUserInTenantProject({
    String? authUid,
    required String email,
  }) async {
    try {
      final masterProjectId = _masterProjectId;
      if (masterProjectId == null || masterProjectId.trim().isEmpty) {
        return;
      }
      final tenantProjectId = _context.app.options.projectId.trim();
      if (tenantProjectId.isEmpty || tenantProjectId == masterProjectId) {
        return;
      }

      final currentUser = _context.auth.currentUser;
      if (currentUser == null) return;
      final idToken = (await currentUser.getIdToken(true)) ?? '';
      if (idToken.isEmpty) return;

      final url = Uri.parse(
        'https://us-central1-$masterProjectId'
        '.cloudfunctions.net/deleteTenantUser',
      );
      final response = await http
          .post(
            url,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'projectId': tenantProjectId,
                if (authUid != null && authUid.trim().isNotEmpty)
                  'uid': authUid.trim(),
                'email': email,
              },
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        debugPrint(
          'deleteTenantUser: HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('deleteTenantUser best-effort failed: $e');
    }
  }

  /// The master (control plane) Firebase project ID, resolved once.
  String? get _masterProjectId {
    try {
      return ControlPlaneFirebase.instance.context.app.options.projectId;
    } catch (_) {
      return null;
    }
  }

  Stream<List<Staff>> getTeamMembersByManager(String managerName) {
    return _firestore
        .collection(collectionName)
        .where('reportsTo', isEqualTo: managerName)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Staff.fromFirestore(doc)).toList());
  }

  Future<List<String>> getTeamMemberIdsByManager(String managerName) async {
    try {
      final snapshot = await _firestore
          .collection(collectionName)
          .where('reportsTo', isEqualTo: managerName)
          .get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      throw Exception('Failed to get team members: $e');
    }
  }

  /// Validates if email exists in staff directory
  /// Simple validation - just checks if email matches
  Future<Map<String, dynamic>> validateStaffRegistration(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return {
        'canRegister': false,
        'staff': null,
        'message': 'Email is required',
      };
    }

    // Check if email exists in staff collection
    final query = await _firestore
        .collection(collectionName)
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return {
        'canRegister': false,
        'staff': null,
        'message':
            'Email not found in staff directory. Please contact your administrator.',
      };
    }

    final staff = Staff.fromFirestore(query.docs.first);

    // Check if staff is active
    if (!staff.isActive) {
      return {
        'canRegister': false,
        'staff': staff,
        'message':
            'Your account is deactivated. Please contact your administrator.',
      };
    }

    // Email exists and staff is active - can proceed
    return {
      'canRegister': true,
      'staff': staff,
      'message': 'Email verified successfully.',
    };
  }

  /// Mark a staff member as registered after successful registration
  Future<void> markStaffAsRegistered(String staffId) async {
    try {
      await _firestore.collection(collectionName).doc(staffId).update({
        'hasRegistered': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update registration status: $e');
    }
  }

  /// Check if email is already used by another staff member
  Future<bool> isEmailAlreadyUsed(String email,
      {String? excludeStaffId}) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return false;

    final query = await _firestore
        .collection(collectionName)
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return false;

    // If we're editing an existing staff member, exclude their own ID from the check
    if (excludeStaffId != null && query.docs.first.id == excludeStaffId) {
      return false;
    }

    return true;
  }

  Future<List<String>> getUniqueDepartments() async {
    try {
      final snapshot = await _firestore.collection(collectionName).get();
      final departments = snapshot.docs
          .map((doc) => doc.data()['department'] as String?)
          .where((dept) => dept != null && dept.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
      departments.sort();
      return departments;
    } catch (e) {
      debugPrint('Error fetching unique departments: $e');
      return [];
    }
  }
}
