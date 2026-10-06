import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../pos_state.dart';
import '../cart.dart';
import '../theme/tokens.dart';

// ─── Bar Chart Painter ────────────────────────────────────────────────────────

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final Color barColor;
  final Color barColorAlt;

  const _BarChartPainter({
    required this.values,
    this.barColor = AppColors.accent_primary,
    this.barColorAlt = const Color(0xFFD1FAE5),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.reduce(math.max);
    if (maxVal <= 0) return;
    final barCount = values.length;
    final gap = size.width * 0.06;
    final barW = (size.width - gap * (barCount + 1)) / barCount;
    for (int i = 0; i < barCount; i++) {
      final x = gap + i * (barW + gap);
      final pct = values[i] / maxVal;
      final barH = pct * (size.height - 24);
      final y = size.height - 24 - barH;
      final bgPaint = Paint()..color = barColorAlt..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, barW, size.height - 24), const Radius.circular(5)), bgPaint);
      final barPaint = Paint()..color = barColor..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW, barH), const Radius.circular(5)), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── Spark Line Painter ───────────────────────────────────────────────────────

class _SparkLinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _SparkLinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxVal = values.reduce(math.max);
    if (maxVal == 0) return;
    final stepX = size.width / (values.length - 1);
    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final y = size.height - (values[i] / maxVal) * size.height;
      if (i == 0) { path.moveTo(x, y); fillPath.moveTo(x, size.height); fillPath.lineTo(x, y); }
      else { path.lineTo(x, y); fillPath.lineTo(x, y); }
    }
    fillPath.lineTo(size.width, size.height); fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.12)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─── Reports View ─────────────────────────────────────────────────────────────

