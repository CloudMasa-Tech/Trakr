import re

with open('lib/screens/super_admin/client_onboarding_module.dart', 'r') as f:
    content = f.read()

# Replace Company with Workspace
content = content.replace("import '../../models/company.dart';", "import '../../control_plane/models/workspace.dart';\nimport '../../control_plane/services/workspace_registry_service.dart';")
content = content.replace("import '../../services/company_analytics_service.dart';", "")
content = content.replace("import '../../services/company_service.dart';", "")
content = content.replace("import 'company_details_screen.dart';", "import 'workspace_details_screen.dart';")

content = content.replace("final _companyService = CompanyService();", "final _registry = WorkspaceRegistryService();")
content = content.replace("final _analytics = CompanyAnalyticsService();", "")

content = content.replace("Map<String, int> _usersByCompany = const {};", "")
content = content.replace("Map<String, String> _adminByCompany = const {};", "")
content = content.replace("bool _loadingDirectory = true;", "")

content = content.replace("super.initState();\n    _loadDirectory();", "super.initState();")

content = content.replace("""  Future<void> _loadDirectory() async {
    final usersByCompany = await _analytics.getUserCountByCompany();
    final adminByCompany = await _analytics.getCompanyAdminMap();
    if (!mounted) return;
    setState(() {
      _usersByCompany = usersByCompany;
      _adminByCompany = adminByCompany;
      _loadingDirectory = false;
    });
  }""", "")

content = content.replace("if (created && mounted) _loadDirectory();", "if (created && mounted) setState((){});")

content = content.replace("""  Future<void> _viewCompany(Company company) async {
    await CompanyDetailsScreen.show(
      context,
      companyId: company.id,
      initial: company,
    );
    if (mounted) _loadDirectory();
  }""", """  Future<void> _viewWorkspace(Workspace workspace) async {
    await WorkspaceDetailsScreen.show(
      context,
      workspaceId: workspace.workspaceId,
      initial: workspace,
    );
  }""")

content = content.replace("""  Future<void> _editCompany(Company company) async {
    final saved = await showCoEditCompanyDialog(
      context,
      company,
      _companyService,
    );
    if (saved && mounted) {
      _snack('Company updated successfully.');
    }
  }""", "")

content = content.replace("""  Future<void> _toggleActive(Company company) async {
    final target = !company.isActive;
    final confirmed = await _confirm(
      title: target ? 'Activate company?' : 'Suspend company?',
      message: target
          ? '${company.name} will be reactivated and its users can sign back in.'
          : '${company.name} will be suspended. Its users will no longer be '
              'able to sign in. You can reactivate it anytime.',
      confirmLabel: target ? 'Activate' : 'Suspend',
      destructive: !target,
    );
    if (!confirmed || !mounted) return;
    try {
      await _companyService.setCompanyActive(company.id, isActive: target);
      if (!mounted) return;
      _snack(target
          ? '${company.name} is now active.'
          : '${company.name} has been suspended.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update status: $e', error: true);
    }
  }""", "")

content = content.replace("""  Future<void> _deleteCompany(Company company) async {
    final confirmed = await _confirm(
      title: 'Delete ${company.name}?',
      message: 'This permanently deletes the company and its directory users '
          'and admins. This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _analytics.deleteCompany(company.id);
      if (!mounted) return;
      _loadDirectory();
      _snack('${company.name} was deleted.');
    } catch (e) {
      if (!mounted) return;
      _snack('Delete failed: $e', error: true);
    }
  }""", "")

content = content.replace("""  Widget _buildTable(List<Company> companies, bool loading) {
    return CoSectionCard(
      title: 'Companies',
      subtitle: 'All client companies. Create, view, edit, suspend, or delete.',
      icon: Icons.apartment_rounded,
      child: PlatformCompaniesTable(
        companies: companies,
        usersByCompany: _usersByCompany,
        adminByCompany: _adminByCompany,
        loading: loading || _loadingDirectory,
        onView: _viewCompany,
        onEdit: _editCompany,
        onToggleActive: _toggleActive,
        onDelete: _deleteCompany,
      ),
    );
  }""", """  Widget _buildTable(List<Workspace> workspaces, bool loading) {
    // Omitting table here as it's fully managed in Workspaces tab now.
    return const SizedBox();
  }""")

content = content.replace("List<Company>", "List<Workspace>")
content = content.replace("_companyService.streamAllCompanies()", "_registry.streamWorkspaces()")
content = content.replace("final companies = snapshot.data ?? const <Company>[];", "final workspaces = snapshot.data ?? const <Workspace>[];")
content = content.replace("_buildHeader(companies, loading)", "_buildHeader(workspaces, loading)")
content = content.replace("_buildTable(companies, loading)", "_buildTable(workspaces, loading)")


with open('lib/screens/super_admin/client_onboarding_module.dart', 'w') as f:
    f.write(content)
