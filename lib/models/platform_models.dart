import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _timestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

int _asInt(dynamic value) => (value is num) ? value.toInt() : 0;
double _asDouble(dynamic value) => (value is num) ? value.toDouble() : 0.0;
String _asString(dynamic value) => (value as String?) ?? '';

/// Aggregated, read-frugal platform counters maintained in a single
/// `platformStats/dashboard` document. Mutations on the Super Admin modules
/// update these counters instead of scanning whole collections (Spark plan).
class PlatformStats {
  final int totalCompanies;
  final int activeCompanies;
  final int suspendedCompanies;
  final int pendingApprovals;
  final int totalUsers;
  final int activeUsersToday;
  final int activeSubscriptions;
  final int trialCompanies;
  final int expiringSubscriptions;
  final int planFree;
  final int planStarter;
  final int planPro;
  final int planEnterprise;
  final double monthlyRevenue;
  final double totalRevenue;
  final int openTickets;
  final int closedTickets;
  final int failedLogins;
  final int lockedAccounts;
  final int suspiciousLogins;
  final int passwordResets;
  final Map<String, int> companiesByMonth;
  final Map<String, double> revenueByMonth;
  final DateTime? lastUpdated;

  const PlatformStats({
    this.totalCompanies = 0,
    this.activeCompanies = 0,
    this.suspendedCompanies = 0,
    this.pendingApprovals = 0,
    this.totalUsers = 0,
    this.activeUsersToday = 0,
    this.activeSubscriptions = 0,
    this.trialCompanies = 0,
    this.expiringSubscriptions = 0,
    this.planFree = 0,
    this.planStarter = 0,
    this.planPro = 0,
    this.planEnterprise = 0,
    this.monthlyRevenue = 0,
    this.totalRevenue = 0,
    this.openTickets = 0,
    this.closedTickets = 0,
    this.failedLogins = 0,
    this.lockedAccounts = 0,
    this.suspiciousLogins = 0,
    this.passwordResets = 0,
    this.companiesByMonth = const {},
    this.revenueByMonth = const {},
    this.lastUpdated,
  });

  int get paidSubscriptions => planStarter + planPro + planEnterprise;

  int get totalTickets => openTickets + closedTickets;

  factory PlatformStats.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final companiesByMonth = <String, int>{};
    final rawCompanies = data['companiesByMonth'];
    if (rawCompanies is Map) {
      rawCompanies.forEach((k, v) => companiesByMonth['$k'] = _asInt(v));
    }
    final revenueByMonth = <String, double>{};
    final rawRevenue = data['revenueByMonth'];
    if (rawRevenue is Map) {
      rawRevenue.forEach((k, v) => revenueByMonth['$k'] = _asDouble(v));
    }
    return PlatformStats(
      totalCompanies: _asInt(data['totalCompanies']),
      activeCompanies: _asInt(data['activeCompanies']),
      suspendedCompanies: _asInt(data['suspendedCompanies']),
      pendingApprovals: _asInt(data['pendingApprovals']),
      totalUsers: _asInt(data['totalUsers']),
      activeUsersToday: _asInt(data['activeUsersToday']),
      activeSubscriptions: _asInt(data['activeSubscriptions']),
      trialCompanies: _asInt(data['trialCompanies']),
      expiringSubscriptions: _asInt(data['expiringSubscriptions']),
      planFree: _asInt(data['planFree']),
      planStarter: _asInt(data['planStarter']),
      planPro: _asInt(data['planPro']),
      planEnterprise: _asInt(data['planEnterprise']),
      monthlyRevenue: _asDouble(data['monthlyRevenue']),
      totalRevenue: _asDouble(data['totalRevenue']),
      openTickets: _asInt(data['openTickets']),
      closedTickets: _asInt(data['closedTickets']),
      failedLogins: _asInt(data['failedLogins']),
      lockedAccounts: _asInt(data['lockedAccounts']),
      suspiciousLogins: _asInt(data['suspiciousLogins']),
      passwordResets: _asInt(data['passwordResets']),
      companiesByMonth: companiesByMonth,
      revenueByMonth: revenueByMonth,
      lastUpdated: _timestamp(data['lastUpdated']),
    );
  }
}

