import re

# Fix client_onboarding_add_screen.dart
with open('lib/screens/super_admin/client_onboarding_add_screen.dart', 'r') as f:
    content = f.read()
content = content.replace("import '../../control_plane/services/tenant_provisioner.dart';\n", "")
content = content.replace("import '../../control_plane/services/workspace_provisioning_service.dart';\n", "")
with open('lib/screens/super_admin/client_onboarding_add_screen.dart', 'w') as f:
    f.write(content)

# Fix client_onboarding_module.dart
with open('lib/screens/super_admin/client_onboarding_module.dart', 'r') as f:
    content = f.read()

# Remove _viewWorkspace
view_workspace_pattern = r"  Future<void> _viewWorkspace\(Workspace workspace\) async \{\n    await WorkspaceDetailsScreen\.show\(\n      context,\n      workspaceId: workspace\.workspaceId,\n      initial: workspace,\n    \);\n  \}\n\n"
content = re.sub(view_workspace_pattern, "", content)

# Remove _confirm
confirm_pattern = r"  Future<bool> _confirm\(\{\n    required String title,\n    required String message,\n    required String confirmLabel,\n    bool destructive = false,\n  \}\) async \{[\s\S]*?return result == true;\n  \}\n\n"
content = re.sub(confirm_pattern, "", content)

# Remove _snack
snack_pattern = r"  void _snack\(String message, \{bool error = false\}\) \{[\s\S]*?\}\n\n"
content = re.sub(snack_pattern, "", content)

with open('lib/screens/super_admin/client_onboarding_module.dart', 'w') as f:
    f.write(content)

