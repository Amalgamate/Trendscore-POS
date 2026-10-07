import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../cart.dart';
import '../../pos_state.dart';
import '../../theme/tokens.dart';
import 'category_manager_dialog.dart';
import 'image_upload_widget.dart';

/// Opens the add / edit product dialog (with optional variants).
///
/// Returns a short success message, or null if the user cancelled.
Future<String?> showProductEditor(
  BuildContext context,
  PosState state, {
  PosProduct? product,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductEditorDialog(state: state, product: product),
  );
}

/// Text controllers for one variant row in the editor.
class _VariantDraft {
  _VariantDraft({
    this.id,
    String label = '',
    String sku = '',
    String barcode = '',
    String price = '',
    String cost = '',
    String stock = '0',
  })  : labelCtrl = TextEditingController(text: label),
        skuCtrl = TextEditingController(text: sku),
        barcodeCtrl = TextEditingController(text: barcode),
        priceCtrl = TextEditingController(text: price),
        costCtrl = TextEditingController(text: cost),
        stockCtrl = TextEditingController(text: stock);

  factory _VariantDraft.fromProduct(PosProduct p) => _VariantDraft(
        id: p.id,
        label: p.variantLabel ?? '',
        sku: p.sku,
        barcode: p.barcode ?? '',
        price: p.unitPrice.formatted,
        cost: p.costPrice?.formatted ?? '',
        stock: '${p.stock}',
      );

  /// Existing product id, or null for a variant that has not been saved yet.
  final String? id;
  final TextEditingController labelCtrl;
  final TextEditingController skuCtrl;
  final TextEditingController barcodeCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController costCtrl;
  final TextEditingController stockCtrl;

  void dispose() {
    labelCtrl.dispose();
    skuCtrl.dispose();
    barcodeCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    stockCtrl.dispose();
  }
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({required this.state, this.product});
  final PosState state;
  final PosProduct? product;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final bool isEdit;
  late final TextEditingController nameCtrl;
  late final TextEditingController skuCtrl;
  late final TextEditingController barcodeCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController costCtrl;
  late final TextEditingController stockCtrl;
  late final TextEditingController lowStockCtrl;
  late final TextEditingController notesCtrl;

  late String category;
  String? imageBase64;
  String? imageError;
  String? formError;
  bool saving = false;

  bool hasVariants = false;
  final List<_VariantDraft> drafts = [];

  /// Group this product belonged to when the dialog opened (null if standalone).
  String? existingGroupId;

  /// Ids of the active variants (or the one standalone product) at open time.
  Set<String> originalIds = {};

  /// Product id to reuse when saving in single-product mode.
  String? singleId;

  PosState get state => widget.state;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    isEdit = p != null;

    var siblings = <PosProduct>[];
    if (p != null) {
      siblings = state.variantsOf(p).where((v) => v.isActive).toList();
      if (siblings.isEmpty) siblings = [p];
    }
    final first = siblings.isEmpty ? null : siblings.first;
    existingGroupId = p?.groupId;
    final standalone = existingGroupId == null;

    nameCtrl = TextEditingController(text: p?.name ?? '');
    category = p?.category ??
        (state.categories.isNotEmpty ? state.categories.first.name : 'Other');
    imageBase64 = siblings
        .map((v) => v.imageBase64)
        .firstWhere((i) => i != null && i.isNotEmpty, orElse: () => null);

    skuCtrl = TextEditingController(text: standalone ? (first?.sku ?? '') : '');
    barcodeCtrl = TextEditingController(text: standalone ? (first?.barcode ?? '') : '');
    priceCtrl = TextEditingController(
        text: standalone && first != null ? first.unitPrice.formatted : '');
    costCtrl = TextEditingController(
        text: standalone ? (first?.costPrice?.formatted ?? '') : '');
    stockCtrl = TextEditingController(
        text: standalone && first != null ? '${first.stock}' : '10');
    lowStockCtrl =
        TextEditingController(text: first != null ? '${first.lowStockThreshold}' : '10');
    notesCtrl = TextEditingController(text: first?.notes ?? '');

    singleId = (isEdit && standalone) ? p!.id : null;
    originalIds = siblings.map((v) => v.id).toSet();

    if (!standalone) {
      hasVariants = true;
      for (final v in siblings) {
        drafts.add(_VariantDraft.fromProduct(v));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      nameCtrl, skuCtrl, barcodeCtrl, priceCtrl, costCtrl, stockCtrl, lowStockCtrl, notesCtrl,
    ]) {
      c.dispose();
    }
    for (final d in drafts) {
      d.dispose();
    }
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  Money? _money(String text) {
    final clean = text
        .replaceAll(',', '')
        .replaceAll(RegExp('kes', caseSensitive: false), '')
        .trim();
    if (clean.isEmpty) return null;
    try {
      return Money.parse(clean);
    } catch (_) {
      return null;
    }
  }