class ReportsView extends StatefulWidget {
  const ReportsView({super.key, required this.state});
  final PosState state;
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> with SingleTickerProviderStateMixin {
  String _selectedPeriod = 'Today';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<SaleRecord> get _periodSales {
    final now = DateTime.now();
    return widget.state.salesLedger.where((s) {
      switch (_selectedPeriod) {
        case 'Today':
          return s.timestamp.year == now.year && s.timestamp.month == now.month && s.timestamp.day == now.day;
        case 'This Week':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return s.timestamp.isAfter(weekStart.subtract(const Duration(seconds: 1)));
        case 'This Month':
          return s.timestamp.year == now.year && s.timestamp.month == now.month;
        default:
          return true;
      }
    }).toList();
  }

  Map<String, dynamic> _aggregate(List<SaleRecord> sales) {
    final completed = sales.where((s) => s.status == SaleStatus.completed).toList();
    int totalCents = 0, vatCents = 0, mpesaCents = 0, cashCents = 0, creditCents = 0;
    final Map<String, int> productQtyMap = {};
    final Map<String, int> productRevMap = {};
    for (final s in completed) {
      final gross = s.subtotal.minorUnits + s.vatAmount.minorUnits;
      totalCents += gross; vatCents += s.vatAmount.minorUnits;
      if (s.paymentMethod == SalePaymentMethod.mpesa) mpesaCents += gross;
      else if (s.paymentMethod == SalePaymentMethod.cash) cashCents += gross;
      else if (s.paymentMethod == SalePaymentMethod.credit) creditCents += gross;
      for (final item in s.items) {
        productQtyMap[item.productName] = (productQtyMap[item.productName] ?? 0) + item.quantity;
        productRevMap[item.productName] = (productRevMap[item.productName] ?? 0) + item.lineTotal.minorUnits;
      }
    }
    return {
      'totalCents': totalCents, 'vatCents': vatCents,
      'netSalesCents': totalCents - vatCents,
      'mpesaCents': mpesaCents, 'cashCents': cashCents, 'creditCents': creditCents,
      'orderCount': completed.length,
      'reversedCount': sales.where((s) => s.status == SaleStatus.reversed).length,
      'avgBasketCents': completed.isNotEmpty ? (totalCents ~/ completed.length) : 0,
      'productQtyMap': productQtyMap,
      'topProducts': (productRevMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value))),
    };
  }

  List<double> _hourlyRevenue(List<SaleRecord> sales) {
    final hours = List<double>.filled(8, 0);
    final now = DateTime.now();
    for (final s in sales.where((s) => s.status == SaleStatus.completed)) {
      if (s.timestamp.day == now.day) {
        final bucket = (s.timestamp.hour - 8).clamp(0, 7);
        hours[bucket] += (s.subtotal.minorUnits + s.vatAmount.minorUnits) / 100;
      }
    }
    return hours;
  }

  Map<String, int> _categoryRevenue(List<SaleRecord> sales) {
    final map = <String, int>{};
    for (final s in sales.where((s) => s.status == SaleStatus.completed)) {
      for (final item in s.items) {
        final product = widget.state.products.where((p) => p.id == item.productId).firstOrNull;
        final cat = product?.category ?? 'Other';
        map[cat] = (map[cat] ?? 0) + item.lineTotal.minorUnits;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final sales = _periodSales;
    final agg = _aggregate(sales);
    final totalCents = agg['totalCents'] as int;
    final vatCents = agg['vatCents'] as int;
    final netSalesCents = agg['netSalesCents'] as int;
    final mpesaCents = agg['mpesaCents'] as int;
    final cashCents = agg['cashCents'] as int;
    final creditCents = agg['creditCents'] as int;
    final orderCount = agg['orderCount'] as int;
    final reversedCount = agg['reversedCount'] as int;
    final avgBasketCents = agg['avgBasketCents'] as int;
    final topProducts = agg['topProducts'] as List<MapEntry<String, int>>;
    final productQtyMap = agg['productQtyMap'] as Map<String, int>;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 16 : 24, isMobile ? 16 : 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Reports & Analytics', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text_primary)),
                          SizedBox(height: 4),
                          Text('Sales performance, financial reconciliation & product insights', style: TextStyle(fontSize: 13, color: AppColors.text_tertiary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _PeriodSelector(selected: _selectedPeriod, onChanged: (p) => setState(() => _selectedPeriod = p), isMobile: isMobile),
                    if (!isMobile) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => _showZReportDialog(context, totalCents, vatCents, netSalesCents, mpesaCents, cashCents, creditCents),
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('Z-Report'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent_primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 20),
                  LayoutBuilder(builder: (_, constraints) {
                    final cols = constraints.maxWidth > 720 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12, crossAxisSpacing: 12,
                      childAspectRatio: cols == 4 ? 1.7 : 1.5,
                      children: [
                        _KpiCard(title: 'Gross Revenue', cents: totalCents, subtitle: '$orderCount transactions', icon: Icons.trending_up, color: AppColors.accent_primary, sparkValues: _hourlyRevenue(sales)),
                        _KpiCard(title: 'Net Sales (ex-VAT)', cents: netSalesCents, subtitle: '16% KRA VAT', icon: Icons.account_balance_outlined, color: const Color(0xFF2563EB), sparkValues: null),
                        _KpiCard(title: 'VAT Collected', cents: vatCents, subtitle: 'Tax liability', icon: Icons.receipt_outlined, color: const Color(0xFF7C3AED), sparkValues: null),
                        _KpiCard(title: 'Avg Basket', cents: avgBasketCents, subtitle: reversedCount > 0 ? '$reversedCount reversed' : 'No reversals', icon: Icons.shopping_basket_outlined, color: const Color(0xFFD97706), sparkValues: null),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg_subtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border_subtle),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: AppColors.text_primary,
                      unselectedLabelColor: AppColors.text_tertiary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                      dividerColor: Colors.transparent,
                      tabs: const [Tab(text: 'Overview'), Tab(text: 'Products'), Tab(text: 'Cash Flow')],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        body: Padding(
          padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 16, isMobile ? 16 : 24, 0),
          child: TabBarView(
            controller: _tabController,
            children: [
              _OverviewTab(hourlyValues: _hourlyRevenue(sales), mpesaCents: mpesaCents, cashCents: cashCents, creditCents: creditCents, totalCents: totalCents, topProducts: topProducts, productQtyMap: productQtyMap, isMobile: isMobile),
              _ProductsTab(topProducts: topProducts, productQtyMap: productQtyMap, categoryRevenue: _categoryRevenue(sales), totalCents: totalCents, state: widget.state),
              _CashFlowTab(state: widget.state),
            ],
          ),
        ),
      ),
    );
  }

  void _showZReportDialog(BuildContext context, int totalCents, int vatCents, int netCents, int mpesaCents, int cashCents, int creditCents) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border_subtle)),
        title: Row(children: const [Icon(Icons.receipt_long, color: AppColors.accent_primary), SizedBox(width: 12), Text('End of Day Z-Report', style: TextStyle(color: AppColors.text_primary, fontSize: 18, fontWeight: FontWeight.bold))]),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.bg_subtle, borderRadius: BorderRadius.circular(10)),
              child: Text('${widget.state.shopName}\n${widget.state.storeBranch}\n${widget.state.tillId} · Cashier: ${widget.state.activeCashierName}\n${DateTime.now().toLocal().toString().split('.')[0]}',
                  style: const TextStyle(fontSize: 12, color: AppColors.text_secondary, height: 1.6)),
            ),
            const SizedBox(height: 16),
            _zRow('Gross Revenue', 'KES ${Money(totalCents).formatted}'),
            _zRow('16% VAT Collected', 'KES ${Money(vatCents).formatted}'),
            _zRow('Net Sales (Ex-VAT)', 'KES ${Money(netCents).formatted}'),
            const Divider(color: AppColors.border_subtle),
            _zRow('M-Pesa', 'KES ${Money(mpesaCents).formatted}'),
            _zRow('Cash', 'KES ${Money(cashCents).formatted}'),
            _zRow('Credit', 'KES ${Money(creditCents).formatted}'),
            const Divider(color: AppColors.border_subtle),
            _zRow('Expected Cash Balance', 'KES ${widget.state.expectedDrawerCash.formatted}', bold: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: AppColors.text_secondary))),
          FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Z-Report sent to thermal printer.'), backgroundColor: AppColors.accent_primary)); },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Print Z-Report'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary),
          ),
        ],
      ),
    );
  }

  Widget _zRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: bold ? AppColors.text_primary : AppColors.text_secondary, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
      Text(value, style: TextStyle(color: AppColors.text_primary, fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: 12)),
    ]),
  );
}

