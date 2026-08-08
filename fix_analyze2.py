with open('lib/screens/super_admin/client_onboarding_module.dart', 'r') as f:
    content = f.read()

content = content.replace("import '../../theme/app_theme_colors.dart';\n", "")
content = content.replace("import 'workspace_details_screen.dart';\n", "")

with open('lib/screens/super_admin/client_onboarding_module.dart', 'w') as f:
    f.write(content)
