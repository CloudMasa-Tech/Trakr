import 'package:cloud_firestore/cloud_firestore.dart';

/// A billable plan a workspace can subscribe to (platform-level data).
///
/// Plans live in the Master Firebase control plane (`plans/{planId}`) and are
/// referenced by [Subscription]s. They describe pricing and entitlements only —
/// they never carry operational data.
class Plan {
  /// The unique plan id (`plans/{planId}`).
  final String id;

  /// Display name, e.g. "Pro".
  final String name;

  /// Short human-readable description.
  final String description;

  /// Monthly price in [currency].
  final double monthlyPrice;

  /// Annual price in [currency] (usually discounted).
  final double annualPrice;

  /// ISO 4217 currency code, e.g. "USD".
  final String currency;

  /// Maximum number of seats (employees) included.
  final int maxSeats;

  /// Feature entitlement flags, e.g. `{'reports': true, 'qr': true}`.
  final Map<String, bool> features;

  /// Whether the plan is currently offered.
  final bool isActive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Plan({
    required this.id,
    required this.name,
    this.description = '',
    this.monthlyPrice = 0,
    this.annualPrice = 0,
    this.currency = 'USD',
    this.maxSeats = 0,
    this.features = const {},
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Plan.fromFirestore(Map<String, dynamic> data, String id) {
    return Plan(
      id: id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      monthlyPrice: (data['monthlyPrice'] as num?)?.toDouble() ?? 0,
      annualPrice: (data['annualPrice'] as num?)?.toDouble() ?? 0,
      currency: data['currency'] as String? ?? 'USD',
      maxSeats: (data['maxSeats'] as num?)?.toInt() ?? 0,
      features: _stringBoolMap(data['features']),
      isActive: data['isActive'] as bool? ?? true,
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'monthlyPrice': monthlyPrice,
      'annualPrice': annualPrice,
      'currency': currency,
      'maxSeats': maxSeats,
      'features': features,
      'isActive': isActive,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Plan copyWith({
    String? id,
    String? name,
    String? description,
    double? monthlyPrice,
    double? annualPrice,
    String? currency,
    int? maxSeats,
    Map<String, bool>? features,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Plan(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      annualPrice: annualPrice ?? this.annualPrice,
      currency: currency ?? this.currency,
      maxSeats: maxSeats ?? this.maxSeats,
      features: features ?? this.features,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Map<String, bool> _stringBoolMap(Object? value) {
    if (value is! Map) return const {};
    final result = <String, bool>{};
    for (final entry in value.entries) {
      result[entry.key.toString()] = entry.value == true;
    }
    return result;
  }

  static DateTime? _timestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is DateTime) return value;
    return null;
  }
}
