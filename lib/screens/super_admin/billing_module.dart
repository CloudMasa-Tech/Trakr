import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/company.dart';
import '../../models/platform_models.dart';
import '../../services/company_service.dart';
import '../../services/platform_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/platform_export.dart';
import 'portal_widgets.dart';

class BillingModule extends StatefulWidget {
  const BillingModule({super.key});

  @override
  State<BillingModule> createState() => _BillingModuleState();
}

class _BillingModuleState extends State<BillingModule> {
  final _platform = PlatformService();
  final _companyService = CompanyService();

  List<Company> _companies = const [];

  @override
  void initState() {
    super.initState();
    _companyService.getAllCompanies().then((companies) {
      if (mounted) setState(() => _companies = companies);
    });
  }

  Future<void> _createInvoice() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _InvoiceDialog(companies: _companies),
    );
    if (result == null || !mounted) return;
    try {
      await _platform.createInvoice(
        companyId: result['companyId'],
        companyName: result['companyName'],
        description: result['description'],
        amount: result['amount'],
        currency: result['currency'],
        status: result['status'],
        dueDate: result['dueDate'] as DateTime?,
      );
      await _platform.recordActivity(
        type: 'billing',
        title: 'Invoice created',
        detail: '${coMoney(result['amount'], result['currency'])} invoice for '
            '${result['companyName']}.',
        companyId: result['companyId'],
        companyName: result['companyName'],
      );
      await _platform.recordAudit(
        category: 'Billing',
        action: 'create_invoice',
        targetType: 'company',
        targetId: result['companyId'],
        targetName: result['companyName'],
        changes: {'amount': result['amount']},
      );
      if (!mounted) return;
      _snack('Invoice created.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not create invoice: $e', error: true);
    }
  }

  Future<void> _recordPayment() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentDialog(companies: _companies),
    );
    if (result == null || !mounted) return;
    try {
      await _platform.recordPayment(
        companyId: result['companyId'],
        companyName: result['companyName'],
        amount: result['amount'],
        currency: result['currency'],
        method: result['method'],
        reference: result['reference'] as String?,
      );
      await _bumpRevenue(result['amount'], result['currency']);
      await _platform.recordActivity(
        type: 'billing',
        title: 'Payment recorded',
        detail:
            '${coMoney(result['amount'], result['currency'])} received from '
            '${result['companyName']}.',
        companyId: result['companyId'],
        companyName: result['companyName'],
      );
      await _platform.recordAudit(
        category: 'Billing',
        action: 'record_payment',
        targetType: 'company',
        targetId: result['companyId'],
        targetName: result['companyName'],
        changes: {'amount': result['amount'], 'method': result['method']},
      );
      if (!mounted) return;
      _snack('Payment recorded.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not record payment: $e', error: true);
    }
  }

  Future<void> _bumpRevenue(double amount, String currency) async {
    if (currency != 'USD') {
      // Revenue counters are normalized to USD; non-USD payments still count
      // in the totals at face value for simplicity.
    }
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await _platform.bumpStats({
      'totalRevenue': amount,
      'monthlyRevenue': amount,
      'revenueByMonth.$monthKey': amount,
    });
  }

  Future<void> _markInvoicePaid(Invoice invoice) async {
    final confirmed = await _confirm(
      title: 'Mark invoice as paid',
      message: '${coMoney(invoice.amount, invoice.currency)} will be added to '
          'recognized revenue for ${invoice.companyName}.',
      confirmLabel: 'Mark paid',
    );
    if (!confirmed || !mounted) return;
    try {
      await _platform.markInvoicePaid(invoice.id);
      await _bumpRevenue(invoice.amount, invoice.currency);
      await _platform.recordActivity(
        type: 'billing',
        title: 'Invoice paid',
        detail:
            '${coMoney(invoice.amount, invoice.currency)} — ${invoice.companyName}.',
        companyId: invoice.companyId,
        companyName: invoice.companyName,
      );
      await _platform.recordAudit(
        category: 'Billing',
        action: 'mark_invoice_paid',
        targetType: 'company',
        targetId: invoice.companyId,
        targetName: invoice.companyName,
        changes: {'invoiceId': invoice.id, 'amount': invoice.amount},
      );
      if (!mounted) return;
      _snack('Invoice marked as paid.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not update invoice: $e', error: true);
    }
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirmed = await _confirm(
      title: 'Delete invoice?',
      message:
          'This permanently removes the invoice for ${invoice.companyName}.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _platform.deleteInvoice(invoice.id);
      if (!mounted) return;
      _snack('Invoice deleted.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not delete invoice: $e', error: true);
    }
  }

  Future<void> _exportInvoices(List<Invoice> invoices) async {
    await PlatformExport.toCsv(
      name: 'invoices_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      headers: const [
        'Company',
        'Description',
        'Amount',
        'Currency',
        'Status',
        'Issue date',
        'Due date'
      ],
      rows: [
        for (final i in invoices)
          [
            i.companyName,
            i.description,
            i.amount.toStringAsFixed(2),
            i.currency,
            i.status,
            i.issueDate,
            i.dueDate,
          ],
      ],
    );
  }

  Future<void> _exportPayments(List<Payment> payments) async {
    await PlatformExport.toCsv(
      name: 'payments_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      headers: const [
        'Company',
        'Amount',
        'Currency',
        'Method',
        'Reference',
        'Date'
      ],
      rows: [
        for (final p in payments)
          [
            p.companyName,
            p.amount.toStringAsFixed(2),
            p.currency,
            p.method,
            p.reference ?? '',
            p.paidAt ?? p.createdAt,
          ],
      ],
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
          child: StreamBuilder<PlatformStats>(
            stream: _platform.streamStats(),
            builder: (context, statsSnap) {
              final stats =
                  statsSnap.data ?? const PlatformStats(totalCompanies: -1);
              final loading = stats.totalCompanies < 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CoPageHeader(
                    title: 'Billing',
                    subtitle: 'Revenue, invoices, and payments for the whole '
                        'platform.',
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _createInvoice,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kCoAccent,
                          side: const BorderSide(color: kCoBorder),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        icon:
                            const Icon(Icons.request_quote_outlined, size: 18),
                        label: const Text('New Invoice'),
                      ),
                      FilledButton.icon(
                        onPressed: _recordPayment,
                        style: FilledButton.styleFrom(
                          backgroundColor: kCoAccent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('Record Payment'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildMetrics(stats, loading),
                  const SizedBox(height: 24),
                  _buildRevenueChart(stats, loading),
                  const SizedBox(height: 24),
                  _buildLists(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMetrics(PlatformStats stats, bool loading) {
    final metrics = [
      CoMetricCard(
        icon: Icons.trending_up_rounded,
        label: 'Monthly Revenue',
        value: loading ? '—' : coMoney(stats.monthlyRevenue, 'USD'),
        accent: kCoCyan,
      ),
      CoMetricCard(
        icon: Icons.savings_outlined,
        label: 'Total Revenue',
        value: loading ? '—' : coMoney(stats.totalRevenue, 'USD'),
        accent: kCoGreen,
      ),
      CoMetricCard(
        icon: Icons.verified_outlined,
        label: 'Active Subscriptions',
        value: loading ? '—' : '${stats.activeSubscriptions}',
        accent: kCoBlue,
      ),
      CoMetricCard(
        icon: Icons.request_quote_outlined,
        label: 'Paid Subscriptions',
        value: loading ? '—' : '${stats.paidSubscriptions}',
        accent: kCoViolet,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        const spacing = 12.0;
        final itemWidth = (c.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final m in metrics) SizedBox(width: itemWidth, child: m),
          ],
        );
      },
    );
  }

  Widget _buildRevenueChart(PlatformStats stats, bool loading) {
    final months = _lastMonths(6);
    final hasData = months.any((m) => (stats.revenueByMonth[m.key] ?? 0) > 0);
    final maxRevenue = months.fold<double>(1, (acc, m) {
      final r = stats.revenueByMonth[m.key] ?? 0;
      return r > acc ? r : acc;
    });
    return CoSectionCard(
      title: 'Revenue trend',
      subtitle: 'Revenue recognized in the last 6 months (USD).',
      icon: Icons.attach_money_rounded,
      child: loading
          ? const CoInlineLoading()
          : SizedBox(
              height: 180,
              child: !hasData
                  ? const CoEmptyState(
                      icon: Icons.payments_outlined,
                      message: 'No revenue recorded yet. Create invoices and '
                          'record payments to build your revenue history.')
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxRevenue,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: kCoBorder,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => AppThemeColors.darkCanvas,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                '${months[group.x].label}\n${coMoney(rod.toY, 'USD')}',
                                const TextStyle(
                                  color: kCoLabel,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= months.length) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    months[i].label,
                                    style: const TextStyle(
                                      color: kCoSubtle,
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: List.generate(months.length, (i) {
                          final revenue =
                              stats.revenueByMonth[months[i].key] ?? 0;
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: revenue,
                                color: kCoCyan,
                                width: 16,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
            ),
    );
  }

  List<({String key, String label})> _lastMonths(int count) {
    final now = DateTime.now();
    final list = <({String key, String label})>[];
    for (var i = count - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      list.add((
        key: '${date.year}-${date.month.toString().padLeft(2, '0')}',
        label: DateFormat('MMM').format(date),
      ));
    }
    return list;
  }

  Widget _buildLists() {
    return LayoutBuilder(
      builder: (context, c) {
        final invoices = _buildInvoices();
        final payments = _buildPayments();
        if (c.maxWidth < 1000) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              invoices,
              const SizedBox(height: 18),
              payments,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: invoices),
            const SizedBox(width: 18),
            Expanded(child: payments),
          ],
        );
      },
    );
  }

  Widget _buildInvoices() {
    return CoSectionCard(
      title: 'Invoices',
      subtitle: 'Latest invoices issued to companies.',
      icon: Icons.request_quote_outlined,
      child: StreamBuilder<List<Invoice>>(
        stream: _platform.streamInvoices(limit: 50),
        builder: (context, snapshot) {
          final invoices = snapshot.data ?? const <Invoice>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              invoices.isEmpty) {
            return const CoInlineLoading();
          }
          if (invoices.isEmpty) {
            return const CoEmptyState(
              icon: Icons.request_quote_outlined,
              message: 'No invoices yet.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  for (var i = 0; i < invoices.length; i++) ...[
                    if (i > 0) const Divider(color: kCoBorder, height: 1),
                    _invoiceRow(invoices[i]),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _exportInvoices(invoices),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Export CSV'),
                  style: TextButton.styleFrom(
                    foregroundColor: kCoAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _invoiceRow(Invoice invoice) {
    final (color, label) = switch (invoice.status) {
      'paid' => (kCoGreen, 'Paid'),
      'overdue' => (kCoRed, 'Overdue'),
      'sent' => (kCoBlue, 'Sent'),
      _ => (kCoGrey, 'Draft'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.receipt_long_outlined, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.companyName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kCoLabel,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  invoice.description,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kCoSubtle, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  invoice.issueDate == null
                      ? '—'
                      : DateFormat('dd MMM yyyy').format(invoice.issueDate!),
                  style: const TextStyle(color: kCoSubtle, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                coMoney(invoice.amount, invoice.currency),
                style: const TextStyle(
                    color: kCoLabel, fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              CoStatusBadge(label: label, color: color),
            ],
          ),
          const SizedBox(width: 4),
          if (invoice.status != 'paid')
            IconButton(
              onPressed: () => _markInvoicePaid(invoice),
              icon:
                  const Icon(Icons.done_all_rounded, color: kCoGreen, size: 18),
              tooltip: 'Mark paid',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: () => _deleteInvoice(invoice),
            icon: const Icon(Icons.delete_outline_rounded,
                color: kCoRed, size: 18),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildPayments() {
    return CoSectionCard(
      title: 'Payments',
      subtitle: 'Latest payments received.',
      icon: Icons.payments_outlined,
      child: StreamBuilder<List<Payment>>(
        stream: _platform.streamPayments(limit: 50),
        builder: (context, snapshot) {
          final payments = snapshot.data ?? const <Payment>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              payments.isEmpty) {
            return const CoInlineLoading();
          }
          if (payments.isEmpty) {
            return const CoEmptyState(
              icon: Icons.payments_outlined,
              message: 'No payments recorded yet.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  for (var i = 0; i < payments.length; i++) ...[
                    if (i > 0) const Divider(color: kCoBorder, height: 1),
                    _paymentRow(payments[i]),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _exportPayments(payments),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Export CSV'),
                  style: TextButton.styleFrom(
                    foregroundColor: kCoAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _paymentRow(Payment payment) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: kCoGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: kCoGreen, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.companyName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kCoLabel,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${payment.method}'
                  '${payment.reference != null && payment.reference!.isNotEmpty ? ' • ${payment.reference}' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kCoSubtle, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  payment.paidAt == null
                      ? '—'
                      : DateFormat('dd MMM yyyy').format(payment.paidAt!),
                  style: const TextStyle(color: kCoSubtle, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Text(
            coMoney(payment.amount, payment.currency),
            style: const TextStyle(
                color: kCoGreen, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InvoiceDialog extends StatefulWidget {
  final List<Company> companies;

  const _InvoiceDialog({required this.companies});

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  String? _companyId;
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _status = 'sent';
  String _currency = 'USD';
  DateTime? _dueDate;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Company? get _company =>
      widget.companies.where((c) => c.id == _companyId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kCoBorder),
      ),
      title: const Text('New invoice',
          style: TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _companyDropdown(),
                const SizedBox(height: 12),
                _field(_descCtrl, 'Description', hint: 'e.g. Pro plan — July'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(_amountCtrl, 'Amount',
                          hint: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true)),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 110,
                      child: _currencyDropdown(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _statusDropdown(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _pickDueDate(),
                        icon: const Icon(Icons.event_rounded, size: 16),
                        label: Text(
                          _dueDate == null
                              ? 'Due date'
                              : DateFormat('dd MMM yyyy').format(_dueDate!),
                          style: const TextStyle(color: kCoAccent),
                        ),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: kCoAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
            Navigator.of(context).pop(<String, dynamic>{
              'companyId': _companyId,
              'companyName': _company?.name ?? 'Unknown',
              'description': _descCtrl.text.trim(),
              'amount': double.tryParse(_amountCtrl.text.trim()) ?? 0,
              'currency': _currency,
              'status': _status,
              if (_dueDate != null) 'dueDate': _dueDate,
            });
          },
          style: FilledButton.styleFrom(backgroundColor: kCoAccent),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _companyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Company',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
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
                        child: Text(c.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _companyId = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _currencyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Currency',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCoBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: _currency,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kCoSubtle),
              items: const [
                DropdownMenuItem(value: 'USD', child: Text('USD')),
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                DropdownMenuItem(value: 'INR', child: Text('INR')),
              ]
                  .map((e) => DropdownMenuItem(
                        value: e.value as String,
                        child: Text(e.child.toString(),
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Status',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
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
              value: _status,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kCoSubtle),
              items: const ['draft', 'sent', 'paid']
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s,
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: kCoLabel, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: kCoSubtle, fontSize: 13),
        hintStyle: const TextStyle(color: kCoSubtle, fontSize: 13),
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
        if (value == null || value.trim().isEmpty) {
          return '$label is required';
        }
        if (controller == _amountCtrl &&
            (double.tryParse(value.trim()) ?? 0) <= 0) {
          return 'Enter a valid amount';
        }
        return null;
      },
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kCoAccent,
            surface: AppThemeColors.darkSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }
}

class _PaymentDialog extends StatefulWidget {
  final List<Company> companies;

  const _PaymentDialog({required this.companies});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String? _companyId;
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  String _method = 'Card';
  String _currency = 'USD';
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  Company? get _company =>
      widget.companies.where((c) => c.id == _companyId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kCoBorder),
      ),
      title: const Text('Record payment',
          style: TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w800, fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _companyDropdown(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: kCoLabel, fontSize: 14),
                decoration: _decoration('Amount'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  if ((double.tryParse(v.trim()) ?? 0) <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _methodDropdown(),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: _currencyDropdown(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenceCtrl,
                style: const TextStyle(color: kCoLabel, fontSize: 14),
                decoration: _decoration('Reference (optional)'),
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
            Navigator.of(context).pop(<String, dynamic>{
              'companyId': _companyId,
              'companyName': _company?.name ?? 'Unknown',
              'amount': double.tryParse(_amountCtrl.text.trim()) ?? 0,
              'currency': _currency,
              'method': _method,
              if (_referenceCtrl.text.trim().isNotEmpty)
                'reference': _referenceCtrl.text.trim(),
            });
          },
          style: FilledButton.styleFrom(backgroundColor: kCoAccent),
          child: const Text('Record'),
        ),
      ],
    );
  }

  Widget _companyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Company',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
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
                        child: Text(c.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _companyId = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _methodDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Method',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
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
              value: _method,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kCoSubtle),
              items: const ['Card', 'Bank transfer', 'Cash', 'Other']
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m,
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _method = v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _currencyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Currency',
            style: TextStyle(
                color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCoBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: _currency,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kCoSubtle),
              items: const ['USD', 'EUR', 'GBP', 'INR']
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: const TextStyle(
                                color: kCoLabel, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
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
    );
  }
}
