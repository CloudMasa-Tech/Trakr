import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/firebase_context.dart';
import '../../firebase/firebase_manager.dart';
import '../control_plane_firebase.dart';
import '../models/tenant_identity.dart';

/// CRUD for the Master control-plane login identity index.
///
/// Reads and writes the `tenant_users/{email}` collection on the Master project
/// only (via [ControlPlaneFirebase]), so identities can never be resolved
/// against a tenant (data plane) database.
///
/// The index is what lets the login flow answer "which tenant project does
/// this email belong to?" before any credentials are exchanged. It is a
/// redirection hint only: actual accounts and credentials live in the tenant
/// projects.
class TenantIdentityRepository {
  TenantIdentityRepository({FirebaseContext? context})
      : _context = context ?? ControlPlaneFirebase.instance.context;

  final FirebaseContext _context;

  static const String _collectionName = 'tenant_users';

  FirebaseFirestore get _firestore => _context.firestore;

  /// Reads the identity bound to [email] (case-insensitive), or `null` when
  /// the email has no entry in the index.
  Future<TenantIdentity?> getByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final doc =
        await _firestore.collection(_collectionName).doc(normalized).get();
    return doc.exists ? TenantIdentity.fromDocument(doc) : null;
  }

  /// Creates or refreshes the identity entry for [email].
  Future<void> upsert({
    required String email,
    required String workspaceId,
    required TenantIdentityRole role,
    String? name,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || workspaceId.isEmpty) return;
    await _firestore.collection(_collectionName).doc(normalized).set(
          TenantIdentity(
            email: normalized,
            workspaceId: workspaceId,
            role: role,
            name: name,
          ).toMap(),
        );
  }

  /// Removes an identity entry (e.g. when a workspace is decommissioned).
  Future<void> remove(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    try {
      await _firestore.collection(_collectionName).doc(normalized).delete();
    } catch (_) {
      // Best-effort cleanup; a stale index entry only redirects a login to a
      // workspace that will reject the credentials anyway.
    }
  }

  /// Best-effort registration of a tenant member in the Master login index.
  ///
  /// Called right after a Company Admin creates an employee/manager account in
  /// a tenant (data plane) project. When [context] is bound to the default
  /// (Master) project there is no tenant, so this is a no-op. Failures never
  /// propagate: the index is a redirection hint, not a gate — the real account
  /// and credential check live in the tenant project.
  static Future<void> registerFromTenantContext({
    required FirebaseContext context,
    required String email,
    required TenantIdentityRole role,
    String? name,
  }) async {
    try {
      if (context.app.name == FirebaseManager.instance.defaultApp.name) return;
      final workspaceId = context.app.name;
      if (workspaceId.isEmpty) return;
      await TenantIdentityRepository().upsert(
        email: email,
        workspaceId: workspaceId,
        role: role,
        name: name,
      );
    } catch (_) {
      // Best-effort by design; account creation must not fail because the
      // control-plane index write was rejected.
    }
  }
}
