import 'package:flutter/material.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';

class WebsiteBuilderView extends StatefulWidget {
  const WebsiteBuilderView({super.key, required this.state});

  final PosState state;

  @override
  State<WebsiteBuilderView> createState() => _WebsiteBuilderViewState();
}

class _WebsiteBuilderViewState extends State<WebsiteBuilderView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {
    'storeName': TextEditingController(),
    'description': TextEditingController(),
    'phone': TextEditingController(),
    'email': TextEditingController(),
    'address': TextEditingController(),
    'county': TextEditingController(),
    'logoUrl': TextEditingController(),
    'openingHours': TextEditingController(),
    'deliveryDetails': TextEditingController(),
    'pickupDetails': TextEditingController(),
    'policyDelivery': TextEditingController(),
    'policyReturns': TextEditingController(),
    'policyPrivacy': TextEditingController(),
    'policyTerms': TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  bool _deliveryEnabled = false;
  bool _pickupEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final settings = await ApiService.instance.getStorefrontSettings();
    if (!mounted) return;
    if (settings == null) {
      setState(() {
        _loading = false;
        _error =
            ApiService.instance.lastError ??
            'Could not load the storefront settings.';
      });
      return;
    }

    final policies = settings['policies'] is Map
        ? Map<String, dynamic>.from(settings['policies'] as Map)
        : const <String, dynamic>{};
    void setText(String key, Object? value) {
      _controllers[key]?.text = value is String ? value : '';
    }

    setState(() {
      for (final key in [
        'storeName',
        'description',
        'phone',
        'email',
        'address',
        'county',
        'logoUrl',
        'openingHours',
        'deliveryDetails',
        'pickupDetails',
      ]) {
        setText(key, settings[key]);
      }
      setText('policyDelivery', policies['delivery']);
      setText('policyReturns', policies['returns']);
      setText('policyPrivacy', policies['privacy']);
      setText('policyTerms', policies['terms']);
      _deliveryEnabled = settings['deliveryEnabled'] == true;
      _pickupEnabled = settings['pickupEnabled'] == true;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final settings = <String, dynamic>{
      'storeName': _controllers['storeName']!.text.trim(),
      'description': _controllers['description']!.text.trim(),
      'phone': _controllers['phone']!.text.trim(),
      'email': _controllers['email']!.text.trim(),
      'address': _controllers['address']!.text.trim(),
      'county': _controllers['county']!.text.trim(),
      'logoUrl': _controllers['logoUrl']!.text.trim(),
      'openingHours': _controllers['openingHours']!.text.trim(),
      'deliveryEnabled': _deliveryEnabled,
      'deliveryDetails': _controllers['deliveryDetails']!.text.trim(),
      'pickupEnabled': _pickupEnabled,
      'pickupDetails': _controllers['pickupDetails']!.text.trim(),
      'policies': {
        'delivery': _controllers['policyDelivery']!.text.trim(),
        'returns': _controllers['policyReturns']!.text.trim(),
        'privacy': _controllers['policyPrivacy']!.text.trim(),
        'terms': _controllers['policyTerms']!.text.trim(),
      },
    };
    final saved = await ApiService.instance.updateStorefrontSettings(settings);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) {
        _error =
            ApiService.instance.lastError ??
            'Could not save the storefront settings.';
      }
    });
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storefront settings saved.')),
      );
    }
  }

  TextEditingController _controller(String key) => _controllers[key]!;

  Widget _field(
    String key,
    String label, {
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: _controller(key),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        alignLabelWithHint: maxLines > 1,
      ),
      maxLines: maxLines,
      maxLength: switch (key) {
        'storeName' => 200,
        'description' => 2000,
        'openingHours' => 2000,
        'deliveryDetails' || 'pickupDetails' => 3000,
        'policyDelivery' ||
        'policyReturns' ||
        'policyPrivacy' ||
        'policyTerms' => 8000,
        'address' => 300,
        'county' => 100,
        'phone' => 40,
        _ => null,
      },
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _section(String title, String description, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bg_surface,
        border: Border.all(color: AppColors.border_subtle),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text_primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.text_secondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? _loadError()
                  : _settingsForm(compact),
            ),
          ),
        );
      },
    );
  }

  Widget _loadError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Storefront settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.status_danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: Text(_error!)),
              TextButton.icon(
                onPressed: _loadSettings,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsForm(bool compact) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Storefront settings',
            style: TextStyle(
              color: AppColors.text_primary,
              fontSize: compact ? 22 : 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose what customers can see on your online store. Contact details are private until you add them here.',
            style: TextStyle(
              color: AppColors.text_secondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _section(
            'Store profile',
            'These details appear on your public storefront. Leave a contact field blank to keep it private.',
            [
              _field(
                'storeName',
                'Store name',
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a store name.'
                    : null,
              ),
              const SizedBox(height: 14),
              _field(
                'description',
                'Short description',
                hint: 'A few words about your shop',
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              if (compact) ...[
                _field(
                  'phone',
                  'Public phone number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                _field(
                  'email',
                  'Public email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                        ? null
                        : 'Enter a valid email address.';
                  },
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'phone',
                        'Public phone number',
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _field(
                        'email',
                        'Public email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          return RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(value)
                              ? null
                              : 'Enter a valid email address.';
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              _field('address', 'Public shop address'),
              const SizedBox(height: 14),
              if (compact)
                _field('county', 'County')
              else
                _field('county', 'County'),
              const SizedBox(height: 14),
              _field(
                'logoUrl',
                'Store logo URL (optional)',
                hint: 'https://…',
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final uri = Uri.tryParse(value);
                  return uri != null &&
                          uri.scheme == 'https' &&
                          uri.host.isNotEmpty
                      ? null
                      : 'Use a valid HTTPS image URL.';
                },
              ),
              const SizedBox(height: 14),
              _field(
                'openingHours',
                'Opening hours',
                hint: 'For example, Monday to Saturday, 8:00 am–6:00 pm',
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            'Delivery & pickup information',
            'Describe current arrangements for customers. This does not enable online checkout or calculate fees.',
            [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer delivery'),
                value: _deliveryEnabled,
                onChanged: (value) => setState(() => _deliveryEnabled = value),
              ),
              if (_deliveryEnabled) ...[
                const SizedBox(height: 8),
                _field(
                  'deliveryDetails',
                  'Delivery details',
                  hint: 'Areas served, timings, and any customer instructions',
                  maxLines: 4,
                ),
              ],
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer store pickup'),
                value: _pickupEnabled,
                onChanged: (value) => setState(() => _pickupEnabled = value),
              ),
              if (_pickupEnabled) ...[
                const SizedBox(height: 8),
                _field(
                  'pickupDetails',
                  'Pickup details',
                  hint: 'Collection location, hours, and instructions',
                  maxLines: 4,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _section(
            'Customer policies',
            'Only enter wording approved by your shop. Empty policies will be clearly marked as not provided.',
            [
              _field('policyDelivery', 'Delivery policy', maxLines: 5),
              const SizedBox(height: 14),
              _field('policyReturns', 'Returns & refunds policy', maxLines: 5),
              const SizedBox(height: 14),
              _field('policyPrivacy', 'Privacy policy', maxLines: 5),
              const SizedBox(height: 14),
              _field('policyTerms', 'Terms of sale', maxLines: 5),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.status_danger),
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveSettings,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save storefront settings'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Online ordering remains unavailable until checkout and verified payment are connected.',
            style: TextStyle(
              color: AppColors.text_tertiary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
