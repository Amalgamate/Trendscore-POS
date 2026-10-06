import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pos_state.dart';
import '../cart.dart';
import '../theme/tokens.dart';

/// Purchase order / goods receiving view.
class PurchaseOrdersView extends StatefulWidget {
  const PurchaseOrdersView({super.key, required this.state});
  final PosState state;
  @override
  State<PurchaseOrdersView> createState() => _PurchaseOrdersViewState();
}

class _PurchaseOrdersViewState extends State<PurchaseOrdersView> {
  final List<_PurchaseOrder> _orders = [];
  final _search = TextEditingController();

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  void _showReceiveStockModal() {
    final supplierCtrl = TextEditingController();
    final List<_OrderLine> lines = [];

    // Pre-populate with low stock items
    for (final p in widget.state.products.where((p) => p.isLowStock || p.isOutOfStock)) {
      lines.add(_OrderLine(product: p, qtyCtrl: TextEditingController(text: '10'), costCtrl: TextEditingController(text: p.costPrice != null ? '${p.costPrice!.minorUnits ~/ 100}' : '')));
    }
    if (lines.isEmpty) {
      for (final p in widget.state.products.take(3)) {
        lines.add(_OrderLine(product: p, qtyCtrl: TextEditingController(text: '10'), costCtrl: TextEditingController(text: p.costPrice != null ? '${p.costPrice!.minorUnits ~/ 100}' : '')));
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(ctx).height * 0.85,
            child: Column(children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.bg_subtle,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
                ),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined, color: AppColors.accent_primary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Receive Stock / Purchase Order', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
                    Text('Record goods received and update shelf stock', style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                  ])),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ]),
              ),
              // Supplier
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: TextField(
                  controller: supplierCtrl,
                  decoration: InputDecoration(
                    labelText: 'Supplier / Vendor Name (optional)',
                    prefixIcon: const Icon(Icons.business_outlined, size: 18, color: AppColors.text_tertiary),
                    filled: true, fillColor: AppColors.bg_subtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Column headers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.bg_subtle, borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Expanded(flex: 4, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary))),
                    SizedBox(width: 8),
                    Expanded(flex: 2, child: Text('Qty Received', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary))),
                    SizedBox(width: 8),
                    Expanded(flex: 2, child: Text('Cost/Unit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text_tertiary))),
                    SizedBox(width: 8),
                    SizedBox(width: 32),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              // Lines
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final line = lines[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border_subtle),
                          borderRadius: BorderRadius.circular(10),
                          color: line.product.isOutOfStock ? AppColors.status_danger.withValues(alpha: 0.04) : Colors.white,
                        ),
                        child: Row(children: [
                          Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(line.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text_primary), overflow: TextOverflow.ellipsis),
                            Text('Stock: ${line.product.stock} units', style: TextStyle(fontSize: 11, color: line.product.isOutOfStock ? AppColors.status_danger : AppColors.text_tertiary)),
                          ])),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextField(
                            controller: line.qtyCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            decoration: InputDecoration(hintText: '0', contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), filled: true, fillColor: AppColors.bg_subtle, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border_subtle))),
                          )),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: TextField(
                            controller: line.costCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(hintText: '0', prefixText: 'KES ', contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), filled: true, fillColor: AppColors.bg_subtle, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border_subtle))),
                          )),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.status_danger),
                            onPressed: () => setModal(() => lines.removeAt(i)),
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              // Add product row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: DropdownButtonFormField<PosProduct>(
                  decoration: InputDecoration(
                    hintText: 'Add another product to this order...',
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.accent_primary),
                    filled: true, fillColor: AppColors.bg_subtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  value: null,
                  items: widget.state.products
                      .where((p) => !lines.any((l) => l.product.id == p.id))
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (p) {
                    if (p != null) setModal(() => lines.add(_OrderLine(product: p, qtyCtrl: TextEditingController(text: '10'), costCtrl: TextEditingController(text: p.costPrice != null ? '${p.costPrice!.minorUnits ~/ 100}' : ''))));
                  },
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border_subtle))),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.text_secondary))),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Receive & Update Stock'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      final received = <String, int>{};
                      for (final line in lines) {
                        final qty = int.tryParse(line.qtyCtrl.text) ?? 0;
                        if (qty > 0) {
                          received[line.product.id] = qty;
                          // cost parsed in map below
                          widget.state.adjustStock(line.product.id, qty, 'Purchase Order: ${supplierCtrl.text.trim().isNotEmpty ? supplierCtrl.text.trim() : 'Supplier'}');
                        }
                      }
                      if (received.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter quantities for at least one product.'))); return; }
                      setState(() {
                        _orders.insert(0, _PurchaseOrder(
                          id: 'PO-${DateTime.now().millisecondsSinceEpoch}',
                          supplier: supplierCtrl.text.trim().isNotEmpty ? supplierCtrl.text.trim() : 'Unknown Supplier',
                          timestamp: DateTime.now(),
                          lines: lines.where((l) => (int.tryParse(l.qtyCtrl.text) ?? 0) > 0).map((l) => _POLine(
                            productName: l.product.name,
                            qty: int.tryParse(l.qtyCtrl.text) ?? 0,
                            costPerUnit: int.tryParse(l.costCtrl.text) ?? 0,
                          )).toList(),
                          receivedBy: widget.state.activeCashierName,
                        ));
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stock received from ${supplierCtrl.text.trim().isNotEmpty ? supplierCtrl.text.trim() : 'supplier'}. Shelf stock updated.'), backgroundColor: AppColors.status_success));
                    },
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final lowStockProducts = widget.state.products.where((p) => p.isLowStock || p.isOutOfStock).toList();

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('Purchase Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text_primary)),
                    SizedBox(height: 4),
                    Text('Receive stock from suppliers and update shelf inventory', style: TextStyle(fontSize: 13, color: AppColors.text_tertiary)),
                  ])),
                  FilledButton.icon(
                    onPressed: _showReceiveStockModal,
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Receive Stock'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ]),
                const SizedBox(height: 20),

                // Reorder alerts
                if (lowStockProducts.isNotEmpty) Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                      const SizedBox(width: 8),
                      Text('${lowStockProducts.length} product(s) need reordering', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: lowStockProducts.map((p) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.isOutOfStock ? AppColors.status_danger.withValues(alpha: 0.1) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: p.isOutOfStock ? AppColors.status_danger.withValues(alpha: 0.3) : const Color(0xFFFED7AA)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(p.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.isOutOfStock ? AppColors.status_danger : const Color(0xFF92400E)), overflow: TextOverflow.ellipsis),
                        const SizedBox(width: 6),
                        Text('(${p.stock})', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                      ]),
                    )).toList()),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.local_shipping_outlined, size: 16, color: Color(0xFFD97706)),
                        label: const Text('Create Reorder for Low Stock Items', style: TextStyle(color: Color(0xFFD97706))),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFFED7AA)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: _showReceiveStockModal,
                      ),
                    ),
                  ]),
                ),

                if (lowStockProducts.isNotEmpty) const SizedBox(height: 20),
              ]),
            ),
          ),

          // Order history
          if (_orders.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.local_shipping_outlined, size: 64, color: AppColors.border_subtle),
                  const SizedBox(height: 16),
                  const Text('No purchase orders yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
                  const SizedBox(height: 8),
                  const Text('Tap "Receive Stock" to record goods received from a supplier.', style: TextStyle(color: AppColors.text_tertiary), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _showReceiveStockModal,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Receive First Order'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final order = _orders[i];
                    final totalValue = order.lines.fold<int>(0, (s, l) => s + l.qty * l.costPerUnit);
                    final totalQty = order.lines.fold<int>(0, (s, l) => s + l.qty);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border_subtle)),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.accent_light, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.local_shipping_outlined, color: AppColors.accent_primary, size: 20),
                        ),
                        title: Text(order.supplier, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text_primary)),
                        subtitle: Text('${_fmt(order.timestamp)} · ${order.lines.length} items · $totalQty units · By ${order.receivedBy}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (totalValue > 0) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: AppColors.accent_light, borderRadius: BorderRadius.circular(8)),
                            child: Text('KES ${Money(totalValue * 100).formatted}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.accent_primary)),
                          ),
                          const Icon(Icons.expand_more, color: AppColors.text_tertiary),
                        ]),
                        children: order.lines.map((line) => Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                          child: Row(children: [
                            const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.text_tertiary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(line.productName, style: const TextStyle(fontSize: 13, color: AppColors.text_primary))),
                            Text('+${line.qty} units', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.status_success, fontSize: 13)),
                            if (line.costPerUnit > 0) ...[
                              const SizedBox(width: 10),
                              Text('@ KES ${line.costPerUnit}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                            ],
                          ]),
                        )).toList(),
                      ),
                    );
                  },
                  childCount: _orders.length,
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _PurchaseOrder {
  const _PurchaseOrder({required this.id, required this.supplier, required this.timestamp, required this.lines, required this.receivedBy});
  final String id, supplier, receivedBy;
  final DateTime timestamp;
  final List<_POLine> lines;
}

class _POLine {
  const _POLine({required this.productName, required this.qty, required this.costPerUnit});
  final String productName;
  final int qty, costPerUnit;
}

class _OrderLine {
  const _OrderLine({required this.product, required this.qtyCtrl, required this.costCtrl});
  final PosProduct product;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
}
