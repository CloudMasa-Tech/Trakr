import 'workspace_firebase_config.dart';

/// Payload for workspace provisioning from the Super Admin onboarding flow.
/// Captures everything the platform Super Admin needs to create a brand-new
/// tenant workspace: the workspace identity, the company basic details, the
/// email of the initial Company Admin (who receives login credentials), and the
/// client-side Firebase configuration of the dedicated Firebase project that
/// was created manually in the Firebase Console and uploaded during onboarding.
/// All provisioning is handled client-side via [WorkspaceProvisioningClientService],
/// which runs against the Master Firebase project using only the Firebase Client SDK.
class WorkspaceProvisionRequest {
  /// Display name of the workspace; drives the generated workspace code.
  final String workspaceName;

  final String companyName;
  final String companyPhone;
  final String? companyAddress;
  final String industry;

  /// Email of the initial Company Admin; login credentials are delivered here.
  final String companyAdminEmail;

  /// The client-side Firebase configuration uploaded by the Super Admin for the
  /// workspace's dedicated Firebase project. This is what the workspace is
  /// mapped to — every workspace gets its OWN Firebase project.
  final WorkspaceFirebaseConfig? firebaseConfig;

  /// Google account that owns the dedicated Firebase project. Optional in the
  /// current flow (the project is created manually in the Console, not by the
  /// app); kept as an audit hint.
  final String? targetFirebaseAccountEmail;

  /// Client-generated id of the `workspace_provision_logs` audit doc that
  /// streams provisioning progress while the callable runs.
  final String? logId;

  const WorkspaceProvisionRequest({
    required this.workspaceName,
    required this.companyName,
    required this.companyPhone,
    this.companyAddress,
    required this.industry,
    required this.companyAdminEmail,
    this.firebaseConfig,
    this.targetFirebaseAccountEmail,
    this.logId,
  });

  Map<String, dynamic> toJson() {
    return {
      'workspaceName': workspaceName,
      'companyName': companyName,
      'companyPhone': companyPhone,
      if (companyAddress != null && companyAddress!.isNotEmpty)
        'companyAddress': companyAddress,
      'industry': industry,
      'companyAdminEmail': companyAdminEmail,
      if (firebaseConfig != null) 'firebaseConfig': firebaseConfig!.toMap(),
      if (targetFirebaseAccountEmail != null &&
          targetFirebaseAccountEmail!.trim().isNotEmpty)
        'targetFirebaseAccountEmail': targetFirebaseAccountEmail,
      if (logId != null && logId!.isNotEmpty) 'logId': logId,
    };
  }

  WorkspaceProvisionRequest copyWith({String? logId}) {
    return WorkspaceProvisionRequest(
      workspaceName: workspaceName,
      companyName: companyName,
      companyPhone: companyPhone,
      companyAddress: companyAddress,
      industry: industry,
      companyAdminEmail: companyAdminEmail,
      firebaseConfig: firebaseConfig,
      targetFirebaseAccountEmail: targetFirebaseAccountEmail,
      logId: logId ?? this.logId,
    );
  }
}
