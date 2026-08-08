import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/company.dart';
import '../providers/auth_session_provider.dart';
import '../services/email_service.dart';
import '../services/manager_account_service.dart';

class CompanyOnboardingResult {
  final String companyId;
  final String adminUid;
  final String adminEmail;

  const CompanyOnboardingResult({
    required this.companyId,
    required this.adminUid,
    required this.adminEmail,
  });
}

class CompanyService {
  CompanyService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  static const String _collectionName = 'companies';

  Future<Company> createCompany({
    required String name,
    String? domain,
    String? email,
    String? supportEmail,
    String? phone,
    String? address,
    String? logoUrl,
    String? website,
    String? industry,
    String? companySize,
    String? country,
    String? timezone,
    String? primaryColorHex,
  }) async {
    final docRef = _firestore.collection(_collectionName).doc();
    final now = FieldValue.serverTimestamp();
    await docRef.set({
      'name': name,
      'domain': domain,
      'email': email,
      'supportEmail': supportEmail,
      'phone': phone,
      'address': address,
      'logoUrl': logoUrl,
      'companyLogoUrl': logoUrl,
      'website': website,
      'industry': industry,
      'companySize': companySize,
      'country': country,
      'timezone': timezone,
      'primaryColorHex': primaryColorHex,
      'isActive': true,
      'createdAt': now,
      'updatedAt': now,
      'lastActiveAt': now,
    });
    final doc = await docRef.get();
    return Company.fromFirestore(doc);
  }

