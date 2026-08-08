import 'package:cloud_firestore/cloud_firestore.dart';

class Company {
  final String id;
  final String name;
  final String? domain;
  final String? email;
  final String? supportEmail;
  final String? phone;
  final String? address;
  final String? logoUrl;
  final String? website;
  final String? industry;
  final String? companySize;
  final String? country;
  final String? timezone;
  final String? primaryColorHex;
  final bool isActive;
  final String plan;
  final String subscriptionStatus;
  final String billingCycle;
  final DateTime? renewsAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastActiveAt;

  const Company({
    required this.id,
    required this.name,
    this.domain,
    this.email,
    this.supportEmail,
    this.phone,
    this.address,
    this.logoUrl,
    this.website,
    this.industry,
    this.companySize,
    this.country,
    this.timezone,
    this.primaryColorHex,
    this.isActive = true,
    this.plan = 'Free',
    this.subscriptionStatus = 'active',
    this.billingCycle = 'Monthly',
    this.renewsAt,
    this.createdAt,
    this.updatedAt,
    this.lastActiveAt,
  });

  factory Company.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Company(
      id: doc.id,
      name: data['name'] ?? '',
      domain: data['domain'],
      email: data['email'],
      supportEmail: data['supportEmail'],
      phone: data['phone'],
      address: data['address'],
      logoUrl: data['logoUrl'] ?? data['companyLogoUrl'],
      website: data['website'],
      industry: data['industry'],
      companySize: data['companySize'],
      country: data['country'],
      timezone: data['timezone'],
      primaryColorHex: data['primaryColorHex'],
      isActive: data['isActive'] ?? true,
      plan: data['plan'] ?? 'Free',
      subscriptionStatus: data['subscriptionStatus'] ?? 'active',
      billingCycle: data['billingCycle'] ?? 'Monthly',
      renewsAt: _timestamp(data['renewsAt']),
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
      lastActiveAt: _timestamp(data['lastActiveAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'domain': domain,
      'email': email,
      'supportEmail': supportEmail,
      'phone': phone,
      'address': address,
      'logoUrl': logoUrl,
      'website': website,
      'industry': industry,
      'companySize': companySize,
      'country': country,
      'timezone': timezone,
      'primaryColorHex': primaryColorHex,
      'isActive': isActive,
      'plan': plan,
      'subscriptionStatus': subscriptionStatus,
      'billingCycle': billingCycle,
      if (renewsAt != null) 'renewsAt': Timestamp.fromDate(renewsAt!),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastActiveAt': lastActiveAt != null
          ? Timestamp.fromDate(lastActiveAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _timestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}
