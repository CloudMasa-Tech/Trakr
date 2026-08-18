// lib/screens/admin/designations_screen.dart

import 'package:flutter/material.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/designation.dart';
import '../../services/access_control_service.dart';
import '../../services/designation_service.dart';
import '../../theme/app_theme_colors.dart';

class DesignationsScreen extends StatelessWidget {
  const DesignationsScreen({super.key});

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
                'Designations Management',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Create and manage the designation titles shown in the '
                'onboarding flow. Designations are scoped to this company.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textMuted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              const _DesignationsTable(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesignationsTable extends StatefulWidget {
  const _DesignationsTable();

  @override
  State<_DesignationsTable> createState() => _DesignationsTableState();
}

class _DesignationsTableState extends State<_DesignationsTable> {
  final _designationService = DesignationService();
  final _accessControl = AccessControlService();
  final _horizontalScrollCtrl = ScrollController();

  bool _canManageDesignations = false;

  @override
  void initState() {
    super.initState();
    _resolvePermission();
  }

  @override
  void dispose() {
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  /// Only users holding the `roles.manage` permission can create, edit, delete
  /// or assign roles. Resolution mirrors the roles screen so the UI never
  /// shows a control the Firestore rules would reject.
  Future<void> _resolvePermission() async {
    final uid = FirebaseContextProvider.current.auth.currentUser?.uid;
    var canManage = false;
    if (uid != null) {
      canManage = await _accessControl
          .hasPermission(userId: uid, permissionId: 'roles.manage');
    }
    if (!mounted) return;
    setState(() => _canManageDesignations = canManage);
  }

  Stream<List<Designation>> _designationsStream() =>
      _designationService.getAllDesignations();

  Future<void> _createDesignation() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _DesignationEditorDialog(),
    );
    if (created == true && mounted) {
      _showSnack('Designation created.');
    }
  }

  Future<void> _editDesignation(Designation designation) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _DesignationEditorDialog(designation: designation),
    );
    if (updated == true && mounted) {
      _showSnack('Designation updated.');
    }
  }

  Future<void> _toggleDesignation(Designation designation) async {
    try {
      await _designationService.updateDesignation(
        designationId: designation.id,
        isActive: !designation.isActive,
      );
      if (mounted) {
        _showSnack(designation.isActive
            ? '"${designation.name}" deactivated.'
            : '"${designation.name}" activated.');
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to update designation: $e', error: true);
    }
  }

  Future<void> _deleteDesignation(Designation designation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dark.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.dark.border),
        ),
        title: Text(
          'Delete "${designation.name}"?',
          style: TextStyle(color: AppColors.dark.textPrimary),
        ),
        content: Text(
          'Existing staff and manager records keep their designation string, '
          'but it will no longer appear in the onboarding picker. '
          'This cannot be undone.',
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
      await _designationService.deleteDesignation(designation.id);
      if (mounted) _showSnack('Designation "${designation.name}" deleted.');
    } catch (e) {
      if (mounted) _showSnack('Failed to delete designation: $e', error: true);
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
    return StreamBuilder<List<Designation>>(
      stream: _designationsStream(),
      builder: (context, snap) {
        final designations = snap.data ?? const <Designation>[];
        final loading = snap.connectionState == ConnectionState.waiting;

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
                        '${designations.length} designation${designations.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _canManageDesignations ? _createDesignation : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New Designation'),
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
              else if (designations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    children: [
                      Icon(Icons.work_outline_rounded,
                          size: 40, color: colors.iconMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No designations yet. Create your first one.',
                        style: TextStyle(color: colors.textMuted),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return _buildDesignationCards(designations);
                    }
                    return _buildDesignationTable(designations, constraints);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesignationTable(
      List<Designation> designations, BoxConstraints constraints) {
    final colors = AppColors.of(context);

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
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: colors.tableHeader,
              child: Row(
                children: [
                  _headerCell(colors, 'Designation', flex: 5),
                  _headerCell(colors, 'Slug', flex: 3),
                  _headerCell(colors, 'Status', flex: 2),
                  _headerCell(colors, 'Actions', flex: 3, alignEnd: true),
                ],
              ),
            ),
            for (var i = 0; i < designations.length; i++)
              Container(
                color: i.isEven ? colors.tableRow : colors.tableRowAlt,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        designations[i].name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        designations[i].slug,
                        style: TextStyle(
                            color: colors.textMuted, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: designations[i].isActive
                          ? _badge(colors, 'Active', colors.success)
                          : _badge(colors, 'Inactive', colors.textMuted),
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_canManageDesignations) ...[
                            IconButton(
                              tooltip: designations[i].isActive
                                  ? 'Deactivate'
                                  : 'Activate',
                              onPressed: () =>
                                  _toggleDesignation(designations[i]),
                              icon: Icon(
                                designations[i].isActive
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: colors.iconSecondary,
                                size: 20,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit designation',
                              onPressed: () =>
                                  _editDesignation(designations[i]),
                              icon: Icon(Icons.edit_rounded,
                                  color: colors.iconSecondary, size: 20),
                            ),
                            IconButton(
                              tooltip: 'Delete designation',
                              onPressed: () =>
                                  _deleteDesignation(designations[i]),
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

  Widget _buildDesignationCards(List<Designation> designations) {
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final designation in designations)
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
                          designation.name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (designation.isActive)
                        _badge(colors, 'Active', colors.success)
                      else
                        _badge(colors, 'Inactive', colors.textMuted),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Slug: ${designation.slug}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                  if (_canManageDesignations) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _toggleDesignation(designation),
                          icon: Icon(
                            designation.isActive
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 16,
                          ),
                          label: Text(
                              designation.isActive ? 'Deactivate' : 'Activate'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.focus,
                            side: BorderSide(color: colors.focus),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Edit designation',
                          onPressed: () => _editDesignation(designation),
                          icon: Icon(Icons.edit_rounded,
                              color: colors.iconSecondary, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Delete designation',
                          onPressed: () => _deleteDesignation(designation),
                          icon: Icon(Icons.delete_outline_rounded,
                              color: colors.error, size: 20),
                        ),
                      ],
                    ),
                  ],
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
}

class _DesignationEditorDialog extends StatefulWidget {
  final Designation? designation;

  const _DesignationEditorDialog({this.designation});

  @override
  State<_DesignationEditorDialog> createState() =>
      _DesignationEditorDialogState();
}

class _DesignationEditorDialogState extends State<_DesignationEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late bool _isActive;
  bool _submitting = false;
  final _designationService = DesignationService();

  bool get _isEditing => widget.designation != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.designation?.name ?? '');
    _isActive = widget.designation?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
        constraints: const BoxConstraints(maxWidth: 480),
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
                    child: Icon(Icons.work_outline_rounded,
                        color: colors.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing
                              ? 'Edit "${widget.designation!.name}"'
                              : 'Create designation',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isEditing
                              ? 'Adjust the designation title and availability.'
                              : 'Name the designation shown in onboarding.',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      style:
                          TextStyle(color: colors.textPrimary, fontSize: 14),
                      cursorColor: colors.focus,
                      decoration: InputDecoration(
                        labelText: 'Designation name',
                        labelStyle: TextStyle(color: colors.textMuted),
                        hintText: 'e.g. Senior Engineer',
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
                          return 'Designation name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isActive,
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _isActive = v),
                      title: Text(
                        'Active',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        'Inactive designations are hidden from the onboarding picker.',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      activeThumbColor: colors.focus,
                    ),
                  ],
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
                    label:
                        Text(_submitting ? 'Saving…' : 'Save designation'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final name = _nameCtrl.text.trim();
      if (_isEditing) {
        await _designationService.updateDesignation(
          designationId: widget.designation!.id,
          name: name,
          isActive: _isActive,
        );
      } else {
        await _designationService.createDesignation(name: name);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save designation: $e'),
          backgroundColor: AppColors.dark.error,
        ),
      );
    }
  }
}
