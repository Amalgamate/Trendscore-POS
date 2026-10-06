import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';
import 'widgets/image_upload_widget.dart';

const _categoryMeta = {
  'Dairy':     {'color': Color(0xFFEFF6FF), 'icon': Icons.egg_outlined},
  'Bakery':    {'color': Color(0xFFFFFBEB), 'icon': Icons.bakery_dining},
  'Beverages': {'color': Color(0xFFF0FDF4), 'icon': Icons.local_drink_outlined},
  'Produce':   {'color': Color(0xFFF0FDF4), 'icon': Icons.eco_outlined},
  'Snacks':    {'color': Color(0xFFFFF7ED), 'icon': Icons.fastfood_outlined},
  'Household': {'color': Color(0xFFF5F3FF), 'icon': Icons.home_outlined},
  'Grains':    {'color': Color(0xFFFEFCE8), 'icon': Icons.grass_outlined},
  'Health':    {'color': Color(0xFFFFEFF2), 'icon': Icons.health_and_safety_outlined},
  'Cleaning':  {'color': Color(0xFFEEF2FF), 'icon': Icons.cleaning_services_outlined},
  'Other':     {'color': Color(0xFFF8FAFC), 'icon': Icons.inventory_2_outlined},
};

Color _catColor(String cat) =>
    (_categoryMeta[cat]?['color'] as Color?) ?? const Color(0xFFF8FAFC);
IconData _catIcon(String cat) =>
    (_categoryMeta[cat]?['icon'] as IconData?) ?? Icons.inventory_2_outlined;

class InventoryView extends StatefulWidget {
  const InventoryView({super.key, required this.state});
  final PosState state;

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  String _category = 'All';
  String _stockFilter = 'All';
  bool _showInactive = false;
  final _search = TextEditingController();
  PosProduct? _selectedProduct;

  static const _allCategories = [
    'All', 'Dairy', 'Bakery', 'Beverages', 'Produce',
    'Snacks', 'Household', 'Grains', 'Health', 'Cleaning', 'Other',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PosProduct> get _filtered {
    return widget.state.products.where((p) {
      if (!_showInactive && !p.isActive) return false;
      if (_category != 'All' && p.category != _category) return false;
      if (_stockFilter == 'Low' && !p.isLowStock) return false;
      if (_stockFilter == 'Out' && !p.isOutOfStock) return false;
      final q = _search.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        return p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            (p.barcode?.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  void _showProductEditor({PosProduct? product}) {
    final isEdit = product != null;
    final categories = _allCategories.skip(1).toList();
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final skuCtrl = TextEditingController(text: product?.sku ?? '');
    final barcodeCtrl = TextEditingController(text: product?.barcode ?? '');
    final priceCtrl = TextEditingController(text: isEdit ? product.unitPrice.formatted : '');
    final costCtrl = TextEditingController(
        text: isEdit && product.costPrice != null ? product.costPrice!.formatted : '');
    final stockCtrl = TextEditingController(text: isEdit ? '${product.stock}' : '10');
    final lowStockCtrl = TextEditingController(
        text: isEdit ? '${product.lowStockThreshold}' : '10');
    final notesCtrl = TextEditingController(text: product?.notes ?? '');
    String category = product?.category ?? 'Dairy';
    String? imageBase64 = product?.imageBase64;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final screenWidth = MediaQuery.of(context).size.width;
          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: math.min(620.0, screenWidth - 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: AppColors.border_subtle),
                          left: BorderSide(color: AppColors.accent_primary, width: 4),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            isEdit ? 'Edit Product' : 'Add New Product',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text_primary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: AppColors.text_tertiary,
                        ),
                      ]),
                    ),

                    // ── Body (scrollable, max height 520) ───────────────
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 520),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _modalSectionLabel('PRODUCT IDENTITY'),
                            const SizedBox(height: 12),

                            // Image + Name/Category row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    ImageUploadWidget(
                                      currentBase64: imageBase64,
                                      size: 100,
                                      label: 'Product Photo',
                                      borderRadius: 10,
                                      onImagePicked: (b64) => setModal(() => imageBase64 = b64),
                                      onImageCleared: () => setModal(() => imageBase64 = null),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Click to upload a photo',
                                      style: TextStyle(fontSize: 10, color: AppColors.text_tertiary),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    children: [
                                      TextField(
                                        controller: nameCtrl,
                                        decoration: _modalInputDeco('Product Name *',
                                            hint: 'e.g. Fresh Whole Milk 1L'),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        value: category,
                                        decoration: _modalInputDeco('Category'),
                                        items: categories.map((c) => DropdownMenuItem(
                                          value: c,
                                          child: Row(children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _catColor(c),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.black12),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(_catIcon(c), size: 15, color: AppColors.text_tertiary),
                                            const SizedBox(width: 6),
                                            Text(c),
                                          ]),
                                        )).toList(),
                                        onChanged: (v) { if (v != null) setModal(() => category = v); },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // SKU + Barcode
                            Row(children: [
                              Expanded(child: TextField(
                                controller: skuCtrl,
                                decoration: _modalInputDeco('SKU Code', hint: 'e.g. MK-001'),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: TextField(
                                controller: barcodeCtrl,
                                decoration: _modalInputDeco('Barcode / EAN', hint: '6901234567890'),
                              )),
                            ]),

                            // ── PRICING ──────────────────────────────────
                            const SizedBox(height: 16),
                            _modalSectionLabel('PRICING'),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: TextField(
                                controller: priceCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _modalInputDeco('Selling Price (KES) *', hint: '0'),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: TextField(
                                controller: costCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _modalInputDeco('Cost Price (KES)', hint: '0 (optional)'),
                              )),
                            ]),
                            const SizedBox(height: 6),
                            const Text(
                              'Prices are VAT-inclusive',
                              style: TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                            ),

