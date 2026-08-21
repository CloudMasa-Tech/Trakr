/// Payload for workspace provisioning from the Super Admin onboarding flow.
/// Captures everything the platform Super Admin needs to create a brand-new
/// tenant workspace and resume a prior attempt safely.
class WorkspaceProvisionRequest {
  final String workspaceName;
  final String companyName;
  final String companyPhone;
  final String? companyAddress;
  final String industry;
  final String companyAdminEmail;
  final String? existingWorkspaceId;
  final String? logId;

  const WorkspaceProvisionRequest({
    required this.workspaceName,
    required this.companyName,
    required this.companyPhone,
    this.companyAddress,
    required this.industry,
    required this.companyAdminEmail,
    this.existingWorkspaceId,
    this.logId,
  });

  Map<String, dynamic> toJson() {
    return {
      "workspaceName": workspaceName,
      "companyName": companyName,
      "companyPhone": companyPhone,
      if (companyAddress != null && companyAddress!.isNotEmpty)
        "companyAddress": companyAddress,
      "industry": industry,
      "companyAdminEmail": companyAdminEmail,
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
      existingWorkspaceId: existingWorkspaceId,
      logId: logId ?? this.logId,
    );
  }
}
