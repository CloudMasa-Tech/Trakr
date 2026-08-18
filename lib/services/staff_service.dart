import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../control_plane/models/tenant_identity.dart';
import '../control_plane/repositories/tenant_identity_repository.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
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

      // 3. Save staff record to Firestore
      final docRef =
          await _firestore.collection(collectionName).add(staff.toMap());

      // Register the login identity so the staff can sign in with their email
      // without entering a workspace code (best-effort, never blocks creation).
      unawaited(TenantIdentityRepository.registerFromTenantContext(
        context: _context,
        email: staff.email,
        role: TenantIdentityRole.user,
        name: staff.name,
      ));

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
    try {
      final doc = await _firestore.collection(collectionName).doc(id).get();
      if (doc.exists) {
        final staff = Staff.fromFirestore(doc);
        await AttendanceService(context: _context).clearProfileIdentityFromLogs(
          employeeId: staff.employeeId,
          employeeName: staff.name,
        );
      }
      await _firestore.collection(collectionName).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete staff: $e');
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
