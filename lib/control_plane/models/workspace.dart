import 'package:cloud_firestore/cloud_firestore.dart';

import 'subscription.dart';
import 'workspace_firebase_config.dart';
import 'workspace_status.dart';

/// A tenant workspace registered in the Master Firebase control plane.
///
/// This is the registry entry that ties a workspace to its dedicated tenant
/// (data plane) Firebase project. It contains only platform-level data
/// (identity, firebase configuration, status, subscription) — never operational
/// data such as employees, attendance, leave, payroll or QR.
class Workspace {
  /// Stable unique id; also used as the tenant [FirebaseApp] name.
  final String workspaceId;

  /// Human-friendly unique code/slug, e.g. `green-hospital`.
  final String workspaceCode;

  /// URL slug used in web dashboard routes, e.g.
  /// `/workspace/cloudmasa-innovation-lab/dashboard`. Same value as
  /// [workspaceCode]; kept as its own field so the routing layer reads an
  /// explicit `workspaceSlug` from the registry/company records.
  final String workspaceSlug;

  /// Registered legal/company name.
  final String companyName;

  /// The Google Cloud project id of the workspace's tenant Firebase project.
  final String firebaseProjectId;

  /// Credentials/options for the tenant Firebase project.
  final WorkspaceFirebaseConfig firebaseConfig;

  /// Whether the tenant Firebase project has been mapped to this workspace by
  /// the Super Admin (client config uploaded, validated and confirmed).
  final bool firebaseConfigured;

  /// Lifecycle status of the workspace.
  final WorkspaceStatus status;

  /// How far the tenant project provisioning has progressed.
  final WorkspaceOnboardingStatus onboardingStatus;

  /// Billing subscription attached to the workspace.
  final Subscription subscription;

  /// Optional support contact shown for this workspace.
  final String? supportEmail;

  /// Company admin email (captured during onboarding).
  final String? adminEmail;

  /// Company admin name (derived from email during onboarding).
  final String? adminName;

  /// Company phone number (captured during onboarding).
  final String? companyPhone;

  /// Company industry (captured during onboarding).
  final String? industry;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Workspace({
    required this.workspaceId,
    required this.workspaceCode,
    this.workspaceSlug = '',
    required this.companyName,
    required this.firebaseProjectId,
    required this.firebaseConfig,
    this.firebaseConfigured = false,
    this.status = WorkspaceStatus.provisioning,
    this.onboardingStatus = WorkspaceOnboardingStatus.pending,
    this.subscription = const Subscription.empty(),
    this.supportEmail,
    this.adminEmail,
    this.adminName,
    this.companyPhone,
    this.industry,
    this.createdAt,
    this.updatedAt,
  });

  factory Workspace.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Workspace document ${doc.id} has no data.');
    }
    return Workspace.fromMap(data, doc.id);
  }

  factory Workspace.fromMap(Map<String, dynamic> data, String workspaceId) {
    return Workspace(
      workspaceId: data['workspaceId'] as String? ?? workspaceId,
      workspaceCode: data['workspaceCode'] as String? ?? '',
      workspaceSlug: data['workspaceSlug'] as String? ??
          (data['workspaceCode'] as String? ?? ''),
      companyName: data['companyName'] as String? ?? '',
      firebaseProjectId: data['firebaseProjectId'] as String? ?? '',
      firebaseConfig: WorkspaceFirebaseConfig.fromMap(
        Map<String, dynamic>.from(
          (data['firebaseConfig'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      firebaseConfigured: data['firebaseConfigured'] as bool? ??
          _configCarriesCredentials(data['firebaseConfig']),
      status: WorkspaceStatus.fromValue(data['status'] as String?) ??
          WorkspaceStatus.provisioning,
      onboardingStatus: WorkspaceOnboardingStatus.fromValue(
              data['onboardingStatus'] as String?) ??
          WorkspaceOnboardingStatus.pending,
      subscription: Subscription.fromMap(
        Map<String, dynamic>.from(
          (data['subscription'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      supportEmail: data['supportEmail'] as String?,
      adminEmail: data['adminEmail'] as String?,
      adminName: data['adminName'] as String?,
      companyPhone: data['companyPhone'] as String?,
      industry: data['industry'] as String?,
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workspaceId': workspaceId,
      'workspaceCode': workspaceCode,
      'workspaceSlug': workspaceSlug,
      'companyName': companyName,
      'firebaseProjectId': firebaseProjectId,
      'firebaseConfig': firebaseConfig.toMap(),
      'firebaseConfigured': firebaseConfigured,
      'status': status.value,
      'onboardingStatus': onboardingStatus.value,
      'subscription': subscription.toMap(),
      if (supportEmail != null) 'supportEmail': supportEmail,
      if (adminEmail != null) 'adminEmail': adminEmail,
      if (adminName != null) 'adminName': adminName,
      if (companyPhone != null) 'companyPhone': companyPhone,
      if (industry != null) 'industry': industry,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The name used for the tenant [FirebaseApp] (see FirebaseManager).
  String get appName => workspaceId;

  Workspace copyWith({
    String? workspaceId,
    String? workspaceCode,
    String? workspaceSlug,
    String? companyName,
    String? firebaseProjectId,
    WorkspaceFirebaseConfig? firebaseConfig,
    bool? firebaseConfigured,
    WorkspaceStatus? status,
    WorkspaceOnboardingStatus? onboardingStatus,
    Subscription? subscription,
    String? supportEmail,
    String? adminEmail,
    String? adminName,
    String? companyPhone,
    String? industry,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Workspace(
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceCode: workspaceCode ?? this.workspaceCode,
      workspaceSlug: workspaceSlug ?? this.workspaceSlug,
      companyName: companyName ?? this.companyName,
      firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
      firebaseConfig: firebaseConfig ?? this.firebaseConfig,
      firebaseConfigured: firebaseConfigured ?? this.firebaseConfigured,
      status: status ?? this.status,
      onboardingStatus: onboardingStatus ?? this.onboardingStatus,
      subscription: subscription ?? this.subscription,
      supportEmail: supportEmail ?? this.supportEmail,
      adminEmail: adminEmail ?? this.adminEmail,
      adminName: adminName ?? this.adminName,
      companyPhone: companyPhone ?? this.companyPhone,
      industry: industry ?? this.industry,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _timestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is DateTime) return value;
    return null;
  }

  /// Whether a stored `firebaseConfig` map carries usable credentials. Used as
  /// a fallback so workspaces provisioned before `firebaseConfigured` was added
  /// still report configured correctly.
  static bool _configCarriesCredentials(dynamic rawConfig) {
    if (rawConfig is! Map) return false;
    final config = WorkspaceFirebaseConfig.fromMap(
      Map<String, dynamic>.from(rawConfig),
    );
    return config.isValid;
  }
}
