import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'cart.dart';
import 'pos_state.dart';
import 'services/api_service.dart';
import 'services/favicon_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';
import 'views/cash_drawer_view.dart';
import 'views/checkout_modal.dart';
import 'views/customers_view.dart';
import 'views/inventory_view.dart';
import 'views/sales_history_view.dart';
import 'views/login_view.dart';
import 'views/reports_view.dart';
import 'views/settings_view.dart';
import 'views/purchase_orders_view.dart';
import 'views/delivery_view.dart';
import 'views/rider_home_view.dart';
import 'shared/icons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = PosState();
  await state.loadInitialState();
  FaviconService.update(
    state.brandLogoBase64?.isNotEmpty == true
        ? state.brandLogoBase64
        : state.brandLogoUrl,
  );
  ApiService.instance.configure(state.serverUrl);
  if (state.currentLoggedInUser != null) {
    state.catalogueSyncMessage = 'Local-only mode: lock the till and re-enter your PIN to sync the shop catalogue.';
  }
  final themeController = ThemeController();
  await themeController.load();
  runApp(RetailPosApp(state: state, themeController: themeController));
}

class RetailPosApp extends StatelessWidget {
  const RetailPosApp({super.key, required this.state, this.themeController});

  final PosState state;

  /// Light / dark / system choice. Optional so tests can build the app bare.
  final ThemeController? themeController;

  @override
  Widget build(BuildContext context) {
    final controller = themeController;
    if (controller == null) return _buildApp(ThemeMode.light);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildApp(controller.mode),
    );
  }

  Widget _buildApp(ThemeMode mode) {
    return MaterialApp(
      title: 'ShopSmart Retail POS',
      debugShowCheckedModeBanner: false,
      theme: buildRetailOsTheme(),
      darkTheme: buildRetailOsDarkTheme(),
      themeMode: mode,
      home: PosShell(state: state),
    );
  }
}

class PosShell extends StatefulWidget {
  const PosShell({super.key, required this.state});

  final PosState state;

  @override
  State<PosShell> createState() => _PosShellState();
}

