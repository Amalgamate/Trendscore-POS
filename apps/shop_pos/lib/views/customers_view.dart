import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';
import '../shared/icons.dart';

class CustomersView extends StatefulWidget {
  const CustomersView({super.key, required this.state});

  final PosState state;

  @override
  State<CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<CustomersView> {
  final _search = TextEditingController();
  PosCustomer? _selectedCustomer;
  String _ledgerFilter = 'All'; // 'All', 'Debits' (Purchases), 'Credits' (Payments)
  bool _mobileShowDetails = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.customers.isNotEmpty) {
      _selectedCustomer = widget.state.customers.first;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PosCustomer> get _filteredCustomers {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.state.customers;
    return widget.state.customers.where((c) {
      return c.name.toLowerCase().contains(query) || c.phone.contains(query);
    }).toList();
  }

  List<CustomerLedgerEntry> _getFilteredLedger(PosCustomer customer) {
    if (_ledgerFilter == 'Debits') {
      return customer.ledger.where((e) => e.type.isDebit).toList();
    } else if (_ledgerFilter == 'Credits') {
      return customer.ledger.where((e) => !e.type.isDebit).toList();
    }
    return customer.ledger;
  }

  void _showRecordPaymentModal(PosCustomer customer) {
    final amountController = TextEditingController(
      text: (customer.currentBalance.minorUnits ~/ 100).toString(),
    );
    String selectedMethod = 'M-Pesa';
    final refController = TextEditingController(
      text: 'MPESA-QCG${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );
    final notesController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.bg_surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(AppIcons.payments, color: AppColors.status_success, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Record Debt Settlement',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text_primary),
                      ),
                      Text(
                        customer.name,
                        style: const TextStyle(fontSize: 13, color: AppColors.text_secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(440.0, MediaQuery.sizeOf(context).width - 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance status card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Outstanding Debt', style: TextStyle(fontSize: 11, color: Color(0xFF92400E))),
                              const SizedBox(height: 2),
                              Text(
                                'KES ${customer.currentBalance.formatted}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Credit Limit', style: TextStyle(fontSize: 11, color: Color(0xFF92400E))),
                              const SizedBox(height: 2),
                              Text(
                                'KES ${customer.creditLimit.formatted}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text_primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick settlement chips
                    const Text('Quick Amount Settlement:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text_secondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: Text('Full (${customer.currentBalance.formatted})'),
                          backgroundColor: AppColors.accent_light,
                          side: BorderSide.none,
                          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent_primary),
                          onPressed: () {
                            setDialogState(() {
                              amountController.text = (customer.currentBalance.minorUnits ~/ 100).toString();
                            });
                          },
                        ),
                        if (customer.currentBalance.minorUnits > 20000)
                          ActionChip(
                            label: const Text('50% Half'),
                            backgroundColor: AppColors.bg_canvas,
                            side: const BorderSide(color: AppColors.border_subtle),
                            labelStyle: const TextStyle(fontSize: 11, color: AppColors.text_primary),
                            onPressed: () {
                              setDialogState(() {
                                final half = (customer.currentBalance.minorUnits ~/ 200);
                                amountController.text = half.toString();
                              });
                            },
                          ),
                        ActionChip(
                          label: const Text('KES 1,000'),
                          backgroundColor: AppColors.bg_canvas,
                          side: const BorderSide(color: AppColors.border_subtle),
                          labelStyle: const TextStyle(fontSize: 11, color: AppColors.text_primary),
                          onPressed: () => setDialogState(() => amountController.text = '1000'),
                        ),
                        ActionChip(
                          label: const Text('KES 500'),
                          backgroundColor: AppColors.bg_canvas,
                          side: const BorderSide(color: AppColors.border_subtle),
                          labelStyle: const TextStyle(fontSize: 11, color: AppColors.text_primary),
                          onPressed: () => setDialogState(() => amountController.text = '500'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Amount input
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Payment Amount (KES) *',
                        prefixIcon: const Icon(AppIcons.money, size: 20),
                        filled: true,
                        fillColor: AppColors.bg_canvas,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Payment method chips
                    const Text('Payment Method *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text_secondary)),
                    const SizedBox(height: 6),
                    Row(
                      children: ['M-Pesa', 'Cash', 'Bank Transfer'].map((m) {
                        final isSel = selectedMethod == m;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Center(child: Text(m, style: TextStyle(fontSize: 12, fontWeight: isSel ? FontWeight.bold : FontWeight.normal))),
                              selected: isSel,
                              selectedColor: AppColors.accent_primary,
                              labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.text_primary),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    selectedMethod = m;
                                    if (m == 'M-Pesa') {
                                      refController.text = 'MPESA-QCG${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                                    } else if (m == 'Cash') {
                                      refController.text = 'CASH: TILL-COUNTER-01';
                                    } else {
                                      refController.text = 'BANK: EFT-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Reference
                    TextField(
                      controller: refController,
                      decoration: InputDecoration(
                        labelText: 'Transaction Reference *',
                        prefixIcon: const Icon(AppIcons.tag, size: 20),
                        filled: true,
                        fillColor: AppColors.bg_canvas,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Memo
                    TextField(
                      controller: notesController,
                      decoration: InputDecoration(
                        labelText: 'Receipt Memo / Notes (Optional)',
                        prefixIcon: const Icon(AppIcons.notes, size: 20),
                        filled: true,
                        fillColor: AppColors.bg_canvas,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.text_secondary)),
              ),
              FilledButton.icon(
                icon: const Icon(AppIcons.checkCircle, size: 18),
                label: const Text('Confirm Payment'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.status_success,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final val = int.tryParse(amountController.text.trim()) ?? 0;
                  if (val <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid amount greater than 0')),
                    );
                    return;
                  }

                  final ref = refController.text.trim().isEmpty ? '$selectedMethod: REF-${DateTime.now().millisecondsSinceEpoch}' : refController.text.trim();
                  widget.state.recordCustomerPayment(customer.id, Money.shillings(val), ref);

                  setState(() {});
                  Navigator.pop(ctx);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment of KES $val recorded for ${customer.name}. Account balance updated!'),
                      backgroundColor: AppColors.status_success,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showNewCustomerModal() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: '+2547');
    final limitCtrl = TextEditingController(text: '10000');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(AppIcons.personAdd, color: AppColors.accent_primary),
            SizedBox(width: 10),
            Text('Open Customer Credit Facility', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: math.min(380.0, MediaQuery.sizeOf(context).width - 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Customer Full Name *',
                  prefixIcon: const Icon(AppIcons.person),
                  filled: true,
                  fillColor: AppColors.bg_canvas,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile Phone (+254...) *',
                  prefixIcon: const Icon(AppIcons.phone),
                  filled: true,
                  fillColor: AppColors.bg_canvas,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Approved Credit Limit (KES)',
                  prefixIcon: const Icon(AppIcons.creditCard),
                  filled: true,
                  fillColor: AppColors.bg_canvas,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent_primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              final limit = int.tryParse(limitCtrl.text.trim()) ?? 0;

              if (name.isNotEmpty && phone.isNotEmpty) {
                final customer = PosCustomer(
                  id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  phone: phone,
                  creditLimit: Money.shillings(limit),
                  currentBalance: const Money(0),
                  history: [],
                );

                widget.state.addCustomer(customer);
                setState(() {
                  _selectedCustomer = customer;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Account opened for $name with KES $limit credit facility!')),
                );
              }
            },
            child: const Text('Create Account'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCustomer(PosCustomer customer) async {
    final hasBalance = customer.currentBalance.minorUnits > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(AppIcons.delete, color: AppColors.status_danger, size: 22),
            SizedBox(width: 10),
            Text('Delete Customer', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: hasBalance
            ? Text(
                '${customer.name} still has an outstanding balance of KES ${customer.currentBalance.formatted}.\n\nClear the debt before deleting this account.',
                style: const TextStyle(fontSize: 14),
              )
            : Text(
                'Are you sure you want to permanently delete ${customer.name}? This cannot be undone.',
                style: const TextStyle(fontSize: 14),
              ),
        actions: hasBalance
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('OK'),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
      ),
    );

    if (confirmed != true) return;

    final error = await widget.state.deleteCustomer(customer.id);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.status_danger),
      );
    } else {
      setState(() {
        _selectedCustomer = widget.state.customers.isNotEmpty ? widget.state.customers.first : null;
        _mobileShowDetails = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${customer.name} has been deleted.'), backgroundColor: AppColors.status_success),
      );
    }
  }

  void _showPrintStatementDialog(PosCustomer customer) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Account Statement Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(AppIcons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
        content: SizedBox(
          width: math.min(520.0, MediaQuery.sizeOf(context).width - 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Shop Branding Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bg_canvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border_subtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.state.shopName.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent_primary),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                            child: const Text('DEBTOR STATEMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                          ),
                        ],
                      ),
                      Text('Branch: ${widget.state.storeBranch} · Till: ${widget.state.tillId}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Customer: ${customer.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Mobile: ${customer.phone}', style: const TextStyle(fontSize: 11, color: AppColors.text_secondary)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Date: ${DateTime.now().toLocal().toString().split(" ")[0]}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                              Text('Account Ref: ${customer.id}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.text_secondary)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Statement Summary Table
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MiniMetric(label: 'Total Credit Limit', value: 'KES ${customer.creditLimit.formatted}', color: AppColors.text_primary),
                      _MiniMetric(label: 'Current Balance Due', value: 'KES ${customer.currentBalance.formatted}', color: const Color(0xFFD97706)),
                      _MiniMetric(label: 'Available Balance', value: 'KES ${customer.availableCredit.formatted}', color: const Color(0xFF16A34A)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                const Text('Transaction Timeline:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: customer.ledger.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = customer.ledger[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(
                              '${item.timestamp.month.toString().padLeft(2, '0')}/${item.timestamp.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.type.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  Text(item.reference, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.text_tertiary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${item.type.isDebit ? "+" : "-"} KES ${item.amount.formatted}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: item.type.isDebit ? AppColors.status_danger : AppColors.status_success,
                                  ),
                                ),
                                Text('Bal: ${item.runningBalance.formatted}', style: const TextStyle(fontSize: 10, color: AppColors.text_tertiary)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(AppIcons.share, size: 16),
            label: const Text('Share SMS / WhatsApp'),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Statement summary sent to ${customer.phone}!')),
              );
            },
          ),
          FilledButton.icon(
            icon: const Icon(AppIcons.print, size: 16),
            label: const Text('Print Statement'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent_primary),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sending statement to thermal receipt printer...')),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = widget.state.customers;
    final totalOutstandingMinor = customers.fold(0, (sum, c) => sum + c.currentBalance.minorUnits);
    final totalLimitMinor = customers.fold(0, (sum, c) => sum + c.creditLimit.minorUnits);
    final highRiskCount = customers.where((c) {
      if (c.creditLimit.minorUnits == 0) return false;
      return (c.currentBalance.minorUnits / c.creditLimit.minorUnits) > 0.8;
    }).length;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 780;

          return Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Customer Credit & Debt Ledger',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text_primary),
                          ),
                          Text(
                            'Append-only customer debt ledger · Real-time balances',
                            style: TextStyle(fontSize: 12, color: AppColors.text_tertiary),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      icon: const Icon(AppIcons.personAdd, size: 16),
                      label: Text(isMobile ? 'Add' : 'New Account'),
                      onPressed: _showNewCustomerModal,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent_primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Summary KPI Cards
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CustStatCard(
                        title: 'Total Outstanding Debt',
                        value: 'KES ${Money(totalOutstandingMinor).formatted}',
                        subtitle: 'Owed across ${customers.length} accounts',
                        color: const Color(0xFFD97706),
                        width: isMobile ? 160 : 210,
                      ),
                      const SizedBox(width: 10),
                      _CustStatCard(
                        title: 'Total Credit Allocated',
                        value: 'KES ${Money(totalLimitMinor).formatted}',
                        subtitle: 'Total authorized credit',
                        color: AppColors.accent_primary,
                        width: isMobile ? 160 : 210,
                      ),
                      const SizedBox(width: 10),
                      _CustStatCard(
                        title: 'Credit Utilization',
                        value: totalLimitMinor > 0 ? '${((totalOutstandingMinor / totalLimitMinor) * 100).toStringAsFixed(1)}%' : '0%',
                        subtitle: highRiskCount > 0 ? '$highRiskCount accounts > 80% limit' : 'Portfolio risk healthy',
                        color: highRiskCount > 0 ? AppColors.status_danger : const Color(0xFF16A34A),
                        width: isMobile ? 160 : 210,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Main Content: Mobile toggle or Desktop Dual-Pane
                Expanded(
                  child: isMobile
                      ? (_mobileShowDetails && _selectedCustomer != null
                          ? _buildCustomerDetailsPane(_selectedCustomer!, isMobile: true)
                          : _buildCustomerListPane(isMobile: true))
                      : Row(
                          children: [
                            SizedBox(
                              width: 360,
                              child: _buildCustomerListPane(isMobile: false),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _selectedCustomer == null
                                  ? const Center(child: Text('Select an account to view credit statement'))
                                  : _buildCustomerDetailsPane(_selectedCustomer!, isMobile: false),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCustomerListPane({required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search customer name or phone...',
                prefixIcon: const Icon(AppIcons.search, size: 18),
                filled: true,
                fillColor: AppColors.bg_canvas,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filteredCustomers.isEmpty
                ? const Center(child: Text('No customers found', style: TextStyle(color: AppColors.text_tertiary)))
                : ListView.separated(
                    itemCount: _filteredCustomers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = _filteredCustomers[index];
                      final isSelected = c.id == _selectedCustomer?.id;
                      final ratio = c.creditLimit.minorUnits > 0 ? (c.currentBalance.minorUnits / c.creditLimit.minorUnits) : 0.0;
                      final isHigh = ratio > 0.8;

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: AppColors.accent_primary.withValues(alpha: 0.08),
                        onTap: () {
                          setState(() {
                            _selectedCustomer = c;
                            if (isMobile) _mobileShowDetails = true;
                          });
                        },
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? AppColors.accent_primary : AppColors.bg_subtle,
                          child: Text(
                            c.name.isNotEmpty ? c.name.substring(0, 1).toUpperCase() : 'C',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppColors.text_primary,
                            ),
                          ),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.phone, style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: ratio.clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: AppColors.bg_subtle,
                                valueColor: AlwaysStoppedAnimation(isHigh ? AppColors.status_danger : AppColors.accent_primary),
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'KES ${c.currentBalance.formatted}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.currentBalance.minorUnits > 0 ? const Color(0xFFD97706) : AppColors.status_success,
                              ),
                            ),
                            Text(
                              'Limit: ${c.creditLimit.formatted}',
                              style: const TextStyle(fontSize: 10, color: AppColors.text_tertiary),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetailsPane(PosCustomer customer, {required bool isMobile}) {
    final filteredLedger = _getFilteredLedger(customer);

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with back button on mobile
          Row(
            children: [
              if (isMobile)
                IconButton(
                  icon: const Icon(AppIcons.arrowBack),
                  onPressed: () => setState(() => _mobileShowDetails = false),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text_primary)),
                    Text('${customer.phone} · Ref: ${customer.id}', style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(AppIcons.receiptLong, size: 16),
                label: const Text('Statement'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showPrintStatementDialog(customer),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(AppIcons.payments, size: 16),
                label: const Text('Pay Debt'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.status_success,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showRecordPaymentModal(customer),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Delete customer',
                icon: const Icon(AppIcons.delete, size: 20, color: AppColors.status_danger),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _confirmDeleteCustomer(customer),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Mini metrics bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bg_canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border_subtle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MiniMetric(label: 'Current Debt Due', value: 'KES ${customer.currentBalance.formatted}', color: const Color(0xFFD97706)),
                _MiniMetric(label: 'Approved Limit', value: 'KES ${customer.creditLimit.formatted}', color: AppColors.text_primary),
                _MiniMetric(label: 'Available Credit', value: 'KES ${customer.availableCredit.formatted}', color: const Color(0xFF16A34A)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Ledger Filter chips
          Row(
            children: [
              const Text('Ledger History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.text_primary)),
              const Spacer(),
              Row(
                children: ['All', 'Debits', 'Credits'].map((f) {
                  final isSel = _ledgerFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(f, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      selected: isSel,
                      selectedColor: AppColors.accent_light,
                      labelStyle: TextStyle(color: isSel ? AppColors.accent_primary : AppColors.text_secondary),
                      onSelected: (val) {
                        if (val) setState(() => _ledgerFilter = f);
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Ledger List
          Expanded(
            child: filteredLedger.isEmpty
                ? const Center(child: Text('No ledger entries recorded yet', style: TextStyle(color: AppColors.text_tertiary)))
                : ListView.separated(
                    itemCount: filteredLedger.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = filteredLedger[index];
                      final isDebit = entry.type.isDebit;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDebit ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDebit ? AppIcons.arrowUp : AppIcons.arrowDown,
                            size: 18,
                            color: isDebit ? AppColors.status_danger : AppColors.status_success,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(entry.type.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(entry.reference, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.text_secondary)),
                          ],
                        ),
                        subtitle: Text(
                          '${entry.timestamp.year}-${entry.timestamp.month.toString().padLeft(2, '0')}-${entry.timestamp.day.toString().padLeft(2, '0')} ${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isDebit ? "+" : "-"} KES ${entry.amount.formatted}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDebit ? AppColors.status_danger : AppColors.status_success,
                              ),
                            ),
                            Text('Bal: KES ${entry.runningBalance.formatted}', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustStatCard extends StatelessWidget {
  const _CustStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    this.width,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
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
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.text_secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
