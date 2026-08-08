import re

with open('lib/screens/super_admin/dashboard_module.dart', 'r') as f:
    content = f.read()

# 1. Update imports
content = content.replace(
    "import '../../models/company.dart';",
    "import '../../control_plane/models/workspace.dart';\nimport '../../control_plane/services/workspace_registry_service.dart';"
)
content = content.replace("import '../../services/company_analytics_service.dart';\n", "")
content = content.replace("import '../../services/company_service.dart';\n", "")
content = content.replace("import 'company_details_screen.dart';", "import 'workspace_details_screen.dart';")

# 2. Update service instantiations
content = content.replace(
    "final _companyService = CompanyService();\n  final _analytics = CompanyAnalyticsService();",
    "final _registry = WorkspaceRegistryService();"
)

# 3. Update seed variables
content = content.replace(
    "Map<String, String> _adminByCompany = const {};\n  bool _reconciling = false;",
    "bool _reconciling = false;"
)
content = content.replace(
    "List<Company> _seedCompanies = const [];",
    "List<Workspace> _seedWorkspaces = const [];"
)

# 4. Update bootstrap
bootstrap_old = """      final results = await Future.wait<Object>([
        _traced(
          'READ platformStats/dashboard',
          _platform.getStats(),
        ),
        _traced(
          'READ companies (streamAllCompanies)',
          _companyService
              .streamAllCompanies()
              .timeout(_bootstrapTimeout)
              .first,
        ),
        _traced(
          'READ activity_logs (streamActivity)',
          _platform.streamActivity(limit: 10).timeout(_bootstrapTimeout).first,
        ),
        _traced(
          'READ users+admins (getCompanyAdminMap)',
          _analytics.getCompanyAdminMap(),
        ),
      ]).timeout(_bootstrapTimeout);
      if (!mounted) return;
      setState(() {
        _seedStats = results[0] as PlatformStats;
        _seedCompanies = results[1] as List<Company>;
        _seedActivity = results[2] as List<PlatformActivityEvent>;
        _adminByCompany = results[3] as Map<String, String>;
        _boot = _BootStatus.loaded;
      });"""

bootstrap_new = """      final results = await Future.wait<Object>([
        _traced(
          'READ platformStats/dashboard',
          _platform.getStats(),
        ),
        _traced(
          'READ workspaces (streamWorkspaces)',
          _registry
              .streamWorkspaces()
              .timeout(_bootstrapTimeout)
              .first,
        ),
        _traced(
          'READ activity_logs (streamActivity)',
          _platform.streamActivity(limit: 10).timeout(_bootstrapTimeout).first,
        ),
      ]).timeout(_bootstrapTimeout);
      if (!mounted) return;
      setState(() {
        _seedStats = results[0] as PlatformStats;
        _seedWorkspaces = results[1] as List<Workspace>;
        _seedActivity = results[2] as List<PlatformActivityEvent>;
        _boot = _BootStatus.loaded;
      });"""
content = content.replace(bootstrap_old, bootstrap_new)

# 5. Update _viewCompany to _viewWorkspace
content = content.replace(
    "Future<void> _viewCompany(Company company) async {\n    await CompanyDetailsScreen.show(\n      context,\n      companyId: company.id,\n      initial: company,\n    );\n  }",
    "Future<void> _viewWorkspace(Workspace workspace) async {\n    await WorkspaceDetailsScreen.show(\n      context,\n      workspaceId: workspace.workspaceId,\n      initial: workspace,\n    );\n  }"
)

# 6. Update _buildRecentlyOnboarded
onboarded_old = """StreamBuilder<List<Company>>(
        stream: _companyService.streamAllCompanies(),
        initialData: _seedCompanies,
        builder: (context, snapshot) {"""
onboarded_new = """StreamBuilder<List<Workspace>>(
        stream: _registry.streamWorkspaces(),
        initialData: _seedWorkspaces,
        builder: (context, snapshot) {"""
content = content.replace(onboarded_old, onboarded_new)

content = content.replace(
    "final companies = snapshot.data ?? _seedCompanies;",
    "final workspaces = snapshot.data ?? _seedWorkspaces;"
)
content = content.replace(
    "if (loading && companies.isEmpty) return const CoInlineLoading();",
    "if (loading && workspaces.isEmpty) return const CoInlineLoading();"
)
content = content.replace(
    "if (companies.isEmpty) {",
    "if (workspaces.isEmpty) {"
)

content = content.replace(
    "final recent = companies.take(5).toList();",
    "final recent = workspaces.take(5).toList();"
)

content = content.replace(
    "onTap: () => _viewCompany(recent[i]),",
    "onTap: () => _viewWorkspace(recent[i]),"
)

content = content.replace(
    "CoCompanyAvatar(\n                          name: recent[i].name,\n                          logoUrl: recent[i].logoUrl,\n                          size: 34,\n                        ),",
    "CoCompanyAvatar(\n                          name: recent[i].companyName,\n                          logoUrl: null,\n                          size: 34,\n                        ),"
)

content = content.replace(
    "Text(\n                                recent[i].name,",
    "Text(\n                                recent[i].companyName,"
)

content = content.replace(
    "_adminByCompany[recent[i].id] ?? '—',",
    "recent[i].supportEmail ?? '—',"
)


with open('lib/screens/super_admin/dashboard_module.dart', 'w') as f:
    f.write(content)
