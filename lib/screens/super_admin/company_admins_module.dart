import 'package:flutter/material.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/company.dart';
import '../../services/company_analytics_service.dart';
import '../../services/company_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class CompanyAdminsModule extends StatefulWidget {
  const CompanyAdminsModule({super.key});

  @override
  State<CompanyAdminsModule> createState() => _CompanyAdminsModuleState();
}

class _CompanyAdminsModuleState extends State<CompanyAdminsModule> {
  final _companyService = CompanyService();
  final _analytics = CompanyAnalyticsService();

  List<Company> _companies = const [];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 16,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: StreamBuilder<List<Company>>(
            stream: _companyService.streamAllCompanies(),
            builder: (context, snapshot) {
              _companies = snapshot.data ?? const [];
              return StreamBuilder<List<CompanyAdminRow>>(
                stream: _analytics.streamCompanyAdmins(),
                builder: (context, adminsSnap) {
                  final admins = adminsSnap.data ?? const <CompanyAdminRow>[];
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting ||
                          adminsSnap.connectionState == ConnectionState.waiting;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(admins, loading),
                      const SizedBox(height: 20),
                      _buildTable(admins, loading),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<CompanyAdminRow> admins, bool loading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Company Admins',
          style: TextStyle(
            color: kCoLabel,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${loading ? '…' : admins.length} company administrators. Manage '
          'their access, credentials, and company assignment.',
          style: const TextStyle(color: kCoSubtle, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildTable(List<CompanyAdminRow> admins, bool loading) {
    return CoSectionCard(
      title: 'All company admins',
      subtitle: 'Admin name, company, and status. Actions manage credentials '
          'and assignments.',
      icon: Icons.admin_panel_settings_rounded,
      child: loading && admins.isEmpty
          ? const CoEmptyState(
              icon: Icons.hourglass_empty_rounded, message: 'Loading…')
          : admins.isEmpty
              ? const CoEmptyState(
                  icon: Icons.person_off_outlined,
                  message: 'No company admins found.')
              : LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth < 860) {
                      return _cards(admins);
                    }
                    return _table(admins);
                  },
                ),
    );
  }

  Widget _table(List<CompanyAdminRow> admins) {
    const labelStyle =
        TextStyle(color: kCoSubtle, fontSize: 11, fontWeight: FontWeight.w700);
    return Column(
      children: [
        const Divider(color: kCoBorder, height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('ADMIN', style: labelStyle)),
              Expanded(flex: 2, child: Text('COMPANY', style: labelStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: labelStyle)),
              Expanded(flex: 2, child: Text('ACTIONS', style: labelStyle)),
            ],
          ),
        ),
        const Divider(color: kCoBorder, height: 1),
        for (var i = 0; i < admins.length; i++) ...[
          if (i > 0) const Divider(color: kCoBorder, height: 1),
          _tableRow(admins[i]),
        ],
      ],
    );
  }

