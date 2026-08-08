import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/company.dart';
import '../../services/company_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class SupportModule extends StatefulWidget {
  const SupportModule({super.key});

  @override
  State<SupportModule> createState() => _SupportModuleState();
}

class _SupportModuleState extends State<SupportModule> {
  final _companyService = CompanyService();
  List<Company> _companies = const [];
  String _statusFilter = 'all';

  Future<void> _openTicket() async {
    if (_companies.isEmpty) {
      _snack('Create a company before opening a ticket.', error: true);
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NewTicketDialog(companies: _companies),
    );
    if (result == null || !mounted) return;
    try {
      await FirebaseContextProvider.current.firestore
          .collection('support_tickets')
          .add({
        'companyId': result['companyId'],
        'companyName': result['companyName'],
        'subject': result['subject'],
        'message': result['message'],
        'status': 'open',
        'createdBy': 'Super Admin',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await PlatformService().bumpStats({
        'openTickets': 1,
      });
      await PlatformService().recordAudit(
        category: 'support',
        action: 'opened support ticket',
        targetType: 'support_ticket',
        targetName: result['subject'] as String,
        changes: {'company': result['companyName'] as String},
      );
      if (!mounted) return;
      _snack('Support ticket created.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not create ticket: $e', error: true);
    }
  }

  Future<void> _setStatus(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required bool resolved,
  }) async {
    try {
      await doc.reference.update({
        'status': resolved ? 'resolved' : 'open',
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });
      await PlatformService().bumpStats({
        'openTickets': resolved ? -1 : 1,
        'closedTickets': resolved ? 1 : -1,
      });
      await PlatformService().recordAudit(
        category: 'support',
        action:
            resolved ? 'resolved support ticket' : 'reopened support ticket',
        targetType: 'support_ticket',
        targetName: doc.data()?['subject'] as String?,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update ticket: $e', error: true);
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
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 16,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: StreamBuilder<List<Company>>(
            stream: _companyService.streamAllCompanies(),
            builder: (context, companiesSnap) {
              _companies = companiesSnap.data ?? const [];
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseContextProvider.current.firestore
                    .collection('support_tickets')
                    .orderBy('createdAt', descending: true)
                    .limit(100)
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? const [];
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final open = docs.where((d) {
                    return (d.data()['status'] as String? ?? 'open') == 'open';
                  }).length;
                  final resolved = docs.length - open;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(loading),
                      const SizedBox(height: 18),
                      _kpiRow(open, resolved),
                      const SizedBox(height: 16),
                      _filterRow(),
                      const SizedBox(height: 16),
                      _buildTickets(docs, loading, open, resolved),
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

  Widget _buildHeader(bool loading) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Support',
                style: TextStyle(
                  color: kCoLabel,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                loading
                    ? 'Support tickets from client companies.'
                    : 'Manage support tickets from client companies directly '
                        'from the platform.',
                style: const TextStyle(
                    color: kCoSubtle, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: _openTicket,
          style: FilledButton.styleFrom(
            backgroundColor: kCoAccent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New Ticket'),
        ),
      ],
    );
  }

  Widget _kpiRow(int open, int resolved) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi(
              width: cardWidth,
              label: 'Open tickets',
              value: open,
              icon: Icons.markunread_mailbox_outlined,
              color: kCoAmber,
            ),
            _kpi(
              width: cardWidth,
              label: 'Resolved tickets',
              value: resolved,
              icon: Icons.check_circle_outline_rounded,
              color: kCoGreen,
            ),
            _kpi(
              width: cardWidth,
              label: 'Total tickets',
              value: open + resolved,
              icon: Icons.support_agent_outlined,
              color: kCoAccent,
            ),
          ],
        );
      },
    );
  }

