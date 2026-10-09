import 'package:flutter/material.dart';

/// Odoo-style app launcher. Tiles navigate to the same destinations as the
/// POS sidebar; only apps allowed for the current staff role are shown.
class AppMenuView extends StatelessWidget {
  const AppMenuView({
    super.key,
    required this.visibleTabs,
    required this.onSelectTab,
  });

  final Set<int> visibleTabs;
  final ValueChanged<int> onSelectTab;

  static const _apps = <_WorkspaceApp>[
    _WorkspaceApp(
      0,
      'Point of Sale',
      Icons.point_of_sale_rounded,
      Color(0xFF0D9488),
    ),
    _WorkspaceApp(1, 'Sales', Icons.receipt_long_rounded, Color(0xFF2563EB)),
    _WorkspaceApp(2, 'Inventory', Icons.inventory_2_rounded, Color(0xFFEA8A24)),
    _WorkspaceApp(
      3,
      'Customers & Credit',
      Icons.people_alt_rounded,
      Color(0xFF7C3AED),
    ),
    _WorkspaceApp(
      4,
      'Cash Drawer',
      Icons.account_balance_wallet_rounded,
      Color(0xFF16A34A),
    ),
    _WorkspaceApp(5, 'Reports', Icons.bar_chart_rounded, Color(0xFF4F46E5)),
    _WorkspaceApp(6, 'Settings', Icons.settings_rounded, Color(0xFF475569)),
    _WorkspaceApp(7, 'Orders', Icons.local_shipping_rounded, Color(0xFFEA580C)),
    _WorkspaceApp(
      8,
      'Staff Management',
      Icons.manage_accounts_rounded,
      Color(0xFF0D9488),
    ),
    _WorkspaceApp(
      9,
      'Website Builder',
      Icons.storefront_rounded,
      Color(0xFF0D9488),
    ),
    _WorkspaceApp(
      10,
      'Social Commerce',
      Icons.campaign_rounded,
      Color(0xFF2563EB),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final apps = _apps.where((app) => visibleTabs.contains(app.tab)).toList();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF1F0F8), Color(0xFFE7E6F0)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth < 430 ? 116.0 : 138.0;
              final iconSize = constraints.maxWidth < 430 ? 68.0 : 78.0;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: constraints.maxWidth < 600 ? 12 : 30,
                      runSpacing: 26,
                      children: [
                        for (final app in apps)
                          _AppLauncherTile(
                            app: app,
                            width: tileWidth,
                            iconSize: iconSize,
                            onTap: () => onSelectTab(app.tab),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkspaceApp {
  const _WorkspaceApp(this.tab, this.name, this.icon, this.color);

  final int tab;
  final String name;
  final IconData icon;
  final Color color;
}

class _AppLauncherTile extends StatelessWidget {
  const _AppLauncherTile({
    required this.app,
    required this.width,
    required this.iconSize,
    required this.onTap,
  });

  final _WorkspaceApp app;
  final double width;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: app.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4EA)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      app.icon,
                      size: iconSize * 0.52,
                      color: app.color,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  app.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF354052),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
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
