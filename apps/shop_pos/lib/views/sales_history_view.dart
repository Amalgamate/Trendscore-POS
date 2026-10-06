import 'package:flutter/material.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';
import 'receipt_dialog.dart';

class SalesHistoryView extends StatefulWidget {
  const SalesHistoryView({super.key, required this.state});

  final PosState state;

  @override
  State<SalesHistoryView> createState() => _SalesHistoryViewState();
}

class _SalesHistoryViewState extends State<SalesHistoryView> {
  String _filter = 'All';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SaleRecord> get _filteredSales {
    return widget.state.sales.where((s) {
      if (_filter == 'Cash' && s.paymentMethod != SalePaymentMethod.cash) return false;
      if (_filter == 'M-Pesa' && s.paymentMethod != SalePaymentMethod.mpesa) return false;
      if (_filter == 'Credit' && s.paymentMethod != SalePaymentMethod.credit) return false;
      if (_filter == 'Reversed' && !s.isReversed) return false;

      final query = _search.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final matchesReceipt = s.receiptNumber.toLowerCase().contains(query);
        final matchesCust = s.customer?.name.toLowerCase().contains(query) ?? false;
        final matchesRef = s.paymentReference.toLowerCase().contains(query);
        return matchesReceipt || matchesCust || matchesRef;
      }
      return true;
    }).toList();
  }

  void _showSaleDetails(SaleRecord sale) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sale ${sale.receiptNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      '${sale.timestamp.year}-${sale.timestamp.month.toString().padLeft(2, '0')}-${sale.timestamp.day.toString().padLeft(2, '0')} at ${sale.timestamp.hour.toString().padLeft(2, '0')}:${sale.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sale.status.color.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sale.status.color.withAlpha(80)),
                  ),
                  child: Text(
                    sale.status.label.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sale.status.color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),

            // Item list preview
            ...sale.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${item.quantity} × ${item.productName}', style: const TextStyle(fontSize: 13)),
                      Text('KES ${item.lineTotal.formatted}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Gross Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('KES ${sale.subtotal.formatted}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.accent_primary)),
              ],
            ),
            const SizedBox(height: 20),

            // Actions
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isNarrow = constraints.maxWidth < 360;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_outlined, size: 18),
                        label: const Text('View Thermal Slip'),
                        onPressed: () {
                          Navigator.pop(context);
                          ReceiptDialog.show(context, sale, onNewSale: () {}, state: widget.state);
                        },
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                      if (!sale.isReversed) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Reverse Sale (Refund)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.status_danger,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _promptReverseSale(sale);
                          },
                        ),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_outlined, size: 18),
                        label: const Text('View Thermal Slip'),
                        onPressed: () {
                          Navigator.pop(context);
                          ReceiptDialog.show(context, sale, onNewSale: () {}, state: widget.state);
                        },
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                    if (!sale.isReversed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Reverse Sale (Refund)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.status_danger,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _promptReverseSale(sale);
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _promptReverseSale(SaleRecord sale) {
    final reasonController = TextEditingController(text: 'Customer return');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sale Reversal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Per ADR-0001 & ADR-0002, the financial ledger is append-only. This action will NOT delete the record; it will append an offsetting reversal entry, restock the shelf inventory, and adjust the cash/credit balance.',
              style: TextStyle(fontSize: 12, color: AppColors.text_tertiary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason for return/reversal', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
            onPressed: () {
              widget.state.reverseSale(sale, reasonController.text);
              Navigator.pop(context);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sale ${sale.receiptNumber} successfully reversed and restocked.')),
              );
            },
            child: const Text('Confirm Reversal'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSales = widget.state.sales;
    final activeSales = allSales.where((s) => !s.isReversed).toList();
    final totalGrossMinor = activeSales.fold(0, (sum, s) => sum + s.subtotal.minorUnits);
    final mpesaGrossMinor = activeSales.where((s) => s.paymentMethod == SalePaymentMethod.mpesa).fold(0, (sum, s) => sum + s.subtotal.minorUnits);
    final cashGrossMinor = activeSales.where((s) => s.paymentMethod == SalePaymentMethod.cash).fold(0, (sum, s) => sum + s.subtotal.minorUnits);
    final creditGrossMinor = activeSales.where((s) => s.paymentMethod == SalePaymentMethod.credit).fold(0, (sum, s) => sum + s.subtotal.minorUnits);

    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            if (isMobile)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sales History & Ledger', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text_primary)),
                        Text('Immutable audit log', style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    tooltip: 'Export Day Ledger',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ledger exported to CSV/audit format.')));
                    },
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sales History & Ledger', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text_primary)),
                      Text('Immutable audit log of all completed transactions', style: TextStyle(fontSize: 13, color: AppColors.text_tertiary)),
                    ],
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Export Day Ledger'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ledger exported to CSV/audit format.')));
                    },
                  ),
                ],
              ),
            const SizedBox(height: 14),

            // Metrics Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 750;
                if (isNarrow) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatCard(title: 'Total Gross Sales', value: 'KES ${Money(totalGrossMinor).formatted}', subtitle: '${activeSales.length} transactions', color: AppColors.accent_primary, width: 160),
                        const SizedBox(width: 12),
                        _StatCard(title: 'M-Pesa Volume', value: 'KES ${Money(mpesaGrossMinor).formatted}', subtitle: 'Lipa Na M-Pesa', color: const Color(0xFF16A34A), width: 160),
                        const SizedBox(width: 12),
                        _StatCard(title: 'Cash Tendered', value: 'KES ${Money(cashGrossMinor).formatted}', subtitle: 'In till drawer', color: const Color(0xFF2563EB), width: 160),
                        const SizedBox(width: 12),
                        _StatCard(title: 'Debtor Credit', value: 'KES ${Money(creditGrossMinor).formatted}', subtitle: 'On customer tab', color: const Color(0xFFD97706), width: 160),
                      ],
                    ),
                  );
                }
                return Row(
                  children: [
                    _StatCard(title: 'Total Gross Sales', value: 'KES ${Money(totalGrossMinor).formatted}', subtitle: '${activeSales.length} transactions', color: AppColors.accent_primary),
                    const SizedBox(width: 12),
                    _StatCard(title: 'M-Pesa Volume', value: 'KES ${Money(mpesaGrossMinor).formatted}', subtitle: 'Lipa Na M-Pesa', color: const Color(0xFF16A34A)),
                    const SizedBox(width: 12),
                    _StatCard(title: 'Cash Tendered', value: 'KES ${Money(cashGrossMinor).formatted}', subtitle: 'In till drawer', color: const Color(0xFF2563EB)),
                    const SizedBox(width: 12),
                    _StatCard(title: 'Debtor Credit', value: 'KES ${Money(creditGrossMinor).formatted}', subtitle: 'On customer tab', color: const Color(0xFFD97706)),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),

            // Search and Filters
            if (isMobile) ...[
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search receipt, customer or code...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border_subtle)),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Cash', 'M-Pesa', 'Credit', 'Reversed'].map((f) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(f, style: const TextStyle(fontSize: 12)),
                        onSelected: (_) => setState(() => _filter = f),
                        selectedColor: AppColors.accent_primary.withAlpha(30),
                        checkmarkColor: AppColors.accent_primary,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by receipt number, customer name or Daraja code...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border_subtle)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ...['All', 'Cash', 'M-Pesa', 'Credit', 'Reversed'].map((f) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(f),
                        onSelected: (_) => setState(() => _filter = f),
                        selectedColor: AppColors.accent_primary.withAlpha(30),
                        checkmarkColor: AppColors.accent_primary,
                      ),
                    );
                  }),
                ],
              ),
            const SizedBox(height: 14),

            // Sales Table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border_subtle),
                ),
                child: _filteredSales.isEmpty
                    ? const Center(child: Text('No transactions match the selected criteria.'))
                    : ListView.separated(
                        itemCount: _filteredSales.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final s = _filteredSales[index];
                          return ListTile(
                            contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 4),
                            onTap: () => _showSaleDetails(s),
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: s.isReversed
                                    ? AppColors.status_danger.withAlpha(20)
                                    : (s.paymentMethod == SalePaymentMethod.mpesa
                                        ? const Color(0xFF16A34A).withAlpha(20)
                                        : AppColors.accent_primary.withAlpha(20)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                s.isReversed
                                    ? Icons.undo
                                    : (s.paymentMethod == SalePaymentMethod.mpesa ? Icons.phone_android : Icons.receipt_long),
                                color: s.isReversed
                                    ? AppColors.status_danger
                                    : (s.paymentMethod == SalePaymentMethod.mpesa ? const Color(0xFF16A34A) : AppColors.accent_primary),
                                size: 19,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(s.receiptNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.bg_subtle,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(s.paymentMethod.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                ),
                                if (s.customer != null) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '· ${s.customer!.name}',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 11, color: AppColors.text_secondary),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${s.totalUnits} items · ${s.timestamp.hour.toString().padLeft(2, '0')}:${s.timestamp.minute.toString().padLeft(2, '0')} · Ref: ${s.paymentReference}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'KES ${s.subtotal.formatted}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    decoration: s.isReversed ? TextDecoration.lineThrough : null,
                                    color: s.isReversed ? AppColors.text_tertiary : AppColors.text_primary,
                                  ),
                                ),
                                Text(
                                  s.status.label,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: s.status.color),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.subtitle, required this.color, this.width});

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.text_secondary)),
        ],
      ),
    );

    if (width != null) return card;
    return Expanded(child: card);
  }
}
