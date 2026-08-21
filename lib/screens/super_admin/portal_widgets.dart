import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/company.dart';
import '../../services/company_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../theme/portal_palette.dart';

const Color kCoAccent = Color(0xFF0F766E);
const Color kCoBorder = AppThemeColors.darkBorder;
const Color kCoLabel = AppThemeColors.darkText;
const Color kCoSubtle = AppThemeColors.darkMuted;

// Chart/series + semantic palette shared across all super-admin modules.
const Color kCoGreen = Color(0xFF34D399);
const Color kCoBlue = Color(0xFF60A5FA);
const Color kCoAmber = Color(0xFFFBBF24);
const Color kCoCyan = Color(0xFF22D3EE);
const Color kCoViolet = Color(0xFFA78BFA);
const Color kCoRed = Color(0xFFF87171);
const Color kCoOrange = Color(0xFFFB923C);
const Color kCoGrey = Color(0xFF94A3B8);
const Color kCoBrandPink = Color(0xFFFF2D8F);
const Color kCoSuccess = Color(0xFF4CAF50);
const Color kCoGreen600 = Color(0xFF43A047);
const Color kCoError = Color(0xFFE53935);
const Color kCoErrorLight = Color(0xFFE57373);
const Color kCoDanger = Color(0xFFFF5252);
const Color kCoBlue500 = Color(0xFF2196F3);
const Color kCoTeal500 = Color(0xFF009688);
const Color kCoPurple500 = Color(0xFF9C27B0);
const Color kCoPink500 = Color(0xFFE91E63);
const Color kCoRed500 = Color(0xFFF44336);
const Color kCoOrange500 = Color(0xFFFF9800);
const Color kCoGrey500 = Color(0xFF9E9E9E);
const Color kCoWhite = Color(0xFFFFFFFF);
const Color kCoWhite54 = Color(0x8AFFFFFF);

String coMoney(num value, String currency) {
  return NumberFormat.currency(
    symbol: '$currency ',
    decimalDigits: 2,
  ).format(value);
}

String relativeTimeLabel(DateTime? value) {
  if (value == null) return '—';
  final now = DateTime.now();
  final diff = now.difference(value);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('dd MMM yyyy').format(value);
}

class CoSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  const CoSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:
            isDark ? palette.surface.withValues(alpha: 0.7) : palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: palette.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.label,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                            color: palette.subtle, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class CoStatusChip extends StatelessWidget {
  final bool isActive;
  final String? label;
  final Color? colorOverride;

  const CoStatusChip({
    super.key,
    required this.isActive,
    this.label,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorOverride ?? (isActive ? kCoGreen : kCoRed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: color, size: 8),
            const SizedBox(width: 6),
            Text(
              label ?? (isActive ? 'Active' : 'Suspended'),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  const CoMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = accent ?? palette.accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            isDark ? palette.surface.withValues(alpha: 0.7) : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.label,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.subtle, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CoEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const CoEmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, color: palette.subtle.withValues(alpha: 0.6), size: 30),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.subtle, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class CoCompanyAvatar extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final double size;

  const CoCompanyAvatar({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 40,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0].toUpperCase();
    final last = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$first$last';
  }

  @override
  Widget build(BuildContext context) {
    final accent = PortalPalette.of(context).accent;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: accent,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final url = logoUrl;
    if (url == null || url.isEmpty) return fallback;

    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) return fallback;
      try {
        final bytes = base64Decode(url.substring(comma + 1));
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.3),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      } catch (_) {
        return fallback;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.3),
            child: child,
          );
        },
      ),
    );
  }
}

/// Editable company profile dialog shared by the list and details screens.
/// Returns `true` when a change was saved.
Future<bool> showCoEditCompanyDialog(
  BuildContext context,
  Company company,
  CompanyService service,
) async {
  final nameCtrl = TextEditingController(text: company.name);
  final emailCtrl = TextEditingController(text: company.email ?? '');
  final phoneCtrl = TextEditingController(text: company.phone ?? '');
  final websiteCtrl = TextEditingController(text: company.website ?? '');
  final addressCtrl = TextEditingController(text: company.address ?? '');
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kCoBorder),
      ),
      title: const Text('Edit company',
          style: TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 17)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _coDialogField(nameCtrl, 'Company name', required: true),
                const SizedBox(height: 12),
                _coDialogField(emailCtrl, 'Company email',
                    required: true, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _coDialogField(phoneCtrl, 'Phone'),
                const SizedBox(height: 12),
                _coDialogField(websiteCtrl, 'Website',
                    keyboardType: TextInputType.url),
                const SizedBox(height: 12),
                _coDialogField(addressCtrl, 'Registered address', maxLines: 2),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
        ),
        FilledButton(
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final updates = <String, dynamic>{
              'name': nameCtrl.text.trim(),
              'email': emailCtrl.text.trim().toLowerCase(),
              if (phoneCtrl.text.trim().isNotEmpty)
                'phone': phoneCtrl.text.trim(),
              if (websiteCtrl.text.trim().isNotEmpty)
                'website': websiteCtrl.text.trim(),
              if (addressCtrl.text.trim().isNotEmpty)
                'address': addressCtrl.text.trim(),
            };
            try {
              await service.updateCompany(company.id, updates);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            } catch (e) {
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    backgroundColor: kCoError,
                    content: Text('Update failed: $e'),
                  ),
                );
              }
            }
          },
          style: FilledButton.styleFrom(backgroundColor: kCoAccent),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  nameCtrl.dispose();
  emailCtrl.dispose();
  phoneCtrl.dispose();
  websiteCtrl.dispose();
  addressCtrl.dispose();
  return saved == true;
}

