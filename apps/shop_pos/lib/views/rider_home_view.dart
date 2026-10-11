import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../shared/icons.dart';
import 'rider_order_detail_view.dart';

class RiderHomeView extends StatefulWidget {
  const RiderHomeView({super.key, required this.state, required this.onLogout});

  final PosState state;
  final VoidCallback onLogout;

  @override
  State<RiderHomeView> createState() => _RiderHomeViewState();
}

class _RiderHomeViewState extends State<RiderHomeView>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _orders = [];
  String _pendingBalance = '0.00';
  List<Map<String, dynamic>> _ledgerEntries = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _refreshInProgress = false;
  bool _refreshQueued = false;
  String? _loadError;
  DateTime? _lastUpdatedAt;
  bool _sharingLocation = false;
  bool _updatingLocationConsent = false;
  bool _sendingLocation = false;
  bool _appIsForeground = true;
  bool? _locationServicesEnabled;
  bool? _connected;
  LocationPermission? _locationPermission;
  int? _batteryLevel;
  String? _locationError;
  DateTime? _lastLocationAt;
  Timer? _refreshTimer;
  StreamSubscription<Position>? _locationSubscription;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _appIsForeground) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsForeground = state == AppLifecycleState.resumed;
    if (_appIsForeground) {
      unawaited(_refresh());
      unawaited(_syncLocationTracking());
    } else if (!_canTrackInBackground) {
      unawaited(_stopLocationTracking());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    unawaited(_stopLocationTracking());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshInProgress) {
      _refreshQueued = true;
      return;
    }
    _refreshInProgress = true;
    final showInitialLoader = _lastUpdatedAt == null;
    if (mounted) {
      setState(() {
        _loading = showInitialLoader;
        _refreshing = !showInitialLoader;
      });
    }

    List<Map<String, dynamic>>? orders;
    Map<String, dynamic>? earnings;
    String? ordersError;
    String? earningsError;
    String? consentError;
    Map<String, dynamic>? consent;
    try {
      orders = await ApiService.instance.getRiderOrders();
      if (orders == null) ordersError = ApiService.instance.lastError;
      earnings = await ApiService.instance.getRiderEarnings();
      if (earnings == null) earningsError = ApiService.instance.lastError;
      consent = await ApiService.instance.getRiderLocationConsent();
      if (consent == null) consentError = ApiService.instance.lastError;
    } catch (e) {
      earningsError = 'Could not refresh rider data: $e';
    } finally {
      _refreshInProgress = false;
      final refreshAgain = _refreshQueued;
      _refreshQueued = false;
      if (mounted) {
        setState(() {
          if (orders != null) _orders = orders;
          if (earnings != null) {
            _pendingBalance = (earnings['pendingBalance'] as String?) ?? '0.00';
            _ledgerEntries =
                (earnings['entries'] as List?)?.cast<Map<String, dynamic>>() ??
                [];
          }
          if (consent != null) {
            _sharingLocation = consent['sharingEnabled'] == true;
            _lastLocationAt = DateTime.tryParse(
              consent['lastLocationAt']?.toString() ?? '',
            )?.toLocal();
          }
          _loadError = [
            ?ordersError,
            ?earningsError,
            ?consentError,
          ].whereType<String>().join(' ');
          if (orders != null || earnings != null) {
            _lastUpdatedAt = DateTime.now();
          }
          _loading = false;
          _refreshing = false;
        });
        if (_sharingLocation &&
            _orders.any(_isActiveDelivery) &&
            (_appIsForeground || _canTrackInBackground)) {
          unawaited(_syncLocationTracking());
        } else {
          unawaited(_stopLocationTracking());
        }
        if (refreshAgain) unawaited(_refresh());
      }
    }
  }

  bool _isActiveDelivery(Map<String, dynamic> order) =>
      order['status'] == 'ASSIGNED' || order['status'] == 'IN_TRANSIT';

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _canTrackInBackground =>
      _isAndroid && _locationPermission == LocationPermission.always;

  Future<void> _stopLocationTracking() async {
    final subscription = _locationSubscription;
    _locationSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _syncLocationTracking() async {
    if (!_sharingLocation || !_orders.any(_isActiveDelivery)) {
      await _stopLocationTracking();
      return;
    }
    if (!_appIsForeground && !_canTrackInBackground) return;
    if (_locationSubscription != null) return;
    try {
      _locationPermission = await Geolocator.checkPermission();
      if (_locationPermission == LocationPermission.denied ||
          _locationPermission == LocationPermission.deniedForever ||
          _locationPermission == LocationPermission.unableToDetermine) {
        if (mounted) {
          setState(() {
            _locationError =
                'Location permission is unavailable. Enable it in app settings to share.';
          });
        }
        return;
      }
      final settings = _isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 30,
              intervalDuration: const Duration(seconds: 30),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'ShopSmart delivery location',
                notificationText:
                    'Sharing your location with dispatch during an active delivery.',
                enableWakeLock: false,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 30,
            );
      _locationSubscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
            (position) => unawaited(_sendLocation(position)),
            onError: (Object error) {
              _locationSubscription?.cancel();
              _locationSubscription = null;
              if (mounted) {
                setState(
                  () => _locationError = 'Location updates stopped: $error',
                );
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() => _locationError = 'Could not start location updates: $e');
      }
    }
  }

  Future<void> _toggleLocationSharing(bool enabled) async {
    if (_updatingLocationConsent) return;
    if (enabled) {
      final hasActiveDelivery = _orders.any(_isActiveDelivery);
      if (!hasActiveDelivery) {
        setState(
          () => _locationError =
              'Location sharing is available only while you have an active delivery.',
        );
        return;
      }
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Share location during deliveries?'),
              content: const Text(
                'Your live location is shared with authorized shop dispatch staff only during active deliveries. Sharing stops when delivery work ends, and you can turn it off at any time. On Android, background sharing uses an ongoing notification and “Allow all the time” permission. On web and desktop, sharing works only while the app is open.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;

      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _locationServicesEnabled = false;
            _locationError =
                'Turn on device location services to share your location.';
          });
          return;
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        _locationPermission = permission;
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever ||
            permission == LocationPermission.unableToDetermine) {
          setState(() {
            _locationError = permission == LocationPermission.deniedForever
                ? 'Location access is blocked. Allow it in app settings to enable sharing.'
                : 'Location permission was not granted.';
          });
          return;
        }
      } catch (e) {
        setState(
          () => _locationError = 'Could not check location permission: $e',
        );
        return;
      }
    }

    setState(() {
      _updatingLocationConsent = true;
      _locationError = null;
    });
    final result = await ApiService.instance.setRiderLocationConsent(enabled);
    if (!mounted) return;
    setState(() {
      _updatingLocationConsent = false;
      if (result != null) {
        _sharingLocation = result['enabled'] == true;
        if (!enabled) _lastLocationAt = null;
        if (enabled && !_sharingLocation) {
          _locationError =
              'Location sharing was not enabled because there is no active delivery.';
        }
      } else {
        _locationError =
            ApiService.instance.lastError ??
            'Could not update location sharing. Try again.';
      }
    });
    if (_sharingLocation) {
      unawaited(_syncLocationTracking());
    } else {
      unawaited(_stopLocationTracking());
    }
  }

  Future<void> _sendLocation(Position position) async {
    if (_sendingLocation ||
        !_sharingLocation ||
        (!_appIsForeground && !_canTrackInBackground) ||
        !_orders.any(_isActiveDelivery)) {
      return;
    }
    _sendingLocation = true;
    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        if (mounted) {
          setState(() {
            _locationServicesEnabled = false;
            _locationError =
                'Device location services are off; location is not being shared.';
          });
        }
        return;
      }
      try {
        _batteryLevel = await _battery.batteryLevel;
      } catch (e) {
        debugPrint('Could not read rider device battery: $e');
      }
      try {
        final connectivity = await _connectivity.checkConnectivity();
        _connected = connectivity.any(
          (result) => result != ConnectivityResult.none,
        );
      } catch (e) {
        debugPrint('Could not read rider connectivity: $e');
      }
      if (!mounted ||
          !_sharingLocation ||
          (!_appIsForeground && !_canTrackInBackground)) {
        return;
      }
      _locationServicesEnabled = true;
      if (!(_connected ?? false)) {
        setState(
          () => _locationError = 'Offline; location will retry when connected.',
        );
        return;
      }
      var allUpdatesAccepted = true;
      for (final order in _orders.where(_isActiveDelivery)) {
        if (!_sharingLocation ||
            (!_appIsForeground && !_canTrackInBackground)) {
          break;
        }
        final accepted = await ApiService.instance.updateRiderLocation(
          orderId: order['id'] as String,
          latitude: double.parse(position.latitude.toStringAsFixed(5)),
          longitude: double.parse(position.longitude.toStringAsFixed(5)),
          accuracy: position.accuracy,
          recordedAt: position.timestamp,
        );
        if (!accepted) {
          _locationError =
              ApiService.instance.lastError ??
              'Could not send the latest location.';
          allUpdatesAccepted = false;
          break;
        }
      }
      if (mounted && allUpdatesAccepted && _sharingLocation) {
        setState(() {
          _lastLocationAt = position.timestamp.toLocal();
          _locationError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Could not get or send location: $e';
        });
      }
    } finally {
      _sendingLocation = false;
    }
  }

  String get _locationDeviceStatus {
    final parts = <String>[];
    if (_connected != null) parts.add(_connected! ? 'Online' : 'Offline');
    if (_batteryLevel != null) parts.add('Battery $_batteryLevel%');
    if (_locationPermission != null) {
      parts.add(
        _canTrackInBackground ? 'Background permission on' : 'Foreground only',
      );
    }
    return parts.join(' · ');
  }

  Future<void> _handleLogout() async {
    await _stopLocationTracking();
    if (_sharingLocation) {
      await ApiService.instance.setRiderLocationConsent(false);
    }
    if (mounted) widget.onLogout();
  }

  Color _statusColor(String status) => switch (status) {
    'PENDING' => const Color(0xFFF59E0B),
    'ASSIGNED' => const Color(0xFF3B82F6),
    'IN_TRANSIT' => AppColors.accent_primary,
    'DELIVERED' => AppColors.status_success,
    'FAILED' => AppColors.status_danger,
    _ => AppColors.text_tertiary,
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
            const Text(
              'Earnings History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Expanded(
              child: _ledgerEntries.isEmpty
                  ? const Center(child: Text('No earnings history yet.'))
                  : ListView.separated(
                      controller: scroll,
                      itemCount: _ledgerEntries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _ledgerEntries[i];
                        final isCredit = e['entryType'] == 'CREDIT';
                        final amt =
                            double.tryParse(e['amount']?.toString() ?? '0') ??
                            0.0;
                        return ListTile(
                          title: Text(
                            isCredit ? 'Delivery Earned' : 'Payout',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            e['createdAt']?.toString() ?? '',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            '${isCredit ? '+' : '-'} KES ${amt.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isCredit
                                  ? AppColors.status_success
                                  : AppColors.status_danger,
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
            const Text(
              'Rider Dashboard',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.text_primary,
              ),
            ),
            if (rider != null)
              Text(
                rider.fullName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text_tertiary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(AppIcons.lock, color: AppColors.text_tertiary),
            onPressed: _handleLogout,
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
                    _locationSharingCard(),
                    if (_refreshing)
                      const LinearProgressIndicator(minHeight: 2),
                    if (_loadError != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.status_danger.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              AppIcons.warning,
                              size: 18,
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
                              onPressed: _refreshing ? null : _refresh,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    if (_lastUpdatedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Last synced ${_lastUpdatedAt!.toLocal()} · auto-refresh 30s',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.text_tertiary,
                          ),
                        ),
                      ),
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
                          Row(
                            children: [
                              const Icon(
                                AppIcons.shipping,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Your Earnings',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'KES $_pendingBalance',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Available for payout',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _showLedgerSheet,
                            child: const Text('View History →'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Active orders
                    Row(
                      children: [
                        const Text(
                          'Active Deliveries',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text_primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_orders.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent_primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_orders.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (_orders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border_subtle),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              AppIcons.shipping,
                              size: 40,
                              color: AppColors.text_tertiary,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'No active deliveries',
                              style: TextStyle(
                                color: AppColors.text_tertiary,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Check back soon.',
                              style: TextStyle(
                                color: AppColors.text_tertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...(_orders.map((order) {
                        final status = order['status'] as String? ?? '';
                        final fee =
                            double.tryParse(
                              order['deliveryFee']?.toString() ?? '0',
                            ) ??
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
                              border: Border.all(
                                color: AppColors.border_subtle,
                              ),
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

  Widget _locationSharingCard() {
    final activeCount = _orders.where(_isActiveDelivery).length;
    final canShare = activeCount > 0;
    final lastLocationIsStale =
        _lastLocationAt != null &&
        DateTime.now().difference(_lastLocationAt!) >
            const Duration(minutes: 1);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Share location with dispatch',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              canShare
                  ? _sharingLocation
                        ? 'On for $activeCount active ${activeCount == 1 ? 'delivery' : 'deliveries'}'
                        : 'Only while this app is open during active deliveries'
                  : _sharingLocation
                  ? 'On; no location is collected without an active delivery'
                  : 'Available when you have an assigned delivery',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text_tertiary,
              ),
            ),
            value: _sharingLocation,
            onChanged:
                (!canShare && !_sharingLocation) || _updatingLocationConsent
                ? null
                : _toggleLocationSharing,
          ),
          if (_sharingLocation || _locationError != null) ...[
            const Divider(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _locationError == null
                      ? (_locationServicesEnabled == false
                            ? AppIcons.warning
                            : AppIcons.sync)
                      : AppIcons.warning,
                  size: 16,
                  color: _locationError == null
                      ? AppColors.accent_primary
                      : AppColors.status_danger,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _locationError ??
                        (_lastLocationAt == null
                            ? 'Waiting for the first location update'
                            : lastLocationIsStale
                            ? 'Location is stale · last shared ${_lastLocationAt!.toLocal()}'
                            : 'Last shared ${_lastLocationAt!.toLocal()}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: _locationError == null
                          ? AppColors.text_secondary
                          : AppColors.status_danger,
                    ),
                  ),
                ),
              ],
            ),
            if (_locationDeviceStatus.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                _locationDeviceStatus,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.text_tertiary,
                ),
              ),
            ],
            if (_sharingLocation && _isAndroid && !_canTrackInBackground) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                    if (mounted) await _refresh();
                  },
                  icon: const Icon(AppIcons.settings, size: 15),
                  label: const Text('Enable background location'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
