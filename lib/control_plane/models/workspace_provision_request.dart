/// Payload for the backend `provisionWorkspace` callable.
///
/// Captures everything the platform Super Admin needs to create a brand-new
/// tenant workspace: the workspace identity, the company basic details, the
/// email of the initial Company Admin (who receives login credentials), and the
/// Google account under which the dedicated Firebase project is created.
class WorkspaceProvisionRequest {
  /// Display name of the workspace; drives the generated workspace code and the
  /// new Firebase project id/display name.
  final String workspaceName;

  final String companyName;
  final String companyPhone;
  final String? companyAddress;
  final String industry;

  /// Email of the initial Company Admin; login credentials are delivered here.
  final String companyAdminEmail;

  /// Google account that owns the dedicated Firebase project being created.
  final String targetFirebaseAccountEmail;

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
    required this.targetFirebaseAccountEmail,
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
      targetFirebaseAccountEmail: targetFirebaseAccountEmail,
      logId: logId ?? this.logId,
    );
  }
}
