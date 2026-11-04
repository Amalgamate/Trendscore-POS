import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cart.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../services/day_end_slip.dart';
import '../services/xlsx_exporter.dart';
import '../theme/tokens.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key, required this.state});

  final PosState state;

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView>
    with SingleTickerProviderStateMixin {
  static const _periods = ['Today', 'This Week', 'This Month'];
  static const _reportNames = ['Overview', 'Products', 'Cash Flow'];

  String _selectedPeriod = 'Today';
  DateTime _selectedBusinessDate = DateTime.now();
  late final TabController _tabController;
  bool _exporting = false;
  bool _loadingSummary = false;
  Map<String, dynamic>? _serverSummary;

  String get _businessDate =>
      '${_selectedBusinessDate.year.toString().padLeft(4, '0')}-${_selectedBusinessDate.month.toString().padLeft(2, '0')}-${_selectedBusinessDate.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _reportNames.length, vsync: this);
    _loadDailySummary();
  }

  Future<void> _loadDailySummary() async {
    if (!ApiService.instance.hasToken) return;
    setState(() => _loadingSummary = true);
    final summary = await ApiService.instance.getSalesSummary(
      date: _businessDate,
    );
    if (!mounted) return;
    setState(() {
      _serverSummary = summary?['today'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(summary!['today'] as Map)
          : null;
      _loadingSummary = false;
    });
  }

  void _changeBusinessDate(int days) {
    setState(() {
      _selectedBusinessDate = _selectedBusinessDate.add(Duration(days: days));
      _selectedPeriod = 'Today';
      _serverSummary = null;
    });
    _loadDailySummary();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<SaleRecord> get _periodSales {
    final now = DateTime.now();
    final start = switch (_selectedPeriod) {
      'Today' => DateTime(now.year, now.month, now.day),
      'This Week' => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
      'This Month' => DateTime(now.year, now.month),
      _ => DateTime(2000),
    };
    return widget.state.salesLedger
        .where((sale) => !sale.timestamp.isBefore(start))
        .toList();
  }

  _ReportData _buildReportData(
    List<SaleRecord> sales, {
    Map<String, dynamic>? serverSummary,
  }) {
    final completed = sales
        .where((sale) => sale.status == SaleStatus.completed)
        .toList();
    var grossCents = 0;
    var vatCents = 0;
    var mpesaCents = 0;
    var cashCents = 0;
    var creditCents = 0;
    final products = <String, _ProductMetric>{};
    final categories = <String, int>{};
    for (final sale in completed) {
      final gross = sale.subtotal.minorUnits + sale.vatAmount.minorUnits;
      grossCents += gross;
      vatCents += sale.vatAmount.minorUnits;
      switch (sale.paymentMethod) {
        case SalePaymentMethod.mpesa:
          mpesaCents += gross;
        case SalePaymentMethod.cash:
          cashCents += gross;
        case SalePaymentMethod.credit:
          creditCents += gross;
      }
      for (final item in sale.items) {
        final metric = products.putIfAbsent(
          item.productName,
          _ProductMetric.new,
        );
        metric.quantity += item.quantity;
        metric.revenueCents += item.lineTotal.minorUnits;
        final category =
            widget.state.products
                .where((product) => product.id == item.productId)
                .firstOrNull
                ?.category ??
            'Other';
        categories[category] =
            (categories[category] ?? 0) + item.lineTotal.minorUnits;
      }
    }
    final rankedProducts = products.entries.toList()
      ..sort(
        (left, right) =>
            right.value.revenueCents.compareTo(left.value.revenueCents),
      );
    final rankedCategories = categories.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final byMethod = serverSummary?['byMethod'] as Map<String, dynamic>?;
    if (byMethod != null) {
      cashCents = ((byMethod['CASH'] as num? ?? 0) * 100).round();
      mpesaCents = ((byMethod['MPESA'] as num? ?? 0) * 100).round();
      creditCents = ((byMethod['CREDIT'] as num? ?? 0) * 100).round();
    }
    final serverTotal = serverSummary?['total'];
    if (serverTotal is num) grossCents = (serverTotal * 100).round();
    final serverRefund = serverSummary?['refunds'] as Map<String, dynamic>?;
    if (serverRefund?['total'] is num) {
      vatCents = (((serverSummary?['vatTotal'] as num?) ?? 0) * 100).round();
    }
    return _ReportData(
      sales: sales,
      completedSales: completed,
      grossCents: grossCents,
      vatCents: vatCents,
      mpesaCents: mpesaCents,
      cashCents: cashCents,
      creditCents: creditCents,
      reversedCount:
          (serverSummary?['voidedCount'] as num?)?.toInt() ??
          sales.where((sale) => sale.status == SaleStatus.reversed).length,
      refundsCents: (((serverRefund?['total'] as num?) ?? 0) * 100).round(),
      averageCents:
          (((serverSummary?['average'] as num?) ??
                      (completed.isEmpty
                          ? 0
                          : grossCents / 100 / completed.length)) *
                  100)
              .round(),
      transactionCount:
          (serverSummary?['count'] as num?)?.toInt() ?? completed.length,
      creditGivenCents: (((serverSummary?['creditGiven'] as num?) ?? 0) * 100)
          .round(),
      debtPayments: Map<String, dynamic>.from(
        serverSummary?['debtPayments'] as Map? ?? const {},
      ),
      products: rankedProducts,
      categories: rankedCategories,
    );
  }

  Future<void> _exportExcel(_ReportData report) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = encodeXlsx(_buildWorkbook(report));
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save ShopSmart reports',
        fileName: 'shopsmart_reports_$date.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reports exported to Excel.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export reports: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<XlsxSheet> _buildWorkbook(_ReportData report) => [
    XlsxSheet('Summary', [
      ['Report period', _selectedPeriod],
      ['Generated', DateTime.now().toLocal().toIso8601String()],
      ['Completed sales', report.completedSales.length],
      ['Gross sales (KES)', report.grossCents / 100],
      ['Net sales (KES)', (report.grossCents - report.vatCents) / 100],
      ['VAT collected (KES)', report.vatCents / 100],
      [
        'Average sale (KES)',
        report.completedSales.isEmpty
            ? 0
            : report.grossCents / report.completedSales.length / 100,
      ],
      ['Reversed sales', report.reversedCount],
      ['M-Pesa (KES)', report.mpesaCents / 100],
      ['Cash (KES)', report.cashCents / 100],
      ['Credit (KES)', report.creditCents / 100],
    ]),
    XlsxSheet('Products', [
      ['Product', 'Units sold', 'Revenue (KES)', 'Share (%)'],
      for (final entry in report.products)
        [
          entry.key,
          entry.value.quantity,
          entry.value.revenueCents / 100,
          report.grossCents == 0
              ? 0
              : entry.value.revenueCents / report.grossCents * 100,
        ],
    ]),
    XlsxSheet('Categories', [
      ['Category', 'Revenue (KES)'],
      for (final entry in report.categories) [entry.key, entry.value / 100],
    ]),
    XlsxSheet('Sales', [
      [
        'Receipt',
        'Date and time',
        'Payment method',
        'Cashier',
        'Customer',
        'Items',
        'Gross (KES)',
        'Status',
      ],
      for (final sale in report.sales)
        [
          sale.receiptNumber,
          sale.timestamp.toLocal().toIso8601String(),
          sale.paymentMethod.label,
          sale.cashier,
          sale.customer?.name ?? '',
          sale.items.fold<num>(0, (sum, item) => sum + item.quantity),
          (sale.subtotal.minorUnits + sale.vatAmount.minorUnits) / 100,
          sale.status.name,
        ],
    ]),
    XlsxSheet('Cash Flow', [
      ['Type', 'Reason', 'Date and time', 'Cashier', 'Amount (KES)'],
      for (final movement in widget.state.shift.movements)
        [
          movement.type.label,
          movement.reason,
          movement.timestamp.toLocal().toIso8601String(),
          movement.cashier,
          (movement.type.isInflow ? 1 : -1) * movement.amount.minorUnits / 100,
        ],
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final report = _buildReportData(
      _periodSales,
      serverSummary: _selectedPeriod == 'Today' ? _serverSummary : null,
    );
    final grossCents = report.grossCents;
    final salesCount = report.transactionCount;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final lowStockProducts = widget.state.products
        .where((product) => product.isLowStock || product.isOutOfStock)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 12 : 24,
              isMobile ? 12 : 20,
              isMobile ? 12 : 24,
              0,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PeriodSelector(
                        selected: _selectedPeriod,
                        periods: _periods,
                        isMobile: isMobile,
                        onChanged: (period) {
                          setState(() => _selectedPeriod = period);
                          if (period == 'Today') _loadDailySummary();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isMobile)
                      IconButton(
                        tooltip: 'Export to Excel',
                        onPressed: _exporting
                            ? null
                            : () => _exportExcel(report),
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _exporting
                            ? null
                            : () => _exportExcel(report),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(
                          _exporting ? 'Exporting...' : 'Export Excel',
                        ),
                      ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _showZReportDialog(report),
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: const Text('Z-Report'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (_selectedPeriod == 'Today')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous business day',
                        onPressed: () => _changeBusinessDate(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        _businessDate,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        tooltip: 'Next business day',
                        onPressed: () => _changeBusinessDate(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: isMobile ? 1.9 : 2.4,
                      children: [
                        _MetricCard(
                          title: 'Gross sales',
                          value: _kes(grossCents),
                          detail: _loadingSummary
                              ? 'Loading server total…'
                              : '$salesCount sales',
                        ),
                        _MetricCard(
                          title: 'Net sales',
                          value: _kes(report.grossCents - report.refundsCents),
                          detail:
                              '${report.refundsCents == 0 ? 'No' : _kes(report.refundsCents)} refunded',
                        ),
                        _MetricCard(
                          title: 'VAT collected',
                          value: _kes(report.vatCents),
                          detail: 'Tax total',
                        ),
                        _MetricCard(
                          title: 'Average sale',
                          value: _kes(report.averageCents),
                          detail: '${report.reversedCount} voided',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                if (_selectedPeriod == 'Today' && _serverSummary != null)
                  _DailySummaryDetails(summary: report, date: _businessDate),
                if (_selectedPeriod == 'Today' && _loadingSummary)
                  const LinearProgressIndicator(),
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.accent_primary,
                  unselectedLabelColor: AppColors.text_tertiary,
                  indicatorColor: AppColors.accent_primary,
                  dividerColor: AppColors.border_subtle,
                  tabs: _reportNames.map((name) => Tab(text: name)).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _OverviewReport(report: report, isMobile: isMobile),
                _ProductsReport(
                  report: report,
                  lowStockProducts: lowStockProducts,
                  isMobile: isMobile,
                ),
                _CashFlowReport(state: widget.state, isMobile: isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _kes(int cents) => 'KES ${Money(cents).formatted}';

  void _showZReportDialog(_ReportData report) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End of day report'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.state.shopName),
              Text(widget.state.storeBranch),
              Text(
                '${widget.state.tillId} · ${widget.state.activeCashierName}',
              ),
              const Divider(),
              _SummaryLine(
                label: 'Gross sales',
                value: _kes(report.grossCents),
              ),
              _SummaryLine(
                label: 'VAT collected',
                value: _kes(report.vatCents),
              ),
              _SummaryLine(
                label: 'Net sales',
                value: _kes(report.grossCents - report.refundsCents),
              ),
              _SummaryLine(label: 'Refunds', value: _kes(report.refundsCents)),
              _SummaryLine(label: 'M-Pesa', value: _kes(report.mpesaCents)),
              _SummaryLine(label: 'Cash', value: _kes(report.cashCents)),
              _SummaryLine(label: 'Credit', value: _kes(report.creditCents)),
              _SummaryLine(
                label: 'Credit given',
                value: _kes(report.creditGivenCents),
              ),
              for (final entry in report.debtPayments.entries)
                _SummaryLine(
                  label: 'Debt receipt · ${entry.key}',
                  value: _kes(
                    (((entry.value as Map)['amount'] as num? ?? 0) * 100)
                        .round(),
                  ),
                ),
              _SummaryLine(
                label: 'Expected drawer',
                value: widget.state.expectedDrawerCash.toString(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final rows = <({String label, String value})>[
                (label: 'Gross sales', value: _kes(report.grossCents)),
                (label: 'VAT collected', value: _kes(report.vatCents)),
                (
                  label: 'Net sales',
                  value: _kes(report.grossCents - report.refundsCents),
                ),
                (label: 'Refunds', value: _kes(report.refundsCents)),
                (label: 'M-Pesa', value: _kes(report.mpesaCents)),
                (label: 'Cash', value: _kes(report.cashCents)),
                (label: 'Credit', value: _kes(report.creditCents)),
                (label: 'Credit given', value: _kes(report.creditGivenCents)),
                (
                  label: 'Expected drawer',
                  value: widget.state.expectedDrawerCash.toString(),
                ),
              ];
              for (final entry in report.debtPayments.entries) {
                final payment = Map<String, dynamic>.from(entry.value as Map);
                rows.add((
                  label: 'Debt receipt · ${entry.key}',
                  value: _kes(
                    (((payment['amount'] as num?) ?? 0) * 100).round(),
                  ),
                ));
              }
              final slip = buildDayEndSlipHtml(
                shopName: widget.state.shopName,
                branch: widget.state.storeBranch,
                date: _businessDate,
                till: widget.state.tillId,
                cashier: widget.state.activeCashierName,
                rows: rows,
              );
              Navigator.pop(dialogContext);
              final opened = await printDayEndSlip(slip);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    opened
                        ? 'Day-end report opened in the print dialog.'
                        : 'Printing is available in the web POS; this device has no print service.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print'),
          ),
        ],
      ),
    );
  }
}

class _ReportData {
  const _ReportData({
    required this.sales,
    required this.completedSales,
    required this.grossCents,
    required this.vatCents,
    required this.mpesaCents,
    required this.cashCents,
    required this.creditCents,
    required this.reversedCount,
    required this.refundsCents,
    required this.averageCents,
    required this.transactionCount,
    required this.creditGivenCents,
    required this.debtPayments,
    required this.products,
    required this.categories,
  });

  final List<SaleRecord> sales;
  final List<SaleRecord> completedSales;
  final int grossCents;
  final int vatCents;
  final int mpesaCents;
  final int cashCents;
  final int creditCents;
  final int reversedCount;
  final int refundsCents;
  final int averageCents;
  final int transactionCount;
  final int creditGivenCents;
  final Map<String, dynamic> debtPayments;
  final List<MapEntry<String, _ProductMetric>> products;
  final List<MapEntry<String, int>> categories;
}

class _DailySummaryDetails extends StatelessWidget {
  const _DailySummaryDetails({required this.summary, required this.date});

  final _ReportData summary;
  final String date;

  @override
  Widget build(BuildContext context) {
    String money(int cents) => 'KES ${Money(cents).formatted}';
    final methods = <String, int>{
      'Cash': summary.cashCents,
      'M-Pesa': summary.mpesaCents,
      'Credit': summary.creditCents,
    };
    final debt = summary.debtPayments.entries
        .map((entry) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          return '${entry.key}: ${money(((data['amount'] as num? ?? 0) * 100).round())} (${data['count'] ?? 0})';
        })
        .join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            Text('Business day $date'),
            for (final entry in methods.entries)
              Text('${entry.key}: ${money(entry.value)}'),
            Text('Credit given: ${money(summary.creditGivenCents)}'),
            Text('Debt receipts: ${debt.isEmpty ? 'None' : debt}'),
          ],
        ),
      ),
    );
  }
}

class _ProductMetric {
  num quantity = 0;
  int revenueCents = 0;
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.periods,
    required this.isMobile,
    required this.onChanged,
  });

  final String selected;
  final List<String> periods;
  final bool isMobile;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: const InputDecoration(
          labelText: 'Period',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: periods
            .map(
              (period) => DropdownMenuItem(value: period, child: Text(period)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      );
    }
    return SegmentedButton<String>(
      segments: periods
          .map(
            (period) =>
                ButtonSegment<String>(value: period, label: Text(period)),
          )
          .toList(),
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.bg_surface,
      border: Border.all(color: AppColors.border_subtle),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.text_secondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.text_primary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.text_tertiary, fontSize: 11),
        ),
      ],
    ),
  );
}