  String _slug(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  /// Name of another product already using this SKU / barcode, or null.
  String? _clash(String value, {required bool barcode}) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    final own = {...originalIds, if (widget.product != null) widget.product!.id};
    for (final p in state.products) {
      if (own.contains(p.id)) continue;
      final other = barcode ? p.barcode : p.sku;
      if (other != null && other.trim().toLowerCase() == v) return p.displayName;
    }
    return null;
  }

  void _fail(String message) => setState(() => formError = message);

  void _setHasVariants(bool on) {
    setState(() {
      formError = null;
      if (on) {
        final firstDraft = _VariantDraft(
          id: singleId,
          sku: skuCtrl.text,
          barcode: barcodeCtrl.text,
          price: priceCtrl.text,
          cost: costCtrl.text,
          stock: stockCtrl.text,
        );
        drafts
          ..clear()
          ..add(firstDraft)
          ..add(_VariantDraft());
      } else {
        if (drafts.isNotEmpty) {
          final f = drafts.first;
          skuCtrl.text = f.skuCtrl.text;
          barcodeCtrl.text = f.barcodeCtrl.text;
          priceCtrl.text = f.priceCtrl.text;
          costCtrl.text = f.costCtrl.text;
          stockCtrl.text = f.stockCtrl.text;
          singleId = f.id;
        }
        for (final d in drafts) {
          d.dispose();
        }
        drafts.clear();
      }
      hasVariants = on;
    });
  }

  PosProduct _build({
    required String id,
    required String name,
    required String sku,
    required String? barcode,
    required Money price,
    required Money? cost,
    required int stock,
    required int threshold,
    required PosCategory cat,
    required String? notes,
    required String? groupId,
    required String? label,
  }) {
    final existing = state.products.where((p) => p.id == id).firstOrNull;
    return PosProduct(
      id: id,
      name: name,
      sku: sku,
      barcode: (barcode == null || barcode.isEmpty) ? null : barcode,
      category: cat.name,
      unitPrice: price,
      costPrice: cost,
      stock: stock,
      lowStockThreshold: threshold,
      icon: cat.icon,
      tint: cat.color,
      taxRateBasisPoints: existing?.taxRateBasisPoints ?? defaultVatRateBasisPoints,
      isActive: existing?.isActive ?? true,
      notes: notes,
      imageBase64: imageBase64,
      groupId: groupId,
      variantLabel: label,
    );
  }

  // ─── Save ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => formError = null);

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return _fail('Product name is required.');
    final cat = state.categoryByName(category);
    if (cat == null) return _fail('Choose a category.');
    final threshold = int.tryParse(lowStockCtrl.text.trim()) ?? 10;
    final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
    final ts = DateTime.now().millisecondsSinceEpoch;

    final List<PosProduct> items = [];
    String? groupId;

