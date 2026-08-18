import 'package:cloud_firestore/cloud_firestore.dart';

/// The role a login identity holds inside its tenant workspace. Uses the
/// canonical role vocabulary (`admin` / `employee`) while still parsing the
/// legacy `company_admin` / `user` values so older index documents keep
/// resolving.
enum TenantIdentityRole {
  companyAdmin,
  user;

  /// The wire value stored in Firestore.
  String get value {
    switch (this) {
      case TenantIdentityRole.companyAdmin:
        return 'admin';
      case TenantIdentityRole.user:
        return 'employee';
    }
  }

  /// Parses a stored value back into a [TenantIdentityRole], or `null`.
  static TenantIdentityRole? fromValue(String? value) {
    switch (value) {
      case 'company_admin':
      case 'companyAdmin':
      case 'admin':
        return TenantIdentityRole.companyAdmin;
      case 'user':
      case 'staff':
      case 'engineer':
      case 'manager':
      case 'employee':
        return TenantIdentityRole.user;
      default:
        return null;
    }
  }
}

/// A login identity record in the Master Firebase control plane.
///
/// Stored under `tenant_users/{email}` (the document id is the lowercased
/// email), this is the pre-login mapping that lets the app resolve which
/// tenant (data plane) Firebase project an email belongs to before any
/// authentication happens. It deliberately contains no credentials — it is
/// only a redirection hint: the actual account lives in the tenant project and
/// the real credential check always happens against that project's Firebase
/// Auth.
///
/// - Written once at provisioning for the ONE Company Admin (by the Super
///   Admin, while authenticated to the Master project).
/// - Written when the Company Admin creates an employee/manager account (the
///   tenant-side write is a best-effort redirect hint, never an access grant).
class TenantIdentity {
  /// The normalized (lowercased) email; also the document id.
  final String email;

  /// The workspace this identity belongs to.
  final String workspaceId;

  /// The role the identity resolves to after login.
  final TenantIdentityRole role;

  /// Optional display name, shown in Super Admin diagnostics.
  final String? name;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TenantIdentity({
    required this.email,
    required this.workspaceId,
    required this.role,
    this.name,
    this.createdAt,
    this.updatedAt,
  });

  factory TenantIdentity.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Tenant identity document ${doc.id} has no data.');
    }
    return TenantIdentity.fromMap(data, doc.id);
  }

  factory TenantIdentity.fromMap(Map<String, dynamic> data, String email) {
    return TenantIdentity(
      email: data['email'] as String? ?? email,
      workspaceId: data['workspaceId'] as String? ?? '',
      role: TenantIdentityRole.fromValue(data['role'] as String?) ??
          TenantIdentityRole.user,
      name: data['name'] as String?,
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'workspaceId': workspaceId,
      'role': role.value,
      if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
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
