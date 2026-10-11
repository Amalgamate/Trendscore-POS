import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/tokens.dart';

class StorefrontOrdersView extends StatefulWidget {
  const StorefrontOrdersView({super.key});

  @override
  State<StorefrontOrdersView> createState() => _StorefrontOrdersViewState();
}

class _StorefrontOrdersViewState extends State<StorefrontOrdersView> {
  static const _filters = <(String, String?)>[
    ('Awaiting payment', 'AWAITING_PAYMENT'),
    ('Cancelled', 'CANCELLED'),
    ('Expired', 'EXPIRED'),
    ('All', null),
  ];

  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _orders = [];
  Timer? _refreshTimer;
  String? _status = 'AWAITING_PAYMENT';
  String? _error;
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _requestInProgress = false;
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.of(context)) unawaited(_load(reset: true));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_requestInProgress) {
      _refreshQueued = true;
      return;
    }
    _requestInProgress = true;
    final requestedStatus = _status;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = _orders.isEmpty;
        } else {
          _loadingMore = true;
        }
        _error = null;
      });
    }

    final requestedPage = reset ? 1 : _page + 1;
    final response = await ApiService.instance.getStorefrontOrders(
      status: requestedStatus,
      page: requestedPage,
    );
    _requestInProgress = false;
    final refreshQueued = _refreshQueued || requestedStatus != _status;
    _refreshQueued = false;
    if (!mounted) return;

    final data = response?['data'];
    final meta = response?['meta'];
    if (requestedStatus == _status) {
      setState(() {
        if (response == null || data is! List || meta is! Map) {
          _error =
              ApiService.instance.lastError ??
              'Could not load online orders. Try again.';
        } else {
          final fetched = data
              .whereType<Map>()
              .map((order) => Map<String, dynamic>.from(order))
              .toList(growable: false);
          if (reset) {
            _orders
              ..clear()
              ..addAll(fetched);
          } else {
            _orders.addAll(fetched);
          }
          _page = requestedPage;
          _total =
              int.tryParse(meta['total']?.toString() ?? '') ?? _orders.length;
        }
        _loading = false;
        _loadingMore = false;
      });
    }
    if (refreshQueued) unawaited(_load(reset: true));
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final orderNumber = order['orderNumber']?.toString() ?? 'this order';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel online order?'),
        content: Text(
          'Cancel $orderNumber? Its stock hold will be released immediately. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status_danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final cancelled = await ApiService.instance.cancelStorefrontOrder(
      order['id']?.toString() ?? '',
    );
    if (!mounted) return;
    if (cancelled == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.instance.lastError ??
                'Could not cancel the order. Refresh and try again.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order cancelled and reserved stock released.'),
      ),
    );
    await _load(reset: true);
  }

  Future<void> _setDeliveryFee(Map<String, dynamic> order) async {
    final orderNumber = order['orderNumber']?.toString() ?? 'this order';
    final controller = TextEditingController(
      text: order['deliveryFee'] == null ? '' : _money(order['deliveryFee']),
    );
    final formKey = GlobalKey<FormState>();
    String? feeText;
    try {
      feeText = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Set delivery fee · $orderNumber'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Delivery fee',
                prefixText: 'KES ',
                helperText: 'Enter 0 if delivery is free.',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                final amount = double.tryParse(text);
                if (amount == null ||
                    !amount.isFinite ||
                    amount < 0 ||
                    amount > 1000000000 ||
                    !RegExp(r'^\d{1,10}(?:\.\d{1,2})?$').hasMatch(text)) {
                  return 'Enter a valid amount with up to 2 decimal places.';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Send fee to customer'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (feeText == null || !mounted) return;

    final updated = await ApiService.instance.setStorefrontOrderDeliveryFee(
      order['id']?.toString() ?? '',
      double.parse(feeText),
    );
    if (!mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.instance.lastError ??
                'Could not set the fee. Refresh the order and try again.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delivery fee saved. The customer can review it now.'),
      ),
    );
    await _load(reset: true);
  }

  String _dateTime(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'Not recorded';
    final local = parsed.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date, $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 600;
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Online Orders',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColors.text_primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Orders are unpaid. Stock is held for 15 minutes; '
                        'set delivery fees within the hold. Do not prepare or '
                        'dispatch until payment is verified.',
                        style: TextStyle(
                          color: AppColors.text_secondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  );
                  final refresh = IconButton(
                    tooltip: 'Refresh online orders',
                    onPressed: _loading ? null : () => _load(reset: true),
                    icon: const Icon(Icons.refresh_rounded),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: title),
                            refresh,
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildFilters(),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: title),
                          refresh,
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFilters(),
                    ],
                  );
                },
              ),
            ),
            if (_error != null && _orders.isNotEmpty)
              MaterialBanner(
                content: Text(_error!),
                leading: const Icon(Icons.wifi_off_rounded),
                actions: [
                  TextButton(
                    onPressed: () => _load(reset: true),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(child: _buildOrders()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _filters) ...[
            ChoiceChip(
              label: Text(filter.$1),
              selected: _status == filter.$2,
              onSelected: (_) {
                if (_status == filter.$2) return;
                setState(() {
                  _status = filter.$2;
                  _orders.clear();
                  _page = 1;
                  _total = 0;
                  _loading = true;
                });
                unawaited(_load(reset: true));
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildOrders() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.text_tertiary,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inbox_outlined,
                size: 44,
                color: AppColors.text_tertiary,
              ),
              const SizedBox(height: 12),
              Text(
                _status == 'AWAITING_PAYMENT'
                    ? 'No unpaid online orders'
                    : 'No orders in this view',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'New storefront orders will appear here automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text_secondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _orders.length + (_orders.length < _total ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _orders.length) {
            return Center(
              child: TextButton(
                onPressed: _loadingMore ? null : () => _load(reset: false),
                child: Text(_loadingMore ? 'Loading…' : 'Load more orders'),
              ),
            );
          }
          return _orderTile(_orders[index]);
        },
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'UNKNOWN';
    final isAwaitingPayment = status == 'AWAITING_PAYMENT';
    final isDelivery = order['fulfillmentMethod'] == 'DELIVERY';
    final feeAccepted = order['deliveryFeeAcceptedAt'] != null;
    final feeQuoted = order['deliveryFee'] != null;
    final expiry = DateTime.tryParse(order['expiresAt']?.toString() ?? '');
    final holdIsActive = expiry != null && expiry.isAfter(DateTime.now());
    final items = order['items'] is List
        ? (order['items'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final expiryText = expiry == null
        ? ''
        : expiry.isAfter(DateTime.now())
        ? 'Hold expires ${_dateTime(expiry.toIso8601String())}'
        : 'Stock hold has expired';

    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.bg_surface,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Expanded(
              child: Text(
                order['orderNumber']?.toString() ?? 'Online order',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.text_primary,
                ),
              ),
            ),
            _statusChip(status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${order['customerName'] ?? 'Customer'} · '
            '${items.length} ${items.length == 1 ? 'item' : 'items'} · '
            'KES ${_money(order['total'])}\n'
            '${isAwaitingPayment ? expiryText : _dateTime(order['createdAt'])}',
            style: const TextStyle(
              color: AppColors.text_secondary,
              height: 1.5,
            ),
          ),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          _detailRow('Placed', _dateTime(order['createdAt'])),
          _detailRow(
            'Fulfillment',
            order['fulfillmentMethod'] == 'DELIVERY' ? 'Delivery' : 'Pickup',
          ),
          _detailRow('Customer', order['customerName']?.toString() ?? '—'),
          _detailRow('Phone', order['customerPhone']?.toString() ?? '—'),
          if ((order['customerEmail']?.toString() ?? '').isNotEmpty)
            _detailRow('Email', order['customerEmail'].toString()),
          if ((order['deliveryAddress']?.toString() ?? '').isNotEmpty)
            _detailRow('Address', order['deliveryAddress'].toString()),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item['quantity']} × ${item['productName']}'
                      '${(item['variantLabel']?.toString() ?? '').isNotEmpty ? ' (${item['variantLabel']})' : ''}',
                    ),
                  ),
                  Text('KES ${_money(item['lineTotal'])}'),
                ],
              ),
            ),
          const Divider(height: 20),
          _detailRow(
            'Merchandise subtotal',
            'KES ${_money(order['subtotal'])}',
          ),
          if (isDelivery)
            _detailRow(
              'Delivery fee',
              feeQuoted ? 'KES ${_money(order['deliveryFee'])}' : 'Not set',
            ),
          _detailRow('Order total', 'KES ${_money(order['total'])}'),
          if (isDelivery && feeQuoted)
            _detailRow(
              'Customer response',
              feeAccepted ? 'Fee accepted' : 'Waiting for customer',
            ),
          if (isAwaitingPayment) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isDelivery && !feeAccepted && holdIsActive)
                  OutlinedButton.icon(
                    onPressed: () => _setDeliveryFee(order),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(
                      feeQuoted ? 'Update delivery fee' : 'Set delivery fee',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _cancelOrder(order),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel and release stock'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.status_danger,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'AWAITING_PAYMENT' => ('Unpaid', const Color(0xFF9A5B00)),
      'CANCELLED' => ('Cancelled', AppColors.status_danger),
      'EXPIRED' => ('Expired', AppColors.text_tertiary),
      _ => (status, AppColors.text_tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.text_secondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text_primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _money(dynamic value) {
    final number = num.tryParse(value?.toString() ?? '') ?? 0;
    return number.toStringAsFixed(2);
  }
}
