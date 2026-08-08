import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../services/company_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/platform_export.dart';
import 'portal_widgets.dart';

class ReportsModule extends StatefulWidget {
  const ReportsModule({super.key});

  @override
  State<ReportsModule> createState() => _ReportsModuleState();
}

class _ReportsModuleState extends State<ReportsModule> {
  final _companyService = CompanyService();
  final _platform = PlatformService();
  String? _generating;

  Future<void> _generate(
    String key, {
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() rows,
  }) async {
    if (_generating != null) return;
    setState(() => _generating = key);
    final dateStamp = DateFormat('yyyyMMdd').format(DateTime.now());
    try {
      final data = await rows();
      await PlatformExport.toCsv(
        name: '${key}_$dateStamp',
        headers: headers,
        rows: data,
      );
      if (!mounted) return;
      _snack('CSV report downloaded.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not generate report: $e', error: true);
    } finally {
      if (mounted) setState(() => _generating = null);
    }
  }

  Future<void> _generateExcel(
    String key, {
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() rows,
  }) async {
    if (_generating != null) return;
    setState(() => _generating = key);
    final dateStamp = DateFormat('yyyyMMdd').format(DateTime.now());
    try {
      await PlatformExport.toExcel(
        name: '${key}_$dateStamp',
        headers: headers,
        rows: await rows(),
      );
      if (!mounted) return;
      _snack('Excel report downloaded.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not generate report: $e', error: true);
    } finally {
      if (mounted) setState(() => _generating = null);
    }
  }

  Future<void> _generatePdf(
    String key, {
    required String title,
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() rows,
  }) async {
    if (_generating != null) return;
    setState(() => _generating = key);
    final dateStamp = DateFormat('yyyyMMdd').format(DateTime.now());
    try {
      await PlatformExport.toPdf(
        name: '${key}_$dateStamp',
        title: title,
        headers: headers,
        rows: await rows(),
      );
      if (!mounted) return;
      _snack('PDF report downloaded.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not generate report: $e', error: true);
    } finally {
      if (mounted) setState(() => _generating = null);
    }
  }

  Future<List<List<dynamic>>> _companyRows() async {
    final companies = await _companyService.getAllCompanies();
    return [
      for (final c in companies)
        [
          c.name,
          c.email ?? '',
          c.industry ?? '',
          c.companySize ?? '',
          c.country ?? '',
          c.plan,
          c.subscriptionStatus,
          c.billingCycle,
          c.isActive ? 'Active' : 'Suspended',
          c.createdAt,
        ],
    ];
  }

  Future<List<List<dynamic>>> _userRows() async {
    final users = await _platform.streamUsers(limit: 1000).first;
    return [
      for (final u in users)
        [
          u.name,
          u.email,
          u.role,
          u.phone,
          u.companyId ?? '',
          u.isActive ? 'Active' : 'Inactive',
          u.createdAt,
          u.lastLoginAt,
        ],
    ];
  }

  Future<List<List<dynamic>>> _subscriptionRows() async {
    final companies = await _companyService.getAllCompanies();
    return [
      for (final c in companies)
        [
          c.name,
          c.plan,
          c.subscriptionStatus,
          c.billingCycle,
          c.renewsAt,
          c.isActive ? 'Active' : 'Suspended',
        ],
    ];
  }

  Future<List<List<dynamic>>> _invoiceRows() async {
    final invoices = await _platform.streamInvoices(limit: 1000).first;
    return [
      for (final i in invoices)
        [
          i.companyName,
          i.description,
          i.amount.toStringAsFixed(2),
          i.currency,
          i.status,
          i.issueDate,
          i.dueDate,
          i.paidAt,
        ],
    ];
  }

  Future<List<List<dynamic>>> _ticketRows() async {
    final snap = await FirebaseContextProvider.current.firestore
        .collection('support_tickets')
        .limit(1000)
        .get();
    return [
      for (final doc in snap.docs)
        [
          doc.data()['companyName'] ?? '',
          doc.data()['subject'] ?? '',
          doc.data()['message'] ?? '',
          doc.data()['status'] ?? 'open',
          doc.data()['createdBy'] ?? '',
          (doc.data()['createdAt'] as Timestamp?)?.toDate(),
        ],
    ];
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CoPageHeader(
                title: 'Reports',
                subtitle:
                    'Download platform-wide reports as CSV, Excel, or PDF.',
              ),
              const SizedBox(height: 20),
              _reportCard(
                key: 'companies',
                icon: Icons.apartment_rounded,
                title: 'Companies directory',
                description:
                    'All companies with contact details, plan, status, and '
                    'creation date.',
                headers: const [
                  'Name',
                  'Email',
                  'Industry',
                  'Size',
                  'Country',
                  'Plan',
                  'Status',
                  'Cycle',
                  'Active',
                  'Created',
                ],
                rows: _companyRows,
              ),
              const SizedBox(height: 14),
              _reportCard(
                key: 'users',
                icon: Icons.group_rounded,
                title: 'Users directory',
                description:
                    'All login accounts across the platform with roles and '
                    'activity dates.',
                headers: const [
                  'Name',
                  'Email',
                  'Role',
                  'Phone',
                  'CompanyId',
                  'Active',
                  'Created',
                  'Last login',
                ],
                rows: _userRows,
              ),
              const SizedBox(height: 14),
              _reportCard(
                key: 'subscriptions',
                icon: Icons.workspace_premium_outlined,
                title: 'Subscriptions',
                description:
                    'Plan, subscription status, billing cycle, and renewal '
                    'dates for every company.',
                headers: const [
                  'Company',
                  'Plan',
                  'Status',
                  'Cycle',
                  'Renews',
                  'Active',
                ],
                rows: _subscriptionRows,
              ),
              const SizedBox(height: 14),
              _reportCard(
                key: 'revenue',
                icon: Icons.payments_outlined,
                title: 'Revenue (invoices)',
                description:
                    'All invoices with amounts, statuses, and payment dates.',
                headers: const [
                  'Company',
                  'Description',
                  'Amount',
                  'Currency',
                  'Status',
                  'Issue date',
                  'Due date',
                  'Paid',
                ],
                rows: _invoiceRows,
              ),
              const SizedBox(height: 14),
              _reportCard(
                key: 'support_tickets',
                icon: Icons.support_agent_outlined,
                title: 'Support tickets',
                description:
                    'All support tickets from client companies with statuses.',
                headers: const [
                  'Company',
                  'Subject',
                  'Message',
                  'Status',
                  'Created by',
                  'Created',
                ],
                rows: _ticketRows,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportCard({
    required String key,
    required IconData icon,
    required String title,
    required String description,
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() rows,
  }) {
    final generating = _generating == key;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCoBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: kCoAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: kCoAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: kCoLabel,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: kCoSubtle,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            children: [
              _downloadButton('CSV', generating, () async {
                await _generate(key, headers: headers, rows: rows);
              }),
              _downloadButton('Excel', generating, () async {
                await _generateExcel(key, headers: headers, rows: rows);
              }),
              _downloadButton('PDF', generating, () async {
                await _generatePdf(
                  key,
                  title: title,
                  headers: headers,
                  rows: rows,
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _downloadButton(
    String label,
    bool generating,
    Future<void> Function() onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: generating ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: generating ? kCoSubtle : kCoAccent,
        side: const BorderSide(color: kCoBorder),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: generating
          ? const SizedBox(
              width: 14,
              height: 14,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: kCoSubtle),
            )
          : const Icon(Icons.download_rounded, size: 16),
      label: Text(label),
    );
  }
}
