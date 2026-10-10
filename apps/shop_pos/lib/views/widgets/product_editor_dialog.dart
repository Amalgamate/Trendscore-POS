import 'dart:convert';
import 'package:flutter/material.dart';
import '../../cart.dart';
import '../../pos_state.dart';
import '../../theme/tokens.dart';
import 'category_manager_dialog.dart';
import 'image_upload_widget.dart';

/// Opens the full-page add / edit product workspace (with optional variants).
///
/// Returns a short success message, or null if the user cancelled.
Future<String?> showProductEditor(
  BuildContext context,
  PosState state, {
  PosProduct? product,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => _ProductEditorPage(state: state, product: product),
    ),
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
  }) : labelCtrl = TextEditingController(text: label),
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

class _ProductEditorPage extends StatefulWidget {
  const _ProductEditorPage({required this.state, this.product});
  final PosState state;
  final PosProduct? product;

  @override
  State<_ProductEditorPage> createState() => _ProductEditorPageState();
}

class _ProductEditorPageState extends State<_ProductEditorPage> {
  late final bool isEdit;
  late final TextEditingController nameCtrl;
  late final TextEditingController skuCtrl;
  late final TextEditingController barcodeCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController costCtrl;
  late final TextEditingController stockCtrl;
  late final TextEditingController lowStockCtrl;
  late final TextEditingController notesCtrl;
  late final TextEditingController descriptionCtrl;

  late String category;
  String? imageBase64;
  String? imageError;
  String? formError;
  bool saving = false;
  late bool isPublished;

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
    category =
        p?.category ??
        (state.categories.isNotEmpty ? state.categories.first.name : 'Other');
    imageBase64 = siblings
        .map((v) => v.imageBase64)
        .firstWhere((i) => i != null && i.isNotEmpty, orElse: () => null);

