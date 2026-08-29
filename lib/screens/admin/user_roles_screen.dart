// lib/screens/admin/user_roles_screen.dart

import 'package:flutter/material.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/permission.dart';
import '../../models/user_role.dart';
import '../../services/access_control_service.dart';
import '../../theme/app_theme_colors.dart';

class UserRolesScreen extends StatelessWidget {
  const UserRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final colors = AppColors.of(context);

    return SafeArea(
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 14 : 24,
            22,
            isMobile ? 14 : 24,
            110,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User Roles Management',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Create roles, assign module permissions, and bind users to them. '
                'System roles are protected and cannot be modified.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textMuted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              const _RolesTable(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RolesTable extends StatefulWidget {
  const _RolesTable();

  @override
  State<_RolesTable> createState() => _RolesTableState();
}

class _RolesTableState extends State<_RolesTable> {
  final _accessControl = AccessControlService();
  final _horizontalScrollCtrl = ScrollController();

  late final Stream<List<UserRole>> _rolesStream;
  late final Stream<List<AppPermission>> _permissionsStream;

  bool _canManageRoles = false;

  @override
  void initState() {
    super.initState();
    _rolesStream = _accessControl.getAllRoles();
    _permissionsStream = _accessControl.getAllPermissions();
    _resolvePermission();
  }

  @override
  void dispose() {
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  /// Only users holding the `roles.manage` permission can create, edit, delete
  /// or assign roles. Resolution mirrors AccessControlService so the UI never
  /// shows a control the Firestore rules would reject.
  Future<void> _resolvePermission() async {
    final uid = FirebaseContextProvider.current.auth.currentUser?.uid;
    var canManage = false;
    if (uid != null) {
      canManage = await _accessControl
          .hasPermission(userId: uid, permissionId: 'roles.manage');
    }
    if (!mounted) return;
    setState(() => _canManageRoles = canManage);
  }

  Future<void> _createRole() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _RoleEditorDialog(),
    );
    if (created == true && mounted) {
      _showSnack('Role created.');
    }
  }

