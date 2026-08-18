import 'package:cloud_firestore/cloud_firestore.dart';

/// A per-company designation title catalog entry used by the onboarding flow
/// (the staff/manager "Designation" dropdown) and the Designations management
/// screen.
///
/// Seeded during tenant provisioning and extended by the Company Admin. Staff
/// and manager records store their own designation strings, so this catalog is
/// the starting point for the onboarding picker, not a foreign key.
class Designation {
  final String id;
  final String name;
  final String slug;
  final bool isActive;
  final String? companyId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Designation({
    required this.id,
    required this.name,
    required this.slug,
    this.isActive = true,
    this.companyId,
    this.createdAt,
    this.updatedAt,
  });

  factory Designation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Designation(
      id: doc.id,
      name: data['name'] ?? '',
      slug: data['slug'] as String? ?? doc.id,
      isActive: data['isActive'] as bool? ?? true,
      companyId: data['companyId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'slug': slug,
      'isActive': isActive,
      'companyId': companyId,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Designation copyWith({
    String? name,
    bool? isActive,
  }) {
    return Designation(
      id: id,
      name: name ?? this.name,
      slug: _slugify(name ?? this.name),
      isActive: isActive ?? this.isActive,
      companyId: companyId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
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
