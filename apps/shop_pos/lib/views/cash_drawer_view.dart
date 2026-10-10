import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';

/// Enhanced Cash Control & Drawer Reconciliation with Expense Categories.
class CashDrawerView extends StatefulWidget {
  const CashDrawerView({super.key, required this.state});
  final PosState state;
  @override
  State<CashDrawerView> createState() => _CashDrawerViewState();
}

class _CashDrawerViewState extends State<CashDrawerView> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static const _expenseCategories = [
    'Shop Petty Expense', 'Delivery & Transport', 'Utilities (Water/Power)',
    'Staff Allowance', 'Supplier Payment', 'Repairs & Maintenance',
    'Stationery & Supplies', 'Cleaning Supplies', 'Other',
  ];

  void _showMovementModal({required bool isCashIn}) {
    final amountCtrl = TextEditingController();
    String reason = isCashIn ? 'Additional Till Float' : _expenseCategories.first;
    // customReason handled by customCtrl
    final customCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border_subtle)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCashIn ? AppColors.status_success.withValues(alpha: 0.1) : AppColors.status_danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(isCashIn ? Icons.add_circle_outline : Icons.remove_circle_outline, color: isCashIn ? AppColors.status_success : AppColors.status_danger, size: 20),
            ),
            const SizedBox(width: 12),
            Text(isCashIn ? 'Cash In / Float Top-Up' : 'Record Expense / Cash Out', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Amount (KES) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
              const SizedBox(height: 6),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '0',
                  prefixText: 'KES ',
                  filled: true, fillColor: AppColors.bg_subtle,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border_subtle)),
                ),
              ),
              const SizedBox(height: 16),
              if (isCashIn) ...[
                const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: customCtrl,
                  decoration: InputDecoration(hintText: 'e.g. Additional float from safe', filled: true, fillColor: AppColors.bg_subtle, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle))),
                  
                ),
              ] else ...[
                const Text('Expense Category *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: InputDecoration(filled: true, fillColor: AppColors.bg_subtle, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle))),
                  items: _expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) { if (v != null) setModal(() { reason = v; customCtrl.clear(); }); },
                ),
                if (reason == 'Other') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: customCtrl,
                    decoration: InputDecoration(hintText: 'Describe the expense...', filled: true, fillColor: AppColors.bg_subtle, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle))),
                    
                  ),
                ],
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.text_secondary))),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isCashIn ? AppColors.status_success : AppColors.status_danger,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final amount = int.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.')));
                  return;
                }
                final finalReason = isCashIn
                    ? (customCtrl.text.trim().isNotEmpty ? customCtrl.text.trim() : 'Additional Till Float')
                    : (reason == 'Other' && customCtrl.text.trim().isNotEmpty ? customCtrl.text.trim() : reason);
                widget.state.recordCashDrop(Money.shillings(amount), finalReason, isCashIn);
                setState(() {});
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isCashIn ? 'KES $amount added to till.' : 'Expense of KES $amount recorded.'),
                    backgroundColor: isCashIn ? AppColors.status_success : AppColors.status_danger,
                  ),
                );
              },
              child: Text(isCashIn ? 'Confirm Cash In' : 'Record Expense'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloseShiftModal() {
    final countedCtrl = TextEditingController(text: (widget.state.shift.expectedCash.minorUnits ~/ 100).toString());

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final counted = (int.tryParse(countedCtrl.text) ?? 0) * 100;
          final expected = widget.state.shift.expectedCash.minorUnits;
          final diff = counted - expected;
          final isOver = diff > 0;
          final isExact = diff == 0;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border_subtle)),
            title: Row(children: const [Icon(Icons.lock_clock_outlined, color: AppColors.accent_primary), SizedBox(width: 12), Text('Close Shift & Count Cash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text_primary))]),
            content: SizedBox(
              width: 400,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.bg_subtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border_subtle)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('System Expected Cash:', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text_secondary)),
                    Text('KES ${widget.state.shift.expectedCash.formatted}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent_primary, fontSize: 16)),
                  ]),
                ),
                const SizedBox(height: 14),
                const Align(alignment: Alignment.centerLeft, child: Text('Physical Counted Cash (KES) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary))),
                const SizedBox(height: 6),
                TextField(
                  controller: countedCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    prefixText: 'KES ', hintText: '0',
                    filled: true, fillColor: AppColors.bg_subtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border_subtle)),
                  ),
                  onChanged: (_) => setModal(() {}),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isExact ? AppColors.status_success.withValues(alpha: 0.08) : (isOver ? const Color(0xFF2563EB).withValues(alpha: 0.08) : AppColors.status_danger.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isExact ? AppColors.status_success : (isOver ? const Color(0xFF2563EB) : AppColors.status_danger), width: 1),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Variance:', style: TextStyle(fontWeight: FontWeight.w600, color: isExact ? AppColors.status_success : (isOver ? const Color(0xFF2563EB) : AppColors.status_danger))),
                    Text(
                      isExact ? 'EXACT MATCH ✓' : (isOver ? '+ KES ${Money(diff).formatted} OVER' : '- KES ${Money(-diff).formatted} SHORT'),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: isExact ? AppColors.status_success : (isOver ? const Color(0xFF2563EB) : AppColors.status_danger)),
                    ),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.text_secondary))),
              FilledButton.icon(
                icon: const Icon(Icons.lock_outline, size: 16),
                label: const Text('Close Shift'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  final countedVal = int.tryParse(countedCtrl.text) ?? 0;
                  widget.state.closeShift(Money.shillings(countedVal));
                  setState(() {});
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Shift closed and reconciled. Audit log saved.'), backgroundColor: AppColors.status_success),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shift = widget.state.shift;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final movements = shift.movements;
    final expenseTotal = movements.where((m) => m.type == CashMovementType.expenseOut).fold<int>(0, (s, m) => s + m.amount.minorUnits);
    final expenseCount = movements.where((m) => m.type == CashMovementType.expenseOut).length;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: Column(children: [
        // Header
        Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Shift ${shift.shiftId} · ${shift.cashier} · Opened ${shift.openedAt.hour.toString().padLeft(2, '0')}:${shift.openedAt.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                ]),
              ),
              if (!isMobile) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 16, color: AppColors.status_success),
                  label: const Text('Cash In', style: TextStyle(color: AppColors.status_success)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.status_success), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _showMovementModal(isCashIn: true),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.remove_circle_outline, size: 16, color: AppColors.status_danger),
                  label: const Text('Expense Out', style: TextStyle(color: AppColors.status_danger)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.status_danger), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _showMovementModal(isCashIn: false),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_clock_outlined, size: 16),
                  label: Text(shift.isClosed ? 'Shift Closed' : 'Close Shift'),
                  onPressed: shift.isClosed ? null : _showCloseShiftModal,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ],
            ]),
            if (isMobile) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 14, color: AppColors.status_success),
                  label: const Text('Cash In', style: TextStyle(color: AppColors.status_success, fontSize: 12)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.status_success), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () => _showMovementModal(isCashIn: true),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.remove, size: 14, color: AppColors.status_danger),
                  label: const Text('Expense', style: TextStyle(color: AppColors.status_danger, fontSize: 12)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.status_danger), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () => _showMovementModal(isCashIn: false),
                )),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(
                  onPressed: shift.isClosed ? null : _showCloseShiftModal,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: Text(shift.isClosed ? 'Closed' : 'Close Shift', style: const TextStyle(fontSize: 12)),
                )),
              ]),
            ],
          ]),
        ),

        // Status Cards
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
          child: LayoutBuilder(builder: (_, constraints) {
            final cols = constraints.maxWidth > 600 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.8,
              children: [
                _DrawerCard(title: 'Opening Float', value: 'KES ${shift.openingFloat.formatted}', sub: 'Shift start', color: AppColors.text_secondary, icon: Icons.play_circle_outline),
                _DrawerCard(title: 'Cash Sales', value: '+ KES ${shift.cashSales.formatted}', sub: 'Collected', color: AppColors.status_success, icon: Icons.trending_up),
                _DrawerCard(title: 'Expenses Out', value: '- KES ${Money(expenseTotal).formatted}', sub: '$expenseCount entries', color: AppColors.status_danger, icon: Icons.trending_down),
                _DrawerCard(title: 'Expected Balance', value: 'KES ${shift.expectedCash.formatted}', sub: shift.isClosed ? 'CLOSED' : 'Open', color: AppColors.accent_primary, icon: Icons.account_balance, highlight: true),
              ],
            );
          }),
        ),

        const SizedBox(height: 16),

        // Tab bar
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
          child: Container(
            decoration: BoxDecoration(color: AppColors.bg_subtle, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border_subtle)),
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppColors.text_primary, unselectedLabelColor: AppColors.text_tertiary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'All Movements'), Tab(text: 'Expenses Only')],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Journal
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border_subtle)),
              child: TabBarView(
                controller: _tabs,
                children: [
                  _MovementList(movements: movements),
                  _MovementList(movements: movements.where((m) => m.type == CashMovementType.expenseOut).toList()),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _MovementList extends StatelessWidget {
  const _MovementList({required this.movements});
  final List<CashMovement> movements;

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.border_subtle),
        SizedBox(height: 12),
        Text('No entries in this view', style: TextStyle(color: AppColors.text_tertiary)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: movements.length,
      separatorBuilder: (_, __) => const Divider(color: AppColors.border_subtle, height: 1),
      itemBuilder: (_, i) {
        final m = movements[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: m.type.isInflow ? AppColors.status_success.withValues(alpha: 0.1) : AppColors.status_danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(m.type.isInflow ? Icons.south : Icons.north, size: 17, color: m.type.isInflow ? AppColors.status_success : AppColors.status_danger),
          ),
          title: Row(children: [
            Flexible(child: Text(m.type.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_primary))),
            const SizedBox(width: 8),
            Flexible(child: Text('· ${m.reason}', style: const TextStyle(fontSize: 12, color: AppColors.text_secondary), overflow: TextOverflow.ellipsis)),
          ]),
          subtitle: Text('${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')} · ${m.cashier}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
          trailing: Text(
            '${m.type.isInflow ? '+' : '-'} KES ${m.amount.formatted}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: m.type.isInflow ? AppColors.status_success : AppColors.status_danger),
          ),
        );
      },
    );
  }
}

class _DrawerCard extends StatelessWidget {
  const _DrawerCard({required this.title, required this.value, required this.sub, required this.color, required this.icon, this.highlight = false});
  final String title, value, sub;
  final Color color;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: highlight ? AppColors.accent_primary.withValues(alpha: 0.06) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: highlight ? AppColors.accent_primary : AppColors.border_subtle, width: highlight ? 1.5 : 1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Flexible(child: Text(title, style: const TextStyle(fontSize: 10, color: AppColors.text_tertiary), overflow: TextOverflow.ellipsis))]),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.3)),
      const SizedBox(height: 2),
      Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.text_tertiary)),
    ]),
  );
}