class _OverviewReport extends StatelessWidget {
  const _OverviewReport({required this.report, required this.isMobile});

  final _ReportData report;
  final bool isMobile;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.all(isMobile ? 12 : 24),
    children: [
      _ReportSection(
        title: 'Payment totals',
        child: Column(
          children: [
            _SummaryLine(label: 'M-Pesa', value: _money(report.mpesaCents)),
            _SummaryLine(label: 'Cash', value: _money(report.cashCents)),
            _SummaryLine(label: 'Credit', value: _money(report.creditCents)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _ReportSection(
        title: 'Top products',
        child: _ProductList(
          products: report.products.take(6).toList(),
          isMobile: isMobile,
          emptyText: 'No sales in this period.',
        ),
      ),
      const SizedBox(height: 12),
      _ReportSection(
        title: 'Recent sales',
        child: _SalesList(
          sales: report.sales.take(10).toList(),
          isMobile: isMobile,
        ),
      ),
    ],
  );
}

class _ProductsReport extends StatelessWidget {
  const _ProductsReport({
    required this.report,
    required this.lowStockProducts,
    required this.isMobile,
  });

  final _ReportData report;
  final List<PosProduct> lowStockProducts;
  final bool isMobile;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.all(isMobile ? 12 : 24),
    children: [
      _ReportSection(
        title: 'Product performance',
        child: _ProductList(
          products: report.products,
          isMobile: isMobile,
          includeShare: true,
          totalCents: report.grossCents,
          emptyText: 'No product sales in this period.',
        ),
      ),
      const SizedBox(height: 12),
      _ReportSection(
        title: 'Category sales',
        child: _CategoryList(categories: report.categories, isMobile: isMobile),
      ),
      const SizedBox(height: 12),
      _ReportSection(
        title: 'Low stock',
        child: lowStockProducts.isEmpty
            ? const _EmptyReport(text: 'All products are adequately stocked.')
            : Column(
                children: lowStockProducts
                    .map(
                      (product) => _SummaryLine(
                        label: product.name,
                        value: product.isOutOfStock
                            ? 'Out of stock'
                            : '${product.stock} units',
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );
}

class _CashFlowReport extends StatelessWidget {
  const _CashFlowReport({required this.state, required this.isMobile});

  final PosState state;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final shift = state.shift;
    final movements = shift.movements;
    final totalIn = movements
        .where((movement) => movement.type.isInflow)
        .fold<int>(0, (sum, movement) => sum + movement.amount.minorUnits);
    final totalOut = movements
        .where((movement) => !movement.type.isInflow)
        .fold<int>(0, (sum, movement) => sum + movement.amount.minorUnits);

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      children: [
        _ReportSection(
          title: 'Cash position',
          child: Column(
            children: [
              _SummaryLine(
                label: 'Opening float',
                value: shift.openingFloat.toString(),
              ),
              _SummaryLine(label: 'Cash inflows', value: _money(totalIn)),
              _SummaryLine(label: 'Cash outflows', value: _money(totalOut)),
              _SummaryLine(
                label: 'Expected balance',
                value: shift.expectedCash.toString(),
                emphasized: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReportSection(
          title: 'Cash drawer journal',
          child: movements.isEmpty
              ? const _EmptyReport(text: 'No cash movements recorded.')
              : Column(
                  children: movements
                      .map((movement) => _MovementListItem(movement: movement))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.bg_surface,
      border: Border.all(color: AppColors.border_subtle),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.text_primary,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: emphasized
                  ? AppColors.text_primary
                  : AppColors.text_secondary,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColors.text_primary,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.products,
    required this.isMobile,
    required this.emptyText,
    this.includeShare = false,
    this.totalCents = 0,
  });

  final List<MapEntry<String, _ProductMetric>> products;
  final bool isMobile;
  final bool includeShare;
  final int totalCents;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return _EmptyReport(text: emptyText);
    if (isMobile) {
      return Column(
        children: products.map((entry) {
          final share = totalCents == 0
              ? 0
              : entry.value.revenueCents / totalCents * 100;
          return _SummaryLine(
            label: '${entry.key} · ${entry.value.quantity} units',
            value:
                '${_money(entry.value.revenueCents)}'
                '${includeShare ? ' · ${share.toStringAsFixed(1)}%' : ''}',
          );
        }).toList(),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('Product')),
          const DataColumn(label: Text('Units'), numeric: true),
          const DataColumn(label: Text('Revenue'), numeric: true),
          if (includeShare)
            const DataColumn(label: Text('Share'), numeric: true),
        ],
        rows: products.map((entry) {
          final share = totalCents == 0
              ? 0
              : entry.value.revenueCents / totalCents * 100;
          return DataRow(
            cells: [
              DataCell(Text(entry.key)),
              DataCell(Text('${entry.value.quantity}')),
              DataCell(Text(_money(entry.value.revenueCents))),
              if (includeShare) DataCell(Text('${share.toStringAsFixed(1)}%')),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categories, required this.isMobile});

  final List<MapEntry<String, int>> categories;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const _EmptyReport(text: 'No category sales in this period.');
    }
    if (isMobile) {
      return Column(
        children: categories
            .map(
              (entry) =>
                  _SummaryLine(label: entry.key, value: _money(entry.value)),
            )
            .toList(),
      );
    }
    return DataTable(
      columns: const [
        DataColumn(label: Text('Category')),
        DataColumn(label: Text('Revenue'), numeric: true),
      ],
      rows: categories
          .map(
            (entry) => DataRow(
              cells: [
                DataCell(Text(entry.key)),
                DataCell(Text(_money(entry.value))),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _SalesList extends StatelessWidget {
  const _SalesList({required this.sales, required this.isMobile});

  final List<SaleRecord> sales;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const _EmptyReport(text: 'No sales in this period.');
    }
    return Column(
      children: sales.map((sale) {
        final amount = sale.subtotal.minorUnits + sale.vatAmount.minorUnits;
        final subtitle =
            '${sale.paymentMethod.label} · ${sale.timestamp.toLocal().toString().substring(0, 16)}';
        if (isMobile) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(sale.receiptNumber),
            subtitle: Text(subtitle),
            trailing: Text(_money(amount)),
          );
        }
        return _SummaryLine(
          label: '${sale.receiptNumber} · $subtitle',
          value: _money(amount),
        );
      }).toList(),
    );
  }
}

class _MovementListItem extends StatelessWidget {
  const _MovementListItem({required this.movement});

  final CashMovement movement;

  @override
  Widget build(BuildContext context) {
    final prefix = movement.type.isInflow ? '+' : '-';
    final timestamp = movement.timestamp.toLocal().toString().substring(0, 16);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(movement.type.label),
      subtitle: Text('${movement.reason} · $timestamp · ${movement.cashier}'),
      trailing: Text('$prefix ${_money(movement.amount.minorUnits)}'),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: const TextStyle(color: AppColors.text_tertiary)),
  );
}

String _money(int cents) => 'KES ${Money(cents).formatted}';