// ─── Period Selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onChanged, required this.isMobile});
  final String selected;
  final ValueChanged<String> onChanged;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return DropdownButton<String>(
        value: selected, underline: const SizedBox.shrink(),
        style: const TextStyle(color: AppColors.text_primary, fontWeight: FontWeight.w700, fontSize: 13),
        items: ['Today', 'This Week', 'This Month'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      );
    }
    return Container(
      decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border_subtle)),
      padding: const EdgeInsets.all(4),
      child: Row(mainAxisSize: MainAxisSize.min, children: ['Today', 'This Week', 'This Month'].map((p) {
        final sel = p == selected;
        return GestureDetector(
          onTap: () => onChanged(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: sel ? AppColors.accent_primary : Colors.transparent, borderRadius: BorderRadius.circular(7)),
            child: Text(p, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? Colors.white : AppColors.text_secondary)),
          ),
        );
      }).toList()),
    );
  }
}

// ─── Animated Money Counter ──────────────────────────────────────────────────

class _AnimatedMoneyText extends StatelessWidget {
  const _AnimatedMoneyText({
    required this.cents,
    this.prefix = 'KES ',
    this.style,
  });

  final int cents;
  final String prefix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(cents),
      tween: Tween<double>(begin: (cents * 0.7).toDouble(), end: cents.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final currentCents = value.round();
        return Text(
          '$prefix${Money(currentCents).formatted}',
          style: style,
        );
      },
    );
  }
}

// ─── KPI Card ────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.cents,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.sparkValues,
  });
  final String title, subtitle;
  final int cents;
  final IconData icon;
  final Color color;
  final List<double>? sparkValues;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border_subtle)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text_secondary), overflow: TextOverflow.ellipsis)),
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 14, color: color)),
      ]),
      const Spacer(),
      if (sparkValues != null && sparkValues!.any((v) => v > 0)) ...[
        SizedBox(height: 24, child: CustomPaint(painter: _SparkLinePainter(values: sparkValues!, color: color), size: const Size.fromHeight(24))),
        const SizedBox(height: 4),
      ],
      _AnimatedMoneyText(
        cents: cents,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text_primary, letterSpacing: -0.5),
      ),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.text_tertiary)),
    ]),
  );
}

// ─── Overview Tab ─────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.hourlyValues, required this.mpesaCents, required this.cashCents, required this.creditCents, required this.totalCents, required this.topProducts, required this.productQtyMap, required this.isMobile});
  final List<double> hourlyValues;
  final int mpesaCents, cashCents, creditCents, totalCents;
  final List<MapEntry<String, int>> topProducts;
  final Map<String, int> productQtyMap;
  final bool isMobile;
  static const _hourLabels = ['8am', '9am', '10am', '11am', '12pm', '1pm', '2pm', '3pm+'];

  @override
  Widget build(BuildContext context) => ListView(children: [
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Revenue by Hour', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
          const Text('Today', style: TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
        ]),
        const SizedBox(height: 16),
        SizedBox(height: 120, child: CustomPaint(painter: _BarChartPainter(values: hourlyValues), size: const Size.fromHeight(120))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: _hourLabels.map((l) => Text(l, style: const TextStyle(fontSize: 9, color: AppColors.text_tertiary))).toList()),
      ]),
    ),
    const SizedBox(height: 16),
    if (isMobile) ...[
      _PaymentBreakdown(mpesaCents: mpesaCents, cashCents: cashCents, creditCents: creditCents, totalCents: totalCents),
      const SizedBox(height: 12),
      _TopProducts(topProducts: topProducts, productQtyMap: productQtyMap),
    ] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 4, child: _PaymentBreakdown(mpesaCents: mpesaCents, cashCents: cashCents, creditCents: creditCents, totalCents: totalCents)),
      const SizedBox(width: 16),
      Expanded(flex: 5, child: _TopProducts(topProducts: topProducts, productQtyMap: productQtyMap)),
    ]),
    const SizedBox(height: 24),
  ]);
}