  Widget _kpi({
    required double width,
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCoBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: kCoLabel,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: kCoSubtle, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterRow() {
    return Row(
      children: [
        _filterChip('all', 'All tickets'),
        const SizedBox(width: 8),
        _filterChip('open', 'Open'),
        const SizedBox(width: 8),
        _filterChip('resolved', 'Resolved'),
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? kCoAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? kCoAccent : kCoBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? kCoAccent : kCoSubtle,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTickets(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool loading,
    int open,
    int resolved,
  ) {
    final filtered = docs.where((d) {
      final status = d.data()['status'] as String? ?? 'open';
      if (_statusFilter == 'open') return status == 'open';
      if (_statusFilter == 'resolved') return status == 'resolved';
      return true;
    }).toList();
    return CoSectionCard(
      title: 'Tickets',
      subtitle: 'Latest support tickets from companies.',
      icon: Icons.support_agent_outlined,
      child: loading && docs.isEmpty
          ? const CoEmptyState(
              icon: Icons.hourglass_empty_rounded, message: 'Loading…')
          : filtered.isEmpty
              ? const CoEmptyState(
                  icon: Icons.support_agent_outlined,
                  message: 'No tickets match the current filter.')
              : Column(
                  children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i > 0) const Divider(color: kCoBorder, height: 1),
                      _ticketRow(filtered[i]),
                    ],
                  ],
                ),
    );
  }

  Widget _ticketRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final isResolved = (data['status'] as String? ?? 'open') == 'resolved';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final color = isResolved ? kCoGreen : kCoAmber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isResolved
                  ? Icons.check_circle_outline_rounded
                  : Icons.markunread_mailbox_outlined,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (data['subject'] as String? ?? 'Untitled'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kCoLabel,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusChip(isResolved),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  (data['companyName'] as String? ?? 'Unknown company'),
                  style: const TextStyle(
                      color: kCoAccent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  (data['message'] as String? ?? ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kCoSubtle, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 5),
                Text(
                  createdAt == null
                      ? '—'
                      : DateFormat('dd MMM yyyy, hh:mm a').format(createdAt),
                  style: const TextStyle(color: kCoSubtle, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () => _setStatus(doc, resolved: !isResolved),
            icon: Icon(
              isResolved ? Icons.replay_rounded : Icons.done_all_rounded,
              size: 15,
            ),
            label: Text(isResolved ? 'Reopen' : 'Resolve'),
            style: TextButton.styleFrom(
              foregroundColor: isResolved ? kCoAmber : kCoAccent,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool isResolved) {
    final color = isResolved ? kCoGreen : kCoAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isResolved ? 'Resolved' : 'Open',
        style: TextStyle(
            color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NewTicketDialog extends StatefulWidget {
  final List<Company> companies;

  const _NewTicketDialog({required this.companies});

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  String? _companyId;
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kCoBorder),
      ),
      title: const Text('New support ticket',
          style: TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Company',
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
                    value: _companyId,
                    hint: const Text('Select company',
                        style: TextStyle(color: kCoSubtle, fontSize: 13)),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: kCoSubtle),
                    items: widget.companies
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
                    onChanged: (v) => setState(() => _companyId = v),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _subjectCtrl,
                style: const TextStyle(color: kCoLabel, fontSize: 14),
                decoration: _decoration('Subject'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Subject is required'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _messageCtrl,
                style: const TextStyle(color: kCoLabel, fontSize: 14),
                maxLines: 4,
                decoration: _decoration('Describe the issue…'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Message is required'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: kCoSubtle)),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            if (_companyId == null) return;
            final company = _companyById(_companyId!);
            Navigator.of(context).pop(<String, dynamic>{
              'companyId': _companyId,
              'companyName': company?.name ?? 'Unknown',
              'subject': _subjectCtrl.text.trim(),
              'message': _messageCtrl.text.trim(),
            });
          },
          style: FilledButton.styleFrom(backgroundColor: kCoAccent),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Company? _companyById(String id) {
    for (final company in widget.companies) {
      if (company.id == id) return company;
    }
    return null;
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
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