                            // ── STOCK SETTINGS ───────────────────────────
                            const SizedBox(height: 16),
                            _modalSectionLabel('STOCK SETTINGS'),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: TextField(
                                controller: stockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _modalInputDeco(
                                  isEdit ? 'Current Stock (units)' : 'Opening Stock (units)',
                                  hint: '0',
                                ),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: TextField(
                                controller: lowStockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _modalInputDeco('Low-Stock Alert At', hint: '10'),
                              )),
                            ]),

                            // ── NOTES ────────────────────────────────────
                            const SizedBox(height: 16),
                            _modalSectionLabel('NOTES'),
                            const SizedBox(height: 12),
                            TextField(
                              controller: notesCtrl,
                              maxLines: 2,
                              decoration: _modalInputDeco('Internal notes (optional)'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Footer ──────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: AppColors.border_subtle)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.text_secondary),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accent_primary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                ),
                                onPressed: () {
                                  final name = nameCtrl.text.trim();
                                  Money? parsedPrice;
                                  try {
                                    final clean = priceCtrl.text
                                        .replaceAll(',', '')
                                        .replaceAll('KES', '')
                                        .replaceAll('kes', '')
                                        .trim();
                                    if (clean.isNotEmpty) parsedPrice = Money.parse(clean);
                                  } catch (_) {}
                                  if (name.isEmpty ||
                                      parsedPrice == null ||
                                      parsedPrice.minorUnits <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Name and a valid price are required.')));
                                    return;
                                  }
                                  Money? parsedCost;
                                  try {
                                    final clean = costCtrl.text
                                        .replaceAll(',', '')
                                        .replaceAll('KES', '')
                                        .replaceAll('kes', '')
                                        .trim();
                                    if (clean.isNotEmpty) parsedCost = Money.parse(clean);
                                  } catch (_) {}
                                  final sku = skuCtrl.text.trim().isNotEmpty
                                      ? skuCtrl.text.trim()
                                      : 'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                                  final stock =
                                      int.tryParse(stockCtrl.text.trim()) ?? 0;
                                  final threshold =
                                      int.tryParse(lowStockCtrl.text.trim()) ?? 10;
                                  if (isEdit) {
                                    final updated = product.copyWith(
                                      name: name,
                                      sku: sku,
                                      barcode: barcodeCtrl.text.trim().isNotEmpty
                                          ? barcodeCtrl.text.trim()
                                          : null,
                                      category: category,
                                      unitPrice: parsedPrice,
                                      costPrice: parsedCost,
                                      stock: stock,
                                      lowStockThreshold: threshold,
                                      notes: notesCtrl.text.trim().isNotEmpty
                                          ? notesCtrl.text.trim()
                                          : null,
                                      imageBase64: imageBase64,
                                    );
                                    widget.state.updateProduct(updated);
                                    if (_selectedProduct?.id == product.id) {
                                      setState(() => _selectedProduct = updated);
                                    }
                                  } else {
                                    widget.state.addProduct(PosProduct(
                                      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
                                      name: name,
                                      sku: sku,
                                      barcode: barcodeCtrl.text.trim().isNotEmpty
                                          ? barcodeCtrl.text.trim()
                                          : null,
                                      category: category,
                                      unitPrice: parsedPrice,
                                      costPrice: parsedCost,
                                      stock: stock,
                                      lowStockThreshold: threshold,
                                      icon: _catIcon(category),
                                      tint: _catColor(category),
                                      notes: notesCtrl.text.trim().isNotEmpty
                                          ? notesCtrl.text.trim()
                                          : null,
                                      imageBase64: imageBase64,
                                    ));
                                  }
                                  setState(() {});
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(isEdit
                                          ? '"$name" updated.'
                                          : '"$name" added to catalog.')));
                                },
                                child: Text(isEdit ? 'Save Changes' : 'Add Product'),
                              ),
                            ],
                          ),
                          if (!isEdit) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Product will be added to the active catalogue',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.text_tertiary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showStockAdjustDialog(PosProduct product) {
    int delta = 5;
    String reason = 'Stock delivery / Purchase';
    final qtyCtrl = TextEditingController(text: '5');
    bool isAddition = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bg_subtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              const Icon(Icons.swap_vert_circle_outlined, color: AppColors.accent_primary),
              const SizedBox(width: 10),
              Expanded(child: Text('Adjust Stock: ${product.name}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            ]),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bg_subtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border_subtle),
                  ),
                  child: Row(children: [
                    const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.text_tertiary),
                    const SizedBox(width: 8),
                    const Text('Current stock: ',
                        style: TextStyle(fontSize: 13, color: AppColors.text_tertiary)),
                    Text('${product.stock} units',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _choiceButton(
                    label: '+ Receive Stock', icon: Icons.add_circle_outline,
                    selected: isAddition, color: AppColors.status_success,
                    onTap: () => setModal(() {
                      isAddition = true; reason = 'Stock delivery / Purchase';
                    }),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _choiceButton(
                    label: '\u2212 Spoilage / Loss', icon: Icons.remove_circle_outline,
                    selected: !isAddition, color: AppColors.status_danger,
                    onTap: () => setModal(() {
                      isAddition = false; reason = 'Damaged / Expired stock write-off';
                    }),
                  )),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDeco('Quantity to adjust'),
                  onChanged: (v) => delta = int.tryParse(v) ?? 0,
                ),
                const SizedBox(height: 10),
                Text(
                  'Result: ${isAddition ? product.stock + delta : (product.stock - delta < 0 ? 0 : product.stock - delta)} units',
                  style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: TextEditingController(text: reason),
                  decoration: _inputDeco('Reason / Reference'),
                  onChanged: (v) => reason = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: isAddition ? AppColors.status_success : AppColors.status_danger),
              onPressed: () {
                final amount = int.tryParse(qtyCtrl.text) ?? 0;
                if (amount > 0) {
                  widget.state.adjustStock(product.id, isAddition ? amount : -amount, reason);
                  setState(() {});
                }
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Stock updated for ${product.name}')));
              },
              child: const Text('Save Adjustment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(PosProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.status_danger),
          SizedBox(width: 8),
          Text('Delete Product?'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.text_secondary),
                children: [
                  const TextSpan(text: 'You are about to permanently delete '),
                  TextSpan(text: product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.text_primary)),
                  const TextSpan(text: ' from the catalog.'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.status_danger.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.status_danger.withAlpha(60)),
              ),
              child: const Text(
                'This action cannot be undone. Consider deactivating instead.',
                style: TextStyle(fontSize: 12, color: AppColors.status_danger),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.state.deleteProduct(product.id);
      if (_selectedProduct?.id == product.id) setState(() => _selectedProduct = null);
      else setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${product.name}" deleted.')));
    }
  }

  void _duplicateProduct(PosProduct p) {
    widget.state.addProduct(PosProduct(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Copy of ${p.name}', sku: '${p.sku}-COPY',
      category: p.category,
      unitPrice: p.unitPrice, costPrice: p.costPrice,
      stock: 0, lowStockThreshold: p.lowStockThreshold,
      icon: p.icon, tint: p.tint, notes: p.notes,
    ));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Duplicated "${p.name}" \u2014 update the copy.')));
  }

  void _toggleActive(PosProduct p) {
    final updated = p.copyWith(isActive: !p.isActive);
    widget.state.updateProduct(updated);
    if (_selectedProduct?.id == p.id) setState(() => _selectedProduct = updated);
    else setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        updated.isActive ? '"${p.name}" activated.' : '"${p.name}" deactivated.')));
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.state.products;
    final totalSkus = products.where((p) => p.isActive).length;
    final lowCount = products.where((p) => p.isActive && p.isLowStock).length;
    final outCount = products.where((p) => p.isActive && p.isOutOfStock).length;
    final valuation = products.where((p) => p.isActive)
        .fold(0, (sum, p) => sum + (p.unitPrice.minorUnits * p.stock));
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header row
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Inventory & Catalogue',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                              color: AppColors.text_primary)),
                      Text('Manage products, pricing, stock levels and catalogue settings',
                          style: TextStyle(fontSize: 13, color: AppColors.text_tertiary)),
                    ])),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_download_outlined, size: 17),
                      label: const Text('Export'),
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Add Product'),
                      onPressed: () => _showProductEditor(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent_primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // KPI cards
                  Row(children: [
                    _StatCard('Active SKUs', '$totalSkus items',
                        Icons.qr_code_2, AppColors.accent_primary),
                    const SizedBox(width: 10),
                    _StatCard('Stock Valuation', 'KES ${Money(valuation).formatted}',
                        Icons.account_balance_wallet_outlined, const Color(0xFF16A34A)),
                    const SizedBox(width: 10),
                    _StatCard('Low Stock', '$lowCount alerts',
                        Icons.trending_down_outlined, const Color(0xFFD97706)),
                    const SizedBox(width: 10),
                    _StatCard('Out of Stock', '$outCount SKUs',
                        Icons.remove_shopping_cart_outlined, AppColors.status_danger),
                  ]),
                  const SizedBox(height: 16),

                  // Toolbar
                  Row(children: [
                    Expanded(flex: 3, child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by name, SKU or barcode\u2026',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true, fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border_subtle),
                        ),
                      ),
                    )),
                    const SizedBox(width: 10),
                    ...[
                      ('All', 'All', AppColors.accent_primary),
                      ('Low', 'Low Stock', Color(0xFFD97706)),
                      ('Out', 'Out of Stock', AppColors.status_danger),
                    ].map((t) {
                      final sel = _stockFilter == t.$1;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: FilterChip(
                          label: Text(t.$2, style: TextStyle(fontSize: 12,
                              color: sel ? t.$3 : AppColors.text_secondary)),
                          selected: sel,
                          onSelected: (_) => setState(() => _stockFilter = t.$1),
                          selectedColor: (t.$3).withAlpha(20),
                          checkmarkColor: t.$3,
                        ),
                      );
                    }),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: Text('Show Inactive', style: TextStyle(fontSize: 12,
                          color: _showInactive ? AppColors.text_tertiary : AppColors.text_secondary)),
                      selected: _showInactive,
                      onSelected: (_) => setState(() => _showInactive = !_showInactive),
                      selectedColor: AppColors.bg_subtle,
                    ),
                  ]),
                  const SizedBox(height: 10),

                  // Category tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _allCategories.map((c) {
                        final sel = _category == c;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() => _category = c),
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: sel ? AppColors.accent_primary : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? AppColors.accent_primary : AppColors.border_subtle),
                              ),
                              child: Text(c, style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : AppColors.text_secondary,
                              )),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Product table
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border_subtle),
                      ),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.bg_subtle,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
                          ),
                          child: const Row(children: [
                            SizedBox(width: 48),
                            Expanded(flex: 4, child: Text('PRODUCT', style: _headerStyle)),
                            Expanded(flex: 2, child: Text('CATEGORY', style: _headerStyle)),
                            Expanded(flex: 2, child: Text('PRICE', style: _headerStyle)),
                            Expanded(flex: 2, child: Text('MARGIN', style: _headerStyle)),
                            Expanded(flex: 2, child: Text('STOCK', style: _headerStyle)),
                            SizedBox(width: 110),
                          ]),
                        ),
                        if (filtered.isEmpty)
                          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.border_subtle),
                            const SizedBox(height: 12),
                            const Text('No products match your filters',
                                style: TextStyle(color: AppColors.text_tertiary)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add a product'),
                              onPressed: () => _showProductEditor(),
                            ),
                          ])))
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: AppColors.border_subtle),
                              itemBuilder: (ctx, i) => _ProductRow(
                                product: filtered[i],
                                isSelected: _selectedProduct?.id == filtered[i].id,
                                onTap: () => setState(() {
                                  _selectedProduct = _selectedProduct?.id == filtered[i].id
                                      ? null : filtered[i];
                                }),
                                onEdit: () => _showProductEditor(product: filtered[i]),
                                onStockAdjust: () => _showStockAdjustDialog(filtered[i]),
                                onDuplicate: () => _duplicateProduct(filtered[i]),
                                onToggleActive: () => _toggleActive(filtered[i]),
                                onDelete: () => _confirmDelete(filtered[i]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${filtered.length} of ${products.length} products shown',
                        style: const TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                  ),
                ],
              ),
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(1.0, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
              return SlideTransition(position: slide, child: FadeTransition(opacity: animation, child: child));
            },
            child: _selectedProduct != null
                ? _ProductDetailPanel(
                    key: ValueKey(_selectedProduct!.id),
                    product: _selectedProduct!,
                    onEdit: () => _showProductEditor(product: _selectedProduct!),
                    onStockAdjust: () => _showStockAdjustDialog(_selectedProduct!),
                    onClose: () => setState(() => _selectedProduct = null),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── Product row ───────────────────────────────────────────────────────────
class _ProductRow extends StatefulWidget {
  const _ProductRow({
    required this.product, required this.isSelected, required this.onTap,
    required this.onEdit, required this.onStockAdjust,
    required this.onDuplicate, required this.onToggleActive, required this.onDelete,
  });
  final PosProduct product;
  final bool isSelected;
  final VoidCallback onTap, onEdit, onStockAdjust, onDuplicate, onToggleActive, onDelete;

  @override
  State<_ProductRow> createState() => _ProductRowState();
}

class _ProductRowState extends State<_ProductRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final inactive = !p.isActive;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: widget.isSelected
            ? AppColors.accent_primary.withAlpha(10)
            : (_hovered ? AppColors.bg_subtle : Colors.white),
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Opacity(
                opacity: inactive ? 0.4 : 1.0,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  child: p.imageBase64 != null && p.imageBase64!.isNotEmpty
                      ? Image.memory(
                          base64Decode(p.imageBase64!.split(',').last),
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Icon(p.icon, size: 18, color: AppColors.text_secondary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: Opacity(
                opacity: inactive ? 0.5 : 1.0,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(p.name,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                            color: AppColors.text_primary,
                            decoration: inactive ? TextDecoration.lineThrough : null),
                        overflow: TextOverflow.ellipsis)),
                    if (inactive) ...[
                      const SizedBox(width: 6),
                      _Badge('INACTIVE', const Color(0xFF9CA3AF), const Color(0xFFF3F4F6)),
                    ],
                  ]),
                  Text(p.sku, style: const TextStyle(fontSize: 10, fontFamily: 'monospace',
                      color: AppColors.text_tertiary)),
                ]),
              )),
              Expanded(flex: 2, child: Row(children: [
                Icon(_catIcon(p.category), size: 14, color: AppColors.text_tertiary),
                const SizedBox(width: 5),
                Text(p.category, style: const TextStyle(fontSize: 12, color: AppColors.text_secondary)),
              ])),
              Expanded(flex: 2, child: Text('KES ${p.unitPrice.formatted}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: p.marginPercent != null
                  ? Text('${p.marginPercent!.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: p.marginPercent! >= 20
                              ? AppColors.status_success
                              : (p.marginPercent! >= 0 ? const Color(0xFFD97706) : AppColors.status_danger)))
                  : const Text('\u2014', style: TextStyle(fontSize: 12, color: AppColors.text_tertiary))),
              Expanded(flex: 2, child: _StockBadge(p)),
              SizedBox(width: 110, child: (_hovered || widget.isSelected)
                  ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      _ActionIcon(icon: Icons.swap_vert_circle_outlined,
                          tooltip: 'Adjust Stock', color: AppColors.accent_primary,
                          onTap: widget.onStockAdjust),
                      _ActionIcon(icon: Icons.edit_outlined,
                          tooltip: 'Edit Product', color: AppColors.text_secondary,
                          onTap: widget.onEdit),
                      PopupMenuButton<String>(
                        iconSize: 18,
                        tooltip: 'More actions',
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (v) {
                          if (v == 'duplicate') widget.onDuplicate();
                          if (v == 'toggle') widget.onToggleActive();
                          if (v == 'delete') widget.onDelete();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'duplicate',
                              child: _menuRow(Icons.copy_outlined, 'Duplicate')),
                          PopupMenuItem(value: 'toggle',
                              child: _menuRow(
                                  p.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  p.isActive ? 'Deactivate' : 'Activate')),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: 'delete',
                              child: _menuRow(Icons.delete_outline, 'Delete',
                                  color: AppColors.status_danger)),
                        ],
                      ),
                    ])
                  : const SizedBox()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, {Color color = AppColors.text_primary}) =>
      Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ]);
}

