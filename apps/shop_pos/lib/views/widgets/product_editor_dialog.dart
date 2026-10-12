import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../cart.dart';
import '../../pos_state.dart';
import '../../theme/tokens.dart';
import 'category_manager_dialog.dart';
import 'image_upload_widget.dart';

/// Opens the product editor as a full page within the existing app shell
/// (sidebar and app-bar remain visible). Returns a success message or null.
Future<String?> showProductEditor(
  BuildContext context,
  PosState state, {
  PosProduct? product,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, _) =>
          ProductEditorPage(state: state, product: product),
      transitionsBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero)
                    .animate(c),
            child: child,
          ),
        );
      },
    ),
  );
}

// ─── Variant draft ───────────────────────────────────────────────────────────

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

// ─── ProductEditorPage ───────────────────────────────────────────────────────

class ProductEditorPage extends StatefulWidget {
  const ProductEditorPage({super.key, required this.state, this.product});
  final PosState state;
  final PosProduct? product;

  @override
  State<ProductEditorPage> createState() => _ProductEditorPageState();
}

class _ProductEditorPageState extends State<ProductEditorPage> {
  late final bool isEdit;
  late final TextEditingController nameCtrl;
  late final TextEditingController descCtrl;
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
  bool hiddenFromWebShop = false;
  bool hasVariants = false;
  final List<_VariantDraft> drafts = [];

  String? existingGroupId;
  Set<String> originalIds = {};
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
    descCtrl = TextEditingController(text: '');
    category = p?.category ??
        (state.categories.isNotEmpty ? state.categories.first.name : 'Other');
    imageBase64 = siblings
        .map((v) => v.imageBase64)
        .firstWhere((i) => i != null && i.isNotEmpty, orElse: () => null);

    skuCtrl = TextEditingController(text: standalone ? (first?.sku ?? '') : '');
    barcodeCtrl =
        TextEditingController(text: standalone ? (first?.barcode ?? '') : '');
    priceCtrl = TextEditingController(
        text: standalone && first != null ? first.unitPrice.formatted : '');
    costCtrl = TextEditingController(
        text: standalone ? (first?.costPrice?.formatted ?? '') : '');
    stockCtrl = TextEditingController(
        text: standalone && first != null ? '${first.stock}' : '10');
    lowStockCtrl = TextEditingController(
        text: first != null ? '${first.lowStockThreshold}' : '10');
    notesCtrl = TextEditingController(text: first?.notes ?? '');

    singleId = (isEdit && standalone) ? p!.id : null;
    originalIds = siblings.map((v) => v.id).toSet();

    if (!standalone) {
      hasVariants = true;
      for (final v in siblings) {
        drafts.add(_VariantDraft.fromProduct(v));
      }
    }

