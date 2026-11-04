import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';
import 'widgets/product_editor_dialog.dart';
import 'widgets/image_upload_widget.dart';
import '../shared/icons.dart';
import '../services/xlsx_exporter.dart';
import '../services/api_service.dart';
import '../services/day_end_slip.dart';
import '../services/stock_audit_print.dart';
import '../services/stock_audit_export.dart';
import '../units.dart' hide ProductUnitCatalogue;

const _categoryMeta = {
  'Dairy': {'color': Color(0xFFEFF6FF), 'icon': AppIcons.egg},
  'Bakery': {'color': Color(0xFFFFFBEB), 'icon': AppIcons.bakery},
  'Beverages': {'color': Color(0xFFF0FDF4), 'icon': AppIcons.drink},
  'Produce': {'color': Color(0xFFF0FDF4), 'icon': AppIcons.produce},
  'Snacks': {'color': Color(0xFFFFF7ED), 'icon': AppIcons.snack},
  'Household': {'color': Color(0xFFF5F3FF), 'icon': AppIcons.home},
  'Grains': {'color': Color(0xFFFEFCE8), 'icon': AppIcons.grain},
  'Health': {'color': Color(0xFFFFEFF2), 'icon': AppIcons.health},
  'Cleaning': {'color': Color(0xFFEEF2FF), 'icon': AppIcons.clean},
  'Other': {'color': Color(0xFFF8FAFC), 'icon': AppIcons.inventory},
};

Color _catColor(String cat) =>
    (_categoryMeta[cat]?['color'] as Color?) ?? const Color(0xFFF8FAFC);
