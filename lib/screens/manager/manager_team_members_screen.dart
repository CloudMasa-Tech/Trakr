// lib/screens/manager/manager_team_members_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../providers/auth_session_provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/departments.dart';
import 'onboard_user_dialog.dart';

// Fixed-brand palette for the manager team members screen (force-dark).
// Intentional exception: file-scoped brand constants.
const Color _mtmPrimary = Color(0xFF0F766E);
const Color _mtmShadow = Color(0x1A6B7897);
const Color _mtmShadowSoft = Color(0x0D6B7897);
const Color _mtmGreenDeep = Color(0xFF059669);
const Color _mtmAmberDeep = Color(0xFFD97706);
const Color _mtmTintBlue = Color(0xFFEAF1FF);
const Color _mtmRed = Color(0xFFEF4444);
const Color _mtmBlue = Color(0xFF3B82F6);
const Color _mtmGreen = Color(0xFF10B981);
const Color _mtmAmber = Color(0xFFF59E0B);
const Color _mtmViolet = Color(0xFF8B5CF6);
const Color _mtmPink = Color(0xFFEC4899);
const Color _mtmWhite = Color(0xFFFFFFFF);
const Color _mtmGrey400 = Color(0xFFBDBDBD);
const Color _mtmGrey300 = Color(0xFFE0E0E0);
const Color _mtmCyan = Color(0xFF06B6D4);
const Color _mtmLime = Color(0xFF84CC16);
const Color _mtmTintGreen = Color(0xFFD1FAE5);
const Color _mtmTintAmber = Color(0xFFFEF3C7);

class ManagerTeamMembersScreen extends StatefulWidget {
  /// The canonical name of the logged-in manager.
  final String managerName;

  /// The email of the logged-in manager.
  final String managerEmail;

  const ManagerTeamMembersScreen({
    super.key,
    required this.managerName,
    required this.managerEmail,
  });

  @override
  State<ManagerTeamMembersScreen> createState() =>
      _ManagerTeamMembersScreenState();
}

