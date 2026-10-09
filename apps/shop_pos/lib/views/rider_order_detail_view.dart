import 'package:flutter/material.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../shared/icons.dart';

class RiderOrderDetailView extends StatefulWidget {
  const RiderOrderDetailView({
    super.key,
    required this.order,
    required this.state,
  });

  final Map<String, dynamic> order;
  final PosState state;

  @override
  State<RiderOrderDetailView> createState() => _RiderOrderDetailViewState();
}

class _RiderOrderDetailViewState extends State<RiderOrderDetailView> {
  late Map<String, dynamic> _order;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Color _statusColor(String status) {
    return switch (status) {
      'PENDING'    => const Color(0xFFF59E0B),
      'ASSIGNED'   => const Color(0xFF3B82F6),
      'IN_TRANSIT' => AppColors.accent_primary,
      'DELIVERED'  => AppColors.status_success,
      'FAILED'     => AppColors.status_danger,
      _            => AppColors.text_tertiary,
    };
  }

  Future<void> _advanceStatus(String newStatus) async {
    setState(() => _loading = true);
    final result = await ApiService.instance.updateDeliveryStatus(
      _order['id'] as String, newStatus);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update status. Please try again.')),
      );
      return;
    }
    setState(() => _order = result);
    if (newStatus == 'DELIVERED') Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final status = _order['status'] as String? ?? '';
    final fee = double.tryParse(_order['deliveryFee']?.toString() ?? '0') ?? 0.0;
    final dist = double.tryParse(_order['distanceKm']?.toString() ?? '0') ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: AppColors.bg_surface,
        foregroundColor: AppColors.text_primary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status chip
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.replaceAll('_', ' '),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border_subtle),
              ),
              child: Column(
                children: [
                  _infoRow('Recipient', _order['recipientName']?.toString() ?? ''),
                  _infoRow('Phone', _order['recipientPhone']?.toString() ?? ''),
                  _infoRow('Address', _order['deliveryAddress']?.toString() ?? ''),
                  _infoRow('Distance', '${dist.toStringAsFixed(2)} km'),
                  _infoRow('Delivery Fee', 'KES ${fee.toStringAsFixed(2)}'),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Action buttons
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (status == 'ASSIGNED')
              FilledButton.icon(
                icon: const Icon(AppIcons.shipping, size: 18),
                label: const Text('Pick Up'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _advanceStatus('IN_TRANSIT'),
              )
            else if (status == 'IN_TRANSIT')
              FilledButton.icon(
                icon: const Icon(AppIcons.checkCircle, size: 18),
                label: const Text('Mark as Delivered'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.status_success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _advanceStatus('DELIVERED'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.text_tertiary,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: AppColors.text_primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
