import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../control_plane/models/tenant_identity.dart';
import '../control_plane/repositories/tenant_identity_repository.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../providers/auth_session_provider.dart';

class ManagerAccountService {
  ManagerAccountService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;

  Future<String> createManagerAccount({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String employeeId,
    required String department,
    required String position,
    required int staffCount,
    required int maxStaff,
    required DateTime joinDate,
    required String status,
    double? salary,
    String? bloodGroup,
    String? gender,
    String? nationality,
    DateTime? dob,
    String? address,
    String? photoUrl,
    String? companyId,
  }) async {
    FirebaseApp? secondaryApp;
    User? createdUser;
    DocumentReference<Map<String, dynamic>>? managerRef;

    try {
      final normalizedEmail = email.trim().toLowerCase();

      final existingManager = await _firestore
          .collection('managers')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (existingManager.docs.isNotEmpty) {
        throw Exception('A manager with this email already exists');
      }

      secondaryApp = await Firebase.initializeApp(
        name: 'ManagerCreation_${DateTime.now().millisecondsSinceEpoch}',
        options: _context.app.options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      createdUser = credential.user;
      await createdUser?.updateDisplayName(name.trim());

      managerRef = await _firestore.collection('managers').add({
        'name': name,
        'email': normalizedEmail,
        'phone': phone,
        'employeeId': employeeId,
        'department': department,
        'position': position,
        'staffCount': staffCount,
        'maxStaff': maxStaff,
        'joinDate': Timestamp.fromDate(joinDate),
        'status': status,
        'salary': salary,
        'photoUrl': photoUrl,
        'authUid': createdUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'bloodGroup': bloodGroup,
        'gender': gender,
        'nationality': nationality,
        'dob': dob != null ? Timestamp.fromDate(dob) : null,
        'address': address,
        'companyId': companyId,
      });

      await _firestore.collection('users').doc(createdUser!.uid).set({
        'name': name.trim(),
        'email': normalizedEmail,
        'phone': phone.trim(),
        'role': 'manager',
        'managerId': managerRef.id,
        'companyId': companyId,
        'salary': salary,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Register the login identity so the manager can sign in with their
      // email without entering a workspace code (best-effort).
      unawaited(TenantIdentityRepository.registerFromTenantContext(
        context: _context,
        email: normalizedEmail,
        role: TenantIdentityRole.user,
        name: name.trim(),
      ));

      return managerRef.id;
    } catch (e) {
      if (managerRef != null) {
        await managerRef.delete().catchError((_) {});
      }
      if (createdUser != null) {
        await _firestore
            .collection('users')
            .doc(createdUser.uid)
            .delete()
            .catchError((_) {});
        await createdUser.delete().catchError((_) {});
      }
      if (e is FirebaseAuthException) {
        throw Exception(_friendlyAuthMessage(e));
      }
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      await secondaryApp?.delete();
    }
  }

  Future<String> createCompanyAdminAccount({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String companyId,
  }) async {
    FirebaseApp? secondaryApp;
    User? createdUser;
    String? adminDocId;

    try {
      final normalizedEmail = email.trim().toLowerCase();
      final normalizedPhone = phone.trim();

      final existingAdmin = await _firestore
          .collection('admins')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (existingAdmin.docs.isNotEmpty) {
        throw Exception('An admin with this email already exists');
      }

      secondaryApp = await Firebase.initializeApp(
        name: 'CompanyAdminCreation_${DateTime.now().millisecondsSinceEpoch}',
        options: _context.app.options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      createdUser = credential.user;
      await createdUser?.updateDisplayName(name.trim());

      final adminRef = await _firestore.collection('admins').add({
        'name': name.trim(),
        'email': normalizedEmail,
        'phone': normalizedPhone,
        'role': AppUserRole.companyAdmin.value,
        'status': 'active',
        'isActive': true,
        'authUid': createdUser?.uid,
        'companyId': companyId,
        'hasRegistered': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      adminDocId = adminRef.id;

      await _firestore.collection('users').doc(createdUser!.uid).set({
        'name': name.trim(),
        'email': normalizedEmail,
        'phone': normalizedPhone,
        'role': AppUserRole.companyAdmin.value,
        'adminId': adminDocId,
        'companyId': companyId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return createdUser.uid;
    } catch (e) {
      if (adminDocId != null) {
        await _firestore
            .collection('admins')
            .doc(adminDocId)
            .delete()
            .catchError((_) {});
      }
      if (createdUser != null) {
        await _firestore
            .collection('users')
            .doc(createdUser.uid)
            .delete()
            .catchError((_) {});
        await createdUser.delete().catchError((_) {});
      }
      if (e is FirebaseAuthException) {
        throw Exception(_friendlyAuthMessage(e));
      }
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      await secondaryApp?.delete();
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
}