// ─── Detail panel ─────────────────────────────────────────────────────────
class _ProductDetailPanel extends StatelessWidget {
  const _ProductDetailPanel({
    super.key,
    required this.product, required this.onEdit,
    required this.onStockAdjust, required this.onClose,
  });
  final PosProduct product;
  final VoidCallback onEdit, onStockAdjust, onClose;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppColors.border_subtle)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppColors.bg_subtle,
            border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
          ),
          child: Row(children: [
            const Text('Product Details',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                    color: AppColors.text_primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose, padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: AppColors.text_tertiary,
            ),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Column(children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: p.imageBase64 != null && p.imageBase64!.isNotEmpty
                    ? Image.memory(
                        base64Decode(p.imageBase64!.split(',').last),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Icon(p.icon, size: 32, color: AppColors.text_primary),
              ),
              const SizedBox(height: 10),
              Text(p.name, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppColors.text_primary)),
              const SizedBox(height: 4),
              Text(p.sku, style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: AppColors.text_tertiary)),
              const SizedBox(height: 6),
              _Badge(p.category, AppColors.accent_primary, AppColors.accent_primary.withAlpha(18)),
            ])),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            _DetailRow('Selling Price', 'KES ${p.unitPrice.formatted}'),
            if (p.costPrice != null) _DetailRow('Cost Price', 'KES ${p.costPrice!.formatted}'),
            if (p.marginPercent != null)
              _DetailRow('Gross Margin', '${p.marginPercent!.toStringAsFixed(1)}%',
                  valueColor: p.marginPercent! >= 20 ? AppColors.status_success : AppColors.status_danger),
            _DetailRow('Current Stock', '${p.stock} units',
                valueColor: p.isOutOfStock
                    ? AppColors.status_danger
                    : (p.isLowStock ? const Color(0xFFD97706) : AppColors.status_success)),
            _DetailRow('Alert Threshold', '\u2264 ${p.lowStockThreshold} units'),
            if (p.barcode != null) _DetailRow('Barcode', p.barcode!),
            _DetailRow('Status', p.isActive ? 'Active' : 'Inactive',
                valueColor: p.isActive ? AppColors.status_success : AppColors.text_tertiary),
            if (p.notes != null && p.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Notes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppColors.text_tertiary)),
              const SizedBox(height: 4),
              Text(p.notes!, style: const TextStyle(fontSize: 12, color: AppColors.text_secondary)),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Quick Actions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.text_tertiary)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              icon: const Icon(Icons.swap_vert_circle_outlined, size: 16),
              label: const Text('Adjust Stock'),
              onPressed: onStockAdjust,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Product'),
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent_primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )),
          ]),
        )),
      ]),
    );
  }
}