/// Lightweight platform activity entry shown on the dashboard feed. Written
/// only by Super Admin actions (and reconciliation) to stay write-frugal.
class PlatformActivityEvent {
  final String id;
  final String type;
  final String title;
  final String? detail;
  final String? companyId;
  final String? companyName;
  final String? actorEmail;
  final DateTime timestamp;

  const PlatformActivityEvent({
    required this.id,
    required this.type,
    required this.title,
    this.detail,
    this.companyId,
    this.companyName,
    this.actorEmail,
    required this.timestamp,
  });

  factory PlatformActivityEvent.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return PlatformActivityEvent(
      id: doc.id,
      type: _asString(data['type']),
      title: _asString(data['title']),
      detail: data['detail'] as String?,
      companyId: data['companyId'] as String?,
      companyName: data['companyName'] as String?,
      actorEmail: data['actorEmail'] as String?,
      timestamp: _timestamp(data['timestamp']) ?? DateTime.now(),
    );
  }
}

/// Structured, immutable audit trail of Super Admin actions.
class AuditEvent {
  final String id;
  final String category;
  final String action;
  final String actorEmail;
  final String? actorRole;
  final String? targetType;
  final String? targetId;
  final String? targetName;
  final Map<String, dynamic> changes;
  final DateTime timestamp;

  const AuditEvent({
    required this.id,
    required this.category,
    required this.action,
    required this.actorEmail,
    this.actorRole,
    this.targetType,
    this.targetId,
    this.targetName,
    this.changes = const {},
    required this.timestamp,
  });

  factory AuditEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AuditEvent(
      id: doc.id,
      category: _asString(data['category']),
      action: _asString(data['action']),
      actorEmail: _asString(data['actorEmail']),
      actorRole: data['actorRole'] as String?,
      targetType: data['targetType'] as String?,
      targetId: data['targetId'] as String?,
      targetName: data['targetName'] as String?,
      changes: (data['changes'] is Map)
          ? Map<String, dynamic>.from(data['changes'] as Map)
          : const {},
      timestamp: _timestamp(data['timestamp']) ?? DateTime.now(),
    );
  }

  /// A short human-readable description of the change, used in log listings.
  String get detail {
    if (changes.isEmpty) {
      return '${_human(action)}${targetName == null ? '' : ' · $targetName'}';
    }
    final parts = changes.entries
        .map((e) => '${_human(e.key)}: ${e.value ?? '—'}')
        .join(', ');
    return '${_human(action)} · $parts';
  }

  static String _human(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

/// A single platform user directory row (`users` doc).
class PlatformUserRow {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? companyId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  const PlatformUserRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.companyId,
    required this.isActive,
    this.createdAt,
    this.lastLoginAt,
  });

  factory PlatformUserRow.fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return PlatformUserRow(
      uid: doc.id,
      name: _asString(data['name']),
      email: _asString(data['email']),
      phone: _asString(data['phone']),
      role: _asString(data['role']),
      companyId: data['companyId'] as String?,
      isActive: data['isActive'] ?? data['status'] != 'inactive',
      createdAt: _timestamp(data['createdAt']),
      lastLoginAt: _timestamp(data['lastLoginAt']),
    );
  }
}

/// Platform-wide announcement / broadcast message.
class AnnouncementModel {
  final String id;
  final String title;
  final String body;
  final String status;
  final String audience;
  final String createdBy;
  final DateTime? publishAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.audience,
    required this.createdBy,
    this.publishAt,
    this.expiresAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory AnnouncementModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AnnouncementModel(
      id: doc.id,
      title: _asString(data['title']),
      body: _asString(data['body']),
      status: _asString(data['status']),
      audience: _asString(data['audience']),
      createdBy: _asString(data['createdBy']),
      publishAt: _timestamp(data['publishAt']),
      expiresAt: _timestamp(data['expiresAt']),
      createdAt: _timestamp(data['createdAt']) ?? DateTime.now(),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }
}