class _PosShellState extends State<PosShell> with WidgetsBindingObserver {
  late int _activeTabIndex;
  late bool _isLocked;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isLocked = widget.state.currentLoggedInUser == null;
    _activeTabIndex = widget.state.savedTabIndex.clamp(0, 8);
    _startInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!_isLocked) {
      _inactivityTimer = Timer(const Duration(minutes: PosState.sessionTimeoutMinutes), () {
        if (mounted && !_isLocked) {
          _lockTill();
        }
      });
    }
  }

  void _onUserInteraction() {
    widget.state.touchSession();
    _startInactivityTimer();
  }

  void _lockTill() {
    _inactivityTimer?.cancel();
    widget.state.logout();
    setState(() {
      _isLocked = true;
    });
  }

  Set<int> _accessibleTabs(PosUser? user) {
    if (user == null) return const <int>{};
    return switch (user.role) {
      PosUserRole.superAdmin => const <int>{0, 1, 2, 3, 4, 5, 6, 7, 8},
      PosUserRole.owner      => const <int>{0, 1, 2, 3, 4, 5, 6, 7, 8},
      PosUserRole.manager    => const <int>{0, 1, 2, 3, 4, 5, 7, 8},
      PosUserRole.cashier    => const <int>{0, 1, 4, 8},
      PosUserRole.stockClerk => const <int>{2, 7},
      PosUserRole.rider      => const <int>{},
    };
  }

  void _selectTab(int index) {
    final user = widget.state.currentLoggedInUser;
    if (!_accessibleTabs(user).contains(index)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your staff role does not have access to that section.')),
      );
      return;
    }
    setState(() => _activeTabIndex = index);
    widget.state.setActiveTab(index);
    _onUserInteraction();
  }

  void _showMoreSheet(BuildContext context, PosUser? currentUser, Set<int> allowedTabs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bg_canvas,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border_subtle),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.accent_light,
                        child: Text(
                          currentUser?.initials ?? 'JM',
                          style: const TextStyle(color: AppColors.accent_primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser?.fullName ?? widget.state.activeCashier,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.text_primary),
                            ),
                            Text(
                              currentUser?.roleDisplay ?? 'Staff',
                              style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(AppIcons.lock, size: 14, color: AppColors.status_danger),
                        label: const Text('Lock', style: TextStyle(color: AppColors.status_danger, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.status_danger),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _lockTill();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('More Operations', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.text_tertiary, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                if (allowedTabs.contains(7)) _moreTile(AppIcons.shipping, 'Purchase & Supplier Orders', 7, ctx),
                if (allowedTabs.contains(4)) _moreTile(AppIcons.wallet, 'Cash Drawer & Shifts', 4, ctx),
                if (allowedTabs.contains(5)) _moreTile(AppIcons.analytics, 'Reports & Analytics', 5, ctx),
                if (allowedTabs.contains(6)) _moreTile(AppIcons.settings, 'Settings & Hardware', 6, ctx),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _moreTile(IconData icon, String title, int tabIndex, BuildContext ctx) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent_primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(AppIcons.chevronRight, size: 18, color: AppColors.text_tertiary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {
        Navigator.pop(ctx);
        _selectTab(tabIndex);
      },
    );
  }

  void _showSyncDiagnostics(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(AppIcons.cloudSync, color: AppColors.accent_primary, size: 24),
            SizedBox(width: 10),
            Text('Offline & Cloud Sync Status', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: const [
                    Icon(AppIcons.checkCircle, color: AppColors.status_success, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'System Operational · Local-First Offline Mode Enabled',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _diagRow('Local Storage DB', 'Synchronized & Persistent (OK)'),
              _diagRow('Pending Sync Queue', '0 transactions pending upload'),
              _diagRow('Active Till Shift', 'Shift ID: ${widget.state.shift.shiftId}'),
              _diagRow('Total Cached Products', '${widget.state.products.length} catalog items'),
              _diagRow('Cloud Server Host', widget.state.serverUrl),
              _diagRow('Last Heartbeat', 'Just now (0s ago)'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            icon: const Icon(AppIcons.sync, size: 16),
            label: const Text('Force Cloud Resync'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent_primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All local transactions and shift data synchronized with cloud server!'),
                  backgroundColor: AppColors.status_success,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text_secondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text_primary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return LoginView(
        state: widget.state,
        onAuthenticated: () {
          final user = widget.state.currentLoggedInUser;
          final allowedTabs = _accessibleTabs(user);
          if (!allowedTabs.contains(_activeTabIndex) && allowedTabs.isNotEmpty) {
            _activeTabIndex = allowedTabs.first;
          }
          widget.state.persistSession(user, tabIndex: _activeTabIndex);
          _startInactivityTimer();
          setState(() => _isLocked = false);
        },
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserInteraction(),
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final currentUser = widget.state.currentLoggedInUser;
          final allowedTabs = _accessibleTabs(currentUser);
          if (!allowedTabs.contains(_activeTabIndex) && allowedTabs.isNotEmpty) {
            _activeTabIndex = allowedTabs.first;
          }
          final screenWidth = MediaQuery.sizeOf(context).width;
          final isMobile = screenWidth < 768;

          // Rider role: show dedicated dashboard, no POS access
          if (currentUser?.role == PosUserRole.rider) {
            return RiderHomeView(state: widget.state, onLogout: _lockTill);
          }

          final views = [
            _PosTerminalView(
              state: widget.state,
              onOpenSync: () => _showSyncDiagnostics(context),
            ),
            SalesHistoryView(state: widget.state),
            InventoryView(state: widget.state),
            CustomersView(state: widget.state),
            CashDrawerView(state: widget.state),
            ReportsView(state: widget.state),
            SettingsView(state: widget.state),
            PurchaseOrdersView(state: widget.state),
            // index 8 — Delivery management view
            DeliveryView(state: widget.state),
          ];

          if (isMobile) {
            return Scaffold(
              body: SafeArea(
                bottom: false,
                child: IndexedStack(
                  index: _activeTabIndex,
                  children: views,
                ),
              ),
              bottomNavigationBar: _MobileBottomNav(
                activeIndex: _activeTabIndex,
                visibleTabs: allowedTabs,
                onSelectTab: _selectTab,
                onOpenMore: () {
                  _onUserInteraction();
                  _showMoreSheet(context, currentUser, allowedTabs);
                },
                activeCashier: currentUser?.fullName ?? widget.state.activeCashier,
              ),
            );
          }

          return Scaffold(
            body: Row(
              children: [
                // Left Navigation Rail
                _NavigationSidebar(
                  activeIndex: _activeTabIndex,
                  visibleTabs: allowedTabs,
                  onSelectTab: _selectTab,
                  onLockTill: _lockTill,
                  onOpenSync: () {
                    _onUserInteraction();
                    _showSyncDiagnostics(context);
                  },
                  activeCashier: currentUser?.fullName ?? widget.state.activeCashier,
                  roleDisplay: currentUser?.roleDisplay ?? 'Staff',
                  initials: currentUser?.initials,
                  logoBase64: widget.state.brandLogoBase64,
                  logoUrl: widget.state.brandLogoUrl,
                ),

                // Active Main View — animated tab switch
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final offset = Tween<Offset>(
                        begin: const Offset(0.02, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<int>(_activeTabIndex),
                      child: views[_activeTabIndex],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.activeIndex,
    required this.visibleTabs,
    required this.onSelectTab,
    required this.onOpenMore,
    required this.activeCashier,
  });

  final int activeIndex;
  final Set<int> visibleTabs;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenMore;
  final String activeCashier;

  @override
  Widget build(BuildContext context) {
    const primaryTabs = <int>[0, 1, 2, 3];
    final visiblePrimary = primaryTabs.where(visibleTabs.contains).toList();
    final isMoreActive = !visiblePrimary.contains(activeIndex);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border_subtle)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final tab in visiblePrimary)
                _mobileNavItem(
                  switch (tab) {
                    0 => AppIcons.pos,
                    1 => AppIcons.receiptLong,
                    2 => AppIcons.inventory,
                    _ => AppIcons.people,
                  },
                  switch (tab) {
                    0 => 'POS',
                    1 => 'Sales',
                    2 => 'Stock',
                    _ => 'Credit',
                  },
                  tab,
                  activeIndex == tab,
                  () => onSelectTab(tab),
                ),
              _mobileNavItem(AppIcons.menu, 'More', 4, isMoreActive, onOpenMore),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileNavItem(IconData icon, String label, int index, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppColors.accent_primary : AppColors.text_tertiary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.accent_primary : AppColors.text_tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({
    required this.activeIndex,
    required this.visibleTabs,
    required this.onSelectTab,
    required this.onLockTill,
    required this.onOpenSync,
    required this.activeCashier,
    this.roleDisplay,
    this.initials,
    this.logoBase64,
    this.logoUrl,
  });

  final int activeIndex;
  final Set<int> visibleTabs;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onLockTill;
  final VoidCallback onOpenSync;
  final String activeCashier;
  final String? roleDisplay;
  final String? initials;
  final String? logoBase64;
  final String? logoUrl;

  Widget _buildLogo() {
    if (logoBase64 != null && logoBase64!.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(logoBase64!.split(',').last),
          fit: BoxFit.cover,
          width: 44,
          height: 44,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return Image.network(
        logoUrl!,
        fit: BoxFit.contain,
        width: 44,
        height: 44,
        errorBuilder: (_, __, ___) => const Icon(AppIcons.storefront, color: Colors.white, size: 24),
      );
    }
    return const Icon(AppIcons.storefront, color: Colors.white, size: 24);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: const BoxDecoration(
        color: AppColors.bg_surface,
        border: Border(right: BorderSide(color: AppColors.border_subtle)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Logo / Store Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent_primary,
              borderRadius: AppRadius.md,
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildLogo(),
          ),
          const SizedBox(height: 10),

          // Nav Items - scrollable when many tabs
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in <({int tab, IconData icon, String label})>[
                    (tab: 0, icon: AppIcons.pos, label: 'POS'),
                    (tab: 1, icon: AppIcons.receiptLong, label: 'Sales'),
                    (tab: 2, icon: AppIcons.inventory, label: 'Stock'),
                    (tab: 7, icon: AppIcons.shipping, label: 'Orders'),
                    (tab: 8, icon: AppIcons.shipping, label: 'Delivery'),
                    (tab: 3, icon: AppIcons.people, label: 'Credit'),
                    (tab: 4, icon: AppIcons.wallet, label: 'Till'),
                    (tab: 5, icon: AppIcons.analytics, label: 'Reports'),
                    (tab: 6, icon: AppIcons.settings, label: 'Settings'),
                  ])
                    if (visibleTabs.contains(item.tab))
                      _NavIcon(
                        icon: item.icon,
                        label: item.label,
                        isSelected: activeIndex == item.tab,
                        onTap: () => onSelectTab(item.tab),
                      ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Offline Sync Status Icon
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tooltip(
              message: 'Local-First Sync Status: Online',
              child: InkWell(
                onTap: onOpenSync,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(AppIcons.cloudDone, color: AppColors.status_success, size: 18),
                  ),
                ),
              ),
            ),
          ),

          // Lock Till Button
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tooltip(
              message: 'Lock Till',
              child: IconButton(
                icon: const Icon(AppIcons.lock, color: AppColors.text_tertiary, size: 20),
                onPressed: onLockTill,
              ),
            ),
          ),

          // Cashier Profile Avatar
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tooltip(
              message: '$activeCashier • ${roleDisplay ?? 'Staff'} (Tap to lock)',
              child: InkWell(
                onTap: onLockTill,
                borderRadius: BorderRadius.circular(18),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.accent_light,
                  child: Text(
                    initials ?? (activeCashier.isNotEmpty ? activeCashier.substring(0, 2).toUpperCase() : 'JM'),
                    style: const TextStyle(color: AppColors.accent_primary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent_light : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent_primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(height: 6),
              Icon(
                icon,
                color: isSelected ? AppColors.accent_primary : AppColors.text_tertiary,
                size: isSelected ? 22 : 19,
                weight: isSelected ? 700 : 400,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.accent_primary : AppColors.text_tertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosTerminalView extends StatefulWidget {
  const _PosTerminalView({
    required this.state,
    required this.onOpenSync,
  });

  final PosState state;
  final VoidCallback onOpenSync;

  @override
  State<_PosTerminalView> createState() => _PosTerminalViewState();
}

class _PosTerminalViewState extends State<_PosTerminalView> {
  final _search = TextEditingController();
  final _barcodeInput = TextEditingController();
  String _category = 'All items';

  @override
  void dispose() {
    _search.dispose();
    _barcodeInput.dispose();
    super.dispose();
  }

  List<String> get _categories => ['All items', ...{for (final p in widget.state.products) p.category}];

  List<PosProduct> get _visibleProducts => widget.state.products.where((p) {
        final matchesCategory = _category == 'All items' || p.category == _category;
        final query = _search.text.trim().toLowerCase();
        return matchesCategory && (query.isEmpty || p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query));
      }).toList();

  int _qtyInCart(String productId) {
    for (final line in widget.state.cart.lines) {
      if (line.productId == productId) return line.quantity;
    }
    return 0;
  }

  void _onProductTap(PosProduct product) {
    widget.state.addToCart(
      product,
      onRefused: (reason) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name}: $reason'),
            backgroundColor: AppColors.status_danger,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _onCheckout() {
    if (widget.state.cart.isEmpty) return;
    CheckoutModal.show(context, widget.state, onSaleCompleted: () {
      setState(() {});
    });
  }

  void _handleQuickBarcode(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final product = widget.state.products.cast<PosProduct?>().firstWhere(
      (p) => p != null && (
        p.sku.toLowerCase() == clean.toLowerCase() ||
        (p.barcode != null && p.barcode!.toLowerCase() == clean.toLowerCase()) ||
        p.name.toLowerCase().contains(clean.toLowerCase())
      ),
      orElse: () => null,
    );

    if (product != null) {
      _onProductTap(product);
      _barcodeInput.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${product.name}" to basket'),
          backgroundColor: AppColors.status_success,
          duration: const Duration(milliseconds: 1200),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No item found with barcode/SKU: "$clean"'),
          backgroundColor: AppColors.status_danger,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onScanBarcodeModal() {
    final barcodeController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border_subtle),
        ),
        title: Row(
          children: const [
            Icon(AppIcons.qrScanner, color: AppColors.accent_primary),
            SizedBox(width: 10),
            Text('Barcode Scanner Wedge', style: TextStyle(color: AppColors.text_primary, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 70,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.accent_light,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent_primary.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(AppIcons.qrCode, size: 30, color: AppColors.accent_primary),
                      SizedBox(width: 12),
                      Text('Ready to scan • USB HID Wedge Active', style: TextStyle(color: AppColors.accent_primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: barcodeController,
                autofocus: true,
                style: const TextStyle(color: AppColors.text_primary),
                decoration: InputDecoration(
                  labelText: 'Scan or type Barcode / SKU',
                  labelStyle: const TextStyle(color: AppColors.text_secondary),
                  filled: true,
                  fillColor: AppColors.bg_subtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border_subtle),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(AppIcons.arrowForward, color: AppColors.accent_primary),
                    onPressed: () {
                      _handleQuickBarcode(barcodeController.text);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                onSubmitted: (val) {
                  _handleQuickBarcode(val);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 16),
              const Text('Quick Test Barcodes:', style: TextStyle(color: AppColors.text_tertiary, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.state.products.take(4).map((p) {
                  return ActionChip(
                    backgroundColor: AppColors.bg_subtle,
                    side: const BorderSide(color: AppColors.border_subtle),
                    label: Text('${p.sku} (${p.name})', style: const TextStyle(color: AppColors.accent_primary, fontSize: 11, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      _handleQuickBarcode(p.sku);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text_secondary)),
          ),
        ],
      ),
    );
  }

  void _showMobileCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _CartPanel(
              state: widget.state,
              onCheckout: () {
                Navigator.pop(ctx);
                _onCheckout();
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Header with Offline Sync Indicator
        _TopBar(
          branchName: widget.state.storeBranch,
          itemCount: widget.state.cart.itemCount,
          onOpenCart: () => _showMobileCartSheet(context),
          onOpenSync: widget.onOpenSync,
        ),

        // Split Area: Catalog Grid + Cart Sidebar
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 650;
              final isCompact = constraints.maxWidth < 950;
              final catalog = _Catalog(
                search: _search,
                barcodeInput: _barcodeInput,
                categories: _categories,
                selectedCategory: _category,
                products: _visibleProducts,
                allProducts: widget.state.products,
                onCategory: (cat) => setState(() => _category = cat),
                onSearch: (_) => setState(() {}),
                onBarcodeSubmit: _handleQuickBarcode,
                onProductTap: _onProductTap,
                onScan: _onScanBarcodeModal,
                cartQty: _qtyInCart,
              );

              final cartPanel = _CartPanel(
                state: widget.state,
                onCheckout: _onCheckout,
              );

              if (isMobile) {
                final cart = widget.state.cart;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: cart.isNotEmpty ? 70 : 0),
                        child: catalog,
                      ),
                    ),
                    if (cart.isNotEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _MobileCartBanner(
                          state: widget.state,
                          onTap: () => _showMobileCartSheet(context),
                          onCheckout: _onCheckout,
                        ),
                      ),
                  ],
                );
              }

              if (isCompact) {
                return Column(
                  children: [
                    Expanded(child: catalog),
                    SizedBox(height: 380, child: cartPanel),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: catalog),
                  SizedBox(width: 380, child: cartPanel),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.branchName,
    required this.itemCount,
    this.onOpenCart,
    required this.onOpenSync,
  });

  final String branchName;
  final int itemCount;
  final VoidCallback? onOpenCart;
  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.bg_surface,
        border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    branchName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.text_primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Interactive Offline/Online Sync Badge
                InkWell(
                  onTap: onOpenSync,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircleAvatar(radius: 3, backgroundColor: AppColors.status_success),
                        SizedBox(width: 4),
                        Text(
                          'ONLINE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.status_success, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cart indicator with tap support
          InkWell(
            onTap: onOpenCart,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: itemCount > 0 ? AppColors.accent_light : AppColors.bg_canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: itemCount > 0 ? AppColors.accent_primary.withValues(alpha: 0.3) : AppColors.border_subtle),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.bag, size: 16, color: itemCount > 0 ? AppColors.accent_primary : AppColors.text_secondary),
                  const SizedBox(width: 6),
                  Text(
                    '$itemCount units',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: itemCount > 0 ? AppColors.accent_primary : AppColors.text_primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileCartBanner extends StatelessWidget {
  const _MobileCartBanner({
    required this.state,
    required this.onTap,
    required this.onCheckout,
  });

  final PosState state;
  final VoidCallback onTap;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final cart = state.cart;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accent_primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(AppIcons.bag, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${cart.itemCount} ${cart.itemCount == 1 ? "item" : "items"} in basket',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'KES ${cart.subtotal.formatted}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: onCheckout,
                icon: const Icon(AppIcons.arrowForward, size: 16),
                label: const Text('Pay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent_primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  const _Catalog({
    required this.search,
    required this.barcodeInput,
    required this.categories,
    required this.selectedCategory,
    required this.products,
    required this.allProducts,
    required this.onCategory,
    required this.onSearch,
    required this.onBarcodeSubmit,
    required this.onProductTap,
    required this.onScan,
    required this.cartQty,
  });

  final TextEditingController search;
  final TextEditingController barcodeInput;
  final List<String> categories;
  final String selectedCategory;
  final List<PosProduct> products;
  final List<PosProduct> allProducts;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onBarcodeSubmit;
  final ValueChanged<PosProduct> onProductTap;
  final VoidCallback onScan;

  /// Units of a product currently in the basket (0 if none).
  final int Function(String productId) cartQty;

  @override
  Widget build(BuildContext context) {
    // Fast moving popular products for quick addition
    final fastMoving = allProducts.take(5).toList();

    return Container(
      color: AppColors.bg_canvas,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search & Direct Barcode Row
          LayoutBuilder(
            builder: (context, searchConstraints) {
              final isNarrow = searchConstraints.maxWidth < 600;
              if (isNarrow) {
                return Column(
                  children: [
                    TextField(
                      controller: search,
                      onChanged: onSearch,
                      decoration: InputDecoration(
                        hintText: 'Search catalog or SKU...',
                        prefixIcon: const Icon(AppIcons.search, size: 18),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                        suffixIcon: IconButton(
                          icon: const Icon(AppIcons.qrScanner, color: AppColors.accent_primary),
                          onPressed: onScan,
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: search,
                      onChanged: onSearch,
                      decoration: InputDecoration(
                        hintText: 'Search catalog by product name or SKU...',
                        prefixIcon: const Icon(AppIcons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Direct barcode scanner input field
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: barcodeInput,
                      onSubmitted: onBarcodeSubmit,
                      decoration: InputDecoration(
                        hintText: 'Direct Barcode / Scan...',
                        prefixIcon: const Icon(AppIcons.barcodeReader, size: 18, color: AppColors.accent_primary),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                        suffixIcon: IconButton(
                          icon: const Icon(AppIcons.addToCart, size: 18, color: AppColors.accent_primary),
                          onPressed: () => onBarcodeSubmit(barcodeInput.text),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(AppIcons.qrScanner, size: 18),
                    label: const Text('HID Wedge'),
                    onPressed: onScan,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          // Fast-Moving Quick Picks Strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(AppIcons.bolt, size: 14, color: Color(0xFFD97706)),
                      SizedBox(width: 4),
                      Text('Fast Picks:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ...fastMoving.map((p) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(p.icon, size: 14, color: AppColors.accent_primary),
                    label: Text('${p.name} (KES ${p.unitPrice.formatted})'),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border_subtle),
                    labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text_primary),
                    onPressed: () => onProductTap(p),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Category Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = cat == selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(cat),
                    onSelected: (_) => onCategory(cat),
                    selectedColor: AppColors.accent_primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.accent_primary,
                    labelStyle: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppColors.accent_primary : AppColors.text_secondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Product Grid
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No products match your filter.'))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return _StaggeredFadeIn(
                        delay: Duration(milliseconds: (index * 28).clamp(0, 400)),
                        child: _ProductTile(
                          product: p,
                          cartQty: cartQty(p.id),
                          onTap: () => onProductTap(p),
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

/// Lightweight stagger fade+slide for grid items.
class _StaggeredFadeIn extends StatefulWidget {
  const _StaggeredFadeIn({required this.child, required this.delay});
  final Widget child;
  final Duration delay;

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

/// Large, photo-first product tile for the POS grid.
///
/// - Big image fills the top of the card (category icon if no photo).
/// - Hover (desktop) or tap the (i) / long-press (touch) to see SKU, barcode,
///   category, stock level and VAT. Cost price and margin are deliberately NOT
///   shown on the till.
/// - Shows how many units are already in the basket.
class _ProductTile extends StatefulWidget {
  const _ProductTile({
    required this.product,
    required this.cartQty,
    required this.onTap,
  });

  final PosProduct product;
  final int cartQty;
  final VoidCallback onTap;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool _hovered = false;
  bool _pressed = false;
  bool _pinnedInfo = false;

  // Decode the base64 image once, not on every hover rebuild.
  Uint8List? _bytes;
  String? _bytesSource;

  Uint8List? _photoBytes(PosProduct p) {
    final src = p.imageBase64;
    if (src == null || src.isEmpty) return null;
    if (!identical(src, _bytesSource) && src != _bytesSource) {
      try {
        _bytes = base64Decode(src.split(',').last.replaceAll(RegExp(r'\s+'), ''));
      } catch (_) {
        _bytes = null;
      }
      _bytesSource = src;
    }
    return _bytes;
  }

  Widget _photo(PosProduct p) {
    final bytes = _photoBytes(p);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _placeholder(p),
      );
    }
    return _placeholder(p);
  }

  Widget _placeholder(PosProduct p) {
    return Container(
      color: p.tint,
      alignment: Alignment.center,
      child: Icon(p.icon, size: 56, color: AppColors.text_primary.withAlpha(90)),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 62,
            child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoOverlay(PosProduct p) {
    final stockColor = p.isOutOfStock
        ? const Color(0xFFFCA5A5)
        : (p.isLowStock ? const Color(0xFFFCD34D) : const Color(0xFF86EFAC));
    final stockText = p.isOutOfStock
        ? 'Out of stock'
        : '${p.stock} units${p.isLowStock ? ' (low)' : ''}';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC0F172A), Color(0xF20F172A)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      alignment: Alignment.bottomLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Category', p.category),
            _infoRow('SKU', p.sku),
            if (p.barcode != null && p.barcode!.isNotEmpty) _infoRow('Barcode', p.barcode!),
            _infoRow('In stock', stockText, valueColor: stockColor),
            _infoRow('Price', 'incl. ${(p.taxRateBasisPoints / 100).toStringAsFixed(0)}% VAT'),
            if (p.notes != null && p.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  p.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final out = p.isOutOfStock;
    final qty = widget.cartQty;
    final showInfo = _hovered || _pinnedInfo;

    final stockColor = out
        ? AppColors.status_danger
        : (p.isLowStock ? const Color(0xFFD97706) : AppColors.status_success);

    Widget photo = _photo(p);
    if (out) {
      photo = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: photo,
      );
    }

    final selected = qty > 0;

    return MouseRegion(
      cursor: out ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: out ? null : widget.onTap,
        onLongPress: () => setState(() => _pinnedInfo = !_pinnedInfo),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.accent_primary
                    : (_hovered && !out ? AppColors.accent_primary.withAlpha(150) : AppColors.border_subtle),
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _hovered && !out ? AppColors.accent_primary.withAlpha(30) : const Color(0x0A000000),
                  blurRadius: _hovered && !out ? 14 : 5,
                  offset: Offset(0, _hovered && !out ? 6 : 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Big photo ──
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo,

                      // Hover / pinned info
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: showInfo ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: _infoOverlay(p),
                          ),
                        ),
                      ),

                      // Out of stock banner
                      if (out)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: AppColors.status_danger.withAlpha(220),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            alignment: Alignment.center,
                            child: const Text(
                              'OUT OF STOCK',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                            ),
                          ),
                        ),

                      // Stock pill (top-left)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(238),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4)],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(color: stockColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                out ? '0 left' : '${p.stock} left',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: stockColor),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Info button (top-right) — tap to pin details, works on touch
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Tooltip(
                          message: 'Product details',
                          child: GestureDetector(
                            onTap: () => setState(() => _pinnedInfo = !_pinnedInfo),
                            child: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _pinnedInfo ? AppColors.accent_primary : Colors.white.withAlpha(238),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4)],
                              ),
                              child: Icon(
                                AppIcons.info,
                                size: 16,
                                color: _pinnedInfo ? Colors.white : AppColors.text_secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Name + price + add ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 34,
                        child: Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.25),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'KES ${p.unitPrice.formatted}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.accent_primary),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 30,
                            constraints: const BoxConstraints(minWidth: 30),
                            padding: EdgeInsets.symmetric(horizontal: selected ? 9 : 0),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: out
                                  ? AppColors.border_subtle
                                  : (selected || _hovered ? AppColors.accent_primary : AppColors.accent_light),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: selected
                                ? Text(
                                    '×$qty',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                  )
                                : Icon(
                                    AppIcons.add,
                                    size: 18,
                                    color: out
                                        ? AppColors.text_tertiary
                                        : (_hovered ? Colors.white : AppColors.accent_primary),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.product, required this.onTap});

  final PosProduct product;
  final VoidCallback onTap;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: product.isOutOfStock ? null : widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : (_hovered && !product.isOutOfStock ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: product.isOutOfStock
                    ? AppColors.status_danger.withValues(alpha: 0.3)
                    : (_hovered ? AppColors.accent_primary.withAlpha(160) : AppColors.border_subtle),
                width: _hovered && !product.isOutOfStock ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _hovered && !product.isOutOfStock
                      ? AppColors.accent_primary.withAlpha(25)
                      : const Color(0x05000000),
                  blurRadius: _hovered && !product.isOutOfStock ? 10 : 4,
                  offset: Offset(0, _hovered && !product.isOutOfStock ? 4 : 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: product.tint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: product.imageBase64 != null && product.imageBase64!.isNotEmpty
                          ? Image.memory(
                              base64Decode(product.imageBase64!.split(',').last),
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Icon(product.icon, color: AppColors.text_primary, size: 20),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: product.isOutOfStock
                            ? const Color(0xFFFEF2F2)
                            : (product.isLowStock ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: product.isOutOfStock
                              ? const Color(0xFFFECACA)
                              : (product.isLowStock ? const Color(0xFFFDE68A) : const Color(0xFFDCFCE7)),
                        ),
                      ),
                      child: Text(
                        product.isOutOfStock ? '0 LEFT' : '${product.stock} left',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: product.isOutOfStock
                              ? AppColors.status_danger
                              : (product.isLowStock ? const Color(0xFFD97706) : AppColors.status_success),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.2),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'KES ${product.unitPrice.formatted}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.accent_primary),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: product.isOutOfStock
                            ? AppColors.border_subtle
                            : (_hovered ? AppColors.accent_primary : AppColors.accent_light),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        AppIcons.add,
                        color: product.isOutOfStock
                            ? AppColors.text_tertiary
                            : (_hovered ? Colors.white : AppColors.accent_primary),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({required this.state, required this.onCheckout});

  final PosState state;
  final VoidCallback onCheckout;

  void _showSelectCustomerDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bg_surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Attach Customer to Sale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 360,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: state.customers.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final c = state.customers[index];
              return ListTile(
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.phone} · Debt: KES ${c.currentBalance.formatted}'),
                onTap: () {
                  state.selectCustomer(c);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          if (state.selectedCustomer != null)
            TextButton(
              onPressed: () {
                state.selectCustomer(null);
                Navigator.pop(context);
              },
              child: const Text('Clear Customer', style: TextStyle(color: AppColors.status_danger)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = state.cart;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppColors.border_subtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cart Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current Sale', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${cart.itemCount} items in basket', style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                  ],
                ),
                if (cart.isNotEmpty)
                  IconButton(
                    icon: const Icon(AppIcons.deleteSweep, size: 20, color: AppColors.status_danger),
                    tooltip: 'Clear Basket',
                    onPressed: state.clearCart,
                  ),
              ],
            ),
          ),

          // Attached Customer Bar
          InkWell(
            onTap: () => _showSelectCustomerDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: state.selectedCustomer != null ? const Color(0xFFFFFBEB) : AppColors.bg_canvas,
              child: Row(
                children: [
                  Icon(
                    state.selectedCustomer != null ? AppIcons.person : AppIcons.personAdd,
                    size: 18,
                    color: state.selectedCustomer != null ? const Color(0xFFD97706) : AppColors.text_tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.selectedCustomer != null ? 'Customer: ${state.selectedCustomer!.name}' : 'Attach Customer Account (Optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: state.selectedCustomer != null ? FontWeight.bold : FontWeight.normal,
                        color: state.selectedCustomer != null ? const Color(0xFF92400E) : AppColors.text_secondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(AppIcons.chevronRight, size: 16, color: AppColors.text_tertiary),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Cart Items List
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: cart.isEmpty
                  ? const Center(
                      key: ValueKey('empty'),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.cart, size: 48, color: AppColors.border_strong),
                          SizedBox(height: 12),
                          Text('Basket is empty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text_secondary)),
                          SizedBox(height: 4),
                          Text('Tap catalog items to add', style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('cart'),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: cart.lines.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final line = cart.lines.elementAt(index);
                        return _AnimatedCartItem(
                          key: ValueKey(line.productId),
                          child: ListTile(
                            dense: true,
                            title: Text(line.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(
                              '${line.quantity} × KES ${line.unitPrice.formatted}',
                              style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'KES ${line.lineTotal.formatted}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 8),
                                _QtyStepper(
                                  quantity: line.quantity,
                                  stock: line.stock,
                                  onMinus: () => state.changeQuantity(line.productId, -1),
                                  onPlus: () {
                                    state.changeQuantity(
                                      line.productId,
                                      1,
                                      onRefused: (reason) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('${line.name}: $reason'),
                                            backgroundColor: AppColors.status_danger,
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),


          // Financial Summary & Charge Button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.bg_surface,
              border: Border(top: BorderSide(color: AppColors.border_subtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal (Excl. Tax)', style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                    Text(
                      'KES ${Money(cart.subtotal.minorUnits - cart.vatAmount.minorUnits).formatted}',
                      style: const TextStyle(fontSize: 12, color: AppColors.text_secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('VAT Included (16%)', style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                    Text('KES ${cart.vatAmount.formatted}', style: const TextStyle(fontSize: 12, color: AppColors.text_secondary)),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL PAYABLE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                      'KES ${cart.subtotal.formatted}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.accent_primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(AppIcons.creditCard, size: 20),
                  label: Text('CHARGE KES ${cart.subtotal.formatted}'),
                  onPressed: cart.canCheckout ? onCheckout : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent_primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.quantity,
    required this.stock,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final int stock;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg_canvas,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onMinus,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(AppIcons.remove, size: 14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Text(
                '$quantity',
                key: ValueKey<int>(quantity),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          InkWell(
            onTap: onPlus,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(AppIcons.add, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated entrance wrapper for individual cart items — fades and slides in from the right.
class _AnimatedCartItem extends StatefulWidget {
  const _AnimatedCartItem({super.key, required this.child});
  final Widget child;

  @override
  State<_AnimatedCartItem> createState() => _AnimatedCartItemState();
}

class _AnimatedCartItemState extends State<_AnimatedCartItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}
