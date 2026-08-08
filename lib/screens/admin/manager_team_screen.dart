// lib/screens/admin/manager_team_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/staff.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';

// Fixed-brand palette for the manager team screen (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _teamPrimary = Color(0xFF0F766E);
const Color _teamShadow = Color(0x1A6B7897);
const Color _teamGreen = Color(0xFF4CAF50);
const Color _teamGrey = Color(0xFF9E9E9E);

class ManagerTeamScreen extends StatefulWidget {
  final String managerName;
  final String managerId;

  const ManagerTeamScreen({
    super.key,
    required this.managerName,
    required this.managerId,
  });

  @override
  State<ManagerTeamScreen> createState() => _ManagerTeamScreenState();
}

class _ManagerTeamScreenState extends State<ManagerTeamScreen> {
  final StaffService _staffService = StaffService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppThemeColors.darkText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.managerName}\'s Team',
              style: const TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Text(
              'Management and oversight of direct reports',
              style: TextStyle(
                color: AppThemeColors.darkMuted,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            _buildTeamTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppThemeColors.darkBorder),
        boxShadow: const [
          BoxShadow(
            color: _teamShadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: StreamBuilder<List<Staff>>(
        stream: _staffService.getTeamMembersByManager(widget.managerName),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child:
                  Center(child: CircularProgressIndicator(color: _teamPrimary)),
            );
          }

          var members = snapshot.data ?? [];

          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            members = members
                .where((m) =>
                    m.name.toLowerCase().contains(q) ||
                    m.employeeId.toLowerCase().contains(q))
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isSmall = constraints.maxWidth < 450;
                    final searchBar = TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      cursorColor: _teamPrimary,
                      style: const TextStyle(
                        color: AppThemeColors.darkText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search team member...',
                        hintStyle:
                            const TextStyle(color: AppThemeColors.darkMuted),
                        prefixIcon: const Icon(Icons.search,
                            size: 20, color: _teamPrimary),
                        filled: true,
                        fillColor: AppThemeColors.darkCanvas,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppThemeColors.darkBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppThemeColors.darkBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _teamPrimary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                    );

                    final membersCount = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: _teamPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${members.length} Members',
                        style: const TextStyle(
                          color: _teamPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );

                    if (isSmall) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          searchBar,
                          const SizedBox(height: 12),
                          membersCount,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: searchBar),
                        const SizedBox(width: 16),
                        membersCount,
                      ],
                    );
                  },
                ),
              ),

              if (members.isEmpty)
                const SizedBox(
                  height: 150,
                  child: Center(
                    child: Text(
                      'No team members found.',
                      style: TextStyle(color: AppThemeColors.darkMuted),
                    ),
                  ),
                )
              else
                _TeamMembersTable(members: members),
            ],
          );
        },
      ),
    );
  }
}

class _TeamMembersTable extends StatelessWidget {
  final List<Staff> members;

  const _TeamMembersTable({required this.members});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _MemberRow(member: members[index]),
          );
        }

        const minWidth = 1040.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth > minWidth
                  ? constraints.maxWidth
                  : minWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                  decoration: const BoxDecoration(
                    color: AppThemeColors.darkCanvas,
                    border: Border.symmetric(
                      horizontal: BorderSide(color: AppThemeColors.darkBorder),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 28, child: _HeaderLabel('EMPLOYEE')),
                      Expanded(flex: 28, child: _HeaderLabel('CONTACT')),
                      Expanded(flex: 20, child: _HeaderLabel('POSITION')),
                      Expanded(flex: 18, child: _HeaderLabel('DESIGNATION')),
                      Expanded(flex: 14, child: _HeaderLabel('SALARY')),
                      Expanded(flex: 12, child: _HeaderLabel('STATUS')),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: AppThemeColors.darkBorder,
                  ),
                  itemBuilder: (context, index) =>
                      _MemberRow(member: members[index]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String label;
  const _HeaderLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppThemeColors.darkMuted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Staff member;
  const _MemberRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _teamPrimary.withValues(alpha: 0.1),
                  child: Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: _teamPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(
                          color: AppThemeColors.darkText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        member.employeeId,
                        style: const TextStyle(
                          color: AppThemeColors.darkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (member.isActive ? _teamGreen : _teamGrey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    member.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: member.isActive ? _teamGreen : _teamGrey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppThemeColors.darkBorder,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.work_outline,
                          size: 16, color: AppThemeColors.darkMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'POSITION',
                              style: TextStyle(
                                color: AppThemeColors.darkMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              member.position,
                              style: const TextStyle(
                                color: AppThemeColors.darkText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
                  child: Row(
                    children: [
                      const Icon(Icons.business_outlined,
                          size: 16, color: AppThemeColors.darkMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DESIGNATION',
                              style: TextStyle(
                                color: AppThemeColors.darkMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              member.department,
                              style: const TextStyle(
                                color: AppThemeColors.darkText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
              ],
            ),
            if (member.salary != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: AppThemeColors.darkMuted),
                  const SizedBox(width: 8),
                  Text(
                    _formatSalary(member.salary),
                    style: const TextStyle(
                      color: AppThemeColors.darkText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      child: Row(
        children: [
          Expanded(
            flex: 28,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _teamPrimary.withValues(alpha: 0.1),
                  child: Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: _teamPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(
                          color: AppThemeColors.darkText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        member.employeeId,
                        style: const TextStyle(
                          color: AppThemeColors.darkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.email,
                  style: const TextStyle(
                    color: AppThemeColors.darkText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  member.phone.isNotEmpty ? member.phone : '-',
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 20,
            child: Text(
              member.position,
              style: const TextStyle(
                  color: AppThemeColors.darkMuted, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              member.department,
              style: const TextStyle(
                  color: AppThemeColors.darkMuted, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              _formatSalary(member.salary),
              style: const TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: (member.isActive ? _teamGreen : _teamGrey)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  member.isActive ? 'Active' : 'Inactive',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: member.isActive ? _teamGreen : _teamGrey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSalary(double? salary) {
  if (salary == null) return '-';
  return 'INR ${NumberFormat.decimalPattern().format(salary)}';
}