    if (!hasVariants) {
      final price = _money(priceCtrl.text);
      if (price == null || price.minorUnits <= 0) {
        return _fail('Enter a valid selling price.');
      }
      if (costCtrl.text.trim().isNotEmpty && _money(costCtrl.text) == null) {
        return _fail('Cost price is not a valid amount.');
      }
      final sku = skuCtrl.text.trim().isNotEmpty
          ? skuCtrl.text.trim()
          : 'SKU-${ts.toString().substring(7)}';
      final barcode = barcodeCtrl.text.trim();
      final skuClash = _clash(sku, barcode: false);
      if (skuClash != null) return _fail('SKU "$sku" is already used by $skuClash.');
      final barcodeClash = _clash(barcode, barcode: true);
      if (barcodeClash != null) {
        return _fail('Barcode "$barcode" is already used by $barcodeClash.');
      }

      items.add(_build(
        id: singleId ?? 'prod_$ts',
        name: name,
        sku: sku,
        barcode: barcode,
        price: price,
        cost: _money(costCtrl.text),
        stock: int.tryParse(stockCtrl.text.trim()) ?? 0,
        threshold: threshold,
        cat: cat,
        notes: notes,
        groupId: null,
        label: null,
      ));
    } else {
      if (drafts.length < 2) {
        return _fail('Add at least two variants, or switch variants off.');
      }
      groupId = existingGroupId ?? (isEdit ? widget.product!.id : 'grp_$ts');

      final labels = <String>{};
      final skus = <String>{};
      final barcodes = <String>{};
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        final n = i + 1;
        final label = d.labelCtrl.text.trim();
        if (label.isEmpty) return _fail('Variant $n needs a name, e.g. "500ml".');
        if (!labels.add(label.toLowerCase())) {
          return _fail('Two variants are both called "$label".');
        }
        final price = _money(d.priceCtrl.text);
        if (price == null || price.minorUnits <= 0) {
          return _fail('Variant "$label" needs a valid selling price.');
        }
        if (d.costCtrl.text.trim().isNotEmpty && _money(d.costCtrl.text) == null) {
          return _fail('Variant "$label" has an invalid cost price.');
        }
        final stock = int.tryParse(d.stockCtrl.text.trim());
        if (stock == null || stock < 0) {
          return _fail('Variant "$label" needs a stock count (0 or more).');
        }
        var sku = d.skuCtrl.text.trim();
        if (sku.isEmpty) {
          sku = '${_slug(name)}-${_slug(label)}';
          if (sku.length > 40) sku = sku.substring(0, 40);
        }
        if (!skus.add(sku.toLowerCase())) {
          return _fail('SKU "$sku" is used by two variants. Give each its own.');
        }
        final skuClash = _clash(sku, barcode: false);
        if (skuClash != null) return _fail('SKU "$sku" is already used by $skuClash.');
        final barcode = d.barcodeCtrl.text.trim();
        if (barcode.isNotEmpty) {
          if (!barcodes.add(barcode.toLowerCase())) {
            return _fail('Barcode "$barcode" is used by two variants.');
          }
          final bClash = _clash(barcode, barcode: true);
          if (bClash != null) return _fail('Barcode "$barcode" is already used by $bClash.');
        }

        items.add(_build(
          id: d.id ?? 'prod_${ts}_$i',
          name: name,
          sku: sku,
          barcode: barcode,
          price: price,
          cost: _money(d.costCtrl.text),
          stock: stock,
          threshold: threshold,
          cat: cat,
          notes: notes,
          groupId: groupId,
          label: label,
        ));
      }
    }

    setState(() => saving = true);
    try {
      if (!hasVariants && existingGroupId == null) {
        await state.saveProduct(items.first, isNew: !isEdit);
      } else {
        await state.saveVariantGroup(
          groupId: groupId ?? existingGroupId!,
          variants: items,
          originalIds: originalIds,
        );
      }
    } catch (error) {
      if (!mounted) return;
      final detail = error.toString().replaceFirst(RegExp(r'^(Exception|StateError): ?'), '');
      setState(() {
        saving = false;
        formError = 'Product was not saved: $detail';
      });
      return;
    }

    if (!mounted) return;
    final suffix = hasVariants ? ' (${items.length} variants)' : '';
    Navigator.pop(context, isEdit ? '"$name" updated$suffix.' : '"$name" added to catalog$suffix.');
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.bg_subtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.text_tertiary,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _field(TextEditingController c, String label,
          {String? hint, bool number = false}) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: _deco(label, hint: hint),
      );

  Widget _categoryPicker() {
    final names = state.categories.map((c) => c.name).toList();
    final value = names.contains(category) ? category : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('$value|${names.join(',')}'),
            initialValue: value,
            isExpanded: true,
            decoration: _deco('Category'),
            items: state.categories
                .map((c) => DropdownMenuItem(
                      value: c.name,
                      child: Row(children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border_subtle),
                          ),
                          child: Icon(c.icon, size: 13, color: AppColors.text_secondary),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ]),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => category = v);
            },
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Add or edit categories',
          child: IconButton.outlined(
            icon: const Icon(Icons.tune, size: 18),
            onPressed: () async {
              await showCategoryManager(context, state);
              if (!mounted) return;
              setState(() {
                if (state.categoryByName(category) == null && state.categories.isNotEmpty) {
                  category = state.categories.first.name;
                }
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _variantsToggle() {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: hasVariants ? AppColors.accent_light : AppColors.bg_canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasVariants ? AppColors.accent_primary.withAlpha(90) : AppColors.border_subtle,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.layers_outlined,
              size: 20, color: hasVariants ? AppColors.accent_primary : AppColors.text_tertiary),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This product has variants',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                SizedBox(height: 2),
                Text(
                  'Sizes, flavours, pack sizes\u2026 each variant has its own price, SKU, barcode and stock.',
                  style: TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                ),
              ],
            ),
          ),
          Switch(
            value: hasVariants,
            activeThumbColor: AppColors.accent_primary,
            onChanged: saving ? null : _setHasVariants,
          ),
        ],
      ),
    );
  }

  Widget _variantCard(int index, _VariantDraft d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.accent_light, shape: BoxShape.circle),
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent_primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _field(d.labelCtrl, 'Variant name *', hint: 'e.g. 500ml'),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(d.priceCtrl, 'Price (KES) *', hint: '0', number: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(d.stockCtrl, 'Stock', hint: '0', number: true),
              ),
              IconButton(
                tooltip: 'Remove variant',
                icon: const Icon(Icons.delete_outline, size: 19),
                color: AppColors.status_danger,
                onPressed: drafts.length <= 1
                    ? null
                    : () => setState(() {
                          drafts.removeAt(index).dispose();
                        }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 34),
              Expanded(child: _field(d.skuCtrl, 'SKU', hint: 'auto if empty')),
              const SizedBox(width: 10),
              Expanded(child: _field(d.barcodeCtrl, 'Barcode / EAN')),
              const SizedBox(width: 10),
              Expanded(child: _field(d.costCtrl, 'Cost (KES)', hint: 'optional', number: true)),
              const SizedBox(width: 40),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(760.0, screen.width - 32);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
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
                          fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text_primary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: saving ? null : () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: AppColors.text_tertiary,
                  ),
                ]),
              ),

              // Body
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: math.max(260, screen.height * 0.68)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section('PRODUCT IDENTITY'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(children: [
                            ImageUploadWidget(
                              currentBase64: imageBase64,
                              size: 108,
                              label: 'Product Photo',
                              borderRadius: 10,
                              onImagePicked: (b64) => setState(() => imageBase64 = b64),
                              onImageCleared: () => setState(() => imageBase64 = null),
                              onError: (msg) => setState(() => imageError = msg.isEmpty ? null : msg),
                            ),
                            const SizedBox(height: 6),
                            const Text('Click to upload a photo',
                                style: TextStyle(fontSize: 10, color: AppColors.text_tertiary)),
                          ]),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(children: [
                              _field(nameCtrl, 'Product Name *', hint: 'e.g. Fresh Whole Milk'),
                              const SizedBox(height: 12),
                              _categoryPicker(),
                            ]),
                          ),
                        ],
                      ),
                      if (imageError != null) ...[
                        const SizedBox(height: 10),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.error_outline, size: 16, color: AppColors.status_danger),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(imageError!,
                                style: const TextStyle(fontSize: 12, color: AppColors.status_danger)),
                          ),
                        ]),
                      ],

                      _variantsToggle(),

                      if (!hasVariants) ...[
                        _section('CODES'),
                        Row(children: [
                          Expanded(child: _field(skuCtrl, 'SKU Code', hint: 'e.g. MK-001')),
                          const SizedBox(width: 12),
                          Expanded(child: _field(barcodeCtrl, 'Barcode / EAN', hint: '6901234567890')),
                        ]),
                        _section('PRICING'),
                        Row(children: [
                          Expanded(
                              child: _field(priceCtrl, 'Selling Price (KES) *', hint: '0', number: true)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _field(costCtrl, 'Cost Price (KES)', hint: '0 (optional)', number: true)),
                        ]),
                        const SizedBox(height: 6),
                        const Text('Prices are VAT-inclusive',
                            style: TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                        _section('STOCK SETTINGS'),
                        Row(children: [
                          Expanded(
                            child: _field(
                              stockCtrl,
                              isEdit ? 'Current Stock (units)' : 'Opening Stock (units)',
                              hint: '0',
                              number: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _field(lowStockCtrl, 'Low-Stock Alert At', hint: '10', number: true)),
                        ]),
                      ] else ...[
                        _section('VARIANTS'),
                        for (var i = 0; i < drafts.length; i++) _variantCard(i, drafts[i]),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add variant'),
                            onPressed: () => setState(() => drafts.add(_VariantDraft())),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Prices are VAT-inclusive. Each variant is sold, counted and receipted on its own.',
                          style: TextStyle(fontSize: 11, color: AppColors.text_tertiary),
                        ),
                        _section('STOCK ALERT (ALL VARIANTS)'),
                        SizedBox(
                          width: 260,
                          child: _field(lowStockCtrl, 'Low-Stock Alert At', hint: '10', number: true),
                        ),
                      ],

                      _section('NOTES'),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: _deco('Internal notes (optional)'),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border_subtle)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (formError != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.status_danger.withAlpha(15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.status_danger.withAlpha(70)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: AppColors.status_danger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(formError!,
                                  style: const TextStyle(fontSize: 12, color: AppColors.status_danger)),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving ? null : () => Navigator.pop(context),
                          style: TextButton.styleFrom(foregroundColor: AppColors.text_secondary),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent_primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: saving ? null : _save,
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(isEdit ? 'Save Changes' : 'Add Product'),
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
    );
  }
}
