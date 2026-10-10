import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../shared/icons.dart';

class DeliveryView extends StatefulWidget {
  const DeliveryView({super.key, required this.state});

  final PosState state;

  @override
  State<DeliveryView> createState() => _DeliveryViewState();
}

class _DeliveryViewState extends State<DeliveryView> {
  @override
  Widget build(BuildContext context) {
    final isManager = [
      PosUserRole.manager,
      PosUserRole.owner,
      PosUserRole.superAdmin,
    ].contains(widget.state.currentLoggedInUser?.role);

    return DefaultTabController(
      length: isManager ? 3 : 1,
      child: Scaffold(
        backgroundColor: AppColors.bg_canvas,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.bg_surface,
          elevation: 0,
          title: const Text(
            'Delivery Management',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.text_primary),
          ),
          bottom: TabBar(
            labelColor: AppColors.accent_primary,
            unselectedLabelColor: AppColors.text_tertiary,
            indicatorColor: AppColors.accent_primary,
            tabs: [
              const Tab(text: 'Orders'),
              if (isManager) const Tab(text: 'Riders'),
              if (isManager) const Tab(text: 'Config'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DeliveryOrdersTab(state: widget.state, isManager: isManager),
            if (isManager) _RidersTab(state: widget.state),
            if (isManager) _DeliveryConfigTab(state: widget.state),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Orders Tab
// ─────────────────────────────────────────────────────────────────

class _DeliveryOrdersTab extends StatefulWidget {
  const _DeliveryOrdersTab({
    required this.state,
    required this.isManager,
  });

  final PosState state;
  final bool isManager;

  @override
  State<_DeliveryOrdersTab> createState() => _DeliveryOrdersTabState();
}

class _DeliveryOrdersTabState extends State<_DeliveryOrdersTab> {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _riders = [];
  String? _filter; // null = all
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ordersEnvelope = await ApiService.instance
        .getDeliveryOrders(status: _filter);
    final rawOrders = ordersEnvelope?['data'] as List? ?? [];
    final riders = widget.isManager
        ? await ApiService.instance.getRiders()
        : <Map<String, dynamic>>[];
    if (mounted) {
      setState(() {
        _orders = rawOrders.cast<Map<String, dynamic>>();
        _riders = riders ?? [];
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) => switch (status) {
        'PENDING'    => const Color(0xFFF59E0B),
        'ASSIGNED'   => const Color(0xFF3B82F6),
        'IN_TRANSIT' => AppColors.accent_primary,
        'DELIVERED'  => AppColors.status_success,
        'FAILED'     => AppColors.status_danger,
        _            => AppColors.text_tertiary,
      };

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final distCtrl = TextEditingController();
    double? previewFee;
    Map<String, dynamic>? config;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Load config once for fee preview
          if (config == null) {
            ApiService.instance.getDeliveryConfig().then((c) {
              if (c != null && ctx.mounted) {
                setDialogState(() => config = c);
              }
            });
          }

          void recalcFee() {
            final dist = double.tryParse(distCtrl.text.trim()) ?? 0.0;
            if (config != null && dist > 0) {
              final base = double.tryParse(
                      config!['baseFee']?.toString() ?? '0') ??
                  0.0;
              final rate = double.tryParse(
                      config!['distanceTopupRate']?.toString() ?? '0') ??
                  0.0;
              setDialogState(() => previewFee = base + rate * dist);
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.bg_surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(AppIcons.shipping, color: AppColors.accent_primary),
                SizedBox(width: 10),
                Text('New Delivery Order',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: math.min(400.0, MediaQuery.sizeOf(context).width - 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogField(nameCtrl, 'Recipient Name *',
                        AppIcons.person),
                    const SizedBox(height: 12),
                    _dialogField(phoneCtrl, 'Recipient Phone *',
                        AppIcons.phone,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),
                    _dialogField(addressCtrl, 'Delivery Address *',
                        AppIcons.storefront),
                    const SizedBox(height: 12),
                    TextField(
                      controller: distCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => recalcFee(),
                      decoration: InputDecoration(
                        labelText: 'Distance (km) *',
                        prefixIcon:
                            const Icon(AppIcons.arrowForward, size: 20),
                        filled: true,
                        fillColor: AppColors.bg_canvas,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.border_subtle)),
                      ),
                    ),
                    if (previewFee != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accent_light,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Estimated Fee',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.accent_primary)),
                            Text(
                              'KES ${previewFee!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accent_primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.text_secondary)),
              ),
              FilledButton.icon(
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('Create Order'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent_primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();
                  final address = addressCtrl.text.trim();
                  final dist =
                      double.tryParse(distCtrl.text.trim()) ?? 0.0;

                  if (name.isEmpty || phone.isEmpty || address.isEmpty ||
                      dist <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Please fill in all required fields.')),
                    );
                    return;
                  }

                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final result =
                      await ApiService.instance.createDeliveryOrder({
                    'recipientName': name,
                    'recipientPhone': phone,
                    'deliveryAddress': address,
                    'distanceKm': dist,
                  });

                  if (!mounted) return;
                  if (result != null) {
                    messenger.showSnackBar(
                      const SnackBar(
                          content: Text('Delivery order created.'),
                          backgroundColor: AppColors.status_success),
                    );
                    _load();
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Could not create order. Please try again.'),
                          backgroundColor: AppColors.status_danger),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionRow(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    final orderId = order['id'] as String? ?? '';
    final currentRiderId = order['riderId'] as String?;

    return Row(
      children: [
        // Rider assignment dropdown (pending or assigned)
        if ((status == 'PENDING' || status == 'ASSIGNED') &&
            _riders.isNotEmpty)
          Expanded(
            child: DropdownButton<String>(
              value: _riders.any((r) => r['id'] == currentRiderId)
                  ? currentRiderId
                  : null,
              hint: const Text('Assign Rider',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text_tertiary)),
              isExpanded: true,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.text_primary),
              underline: const SizedBox.shrink(),
              items: _riders
                  .map((r) => DropdownMenuItem<String>(
                        value: r['id'] as String?,
                        child: Text(r['fullName']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (riderId) async {
                if (riderId == null) return;
                final result = await ApiService.instance
                    .assignRider(orderId, riderId);
                if (!mounted) return;
                if (result != null) {
                  _load();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Could not assign rider.')),
                  );
                }
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const statuses = ['PENDING', 'ASSIGNED', 'IN_TRANSIT', 'DELIVERED'];

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      floatingActionButton: widget.isManager
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(AppIcons.add),
              label: const Text('New Delivery'),
              backgroundColor: AppColors.accent_primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            // Filter chips
            Container(
              color: AppColors.bg_surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) {
                      setState(() => _filter = null);
                      _load();
                    },
                    selectedColor: AppColors.accent_light,
                    checkmarkColor: AppColors.accent_primary,
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: _filter == null
                            ? AppColors.accent_primary
                            : AppColors.text_secondary),
                  ),
                  for (final s in statuses)
                    FilterChip(
                      label: Text(s.replaceAll('_', ' ')),
                      selected: _filter == s,
                      onSelected: (_) {
                        setState(() => _filter = s);
                        _load();
                      },
                      selectedColor: AppColors.accent_light,
                      checkmarkColor: AppColors.accent_primary,
                      labelStyle: TextStyle(
                          fontSize: 12,
                          color: _filter == s
                              ? AppColors.accent_primary
                              : AppColors.text_secondary),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Order list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _orders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(AppIcons.shipping,
                                  size: 48,
                                  color: AppColors.text_tertiary),
                              const SizedBox(height: 12),
                              Text(
                                _filter == null
                                    ? 'No delivery orders yet.'
                                    : 'No ${_filter!.replaceAll('_', ' ')} orders.',
                                style: const TextStyle(
                                    color: AppColors.text_tertiary,
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: _orders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final order = _orders[i];
                            final status =
                                order['status'] as String? ?? '';
                            final fee = double.tryParse(
                                    order['deliveryFee']?.toString() ??
                                        '0') ??
                                0.0;
                            final riderName =
                                order['riderName']?.toString();

                            return Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(
                                    color: AppColors.border_subtle),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status)
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            status.replaceAll('_', ' '),
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _statusColor(status)),
                                          ),
                                        ),
                                        Text(
                                          'KES ${fee.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: AppColors.accent_primary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      order['recipientName']
                                              ?.toString() ??
                                          '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                    Text(
                                      order['recipientPhone']
                                              ?.toString() ??
                                          '',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text_tertiary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      order['deliveryAddress']
                                              ?.toString() ??
                                          '',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text_secondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (riderName != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Rider: $riderName',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.text_tertiary,
                                            fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                    if (widget.isManager) ...[
                                      const SizedBox(height: 8),
                                      _actionRow(order),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _dialogField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppColors.bg_canvas,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border_subtle)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Riders Tab
// ─────────────────────────────────────────────────────────────────

class _RidersTab extends StatefulWidget {
  const _RidersTab({required this.state});

  final PosState state;

  @override
  State<_RidersTab> createState() => _RidersTabState();
}

class _RidersTabState extends State<_RidersTab> {
  List<Map<String, dynamic>> _riders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final riders = await ApiService.instance.getRiders();
    if (mounted) {
      setState(() {
        _riders = riders ?? [];
        _loading = false;
      });
    }
  }

  void _showPayoutDialog(Map<String, dynamic> rider) {
    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(
        text: rider['phone']?.toString() ?? '');
    final riderId = rider['id'] as String? ?? '';
    final riderName = rider['fullName']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(AppIcons.wallet, color: AppColors.accent_primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rider Payout',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(riderName,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text_secondary)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: math.min(360.0, MediaQuery.sizeOf(context).width - 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (KES) *',
                  prefixIcon: const Icon(AppIcons.money, size: 20),
                  filled: true,
                  fillColor: AppColors.bg_canvas,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'M-Pesa Phone *',
                  prefixIcon: const Icon(AppIcons.phoneAndroid, size: 20),
                  filled: true,
                  fillColor: AppColors.bg_canvas,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.text_secondary)),
          ),
          FilledButton.icon(
            icon: const Icon(AppIcons.send, size: 16),
            label: const Text('Send Payout'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent_primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final amount =
                  double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              final phone = phoneCtrl.text.trim();
              if (amount <= 0 || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Enter a valid amount and phone.')),
                );
                return;
              }
              Navigator.pop(ctx);
              final ok = await ApiService.instance
                  .initiateRiderPayout(riderId, amount, phone);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Payout of KES ${amount.toStringAsFixed(2)} initiated for $riderName.'
                      : 'Payout failed. Please try again.'),
                  backgroundColor:
                      ok ? AppColors.status_success : AppColors.status_danger,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _riders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(AppIcons.person,
                          size: 48, color: AppColors.text_tertiary),
                      SizedBox(height: 12),
                      Text('No riders registered.',
                          style: TextStyle(
                              color: AppColors.text_tertiary, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _riders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final rider = _riders[i];
                    final balance = double.tryParse(
                            rider['pendingBalance']?.toString() ?? '0') ??
                        0.0;
                    return Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border_subtle),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.accent_light,
                          child: Text(
                            (rider['fullName']?.toString() ?? 'R')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.accent_primary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          rider['fullName']?.toString() ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          rider['phone']?.toString() ?? '',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'KES ${balance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.accent_primary),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => _showPayoutDialog(rider),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent_primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Pay Out',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Config Tab
// ─────────────────────────────────────────────────────────────────

class _DeliveryConfigTab extends StatefulWidget {
  const _DeliveryConfigTab({required this.state});

  final PosState state;

  @override
  State<_DeliveryConfigTab> createState() => _DeliveryConfigTabState();
}

class _DeliveryConfigTabState extends State<_DeliveryConfigTab> {
  final _baseFeeCtrl = TextEditingController();
  final _topupCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseFeeCtrl.dispose();
    _topupCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final config = await ApiService.instance.getDeliveryConfig();
    if (mounted) {
      _baseFeeCtrl.text =
          config?['baseFee']?.toString() ?? '0';
      _topupCtrl.text =
          config?['distanceTopupRate']?.toString() ?? '0';
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final base = double.tryParse(_baseFeeCtrl.text.trim()) ?? 0.0;
    final rate = double.tryParse(_topupCtrl.text.trim()) ?? 0.0;
    setState(() => _saving = true);
    final ok = await ApiService.instance.updateDeliveryConfig(base, rate);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Delivery config saved.'
            : 'Could not save config. Please try again.'),
        backgroundColor:
            ok ? AppColors.status_success : AppColors.status_danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border_subtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fee Structure',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.text_primary)),
                const SizedBox(height: 4),
                const Text(
                  'Fee = Base Fee + (Distance × Per-km Rate)',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text_tertiary),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _baseFeeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Base Fee (KES)',
                    prefixIcon: const Icon(AppIcons.money, size: 20),
                    filled: true,
                    fillColor: AppColors.bg_canvas,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border_subtle)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _topupCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Per-km Rate (KES / km)',
                    prefixIcon: const Icon(AppIcons.arrowForward, size: 20),
                    filled: true,
                    fillColor: AppColors.bg_canvas,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border_subtle)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(AppIcons.save, size: 18),
                    label: const Text('Save Configuration'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent_primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
