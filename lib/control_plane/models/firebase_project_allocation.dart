import 'package:cloud_firestore/cloud_firestore.dart';

import 'workspace_firebase_config.dart';

/// Whether a pre-created Firebase project in the allocation pool is usable.
///
/// Projects are created by platform ops/automation, never by the app itself.
/// The pool only records that a ready-made project exists and whether it has
/// already been handed to a workspace.
enum AllocationStatus {
  /// Not reserved by any workspace; safe to allocate.
  available,

  /// Reserved by a workspace during (or after) provisioning.
  allocated;

  /// The wire value stored in Firestore.
  String get value {
    switch (this) {
      case AllocationStatus.available:
        return 'available';
      case AllocationStatus.allocated:
        return 'allocated';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case AllocationStatus.available:
        return 'Available';
      case AllocationStatus.allocated:
        return 'Allocated';
    }
  }

  /// Parses a stored value back into an [AllocationStatus], or `null` for
  /// unknown values.
  static AllocationStatus? fromValue(String? value) {
    switch (value) {
      case 'available':
        return AllocationStatus.available;
      case 'allocated':
        return AllocationStatus.allocated;
      default:
        return null;
    }
  }
}

/// A pre-created Firebase project eligible for workspace provisioning.
///
/// These records live in the Master Firebase control plane under
/// `firebase_project_allocations/{projectId}` (the document id is the Google
/// Cloud project id). Each entry carries the full [WorkspaceFirebaseConfig] of
/// the ready-made project; when a workspace is provisioned, that config is
/// copied into the `workspaces/{workspaceId}` registry document so the tenant
/// app can be initialized with it later.
///
/// The app never creates Firebase projects — ops/automation do — but it does
/// reserve (claim) one atomically so two workspaces can never share a project.
class FirebaseProjectAllocation {
  const FirebaseProjectAllocation({
    required this.projectId,
    required this.firebaseConfig,
    this.status = AllocationStatus.available,
    this.label,
    this.region,
    this.allocatedWorkspaceId,
    this.allocatedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// The Google Cloud project id (also the Firestore document id).
  final String projectId;

  /// Credentials/options for the pre-created Firebase project.
  final WorkspaceFirebaseConfig firebaseConfig;

  final AllocationStatus status;

  /// Optional human label for the project (e.g. which region/tier it is).
  final String? label;

  /// Optional GCP region the project was created in.
  final String? region;

  /// The workspace this project was handed to, once allocated.
  final String? allocatedWorkspaceId;

  final DateTime? allocatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether this project is not yet reserved and safe to allocate.
  bool get isAvailable => status == AllocationStatus.available;

  factory FirebaseProjectAllocation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Allocation document ${doc.id} has no data.');
    }
    return FirebaseProjectAllocation.fromMap(data, doc.id);
  }

  factory FirebaseProjectAllocation.fromMap(
    Map<String, dynamic> data,
    String projectId,
  ) {
    return FirebaseProjectAllocation(
      projectId: data['projectId'] as String? ?? projectId,
      firebaseConfig: WorkspaceFirebaseConfig.fromMap(
        Map<String, dynamic>.from(
          (data['firebaseConfig'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      status: AllocationStatus.fromValue(data['status'] as String?) ??
          AllocationStatus.available,
      label: data['label'] as String?,
      region: data['region'] as String?,
      allocatedWorkspaceId: data['allocatedWorkspaceId'] as String?,
      allocatedAt: _timestamp(data['allocatedAt']),
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'projectId': projectId,
      'firebaseConfig': firebaseConfig.toMap(),
      'status': status.value,
      if (label != null) 'label': label,
      if (region != null) 'region': region,
      if (allocatedWorkspaceId != null)
        'allocatedWorkspaceId': allocatedWorkspaceId,
      if (allocatedAt != null) 'allocatedAt': Timestamp.fromDate(allocatedAt!),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  FirebaseProjectAllocation copyWith({
    String? projectId,
    WorkspaceFirebaseConfig? firebaseConfig,
    AllocationStatus? status,
    String? label,
    String? region,
    String? allocatedWorkspaceId,
    DateTime? allocatedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FirebaseProjectAllocation(
      projectId: projectId ?? this.projectId,
      firebaseConfig: firebaseConfig ?? this.firebaseConfig,
      status: status ?? this.status,
      label: label ?? this.label,
      region: region ?? this.region,
      allocatedWorkspaceId: allocatedWorkspaceId ?? this.allocatedWorkspaceId,
      allocatedAt: allocatedAt ?? this.allocatedAt,
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
}
