import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/designation.dart';

/// Per-company designation catalog CRUD, mirroring [AccessControlService].
///
/// Every document carries a `companyId` (resolved from the signed-in user's
/// `users` doc at create time) so a tenant's designation list is scoped to its
/// own company. The onboarding dialog and the Designations management screen
/// both read through this service so UI and rules never drift apart.
class DesignationService {
  DesignationService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  static const String _designationsCollection = 'designations';

  /// Live stream of the tenant's designation catalog, newest inactive entries
  /// pushed to the end and active titles ordered by name.
  Stream<List<Designation>> getAllDesignations() {
    return _firestore.collection(_designationsCollection).snapshots().map(
          (snap) => snap.docs
              .map((doc) => Designation.fromFirestore(doc))
              .toList()
            ..sort((a, b) {
              if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            }),
        );
  }

  /// One-shot fetch used by the onboarding dialog so it can populate its
  /// dropdown without keeping a long-lived subscription.
  Future<List<Designation>> fetchAllDesignations() async {
    final snap = await _firestore
        .collection(_designationsCollection)
        .orderBy('name')
        .get();
    final designations = snap.docs
        .map((doc) => Designation.fromFirestore(doc))
        .where((d) => d.isActive)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return designations;
  }

  Future<String> createDesignation({
    required String name,
    String? companyId,
  }) async {
    final slug = _slugify(name);
    final resolvedCompanyId = companyId ?? await _resolveCompanyId();
    final ref = _firestore.collection(_designationsCollection).doc(slug);
    final designation = Designation(
      id: ref.id,
      name: name,
      slug: slug,
      isActive: true,
      companyId: resolvedCompanyId,
    );
    await ref.set(designation.toMap());
    return ref.id;
  }

  Future<void> updateDesignation({
    required String designationId,
    String? name,
    bool? isActive,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) {
      data['name'] = name;
      data['slug'] = _slugify(name);
    }
    if (isActive != null) data['isActive'] = isActive;
    await _firestore
        .collection(_designationsCollection)
        .doc(designationId)
        .update(data);
  }

  Future<void> deleteDesignation(String designationId) async {
    await _firestore.collection(_designationsCollection).doc(designationId).delete();
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

  static String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'item' : slug;
  }
}
