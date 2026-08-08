import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../firebase/firebase_context_provider.dart';
import '../providers/auth_session_provider.dart';

/// Utility class to seed Firestore with test data
class FirestoreSeeds {
  static final FirebaseFirestore _firestore =
      FirebaseContextProvider.current.firestore;

  /// Initialize Firestore with runtime-derived project structure.
  static Future<void> seedProjectStructure(
      {required String adminEmail, required String adminPassword}) async {
    try {
      final cleanEmail = adminEmail.trim().toLowerCase();

      final verifiedAdmin =
          await _verifyAdminCredentials(cleanEmail, adminPassword);

      final adminName = _nameFromEmail(cleanEmail);
      final companyName = _companyNameFromEmail(cleanEmail);

      // Create default company
      final companyRef = _firestore.collection('companies').doc();
      final companyId = companyRef.id;
      await companyRef.set({
        'name': companyName,
        'domain': cleanEmail.split('@').last,
        'primaryColorHex': '0F766E',
        'supportEmail': cleanEmail,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('settings').doc('white_label').set({
        'companyName': companyName,
        'primaryColorHex': '0F766E',
        'supportEmail': cleanEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final uid = verifiedAdmin.uid;
      await _firestore.collection('admins').doc(uid).set({
        'name': adminName,
        'email': cleanEmail,
        'authUid': uid,
        'role': AppUserRole.companyAdmin.value,
        'status': 'active',
        'isActive': true,
        'photoUrl': verifiedAdmin.photoURL,
        'companyId': companyId,
        'designation': 'Administrator',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'firebase_auth_verified',
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(uid).set({
        'name': adminName,
        'email': cleanEmail,
        'role': AppUserRole.companyAdmin.value,
        'companyId': companyId,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore.collection('app_config').doc('admin_access').set({
        'primaryAdminEmail': cleanEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final defaultGeoConfig = {
        'name': '$companyName Office',
        'latitude': null,
        'longitude': null,
        'radius': 100,
        'geoFenceRadius': 100,
        'checkInStart': '08:30 AM',
        'checkInEnd': '10:30 AM',
        'checkOutEnd': '07:30 PM',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _firestore
          .collection('geo_config')
          .doc('default')
          .set(defaultGeoConfig, SetOptions(merge: true));
      await _firestore
          .collection('offices')
          .doc('default')
          .set(defaultGeoConfig, SetOptions(merge: true));

      await _firestore.collection('qr_tokens').doc('initial').set({
        'info': 'Initialized by admin setup',
        'tenantId': companyId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore.collection('attendance_alerts').doc('system_init').set({
        'message': 'System initialized by $adminName',
        'type': 'info',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('Project structure initialized successfully');
    } catch (e) {
      debugPrint('Error initializing project structure: $e');
      rethrow;
    }
  }

  /// Kept for existing callers. This no longer inserts fixed sample people.
  static Future<void> seedTestStaff() async {
    try {
      await _firestore.collection('staff_metadata').doc('setup').set({
        'initializedAt': FieldValue.serverTimestamp(),
        'source': 'dynamic_setup',
      }, SetOptions(merge: true));
      debugPrint('Staff metadata initialized successfully');
    } catch (e) {
      debugPrint('Error initializing staff metadata: $e');
      rethrow;
    }
  }

  static String _nameFromEmail(String email) {
    final localPart = email.split('@').first;
    return localPart
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static Future<User> _verifyAdminCredentials(
    String email,
    String password,
  ) async {
    final credential =
        await FirebaseContextProvider.current.auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw Exception('Admin sign-in failed.');
    }

    final isAdmin = await _isAdminDirectoryUser(user) ||
        await _isFirebaseAuthOnlyAdmin(user);
    if (!isAdmin) {
      await FirebaseContextProvider.current.auth.signOut();
      throw Exception(
        'Only an admin registered in Firestore can initialize data.',
      );
    }

    return user;
  }

  static Future<bool> _isAdminDirectoryUser(User user) async {
    final uidDoc = await _firestore.collection('admins').doc(user.uid).get();
    if (uidDoc.exists && _isActiveAdmin(uidDoc.data())) return true;

    final email = user.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) return false;

    final exactEmail = await _firestore
        .collection('admins')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (exactEmail.docs.any((doc) => _isActiveAdmin(doc.data()))) return true;

    final admins = await _firestore.collection('admins').limit(100).get();
    for (final doc in admins.docs) {
      final data = doc.data();
      final docEmail = (data['email'] as String? ?? '').trim().toLowerCase();
      if (docEmail == email && _isActiveAdmin(data)) return true;
    }

    return false;
  }

  static Future<bool> _isFirebaseAuthOnlyAdmin(User user) async {
    final email = user.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) return false;

    if (await _emailExistsInRoleDirectory('managers', email)) return false;
    if (await _emailExistsInRoleDirectory('staff', email)) return false;

    return true;
  }

  static Future<bool> _emailExistsInRoleDirectory(
    String collection,
    String email,
  ) async {
    final exactEmail = await _firestore
        .collection(collection)
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (exactEmail.docs.isNotEmpty) return true;

    final docs = await _firestore.collection(collection).limit(200).get();
    for (final doc in docs.docs) {
      final data = doc.data();
      final docEmail = (data['email'] as String? ?? '').trim().toLowerCase();
      if (docEmail == email) return true;
    }

    return false;
  }

  static bool _isActiveAdmin(Map<String, dynamic>? data) {
    if (data == null) return false;
    final role = (data['role'] as String? ?? '').trim().toLowerCase();
    final status = (data['status'] as String? ?? 'active').trim().toLowerCase();
    final isActive = data['isActive'];
    final active = isActive is bool ? isActive : true;
    return (role == 'admin' ||
            role == 'company_admin' ||
            role == 'companyAdmin') &&
        active &&
        status != 'inactive';
  }

  static String _companyNameFromEmail(String email) {
    final domain = email.contains('@') ? email.split('@').last : '';
    final company = domain.split('.').first;
    if (company.isEmpty) return 'Attendance System';
    return '${company[0].toUpperCase()}${company.substring(1)} Attendances';
  }
}
