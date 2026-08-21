import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../firebase/firebase_context.dart';
import '../control_plane_firebase.dart';
import '../models/workspace.dart';

/// CRUD for workspace registry entries in the Master Firebase control plane.
///
/// Reads and writes the `workspaces/{workspaceId}` collection on the master
/// project only. Because [ControlPlaneFirebase] is bound to the default
/// project regardless of the active tenant, workspace records can never be
/// resolved against a tenant (data plane) database.
class WorkspaceRepository {
  WorkspaceRepository({FirebaseContext? context})
      : _context = context ?? ControlPlaneFirebase.instance.context;

  final FirebaseContext _context;

  static const String _collectionName = 'workspaces';

  FirebaseFirestore get _firestore => _context.firestore;

  void _validateFirebaseProjectConsistency(Map<String, dynamic> data) {
    final firebaseProjectId = (data['firebaseProjectId'] as String? ?? data['projectId'] as String?)?.trim() ?? '';
    final firebaseConfig = data['firebaseConfig'];
    final configProjectId = firebaseConfig is Map
        ? (firebaseConfig['projectId'] as String?)?.trim() ?? ''
        : '';
    if (firebaseProjectId.isNotEmpty &&
        configProjectId.isNotEmpty &&
        firebaseProjectId != configProjectId) {
      throw StateError(
        'Workspace Firebase project mismatch: firebaseProjectId="$firebaseProjectId'
        '" does not match firebaseConfig.projectId="$configProjectId".',
      );
    }
  }

  /// A fresh auto-generated id for a new workspace registry entry.
  Future<String> nextId() async {
    return _firestore.collection(_collectionName).doc().id;
  }

  /// Reads a single workspace by its stable id.
  Future<Workspace?> getById(String workspaceId) async {
    final doc =
        await _firestore.collection(_collectionName).doc(workspaceId).get();
    return doc.exists ? Workspace.fromFirestore(doc) : null;
  }

  /// Streams a single workspace for live registry updates.
  Stream<Workspace?> streamById(String workspaceId) {
    return _firestore
        .collection(_collectionName)
        .doc(workspaceId)
        .snapshots()
        .map((doc) => doc.exists ? Workspace.fromFirestore(doc) : null);
  }

  /// Reads a single workspace by its unique human-friendly code.
  Future<Workspace?> getByCode(String workspaceCode) async {
    final snap = await _firestore
        .collection(_collectionName)
        .where('workspaceCode', isEqualTo: workspaceCode)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Workspace.fromFirestore(snap.docs.first);
  }

  /// Every workspace whose `adminEmail` matches [adminEmail] (the login
  /// identity index). Used by the provisioning retry to resume a failed run
  /// instead of creating a duplicate workspace.
  Future<List<Workspace>> getByAdminEmail(String adminEmail) async {
    final normalized = adminEmail.trim().toLowerCase();
    if (normalized.isEmpty) return const <Workspace>[];
    final snap = await _firestore
        .collection(_collectionName)
        .where('adminEmail', isEqualTo: normalized)
        .limit(20)
        .get();
    return snap.docs.map(Workspace.fromFirestore).toList();
  }

  /// Lists every workspace, newest first.
  Future<List<Workspace>> getAll() async {
    final snap = await _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(Workspace.fromFirestore).toList();
  }

  /// Streams every workspace, newest first.
  Stream<List<Workspace>> streamAll() {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Workspace.fromFirestore).toList());
  }

  /// Persists a workspace registry entry (create or full overwrite).
  Future<void> create(Workspace workspace) async {
    await createDocument(workspace.workspaceId, workspace.toMap());
  }

  /// Creates a workspace document without allowing an existing project binding
  /// to be replaced. This also closes the read-then-set race during onboarding.
  Future<void> createDocument(
    String workspaceId,
    Map<String, dynamic> data,
  ) async {
    _validateFirebaseProjectConsistency(data);
    final ref = _firestore.collection(_collectionName).doc(workspaceId);
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      if (current.exists) {
        final currentData = current.data() ?? <String, dynamic>{};
        final oldProjectId = (currentData['firebaseProjectId'] as String? ??
                currentData['projectId'] as String? ?? '')
            .trim();
        final newProjectId =
            (data['firebaseProjectId'] as String? ?? '').trim();
        if (oldProjectId.isNotEmpty &&
            newProjectId.isNotEmpty &&
            oldProjectId != newProjectId) {
          final message =
              'BLOCKED: attempted to overwrite firebaseProjectId for workspace '
              '$workspaceId from $oldProjectId to $newProjectId '
              '- this would orphan a GCP project';
          debugPrint(message);
          throw StateError(message);
        }
      }
      transaction.set(ref, data);
    });
  }

  /// Applies a partial update to a workspace entry. Always stamps `updatedAt`.
  Future<void> update(String workspaceId, Map<String, dynamic> updates) async {
    final ref = _firestore.collection(_collectionName).doc(workspaceId);
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final currentData = current.data() ?? <String, dynamic>{};
      final oldProjectId = (currentData['firebaseProjectId'] as String? ??
              currentData['projectId'] as String? ?? '')
          .trim();
      final requestedProjectId = updates.containsKey('firebaseProjectId')
          ? (updates['firebaseProjectId'] as String? ?? '').trim()
          : oldProjectId;
      if (oldProjectId.isNotEmpty &&
          requestedProjectId.isNotEmpty &&
          requestedProjectId != oldProjectId) {
        final message =
            'BLOCKED: attempted to overwrite firebaseProjectId for workspace '
            '$workspaceId from $oldProjectId to $requestedProjectId '
            '- this would orphan a GCP project';
        debugPrint(message);
        throw StateError(message);
      }

      final merged = <String, dynamic>{
        ...currentData,
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      _validateFirebaseProjectConsistency(merged);
      transaction.update(ref, merged);
    });
  }

  /// Deletes a workspace registry entry.
  Future<void> delete(String workspaceId) async {
    await _firestore.collection(_collectionName).doc(workspaceId).delete();
  }

  /// Whether [workspaceCode] is not yet used by any workspace.
  Future<bool> isCodeAvailable(String workspaceCode) async {
    final snap = await _firestore
        .collection(_collectionName)
        .where('workspaceCode', isEqualTo: workspaceCode)
        .limit(1)
        .get();
    return snap.docs.isEmpty;
  }

  /// Whether a Firebase project is already mapped to a workspace.
  ///
  /// Each workspace must have its OWN Firebase project, so the same
  /// `firebaseProjectId` can never be bound to two workspaces. [excludeId] lets
  /// a workspace keep its own mapping when it is being re-checked (e.g. a
  /// config re-upload edit) without tripping over itself.
  Future<bool> isFirebaseProjectMapped(
    String firebaseProjectId, {
    String? excludeId,
  }) async {
    if (firebaseProjectId.trim().isEmpty) return false;
    final snap = await _firestore
        .collection(_collectionName)
        .where('firebaseProjectId', isEqualTo: firebaseProjectId)
        .limit(2)
        .get();
    for (final doc in snap.docs) {
      if (doc.id != excludeId) return true;
    }
    return false;
  }
}
