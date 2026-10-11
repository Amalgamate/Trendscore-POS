import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class MpesaIntegrationView extends StatefulWidget {
  const MpesaIntegrationView({super.key});

  @override
  State<MpesaIntegrationView> createState() => _MpesaIntegrationViewState();
}

class _MpesaIntegrationViewState extends State<MpesaIntegrationView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _shortcode = TextEditingController();
  final _accountReference = TextEditingController();
  final _consumerKey = TextEditingController();
  final _consumerSecret = TextEditingController();
  final _passkey = TextEditingController();
  String _environment = 'Sandbox';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final controller in [
      _shortcode,
      _accountReference,
      _consumerKey,
      _consumerSecret,
      _passkey,
    ]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Integrations',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          _statePill(
                            'Not connected',
                            Icons.link_off_rounded,
                            palette.statusWarning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Configure and monitor the payment providers used by this shop.',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      TabBar(
                        controller: _tabs,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelColor: palette.accentPrimary,
                        unselectedLabelColor: palette.textSecondary,
                        indicatorColor: palette.accentPrimary,
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'M-Pesa setup'),
                          Tab(text: 'Transactions'),
                          Tab(text: 'Reconciliation'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _overview(),
                  _setup(),
                  _transactions(),
                  _reconciliation(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    return _pageContent(
      LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final status = _statusPanel();
          final readiness = _readinessPanel();
          return stacked
              ? Column(
                  children: [status, const SizedBox(height: 16), readiness],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: status),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: readiness),
                  ],
                );
        },
      ),
    );
  }

  Widget _statusPanel() {
    final palette = context.palette;
    return _section(
      title: 'M-Pesa',
      description: 'Safaricom Daraja payment integration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.statusWarningLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: palette.statusWarning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: palette.statusWarning),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Daraja is not connected. No M-Pesa payments are being initiated or verified.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _statusRow('Environment', 'Not selected', Icons.tune_rounded),
          _statusRow(
            'Last connection check',
            'Not available',
            Icons.schedule_rounded,
          ),
          _statusRow(
            'Callback verification',
            'Not configured',
            Icons.webhook_rounded,
          ),
          _statusRow(
            'Payment processing',
            'Unavailable',
            Icons.payments_outlined,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Test connection'),
          ),
        ],
      ),
    );
  }

  Widget _readinessPanel() {
    final palette = context.palette;
    return _section(
      title: 'Before payments can go live',
      description:
          'The connection remains disabled until each control is in place.',
      child: Column(
        children: [
          _readinessItem(
            'Secure credential storage',
            'Required before consumer keys or passkeys can be saved.',
            Icons.lock_outline_rounded,
            palette.statusWarning,
          ),
          _readinessItem(
            'Daraja server adapter',
            'The server-side provider boundary is prepared; no live adapter is active.',
            Icons.hub_outlined,
            palette.statusInfo,
          ),
          _readinessItem(
            'Verified callback handling',
            'Callbacks must be correlated with a recorded checkout and amount.',
            Icons.verified_user_outlined,
            palette.statusInfo,
          ),
          _readinessItem(
            'Payment-to-order reconciliation',
            'Uncertain results must be resolved before an order is marked paid.',
            Icons.sync_alt_rounded,
            palette.statusInfo,
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _setup() {
    final palette = context.palette;
    return _pageContent(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.statusInfoLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: palette.statusInfo.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: AppColors.status_info),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Setup preview only. Values stay in this screen and are not saved or sent. Saving and connection tests will be enabled after secure server-side credential storage is available.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section(
            title: 'Merchant settings',
            description:
                'Choose the Daraja environment and the merchant account for checkout.',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 620;
                final fields = [
                  DropdownButtonFormField<String>(
                    initialValue: _environment,
                    decoration: const InputDecoration(
                      labelText: 'Environment',
                      prefixIcon: Icon(Icons.cloud_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Sandbox',
                        child: Text('Sandbox'),
                      ),
                      DropdownMenuItem(
                        value: 'Production',
                        child: Text('Production'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _environment = value);
                    },
                  ),
                  TextFormField(
                    controller: _shortcode,
                    decoration: const InputDecoration(
                      labelText: 'Paybill or Till number',
                      hintText: 'Enter the Safaricom shortcode',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  TextFormField(
                    controller: _accountReference,
                    decoration: const InputDecoration(
                      labelText: 'Account reference',
                      hintText: 'For example, order reference',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                ];
                return narrow
                    ? Column(
                        children: [
                          for (final field in fields) ...[
                            field,
                            const SizedBox(height: 14),
                          ],
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: fields[0]),
                              const SizedBox(width: 16),
                              Expanded(child: fields[1]),
                            ],
                          ),
                          const SizedBox(height: 14),
                          fields[2],
                        ],
                      );
              },
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Daraja credentials',
            description:
                'Credentials are sensitive. They will only be accepted by the secure server adapter.',
            child: Column(
              children: [
                _secretField(_consumerKey, 'Consumer key'),
                const SizedBox(height: 14),
                _secretField(_consumerSecret, 'Consumer secret'),
                const SizedBox(height: 14),
                _secretField(_passkey, 'Lipa Na M-Pesa passkey'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Callback endpoint',
            description:
                'The callback URL will be provisioned and verified by the Shop API.',
            child: const SelectableText(
              'Not provisioned',
              style: TextStyle(
                fontFamily: AppFontFamily.mono,
                fontSize: AppFontSize.base,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save configuration'),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Test connection'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transactions() {
    final palette = context.palette;
    return _pageContent(
      _section(
        title: 'M-Pesa transactions',
        description:
            'Payment requests, callbacks, and provider receipts will be listed here.',
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 16),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 42,
                  color: palette.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Transaction history is not connected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'No live or sample transactions are shown. Connect and verify Daraja before payment records appear.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reconciliation() {
    final palette = context.palette;
    return _pageContent(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            title: 'Reconciliation',
            description:
                'Resolve delayed, timed-out, and callback-mismatched payment results.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reconciliation is unavailable until the Daraja adapter and verified callback pipeline are connected.',
                  style: TextStyle(color: palette.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check pending payments'),
                    ),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export reconciliation'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section(
            title: 'Callback activity',
            description:
                'Untrusted or unmatched callbacks must never mark an order as paid.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.webhook_outlined, color: palette.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No callback endpoint is active. Callback delivery attempts will be visible here after server-side verification is implemented.',
                    style: TextStyle(color: palette.textSecondary, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageContent(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: child,
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required String description,
    required Widget child,
  }) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: palette.textSecondary)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _statePill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, IconData icon) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 19, color: palette.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: palette.textSecondary)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readinessItem(
    String title,
    String description,
    IconData icon,
    Color color, {
    bool last = false,
  }) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(color: palette.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secretField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Enter $label',
        prefixIcon: const Icon(Icons.key_outlined),
        helperText: 'Preview only — not saved or transmitted',
      ),
    );
  }
}
