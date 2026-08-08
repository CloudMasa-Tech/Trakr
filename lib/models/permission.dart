import 'package:cloud_firestore/cloud_firestore.dart';

class AppPermission {
  final String id;
  final String name;
  final String description;
  final String category;
  final bool isSystem;

  const AppPermission({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.isSystem = false,
  });

  factory AppPermission.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppPermission(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      isSystem: data['isSystem'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'isSystem': isSystem,
    };
  }
}
