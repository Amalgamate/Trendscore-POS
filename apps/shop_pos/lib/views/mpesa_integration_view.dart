import 'package:flutter/material.dart';

import '../services/api_service.dart';
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
  String _environment = 'sandbox';
  String _transactionType = 'CustomerPayBillOnline';
  Map<String, dynamic>? _configuration;
  List<Map<String, dynamic>> _paymentTransactions = [];
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _refreshingTransactions = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final configuration = await ApiService.instance
        .getMpesaConfigurationStatus();
    final transactions = await ApiService.instance.getMpesaTransactions();
    if (!mounted) return;
    setState(() {
      _configuration = configuration;
      _paymentTransactions = (transactions?['data'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      _loading = false;
      if (configuration == null || transactions == null) {
        _feedback = ApiService.instance.lastError;
      }
      if (configuration != null) {
        _environment = configuration['environment']?.toString() ?? _environment;
        _transactionType =
            configuration['transactionType']?.toString() ?? _transactionType;
        _shortcode.text = configuration['shortcode']?.toString() ?? '';
        _accountReference.text =
            configuration['accountReference']?.toString() ?? '';
      }
    });
  }

  Future<void> _refreshTransactions() async {
    setState(() => _refreshingTransactions = true);
    final result = await ApiService.instance.getMpesaTransactions();
    if (!mounted) return;
    setState(() {
      _refreshingTransactions = false;
      if (result != null) {
        _paymentTransactions = (result['data'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
        _feedback = null;
      } else {
        _feedback = ApiService.instance.lastError;
      }
    });
  }

  Future<void> _saveConfiguration() async {
    if (_shortcode.text.trim().isEmpty ||
        _accountReference.text.trim().isEmpty ||
        _consumerKey.text.trim().isEmpty ||
        _consumerSecret.text.trim().isEmpty ||
        _passkey.text.trim().isEmpty) {
      setState(
        () => _feedback =
            'Complete every merchant and credential field before saving.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _feedback = null;
    });
    final saved = await ApiService.instance.saveMpesaConfiguration({
      'environment': _environment,
      'shortcode': _shortcode.text.trim(),
      'transactionType': _transactionType,
      'accountReference': _accountReference.text.trim(),
      'consumerKey': _consumerKey.text.trim(),
      'consumerSecret': _consumerSecret.text.trim(),
      'passkey': _passkey.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      _configuration = saved ?? _configuration;
      _feedback = saved == null
          ? ApiService.instance.lastError
          : 'Credentials were encrypted and saved on the shop server.';
    });
    if (saved != null) {
      _consumerKey.clear();
      _consumerSecret.clear();
      _passkey.clear();
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _feedback = null;
    });
    final connected = await ApiService.instance.testMpesaConnection();
    final refreshedConfiguration = connected
        ? await ApiService.instance.getMpesaConfigurationStatus()
        : null;
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (refreshedConfiguration != null) {
        _configuration = refreshedConfiguration;
      }
      _feedback = connected
          ? 'Daraja credentials are valid and the server can reach the provider.'
          : ApiService.instance.lastError;
    });
  }

  Future<void> _reconcile(String paymentId) async {
    setState(() {
      _feedback = null;
      _refreshingTransactions = true;
    });
    final payment = await ApiService.instance.reconcileMpesaTransaction(
      paymentId,
    );
    final result = await ApiService.instance.getMpesaTransactions();
    if (!mounted) return;
    setState(() {
      _refreshingTransactions = false;
      if (result != null) {
        _paymentTransactions = (result['data'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      }
      _feedback = payment == null
          ? ApiService.instance.lastError
          : 'Payment status checked: ${payment['status'] ?? 'unknown'}.';
    });
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
    final configured = _configuration?['configured'] == true;
    final ready = _configuration?['paymentReady'] == true;
    final connectionLabel = _loading
        ? 'Checking'
        : ready
        ? 'Ready'
        : !configured
        ? 'Not connected'
        : _configuration?['callbackUrl'] == null
        ? 'Needs callback'
        : _configuration?['verified'] == true
        ? 'Ready'
        : 'Needs test';
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
                            connectionLabel,
                            ready
                                ? Icons.verified_rounded
                                : Icons.link_off_rounded,
                            ready
                                ? palette.statusSuccess
                                : palette.statusWarning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Configure and monitor the payment providers used by this shop.',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      if (_loading) const LinearProgressIndicator(),
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
          final statusPanel = _statusPanel();
          final readiness = _readinessPanel();
          return stacked
              ? Column(
                  children: [
                    statusPanel,
                    const SizedBox(height: 16),
                    readiness,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: statusPanel),
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
    final configuration = _configuration;
    final configured = configuration?['configured'] == true;
    final ready = configuration?['paymentReady'] == true;
    return _section(
      title: 'M-Pesa',
      description: 'Safaricom Daraja payment integration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ready
                  ? palette.statusSuccessLight
                  : palette.statusWarningLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (ready ? palette.statusSuccess : palette.statusWarning)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ready
                      ? Icons.check_circle_outline
                      : Icons.info_outline_rounded,
                  color: ready ? palette.statusSuccess : palette.statusWarning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _statusRow(
            'Environment',
            configuration?['environment']?.toString() ?? 'Not selected',
            Icons.tune_rounded,
          ),
          _statusRow(
            'Merchant shortcode',
            configuration?['shortcode']?.toString() ?? 'Not configured',
            Icons.storefront_outlined,
          ),
          _statusRow(
            'Server encryption',
            configuration?['encryptionReady'] == true ? 'Ready' : 'Unavailable',
            Icons.lock_outline_rounded,
          ),
          _statusRow(
            'Public HTTPS callback',
            configuration?['callbackUrl']?.toString() ?? 'Not provisioned',
            Icons.schedule_rounded,
          ),
          _statusRow(
            'Payment processing',
            ready ? 'Pickup payments enabled' : 'Unavailable',
            Icons.payments_outlined,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: !_loading && configured && !_testing
                ? _testConnection
                : null,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded),
            label: Text(_testing ? 'Testing connection…' : 'Test connection'),
          ),
        ],
      ),
    );
  }

  String get _statusMessage {
    if (_loading) return 'Checking the shop server configuration.';
    if (_configuration == null) {
      return _feedback ??
          'M-Pesa status could not be loaded from the shop server.';
    }
    if (_configuration?['paymentReady'] == true) {
      return 'Daraja is configured. Online M-Pesa is enabled for pickup orders only.';
    }
    if (_configuration?['configured'] == true) {
      if (_configuration?['callbackUrl'] == null) {
        return 'Credentials are saved, but payment initiation stays disabled until a public HTTPS callback is configured.';
      }
      if (_configuration?['verified'] != true) {
        return 'Credentials are saved. Test the Daraja connection before pickup payments can be enabled.';
      }
    }
    if (_configuration?['encryptionReady'] != true) {
      return 'Server-side encryption is not available. No credentials can be saved.';
    }
    return 'Daraja is not connected. No M-Pesa payments are being initiated or verified.';
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
            _configuration?['encryptionReady'] == true
                ? 'Server-side encryption is ready for credentials.'
                : 'Server-side encryption key is unavailable.',
            Icons.lock_outline_rounded,
            _configuration?['encryptionReady'] == true
                ? palette.statusSuccess
                : palette.statusWarning,
          ),
          _readinessItem(
            'Daraja server adapter',
            'Daraja OAuth, STK Push, and transaction query are available server-side.',
            Icons.hub_outlined,
            palette.statusInfo,
          ),
          _readinessItem(
            'Verified callback handling',
            'Callbacks are correlated with a recorded checkout, then verified with Daraja.',
            Icons.verified_user_outlined,
            palette.statusInfo,
          ),
          _readinessItem(
            'Payment-to-order reconciliation',
            'Uncertain payment results keep the stock hold until staff reconcile them.',
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: _configuration?['encryptionReady'] == true
                      ? palette.statusInfo
                      : palette.statusWarning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _configuration?['encryptionReady'] == true
                        ? 'Credentials are sent directly to the shop API over HTTPS and encrypted before storage. They are never retained on this device.'
                        : 'Server-side encryption is unavailable. The shop API will reject credential saves until its encryption key is provisioned.',
                    style: const TextStyle(height: 1.45),
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
                    value: _environment,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Environment',
                      prefixIcon: Icon(Icons.cloud_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'sandbox',
                        child: Text('Sandbox'),
                      ),
                      DropdownMenuItem(
                        value: 'production',
                        child: Text('Production'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _environment = value);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: _transactionType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Transaction type',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'CustomerPayBillOnline',
                        child: Text('Paybill'),
                      ),
                      DropdownMenuItem(
                        value: 'CustomerBuyGoodsOnline',
                        child: Text('Buy Goods / Till'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _transactionType = value);
                      }
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
                if (narrow) {
                  return Column(
                    children: [
                      for (final field in fields) ...[
                        field,
                        const SizedBox(height: 14),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 16),
                        Expanded(child: fields[2]),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: fields[1]),
                        const SizedBox(width: 16),
                        Expanded(child: fields[3]),
                      ],
                    ),
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
                'Daraja sends payment results to this public HTTPS endpoint for server-side verification.',
            child: SelectableText(
              _configuration?['callbackUrl']?.toString() ?? 'Not provisioned',
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
                onPressed: _saving || _configuration?['encryptionReady'] != true
                    ? null
                    : _saveConfiguration,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  _saving ? 'Saving securely…' : 'Save configuration',
                ),
              ),
              OutlinedButton.icon(
                onPressed: !_configurationReady || _testing
                    ? null
                    : _testConnection,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_testing ? 'Testing…' : 'Test saved connection'),
              ),
            ],
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 12),
            Text(
              _feedback!,
              style: TextStyle(
                color:
                    _feedback!.toLowerCase().contains('could not') ||
                        _feedback!.toLowerCase().contains('unavailable')
                    ? palette.statusDanger
                    : palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _configurationReady => _configuration?['configured'] == true;

  Widget _transactions() {
    final palette = context.palette;
    return _pageContent(
      _section(
        title: 'M-Pesa transactions',
        description:
            'Recorded payment requests, verified receipts, and current settlement state.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _refreshingTransactions
                    ? null
                    : _refreshTransactions,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  _refreshingTransactions ? 'Refreshing…' : 'Refresh',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_paymentTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    _loading
                        ? 'Loading payment history…'
                        : 'No M-Pesa transactions have been recorded.',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ),
              )
            else
              for (final payment in _paymentTransactions) ...[
                _paymentRow(payment, reconciliable: false),
                if (payment != _paymentTransactions.last)
                  Divider(color: palette.borderSubtle, height: 1),
              ],
          ],
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
                'Recheck pending and uncertain results against Daraja before treating an order as paid.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unresolved payments retain their stock reservation. Reconciliation never marks an order paid unless Daraja reports success and the callback details match the recorded amount and phone.',
                  style: TextStyle(color: palette.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _refreshingTransactions
                      ? null
                      : _refreshTransactions,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    _refreshingTransactions
                        ? 'Checking…'
                        : 'Refresh unresolved payments',
                  ),
                ),
                const SizedBox(height: 12),
                for (final payment in _paymentTransactions.where(
                  (entry) =>
                      entry['status'] == 'PENDING' ||
                      entry['status'] == 'UNKNOWN',
                )) ...[
                  _paymentRow(payment, reconciliable: true),
                  Divider(color: palette.borderSubtle, height: 1),
                ],
                if (!_loading &&
                    _paymentTransactions.every(
                      (entry) =>
                          entry['status'] != 'PENDING' &&
                          entry['status'] != 'UNKNOWN',
                    ))
                  Text(
                    'No unresolved payments need reconciliation.',
                    style: TextStyle(color: palette.textSecondary),
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
                    _configuration?['callbackUrl']?.toString() ??
                        'No public HTTPS callback endpoint is configured.',
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

  Widget _paymentRow(
    Map<String, dynamic> payment, {
    required bool reconciliable,
  }) {
    final palette = context.palette;
    final status = payment['status']?.toString() ?? 'UNKNOWN';
    final order = payment['order'] is Map
        ? Map<String, dynamic>.from(payment['order'] as Map)
        : <String, dynamic>{};
    final amount = payment['amount'];
    final paymentId = payment['id']?.toString();
    final unresolved = status == 'PENDING' || status == 'UNKNOWN';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order['orderNumber'] ?? 'Order'} · ${amount is num ? amount.toStringAsFixed(2) : amount ?? '—'} KES',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${order['customerName'] ?? 'Customer'} · ${payment['phoneNumber'] ?? ''}',
                style: TextStyle(color: palette.textSecondary),
              ),
              if (payment['receiptNumber'] is String)
                Text(
                  'Receipt ${payment['receiptNumber']}',
                  style: TextStyle(color: palette.textSecondary),
                ),
              if (payment['message'] is String)
                Text(
                  payment['message'] as String,
                  style: TextStyle(color: palette.textTertiary),
                ),
            ],
          );
          final action = reconciliable && unresolved && paymentId != null
              ? OutlinedButton(
                  onPressed: _refreshingTransactions
                      ? null
                      : () => _reconcile(paymentId),
                  child: const Text('Reconcile'),
                )
              : _statePill(
                  status,
                  status == 'SUCCEEDED'
                      ? Icons.check_circle_outline
                      : status == 'FAILED'
                      ? Icons.error_outline
                      : Icons.schedule_rounded,
                  status == 'SUCCEEDED'
                      ? palette.statusSuccess
                      : status == 'FAILED'
                      ? palette.statusDanger
                      : palette.statusWarning,
                );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 10), action],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
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
