import 'package:flutter/material.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../shared/icons.dart';
import 'rider_order_detail_view.dart';

class RiderHomeView extends StatefulWidget {
  const RiderHomeView({
    super.key,
    required this.state,
    required this.onLogout,
  });

  final PosState state;
  final VoidCallback onLogout;

  @override
  State<RiderHomeView> createState() => _RiderHomeViewState();
}

class _RiderHomeViewState extends State<RiderHomeView> {
  List<Map<String, dynamic>> _orders = [];
  String _pendingBalance = '0.00';
  List<Map<String, dynamic>> _ledgerEntries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final orders = await ApiService.instance.getRiderOrders();
    final earnings = await ApiService.instance.getRiderEarnings();
    if (mounted) {
      setState(() {
        _orders = orders ?? [];
        _pendingBalance =
            (earnings?['pendingBalance'] as String?) ?? '0.00';
        _ledgerEntries = (earnings?['entries'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
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

  void _showLedgerSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border_subtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Earnings History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            Expanded(
              child: _ledgerEntries.isEmpty
                  ? const Center(child: Text('No earnings history yet.'))
                  : ListView.separated(
                      controller: scroll,
                      itemCount: _ledgerEntries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _ledgerEntries[i];
                        final isCredit = e['entryType'] == 'CREDIT';
                        final amt = double.tryParse(
                                e['amount']?.toString() ?? '0') ??
                            0.0;
                        return ListTile(
                          title: Text(
                              isCredit ? 'Delivery Earned' : 'Payout',
                              style: const TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(e['createdAt']?.toString() ?? '',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(
                            '${isCredit ? '+' : '-'} KES ${amt.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCredit
                                    ? AppColors.status_success
                                    : AppColors.status_danger),
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

  @override
  Widget build(BuildContext context) {
    final rider = widget.state.currentLoggedInUser;
    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg_surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rider Dashboard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: AppColors.text_primary)),
            if (rider != null)
              Text(rider.fullName,
                  style: const TextStyle(fontSize: 12,
                      color: AppColors.text_tertiary)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(AppIcons.lock, color: AppColors.text_tertiary),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Earnings banner
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.accent_primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(AppIcons.shipping, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            const Text('Your Earnings',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ]),
                          const SizedBox(height: 8),
                          Text('KES $_pendingBalance',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 28,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          const Text('Available for payout',
                              style: TextStyle(color: Colors.white60, fontSize: 12)),
                          const SizedBox(height: 10),
                          TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero),
                            onPressed: _showLedgerSheet,
                            child: const Text('View History →'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Active orders
                    Row(children: [
                      const Text('Active Deliveries',
                          style: TextStyle(fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text_primary)),
                      const SizedBox(width: 8),
                      if (_orders.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent_primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${_orders.length}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ]),
                    const SizedBox(height: 10),

                    if (_orders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border_subtle),
                        ),
                        child: const Column(children: [
                          Icon(AppIcons.shipping, size: 40,
                              color: AppColors.text_tertiary),
                          SizedBox(height: 8),
                          Text('No active deliveries',
                              style: TextStyle(color: AppColors.text_tertiary,
                                  fontSize: 14)),
                          Text('Check back soon.',
                              style: TextStyle(color: AppColors.text_tertiary,
                                  fontSize: 12)),
                        ]),
                      )
                    else
                      ...(_orders.map((order) {
                        final status = order['status'] as String? ?? '';
                        final fee = double.tryParse(
                                order['deliveryFee']?.toString() ?? '0') ??
                            0.0;
                        return GestureDetector(
                          onTap: () async {
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RiderOrderDetailView(
                                  order: order,
                                  state: widget.state,
                                ),
                              ),
                            );
                            await _refresh();
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border_subtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.replaceAll('_', ' '),
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _statusColor(status)),
                                      ),
                                    ),
                                    Text('KES ${fee.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppColors.accent_primary)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  order['recipientName']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  order['recipientPhone']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.text_tertiary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  order['deliveryAddress']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.text_secondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      })),
                  ],
                ),
              ),
      ),
    );
  }
}
