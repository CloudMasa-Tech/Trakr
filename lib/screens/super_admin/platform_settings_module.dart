import 'package:flutter/material.dart';

import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class PlatformSettingsModule extends StatefulWidget {
  const PlatformSettingsModule({super.key});

  @override
  State<PlatformSettingsModule> createState() => _PlatformSettingsModuleState();
}

class _PlatformSettingsModuleState extends State<PlatformSettingsModule> {
  final _platform = PlatformService();
  final _nameCtrl = TextEditingController(text: 'TRAKR');
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _currency = 'USD';
  String _timezone = 'UTC';
  bool _requireTwoFactorAuth = false;
  int _sessionTimeoutMinutes = 60;
  String _maintenanceMode = 'off';
  bool _allowCompanySignups = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _platform.getPlatformSettings();
      if (!mounted) return;
      _nameCtrl.text = settings.platformName;
      _emailCtrl.text = settings.supportEmail;
      _phoneCtrl.text = settings.supportPhone;
      _currency = settings.currency;
      _timezone = settings.defaultTimezone;
      _requireTwoFactorAuth = settings.requireTwoFactorAuth;
      _sessionTimeoutMinutes = settings.sessionTimeoutMinutes;
      _maintenanceMode = settings.maintenanceMode;
      _allowCompanySignups = settings.allowCompanySignups;
      setState(() {});
    } catch (e) {
      debugPrint('PlatformSettings load failed: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _platform.savePlatformSettings({
        'platformName':
            _nameCtrl.text.trim().isEmpty ? 'TRAKR' : _nameCtrl.text.trim(),
        'supportEmail': _emailCtrl.text.trim(),
        'supportPhone': _phoneCtrl.text.trim(),
        'currency': _currency,
        'defaultTimezone': _timezone,
        'requireTwoFactorAuth': _requireTwoFactorAuth,
        'sessionTimeoutMinutes': _sessionTimeoutMinutes,
        'maintenanceMode': _maintenanceMode,
        'allowCompanySignups': _allowCompanySignups,
      });
      await _platform.recordAudit(
        category: 'platform',
        action: 'updated platform settings',
        changes: {
          'platformName': _nameCtrl.text.trim(),
          'maintenanceMode': _maintenanceMode,
        },
      );
      if (!mounted) return;
      _snack('Platform settings saved.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not save settings: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kCoError : kCoSuccess,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Platform Settings',
                style: TextStyle(
                  color: kCoLabel,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Manage platform-level configuration. '
                'Attendance and company settings live in the Company Admin portal.',
                style: TextStyle(color: kCoSubtle, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              _buildIdentityCard(),
              const SizedBox(height: 16),
              _buildSecurityCard(),
              const SizedBox(height: 16),
              _buildAccessCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return CoSectionCard(
      title: 'Platform identity',
      subtitle: 'Shown to company admins and support contacts.',
      icon: Icons.branding_watermark_outlined,
      child: Column(
        children: [
          _row(
            'Platform name',
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: kCoLabel, fontSize: 14),
              decoration: _decoration(),
            ),
          ),
          const SizedBox(height: 14),
          _row(
            'Support email',
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: kCoLabel, fontSize: 14),
              decoration: _decoration(),
            ),
          ),
          const SizedBox(height: 14),
          _row(
            'Support phone',
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: kCoLabel, fontSize: 14),
              decoration: _decoration(),
            ),
          ),
          const SizedBox(height: 14),
          _row(
            'Currency',
            _dropdown<String>(
              value: _currency,
              items: const ['USD', 'EUR', 'INR', 'GBP', 'AUD', 'CAD'],
              onChanged: (v) => setState(() => _currency = v),
            ),
          ),
          const SizedBox(height: 14),
          _row(
            'Default timezone',
            _dropdown<String>(
              value: _timezone,
              items: const ['UTC', 'IST', 'EST', 'CST', 'PST', 'GMT', 'CET'],
              onChanged: (v) => setState(() => _timezone = v),
            ),
          ),
          const SizedBox(height: 18),
          _saveRow(),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return CoSectionCard(
      title: 'Security',
      subtitle: 'Defaults for login and session enforcement.',
      icon: Icons.security_rounded,
      child: Column(
        children: [
          _toggleRow(
            'Require two-factor authentication',
            'All company admins and managers must enable 2FA on next login.',
            _requireTwoFactorAuth,
            (v) => setState(() => _requireTwoFactorAuth = v),
          ),
          const Divider(color: kCoBorder, height: 24),
          _row(
            'Session timeout (min)',
            _dropdown<int>(
              value: _sessionTimeoutMinutes,
              items: const [30, 60, 120, 240, 480],
              itemLabel: (v) => '$v minutes',
              onChanged: (v) => setState(() => _sessionTimeoutMinutes = v),
            ),
          ),
          const Divider(color: kCoBorder, height: 24),
          _toggleRow(
            'Maintenance mode',
            _maintenanceMode == 'on'
                ? 'Users will see a maintenance notice instead of signing in.'
                : 'Keep the platform available to all users.',
            _maintenanceMode == 'on',
            (v) => setState(() => _maintenanceMode = v ? 'on' : 'off'),
          ),
          const SizedBox(height: 18),
          _saveRow(),
        ],
      ),
    );
  }

  Widget _buildAccessCard() {
    return CoSectionCard(
      title: 'Sign-up & access',
      subtitle: 'Control how companies join the platform.',
      icon: Icons.app_registration_rounded,
      child: Column(
        children: [
          _toggleRow(
            'Allow new company sign-ups',
            'The Client Onboarding module stays available for new companies.',
            _allowCompanySignups,
            (v) => setState(() => _allowCompanySignups = v),
          ),
          const SizedBox(height: 18),
          _saveRow(),
        ],
      ),
    );
  }

  Widget _saveRow() {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: kCoAccent),
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: kCoWhite))
            : const Icon(Icons.save_outlined, size: 17),
        label: Text(_saving ? 'Saving…' : 'Save Settings'),
      ),
    );
  }

  Widget _row(String label, Widget field) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              label,
              style: const TextStyle(
                color: kCoLabel,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        Expanded(child: field),
      ],
    );
  }

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: kCoLabel,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: kCoSubtle,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: kCoAccent,
          activeTrackColor: kCoAccent.withValues(alpha: 0.4),
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T> onChanged,
    String Function(T)? itemLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kCoBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          dropdownColor: AppThemeColors.darkSurface,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kCoSubtle),
          style: const TextStyle(color: kCoLabel, fontSize: 14),
          items: items
              .map((v) => DropdownMenuItem<T>(
                    value: v,
                    child: Text(
                      itemLabel?.call(v) ?? v.toString(),
                      style: const TextStyle(color: kCoLabel, fontSize: 14),
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  InputDecoration _decoration() {
    return InputDecoration(
      hintStyle: const TextStyle(color: kCoSubtle, fontSize: 13),
      filled: true,
      fillColor: AppThemeColors.darkCanvas,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
