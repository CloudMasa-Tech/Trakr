import 'workspace_firebase_config.dart';

/// Payload for workspace provisioning from the Super Admin onboarding flow.
/// Captures everything the platform Super Admin needs to create a brand-new
/// tenant workspace and resume a prior attempt safely.
///
/// The Firebase project is NOT created by TRAKR. The Super Admin creates it
/// manually in the Firebase Console (enabling Authentication → Email/Password
/// and Firestore in Native mode), then supplies its project id and web app
/// configuration here. Provisioning only configures the existing project
/// (rules deployment, initial collections, admin user, workspace metadata).
class WorkspaceProvisionRequest {
  final String workspaceName;
  final String companyName;
  final String companyPhone;
  final String? companyAddress;
  final String industry;
  final String companyAdminEmail;

  /// The id of the ALREADY-CREATED Firebase project to bind this workspace to.
  final String firebaseProjectId;

  /// The client-side web app configuration of [firebaseProjectId], captured
  /// through the onboarding form's validated Firebase config upload field.
  final WorkspaceFirebaseConfig? firebaseConfig;

  /// The Firebase billing plan the Super Admin selected for the manually
  /// created project: 'spark' or 'blaze'. Recorded for tracking/reference
  /// purposes only — TRAKR never changes the actual plan via API.
  final String firebasePlan;

  final String? existingWorkspaceId;
  final String? logId;

  const WorkspaceProvisionRequest({
    required this.workspaceName,
    required this.companyName,
    required this.companyPhone,
    this.companyAddress,
    required this.industry,
    required this.companyAdminEmail,
    this.firebaseProjectId = '',
    this.firebaseConfig,
    this.firebasePlan = '',
    this.existingWorkspaceId,
    this.logId,
  });

  /// Valid values for [firebasePlan].
  static const Set<String> validFirebasePlans = <String>{'spark', 'blaze'};

  Map<String, dynamic> toJson() {
    return {
      "workspaceName": workspaceName,
      "companyName": companyName,
      "companyPhone": companyPhone,
      if (companyAddress != null && companyAddress!.isNotEmpty)
        "companyAddress": companyAddress,
      "industry": industry,
      "companyAdminEmail": companyAdminEmail,
      if (firebaseProjectId.isNotEmpty) "firebaseProjectId": firebaseProjectId,
      if (firebaseConfig != null) "firebaseConfig": firebaseConfig!.toMap(),
      if (firebasePlan.isNotEmpty) "firebasePlan": firebasePlan,
      if (existingWorkspaceId != null && existingWorkspaceId!.isNotEmpty)
        "existingWorkspaceId": existingWorkspaceId,
      if (logId != null && logId!.isNotEmpty) "logId": logId,
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
      firebaseProjectId: firebaseProjectId,
      firebaseConfig: firebaseConfig,
      firebasePlan: firebasePlan,
      existingWorkspaceId: existingWorkspaceId,
      logId: logId ?? this.logId,
    );
  }
}