class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.mpesaCents, required this.cashCents, required this.creditCents, required this.totalCents});
  final int mpesaCents, cashCents, creditCents, totalCents;

  Widget _row(String label, IconData icon, int cents, Color color) {
    final pct = totalCents > 0 ? cents / totalCents : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: color), const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_primary)),
        const Spacer(),
        Text('${(pct * 100).round()}% · KES ${Money(cents).formatted}', style: const TextStyle(fontSize: 12, color: AppColors.text_secondary)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), minHeight: 7, backgroundColor: AppColors.bg_subtle, valueColor: AlwaysStoppedAnimation<Color>(color))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Payment Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
      const SizedBox(height: 16),
      _row('M-Pesa', Icons.phone_android, mpesaCents, const Color(0xFF16A34A)),
      const SizedBox(height: 12),
      _row('Cash', Icons.attach_money, cashCents, const Color(0xFF2563EB)),
      const SizedBox(height: 12),
      _row('Credit', Icons.people_outline, creditCents, const Color(0xFFD97706)),
    ]),
  );
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.topProducts, required this.productQtyMap});
  final List<MapEntry<String, int>> topProducts;
  final Map<String, int> productQtyMap;
  static const _colors = [AppColors.accent_primary, Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFD97706), Color(0xFF16A34A), AppColors.text_tertiary];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Top Products', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
        Text('${topProducts.length}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
      ]),
      const SizedBox(height: 14),
      if (topProducts.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No sales yet', style: TextStyle(color: AppColors.text_tertiary))))
      else
        ...topProducts.take(6).toList().asMap().entries.map((e) {
          final color = _colors[e.key % _colors.length];
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
            Container(width: 26, height: 26, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center,
              child: Text('${e.key + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_primary), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${productQtyMap[e.value.key] ?? 0} units', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
            ])),
            Text('KES ${Money(e.value.value).formatted}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          ]));
        }),
    ]),
  );
}

// ─── Products Tab ─────────────────────────────────────────────────────────────

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({required this.topProducts, required this.productQtyMap, required this.categoryRevenue, required this.totalCents, required this.state});
  final List<MapEntry<String, int>> topProducts;
  final Map<String, int> productQtyMap;
  final Map<String, int> categoryRevenue;
  final int totalCents;
  final PosState state;

  @override
  Widget build(BuildContext context) {
    final catEntries = categoryRevenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ListView(children: [
      if (catEntries.isNotEmpty) Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Revenue by Category', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
          const SizedBox(height: 16),
          SizedBox(height: 110, child: CustomPaint(painter: _BarChartPainter(values: catEntries.map((e) => e.value.toDouble()).toList(), barColor: const Color(0xFF7C3AED), barColorAlt: const Color(0xFFF5F3FF)), size: const Size.fromHeight(110))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: catEntries.map((e) => Flexible(child: Text(e.key, style: const TextStyle(fontSize: 9, color: AppColors.text_tertiary), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))).toList()),
        ]),
      ),
      const SizedBox(height: 16),

      // Full table
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Full Product Performance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: AppColors.bg_subtle, borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Expanded(flex: 4, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary))),
              Expanded(flex: 2, child: Text('Units', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary), textAlign: TextAlign.center)),
              Expanded(flex: 3, child: Text('Revenue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary), textAlign: TextAlign.right)),
              Expanded(flex: 2, child: Text('Share', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary), textAlign: TextAlign.right)),
            ]),
          ),
          const SizedBox(height: 8),
          if (topProducts.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No sales data', style: TextStyle(color: AppColors.text_tertiary))))
          else
            ...topProducts.map((e) {
              final share = totalCents > 0 ? (e.value / totalCents * 100) : 0.0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border_subtle))),
                child: Row(children: [
                  Expanded(flex: 4, child: Text(e.key, style: const TextStyle(fontSize: 13, color: AppColors.text_primary), overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text('${productQtyMap[e.key] ?? 0}', style: const TextStyle(fontSize: 13, color: AppColors.text_secondary), textAlign: TextAlign.center)),
                  Expanded(flex: 3, child: Text('KES ${Money(e.value).formatted}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent_primary), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text('${share.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary), textAlign: TextAlign.right)),
                ]),
              );
            }),
        ]),
      ),
      const SizedBox(height: 16),

      // Low stock panel
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18), const SizedBox(width: 8),
            const Text('Low Stock Alerts', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
            const Spacer(),
            Text('${state.products.where((p) => p.isLowStock || p.isOutOfStock).length} items', style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
          ]),
          const SizedBox(height: 14),
          ...state.products.where((p) => p.isLowStock || p.isOutOfStock).map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: p.isOutOfStock ? AppColors.status_danger.withValues(alpha: 0.1) : const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(6)),
                child: Text(p.isOutOfStock ? 'OUT' : 'LOW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: p.isOutOfStock ? AppColors.status_danger : const Color(0xFFD97706))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(p.name, style: const TextStyle(fontSize: 13, color: AppColors.text_primary), overflow: TextOverflow.ellipsis)),
              Text('${p.stock} units', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.isOutOfStock ? AppColors.status_danger : const Color(0xFFD97706))),
            ]),
          )),
          if (state.products.every((p) => !p.isLowStock && !p.isOutOfStock))
            const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('All products adequately stocked ✓', style: TextStyle(color: AppColors.status_success, fontWeight: FontWeight.w600)))),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