/// Billing invoice generated from the Super Admin console.
class Invoice {
  final String id;
  final String companyId;
  final String companyName;
  final String description;
  final double amount;
  final String currency;
  final String status;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final DateTime createdAt;

  const Invoice({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.description,
    required this.amount,
    required this.currency,
    required this.status,
    this.issueDate,
    this.dueDate,
    this.paidAt,
    required this.createdAt,
  });

  factory Invoice.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Invoice(
      id: doc.id,
      companyId: _asString(data['companyId']),
      companyName: _asString(data['companyName']),
      description: _asString(data['description']),
      amount: _asDouble(data['amount']),
      currency: _asString(data['currency']),
      status: _asString(data['status']),
      issueDate: _timestamp(data['issueDate']),
      dueDate: _timestamp(data['dueDate']),
      paidAt: _timestamp(data['paidAt']),
      createdAt: _timestamp(data['createdAt']) ?? DateTime.now(),
    );
  }
}

/// Payment received and recorded from the Super Admin console.
class Payment {
  final String id;
  final String companyId;
  final String companyName;
  final double amount;
  final String currency;
  final String method;
  final String? reference;
  final String? invoiceId;
  final DateTime? paidAt;
  final DateTime createdAt;

  const Payment({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.amount,
    required this.currency,
    required this.method,
    this.reference,
    this.invoiceId,
    this.paidAt,
    required this.createdAt,
  });

  factory Payment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Payment(
      id: doc.id,
      companyId: _asString(data['companyId']),
      companyName: _asString(data['companyName']),
      amount: _asDouble(data['amount']),
      currency: _asString(data['currency']),
      method: _asString(data['method']),
      reference: data['reference'] as String?,
      invoiceId: data['invoiceId'] as String?,
      paidAt: _timestamp(data['paidAt']),
      createdAt: _timestamp(data['createdAt']) ?? DateTime.now(),
    );
  }
}

/// Security event captured from platform sign-ins and admin actions.
class SecurityEvent {
  final String id;
  final String type;
  final String email;
  final String? detail;
  final DateTime timestamp;

  const SecurityEvent({
    required this.id,
    required this.type,
    required this.email,
    this.detail,
    required this.timestamp,
  });

  factory SecurityEvent.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return SecurityEvent(
      id: doc.id,
      type: _asString(data['type']),
      email: _asString(data['email']),
      detail: data['detail'] as String?,
      timestamp: _timestamp(data['timestamp']) ?? DateTime.now(),
    );
  }
}

/// Platform-level configuration stored under `app_config/platform`.
class PlatformSettings {
  final String platformName;
  final String supportEmail;
  final String supportPhone;
  final String currency;
  final String defaultTimezone;
  final bool requireTwoFactorAuth;
  final int sessionTimeoutMinutes;
  final String maintenanceMode;
  final bool allowCompanySignups;

  const PlatformSettings({
    this.platformName = 'TRAKR',
    this.supportEmail = '',
    this.supportPhone = '',
    this.currency = 'USD',
    this.defaultTimezone = 'UTC',
    this.requireTwoFactorAuth = false,
    this.sessionTimeoutMinutes = 60,
    this.maintenanceMode = 'off',
    this.allowCompanySignups = true,
  });

  factory PlatformSettings.fromMap(Map<String, dynamic> data) {
    return PlatformSettings(
      platformName: _asString(data['platformName']).isEmpty
          ? 'TRAKR'
          : _asString(data['platformName']),
      supportEmail: _asString(data['supportEmail']),
      supportPhone: _asString(data['supportPhone']),
      currency: _asString(data['currency']).isEmpty
          ? 'USD'
          : _asString(data['currency']),
      defaultTimezone: _asString(data['defaultTimezone']).isEmpty
          ? 'UTC'
          : _asString(data['defaultTimezone']),
      requireTwoFactorAuth: data['requireTwoFactorAuth'] ?? false,
      sessionTimeoutMinutes: data['sessionTimeoutMinutes'] is num
          ? (data['sessionTimeoutMinutes'] as num).toInt()
          : 60,
      maintenanceMode: _asString(data['maintenanceMode']),
      allowCompanySignups: data['allowCompanySignups'] ?? true,
    );
  }
}