// ─── Shared helpers ────────────────────────────────────────────────────────
const _headerStyle = TextStyle(
  fontSize: 10, fontWeight: FontWeight.w700,
  letterSpacing: 0.8, color: AppColors.text_tertiary,
);

class _StatCard extends StatelessWidget {
  const _StatCard(this.title, this.value, this.icon, this.color);
  final String title, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withAlpha(18), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 10,
              color: AppColors.text_tertiary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ])),
      ]),
    ),
  );
}

class _StockBadge extends StatelessWidget {
  const _StockBadge(this.product);
  final PosProduct product;

  @override
  Widget build(BuildContext context) {
    final isOut = product.isOutOfStock;
    final isLow = product.isLowStock;
    final label = isOut ? 'OUT' : (isLow ? 'LOW' : 'OK');
    final color = isOut ? AppColors.status_danger
        : (isLow ? const Color(0xFFD97706) : AppColors.status_success);
    return Row(children: [
      Text('${product.stock}', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: color.withAlpha(18), borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
      ),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.textColor, this.bgColor);
  final String label;
  final Color textColor, bgColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700, color: textColor)),
  );
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tooltip,
      required this.color, required this.onTap});
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(6),
      child: Padding(padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 18, color: color)),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: valueColor ?? AppColors.text_primary)),
    ]),
  );
}

InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
  labelText: label, hintText: hint,
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
);

InputDecoration _modalInputDeco(String label, {String? hint}) => InputDecoration(
  labelText: label,
  hintText: hint,
  filled: true,
  fillColor: AppColors.bg_subtle,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.border_subtle),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.border_subtle),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.accent_primary, width: 1.5),
  ),
);

Widget _modalSectionLabel(String text) => Text(
  text,
  style: const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.text_tertiary,
    letterSpacing: 0.5,
  ),
);

Widget _choiceButton({
  required String label, required IconData icon,
  required bool selected, required Color color, required VoidCallback onTap,
}) =>
    InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.border_subtle,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: selected ? color : AppColors.text_tertiary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? color : AppColors.text_secondary)),
        ]),
      ),
    );