// ─── Cash Flow Tab ────────────────────────────────────────────────────────────

class _CashFlowTab extends StatelessWidget {
  const _CashFlowTab({required this.state});
  final PosState state;

  @override
  Widget build(BuildContext context) {
    final shift = state.shift;
    final movements = shift.movements;
    final totalIn = movements.where((m) => m.type.isInflow).fold<int>(0, (s, m) => s + m.amount.minorUnits);
    final totalOut = movements.where((m) => !m.type.isInflow).fold<int>(0, (s, m) => s + m.amount.minorUnits);

    return ListView(children: [
      LayoutBuilder(builder: (_, constraints) {
        final cols = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.6,
          children: [
            _FlowCard(title: 'Opening Float', cents: shift.openingFloat.minorUnits, color: AppColors.text_secondary, icon: Icons.account_balance_wallet_outlined),
            _FlowCard(title: 'Cash Inflows', cents: totalIn, prefix: '+ KES ', color: AppColors.status_success, icon: Icons.south),
            _FlowCard(title: 'Cash Outflows', cents: totalOut, prefix: '- KES ', color: AppColors.status_danger, icon: Icons.north),
            _FlowCard(title: 'Expected Balance', cents: shift.expectedCash.minorUnits, color: AppColors.accent_primary, icon: Icons.account_balance, highlight: true),
          ],
        );
      }),
      const SizedBox(height: 16),
      Container(
        decoration: BoxDecoration(color: AppColors.bg_surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border_subtle)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              const Text('Cash Drawer Journal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accent_light, borderRadius: BorderRadius.circular(6)),
                child: Text('${movements.length} entries', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent_primary)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border_subtle, height: 1),
          ListView.separated(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: movements.length,
            separatorBuilder: (_, __) => const Divider(color: AppColors.border_subtle, height: 1),
            itemBuilder: (_, i) {
              final m = movements[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: m.type.isInflow ? AppColors.status_success.withValues(alpha: 0.1) : AppColors.status_danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(m.type.isInflow ? Icons.south : Icons.north, size: 16, color: m.type.isInflow ? AppColors.status_success : AppColors.status_danger),
                ),
                title: Text(m.type.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text('${m.reason} · ${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')} · ${m.cashier}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                trailing: Text('${m.type.isInflow ? '+' : '-'} KES ${m.amount.formatted}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: m.type.isInflow ? AppColors.status_success : AppColors.status_danger)),
              );
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.title,
    required this.cents,
    required this.color,
    required this.icon,
    this.prefix = 'KES ',
    this.highlight = false,
  });
  final String title;
  final int cents;
  final Color color;
  final IconData icon;
  final String prefix;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: highlight ? AppColors.accent_primary.withValues(alpha: 0.06) : AppColors.bg_surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: highlight ? AppColors.accent_primary : AppColors.border_subtle, width: highlight ? 1.5 : 1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6), Flexible(child: Text(title, style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary), overflow: TextOverflow.ellipsis))]),
      const Spacer(),
      _AnimatedMoneyText(
        cents: cents,
        prefix: prefix,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.3),
      ),
    ]),
  );
}
