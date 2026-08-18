import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/firebase_context.dart';
import '../control_plane_firebase.dart';
import '../models/firebase_project_allocation.dart';

/// CRUD for the pool of pre-created Firebase projects eligible for workspace
/// provisioning.
///
/// Reads and writes the `firebase_project_allocations/{projectId}` collection
/// on the Master Firebase control plane only (via [ControlPlaneFirebase]), so
/// the pool can never be resolved against a tenant (data plane) database.
///
/// The pool is populated by platform ops/automation (see `functions/seed.js`),
/// never by the app itself. [claimByProjectId] reserves a project atomically in
/// a Firestore transaction so two concurrent provisioning runs can never be
/// handed the same project.
class WorkspaceAllocationRepository {
  WorkspaceAllocationRepository({FirebaseContext? context})
      : _context = context ?? ControlPlaneFirebase.instance.context;

  final FirebaseContext _context;

  static const String _collectionName = 'firebase_project_allocations';

  FirebaseFirestore get _firestore => _context.firestore;

  /// Registers (or overwrites) an allocation record for a pre-created project.
  Future<void> add(FirebaseProjectAllocation allocation) async {
    await _firestore
        .collection(_collectionName)
        .doc(allocation.projectId)
        .set(allocation.toMap());
  }

  /// Reads a single allocation by its Google Cloud project id.
  Future<FirebaseProjectAllocation?> getByProjectId(String projectId) async {
    final doc =
        await _firestore.collection(_collectionName).doc(projectId).get();
    return doc.exists ? FirebaseProjectAllocation.fromFirestore(doc) : null;
  }

  /// Every project currently available to be allocated.
  Future<List<FirebaseProjectAllocation>> listAvailable() async {
    final snap = await _firestore
        .collection(_collectionName)
        .where('status', isEqualTo: AllocationStatus.available.value)
        .get();
    return snap.docs.map(FirebaseProjectAllocation.fromFirestore).toList();
  }

  /// Every allocation record in the pool.
  Future<List<FirebaseProjectAllocation>> getAll() async {
    final snap = await _firestore.collection(_collectionName).get();
    return snap.docs.map(FirebaseProjectAllocation.fromFirestore).toList();
  }

  /// Streams every allocation record for live pool monitoring.
  Stream<List<FirebaseProjectAllocation>> streamAll() {
    return _firestore.collection(_collectionName).snapshots().map((snap) =>
        snap.docs.map(FirebaseProjectAllocation.fromFirestore).toList());
  }

  /// Atomically reserves [projectId] for a workspace.
  ///
  /// Returns `true` only when the project was still available and this call
  /// marked it allocated. Runs inside a Firestore transaction so concurrent
  /// claimers re-read the document: the second one sees `allocated` and gets
  /// `false`, guaranteeing a project is never handed to two workspaces.
  Future<bool> claimByProjectId(String projectId) async {
    return _firestore.runTransaction((tx) async {
      final ref = _firestore.collection(_collectionName).doc(projectId);
      final snap = await tx.get(ref);
      if (!snap.exists) return false;
      final allocation = FirebaseProjectAllocation.fromFirestore(snap);
      if (!allocation.isAvailable) return false;
      tx.update(ref, {
        'status': AllocationStatus.allocated.value,
        'allocatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// Links an allocated project to the workspace that owns it.
  ///
  /// Called after the workspace registry entry exists, so the allocation can
  /// be audited back to its workspace.
  Future<void> bindWorkspace(String projectId, String workspaceId) async {
    await _firestore.collection(_collectionName).doc(projectId).update({
      'allocatedWorkspaceId': workspaceId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Returns [projectId] to the pool (rollback path).
  Future<void> release(String projectId) async {
    await _firestore.collection(_collectionName).doc(projectId).update({
      'status': AllocationStatus.available.value,
      'allocatedWorkspaceId': null,
      'allocatedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently removes [projectId] from the pool.
  Future<void> delete(String projectId) async {
    await _firestore.collection(_collectionName).doc(projectId).delete();
  }
}