  Widget _tableRow(CompanyAdminRow admin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: kCoAccent.withValues(alpha: 0.16),
                  child: Text(
                    admin.name.isNotEmpty ? admin.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: kCoAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admin.name.isEmpty ? 'Unnamed' : admin.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoLabel,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        admin.email,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: kCoSubtle, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              admin.companyName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusChip(admin.isActive),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _actionButton(
                  icon: Icons.password_rounded,
                  tooltip: 'Reset password',
                  onTap: () => _resetPassword(admin),
                ),
                _actionButton(
                  icon: admin.isActive
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                  tooltip: admin.isActive ? 'Deactivate' : 'Activate',
                  color: admin.isActive ? kCoAmber : kCoGreen,
                  onTap: () => _toggleActive(admin),
                ),
                _actionButton(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: 'Reassign admin',
                  color: kCoBlue,
                  onTap: () => _reassign(admin),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cards(List<CompanyAdminRow> admins) {
    return Column(
      children: [
        for (var i = 0; i < admins.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _card(admins[i]),
        ],
      ],
    );
  }

  Widget _card(CompanyAdminRow admin) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: kCoAccent.withValues(alpha: 0.16),
                child: Text(
                  admin.name.isNotEmpty ? admin.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: kCoAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      admin.name.isEmpty ? 'Unnamed' : admin.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kCoLabel,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5),
                    ),
                    Text(
                      admin.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kCoSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _statusChip(admin.isActive),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.apartment_rounded, color: kCoSubtle, size: 14),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  admin.companyName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kCoSubtle, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                icon: Icons.password_rounded,
                tooltip: 'Reset password',
                onTap: () => _resetPassword(admin),
              ),
              _actionButton(
                icon: admin.isActive
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                tooltip: admin.isActive ? 'Deactivate' : 'Activate',
                color: admin.isActive ? kCoAmber : kCoGreen,
                onTap: () => _toggleActive(admin),
              ),
              _actionButton(
                icon: Icons.swap_horiz_rounded,
                tooltip: 'Reassign admin',
                color: kCoBlue,
                onTap: () => _reassign(admin),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool isActive) {
    final color = isActive ? kCoGreen : kCoRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 19, color: color ?? kCoSubtle),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    );
  }

  Future<void> _resetPassword(CompanyAdminRow admin) async {
    if (admin.email.isEmpty) {
      _snack('This admin has no email on record.', error: true);
      return;
    }
    final confirmed = await _confirm(
      title: 'Reset password',
      message:
          'A password reset email will be sent to ${admin.email}. The admin '
          'can use it to set a new password.',
      confirmLabel: 'Send reset email',
    );
    if (!confirmed || !mounted) return;
    try {
      await FirebaseContextProvider.current.auth
          .sendPasswordResetEmail(email: admin.email);
      if (!mounted) return;
      _snack('Password reset email sent to ${admin.email}.');
    } catch (e) {
      if (!mounted) return;
      _snack(
          'Could not send reset email: ${e.toString().replaceFirst('Exception: ', '')}',
          error: true);
    }
  }

  Future<void> _toggleActive(CompanyAdminRow admin) async {
    final target = !admin.isActive;
    final confirmed = await _confirm(
      title: target ? 'Activate admin?' : 'Deactivate admin?',
      message: target
          ? '${admin.name} will regain access to ${admin.companyName}.'
          : '${admin.name} will be blocked from signing in to '
              '${admin.companyName}.',
      confirmLabel: target ? 'Activate' : 'Deactivate',
      destructive: !target,
    );
    if (!confirmed || !mounted) return;
    try {
      await _analytics.setCompanyAdminActive(admin.uid, isActive: target);
      if (!mounted) return;
      _snack(target
          ? '${admin.name} has been activated.'
          : '${admin.name} has been deactivated.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update admin: $e', error: true);
    }
  }

  Future<void> _reassign(CompanyAdminRow admin) async {
    String? selected =
        _companies.any((c) => c.id == admin.companyId) ? admin.companyId : null;
    if (_companies.isNotEmpty && selected == null) {
      selected = _companies.first.id;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppThemeColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: kCoBorder),
          ),
          title: const Text('Reassign admin',
              style: TextStyle(
                  color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 17)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move ${admin.name} to a different company.',
                  style: const TextStyle(
                      color: kCoSubtle, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text('Target company',
                    style: TextStyle(
                        color: kCoLabel,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppThemeColors.darkCanvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kCoBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: AppThemeColors.darkSurface,
                      value: selected,
                      hint: const Text('Select company',
                          style: TextStyle(color: kCoSubtle, fontSize: 13)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: kCoSubtle),
                      items: _companies
                          .map((c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: kCoLabel,
                                      fontWeight: FontWeight.w600),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selected = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(selected),
              style: FilledButton.styleFrom(backgroundColor: kCoAccent),
              child: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == admin.companyId || !mounted) return;
    try {
      await _analytics.reassignCompanyAdmin(admin.uid, result);
      if (!mounted) return;
      _snack('${admin.name} was reassigned to a new company.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not reassign admin: $e', error: true);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final color = destructive ? kCoRed : kCoAccent;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCoBorder),
        ),
        title: Text(title,
            style: const TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(message,
            style:
                const TextStyle(color: kCoSubtle, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: color),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kCoError : kCoSuccess,
        content: Text(message),
      ),
    );
  }
}
