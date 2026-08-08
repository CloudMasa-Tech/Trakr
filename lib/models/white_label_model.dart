// lib/models/white_label_model.dart

import 'package:flutter/material.dart';

class WhiteLabelModel {
  static const String defaultCompanyName = 'QR Attendances';

  final String companyName;
  final String primaryColorHex;
  final String customDomain;
  final String supportEmail;
  final String? logoUrl;
  final DateTime? updatedAt;

  const WhiteLabelModel({
    required this.companyName,
    required this.primaryColorHex,
    required this.customDomain,
    required this.supportEmail,
    this.logoUrl,
    this.updatedAt,
  });

  static const WhiteLabelModel empty = WhiteLabelModel(
    companyName: defaultCompanyName,
    primaryColorHex: '0F766E',
    customDomain: '',
    supportEmail: '',
    logoUrl: null,
  );
  Color get primaryColor {
    try {
      final hex = primaryColorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF0F766E);
    }
  }

  String get displayCompanyName {
    final normalized = companyName.trim();
    if (normalized.isEmpty ||
        normalized == 'My Company' ||
        normalized == 'My Comapny' ||
        normalized == 'AttendQR') {
      return defaultCompanyName;
    }
    return normalized;
  }

  factory WhiteLabelModel.fromMap(Map<String, dynamic> map) {
    return WhiteLabelModel(
      companyName: map['companyName'] ?? defaultCompanyName,
      primaryColorHex: map['primaryColorHex'] ?? '0F766E',
      customDomain: map['customDomain'] ?? '',
      supportEmail: map['supportEmail'] ?? '',
      logoUrl: map['logoUrl'],
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
              : (map['updatedAt'] as dynamic).toDate())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'companyName': companyName,
      'primaryColorHex': primaryColorHex,
      'customDomain': customDomain,
      'supportEmail': supportEmail,
      'logoUrl': logoUrl,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  WhiteLabelModel copyWith({
    String? companyName,
    String? primaryColorHex,
    String? customDomain,
    String? supportEmail,
    String? logoUrl,
  }) {
    return WhiteLabelModel(
      companyName: companyName ?? this.companyName,
      primaryColorHex: primaryColorHex ?? this.primaryColorHex,
      customDomain: customDomain ?? this.customDomain,
      supportEmail: supportEmail ?? this.supportEmail,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }
}