    skuCtrl = TextEditingController(text: standalone ? (first?.sku ?? '') : '');
    barcodeCtrl = TextEditingController(
      text: standalone ? (first?.barcode ?? '') : '',
    );
    priceCtrl = TextEditingController(
      text: standalone && first != null ? first.unitPrice.formatted : '',
    );
    costCtrl = TextEditingController(
      text: standalone ? (first?.costPrice?.formatted ?? '') : '',
    );
    stockCtrl = TextEditingController(
      text: standalone && first != null ? '${first.stock}' : '10',
    );
    lowStockCtrl = TextEditingController(
      text: first != null ? '${first.lowStockThreshold}' : '10',
    );
    notesCtrl = TextEditingController(text: first?.notes ?? '');
    descriptionCtrl = TextEditingController(text: first?.description ?? '');
    isPublished = siblings.any((variant) => variant.isPublished);
    for (final controller in [nameCtrl, descriptionCtrl, priceCtrl]) {
      controller.addListener(_refreshPreview);
    }

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
      nameCtrl,
      skuCtrl,
      barcodeCtrl,
      priceCtrl,
      costCtrl,
      stockCtrl,
      lowStockCtrl,
      notesCtrl,
      descriptionCtrl,
    ]) {
      c.dispose();
    }
    for (final controller in [nameCtrl, descriptionCtrl, priceCtrl]) {
      controller.removeListener(_refreshPreview);
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

  String _slug(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Name of another product already using this SKU / barcode, or null.
  String? _clash(String value, {required bool barcode}) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    final own = {
      ...originalIds,
      if (widget.product != null) widget.product!.id,
    };
    for (final p in state.products) {
      if (own.contains(p.id)) continue;
      final other = barcode ? p.barcode : p.sku;
      if (other != null && other.trim().toLowerCase() == v)
        return p.displayName;
    }
    return null;
  }

  void _fail(String message) => setState(() => formError = message);

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

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
      taxRateBasisPoints:
          existing?.taxRateBasisPoints ?? defaultVatRateBasisPoints,
      isActive: existing?.isActive ?? true,
      isPublished: isPublished,
      publishedAt: isPublished ? existing?.publishedAt ?? DateTime.now() : null,
      notes: notes,
      imageBase64: imageBase64,
      description: descriptionCtrl.text.trim().isEmpty
          ? null
          : descriptionCtrl.text.trim(),
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
      if (skuClash != null)
        return _fail('SKU "$sku" is already used by $skuClash.');
      final barcodeClash = _clash(barcode, barcode: true);
      if (barcodeClash != null) {
        return _fail('Barcode "$barcode" is already used by $barcodeClash.');
      }

      items.add(
        _build(
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
        ),
      );
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
        if (label.isEmpty)
          return _fail('Variant $n needs a name, e.g. "500ml".');
        if (!labels.add(label.toLowerCase())) {
          return _fail('Two variants are both called "$label".');
        }
        final price = _money(d.priceCtrl.text);
        if (price == null || price.minorUnits <= 0) {
          return _fail('Variant "$label" needs a valid selling price.');
        }
        if (d.costCtrl.text.trim().isNotEmpty &&
            _money(d.costCtrl.text) == null) {
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
          return _fail(
            'SKU "$sku" is used by two variants. Give each its own.',
          );
        }
        final skuClash = _clash(sku, barcode: false);
        if (skuClash != null)
          return _fail('SKU "$sku" is already used by $skuClash.');
        final barcode = d.barcodeCtrl.text.trim();
        if (barcode.isNotEmpty) {
          if (!barcodes.add(barcode.toLowerCase())) {
            return _fail('Barcode "$barcode" is used by two variants.');
          }
          final bClash = _clash(barcode, barcode: true);
          if (bClash != null)
            return _fail('Barcode "$barcode" is already used by $bClash.');
        }

        items.add(
          _build(
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
          ),
        );
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
      final detail = error.toString().replaceFirst(
        RegExp(r'^(Exception|StateError): ?'),
        '',
      );
      setState(() {
        saving = false;
        formError = 'Product was not saved: $detail';
      });
      return;
    }

    if (!mounted) return;
    final suffix = hasVariants ? ' (${items.length} variants)' : '';
    Navigator.pop(
      context,
      isEdit ? '"$name" updated$suffix.' : '"$name" added to catalog$suffix.',
    );
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

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool number = false,
  }) => TextField(
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
                .map(
                  (c) => DropdownMenuItem(
                    value: c.name,
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border_subtle),
                          ),
                          child: Icon(
                            c.icon,
                            size: 13,
                            color: AppColors.text_secondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                )
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
                if (state.categoryByName(category) == null &&
                    state.categories.isNotEmpty) {
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
          color: hasVariants
              ? AppColors.accent_primary.withAlpha(90)
              : AppColors.border_subtle,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.layers_outlined,
            size: 20,
            color: hasVariants
                ? AppColors.accent_primary
                : AppColors.text_tertiary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This product has variants',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'Sizes, flavours, pack sizes\u2026 each variant has its own price, SKU, barcode and stock.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.text_tertiary,
                  ),
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
    final compact = MediaQuery.sizeOf(context).width < 700;
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
                  color: AppColors.accent_light,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent_primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: compact ? 1 : 3,
                child: _field(
                  d.labelCtrl,
                  'Variant name *',
                  hint: 'e.g. 500ml',
                ),
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
              Expanded(
                child: _field(
                  d.priceCtrl,
                  'Price (KES) *',
                  hint: '0',
                  number: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(d.stockCtrl, 'Stock', hint: '0', number: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (compact) ...[
            Row(
              children: [
                Expanded(
                  child: _field(d.skuCtrl, 'SKU', hint: 'auto if empty'),
                ),
                const SizedBox(width: 10),
                Expanded(child: _field(d.barcodeCtrl, 'Barcode / EAN')),
              ],
            ),
            const SizedBox(height: 10),
            _field(d.costCtrl, 'Cost (KES)', hint: 'optional', number: true),
          ] else
            Row(
              children: [
                const SizedBox(width: 34),
                Expanded(
                  child: _field(d.skuCtrl, 'SKU', hint: 'auto if empty'),
                ),
                const SizedBox(width: 10),
                Expanded(child: _field(d.barcodeCtrl, 'Barcode / EAN')),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    d.costCtrl,
                    'Cost (KES)',
                    hint: 'optional',
                    number: true,
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
        ],
      ),
    );
  }

  Widget _publicationControl() => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isPublished ? const Color(0xFFEAF7F2) : AppColors.bg_canvas,
      border: Border.all(
        color: isPublished ? const Color(0xFF9BD5BE) : AppColors.border_subtle,
      ),
    ),
    child: Row(
      children: [
        Icon(
          isPublished ? Icons.public : Icons.public_off_outlined,
          color: isPublished
              ? const Color(0xFF14734A)
              : AppColors.text_secondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPublished ? 'Available in web shop' : 'Hidden from web shop',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Only this product’s public details and availability are shown. Cost and exact stock stay private.',
                style: TextStyle(fontSize: 11, color: AppColors.text_secondary),
              ),
            ],
          ),
        ),
        Switch(
          value: isPublished,
          activeThumbColor: AppColors.accent_primary,
          onChanged: saving
              ? null
              : (value) => setState(() => isPublished = value),
        ),
      ],
    ),
  );

  Widget _storePreview() {
    final price = _money(priceCtrl.text);
    final image = imageBase64;
    return Container(
      width: 286,
      padding: const EdgeInsets.all(18),
      color: const Color(0xFFF2F5F3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CUSTOMER VIEW',
            style: TextStyle(
              color: AppColors.text_secondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 240,
            color: const Color(0xFFE4EAE6),
            clipBehavior: Clip.antiAlias,
            child: image == null
                ? const Icon(
                    Icons.inventory_2_outlined,
                    size: 52,
                    color: AppColors.text_tertiary,
                  )
                : Image.memory(
                    base64Decode(image.split(',').last),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            nameCtrl.text.trim().isEmpty
                ? 'Product name'
                : nameCtrl.text.trim(),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (hasVariants && drafts.isNotEmpty)
            Text(
              '${drafts.length} options',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text_secondary,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            price == null ? 'KES —' : 'KES ${price.formatted}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            descriptionCtrl.text.trim().isEmpty
                ? 'Your product description will appear here.'
                : descriptionCtrl.text.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.text_secondary,
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            color: isPublished
                ? AppColors.accent_primary
                : const Color(0xFFDFE5E2),
            child: Text(
              isPublished ? 'Available to browse' : 'Not published',
              style: TextStyle(
                color: isPublished ? Colors.white : AppColors.text_secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= 980;
    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back to products',
          icon: const Icon(Icons.arrow_back),
          onPressed: saving ? null : () => Navigator.pop(context),
        ),
        title: Text(isEdit ? 'Configure product' : 'Create product'),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEdit ? 'Save product' : 'Create product'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(wide ? 24 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (formError != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFFFFE8E8),
                          child: Text(
                            formError!,
                            style: const TextStyle(
                              color: AppColors.status_danger,
                            ),
                          ),
                        ),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: AppColors.border_subtle),
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(wide ? 24 : 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _section('PRODUCT IDENTITY'),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ImageUploadWidget(
                                      currentBase64: imageBase64,
                                      size: wide ? 116 : 82,
                                      label: 'Product photo',
                                      borderRadius: 4,
                                      onImagePicked: (image) =>
                                          setState(() => imageBase64 = image),
                                      onImageCleared: () =>
                                          setState(() => imageBase64 = null),
                                      onError: (message) => setState(
                                        () => imageError = message.isEmpty
                                            ? null
                                            : message,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          _field(
                                            nameCtrl,
                                            'Product name *',
                                            hint: 'e.g. Fresh Whole Milk',
                                          ),
                                          const SizedBox(height: 12),
                                          _categoryPicker(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (imageError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    imageError!,
                                    style: const TextStyle(
                                      color: AppColors.status_danger,
                                    ),
                                  ),
                                ],
                                _section('DESCRIPTION'),
                                TextField(
                                  controller: descriptionCtrl,
                                  maxLength: 5000,
                                  maxLines: 4,
                                  decoration: _deco(
                                    'Customer-facing description',
                                    hint: 'Describe the product accurately',
                                  ),
                                ),
                                _publicationControl(),
                                _variantsToggle(),
                                if (!hasVariants) ...[
                                  _section('PRODUCT CODES'),
                                  _responsivePair(
                                    _field(
                                      skuCtrl,
                                      'SKU code',
                                      hint: 'e.g. MK-001',
                                    ),
                                    _field(
                                      barcodeCtrl,
                                      'Barcode / EAN',
                                      hint: '6901234567890',
                                    ),
                                  ),
                                  _section('PRICING'),
                                  _responsivePair(
                                    _field(
                                      priceCtrl,
                                      'Selling price (KES) *',
                                      hint: '0',
                                      number: true,
                                    ),
                                    _field(
                                      costCtrl,
                                      'Cost price (KES)',
                                      hint: 'Optional',
                                      number: true,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Prices are VAT-inclusive.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.text_tertiary,
                                    ),
                                  ),
                                  _section('STOCK SETTINGS'),
                                  _responsivePair(
                                    _field(
                                      stockCtrl,
                                      isEdit
                                          ? 'Current stock'
                                          : 'Opening stock',
                                      hint: '0',
                                      number: true,
                                    ),
                                    _field(
                                      lowStockCtrl,
                                      'Low-stock alert at',
                                      hint: '10',
                                      number: true,
                                    ),
                                  ),
                                ] else ...[
                                  _section('VARIANTS'),
                                  for (var i = 0; i < drafts.length; i++)
                                    _variantCard(i, drafts[i]),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add variant'),
                                    onPressed: () => setState(
                                      () => drafts.add(_VariantDraft()),
                                    ),
                                  ),
                                  _section('STOCK ALERT (ALL VARIANTS)'),
                                  SizedBox(
                                    width: 260,
                                    child: _field(
                                      lowStockCtrl,
                                      'Low-stock alert at',
                                      hint: '10',
                                      number: true,
                                    ),
                                  ),
                                ],
                                _section('INTERNAL NOTES'),
                                TextField(
                                  controller: notesCtrl,
                                  maxLines: 2,
                                  decoration: _deco(
                                    'Notes only visible to staff',
                                  ),
                                ),
                                if (!wide) ...[
                                  _section('WEB SHOP PREVIEW'),
                                  SizedBox(height: 500, child: _storePreview()),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (wide) _storePreview(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _responsivePair(Widget first, Widget second) {
    if (MediaQuery.sizeOf(context).width < 700) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}
