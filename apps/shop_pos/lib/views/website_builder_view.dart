import 'package:flutter/material.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';

class WebsiteBuilderView extends StatefulWidget {
  const WebsiteBuilderView({super.key, required this.state});

  final PosState state;

  @override
  State<WebsiteBuilderView> createState() => _WebsiteBuilderViewState();
}

class _WebsiteBuilderViewState extends State<WebsiteBuilderView> {
  static const _industries = <String>[
    'General retail',
    'Fashion & footwear',
    'Electronics',
    'Grocery & convenience',
    'Home & furniture',
    'Beauty & personal care',
    'Health & pharmacy',
    'Hardware & building',
    'Food service',
    'Automotive & parts',
    'Other',
  ];

  String _industry = _industries.first;

  @override
  Widget build(BuildContext context) {
    final sections = <({IconData icon, String title, String detail})>[
      (
        icon: Icons.storefront_outlined,
        title: 'Store profile',
        detail: 'Shop name, brand, contact details, and public URL',
      ),
      (
        icon: Icons.category_outlined,
        title: 'Industry & catalog',
        detail: 'Choose product attributes and stock tracking for your trade',
      ),
      (
        icon: Icons.inventory_2_outlined,
        title: 'Published products',
        detail: 'Select POS products and keep online availability in sync',
      ),
      (
        icon: Icons.local_shipping_outlined,
        title: 'Delivery & pickup',
        detail: 'Set collection options, delivery areas, and fees',
      ),
      (
        icon: Icons.policy_outlined,
        title: 'Policies & footer',
        detail: 'Add your approved returns, delivery, privacy, and terms copy',
      ),
      (
        icon: Icons.payments_outlined,
        title: 'Checkout',
        detail: 'Connect verified M-Pesa checkout before accepting payment',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        return SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 16 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StoreStatus(shopName: widget.state.shopName),
                  const SizedBox(height: 20),
                  if (narrow)
                    Column(
                      children: [
                        _industrySetup(),
                        const SizedBox(height: 16),
                        _setupChecklist(sections),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _industrySetup()),
                        const SizedBox(width: 18),
                        Expanded(flex: 6, child: _setupChecklist(sections)),
                      ],
                    ),
                  const SizedBox(height: 18),
                  _ScaffoldNotice(
                    icon: Icons.info_outline,
                    message:
                        'This setup is a scaffold. Saving settings, publishing products, and accepting orders will be enabled when the shop API and payment integrations are connected.',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _industrySetup() {
    return _Panel(
      title: 'Start with your kind of business',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We will tailor product details and stock workflows to your industry. You can change this later.',
            style: TextStyle(
              color: AppColors.text_secondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _industry,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Business industry',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final industry in _industries)
                DropdownMenuItem(
                  value: industry,
                  child: Text(industry, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _industry = value);
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Selected: $_industry',
            style: const TextStyle(
              color: AppColors.accent_primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Industry templates will suggest fields such as size and colour for fashion, or model and warranty for electronics. Products remain in the shared POS catalog.',
            style: TextStyle(
              color: AppColors.text_tertiary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _setupChecklist(
    List<({IconData icon, String title, String detail})> sections,
  ) {
    return _Panel(
      title: 'Store launch checklist',
      child: Column(
        children: [
          for (final section in sections)
            _ChecklistRow(
              icon: section.icon,
              title: section.title,
              detail: section.detail,
            ),
        ],
      ),
    );
  }
}

class _StoreStatus extends StatelessWidget {
  const _StoreStatus({required this.shopName});

  final String shopName;

  @override
  Widget build(BuildContext context) {
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, size: 9, color: AppColors.status_warning),
        const SizedBox(width: 8),
        const Text(
          'Not published',
          style: TextStyle(
            color: AppColors.text_secondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            shopName.isEmpty ? 'Your online store' : shopName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text_primary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 16),
        status,
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent_primary, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text_primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.text_tertiary,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Setup needed',
                  style: TextStyle(
                    color: AppColors.text_tertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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

class _ScaffoldNotice extends StatelessWidget {
  const _ScaffoldNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg_subtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.text_secondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.text_secondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
