import 'package:cloud_firestore/cloud_firestore.dart';

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
    await _firestore
        .collection(_collectionName)
        .doc(workspace.workspaceId)
        .set(workspace.toMap());
  }

  /// Applies a partial update to a workspace entry. Always stamps `updatedAt`.
  Future<void> update(String workspaceId, Map<String, dynamic> updates) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .collection(_collectionName)
        .doc(workspaceId)
        .update(updates);
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
}