  Future<void> _editRole(UserRole role) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _RoleEditorDialog(role: role),
    );
    if (updated == true && mounted) {
      _showSnack('Role updated.');
    }
  }

  Future<void> _manageUsers(UserRole role) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _AssignUsersDialog(role: role),
    );
  }

  Future<void> _deleteRole(UserRole role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.dark.border),
        ),
        title: Text(
          'Delete "${role.name}"?',
          style: TextStyle(color: AppColors.dark.textPrimary),
        ),
        content: Text(
          'Users assigned to this role will keep their direct permissions but '
          'lose any that came from the role. This cannot be undone.',
          style: TextStyle(color: AppColors.dark.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.dark.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dark.error,
              foregroundColor: AppColors.dark.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _accessControl.deleteRole(role.id);
      if (mounted) _showSnack('Role "${role.name}" deleted.');
    } catch (e) {
      if (mounted) _showSnack('Failed to delete role: $e', error: true);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.dark.error : AppColors.dark.focus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return StreamBuilder<List<UserRole>>(
      stream: _rolesStream,
      builder: (context, rolesSnap) {
        final roles = rolesSnap.data ?? const <UserRole>[];
        return StreamBuilder<List<AppPermission>>(
          stream: _permissionsStream,
          builder: (context, permsSnap) {
            final permissions = permsSnap.data ?? const <AppPermission>[];
            final loading = rolesSnap.connectionState == ConnectionState.waiting;

            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A6B7897),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${roles.length} role${roles.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _canManageRoles ? _createRole : null,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New Role'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.onPrimary,
                            disabledBackgroundColor: colors.border,
                            disabledForegroundColor: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF1C3F50)),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    )
                  else if (roles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        children: [
                          Icon(Icons.admin_panel_settings_outlined,
                              size: 40, color: colors.iconMuted),
                          const SizedBox(height: 12),
                          Text('No roles yet. Create your first role.',
                              style: TextStyle(color: colors.textMuted)),
                        ],
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                            if (constraints.maxWidth < 760) {
                              return _buildRoleCards(roles, permissions);
                            }
                            return _buildRoleTable(roles, permissions, constraints);
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoleTable(List<UserRole> roles, List<AppPermission> permissions,
      BoxConstraints constraints) {
    final colors = AppColors.of(context);
    final permissionById = {for (final p in permissions) p.id: p};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _horizontalScrollCtrl,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 760,
          maxWidth: constraints.maxWidth.isFinite && constraints.maxWidth > 760
              ? constraints.maxWidth
              : 760,
        ),
        child: Column(
          children: [
            // Header row
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: colors.tableHeader,
              child: Row(
                children: [
                  _headerCell(colors, 'Role', flex: 3),
                  _headerCell(colors, 'Level', flex: 1),
                  _headerCell(colors, 'Type', flex: 2),
                  _headerCell(colors, 'Permissions', flex: 5),
                  _headerCell(colors, 'Actions', flex: 3, alignEnd: true),
                ],
              ),
            ),
            for (var i = 0; i < roles.length; i++)
              Container(
                color: i.isEven ? colors.tableRow : colors.tableRowAlt,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roles[i].name,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (roles[i].description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              roles[i].description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.textMuted, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        roles[i].level.toString(),
                        style: TextStyle(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: roles[i].isSystem
                          ? _badge(colors, 'System', colors.focus)
                          : _badge(colors, 'Custom', colors.success),
                    ),
                    Expanded(
                      flex: 5,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (roles[i].permissionIds.isEmpty)
                            Text('No permissions',
                                style:
                                    TextStyle(color: colors.textMuted)),
                          for (final pid in roles[i].permissionIds.take(4))
                            _permissionChip(
                                colors, permissionById[pid]?.name ?? pid),
                          if (roles[i].permissionIds.length > 4)
                            _permissionChip(
                              colors,
                              '+${roles[i].permissionIds.length - 4} more',
                              muted: true,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Assign users',
                            onPressed:
                                _canManageRoles && roles[i].name != 'Super Admin'
                                    ? () => _manageUsers(roles[i])
                                    : null,
                            icon: Icon(Icons.people_outline_rounded,
                                color: colors.iconSecondary, size: 20),
                          ),
                          if (!roles[i].isSystem && _canManageRoles) ...[
                            IconButton(
                              tooltip: 'Edit role',
                              onPressed: () => _editRole(roles[i]),
                              icon: Icon(Icons.edit_rounded,
                                  color: colors.iconSecondary, size: 20),
                            ),
                            IconButton(
                              tooltip: 'Delete role',
                              onPressed: () => _deleteRole(roles[i]),
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: colors.error, size: 20),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCards(List<UserRole> roles, List<AppPermission> permissions) {
    final colors = AppColors.of(context);
    final permissionById = {for (final p in permissions) p.id: p};

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final role in roles)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.tableRow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          role.name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (role.isSystem)
                        _badge(colors, 'System', colors.focus)
                      else
                        _badge(colors, 'Custom', colors.success),
                    ],
                  ),
                  if (role.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(role.description,
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final pid in role.permissionIds.take(5))
                        _permissionChip(
                            colors, permissionById[pid]?.name ?? pid),
                      if (role.permissionIds.length > 5)
                        _permissionChip(
                          colors,
                          '+${role.permissionIds.length - 5} more',
                          muted: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _canManageRoles && role.name != 'Super Admin'
                                ? () => _manageUsers(role)
                                : null,
                        icon: const Icon(Icons.people_outline_rounded,
                            size: 16),
                        label: const Text('Assign'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.focus,
                          side: BorderSide(color: colors.focus),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const Spacer(),
                      if (!role.isSystem && _canManageRoles) ...[
                        IconButton(
                          tooltip: 'Edit role',
                          onPressed: () => _editRole(role),
                          icon: Icon(Icons.edit_rounded,
                              color: colors.iconSecondary, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Delete role',
                          onPressed: () => _deleteRole(role),
                          icon: Icon(Icons.delete_outline_rounded,
                              color: colors.error, size: 20),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(AppColors colors, String label,
      {int flex = 1, bool alignEnd = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _badge(AppColors colors, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _permissionChip(AppColors colors, String label, {bool muted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: muted
            ? colors.border.withValues(alpha: 0.35)
            : colors.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? colors.textMuted : colors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoleEditorDialog extends StatefulWidget {
  final UserRole? role;

  const _RoleEditorDialog({this.role});

  @override
  State<_RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<_RoleEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _levelCtrl;
  late final Set<String> _selected;
  bool _isManagerial = false;
  bool _canBeReportingManager = false;
  bool _submitting = false;
  final _accessControl = AccessControlService();
  late final Stream<List<AppPermission>> _permissionsStream;

  bool get _isEditing => widget.role != null;

  @override
  void initState() {
    super.initState();
    _permissionsStream = _accessControl.getAllPermissions();
    _nameCtrl = TextEditingController(text: widget.role?.name ?? '');
    _descCtrl =
        TextEditingController(text: widget.role?.description ?? '');
    _levelCtrl = TextEditingController(
        text: widget.role?.level.toString() ?? '10');
    _isManagerial = widget.role?.isManagerial ?? false;
    _canBeReportingManager = _initialCanBeReportingManager(widget.role);
    _selected = {...?widget.role?.permissionIds};
  }

  /// Defaults the reporting-manager flag to true for the built-in
  /// admin / company_admin / manager roles (and any role already marked
  /// managerial), so existing behaviour is preserved even before the
  /// backfill script has written the field. Custom roles default to false.
  bool _initialCanBeReportingManager(UserRole? role) {
    if (role == null) return false;
    if (role.canBeReportingManager) return true;
    final id = role.id.toLowerCase();
    if (id == 'admin' ||
        id == 'company_admin' ||
        id == 'manager' ||
        role.isManagerial) {
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _levelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.admin_panel_settings_outlined,
                        color: colors.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing
                              ? 'Edit "${widget.role!.name}"'
                              : 'Create role',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isEditing
                              ? 'Adjust the permissions granted by this role.'
                              : 'Name the role and pick the module permissions.',
                          style: TextStyle(
                              color: colors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 14),
                        cursorColor: colors.focus,
                        decoration: InputDecoration(
                          labelText: 'Role name',
                          labelStyle:
                              TextStyle(color: colors.textMuted),
                          hintText: 'e.g. Team Lead',
                          hintStyle: TextStyle(color: colors.textMuted),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: colors.focus, width: 1.5),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Role name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 2,
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 14),
                        cursorColor: colors.focus,
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          labelStyle:
                              TextStyle(color: colors.textMuted),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: colors.focus, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _levelCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 14),
                        cursorColor: colors.focus,
                        decoration: InputDecoration(
                          labelText: 'Hierarchy Level',
                          labelStyle:
                              TextStyle(color: colors.textMuted),
                          hintText: 'e.g. 10',
                          hintStyle: TextStyle(color: colors.textMuted),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: colors.focus, width: 1.5),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Level is required';
                          }
                          final level = int.tryParse(value.trim());
                          if (level == null || level < 1 || level > 100) {
                            return 'Enter a number between 1 and 100';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            'Managerial role',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Marks this as a leadership role that can oversee a team.',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 12),
                          ),
                          value: _isManagerial,
                          onChanged: _submitting
                              ? null
                              : (v) => setState(() => _isManagerial = v),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            'Eligible as reporting manager',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Users with this role appear in the "Reports to" dropdown when onboarding employees.',
                            style: TextStyle(
                                color: colors.textMuted, fontSize: 12),
                          ),
                          value: _canBeReportingManager,
                          onChanged: _submitting
                              ? null
                              : (v) =>
                                  setState(() => _canBeReportingManager = v),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Permissions',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select the modules and actions this role can perform.',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      StreamBuilder<List<AppPermission>>(
                        stream: _permissionsStream,
                        builder: (context, snap) {
                          final permissions = snap.data ?? const <AppPermission>[];
                          final grouped = <String, List<AppPermission>>{};
                          for (final p in permissions) {
                            grouped.putIfAbsent(p.category, () => []);
                            grouped[p.category]!.add(p);
                          }
                          final categories = grouped.keys.toList()..sort();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final category in categories)
                                _buildPermissionGroup(category, grouped[category]!),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: Color(0xFF93A9B9))),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_submitting ? 'Saving…' : 'Save role'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionGroup(String category, List<AppPermission> permissions) {
    final colors = AppColors.of(context);
    final label = _categoryLabel(category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          for (final p in permissions)
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                value: _selected.contains(p.id),
                onChanged: _submitting
                    ? null
                    : (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(p.id);
                          } else {
                            _selected.remove(p.id);
                          }
                        }),
                title: Text(
                  p.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: p.description.isNotEmpty
                    ? Text(
                        p.description,
                        style: TextStyle(
                            color: colors.textMuted, fontSize: 11),
                      )
                    : null,
                activeColor: colors.focus,
                checkColor: colors.background,
              ),
            ),
        ],
      ),
    );
  }

  String _categoryLabel(String category) {
    const labels = {
      'attendance': 'Attendance',
      'team': 'Team',
      'leave': 'Leave',
      'permission': 'Permission to Exit',
      'reports': 'Reports & Analytics',
      'payroll': 'Payroll',
      'users': 'User Management',
      'company': 'Company Settings',
      'notifications': 'Notifications',
      'qr': 'QR Management',
    };
    return labels[category] ??
        category[0].toUpperCase() + category.substring(1);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final name = _nameCtrl.text.trim();
      final description = _descCtrl.text.trim();
      final level = int.parse(_levelCtrl.text.trim());
      if (_isEditing) {
        await _accessControl.updateRole(
          roleId: widget.role!.id,
          name: name,
          description: description,
          permissionIds: _selected.toList(),
          level: level,
          isManagerial: _isManagerial,
          canBeReportingManager: _canBeReportingManager,
        );
      } else {
        await _accessControl.createRole(
          name: name,
          description: description,
          permissionIds: _selected.toList(),
          level: level,
          isManagerial: _isManagerial,
          canBeReportingManager: _canBeReportingManager,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save role: $e'),
          backgroundColor: AppColors.dark.error,
        ),
      );
    }
  }
}

class _AssignUsersDialog extends StatefulWidget {
  final UserRole role;

  const _AssignUsersDialog({required this.role});

  @override
  State<_AssignUsersDialog> createState() => _AssignUsersDialogState();
}

class _AssignUsersDialogState extends State<_AssignUsersDialog> {
  final _accessControl = AccessControlService();
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _assign(String userId, String roleId) async {
    try {
      await _accessControl.assignRoleToUser(userId: userId, roleId: roleId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Role assignment updated.'),
            backgroundColor: AppColors.dark.focus,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign role: $e'),
          backgroundColor: AppColors.dark.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.group_add_rounded,
                        color: colors.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assign "${widget.role.name}"',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select users to receive this role.',
                          style: TextStyle(
                              color: colors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                cursorColor: colors.focus,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  hintStyle: TextStyle(color: colors.textMuted),
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.focus),
                  filled: true,
                  fillColor: colors.background,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.focus, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _accessControl.getAllUsersWithRoles(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final users = (snap.data ?? const <Map<String, dynamic>>[])
                      .where((u) {
                    final q = _query.trim().toLowerCase();
                    if (q.isEmpty) return true;
                    return '${u['name']} ${u['email']}'
                        .toLowerCase()
                        .contains(q);
                  }).toList();

                  if (users.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('No users found.',
                            style: TextStyle(color: colors.textMuted)),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, i) {
                      final user = users[i];
                      final userId = user['id'] as String? ?? '';
                      final name = user['name'] as String? ?? 'Unknown';
                      final email = user['email'] as String? ?? '';
                      final currentRole = user['roleId'] as String?;
                      final isAssigned = currentRole == widget.role.id;
                      return CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: isAssigned,
                        activeColor: colors.focus,
                        checkColor: colors.background,
                        onChanged: (checked) {
                          if (checked == true) {
                            _assign(userId, widget.role.id);
                          } else {
                            _accessControl.unassignRoleFromUser(userId);
                          }
                        },
                        title: Text(
                          name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          email,
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 11),
                        ),
                        secondary: _avatar(name, colors),
                      );
                    },
                  );
                },
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'A user can hold one role; assigning replaces the previous one.',
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done',
                        style: TextStyle(color: Color(0xFF22D3EE))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String name, AppColors colors) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: colors.primary.withValues(alpha: 0.18),
      child: Text(
        letter,
        style: TextStyle(
          color: colors.primary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
