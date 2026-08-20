/// Payload for workspace provisioning from the Super Admin onboarding flow.
/// Captures everything the platform Super Admin needs to create a brand-new
/// tenant workspace: the workspace identity, the company basic details, and
/// the email of the initial Company Admin (who receives login credentials).
/// Firebase project creation and configuration are handled automatically by
/// [WorkspaceProvisioningClientService] and the backend provisioning flow.
class WorkspaceProvisionRequest {
  /// Display name of the workspace; drives the generated workspace code.
  final String workspaceName;

  final String companyName;
  final String companyPhone;
  final String? companyAddress;
  final String industry;

  /// Email of the initial Company Admin; login credentials are delivered here.
  final String companyAdminEmail;

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
      logId: logId ?? this.logId,
    );
  }
}