Widget _coDialogField(
  TextEditingController controller,
  String label, {
  bool required = false,
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    style: const TextStyle(color: kCoLabel, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: kCoSubtle, fontSize: 13),
      filled: true,
      fillColor: AppThemeColors.darkCanvas,
      isDense: true,
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
    ),
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) {
        return '$label is required';
      }
      return null;
    },
  );
}

/// Shared companies table/card list used by the Client Onboarding and
/// Companies modules. Optional callbacks enable or hide row actions.
class PlatformCompaniesTable extends StatelessWidget {
  final List<Company> companies;
  final Map<String, int> usersByCompany;
  final Map<String, String> adminByCompany;
  final bool loading;
  final ValueChanged<Company> onView;
  final ValueChanged<Company>? onEdit;
  final ValueChanged<Company>? onToggleActive;
  final ValueChanged<Company>? onDelete;

  const PlatformCompaniesTable({
    super.key,
    required this.companies,
    required this.usersByCompany,
    required this.adminByCompany,
    required this.loading,
    required this.onView,
    this.onEdit,
    this.onToggleActive,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && companies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: kCoAccent),
          ),
        ),
      );
    }
    if (companies.isEmpty) {
      return const CoEmptyState(
        icon: Icons.business_center_outlined,
        message: 'No companies found.',
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 860) {
          return Column(
            children: [
              for (var i = 0; i < companies.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _companyCard(companies[i]),
              ],
            ],
          );
        }
        return _companyTable();
      },
    );
  }

  Widget _companyTable() {
    const labelStyle =
        TextStyle(color: kCoSubtle, fontSize: 11, fontWeight: FontWeight.w700);
    return Column(
      children: [
        const Divider(color: kCoBorder, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Expanded(
                  flex: 3, child: Text('COMPANY', style: labelStyle)),
              const Expanded(
                  flex: 2, child: Text('INDUSTRY', style: labelStyle)),
              const Expanded(
                  flex: 2, child: Text('COMPANY ADMIN', style: labelStyle)),
              const Expanded(flex: 1, child: Text('USERS', style: labelStyle)),
              const Expanded(flex: 1, child: Text('PLAN', style: labelStyle)),
              const Expanded(flex: 1, child: Text('STATUS', style: labelStyle)),
              const Expanded(
                  flex: 2, child: Text('CREATED', style: labelStyle)),
              Expanded(
                flex: 2,
                child: Text(
                    onDelete != null || onToggleActive != null ? 'ACTIONS' : '',
                    style: labelStyle),
              ),
            ],
          ),
        ),
        const Divider(color: kCoBorder, height: 1),
        for (var i = 0; i < companies.length; i++) ...[
          if (i > 0) const Divider(color: kCoBorder, height: 1),
          _tableRow(companies[i]),
        ],
      ],
    );
  }

  Widget _tableRow(Company company) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CoCompanyAvatar(
                    name: company.name, logoUrl: company.logoUrl, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    company.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kCoLabel,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              company.industry ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              adminByCompany[company.id] ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${usersByCompany[company.id] ?? 0}',
              style: const TextStyle(
                  color: kCoLabel, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _planChip(company.plan),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CoStatusChip(isActive: company.isActive),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              company.createdAt == null
                  ? '—'
                  : DateFormat('dd MMM yyyy').format(company.createdAt!),
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _actionButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'View',
                    onTap: () => onView(company),
                  ),
                  if (onEdit != null)
                    _actionButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: () => onEdit!(company),
                    ),
                  if (onToggleActive != null)
                    _actionButton(
                      icon: company.isActive
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      tooltip: company.isActive ? 'Suspend' : 'Activate',
                      color: company.isActive ? kCoAmber : kCoGreen,
                      onTap: () => onToggleActive!(company),
                    ),
                  if (onDelete != null)
                    _actionButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      color: kCoRed,
                      onTap: () => onDelete!(company),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyCard(Company company) {
    final hasActions =
        onEdit != null || onToggleActive != null || onDelete != null;
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
              CoCompanyAvatar(
                  name: company.name, logoUrl: company.logoUrl, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kCoLabel,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      company.industry ?? 'General',
                      style: const TextStyle(color: kCoSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              CoStatusChip(isActive: company.isActive),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _cardMeta(Icons.admin_panel_settings_outlined,
                  'Admin: ${adminByCompany[company.id] ?? '—'}'),
              _cardMeta(Icons.group_outlined,
                  'Users: ${usersByCompany[company.id] ?? 0}'),
              _cardMeta(
                  Icons.workspace_premium_outlined, 'Plan: ${company.plan}'),
              _cardMeta(
                Icons.calendar_today_outlined,
                company.createdAt == null
                    ? 'Created: —'
                    : 'Created: ${DateFormat('dd MMM yyyy').format(company.createdAt!)}',
              ),
            ],
          ),
          if (hasActions) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _actionButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'View',
                  onTap: () => onView(company),
                ),
                if (onEdit != null)
                  _actionButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: () => onEdit!(company),
                  ),
                if (onToggleActive != null)
                  _actionButton(
                    icon: company.isActive
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    tooltip: company.isActive ? 'Suspend' : 'Activate',
                    color: company.isActive ? kCoAmber : kCoGreen,
                    onTap: () => onToggleActive!(company),
                  ),
                if (onDelete != null)
                  _actionButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    color: kCoRed,
                    onTap: () => onDelete!(company),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kCoSubtle, size: 14),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: kCoSubtle, fontSize: 12)),
      ],
    );
  }

  Widget _planChip(String plan) {
    final (color, label) = switch (plan) {
      'Starter' => (kCoBlue, 'Starter'),
      'Pro' => (kCoCyan, 'Pro'),
      'Enterprise' => (kCoViolet, 'Enterprise'),
      _ => (kCoGrey, 'Free'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
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
}

class CoInlineLoading extends StatelessWidget {
  final bool show;
  final String? label;

  const CoInlineLoading({super.key, this.show = true, this.label});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    final palette = PortalPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: label == null
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: palette.accent),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: palette.accent),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label!,
                    style: TextStyle(color: palette.subtle, fontSize: 12.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Standard module header: title, subtitle, and optional trailing actions.
class CoPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? actions;

  const CoPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.label,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style:
                    TextStyle(color: palette.subtle, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(width: 16),
          Wrap(spacing: 10, runSpacing: 10, children: actions!),
        ],
      ],
    );
  }
}

