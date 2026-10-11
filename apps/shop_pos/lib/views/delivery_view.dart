import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
      length: isManager ? 4 : 1,
      child: Scaffold(
        backgroundColor: AppColors.bg_canvas,
        body: Column(
          children: [
            Material(
              color: AppColors.bg_surface,
              child: TabBar(
                labelColor: AppColors.accent_primary,
                unselectedLabelColor: AppColors.text_tertiary,
                indicatorColor: AppColors.accent_primary,
                tabs: [
                  const Tab(text: 'Orders'),
                  if (isManager) const Tab(text: 'Live map'),
                  if (isManager) const Tab(text: 'Riders'),
                  if (isManager) const Tab(text: 'Config'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _DeliveryOrdersTab(state: widget.state, isManager: isManager),
                  if (isManager) const _DeliveryMapTab(),
                  if (isManager) _RidersTab(state: widget.state),
                  if (isManager) _DeliveryConfigTab(state: widget.state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryMapTab extends StatefulWidget {
  const _DeliveryMapTab();

  @override
  State<_DeliveryMapTab> createState() => _DeliveryMapTabState();
}

class _DeliveryMapTabState extends State<_DeliveryMapTab> {
  static const _staleAfter = Duration(seconds: 90);
  static const _initialCenter = LatLng(-0.0236, 37.9062);

  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _requestInProgress = false;
  bool _refreshQueued = false;
  bool _mapReady = false;
  bool _hasFittedLocations = false;
  String? _selectedDeliveryId;
  String? _loadError;
  DateTime? _lastUpdatedAt;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.of(context)) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_requestInProgress) {
      _refreshQueued = true;
      return;
    }
    _requestInProgress = true;
    if (mounted) {
      setState(() {
        _loading = _lastUpdatedAt == null;
        _refreshing = _lastUpdatedAt != null;
      });
    }

    final deliveries = await ApiService.instance.getActiveDeliveryLocations();
    _requestInProgress = false;
    final refreshAgain = _refreshQueued;
    _refreshQueued = false;
    if (!mounted) return;

    setState(() {
      if (deliveries != null) {
        _deliveries = deliveries;
        _lastUpdatedAt = DateTime.now();
        if (_selectedDeliveryId != null &&
            !_deliveries.any((item) => item['id'] == _selectedDeliveryId)) {
          _selectedDeliveryId = null;
        }
      }
      _loadError = deliveries == null
          ? (ApiService.instance.lastError ??
                'Could not load live delivery locations.')
          : null;
      _loading = false;
      _refreshing = false;
    });

    if (deliveries != null) _fitInitialLocations();
    if (refreshAgain) unawaited(_load());
  }

  void _onMapReady() {
    _mapReady = true;
    _fitInitialLocations();
  }

  void _fitInitialLocations() {
    if (!_mapReady || _hasFittedLocations) return;
    final points = _deliveries
        .map(_positionFor)
        .whereType<LatLng>()
        .toList(growable: false);
    if (points.isEmpty) return;
    _hasFittedLocations = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.single, 14);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    });
  }

  LatLng? _positionFor(Map<String, dynamic> delivery) {
    final location = delivery['location'];
    if (location is! Map) return null;
    final latitude = num.tryParse(location['latitude']?.toString() ?? '');
    final longitude = num.tryParse(location['longitude']?.toString() ?? '');
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  DateTime? _recordedAt(Map<String, dynamic> delivery) {
    final location = delivery['location'];
    if (location is! Map) return null;
    return DateTime.tryParse(
      location['recordedAt']?.toString() ?? '',
    )?.toLocal();
  }

  bool _isStale(Map<String, dynamic> delivery) {
    final recordedAt = _recordedAt(delivery);
    return recordedAt == null ||
        DateTime.now().difference(recordedAt) > _staleAfter;
  }

  String _ageLabel(DateTime recordedAt) {
    final seconds = math.max(
      0,
      DateTime.now().difference(recordedAt).inSeconds,
    );
    if (seconds < 60) return '${seconds}s ago';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ago';
    return '${minutes ~/ 60}h ${minutes % 60}m ago';
  }

  void _selectDelivery(Map<String, dynamic> delivery) {
    setState(() => _selectedDeliveryId = delivery['id']?.toString());
    final position = _positionFor(delivery);
    if (position != null && _mapReady) _mapController.move(position, 14);
  }

  void _recenterMap() {
    final points = _deliveries
        .map(_positionFor)
        .whereType<LatLng>()
        .toList(growable: false);
    if (points.isEmpty) {
      _mapController.move(_initialCenter, 6);
    } else if (points.length == 1) {
      _mapController.move(points.single, 14);
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
      );
    }
  }

  Color _markerColor(Map<String, dynamic> delivery) {
    if (_isStale(delivery)) return AppColors.status_warning;
    return delivery['status'] == 'IN_TRANSIT'
        ? AppColors.accent_primary
        : AppColors.status_info;
  }

  Widget _mapPanel() {
    final palette = context.palette;
    final hasCoordinates = _deliveries.any(
      (delivery) => _positionFor(delivery) != null,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 6,
              onMapReady: _onMapReady,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ke.trendscore.retailpos.shop_pos',
              ),
              MarkerLayer(
                markers: [
                  for (final delivery in _deliveries)
                    if (_positionFor(delivery) case final point?)
                      Marker(
                        point: point,
                        width: 48,
                        height: 52,
                        child: Semantics(
                          button: true,
                          label:
                              '${delivery['recipientName'] ?? 'Delivery'}, ${delivery['status'] ?? 'Active'}',
                          child: GestureDetector(
                            onTap: () => _selectDelivery(delivery),
                            child: AnimatedContainer(
                              duration: AppMotion.base,
                              decoration: BoxDecoration(
                                color: _markerColor(delivery),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: palette.bgSurface,
                                  width:
                                      _selectedDeliveryId ==
                                          delivery['id']?.toString()
                                      ? 4
                                      : 2,
                                ),
                              ),
                              child: Icon(
                                Icons.delivery_dining,
                                color: palette.textInverse,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
              SimpleAttributionWidget(
                source: const Text('© OpenStreetMap contributors'),
                backgroundColor: palette.bgSurface.withValues(alpha: 0.92),
              ),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: palette.bgSurface,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: 'Show all rider locations',
                onPressed: _mapReady ? _recenterMap : null,
                icon: const Icon(Icons.center_focus_strong),
              ),
            ),
          ),
          if (!hasCoordinates)
            Positioned(
              top: 12,
              left: 12,
              right: 64,
              child: Material(
                color: palette.bgSurface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Text(
                    _lastUpdatedAt == null && _loadError != null
                        ? 'Live delivery data is unavailable. Retry to load locations.'
                        : _deliveries.isEmpty
                        ? 'No active deliveries to show.'
                        : 'No shared rider locations yet. Active deliveries remain listed below.',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deliveryList() {
    final palette = context.palette;
    if (_loading && _deliveries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lastUpdatedAt == null && _loadError != null) {
      final palette = context.palette;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, color: palette.statusWarning),
              const SizedBox(height: 8),
              Text(
                'Delivery locations could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textPrimary),
              ),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_deliveries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 36, color: palette.textTertiary),
              const SizedBox(height: 10),
              Text(
                'No active deliveries',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Assigned and in-transit deliveries will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textTertiary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _deliveries.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: palette.borderSubtle,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final delivery = _deliveries[index];
        final status = delivery['status']?.toString() ?? 'ASSIGNED';
        final sharingEnabled = delivery['sharingEnabled'] == true;
        final recordedAt = _recordedAt(delivery);
        final hasPosition = _positionFor(delivery) != null;
        final stale = sharingEnabled && (!hasPosition || _isStale(delivery));
        final statusColor = status == 'IN_TRANSIT'
            ? AppColors.accent_primary
            : AppColors.status_info;
        final locationLabel = !sharingEnabled
            ? 'Location sharing off'
            : !hasPosition
            ? 'No location yet · rider may be offline'
            : stale
            ? 'No recent location · rider may be offline'
            : 'Location ${_ageLabel(recordedAt!)}';

        return ListTile(
          selected: _selectedDeliveryId == delivery['id']?.toString(),
          selectedTileColor: palette.accentLight,
          onTap: () => _selectDelivery(delivery),
          leading: Icon(
            stale ? Icons.location_off_outlined : Icons.location_on,
            color: stale ? palette.statusWarning : statusColor,
          ),
          title: Text(
            delivery['recipientName']?.toString() ?? 'Delivery',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${delivery['rider']?['fullName'] ?? 'Unassigned rider'} · ${status == 'IN_TRANSIT' ? 'In transit' : 'Assigned'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary),
                ),
                if (delivery['deliveryAddress'] case final String address)
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textTertiary, fontSize: 12),
                  ),
                const SizedBox(height: 3),
                Text(
                  locationLabel,
                  style: TextStyle(
                    color: stale ? palette.statusWarning : palette.textTertiary,
                    fontSize: 12,
                    fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: palette.textTertiary),
        );
      },
    );
  }

  Widget _summary() {
    final palette = context.palette;
    final sharing = _deliveries
        .where((delivery) => delivery['sharingEnabled'] == true)
        .length;
    final attention = _deliveries.where((delivery) {
      return delivery['sharingEnabled'] == true &&
          (_positionFor(delivery) == null || _isStale(delivery));
    }).length;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _summaryItem(
          Icons.local_shipping_outlined,
          '${_deliveries.length} active',
          palette.textSecondary,
        ),
        _summaryItem(
          Icons.location_on_outlined,
          '$sharing sharing',
          palette.statusSuccess,
        ),
        _summaryItem(
          Icons.location_off_outlined,
          '$attention need attention',
          attention > 0 ? palette.statusWarning : palette.textTertiary,
        ),
        if (_refreshing)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_lastUpdatedAt != null)
          Text(
            'Updated ${_ageLabel(_lastUpdatedAt!)}',
            style: TextStyle(color: palette.textTertiary, fontSize: 12),
          ),
      ],
    );
  }

  Widget _summaryItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _errorBanner() {
    final palette = context.palette;
    return Material(
      color: palette.statusWarningLight,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.wifi_off, size: 18, color: palette.statusWarning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _loadError!,
                style: TextStyle(color: palette.textPrimary, fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Retry loading locations',
              onPressed: _refreshing ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Live delivery map',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh live locations',
                  onPressed: _refreshing ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _summary(),
            if (_loadError != null) ...[
              const SizedBox(height: 10),
              _errorBanner(),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return Row(
                      children: [
                        Expanded(child: _mapPanel()),
                        const SizedBox(width: 16),
                        SizedBox(width: 380, child: _deliveryList()),
                      ],
                    );
                  }
                  final mapHeight = (constraints.maxHeight * 0.44)
                      .clamp(170.0, 360.0)
                      .toDouble();
                  return Column(
                    children: [
                      SizedBox(height: mapHeight, child: _mapPanel()),
                      const SizedBox(height: 8),
                      Expanded(child: _deliveryList()),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Location shown only while rider consent is active · Map © OpenStreetMap contributors',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textTertiary, fontSize: 11),
            ),
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
  const _DeliveryOrdersTab({required this.state, required this.isManager});

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
  bool _refreshing = false;
  bool _loadInProgress = false;
  bool _loadAgain = false;
  int _loadGeneration = 0;
  String? _loadError;
  DateTime? _lastUpdatedAt;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.isManager) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && TickerMode.of(context)) _load();
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadInProgress) {
      _loadAgain = true;
      return;
    }
    _loadInProgress = true;
    final generation = _loadGeneration;
    final requestedFilter = _filter;
    final showInitialLoader = _orders.isEmpty && _lastUpdatedAt == null;
    if (mounted) {
      setState(() {
        _loading = showInitialLoader;
        _refreshing = !showInitialLoader;
      });
    }

    List<Map<String, dynamic>>? loadedOrders;
    List<Map<String, dynamic>>? loadedRiders;
    String? error;
    try {
      final ordersEnvelope = await ApiService.instance.getDeliveryOrders(
        status: requestedFilter,
      );
      if (ordersEnvelope == null) {
        error =
            ApiService.instance.lastError ?? 'Could not load delivery orders.';
      } else {
        final rawOrders = ordersEnvelope['data'];
        if (rawOrders is! List) {
          error = 'The shop API returned an invalid delivery order list.';
        } else {
          loadedOrders = rawOrders.cast<Map<String, dynamic>>();
          if (widget.isManager) {
            loadedRiders = await ApiService.instance.getRiders();
            if (loadedRiders == null) {
              error = ApiService.instance.lastError ?? 'Could not load riders.';
            }
          }
        }
      }
    } catch (e) {
      error = 'Could not refresh delivery data: $e';
    } finally {
      _loadInProgress = false;
      final shouldReload = _loadAgain || generation != _loadGeneration;
      _loadAgain = false;
      if (mounted) {
        setState(() {
          if (generation == _loadGeneration && loadedOrders != null) {
            _orders = loadedOrders;
            _lastUpdatedAt = DateTime.now();
          }
          if (generation == _loadGeneration) {
            if (loadedRiders != null) _riders = loadedRiders;
            _loadError = error;
            _loading = false;
            _refreshing = false;
          }
        });
        if (shouldReload) unawaited(_load());
      }
    }
  }

  void _setFilter(String? status) {
    if (_filter == status) return;
    _loadGeneration++;
    setState(() {
      _filter = status;
      _orders = [];
      _lastUpdatedAt = null;
      _loading = true;
    });
    _load();
  }

  Color _statusColor(String status) => switch (status) {
    'PENDING' => const Color(0xFFF59E0B),
    'ASSIGNED' => const Color(0xFF3B82F6),
    'IN_TRANSIT' => AppColors.accent_primary,
    'DELIVERED' => AppColors.status_success,
    'FAILED' => AppColors.status_danger,
    'CANCELLED' => AppColors.text_tertiary,
    _ => AppColors.text_tertiary,
  };

  DateTime? _orderTime(Map<String, dynamic> order, String field) {
    final value = order[field]?.toString();
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  String _formatTime(DateTime dateTime) {
    final date = dateTime.toLocal();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} $hour:$minute $period';
  }

  String _elapsedLabel(DateTime start) {
    final elapsed = DateTime.now().difference(start);
    final minutes = math.max(0, elapsed.inMinutes);
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours < 24) return '${hours}h ${remainingMinutes}m';
    return '${hours ~/ 24}d ${hours % 24}h';
  }

  Widget _orderTimeline(Map<String, dynamic> order) {
    const milestones = [
      ('Created', 'createdAt'),
      ('Assigned', 'assignedAt'),
      ('Picked up', 'pickedUpAt'),
      ('Delivered', 'deliveredAt'),
    ];
    final labels = <String>[];
    for (final (label, field) in milestones) {
      final time = _orderTime(order, field);
      if (time != null) labels.add('$label ${_formatTime(time)}');
    }
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 5,
        children: [
          for (final label in labels)
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.text_tertiary,
              ),
            ),
        ],
      ),
    );
  }

  String? _activeAge(Map<String, dynamic> order, String status) {
    final (label, field) = switch (status) {
      'PENDING' => ('Waiting for assignment', 'createdAt'),
      'ASSIGNED' => ('Assigned', 'assignedAt'),
      'IN_TRANSIT' => ('In transit', 'pickedUpAt'),
      'FAILED' => ('Failed', 'updatedAt'),
      _ => ('', ''),
    };
    if (field.isEmpty) return null;
    final start = _orderTime(order, field);
    return start == null ? null : '$label · ${_elapsedLabel(start)}';
  }

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
              final base =
                  double.tryParse(config!['baseFee']?.toString() ?? '0') ?? 0.0;
              final rate =
                  double.tryParse(
                    config!['distanceTopupRate']?.toString() ?? '0',
                  ) ??
                  0.0;
              setDialogState(() => previewFee = base + rate * dist);
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.bg_surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(AppIcons.shipping, color: AppColors.accent_primary),
                SizedBox(width: 10),
                Text(
                  'New Delivery Order',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(400.0, MediaQuery.sizeOf(context).width - 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogField(nameCtrl, 'Recipient Name *', AppIcons.person),
                    const SizedBox(height: 12),
                    _dialogField(
                      phoneCtrl,
                      'Recipient Phone *',
                      AppIcons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    _dialogField(
                      addressCtrl,
                      'Delivery Address *',
                      AppIcons.storefront,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: distCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => recalcFee(),
                      decoration: InputDecoration(
                        labelText: 'Distance (km) *',
                        prefixIcon: const Icon(AppIcons.arrowForward, size: 20),
                        filled: true,
                        fillColor: AppColors.bg_canvas,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.border_subtle,
                          ),
                        ),
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
                            const Text(
                              'Estimated Fee',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.accent_primary,
                              ),
                            ),
                            Text(
                              'KES ${previewFee!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent_primary,
                              ),
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
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.text_secondary),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('Create Order'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent_primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();
                  final address = addressCtrl.text.trim();
                  final dist = double.tryParse(distCtrl.text.trim()) ?? 0.0;

                  if (name.isEmpty ||
                      phone.isEmpty ||
                      address.isEmpty ||
                      dist <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill in all required fields.'),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await ApiService.instance.createDeliveryOrder({
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
                        backgroundColor: AppColors.status_success,
                      ),
                    );
                    _load();
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not create order. Please try again.',
                        ),
                        backgroundColor: AppColors.status_danger,
                      ),
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
        if ((status == 'PENDING' || status == 'ASSIGNED') && _riders.isNotEmpty)
          Expanded(
            child: DropdownButton<String>(
              value: _riders.any((r) => r['id'] == currentRiderId)
                  ? currentRiderId
                  : null,
              hint: Text(
                status == 'ASSIGNED' ? 'Change Rider' : 'Assign Rider',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text_tertiary,
                ),
              ),
              isExpanded: true,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text_primary,
              ),
              underline: const SizedBox.shrink(),
              items: _riders
                  .map(
                    (r) => DropdownMenuItem<String>(
                      value: r['id'] as String?,
                      child: Text(
                        r['fullName']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (riderId) async {
                if (riderId == null || riderId == currentRiderId) return;
                final result = await ApiService.instance.assignRider(
                  orderId,
                  riderId,
                );
                if (!mounted) return;
                if (result != null) {
                  _load();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ApiService.instance.lastError ??
                            'Could not assign rider.',
                      ),
                    ),
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
    const statuses = [
      'PENDING',
      'ASSIGNED',
      'IN_TRANSIT',
      'DELIVERED',
      'FAILED',
      'CANCELLED',
    ];

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => _setFilter(null),
                    selectedColor: AppColors.accent_light,
                    checkmarkColor: AppColors.accent_primary,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _filter == null
                          ? AppColors.accent_primary
                          : AppColors.text_secondary,
                    ),
                  ),
                  for (final s in statuses)
                    FilterChip(
                      label: Text(s.replaceAll('_', ' ')),
                      selected: _filter == s,
                      onSelected: (_) => _setFilter(s),
                      selectedColor: AppColors.accent_light,
                      checkmarkColor: AppColors.accent_primary,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: _filter == s
                            ? AppColors.accent_primary
                            : AppColors.text_secondary,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (widget.isManager)
              Container(
                color: AppColors.bg_surface,
                padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
                child: Row(
                  children: [
                    const Icon(
                      AppIcons.sync,
                      size: 15,
                      color: AppColors.text_tertiary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _lastUpdatedAt == null
                            ? 'Updates automatically every 30 seconds'
                            : 'Updated ${_formatTime(_lastUpdatedAt!)} · auto-refresh 30s',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text_tertiary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh delivery orders',
                      visualDensity: VisualDensity.compact,
                      onPressed: _refreshing ? null : _load,
                      icon: const Icon(AppIcons.sync, size: 18),
                    ),
                  ],
                ),
              ),
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            if (_loadError != null)
              Container(
                width: double.infinity,
                color: AppColors.status_danger.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      AppIcons.warning,
                      size: 16,
                      color: AppColors.status_danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.status_danger,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _refreshing ? null : _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // Order list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _orders.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 260,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _loadError == null
                                      ? AppIcons.shipping
                                      : AppIcons.warning,
                                  size: 48,
                                  color: AppColors.text_tertiary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _loadError != null
                                      ? 'Some delivery data could not be loaded. Retry above.'
                                      : _filter == null
                                      ? 'No delivery orders yet.'
                                      : 'No ${_filter!.replaceAll('_', ' ')} orders.',
                                  style: const TextStyle(
                                    color: AppColors.text_tertiary,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: _orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final order = _orders[i];
                        final status = order['status'] as String? ?? '';
                        final fee =
                            double.tryParse(
                              order['deliveryFee']?.toString() ?? '0',
                            ) ??
                            0.0;
                        final riderName =
                            (order['rider']
                                    as Map<String, dynamic>?)?['fullName']
                                ?.toString() ??
                            order['riderName']?.toString();
                        final activeAge = _activeAge(order, status);

                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(
                              color: AppColors.border_subtle,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(
                                          status,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.replaceAll('_', ' '),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _statusColor(status),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'KES ${fee.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.accent_primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  order['recipientName']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  order['recipientPhone']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.text_tertiary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  order['deliveryAddress']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.text_secondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (activeAge != null) ...[
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      Icon(
                                        status == 'FAILED'
                                            ? AppIcons.warning
                                            : AppIcons.lockClock,
                                        size: 14,
                                        color: status == 'FAILED'
                                            ? AppColors.status_danger
                                            : AppColors.text_secondary,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        activeAge,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: status == 'FAILED'
                                              ? AppColors.status_danger
                                              : AppColors.text_secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (riderName != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rider: $riderName',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.text_tertiary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                _orderTimeline(order),
                                if (status == 'FAILED' &&
                                    (order['failureReason']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.status_danger.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Failure reason: ${order['failureReason']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.status_danger,
                                      ),
                                    ),
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
          borderSide: const BorderSide(color: AppColors.border_subtle),
        ),
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
      text: rider['phone']?.toString() ?? '',
    );
    final riderId = rider['id'] as String? ?? '';
    final riderName = rider['fullName']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(AppIcons.wallet, color: AppColors.accent_primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rider Payout',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    riderName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.text_secondary,
                    ),
                  ),
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
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount (KES) *',
                  prefixIcon: const Icon(AppIcons.money, size: 20),
                  filled: true,
                  fillColor: AppColors.bg_canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.text_secondary),
            ),
          ),
          FilledButton.icon(
            icon: const Icon(AppIcons.send, size: 16),
            label: const Text('Send Payout'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent_primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              final phone = phoneCtrl.text.trim();
              if (amount <= 0 || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid amount and phone.'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              final ok = await ApiService.instance.initiateRiderPayout(
                riderId,
                amount,
                phone,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Payout of KES ${amount.toStringAsFixed(2)} initiated for $riderName.'
                        : 'Payout failed. Please try again.',
                  ),
                  backgroundColor: ok
                      ? AppColors.status_success
                      : AppColors.status_danger,
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
                  Icon(
                    AppIcons.person,
                    size: 48,
                    color: AppColors.text_tertiary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No riders registered.',
                    style: TextStyle(
                      color: AppColors.text_tertiary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _riders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final rider = _riders[i];
                final balance =
                    double.tryParse(
                      rider['pendingBalance']?.toString() ?? '0',
                    ) ??
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
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.accent_light,
                      child: Text(
                        (rider['fullName']?.toString() ?? 'R')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.accent_primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      rider['fullName']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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
                            color: AppColors.accent_primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _showPayoutDialog(rider),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent_primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Pay Out',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
      _baseFeeCtrl.text = config?['baseFee']?.toString() ?? '0';
      _topupCtrl.text = config?['distanceTopupRate']?.toString() ?? '0';
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
        content: Text(
          ok
              ? 'Delivery config saved.'
              : 'Could not save config. Please try again.',
        ),
        backgroundColor: ok
            ? AppColors.status_success
            : AppColors.status_danger,
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
                const Text(
                  'Fee Structure',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.text_primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Fee = Base Fee + (Distance × Per-km Rate)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text_tertiary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _baseFeeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Base Fee (KES)',
                    prefixIcon: const Icon(AppIcons.money, size: 20),
                    filled: true,
                    fillColor: AppColors.bg_canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.border_subtle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _topupCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Per-km Rate (KES / km)',
                    prefixIcon: const Icon(AppIcons.arrowForward, size: 20),
                    filled: true,
                    fillColor: AppColors.bg_canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.border_subtle,
                      ),
                    ),
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
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(AppIcons.save, size: 18),
                    label: const Text('Save Configuration'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent_primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
