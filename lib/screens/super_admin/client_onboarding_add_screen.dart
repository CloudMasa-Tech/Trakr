import 'package:flutter/material.dart';

import '../../control_plane/models/workspace_provision_request.dart';
import '../../control_plane/services/workspace_provisioning_client_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/country_options.dart';
import 'portal_widgets.dart';
import 'workspace_provisioning_progress_modal.dart';

const List<String> kCoIndustries = [
  'Technology',
  'Healthcare',
  'Education',
  'Finance & Banking',
  'Retail & E-commerce',
  'Manufacturing',
  'Construction',
  'Hospitality',
  'Media & Entertainment',
  'Real Estate',
  'Logistics & Transport',
  'Legal & Professional Services',
  'Agriculture',
  'Energy & Utilities',
  'Consulting',
  'Other',
];

class ClientOnboardingAddScreen extends StatefulWidget {
  const ClientOnboardingAddScreen({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ClientOnboardingAddScreen()),
    );
    return result == true;
  }

  @override
  State<ClientOnboardingAddScreen> createState() =>
      _ClientOnboardingAddScreenState();
}

class _ClientOnboardingAddScreenState extends State<ClientOnboardingAddScreen> {
  final _formKey = GlobalKey<FormState>();

  final _provisioningClient = WorkspaceProvisioningClientService();

  final _workspaceNameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  final _adminEmailCtrl = TextEditingController();

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  String _selectedDialCode = '+91';
  String? _selectedIndustry;

  bool _submitting = false;

  void _refreshButtonState() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _busy => _submitting;