/// Dark search field used by directory modules.
class CoSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const CoSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      width: 280,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: kCoLabel, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kCoSubtle, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, color: kCoSubtle, size: 20),
          filled: true,
          fillColor: AppThemeColors.darkCanvas,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
        ),
      ),
    );
  }
}

/// Generic pagination bar.
class CoPaginationBar extends StatelessWidget {
  final int page;
  final int pageSize;
  final int totalItems;
  final bool canNext;
  final ValueChanged<int> onPageChanged;

  const CoPaginationBar({
    super.key,
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.canNext,
    required this.onPageChanged,
  });

  int get _totalPages => (totalItems / pageSize).ceil().clamp(1, 1 << 30);

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : page * pageSize + 1;
    final end = ((page + 1) * pageSize).clamp(0, totalItems);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Text(
            '$start–$end of $totalItems',
            style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
          ),
          const Spacer(),
          IconButton(
            onPressed: page == 0 ? null : () => onPageChanged(page - 1),
            icon: const Icon(Icons.chevron_left_rounded),
            color: page == 0 ? kCoSubtle.withValues(alpha: 0.4) : kCoLabel,
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous page',
          ),
          Text(
            'Page ${page + 1} / $_totalPages',
            style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
          ),
          IconButton(
            onPressed: canNext ? () => onPageChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canNext ? kCoLabel : kCoSubtle.withValues(alpha: 0.4),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

/// Generic colored status chip.
class CoStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const CoStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 7),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// User avatar with initials fallback.
class CoUserAvatar extends StatelessWidget {
  final String name;
  final double size;

  const CoUserAvatar({super.key, required this.name, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: kCoAccent.withValues(alpha: 0.16),
      child: Text(
        initial,
        style: TextStyle(
          color: kCoAccent,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Compact filter dropdown used in module toolbars.
class CoFilterMenu extends StatelessWidget {
  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const CoFilterMenu({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kCoBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: false,
          dropdownColor: AppThemeColors.darkSurface,
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kCoSubtle),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option,
                child: Text(
                  option == 'All' ? label : option,
                  style: const TextStyle(
                    color: kCoLabel,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