IconData _catIcon(String cat) =>
    (_categoryMeta[cat]?['icon'] as IconData?) ?? AppIcons.inventory;

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

  bool get _canManageStock {
    final role = widget.state.currentLoggedInUser?.role;
    return role == null ||
        role == PosUserRole.owner ||
        role == PosUserRole.manager ||
        role == PosUserRole.stockClerk ||
        role == PosUserRole.superAdmin;
  }

  bool _requireStockManager() {
    if (_canManageStock) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Stock receiving, adjustments, counts and movement history require an Owner, Manager or Stock Clerk.',
        ),
      ),
    );
    return false;
  }

  PosProduct? _selectedProduct;

  static const _allCategories = [
    'All',
    'Dairy',
    'Bakery',
    'Beverages',
    'Produce',
    'Snacks',
    'Household',
    'Grains',
    'Health',
    'Cleaning',
    'Other',
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

  Future<void> _showProductEditor({PosProduct? product}) async {
    final message = await showProductEditor(
      context,
      widget.state,
      product: product,
    );
    if (!mounted || message == null) return;
    if (product != null) {
      _selectedProduct = widget.state.products
          .where((item) => item.id == product.id)
          .firstOrNull;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showProductEditorLegacy({PosProduct? product}) {
    final isEdit = product != null;
    final categories = _allCategories.skip(1).toList();
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final skuCtrl = TextEditingController(text: product?.sku ?? '');
    final barcodeCtrl = TextEditingController(text: product?.barcode ?? '');
    final priceCtrl = TextEditingController(
      text: isEdit ? product.unitPrice.formatted : '',
    );
    final costCtrl = TextEditingController(
      text: isEdit && product.costPrice != null
          ? product.costPrice!.formatted
          : '',
    );
    final stockCtrl = TextEditingController(
      text: isEdit ? '${product.stock}' : '10',
    );
    final lowStockCtrl = TextEditingController(
      text: isEdit ? '${product.lowStockThreshold}' : '10',
    );
    final notesCtrl = TextEditingController(text: product?.notes ?? '');
    String category = product?.category ?? 'Dairy';
    String? imageBase64 = product?.imageBase64;
    bool savingProduct = false;
    String? imageError;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final media = MediaQuery.of(context);
          final screenWidth = media.size.width;
          final isCompact = screenWidth < 600;
          final dialogWidth = math.min(
            620.0,
            screenWidth - (isCompact ? 32.0 : 80.0),
          );
          final availableHeight =
              media.size.height - media.viewInsets.bottom - 32;
          Widget pairedFields(Widget first, Widget second) {
            if (isCompact) {
              return Column(
                children: [first, const SizedBox(height: 12), second],
              );
            }
            return Row(
              children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: second),
              ],
            );
          }

          final photo = Column(
            children: [
              ImageUploadWidget(
                currentBase64: imageBase64,
                size: 100,
                label: 'Product Photo',
                borderRadius: 10,
                onImagePicked: (b64) => setModal(() => imageBase64 = b64),
                onImageCleared: () => setModal(() => imageBase64 = null),
                onError: (msg) =>
                    setModal(() => imageError = msg.isEmpty ? null : msg),
              ),
              const SizedBox(height: 6),
              Text(
                isCompact ? 'Tap to upload a photo' : 'Click to upload a photo',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.text_tertiary,
                ),
              ),
            ],
          );
          final identityFields = Column(
            children: [
              TextField(
                controller: nameCtrl,
                decoration: _modalInputDeco(
                  'Product Name *',
                  hint: 'e.g. Fresh Whole Milk 1L',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: _modalInputDeco('Category'),
                items: categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Row(
                          children: [
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
                            Icon(
                              _catIcon(c),
                              size: 15,
                              color: AppColors.text_tertiary,
                            ),
                            const SizedBox(width: 6),
                            Text(c),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setModal(() => category = v);
                },
              ),
            ],
          );
          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 40,
              vertical: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: dialogWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.min(680.0, availableHeight),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Header ──────────────────────────────────────────
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(color: AppColors.border_subtle),
                            left: BorderSide(
                              color: AppColors.accent_primary,
                              width: 4,
                            ),
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 16 : 24,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
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
                              icon: const Icon(AppIcons.close, size: 20),
                              onPressed: () => Navigator.pop(ctx),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: AppColors.text_tertiary,
                            ),
                          ],
                        ),
                      ),

                      // ── Body (scrollable, max height 520) ───────────────
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isCompact ? 16 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _modalSectionLabel('PRODUCT IDENTITY'),
                              const SizedBox(height: 12),

                              // Image + Name/Category row
                              if (isCompact)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    photo,
                                    const SizedBox(height: 14),
                                    identityFields,
                                  ],
                                )
                              else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    photo,
                                    const SizedBox(width: 16),
                                    Expanded(child: identityFields),
                                  ],
                                ),
                              if (imageError != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      AppIcons.error,
                                      size: 16,
                                      color: AppColors.status_danger,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        imageError!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.status_danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),

                              // SKU + Barcode
                              pairedFields(
                                TextField(
                                  controller: skuCtrl,
                                  decoration: _modalInputDeco(
                                    'SKU Code',
                                    hint: 'e.g. MK-001',
                                  ),
                                ),
                                TextField(
                                  controller: barcodeCtrl,
                                  decoration: _modalInputDeco(
                                    'Barcode / EAN',
                                    hint: '6901234567890',
                                  ),
                                ),
                              ),

                              // ── PRICING ──────────────────────────────────
                              const SizedBox(height: 16),
                              _modalSectionLabel('PRICING'),
                              const SizedBox(height: 12),
                              pairedFields(
                                TextField(
                                  controller: priceCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _modalInputDeco(
                                    'Selling Price (KES) *',
                                    hint: '0',
                                  ),
                                ),
                                TextField(
                                  controller: costCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _modalInputDeco(
                                    'Cost Price (KES)',
                                    hint: '0 (optional)',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Prices are VAT-inclusive',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.text_tertiary,
                                ),
                              ),

                              // ── STOCK SETTINGS ───────────────────────────
                              const SizedBox(height: 16),
                              _modalSectionLabel('STOCK SETTINGS'),
                              const SizedBox(height: 12),
                              pairedFields(
                                TextField(
                                  controller: stockCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _modalInputDeco(
                                    isEdit
                                        ? 'Current Stock (units)'
                                        : 'Opening Stock (units)',
                                    hint: '0',
                                  ),
                                ),
                                TextField(
                                  controller: lowStockCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _modalInputDeco(
                                    'Low-Stock Alert At',
                                    hint: '10',
                                  ),
                                ),
                              ),

                              // ── NOTES ────────────────────────────────────
                              const SizedBox(height: 16),
                              _modalSectionLabel('NOTES'),
                              const SizedBox(height: 12),
                              TextField(
                                controller: notesCtrl,
                                maxLines: 2,
                                decoration: _modalInputDeco(
                                  'Internal notes (optional)',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Footer ──────────────────────────────────────────
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 16 : 24,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: AppColors.border_subtle),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.text_secondary,
                                  ),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent_primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: savingProduct
                                      ? null
                                      : () async {
                                          final name = nameCtrl.text.trim();
                                          Money? parsedPrice;
                                          try {
                                            final clean = priceCtrl.text
                                                .replaceAll(',', '')
                                                .replaceAll('KES', '')
                                                .replaceAll('kes', '')
                                                .trim();
                                            if (clean.isNotEmpty)
                                              parsedPrice = Money.parse(clean);
                                          } catch (_) {}
                                          if (name.isEmpty ||
                                              parsedPrice == null ||
                                              parsedPrice.minorUnits <= 0) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Name and a valid price are required.',
                                                ),
                                              ),
                                            );
                                            return;
                                          }
                                          Money? parsedCost;
                                          try {
                                            final clean = costCtrl.text
                                                .replaceAll(',', '')
                                                .replaceAll('KES', '')
                                                .replaceAll('kes', '')
                                                .trim();
                                            if (clean.isNotEmpty)
                                              parsedCost = Money.parse(clean);
                                          } catch (_) {}
                                          final sku =
                                              skuCtrl.text.trim().isNotEmpty
                                              ? skuCtrl.text.trim()
                                              : 'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                                          final stock =
                                              int.tryParse(
                                                stockCtrl.text.trim(),
                                              ) ??
                                              0;
                                          final threshold =
                                              int.tryParse(
                                                lowStockCtrl.text.trim(),
                                              ) ??
                                              10;
                                          final savedProduct = isEdit
                                              ? product.copyWith(
                                                  name: name,
                                                  sku: sku,
                                                  barcode:
                                                      barcodeCtrl.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? barcodeCtrl.text.trim()
                                                      : null,
                                                  category: category,
                                                  unitPrice: parsedPrice,
                                                  costPrice: parsedCost,
                                                  stock: stock,
                                                  lowStockThreshold: threshold,
                                                  notes:
                                                      notesCtrl.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? notesCtrl.text.trim()
                                                      : null,
                                                  imageBase64: imageBase64,
                                                )
                                              : PosProduct(
                                                  id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
                                                  name: name,
                                                  sku: sku,
                                                  barcode:
                                                      barcodeCtrl.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? barcodeCtrl.text.trim()
                                                      : null,
                                                  category: category,
                                                  unitPrice: parsedPrice,
                                                  costPrice: parsedCost,
                                                  stock: stock,
                                                  lowStockThreshold: threshold,
                                                  icon: _catIcon(category),
                                                  tint: _catColor(category),
                                                  notes:
                                                      notesCtrl.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? notesCtrl.text.trim()
                                                      : null,
                                                  imageBase64: imageBase64,
                                                );
                                          setModal(() => savingProduct = true);
                                          try {
                                            await widget.state.saveProduct(
                                              savedProduct,
                                              isNew: !isEdit,
                                            );
                                          } catch (error) {
                                            if (!mounted || !ctx.mounted)
                                              return;
                                            setModal(
                                              () => savingProduct = false,
                                            );
                                            final detail = error
                                                .toString()
                                                .replaceFirst(
                                                  RegExp(r'^Exception: '),
                                                  '',
                                                );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Product was not saved: $detail',
                                                ),
                                                duration: const Duration(
                                                  seconds: 6,
                                                ),
                                              ),
                                            );
                                            return;
                                          }
                                          if (!mounted || !ctx.mounted) return;
                                          if (isEdit &&
                                              _selectedProduct?.id ==
                                                  product.id) {
                                            setState(
                                              () => _selectedProduct =
                                                  savedProduct,
                                            );
                                          }
                                          setState(() {});
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                isEdit
                                                    ? '"$name" updated.'
                                                    : '"$name" added to catalog.',
                                              ),
                                            ),
                                          );
                                        },
                                  child: savingProduct
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          isEdit
                                              ? 'Save Changes'
                                              : 'Add Product',
                                        ),
                                ),
                              ],
                            ),
                            if (!isEdit) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Product will be added to the active catalogue',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.text_tertiary,
                                ),
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportInventory({required bool excel}) async {
    final inventory = await ApiService.instance.getStockAuditList();
    if (inventory == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ApiService.instance.lastError ?? 'Could not load stock list.',
            ),
          ),
        );
      return;
    }
    final rows = buildStockAuditExportRows(inventory);
    final date = DateTime.now().toIso8601String().substring(0, 10);
    try {
      final bytes = excel
          ? encodeXlsx([XlsxSheet('Stock Audit', rows)])
          : buildStockAuditCsvBytes(rows);
      await FilePicker.saveFile(
        dialogTitle: 'Save inventory stock audit',
        fileName: 'guta_gala_stock_$date.${excel ? 'xlsx' : 'csv'}',
        type: FileType.custom,
        allowedExtensions: [excel ? 'xlsx' : 'csv'],
        bytes: bytes,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export stock list: $error')),
        );
    }
  }

  Future<void> _printStockAudit() async {
    final inventory = await ApiService.instance.getStockAuditList();
    if (inventory == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ApiService.instance.lastError ?? 'Could not load stock list.',
            ),
          ),
        );
      }
      return;
    }
    final html = buildStockAuditHtml(
      shopName: widget.state.shopName,
      printedAt: DateTime.now(),
      products: inventory,
    );
    final opened = await printDayEndSlip(html);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Stock audit opened in the print dialog.'
              : 'Printing is available in the web POS; this device has no print service.',
        ),
      ),
    );
  }

  Future<void> _showStockAuditList() async {
    final inventory = await ApiService.instance.getStockAuditList();
    if (!mounted) return;
    if (inventory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.instance.lastError ?? 'Could not load stock list.',
          ),
        ),
      );
      return;
    }
    var search = '';
    var selectedCategory = 'All';
    var sortColumn = 'name';
    var ascending = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final categories =
              inventory
                  .map((item) => item['category'] as String? ?? 'Other')
                  .toSet()
                  .toList()
                ..sort();
          final query = search.trim().toLowerCase();
          final visible = inventory.where((item) {
            final name = '${item['name'] ?? ''} ${item['sku'] ?? ''}'
                .toLowerCase();
            final category = item['category'] as String? ?? 'Other';
            return (selectedCategory == 'All' ||
                    category == selectedCategory) &&
                (query.isEmpty || name.contains(query));
          }).toList();
          visible.sort((a, b) {
            final left = a[sortColumn];
            final right = b[sortColumn];
            final comparison = left is num && right is num
                ? left.compareTo(right)
                : '${left ?? ''}'.toLowerCase().compareTo(
                    '${right ?? ''}'.toLowerCase(),
                  );
            return ascending ? comparison : -comparison;
          });
          final costTotal = visible.fold<double>(
            0,
            (sum, row) => sum + ((row['valueAtCost'] as num?)?.toDouble() ?? 0),
          );
          final retailTotal = visible.fold<double>(
            0,
            (sum, row) =>
                sum + ((row['valueAtSellingPrice'] as num?)?.toDouble() ?? 0),
          );
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 1180,
              height: 720,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stock audit · ${widget.state.shopName}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Cost price and stock valuation are visible to all shop roles.',
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search name or SKU',
                            ),
                            onChanged: (value) =>
                                setDialogState(() => search = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedCategory,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'All',
                                child: Text('All categories'),
                              ),
                              ...categories.map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              ),
                            ],
                            onChanged: (value) => setDialogState(
                              () => selectedCategory = value ?? 'All',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${visible.length} products'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              sortAscending: ascending,
                              sortColumnIndex: switch (sortColumn) {
                                'name' => 0,
                                'category' => 1,
                                'quantity' => 2,
                                'costPrice' => 3,
                                'valueAtCost' => 4,
                                'valueAtSellingPrice' => 5,
                                _ => null,
                              },
                              columns: [
                                DataColumn(
                                  label: const Text('Product'),
                                  onSort: (_, __) => setDialogState(() {
                                    if (sortColumn == 'name')
                                      ascending = !ascending;
                                    sortColumn = 'name';
                                  }),
                                ),
                                DataColumn(
                                  label: const Text('Category'),
                                  onSort: (_, __) => setDialogState(() {
                                    if (sortColumn == 'category')
                                      ascending = !ascending;
                                    sortColumn = 'category';
                                  }),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text('Available stock'),
                                  onSort: (_, __) => setDialogState(() {
                                    if (sortColumn == 'quantity')
                                      ascending = !ascending;
                                    sortColumn = 'quantity';
                                  }),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text('Cost / unit'),
                                  onSort: (_, __) => setDialogState(() {
                                    if (sortColumn == 'costPrice')
                                      ascending = !ascending;
                                    sortColumn = 'costPrice';
                                  }),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text('Value at cost'),
                                  onSort: (_, __) => setDialogState(() {
                                    if (sortColumn == 'valueAtCost')
                                      ascending = !ascending;
                                    sortColumn = 'valueAtCost';
                                  }),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text('Value at selling price'),
                                  onSort: (_, __) => setDialogState(() {
                                    if (sortColumn == 'valueAtSellingPrice')
                                      ascending = !ascending;
                                    sortColumn = 'valueAtSellingPrice';
                                  }),
                                ),
                                const DataColumn(label: Text('Flags')),
                              ],
                              rows: [
                                for (final row in visible)
                                  DataRow(
                                    color:
                                        ((row['isNegative'] == true) ||
                                            (row['varianceFlag'] == true))
                                        ? WidgetStatePropertyAll(
                                            AppColors.status_danger.withAlpha(
                                              18,
                                            ),
                                          )
                                        : null,
                                    cells: [
                                      DataCell(
                                        Text(
                                          '${row['name'] ?? ''}\n${row['sku'] ?? ''}',
                                        ),
                                      ),
                                      DataCell(
                                        Text('${row['category'] ?? 'Other'}'),
                                      ),
                                      DataCell(
                                        Text(
                                          '${StockUnitFormatter.format((((row['quantity'] as num?) ?? 0) * 1000).round(), row['unit'] as String? ?? 'pc')}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'KES ${((row['costPrice'] as num?) ?? 0).toStringAsFixed(2)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'KES ${((row['valueAtCost'] as num?) ?? 0).toStringAsFixed(2)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'KES ${((row['valueAtSellingPrice'] as num?) ?? 0).toStringAsFixed(2)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          [
                                            if (row['isNegative'] == true)
                                              'NEGATIVE',
                                            if (row['varianceFlag'] == true)
                                              'VARIANCE',
                                          ].join(' · '),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Totals for visible rows · Value at cost KES ${costTotal.toStringAsFixed(2)} · Value at selling price KES ${retailTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  Future<void> _importProductsCsv() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final text = utf8
          .decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '');
      final table = _parseCsv(text);
      if (table.length < 2)
        throw const FormatException('The CSV has no product rows.');
      final headers = table.first
          .map((header) => header.trim().toLowerCase())
          .toList();
      final required = ['name', 'sku', 'category', 'price', 'stock'];
      final missing = required
          .where((header) => !headers.contains(header))
          .toList();
      if (missing.isNotEmpty) {
        throw FormatException(
          'Missing required columns: ${missing.join(', ')}.',
        );
      }
      String cell(List<String> row, String header) {
        final i = headers.indexOf(header);
        return i < 0 || i >= row.length ? '' : row[i].trim();
      }

      final seenSkus = widget.state.products
          .map((p) => p.sku.toLowerCase())
          .toSet();
      final products = <PosProduct>[];
      var skipped = 0;
      for (final row in table.skip(1)) {
        if (row.every((value) => value.trim().isEmpty)) continue;
        try {
          final name = cell(row, 'name');
          final sku = cell(row, 'sku');
          final category = cell(row, 'category');
          final stock = int.parse(cell(row, 'stock'));
          final price = Money.parse(cell(row, 'price'));
          if (name.isEmpty ||
              sku.isEmpty ||
              category.isEmpty ||
              stock < 0 ||
              price.isZero ||
              price.minorUnits < 0) {
            throw const FormatException('Required value is empty or invalid.');
          }
          if (!seenSkus.add(sku.toLowerCase())) {
            skipped++;
            continue;
          }
          final costText = cell(row, 'cost');
          final thresholdText = cell(row, 'low_stock_threshold');
          products.add(
            PosProduct(
              id: 'prod_${DateTime.now().microsecondsSinceEpoch}_${products.length}',
              name: name,
              sku: sku,
              barcode: cell(row, 'barcode').isEmpty
                  ? null
                  : cell(row, 'barcode'),
              category: category,
              unitPrice: price,
              costPrice: costText.isEmpty ? null : Money.parse(costText),
              stock: stock,
              lowStockThreshold: thresholdText.isEmpty
                  ? 10
                  : int.parse(thresholdText),
              icon: AppIcons.inventory,
              tint: const Color(0xFFF8FAFC),
            ),
          );
        } on FormatException {
          skipped++;
        }
      }
      if (products.isEmpty) {
        throw FormatException(
          'No valid new products found. $skipped rows were skipped.',
        );
      }
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Preview CSV import'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${products.length} products ready; $skipped rows skipped (invalid or duplicate SKU).',
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: math.min(products.length, 6),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final product = products[index];
                      return ListTile(
                        dense: true,
                        title: Text(product.name),
                        subtitle: Text(
                          '${product.sku} · ${product.category} · ${StockUnitFormatter.format((product.stock * 1000).round(), product.unit)}',
                        ),
                        trailing: Text('KES ${product.unitPrice.formatted}'),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Columns: name, sku, category, price, stock; optional: barcode, cost, low_stock_threshold.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Import ${products.length}'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final added = await widget.state.importProducts(products);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added products imported; $skipped rows skipped.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(FormatException|Exception|StateError): ?'),
        '',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV import failed: $message')));
    }
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (quoted) {
        if (char == '"' && i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else if (char == '"') {
          quoted = false;
        } else {
          field.write(char);
        }
      } else if (char == '"' && field.isEmpty) {
        quoted = true;
      } else if (char == ',') {
        row.add(field.toString());
        field = StringBuffer();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        row.add(field.toString());
        if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(char);
      }
    }
    if (quoted)
      throw const FormatException('CSV contains an unclosed quoted field.');
    row.add(field.toString());
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  void _showStockAdjustDialog(PosProduct product) {
    if (!_requireStockManager()) return;
    String reasonCode = 'SPILLAGE';
    String unit = product.unit;
    String reason = 'Spillage / leakage';
    final qtyCtrl = TextEditingController(text: '0.5');
    final costCtrl = TextEditingController(
      text: product.costPrice == null
          ? ''
          : (product.costPrice!.minorUnits / 100).toStringAsFixed(2),
    );
    final referenceCtrl = TextEditingController();
    bool isAddition = true;
    bool isSaving = false;
    final unitOptions = switch (product.unit) {
      'l' || 'ml' => const ['ml', 'l'],
      'kg' || 'g' => const ['g', 'kg'],
      _ => const ['pc', 'dozen'],
    };
    final selectableUnits = [
      ...unitOptions,
      if (product.purchaseContainerSize != null &&
          product.purchaseContainerSize! > 0)
        'container',
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bg_subtle,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.swapVert, color: AppColors.accent_primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Adjust Stock: ${product.name}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg_subtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border_subtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        AppIcons.inventory,
                        size: 16,
                        color: AppColors.text_tertiary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Current stock: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.text_tertiary,
                        ),
                      ),
                      Text(
                        StockUnitFormatter.format(
                          (product.stock * 1000).round(),
                          product.unit,
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _choiceButton(
                        label: '+ Receive Stock',
                        icon: AppIcons.addCircle,
                        selected: isAddition,
                        color: AppColors.status_success,
                        onTap: () => setModal(() {
                          isAddition = true;
                          reason = 'Stock received';
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _choiceButton(
                        label: '\u2212 Spoilage / Loss',
                        icon: AppIcons.removeCircle,
                        selected: !isAddition,
                        color: AppColors.status_danger,
                        onTap: () => setModal(() {
                          isAddition = false;
                          reasonCode = 'SPILLAGE';
                          reason = 'Spillage / leakage';
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d{0,3}')),
                  ],
                  decoration: _inputDeco('Quantity'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectableUnits.contains(unit) ? unit : product.unit,
                  decoration: _inputDeco('Unit'),
                  items: unitOptions
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            value == 'container'
                                ? (product.purchaseContainerName ??
                                      '${product.purchaseContainerSize} ${product.unit} container')
                                : (ProductUnitCatalogue.symbols[value] ??
                                      value),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setModal(() => unit = value ?? product.unit),
                ),
                if (isAddition) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: _inputDeco('Cost per ${product.unit} (KES)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: referenceCtrl,
                    decoration: _inputDeco(
                      'Supplier / invoice reference (optional)',
                    ),
                  ),
                ],
                if (!isAddition) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: reasonCode,
                    decoration: _inputDeco('Adjustment reason'),
                    items: const [
                      DropdownMenuItem(
                        value: 'SPILLAGE',
                        child: Text('Spillage'),
                      ),
                      DropdownMenuItem(
                        value: 'WASTAGE',
                        child: Text('Wastage'),
                      ),
                      DropdownMenuItem(value: 'DAMAGE', child: Text('Damage')),
                      DropdownMenuItem(value: 'EXPIRY', child: Text('Expiry')),
                      DropdownMenuItem(
                        value: 'CORRECTION',
                        child: Text('Correction'),
                      ),
                    ],
                    onChanged: (value) => setModal(() {
                      reasonCode = value ?? 'CORRECTION';
                      reason =
                          reasonCode[0] + reasonCode.substring(1).toLowerCase();
                    }),
                  ),
                ],
                Text(
                  'Stock is stored in ${product.unit}; quantities convert automatically.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text_tertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: TextEditingController(text: reason),
                  decoration: _inputDeco('Note (optional)'),
                  onChanged: (v) => reason = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: isSaving
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _showStockHistoryDialog(product);
                    },
              icon: const Icon(Icons.history_rounded, size: 16),
              label: const Text('History'),
            ),
            TextButton.icon(
              onPressed: isSaving
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _showStockCountDialog(product);
                    },
              icon: const Icon(AppIcons.inventory, size: 16),
              label: const Text('Physical count'),
            ),
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isAddition
                    ? AppColors.status_success
                    : AppColors.status_danger,
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final amount = num.tryParse(qtyCtrl.text) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a quantity greater than zero.',
                            ),
                          ),
                        );
                        return;
                      }
                      final unitCost = num.tryParse(costCtrl.text);
                      if (isAddition && (unitCost == null || unitCost < 0)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a valid unit cost to receive a delivery.',
                            ),
                          ),
                        );
                        return;
                      }

                      setModal(() => isSaving = true);
                      try {
                        if (isAddition) {
                          await widget.state.receiveStock(
                            productId: product.id,
                            quantity: unit == 'container'
                                ? amount * product.purchaseContainerSize!
                                : amount,
                            unit: unit == 'container' ? product.unit : unit,
                            unitCost: unitCost!,
                            reference: referenceCtrl.text.trim(),
                          );
                        } else {
                          await widget.state.adjustStock(
                            product.id,
                            -(unit == 'container'
                                ? amount * product.purchaseContainerSize!
                                : amount),
                            reason.trim(),
                            reasonCode: reasonCode,
                            unit: unit == 'container' ? product.unit : unit,
                          );
                        }
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Stock updated to ${product.stock} for ${product.name}.',
                            ),
                            backgroundColor: AppColors.status_success,
                          ),
                        );
                      } catch (error) {
                        if (!mounted || !ctx.mounted) return;
                        setModal(() => isSaving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Stock was not updated: $error'),
                            backgroundColor: AppColors.status_danger,
                          ),
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Adjustment'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStockCountDialog(PosProduct product) {
    final quantityController = TextEditingController(
      text: product.stock.toString(),
    );
    final noteController = TextEditingController();
    var saving = false;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Count stock: ${product.name}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current system balance: ${StockUnitFormatter.format((product.stock * 1000).round(), product.unit)}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d{0,3}')),
                  ],
                  decoration: _inputDeco(
                    'Physical quantity counted (${product.unit})',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  decoration: _inputDeco('Count note (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final counted = num.tryParse(quantityController.text);
                      if (counted == null || counted < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid counted quantity.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.state.countStock(
                          productId: product.id,
                          countedQuantity: counted,
                          note: noteController.text.trim(),
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Physical count recorded in stock history.',
                            ),
                          ),
                        );
                      } catch (error) {
                        if (!mounted || !dialogContext.mounted) return;
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Count was not saved: $error'),
                          ),
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save count'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStockHistoryDialog(PosProduct product) {
    if (!_requireStockManager()) return;
    final future = ApiService.instance.getStockMovements(
      productId: product.id,
      limit: 100,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Stock history: ${product.name}'),
        content: SizedBox(
          width: 560,
          height: 440,
          child: FutureBuilder<List<Map<String, dynamic>>?>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data;
              if (rows == null) {
                return Center(
                  child: Text(
                    ApiService.instance.lastError ??
                        'Could not load stock history.',
                  ),
                );
              }
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No stock movements recorded yet.'),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final quantity = (row['quantity'] as num? ?? 0).toDouble();
                  final balance = (row['balanceAfter'] as num? ?? 0).toDouble();
                  final unit = row['unit'] as String? ?? product.unit;
                  final date = DateTime.tryParse(
                    row['createdAt'] as String? ?? '',
                  );
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${row['type'] ?? 'Movement'} · ${StockUnitFormatter.format((quantity * 1000).round(), unit)}',
                    ),
                    subtitle: Text(
                      [
                        'Balance ${StockUnitFormatter.format((balance * 1000).round(), unit)}',
                        if (row['reason'] != null) '${row['reason']}',
                        if (row['reference'] != null) 'Ref ${row['reference']}',
                        if (date != null)
                          date.toLocal().toString().substring(0, 16),
                        if (row['createdBy'] != null) 'By ${row['createdBy']}',
                      ].join(' · '),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGlobalStockHistory() async {
    if (!_requireStockManager()) return;
    String? type;
    DateTime? from;
    DateTime? to;
    Future<List<Map<String, dynamic>>?> load() => ApiService.instance
        .getStockMovements(type: type, from: from, to: to, limit: 100);
    var future = load();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Stock movement history'),
          content: SizedBox(
            width: 700,
            height: 540,
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        initialValue: type,
                        decoration: const InputDecoration(
                          labelText: 'Movement type',
                        ),
                        items: const [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All types'),
                          ),
                          DropdownMenuItem(
                            value: 'PURCHASE',
                            child: Text('Purchase'),
                          ),
                          DropdownMenuItem(value: 'SALE', child: Text('Sale')),
                          DropdownMenuItem(
                            value: 'ADJUSTMENT_IN',
                            child: Text('Adjustment in'),
                          ),
                          DropdownMenuItem(
                            value: 'ADJUSTMENT_OUT',
                            child: Text('Adjustment out'),
                          ),
                          DropdownMenuItem(
                            value: 'VARIANCE',
                            child: Text('Variance'),
                          ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          type = value;
                          future = load();
                        }),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: dialogContext,
                          initialDate: from ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            from = DateTime(
                              selected.year,
                              selected.month,
                              selected.day,
                            );
                            future = load();
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        from == null
                            ? 'From date'
                            : '${from!.year}-${from!.month.toString().padLeft(2, '0')}-${from!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: dialogContext,
                          initialDate: to ?? DateTime.now(),
                          firstDate: from ?? DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            to = DateTime(
                              selected.year,
                              selected.month,
                              selected.day + 1,
                            );
                            future = load();
                          });
                        }
                      },
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(
                        to == null
                            ? 'To date'
                            : '${to!.subtract(const Duration(days: 1)).year}-${to!.subtract(const Duration(days: 1)).month.toString().padLeft(2, '0')}-${to!.subtract(const Duration(days: 1)).day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>?>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = snapshot.data;
                      if (rows == null) {
                        return Center(
                          child: Text(
                            ApiService.instance.lastError ??
                                'Could not load movement history.',
                          ),
                        );
                      }
                      if (rows.isEmpty)
                        return const Center(
                          child: Text(
                            'No stock movements match these filters.',
                          ),
                        );
                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final quantity = (row['quantity'] as num? ?? 0)
                              .toDouble();
                          final balance = (row['balanceAfter'] as num? ?? 0)
                              .toDouble();
                          final unit = row['unit'] as String? ?? 'pc';
                          final date = DateTime.tryParse(
                            row['createdAt'] as String? ?? '',
                          );
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${row['productName'] ?? 'Product'} · ${row['type'] ?? 'Movement'} · ${StockUnitFormatter.format((quantity * 1000).round(), unit)}',
                            ),
                            subtitle: Text(
                              [
                                'Balance ${StockUnitFormatter.format((balance * 1000).round(), unit)}',
                                if (row['reference'] != null)
                                  'Ref ${row['reference']}',
                                if (date != null)
                                  date.toLocal().toString().substring(0, 16),
                                if (row['createdBy'] != null)
                                  'By ${row['createdBy']}',
                              ].join(' · '),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(PosProduct product) async {
    // Stage 1: confirm dialog with optional discard-stock checkbox.
    bool discardStock = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Row(
            children: [
              Icon(AppIcons.deleteForever, color: AppColors.status_danger),
              SizedBox(width: 8),
              Text('Permanently Delete Product?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.text_secondary,
                  ),
                  children: [
                    const TextSpan(
                      text: 'You are about to permanently delete ',
                    ),
                    TextSpan(
                      text: product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.text_primary,
                      ),
                    ),
                    TextSpan(text: ' (SKU: ${product.sku}).'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Current stock: ${product.stock} units',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.text_secondary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.status_danger.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.status_danger.withAlpha(60),
                  ),
                ),
                child: const Text(
                  'This cannot be undone. Only products with no sales history can be permanently deleted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.status_danger,
                  ),
                ),
              ),
              // Require explicit acknowledgement for positive or negative stock.
              if (product.stock != 0) ...[
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    product.stock < 0
                        ? 'Clear stock discrepancy (${product.stock.abs()} units below zero)'
                        : 'Discard current stock (${product.stock} units)',
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: discardStock,
                  onChanged: (v) => setModal(() => discardStock = v ?? false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(AppIcons.deleteForever, size: 16),
              label: const Text('Delete Permanently'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.status_danger,
              ),
              // Disable button if stock is non-zero and discard not ticked.
              onPressed: (product.stock != 0 && !discardStock)
                  ? null
                  : () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Stage 2: attempt the delete.
    try {
      await widget.state.deleteProduct(product.id, discardStock: discardStock);
      if (!mounted) return;
      if (_selectedProduct?.id == product.id)
        setState(() => _selectedProduct = null);
      else
        setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${product.name}" permanently deleted.')),
      );
    } on ProductHasHistoryException catch (e) {
      // Stage 3a: product has history — offer archive instead.
      if (!mounted) return;
      final counts = e.counts;
      final detail = [
        if ((counts['saleItems'] as int? ?? 0) > 0)
          '${counts['saleItems']} sale(s)',
        if ((counts['purchaseItems'] as int? ?? 0) > 0)
          '${counts['purchaseItems']} purchase(s)',
        if ((counts['refundItems'] as int? ?? 0) > 0)
          '${counts['refundItems']} refund(s)',
      ].join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            '"${product.name}" has history ($detail) and cannot be deleted. Use Archive to hide it.',
          ),
          action: SnackBarAction(
            label: 'Archive instead',
            onPressed: () async {
              try {
                await widget.state.archiveProduct(product.id);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"${product.name}" archived.')),
                );
              } catch (archiveErr) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not archive: $archiveErr')),
                );
              }
            },
          ),
        ),
      );
    } on ProductHasStockException {
      // Stage 3b: should not reach here (button is disabled above) — defensive fallback.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tick "Discard current stock" to delete a product with stock.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete product: $error')),
      );
    }
  }

  void _duplicateProduct(PosProduct p) {
    widget.state.addProduct(
      PosProduct(
        id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Copy of ${p.name}',
        sku: '${p.sku}-COPY',
        category: p.category,
        unitPrice: p.unitPrice,
        costPrice: p.costPrice,
        stock: 0,
        lowStockThreshold: p.lowStockThreshold,
        icon: p.icon,
        tint: p.tint,
        notes: p.notes,
      ),
    );
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Duplicated "${p.name}" \u2014 update the copy.')),
    );
  }

  Future<void> _toggleActive(PosProduct p) async {
    final active = !p.isActive;
    try {
      await widget.state.setProductActive(p.id, active);
      final updated = p.copyWith(isActive: active);
      if (_selectedProduct?.id == p.id)
        setState(() => _selectedProduct = updated);
      else
        setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? '"${p.name}" activated.' : '"${p.name}" deactivated.',
          ),
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update product status: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.state.products;
    final totalSkus = products.where((p) => p.isActive).length;
    final lowCount = products.where((p) => p.isActive && p.isLowStock).length;
    final outCount = products.where((p) => p.isActive && p.isOutOfStock).length;
    final valuation = products
        .where((p) => p.isActive)
        .fold<num>(0, (sum, p) => sum + (p.unitPrice.minorUnits * p.stock));
    final filtered = _filtered;
    if (MediaQuery.sizeOf(context).width < 768) {
      return _buildCompactInventory(
        products: products,
        filtered: filtered,
        totalSkus: totalSkus,
        lowCount: lowCount,
        outCount: outCount,
        valuation: valuation.round(),
      );
    }

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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Inventory & Catalogue',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text_primary,
                              ),
                            ),
                            Text(
                              'Manage products, pricing, stock levels and catalogue settings',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.text_tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(AppIcons.download, size: 17),
                        label: const Text('Export'),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (sheetContext) => SafeArea(
                            child: Wrap(
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.fact_check_outlined,
                                  ),
                                  title: const Text('View stock audit list'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _showStockAuditList();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.history_rounded),
                                  title: const Text('View all stock movements'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _showGlobalStockHistory();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.print_outlined),
                                  title: const Text(
                                    'Print A4 stock count sheet',
                                  ),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _printStockAudit();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.table_chart),
                                  title: const Text(
                                    'Download Excel stock list',
                                  ),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _exportInventory(excel: true);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.text_snippet_outlined,
                                  ),
                                  title: const Text('Download CSV stock list'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _exportInventory(excel: false);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(AppIcons.upload, size: 17),
                        label: const Text('Import CSV'),
                        onPressed: _importProductsCsv,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(AppIcons.add, size: 17),
                        label: const Text('Add Product'),
                        onPressed: () => _showProductEditor(),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent_primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.state.catalogueSyncMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color:
                            widget.state.catalogueSyncMessage!.startsWith(
                                  'Local-only',
                                ) ||
                                widget.state.catalogueSyncMessage!.startsWith(
                                  'Catalogue sync failed',
                                )
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          if (widget.state.catalogueSyncing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              widget.state.catalogueSyncMessage!.startsWith(
                                        'Local-only',
                                      ) ||
                                      widget.state.catalogueSyncMessage!
                                          .startsWith('Catalogue sync failed')
                                  ? AppIcons.cloudOff
                                  : AppIcons.cloudDone,
                              size: 16,
                              color: AppColors.text_secondary,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.state.catalogueSyncMessage!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.text_secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // KPI cards
                  Row(
                    children: [
                      _StatCard(
                        'Active SKUs',
                        '$totalSkus items',
                        AppIcons.qrCode,
                        AppColors.accent_primary,
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        'Stock Valuation',
                        'KES ${Money(valuation.round()).formatted}',
                        AppIcons.wallet,
                        const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        'Low Stock',
                        '$lowCount alerts',
                        AppIcons.trendingDown,
                        const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        'Out of Stock',
                        '$outCount SKUs',
                        AppIcons.removeFromCart,
                        AppColors.status_danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Toolbar
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search by name, SKU or barcode\u2026',
                            prefixIcon: const Icon(AppIcons.search, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppColors.border_subtle,
                              ),
                            ),
                          ),
                        ),
                      ),
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
                            label: Text(
                              t.$2,
                              style: TextStyle(
                                fontSize: 12,
                                color: sel ? t.$3 : AppColors.text_secondary,
                              ),
                            ),
                            selected: sel,
                            onSelected: (_) =>
                                setState(() => _stockFilter = t.$1),
                            selectedColor: (t.$3).withAlpha(20),
                            checkmarkColor: t.$3,
                          ),
                        );
                      }),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: Text(
                          'Show Inactive',
                          style: TextStyle(
                            fontSize: 12,
                            color: _showInactive
                                ? AppColors.text_tertiary
                                : AppColors.text_secondary,
                          ),
                        ),
                        selected: _showInactive,
                        onSelected: (_) =>
                            setState(() => _showInactive = !_showInactive),
                        selectedColor: AppColors.bg_subtle,
                      ),
                    ],
                  ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.accent_primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel
                                      ? AppColors.accent_primary
                                      : AppColors.border_subtle,
                                ),
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : AppColors.text_secondary,
                                ),
                              ),
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
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.bg_subtle,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: AppColors.border_subtle,
                                ),
                              ),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 48),
                                Expanded(
                                  flex: 4,
                                  child: Text('PRODUCT', style: _headerStyle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('CATEGORY', style: _headerStyle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('PRICE', style: _headerStyle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('MARGIN', style: _headerStyle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('STOCK', style: _headerStyle),
                                ),
                                SizedBox(width: 110),
                              ],
                            ),
                          ),
                          if (filtered.isEmpty)
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppIcons.inventory,
                                      size: 48,
                                      color: AppColors.border_subtle,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No products match your filters',
                                      style: TextStyle(
                                        color: AppColors.text_tertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      icon: const Icon(AppIcons.add, size: 16),
                                      label: const Text('Add a product'),
                                      onPressed: () => _showProductEditor(),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: AppColors.border_subtle,
                                ),
                                itemBuilder: (ctx, i) => _ProductRow(
                                  product: filtered[i],
                                  isSelected:
                                      _selectedProduct?.id == filtered[i].id,
                                  onTap: () => setState(() {
                                    _selectedProduct =
                                        _selectedProduct?.id == filtered[i].id
                                        ? null
                                        : filtered[i];
                                  }),
                                  onEdit: () =>
                                      _showProductEditor(product: filtered[i]),
                                  onStockAdjust: () =>
                                      _showStockAdjustDialog(filtered[i]),
                                  onDuplicate: () =>
                                      _duplicateProduct(filtered[i]),
                                  onToggleActive: () =>
                                      _toggleActive(filtered[i]),
                                  onDelete: () => _confirmDelete(filtered[i]),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${filtered.length} of ${products.length} products shown',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text_tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) {
              final slide =
                  Tween<Offset>(
                    begin: const Offset(1.0, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
              return SlideTransition(
                position: slide,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _selectedProduct != null
                ? _ProductDetailPanel(
                    key: ValueKey(_selectedProduct!.id),
                    product: _selectedProduct!,
                    onEdit: () =>
                        _showProductEditor(product: _selectedProduct!),
                    onStockAdjust: () =>
                        _showStockAdjustDialog(_selectedProduct!),
                    onClose: () => setState(() => _selectedProduct = null),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInventory({
    required List<PosProduct> products,
    required List<PosProduct> filtered,
    required int totalSkus,
    required int lowCount,
    required int outCount,
    required int valuation,
  }) {
    final syncMessage = widget.state.catalogueSyncMessage;
    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: widget.state.syncCatalogueFromApi,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Inventory',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text_primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh stock',
                          onPressed: widget.state.catalogueSyncing
                              ? null
                              : widget.state.syncCatalogueFromApi,
                          icon: widget.state.catalogueSyncing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Inventory actions',
                          onSelected: (value) {
                            if (value == 'import') _importProductsCsv();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'import',
                              child: Text('Import CSV'),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: 'Add product',
                          onPressed: () => _showProductEditor(),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.accent_primary,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(AppIcons.add),
                        ),
                      ],
                    ),
                    const Text(
                      'Products and stock levels',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text_tertiary,
                      ),
                    ),
                    if (syncMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: syncMessage.startsWith('Catalogue sync failed')
                              ? AppColors.status_danger_light
                              : AppColors.accent_light,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          syncMessage,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text_secondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _StatCard(
                          'Active SKUs',
                          '$totalSkus items',
                          AppIcons.qrCode,
                          AppColors.accent_primary,
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          'Low Stock',
                          '$lowCount alerts',
                          AppIcons.trendingDown,
                          const Color(0xFFD97706),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatCard(
                          'Stock Value',
                          'KES ${Money(valuation).formatted}',
                          AppIcons.wallet,
                          const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          'Out of Stock',
                          '$outCount SKUs',
                          AppIcons.removeFromCart,
                          AppColors.status_danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search products',
                        prefixIcon: const Icon(AppIcons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.border_subtle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final option in [
                            ('All', 'All'),
                            ('Low', 'Low stock'),
                            ('Out', 'Out of stock'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(option.$2),
                                selected: _stockFilter == option.$1,
                                onSelected: (_) =>
                                    setState(() => _stockFilter = option.$1),
                              ),
                            ),
                          FilterChip(
                            label: const Text('Inactive'),
                            selected: _showInactive,
                            onSelected: (_) =>
                                setState(() => _showInactive = !_showInactive),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _allCategories.map((category) {
                          final selected = _category == category;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _category = category),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ]),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        products.isEmpty
                            ? 'No products yet. Pull down to refresh or add a product.'
                            : 'No products match your filters.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.text_tertiary),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildCompactProduct(filtered[index]),
                      childCount: filtered.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Text(
                    '${filtered.length} of ${products.length} products shown',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text_tertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactProduct(PosProduct product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: product.tint,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: product.imageBase64 != null && product.imageBase64!.isNotEmpty
              ? Image.memory(
                  base64Decode(product.imageBase64!.split(',').last),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              : Icon(product.icon, color: AppColors.text_secondary),
        ),
        title: Text(
          product.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text_primary,
          ),
        ),
        subtitle: Text(
          '${product.sku} · ${product.category} · KES ${product.unitPrice.formatted}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StockBadge(product),
            PopupMenuButton<String>(
              tooltip: 'Product actions',
              onSelected: (value) {
                switch (value) {
                  case 'stock':
                    _showStockAdjustDialog(product);
                    break;
                  case 'edit':
                    _showProductEditor(product: product);
                    break;
                  case 'duplicate':
                    _duplicateProduct(product);
                    break;
                  case 'toggle':
                    _toggleActive(product);
                    break;
                  case 'delete':
                    _confirmDelete(product);
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'stock',
                  child: Text('Adjust stock'),
                ),
                const PopupMenuItem(value: 'edit', child: Text('Edit product')),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate'),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(product.isActive ? 'Deactivate' : 'Activate'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        onTap: () => _showStockAdjustDialog(product),
      ),
    );
  }
}

// ─── Product row ───────────────────────────────────────────────────────────
class _ProductRow extends StatefulWidget {
  const _ProductRow({
    required this.product,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onStockAdjust,
    required this.onDuplicate,
    required this.onToggleActive,
    required this.onDelete,
  });
  final PosProduct product;
  final bool isSelected;
  final VoidCallback onTap,
      onEdit,
      onStockAdjust,
      onDuplicate,
      onToggleActive,
      onDelete;

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
            child: Row(
              children: [
                Opacity(
                  opacity: inactive ? 0.4 : 1.0,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: p.tint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: p.imageBase64 != null && p.imageBase64!.isNotEmpty
                        ? Image.memory(
                            base64Decode(p.imageBase64!.split(',').last),
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Icon(
                            p.icon,
                            size: 18,
                            color: AppColors.text_secondary,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Opacity(
                    opacity: inactive ? 0.5 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.text_primary,
                                  decoration: inactive
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (inactive) ...[
                              const SizedBox(width: 6),
                              _Badge(
                                'INACTIVE',
                                const Color(0xFF9CA3AF),
                                const Color(0xFFF3F4F6),
                              ),
                            ],
                            if (p.isPublished) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Published to the customer web shop',
                                child: _Badge(
                                  'WEB',
                                  const Color(0xFF16835D),
                                  const Color(0xFFE8F6EF),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          p.sku,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppColors.text_tertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Icon(
                        _catIcon(p.category),
                        size: 14,
                        color: AppColors.text_tertiary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        p.category,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text_secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'KES ${p.unitPrice.formatted}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: p.marginPercent != null
                      ? Text(
                          '${p.marginPercent!.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.marginPercent! >= 20
                                ? AppColors.status_success
                                : (p.marginPercent! >= 0
                                      ? const Color(0xFFD97706)
                                      : AppColors.status_danger),
                          ),
                        )
                      : const Text(
                          '\u2014',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text_tertiary,
                          ),
                        ),
                ),
                Expanded(flex: 2, child: _StockBadge(p)),
                SizedBox(
                  width: 110,
                  child: (_hovered || widget.isSelected)
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ActionIcon(
                              icon: AppIcons.swapVert,
                              tooltip: 'Adjust Stock',
                              color: AppColors.accent_primary,
                              onTap: widget.onStockAdjust,
                            ),
                            _ActionIcon(
                              icon: AppIcons.edit,
                              tooltip: 'Edit Product',
                              color: AppColors.text_secondary,
                              onTap: widget.onEdit,
                            ),
                            PopupMenuButton<String>(
                              iconSize: 18,
                              tooltip: 'More actions',
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onSelected: (v) {
                                if (v == 'duplicate') widget.onDuplicate();
                                if (v == 'toggle') widget.onToggleActive();
                                if (v == 'delete') widget.onDelete();
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: _menuRow(AppIcons.copy, 'Duplicate'),
                                ),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: _menuRow(
                                    p.isActive
                                        ? AppIcons.visibilityOff
                                        : AppIcons.visibility,
                                    p.isActive ? 'Deactivate' : 'Activate',
                                  ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: _menuRow(
                                    AppIcons.delete,
                                    'Delete',
                                    color: AppColors.status_danger,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuRow(
    IconData icon,
    String label, {
    Color color = AppColors.text_primary,
  }) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 13, color: color)),
    ],
  );
}

// ─── Detail panel ─────────────────────────────────────────────────────────
class _ProductDetailPanel extends StatelessWidget {
  const _ProductDetailPanel({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onStockAdjust,
    required this.onClose,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: AppColors.bg_subtle,
              border: Border(
                bottom: BorderSide(color: AppColors.border_subtle),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Product Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.text_primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(AppIcons.close, size: 18),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: AppColors.text_tertiary,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: p.tint,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child:
                              p.imageBase64 != null && p.imageBase64!.isNotEmpty
                              ? Image.memory(
                                  base64Decode(p.imageBase64!.split(',').last),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Icon(
                                  p.icon,
                                  size: 32,
                                  color: AppColors.text_primary,
                                ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          p.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text_primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.sku,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppColors.text_tertiary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _Badge(
                          p.category,
                          AppColors.accent_primary,
                          AppColors.accent_primary.withAlpha(18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  _DetailRow('Selling Price', 'KES ${p.unitPrice.formatted}'),
                  if (p.costPrice != null)
                    _DetailRow('Cost Price', 'KES ${p.costPrice!.formatted}'),
                  if (p.marginPercent != null)
                    _DetailRow(
                      'Gross Margin',
                      '${p.marginPercent!.toStringAsFixed(1)}%',
                      valueColor: p.marginPercent! >= 20
                          ? AppColors.status_success
                          : AppColors.status_danger,
                    ),
                  _DetailRow(
                    'Current Stock',
                    StockUnitFormatter.format((p.stock * 1000).round(), p.unit),
                    valueColor: p.isOutOfStock
                        ? AppColors.status_danger
                        : (p.isLowStock
                              ? const Color(0xFFD97706)
                              : AppColors.status_success),
                  ),
                  _DetailRow(
                    'Alert Threshold',
                    '\u2264 ${p.lowStockThreshold} units',
                  ),
                  if (p.barcode != null) _DetailRow('Barcode', p.barcode!),
                  _DetailRow(
                    'Status',
                    p.isActive ? 'Active' : 'Inactive',
                    valueColor: p.isActive
                        ? AppColors.status_success
                        : AppColors.text_tertiary,
                  ),
                  if (p.notes != null && p.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text_tertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.notes!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text_secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text_tertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(AppIcons.swapVert, size: 16),
                      label: const Text('Adjust Stock'),
                      onPressed: onStockAdjust,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(AppIcons.edit, size: 16),
                      label: const Text('Edit Product'),
                      onPressed: onEdit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent_primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
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

// ─── Shared helpers ────────────────────────────────────────────────────────
const _headerStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
  color: AppColors.text_tertiary,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.text_tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final color = isOut
        ? AppColors.status_danger
        : (isLow ? const Color(0xFFD97706) : AppColors.status_success);
    return Row(
      children: [
        Text(
          '${product.stock}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.textColor, this.bgColor);
  final String label;
  final Color textColor, bgColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 18, color: color),
      ),
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
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.text_primary,
          ),
        ),
      ],
    ),
  );
}

InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
  labelText: label,
  hintText: hint,
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
);

InputDecoration _modalInputDeco(String label, {String? hint}) =>
    InputDecoration(
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
        borderSide: const BorderSide(
          color: AppColors.accent_primary,
          width: 1.5,
        ),
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
  required String label,
  required IconData icon,
  required bool selected,
  required Color color,
  required VoidCallback onTap,
}) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(8),
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
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: selected ? color : AppColors.text_tertiary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? color : AppColors.text_secondary,
          ),
        ),
      ],
    ),
  ),
);