  /// Onboards a brand-new Company together with its first Company Admin.
  ///
  /// Reuses the same invite flow used for onboarding users: the admin's login
  /// account is created through a secondary Firebase Auth app and the role is
  /// assigned as [AppUserRole.companyAdmin] internally (not picked in the UI).
  ///
  /// Pass [companyId] when the caller has already uploaded the company logo to
  /// Firebase Storage at `company_logos/{companyId}/logo`; the company document
  /// is then created with that id so the logo reference lines up.
  Future<CompanyOnboardingResult> onboardCompany({
    required String name,
    required String email,
    required String phone,
    String? address,
    String? logoUrl,
    String? website,
    required String industry,
    required String companySize,
    required String country,
    required String timezone,
    required String adminName,
    required String adminEmail,
    required String adminPhone,
    required String adminPassword,
    String? companyId,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedAdminEmail = adminEmail.trim().toLowerCase();

    if (normalizedAdminEmail.isNotEmpty &&
        await _emailExistsInDirectory(normalizedAdminEmail)) {
      throw Exception(
        'A login account already exists for $normalizedAdminEmail. '
        'Use a different admin email.',
      );
    }

    final companyRef = companyId != null
        ? _firestore.collection(_collectionName).doc(companyId)
        : _firestore.collection(_collectionName).doc();
    final resolvedCompanyId = companyRef.id;

    String? adminUid;
    String step = 'create company document';
    try {
      debugPrint(
        'CompanyService.onboardCompany: step "$step" starting '
        '(companyId=$resolvedCompanyId)…',
      );
      await _createCompanyDoc(
        companyRef,
        Company(
          id: resolvedCompanyId,
          name: name.trim(),
          domain: normalizedEmail.contains('@')
              ? normalizedEmail.split('@').last
              : null,
          email: normalizedEmail,
          supportEmail: normalizedEmail,
          phone: phone.trim(),
          address: address?.trim(),
          logoUrl: logoUrl,
          website: website?.trim(),
          industry: industry,
          companySize: companySize,
          country: country,
          timezone: timezone,
          primaryColorHex: '0F766E',
          isActive: true,
        ),
      );
      debugPrint(
        'CompanyService.onboardCompany: step "$step" succeeded '
        '(companyId=$resolvedCompanyId).',
      );

      step = 'create Company Admin account';
      debugPrint(
        'CompanyService.onboardCompany: step "$step" starting '
        'for "$normalizedAdminEmail"…',
      );
      adminUid = await ManagerAccountService(context: _context)
          .createCompanyAdminAccount(
        name: adminName,
        email: normalizedAdminEmail,
        phone: adminPhone,
        password: adminPassword,
        companyId: resolvedCompanyId,
      );
      debugPrint(
        'CompanyService.onboardCompany: step "$step" succeeded '
        '(uid=$adminUid).',
      );

      step = 'send credentials email';
      try {
        await EmailService.sendAccountCredentials(
          recipientEmail: normalizedAdminEmail,
          password: adminPassword,
          roleLabel: 'Company Admin',
          recipientName: adminName,
        );
        debugPrint(
          'CompanyService.onboardCompany: step "$step" succeeded '
          'for "$normalizedAdminEmail".',
        );
      } catch (e, st) {
        // Email delivery is best-effort; do not fail onboarding because of it.
        debugPrint(
          'CompanyService.onboardCompany: step "$step" failed (best-effort) '
          '- $e\n$st',
        );
      }

      return CompanyOnboardingResult(
        companyId: resolvedCompanyId,
        adminUid: adminUid,
        adminEmail: normalizedAdminEmail,
      );
    } catch (e, st) {
      debugPrint(
        'CompanyService.onboardCompany: FAILED at step "$step" '
        'for company "$resolvedCompanyId" - $e\n$st',
      );
      await _rollbackCompanyOnboarding(resolvedCompanyId, adminUid);
      rethrow;
    }
  }

  Future<void> _createCompanyDoc(
    DocumentReference<Map<String, dynamic>> ref,
    Company company,
  ) async {
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'name': company.name,
      'domain': company.domain,
      'email': company.email,
      'supportEmail': company.supportEmail,
      'phone': company.phone,
      'address': company.address,
      'logoUrl': company.logoUrl,
      'companyLogoUrl': company.logoUrl,
      'website': company.website,
      'industry': company.industry,
      'companySize': company.companySize,
      'country': company.country,
      'timezone': company.timezone,
      'primaryColorHex': company.primaryColorHex,
      'isActive': company.isActive,
      'createdAt': now,
      'updatedAt': now,
      'lastActiveAt': now,
    });
  }

  Future<bool> _emailExistsInDirectory(String email) async {
    for (final collection in const ['users', 'admins', 'staff', 'managers']) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) return true;
      } catch (_) {
        // Rules/network hiccups should not block the duplicate check silently
        // failing closed; continue to next collection.
      }
    }
    return false;
  }

  Future<void> _rollbackCompanyOnboarding(
    String companyId,
    String? adminUid,
  ) async {
    // Deleting the company document also removes its logo data URL — there is
    // no separate Cloud Storage object to purge.
    try {
      await _firestore.collection(_collectionName).doc(companyId).delete();
    } catch (_) {}
    if (adminUid != null) {
      try {
        await _firestore.collection('admins').doc(adminUid).delete();
        await _firestore.collection('users').doc(adminUid).delete();
      } catch (_) {}
    }
  }

  Future<void> updateCompany(
    String companyId,
    Map<String, dynamic> updates,
  ) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore.collection(_collectionName).doc(companyId).update(updates);
  }

  Future<void> setCompanyActive(
    String companyId, {
    required bool isActive,
  }) async {
    await _firestore.collection(_collectionName).doc(companyId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Touches the company's `lastActiveAt` marker so the Super Admin dashboard
  /// can show when a company's users were last active in the app.
  Future<void> touchLastActive(String companyId) async {
    if (companyId.isEmpty) return;
    try {
      await _firestore.collection(_collectionName).doc(companyId).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<Company?> getCompany(String companyId) async {
    final doc =
        await _firestore.collection(_collectionName).doc(companyId).get();
    if (!doc.exists) return null;
    return Company.fromFirestore(doc);
  }

  Stream<Company?> streamCompany(String companyId) {
    return _firestore
        .collection(_collectionName)
        .doc(companyId)
        .snapshots()
        .map((doc) => doc.exists ? Company.fromFirestore(doc) : null);
  }

  Stream<List<Company>> streamAllCompanies() {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Company.fromFirestore).toList());
  }

  Future<List<Company>> getAllCompanies() async {
    final snapshot = await _firestore.collection(_collectionName).get();
    return snapshot.docs.map((doc) => Company.fromFirestore(doc)).toList();
  }

  Future<void> deactivateCompany(String companyId) async {
    await setCompanyActive(companyId, isActive: false);
  }

  /// The primary Company Admin for a company, looked up from the `users` and
  /// `admins` directories. Returns the display name if found.
  Future<String?> getCompanyAdminName(String companyId) async {
    try {
      final userSnap = await _firestore
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .where('role', isEqualTo: AppUserRole.companyAdmin.value)
          .limit(1)
          .get();
      if (userSnap.docs.isNotEmpty) {
        final name = userSnap.docs.first.data()['name'] as String?;
        if (name?.trim().isNotEmpty == true) return name;
      }
    } catch (_) {}
    try {
      final adminSnap = await _firestore
          .collection('admins')
          .where('companyId', isEqualTo: companyId)
          .where('role', isEqualTo: AppUserRole.companyAdmin.value)
          .limit(1)
          .get();
      if (adminSnap.docs.isNotEmpty) {
        final name = adminSnap.docs.first.data()['name'] as String?;
        if (name?.trim().isNotEmpty == true) return name;
      }
    } catch (_) {}
    return null;
  }
}
