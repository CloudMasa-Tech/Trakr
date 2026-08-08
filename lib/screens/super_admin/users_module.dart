import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/company.dart';
import '../../models/platform_models.dart';
import '../../services/company_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class UsersModule extends StatefulWidget {
  const UsersModule({super.key});

  @override
  State<UsersModule> createState() => _UsersModuleState();
}

class _UsersModuleState extends State<UsersModule> {
  final _platform = PlatformService();
  final _companyService = CompanyService();
  final _searchCtrl = TextEditingController();

  List<Company> _companies = const [];
  Map<String, String> _companyNames = const {};
  String _roleFilter = 'All';
  String _companyFilter = 'All';
  String _statusFilter = 'All';
  int _page = 0;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    final companies = await _companyService.getAllCompanies();
    if (!mounted) return;
    setState(() {
      _companies = companies;
      _companyNames = {
        for (final c in companies) c.id: c.name,
      };
    });
  }

  List<PlatformUserRow> _filtered(List<PlatformUserRow> users) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return users.where((u) {
      final matchesRole = _roleFilter == 'All' || u.role == _roleFilter;
      final matchesStatus = _statusFilter == 'All' ||
          (_statusFilter == 'Active' && u.isActive) ||
          (_statusFilter == 'Inactive' && !u.isActive);
      final matchesCompany =
          _companyFilter == 'All' || u.companyId == _companyFilter;
      if (!matchesRole || !matchesStatus || !matchesCompany) return false;
      if (query.isEmpty) return true;
      return u.name.toLowerCase().contains(query) ||
          u.email.toLowerCase().contains(query);
    }).toList();
  }

  String _companyName(String? companyId) {
    if (companyId == null) return '—';
    return _companyNames[companyId] ?? 'Unknown';
  }

  Future<void> _resetPassword(PlatformUserRow user) async {
    if (user.email.isEmpty) {
      _snack('This user has no email on record.', error: true);
      return;
    }
    final confirmed = await _confirm(
      title: 'Reset password',
      message: 'A password reset email will be sent to ${user.email}.',
      confirmLabel: 'Send reset email',
    );
    if (!confirmed || !mounted) return;
    try {
      await FirebaseContextProvider.current.auth
          .sendPasswordResetEmail(email: user.email);
      await _platform.recordSecurityEvent(
        type: 'password_reset',
        email: user.email,
        detail: 'Super Admin triggered a password reset.',
      );
      await _platform.recordAudit(
        category: 'Security',
        action: 'reset_password',
        targetType: 'user',
        targetId: user.uid,
        targetName: user.email,
      );
      if (!mounted) return;
      _snack('Password reset email sent to ${user.email}.');
    } catch (e) {
      if (!mounted) return;
      _snack(
        'Could not send reset email: '
        '${e.toString().replaceFirst('Exception: ', '')}',
        error: true,
      );
    }
  }

  Future<void> _toggleActive(PlatformUserRow user) async {
    final target = !user.isActive;
    final confirmed = await _confirm(
      title: target ? 'Activate user?' : 'Deactivate user?',
      message: target
          ? '${user.name} will regain access to the platform.'
          : '${user.name} will be blocked from signing in.',
      confirmLabel: target ? 'Activate' : 'Deactivate',
      destructive: !target,
    );
    if (!confirmed || !mounted) return;
    try {
      await _platform.setUserActive(user.uid, isActive: target);
      await _platform.recordAudit(
        category: 'User',
        action: target ? 'activate' : 'deactivate',
        targetType: 'user',
        targetId: user.uid,
        targetName: user.email,
        changes: {'isActive': target},
      );
      if (!mounted) return;
      _snack('${user.name} ${target ? 'activated' : 'deactivated'}.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update user: $e', error: true);
    }
  }

  Future<void> _deleteUser(PlatformUserRow user) async {
    final confirmed = await _confirm(
      title: 'Remove ${user.name}?',
      message: 'This removes the login account from the users directory. '
          'The Firebase Auth login still exists and can be restored by the '
          'company admin. This cannot be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _platform.deleteUserDoc(user.uid);
      await _platform.recordAudit(
        category: 'User',
        action: 'delete',
        targetType: 'user',
        targetId: user.uid,
        targetName: user.email,
      );
      if (!mounted) return;
      _snack('${user.name} removed from the directory.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not remove user: $e', error: true);
    }
  }

  Future<void> _viewUser(PlatformUserRow user) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCoBorder),
        ),
        title: const Text('User details',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 17)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CoUserAvatar(name: user.name, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name.isEmpty ? 'Unnamed' : user.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kCoLabel,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        Text(user.email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kCoSubtle, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow('Role', user.role),
              _detailRow('Company', _companyName(user.companyId)),
              _detailRow('Phone', user.phone.isEmpty ? '—' : user.phone),
              _detailRow(
                'Created',
                user.createdAt == null
                    ? '—'
                    : DateFormat('dd MMM yyyy').format(user.createdAt!),
              ),
              _detailRow(
                'Last login',
                user.lastLoginAt == null
                    ? '—'
                    : DateFormat('dd MMM yyyy, hh:mm a')
                        .format(user.lastLoginAt!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: kCoSubtle)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: kCoSubtle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: kCoLabel, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
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
          child: StreamBuilder<List<PlatformUserRow>>(
            stream: _platform.streamUsers(limit: 200),
            builder: (context, snapshot) {
              final users = snapshot.data ?? const <PlatformUserRow>[];
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final filtered = _filtered(users);
              final totalPages =
                  (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
              if (_page >= totalPages) _page = totalPages - 1;
              final pageStart = (_page * _pageSize).clamp(0, filtered.length);
              final pageEnd =
                  ((_page + 1) * _pageSize).clamp(0, filtered.length);
              final pageUsers = filtered.sublist(pageStart, pageEnd);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CoPageHeader(
                    title: 'Users',
                    subtitle: '${loading ? '…' : users.length} login accounts '
                        'across all companies on the platform.',
                  ),
                  const SizedBox(height: 20),
                  _buildToolbar(),
                  const SizedBox(height: 14),
                  _buildTable(pageUsers, filtered.length, loading),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return LayoutBuilder(
      builder: (context, c) {
        final search = CoSearchField(
          controller: _searchCtrl,
          hint: 'Search users…',
          onChanged: (_) => setState(() => _page = 0),
        );
        final roleFilter = CoFilterMenu(
          label: 'All roles',
          options: const [
            'All',
            'super_admin',
            'company_admin',
            'manager',
            'staff',
          ],
          value: _roleFilter,
          onChanged: (v) => setState(() {
            _roleFilter = v;
            _page = 0;
          }),
        );
        final statusFilter = CoFilterMenu(
          label: 'All statuses',
          options: const ['All', 'Active', 'Inactive'],
          value: _statusFilter,
          onChanged: (v) => setState(() {
            _statusFilter = v;
            _page = 0;
          }),
        );
        final companyFilter = CoFilterMenu(
          label: 'All companies',
          options: ['All', ..._companies.map((c) => c.name)],
          value: _companies.any((c) => c.name == _companyFilter)
              ? _companyFilter
              : 'All',
          onChanged: (v) => setState(() {
            _companyFilter = _companies.any((c) => c.name == v) ? v : 'All';
            _page = 0;
          }),
        );
        if (c.maxWidth < 900) {
          return Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 260, child: search),
            roleFilter,
            statusFilter,
            companyFilter,
          ]);
        }
        return Row(
          children: [
            search,
            const Spacer(),
            roleFilter,
            const SizedBox(width: 10),
            statusFilter,
            const SizedBox(width: 10),
            companyFilter,
          ],
        );
      },
    );
  }

  Widget _buildTable(List<PlatformUserRow> users, int total, bool loading) {
    return CoSectionCard(
      title: 'All users',
      subtitle: loading
          ? 'Loading user directory…'
          : 'Showing ${users.length} of $total users.',
      icon: Icons.group_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          loading && users.isEmpty
              ? const CoInlineLoading()
              : users.isEmpty
                  ? const CoEmptyState(
                      icon: Icons.group_outlined, message: 'No users found.')
                  : LayoutBuilder(
                      builder: (context, c) {
                        if (c.maxWidth < 900) return _cards(users);
                        return _table(users);
                      },
                    ),
          if (!loading && total > _pageSize)
            CoPaginationBar(
              page: _page,
              pageSize: _pageSize,
              totalItems: total,
              canNext: (_page + 1) * _pageSize < total,
              onPageChanged: (p) => setState(() => _page = p),
            ),
        ],
      ),
    );
  }

  Widget _table(List<PlatformUserRow> users) {
    const labelStyle =
        TextStyle(color: kCoSubtle, fontSize: 11, fontWeight: FontWeight.w700);
    return Column(
      children: [
        const Divider(color: kCoBorder, height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('USER', style: labelStyle)),
              Expanded(flex: 2, child: Text('COMPANY', style: labelStyle)),
              Expanded(flex: 1, child: Text('ROLE', style: labelStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: labelStyle)),
              Expanded(flex: 2, child: Text('CREATED', style: labelStyle)),
              Expanded(flex: 2, child: Text('ACTIONS', style: labelStyle)),
            ],
          ),
        ),
        const Divider(color: kCoBorder, height: 1),
        for (var i = 0; i < users.length; i++) ...[
          if (i > 0) const Divider(color: kCoBorder, height: 1),
          _tableRow(users[i]),
        ],
      ],
    );
  }

  Widget _tableRow(PlatformUserRow user) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CoUserAvatar(name: user.name, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.isEmpty ? 'Unnamed' : user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoLabel,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
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
              _companyName(user.companyId),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(flex: 1, child: _roleChip(user.role)),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusChip(user.isActive),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user.createdAt == null
                  ? '—'
                  : DateFormat('dd MMM yyyy').format(user.createdAt!),
              style: const TextStyle(color: kCoLabel, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _actionButton(
                  icon: Icons.visibility_outlined,
                  tooltip: 'View',
                  onTap: () => _viewUser(user),
                ),
                _actionButton(
                  icon: Icons.password_rounded,
                  tooltip: 'Reset password',
                  onTap: () => _resetPassword(user),
                ),
                _actionButton(
                  icon: user.isActive
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                  tooltip: user.isActive ? 'Deactivate' : 'Activate',
                  color: user.isActive ? kCoAmber : kCoGreen,
                  onTap: () => _toggleActive(user),
                ),
                _actionButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Remove from directory',
                  color: kCoRed,
                  onTap: () => _deleteUser(user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cards(List<PlatformUserRow> users) {
    return Column(
      children: [
        for (var i = 0; i < users.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _card(users[i]),
        ],
      ],
    );
  }

  Widget _card(PlatformUserRow user) {
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
              CoUserAvatar(name: user.name, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isEmpty ? 'Unnamed' : user.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kCoLabel,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5),
                    ),
                    Text(
                      user.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kCoSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _statusChip(user.isActive),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _roleChip(user.role),
              _meta(Icons.apartment_rounded, _companyName(user.companyId)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                icon: Icons.visibility_outlined,
                tooltip: 'View',
                onTap: () => _viewUser(user),
              ),
              _actionButton(
                icon: Icons.password_rounded,
                tooltip: 'Reset password',
                onTap: () => _resetPassword(user),
              ),
              _actionButton(
                icon: user.isActive
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                tooltip: user.isActive ? 'Deactivate' : 'Activate',
                color: user.isActive ? kCoAmber : kCoGreen,
                onTap: () => _toggleActive(user),
              ),
              _actionButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Remove from directory',
                color: kCoRed,
                onTap: () => _deleteUser(user),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kCoSubtle, size: 14),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: kCoSubtle, fontSize: 12)),
      ],
    );
  }

  Widget _roleChip(String role) {
    final (color, label) = switch (role) {
      'super_admin' => (kCoRed, 'Super Admin'),
      'company_admin' => (kCoAmber, 'Company Admin'),
      'manager' => (kCoBlue, 'Manager'),
      'staff' => (kCoGreen, 'Staff'),
      _ => (kCoGrey, role.isEmpty ? 'Unknown' : role),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _statusChip(bool isActive) {
    return CoStatusBadge(
      label: isActive ? 'Active' : 'Inactive',
      color: isActive ? kCoGreen : kCoRed,
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