    for (final c in [nameCtrl, priceCtrl, costCtrl, descCtrl]) {
      c.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      nameCtrl, descCtrl, skuCtrl, barcodeCtrl, priceCtrl,
      costCtrl, stockCtrl, lowStockCtrl, notesCtrl,
    ]) {
      c.dispose();
    }
    for (final d in drafts) {
      d.dispose();
    }
    super.dispose();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

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

  String? _clash(String value, {required bool barcode}) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    final own = {
      ...originalIds,
      if (widget.product != null) widget.product!.id
    };
    for (final p in state.products) {
      if (own.contains(p.id)) continue;
      final other = barcode ? p.barcode : p.sku;
      if (other != null && other.trim().toLowerCase() == v) return p.displayName;
    }
    return null;
  }

  void _fail(String msg) => setState(() => formError = msg);

  void _setHasVariants(bool on) {
    setState(() {
      formError = null;
      if (on) {
        drafts
          ..clear()
          ..add(_VariantDraft(
              id: singleId,
              sku: skuCtrl.text,
              barcode: barcodeCtrl.text,
              price: priceCtrl.text,
              cost: costCtrl.text,
              stock: stockCtrl.text))
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
    final existing =
        state.products.where((p) => p.id == id).firstOrNull;
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
      notes: notes,
      imageBase64: imageBase64,
      groupId: groupId,
      variantLabel: label,
    );
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => formError = null);
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return _fail('Product name is required.');
    final cat = state.categoryByName(category);
    if (cat == null) return _fail('Choose a category.');
    final threshold = int.tryParse(lowStockCtrl.text.trim()) ?? 10;
    final notes =
        notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
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
      final sc = _clash(sku, barcode: false);
      if (sc != null) return _fail('SKU "$sku" is already used by $sc.');
      final bc = _clash(barcode, barcode: true);
      if (bc != null) return _fail('Barcode "$barcode" is already used by $bc.');
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
      groupId =
          existingGroupId ?? (isEdit ? widget.product!.id : 'grp_$ts');
      final labels = <String>{};
      final skus = <String>{};
      final barcodes = <String>{};
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        final label = d.labelCtrl.text.trim();
        if (label.isEmpty) {
          return _fail('Variant ${i + 1} needs a name, e.g. "500ml".');
        }
        if (!labels.add(label.toLowerCase())) {
          return _fail('Two variants both called "$label".');
        }
        final price = _money(d.priceCtrl.text);
        if (price == null || price.minorUnits <= 0) {
          return _fail('Variant "$label" needs a valid price.');
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
          return _fail('SKU "$sku" used by two variants.');
        }
        final sc = _clash(sku, barcode: false);
        if (sc != null) return _fail('SKU "$sku" already used by $sc.');
        final barcode = d.barcodeCtrl.text.trim();
        if (barcode.isNotEmpty) {
          if (!barcodes.add(barcode.toLowerCase())) {
            return _fail('Barcode "$barcode" used by two variants.');
          }
          final bcc = _clash(barcode, barcode: true);
          if (bcc != null) {
            return _fail('Barcode "$barcode" already used by $bcc.');
          }
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
      final detail = error
          .toString()
          .replaceFirst(RegExp(r'^(Exception|StateError): ?'), '');
      setState(() {
        saving = false;
        formError = 'Not saved: $detail';
      });
      return;
    }
    if (!mounted) return;
    final suffix = hasVariants ? ' (${items.length} variants)' : '';
    Navigator.pop(
        context,
        isEdit
            ? '"$name" updated$suffix.'
            : '"$name" added to catalog$suffix.');
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.bg_surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border_subtle)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border_subtle)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
                color: AppColors.accent_primary, width: 1.5)),
      );

  Widget _field(TextEditingController c, String label,
          {String? hint, bool number = false}) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: _deco(label, hint: hint),
      );

  Widget _lbl(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.text_tertiary,
                letterSpacing: 0.8)));

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppColors.bg_surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border_subtle)),
        child: child);

  // ─── Cards ────────────────────────────────────────────────────────────────

  Widget _identityCard() => _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('PRODUCT IDENTITY'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              ImageUploadWidget(
                currentBase64: imageBase64,
                size: 90,
                label: 'Product photo',
                borderRadius: 10,
                onImagePicked: (b64) => setState(() => imageBase64 = b64),
                onImageCleared: () => setState(() => imageBase64 = null),
                onError: (msg) =>
                    setState(() => imageError = msg.isEmpty ? null : msg),
              ),
              const SizedBox(height: 5),
              const Text('Product photo',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.text_tertiary)),
            ]),
            const SizedBox(width: 16),
            Expanded(
                child: Column(children: [
              _field(nameCtrl, 'Product name *',
                  hint: 'e.g. Fresh Whole Milk 1L'),
              const SizedBox(height: 12),
              _categoryPicker(),
            ])),
          ]),
          if (imageError != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.error_outline,
                  size: 15, color: AppColors.status_danger),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(imageError!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.status_danger))),
            ]),
          ],
        ]));

  Widget _descCard() {
    final n = descCtrl.text.length;
    return _card(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('DESCRIPTION'),
          TextField(
              controller: descCtrl,
              maxLines: 4,
              maxLength: 5000,
              buildCounter: (_,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  const SizedBox.shrink(),
              decoration: _deco('Customer-facing description')),
          const SizedBox(height: 4),
          Align(
              alignment: Alignment.centerRight,
              child: Text('$n/5000',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text_tertiary))),
        ]));
  }

  Widget _webShopCard() => _card(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppColors.bg_subtle,
                  borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.visibility_off_outlined,
                  size: 17, color: AppColors.text_tertiary)),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Hidden from web shop',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text_primary)),
                SizedBox(height: 2),
                Text(
                    'Cost price and exact stock stay private. Only public details are shown.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.text_tertiary,
                        height: 1.4)),
              ])),
          Switch(
              value: hiddenFromWebShop,
              activeTrackColor: AppColors.accent_primary,
              activeThumbColor: Colors.white,
              onChanged: saving
                  ? null
                  : (v) => setState(() => hiddenFromWebShop = v)),
        ]));

  Widget _variantsCard() => _card(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: hasVariants
                      ? AppColors.accent_light
                      : AppColors.bg_subtle,
                  borderRadius: BorderRadius.circular(7)),
              child: Icon(Icons.layers_outlined,
                  size: 17,
                  color: hasVariants
                      ? AppColors.accent_primary
                      : AppColors.text_tertiary)),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('This product has variants',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text_primary)),
                SizedBox(height: 2),
                Text(
                    'Sizes, flavours, pack sizes\u2026 each has its own price, SKU and stock.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.text_tertiary,
                        height: 1.4)),
              ])),
          Switch(
              value: hasVariants,
              activeTrackColor: AppColors.accent_primary,
              activeThumbColor: Colors.white,
              onChanged: saving ? null : _setHasVariants),
        ]));

  Widget _codesCard() => _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('PRODUCT CODES'),
          Row(children: [
            Expanded(
                child:
                    _field(skuCtrl, 'SKU code', hint: 'e.g. MK-001')),
            const SizedBox(width: 12),
            Expanded(
                child: _field(barcodeCtrl, 'Barcode / EAN',
                    hint: '6901234567890')),
          ]),
        ]));

  Widget _pricingCard() {
    final price = _money(priceCtrl.text);
    final cost = _money(costCtrl.text);
    Widget pill;
    if (price != null &&
        price.minorUnits > 0 &&
        cost != null &&
        cost.minorUnits > 0) {
      final profit = price.minorUnits - cost.minorUnits;
      final margin = profit / price.minorUnits * 100;
      final pos = profit >= 0;
      final col =
          pos ? AppColors.status_success : AppColors.status_danger;
      pill = Row(children: [
        const Text('VAT-inclusive \u00b7 ',
            style: TextStyle(
                fontSize: 11, color: AppColors.text_tertiary)),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: pos
                  ? AppColors.status_success_light
                  : AppColors.status_danger_light,
              borderRadius: BorderRadius.circular(20)),
          child: Text(
              '${pos ? '+' : ''}${formatKES(profit / 100)} profit \u00b7 ${margin.toStringAsFixed(1)}% margin',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: col)),
        ),
      ]);
    } else {
      pill = const Text('Prices are VAT-inclusive',
          style: TextStyle(
              fontSize: 11, color: AppColors.text_tertiary));
    }
    return _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('PRICING'),
          Row(children: [
            Expanded(
                child: _field(priceCtrl, 'Selling price (KES) *',
                    hint: '0', number: true)),
            const SizedBox(width: 12),
            Expanded(
                child: _field(costCtrl, 'Cost price (KES)',
                    hint: 'Optional', number: true)),
          ]),
          const SizedBox(height: 8),
          pill,
        ]));
  }

  Widget _stockCard() => _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('STOCK'),
          Row(children: [
            Expanded(
                child: _field(
                    stockCtrl,
                    isEdit
                        ? 'Current stock (units)'
                        : 'Opening stock (units)',
                    hint: '0',
                    number: true)),
            const SizedBox(width: 12),
            Expanded(
                child: _field(lowStockCtrl, 'Low-stock alert at',
                    hint: '10', number: true)),
          ]),
          const SizedBox(height: 8),
          const Text(
              'You will be alerted when stock falls at or below the threshold.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.text_tertiary)),
        ]));

  Widget _notesCard() => _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('INTERNAL NOTES'),
          TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: _deco('Staff-only notes (optional)')),
        ]));

  Widget _variantRow(int i, _VariantDraft d) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.bg_canvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border_subtle)),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.accent_light,
                    shape: BoxShape.circle),
                child: Text('${i + 1}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent_primary))),
            const SizedBox(width: 10),
            Expanded(
                flex: 3,
                child: _field(d.labelCtrl, 'Variant name *',
                    hint: 'e.g. 500ml')),
            const SizedBox(width: 8),
            Expanded(
                flex: 2,
                child: _field(d.priceCtrl, 'Price (KES) *',
                    hint: '0', number: true)),
            const SizedBox(width: 8),
            Expanded(
                flex: 2,
                child: _field(d.stockCtrl, 'Stock',
                    hint: '0', number: true)),
            IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.status_danger,
                onPressed: drafts.length <= 1
                    ? null
                    : () => setState(
                        () => drafts.removeAt(i).dispose())),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 32),
            Expanded(
                child:
                    _field(d.skuCtrl, 'SKU', hint: 'auto if empty')),
            const SizedBox(width: 8),
            Expanded(child: _field(d.barcodeCtrl, 'Barcode / EAN')),
            const SizedBox(width: 8),
            Expanded(
                child: _field(d.costCtrl, 'Cost (KES)',
                    hint: 'optional', number: true)),
            const SizedBox(width: 38),
          ]),
        ]));

  Widget _variantsSection() => _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _lbl('VARIANTS'),
          for (var i = 0; i < drafts.length; i++) _variantRow(i, drafts[i]),
          OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add variant'),
              onPressed: () => setState(() => drafts.add(_VariantDraft())),
              style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          const Text(
              'Prices VAT-inclusive. Each variant is sold and counted independently.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.text_tertiary)),
          const SizedBox(height: 14),
          _lbl('LOW-STOCK ALERT (ALL VARIANTS)'),
          SizedBox(
              width: 240,
              child: _field(lowStockCtrl,
                  'Alert when stock at or below',
                  hint: '10',
                  number: true)),
        ]));

  // ─── Category picker ──────────────────────────────────────────────────────

  Widget _categoryPicker() {
    final names = state.categories.map((c) => c.name).toList();
    final value = names.contains(category) ? category : null;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
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
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: c.color,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: AppColors.border_subtle)),
                        child: Icon(c.icon,
                            size: 11,
                            color: AppColors.text_secondary)),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(c.name,
                            overflow: TextOverflow.ellipsis)),
                  ]),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => category = v);
        },
      )),
      const SizedBox(width: 6),
      Tooltip(
          message: 'Add or edit categories',
          child: IconButton.outlined(
            icon: const Icon(Icons.tune, size: 17),
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
          )),
    ]);
  }

  // ─── Customer-view sidebar ───────────────────────────────────────────────

  Widget _previewSidebar() {
    final cat = state.categoryByName(category);
    final priceM = _money(priceCtrl.text);
    final priceStr =
        priceM != null ? 'KES ${priceM.formatted}' : '\u2014';
    final pName = nameCtrl.text.trim().isNotEmpty
        ? nameCtrl.text.trim()
        : 'Product name';
    final desc = descCtrl.text.trim();
    final catCol = cat?.color ?? AppColors.border_strong;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      const Text('CUSTOMER VIEW',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.text_tertiary,
              letterSpacing: 0.8)),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border_subtle),
            boxShadow: AppShadow.md),
        clipBehavior: Clip.antiAlias,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                  color: AppColors.bg_subtle,
                  child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.image_outlined,
                        size: 34, color: AppColors.border_strong),
                    SizedBox(height: 6),
                    Text('No photo',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.text_tertiary)),
                  ]))),
          Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (cat != null)
                  Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: catCol.withAlpha(30),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Icon(cat.icon, size: 10, color: catCol),
                        const SizedBox(width: 4),
                        Text(cat.name,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: catCol)),
                      ])),
                Text(pName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text_primary,
                        height: 1.3)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(desc,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text_tertiary,
                          height: 1.5)),
                ],
                const SizedBox(height: 10),
                Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                  Text(priceStr,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent_primary)),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.status_success_light,
                          borderRadius: BorderRadius.circular(20)),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Icon(Icons.circle,
                            size: 6,
                            color: AppColors.status_success),
                        SizedBox(width: 4),
                        Text('In stock',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.status_success)),
                      ])),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                AppColors.accent_primary,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10)),
                        onPressed: null,
                        child: const Text('Add to cart',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    FontWeight.w600)))),
              ])),
        ]),
      ),
      const SizedBox(height: 12),
      AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: hiddenFromWebShop
                  ? AppColors.status_warning_light
                  : AppColors.status_success_light,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: hiddenFromWebShop
                      ? AppColors.status_warning.withAlpha(80)
                      : AppColors.status_success.withAlpha(80))),
          child: Row(children: [
            Icon(
                hiddenFromWebShop
                    ? Icons.visibility_off_outlined
                    : Icons.check_circle_outline,
                size: 16,
                color: hiddenFromWebShop
                    ? AppColors.status_warning
                    : AppColors.status_success),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    hiddenFromWebShop
                        ? 'Hidden from your web shop.'
                        : 'Visible in your web shop.',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: hiddenFromWebShop
                            ? AppColors.status_warning
                            : AppColors.status_success))),
          ])),
    ]);
  }

  // ─── Left column ─────────────────────────────────────────────────────────

  Widget _leftCol() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _identityCard(),
        _descCard(),
        _webShopCard(),
        _variantsCard(),
        if (!hasVariants) ...[_codesCard(), _pricingCard(), _stockCard()]
        else _variantsSection(),
        _notesCard(),
      ]);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= 1000;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg_surface,
        elevation: 0,
        titleSpacing: 0,
        title: Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Products'),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.text_secondary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8)),
            onPressed:
                saving ? null : () => Navigator.pop(context),
          ),
          Container(
              width: 1,
              height: 20,
              color: AppColors.border_subtle,
              margin:
                  const EdgeInsets.symmetric(horizontal: 4)),
          const SizedBox(width: 12),
          Text(
              isEdit ? 'Edit product' : 'Create product',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text_primary)),
        ]),
        actions: [
          if (formError != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                const Icon(Icons.error_outline,
                    size: 15, color: AppColors.status_danger),
                const SizedBox(width: 6),
                ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 300),
                    child: Text(formError!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.status_danger))),
              ])),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent_primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10)),
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : Text(
                      isEdit
                          ? 'Save changes'
                          : 'Create product',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
            horizontal: wide
                ? math.max(24.0, (screen.width - 1000) / 2)
                : 16,
            vertical: 20),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _leftCol()),
                  const SizedBox(width: 20),
                  SizedBox(
                      width: 260,
                      child: _previewSidebar()),
                ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _previewSidebar(),
                  const SizedBox(height: 20),
                  _leftCol(),
                ]),
      ),
    );
  }
}