class _ManagerTeamMembersScreenState extends State<ManagerTeamMembersScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedDept;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openOnboardDialog() async {
    await OnboardUserDialog.show(
      context,
      currentManagerName: widget.managerName,
      currentManagerEmail: widget.managerEmail,
      onboarderRole: AppUserRole.user,
    );
  }

  /// Live stream: staff where reportsTo matches name OR email
  Stream<QuerySnapshot> _teamStream() {
    final name = widget.managerName.trim();
    final email = widget.managerEmail.trim();

    // Create a list of possible identifiers to match against 'reportsTo'
    List<String> identifiers = [name];
    if (email.isNotEmpty && email != name) {
      identifiers.add(email);
    }

    return FirebaseContextProvider.current.firestore
        .collection('staff')
        .where('reportsTo', whereIn: identifiers)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 0 : 8,
        vertical: isMobile ? 0 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Team Members',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppThemeColors.darkText,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'View your team members and their details.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppThemeColors.darkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _openOnboardDialog,
                style: FilledButton.styleFrom(
                  backgroundColor: _mtmPrimary,
                  foregroundColor: _mtmWhite,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 18,
                    vertical: isMobile ? 12 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(isMobile ? 'Onboard' : 'Onboard user'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Search + designation filter ──────────────────────
          if (isMobile) ...[
            _buildSearchField(),
            const SizedBox(height: 10),
            _buildDeptFilter(),
          ] else
            Row(
              children: [
                Expanded(flex: 3, child: _buildSearchField()),
                const SizedBox(width: 12),
                SizedBox(width: 200, child: _buildDeptFilter()),
              ],
            ),

          const SizedBox(height: 20),

          // ── Stream ────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: _teamStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(color: _mtmPrimary),
                  ),
                );
              }

              if (snapshot.hasError) {
                return _emptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Error loading team',
                  subtitle: snapshot.error.toString(),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];

              // Apply filters
              final filtered = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['name'] as String? ?? '').toLowerCase();
                final empId =
                    (data['employeeId'] as String? ?? '').toLowerCase();
                final dept = (data['department'] as String? ?? '');

                final matchesSearch = _searchQuery.isEmpty ||
                    name.contains(_searchQuery.toLowerCase()) ||
                    empId.contains(_searchQuery.toLowerCase());
                final matchesDept =
                    _selectedDept == null || dept == _selectedDept;

                return matchesSearch && matchesDept;
              }).toList();

              if (allDocs.isEmpty) {
                final displayId = widget.managerName == widget.managerEmail
                    ? widget.managerName
                    : "${widget.managerName}\" or \"${widget.managerEmail}";
                return _emptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No team members yet',
                  subtitle:
                      'Staff added by the admin with "Reports To: $displayId" will appear here.',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Total count card ───────────────────────
                  _TotalCard(count: allDocs.length),
                  const SizedBox(height: 20),

                  // ── Table / Cards ──────────────────────────
                  if (filtered.isEmpty)
                    _emptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No results',
                      subtitle:
                          'Try a different name, ID or designation filter.',
                    )
                  else if (isMobile)
                    ...filtered.map((doc) => _MobileStaffCard(
                          data: doc.data() as Map<String, dynamic>,
                        ))
                  else
                    _TeamMembersTable(
                      docs: filtered,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      style: const TextStyle(color: AppThemeColors.darkText),
      cursorColor: _mtmPrimary,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: 'Search team member by name or ID...',
        hintStyle:
            const TextStyle(color: AppThemeColors.darkMuted, fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: _mtmGrey400, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppThemeColors.darkMuted,
                ),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: AppThemeColors.darkCanvas,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppThemeColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppThemeColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _mtmPrimary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDeptFilter() {
    final value =
        kAppDepartments.contains(_selectedDept) ? _selectedDept : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          dropdownColor: AppThemeColors.darkSurface,
          style: const TextStyle(color: AppThemeColors.darkText, fontSize: 14),
          value: value,
          isExpanded: true,
          hint: const Text('All Departments',
              style: TextStyle(fontSize: 14, color: AppThemeColors.darkMuted)),
          icon: const Icon(Icons.expand_more_rounded,
              color: AppThemeColors.darkMuted, size: 20),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Departments', style: TextStyle(fontSize: 14)),
            ),
            ...kAppDepartments.map((dept) => DropdownMenuItem<String?>(
                  value: dept,
                  child: Text(dept, style: const TextStyle(fontSize: 14)),
                )),
          ],
          onChanged: (v) => setState(() => _selectedDept = v),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 56, color: _mtmGrey300),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppThemeColors.darkText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppThemeColors.darkMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Total Count Card ────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final int count;
  const _TotalCard({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _mtmShadowSoft,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _mtmTintBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.people_alt_rounded,
                color: _mtmPrimary, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Team Members',
                style: TextStyle(
                  fontSize: 13,
                  color: AppThemeColors.darkMuted,
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppThemeColors.darkText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Desktop Table ────────────────────────────────────────────────────────────

class _TeamMembersTable extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const _TeamMembersTable({
    required this.docs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _mtmShadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            decoration: const BoxDecoration(
              color: AppThemeColors.darkCanvas,
              border: Border.symmetric(
                horizontal: BorderSide(color: AppThemeColors.darkBorder),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 28, child: _ColLabel('STAFF')),
                Expanded(flex: 10, child: _ColLabel('ID')),
                Expanded(flex: 18, child: _ColLabel('DESIGNATION')),
                Expanded(flex: 18, child: _ColLabel('POSITION')),
                Expanded(flex: 14, child: _ColLabel('SALARY')),
                Expanded(flex: 12, child: _ColLabel('STATUS')),
                Expanded(flex: 14, child: _ColLabel('JOINED ON')),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppThemeColors.darkBorder),
            itemBuilder: (context, index) {
              return _TeamMemberRow(
                data: docs[index].data() as Map<String, dynamic>,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TeamMemberRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unknown';
    final email = data['email'] as String? ?? '';
    final empId = data['employeeId'] as String? ?? '';
    final dept = data['department'] as String? ?? '—';
    final position = data['position'] as String? ?? '—';
    final salary = (data['salary'] as num?)?.toDouble();
    final isActive = _isActiveStaff(data);
    final joinDate = (data['joinDate'] as Timestamp?)?.toDate();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      child: Row(
        children: [
          Expanded(
            flex: 28,
            child: Row(
              children: [
                _Avatar(name: name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppThemeColors.darkText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppThemeColors.darkMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              empId.isNotEmpty ? empId : '—',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: _mtmPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              dept,
              style: const TextStyle(
                fontSize: 13,
                color: AppThemeColors.darkText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              position,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppThemeColors.darkText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              _formatSalary(salary),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppThemeColors.darkText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 12,
            child: _StatusBadge(isActive: isActive),
          ),
          Expanded(
            flex: 14,
            child: Text(
              joinDate != null
                  ? DateFormat('dd MMM yyyy').format(joinDate)
                  : '—',
              style: const TextStyle(
                fontSize: 13.5,
                color: AppThemeColors.darkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile Card ─────────────────────────────────────────────────────────────

class _MobileStaffCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MobileStaffCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unknown';
    final email = data['email'] as String? ?? '';
    final empId = data['employeeId'] as String? ?? '';
    final dept = data['department'] as String? ?? '—';
    final position = data['position'] as String? ?? '—';
    final salary = (data['salary'] as num?)?.toDouble();
    final isActive = _isActiveStaff(data);
    final joinDate = (data['joinDate'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _mtmShadowSoft,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(name: name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppThemeColors.darkText,
                        ),
                      ),
                    ),
                    _StatusBadge(isActive: isActive),
                  ],
                ),
                if (email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppThemeColors.darkMuted,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (empId.isNotEmpty)
                      _Chip(label: empId, color: _mtmPrimary),
                    _Chip(label: dept, color: AppThemeColors.darkText),
                    _Chip(label: position, color: AppThemeColors.darkMuted),
                    if (salary != null)
                      _Chip(
                        label: _formatSalary(salary),
                        color: _mtmPrimary,
                      ),
                  ],
                ),
                if (joinDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Joined: ${DateFormat('dd MMM yyyy').format(joinDate)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppThemeColors.darkMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  static const List<Color> _colors = [
    _mtmRed,
    _mtmBlue,
    _mtmGreen,
    _mtmAmber,
    _mtmViolet,
    _mtmPink,
    _mtmCyan,
    _mtmLime,
  ];

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _colors[name.codeUnitAt(0) % _colors.length];
    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }
}

bool _isActiveStaff(Map<String, dynamic> data) {
  final rawStatus = data['status']?.toString().toLowerCase().trim();
  if (rawStatus != null && rawStatus.isNotEmpty) {
    return rawStatus == 'active';
  }
  return data['isActive'] as bool? ?? true;
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? _mtmTintGreen : _mtmTintAmber,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? _mtmGreenDeep : _mtmAmberDeep,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Active' : 'On Leave',
            style: TextStyle(
              color: isActive ? _mtmGreenDeep : _mtmAmberDeep,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  const _ColLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppThemeColors.darkMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}

String _formatSalary(double? salary) {
  if (salary == null) return '-';
  return 'INR ${NumberFormat.decimalPattern().format(salary)}';
}