  bool get _canSubmit {
    if (_busy) return false;
    if (_workspaceNameCtrl.text.trim().isEmpty) return false;
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_phoneCtrl.text.trim().isEmpty) return false;
    if (_selectedIndustry == null) return false;
    if (_emailValidator(_adminEmailCtrl.text) != null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _workspaceNameCtrl,
      _nameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _adminEmailCtrl,
    ]) {
      controller.addListener(_refreshButtonState);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _workspaceNameCtrl,
      _nameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _adminEmailCtrl,
    ]) {
      controller.removeListener(_refreshButtonState);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _submitting = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final companyName = _nameCtrl.text.trim();
    final adminEmail = _adminEmailCtrl.text.trim();

    try {
      final incompleteWorkspace =
          await _provisioningClient.findIncompleteWorkspace(
        workspaceName: _workspaceNameCtrl.text.trim(),
        adminEmail: adminEmail,
      );
      if (incompleteWorkspace != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "An incomplete workspace with this name/email already exists — "
              "resuming it instead of creating a new one",
            ),
          ),
        );
      }

      if (!mounted) return;
      final result = await WorkspaceProvisioningProgressModal.show(
        context,
        request: WorkspaceProvisionRequest(
          workspaceName: _workspaceNameCtrl.text.trim(),
          companyName: companyName,
          companyPhone: "$_selectedDialCode ${_phoneCtrl.text.trim()}".trim(),
          companyAddress: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
          industry: _selectedIndustry!,
          companyAdminEmail: adminEmail,
          existingWorkspaceId: incompleteWorkspace?.workspaceId,
        ),
        initialLogId: WorkspaceProvisioningProgressModal.generateLogId(),
        provisioningClient: _provisioningClient,
      );

      if (!mounted) return;
      setState(() {
        _submitting = false;
      });

      if (result == null) return;

      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: kCoGreen600,
          content: Text(
            'Firebase project "${result.firebaseProjectId}" provisioned successfully for '
            'workspace "$companyName" (workspace code: '
            '${result.workspaceCode}; dashboard: '
            '/workspace/${result.workspaceSlug}/dashboard). Login for '
            '$adminEmail was sent by email.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: kCoError,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 48 : 16,
                    vertical: 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 24),
                            _buildSectionCard(
                              title: 'Workspace',
                              subtitle:
                                  'Name used for the workspace code and the '
                                  'automatic Firebase provisioning flow.',
                              icon: Icons.workspaces_rounded,
                              children: [
                                _field(
                                  controller: _workspaceNameCtrl,
                                  label: 'Workspace name',
                                  hint: 'Enter workspace name',
                                  required: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _buildSectionCard(
                              title: 'Company basic details',
                              subtitle:
                                  'Basic information shown on the workspace '
                                  'and its white-label branding.',
                              icon: Icons.apartment_rounded,
                              children: [
                                _twoCol(
                                  _field(
                                    controller: _nameCtrl,
                                    label: 'Company name',
                                    hint: 'Enter company name',
                                    required: true,
                                  ),
                                  _buildPhoneField(
                                    controller: _phoneCtrl,
                                    label: 'Phone',
                                    hint: 'Enter phone number',
                                    required: true,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _twoCol(
                                  _buildDropdownField(
                                    label: 'Industry',
                                    required: true,
                                    value: _selectedIndustry,
                                    hint: 'Select industry',
                                    items: kCoIndustries,
                                    onChanged: (v) =>
                                        setState(() => _selectedIndustry = v),
                                  ),
                                  _field(
                                    controller: _addressCtrl,
                                    label: 'Registered address',
                                    hint: 'Enter complete registered address',
                                    required: false,
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _buildSectionCard(
                              title: 'Company Admin',
                              subtitle: 'The person who manages the company '
                                  'workspace and onboards its team. Their role '
                                  'is set to Company Admin automatically, and '
                                  'their login credentials are emailed to the '
                                  'address below.',
                              icon: Icons.admin_panel_settings_rounded,
                              children: [
                                _field(
                                  controller: _adminEmailCtrl,
                                  label: 'Admin email (login)',
                                  hint: 'Enter admin email',
                                  required: true,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: _emailValidator,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildActions(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _emailValidator(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.darkAppBar.withValues(alpha: 0.85),
        border: const Border(bottom: BorderSide(color: kCoBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: kCoSubtle),
            tooltip: 'Back',
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: kCoAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.add_business_rounded,
                color: kCoAccent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Onboard a new company',
                  style: TextStyle(
                    color: kCoLabel,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Client Onboarding',
                  style: TextStyle(color: kCoSubtle, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a client company',
          style: TextStyle(
            color: kCoLabel,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Enter the workspace and company details, then TRAKR automatically '
          'creates or allocates the Firebase/GCP project, configures the '
          'tenant, seeds its data, and emails the first Company Admin their '
          'login credentials.',
          style: TextStyle(color: kCoSubtle, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: kCoAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kCoAccent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: kCoLabel,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: kCoSubtle, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: kCoSubtle,
              side: const BorderSide(color: kCoBorder),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: kCoAccent,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kCoWhite),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              _submitting
                  ? 'Provisioning…'
                  : 'Create workspace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _twoCol(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        final stack = c.maxWidth < 560;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 14), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLines = 1,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: !_busy,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: maxLines,
          style: const TextStyle(color: kCoLabel, fontSize: 14),
          cursorColor: kCoAccent,
          decoration: _inputDecoration(hint).copyWith(suffixIcon: suffixIcon),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator ??
              (value) {
                if (!required) return null;
                if (value == null || value.trim().isEmpty) {
                  return '$label is required';
                }
                return null;
              },
        ),
      ],
    );
  }

  Widget _buildPhoneField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: kCoLabel, fontSize: 14),
          decoration: _inputDecoration(hint).copyWith(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDialCode,
                  dropdownColor: AppThemeColors.darkSurface,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: kCoSubtle, size: 18),
                  items: kPhoneDialCodeOptions
                      .map((code) => DropdownMenuItem<String>(
                            value: code,
                            child: Text(
                              code,
                              style: const TextStyle(
                                color: kCoLabel,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _selectedDialCode = value ?? '+91'),
                ),
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 86, minHeight: 0),
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            if (!required) return null;
            if (value == null || value.trim().isEmpty) return 'Required';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required bool required,
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required),
        const SizedBox(height: 6),
        FormField<String>(
          initialValue: value,
          validator: (v) {
            if (!required) return null;
            if (v == null || v.isEmpty) return '$label is required';
            return null;
          },
          autovalidateMode: AutovalidateMode.onUserInteraction,
          builder: (fieldState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppThemeColors.darkCanvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: fieldState.hasError ? kCoDanger : kCoBorder,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: AppThemeColors.darkSurface,
                      value: value,
                      hint: Text(hint,
                          style:
                              const TextStyle(color: kCoSubtle, fontSize: 13)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: kCoSubtle),
                      items: items
                          .map((item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                      color: kCoLabel,
                                      fontWeight: FontWeight.w600),
                                ),
                              ))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) {
                              onChanged(v);
                              fieldState.didChange(v);
                            },
                    ),
                  ),
                ),
                if (fieldState.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2),
                    child: Text(
                      fieldState.errorText!,
                      style: const TextStyle(color: kCoDanger, fontSize: 12),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
        if (required)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('*', style: TextStyle(color: kCoDanger)),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kCoSubtle, fontSize: 13),
      filled: true,
      fillColor: AppThemeColors.darkCanvas,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoAccent, width: 1.5),
      ),
    );
  }
}
