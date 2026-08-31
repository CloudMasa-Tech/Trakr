import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../../firebase/firebase_context.dart';
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
    final doc = await _firestore
        .collection(_collectionName)
        .doc(normalized)
        .get()
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException(
                'Login identity lookup timed out reading tenant_users/$normalized');
          },
        );
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

  /// Registers a tenant member in the Master login index BY CALLING the
  /// master-project `registerTenantMember` Cloud Function. The tenant client
  /// cannot write the index directly — Master Firestore rules only allow
  /// `isSuperAdmin()` to write `tenant_users`, and the tenant caller is not
  /// signed in to the Master project.
  ///
  /// AWAITED and non-swallowing: a failure throws, so invite/onboarding can
  /// never report success while the member would still be unable to log in.
  /// No-op when [context] is itself the Master (control-plane) project.
  static Future<void> registerFromTenantContext({
    required FirebaseContext context,
    required String email,
    required TenantIdentityRole role,
    String? name,
  }) async {
    final tenantProjectId = context.app.options.projectId.trim();
    final masterProjectId =
        ControlPlaneFirebase.instance.context.app.options.projectId.trim();
    if (tenantProjectId.isEmpty ||
        masterProjectId.isEmpty ||
        tenantProjectId == masterProjectId) {
      return;
    }

    final currentUser = context.auth.currentUser;
    if (currentUser == null) {
      throw StateError(
          'Cannot register login identity: no signed-in user on the tenant '
          'project.');
    }
    final idToken = (await currentUser.getIdToken(true)) ?? '';
    if (idToken.isEmpty) {
      throw StateError(
          'Cannot register login identity: failed to refresh ID token.');
    }

    final url = Uri.parse(
      'https://us-central1-$masterProjectId'
      '.cloudfunctions.net/registerTenantMember',
    );
    final response = await http
        .post(
          url,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(<String, dynamic>{
            'data': <String, dynamic>{
              'projectId': tenantProjectId,
              'email': email.trim().toLowerCase(),
              'role': role.name,
              if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
            },
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to register login identity (HTTP ${response.statusCode}): '
        '${response.body}',
      );
    }
  }
}
