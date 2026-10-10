# Implementation Plan — Product Editor: Bug Fixes + UI Redesign

Covers four ordered changes. Each leaves the codebase in a buildable state.
Verify each item with `flutter build web --no-pub` run from
`c:\Amalgamate\Projects\Trends CORE Apps\Retail POS\apps\shop_pos`.

---

## Quick-reference: files to touch

| # | File | Change |
|---|------|--------|
| 1 | `web/index.html` | Remove `defer` from `file_picker_plugin.js` |
| 2 | `lib/views/inventory_view.dart` | Fix price parsing; redesign `_showProductEditor` dialog |
| 3 | `lib/views/widgets/image_upload_widget.dart` | Add hover animation |

---

- [ ] 1. **Fix image-upload JS load order in `web/index.html`**

  The `file_picker_plugin.js` script tag has `defer`, which means it is
  fetched and executed after the document has been parsed — potentially after
  Flutter bootstrap runs and attempts to call the plugin. Remove `defer` so
  the script executes synchronously in document order, before Flutter starts.

  **Exact change** — replace:
  ```html
  <script src="packages/file_picker/_web/file_picker_plugin.js" defer></script>
  ```
  with:
  ```html
  <script src="packages/file_picker/_web/file_picker_plugin.js"></script>
  ```
  The `flutter_bootstrap.js` tag keeps its `async` attribute (Flutter expects
  it); only the plugin script loses `defer`.

  Files: `web/index.html`

  Verify: `flutter build web --no-pub` completes without error. Open the
  built app in a browser, open the Add Product dialog, click the image upload
  area and confirm the OS file picker opens.

---

- [ ] 2. **Fix false save-validation error — replace `_parseMoney` with `Money.parse`**

  The existing `_parseMoney` helper strips KES/commas and calls
  `double.tryParse`. `double.tryParse` returns `null` on strings like `"65."`,
  and the subsequent `Money.fromDouble` path rounds — causing the validation
  guard `parsedPrice == null || parsedPrice.minorUnits <= 0` to fire
  incorrectly for valid inputs. Replace the price and cost parsing in the Save
  `onPressed` handler inside `_showProductEditor` to use `Money.parse` from
  `lib/cart.dart`, which parses the integer path and throws a `FormatException`
  on garbage.

  **Keep `_parseMoney` intact** — it is still used for editing cost price
  pre-population (the display path). Only change the two parse calls in the
  `onPressed` lambda.

  **Replace the two parse calls** (inside the `onPressed` of the Save
  `FilledButton.icon`) with the pattern below:

  ```dart
  // Replace:
  final parsedPrice = _parseMoney(priceCtrl.text);
  if (name.isEmpty || parsedPrice == null || parsedPrice.minorUnits <= 0) { ... }
  final parsedCost = _parseMoney(costCtrl.text);

  // With:
  Money? parsedPrice;
  try {
    final clean = priceCtrl.text.replaceAll(',', '').replaceAll('KES', '').replaceAll('kes', '').trim();
    if (clean.isNotEmpty) parsedPrice = Money.parse(clean);
  } on FormatException {
    parsedPrice = null;
  }
  if (name.isEmpty || parsedPrice == null || parsedPrice.minorUnits <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and a valid price are required.')));
    return;
  }
  Money? parsedCost;
  try {
    final cleanCost = costCtrl.text.replaceAll(',', '').replaceAll('KES', '').replaceAll('kes', '').trim();
    if (cleanCost.isNotEmpty) parsedCost = Money.parse(cleanCost);
  } on FormatException {
    parsedCost = null;
  }
  ```

  Files: `lib/views/inventory_view.dart`

  Verify: `flutter build web --no-pub`. Open Add Product dialog, enter a valid
  name + price (e.g. `250`) and tap Save — product should be added with no
  snackbar error. Then enter a non-numeric price and verify the error snackbar
  does appear.

---

- [ ] 3. **Redesign `_showProductEditor` — modern Notion/Linear-style white card modal**

  Replace the entire `_showProductEditor` dialog body (the `Dialog(...)` widget
  tree) in `lib/views/inventory_view.dart`. Keep the existing controller
  declarations and local state (`imageBase64`, `category`) unchanged — only the
  `builder` return value changes.

  Also add a new private helper `_modalInputDeco` (file-scoped, alongside the
  existing `_inputDeco`) so the new style does not affect other dialogs.

  ### 3a. New `_modalInputDeco` helper (add near `_inputDeco`)

  ```dart
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
  ```

  ### 3b. New dialog structure

  The `builder` of `StatefulBuilder` returns:

  ```dart
  Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: SizedBox(
      width: math.min(620.0, MediaQuery.sizeOf(context).width - 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.border_subtle),
                left: BorderSide(color: AppColors.accent_primary, width: 4),
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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

          // ── Body (scrollable, max height 520) ───────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PRODUCT IDENTITY label
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
                                    width: 8, height: 8,
                                    decoration: BoxDecoration(
                                      color: _catColor(c),
                                      shape: BoxShape.circle,
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

                  // ── PRICING ──────────────────────────────────────
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

                  // ── STOCK SETTINGS ───────────────────────────────
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

                  // ── NOTES ────────────────────────────────────────
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

          // ── Footer ──────────────────────────────────────────────
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
                      ),
                      onPressed: () {
                        /* === paste the existing save logic here,
                               replacing _parseMoney with the
                               Money.parse pattern from item 2 === */
                      },
                      child: Text(isEdit ? 'Save Changes' : 'Add Product'),
                    ),
                  ],
                ),
                if (!isEdit) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Product will be added to the active catalogue',
                    style: TextStyle(fontSize: 10, color: AppColors.text_tertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  )
  ```

  ### 3c. New `_modalSectionLabel` helper

  Add alongside `_sectionLabel` (which is kept for other dialogs):

  ```dart
  Widget _modalSectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.text_tertiary,
      letterSpacing: 0.5,
    ),
  );
  ```

  ### Important: left-border on a Dialog
  `Dialog` clips its child by default when the `shape` is set. To make the
  4px left accent border visible, the `Container` bearing the border must sit
  inside the clip — use a `ClipRRect` wrapping the outermost `Column` with the
  same `borderRadius: BorderRadius.circular(12)` if the border is clipped.
  Alternatively, add the left border as the `Dialog`'s `child` first child
  (inside `Column`) using a `Container(width: 4, color: AppColors.accent_primary)`
  in a `Row` — whichever approach renders cleanly in testing.

  Files: `lib/views/inventory_view.dart`

  Verify: `flutter build web --no-pub`. Open both Add Product and Edit Product
  dialogs. Confirm: white header with no tinted background, 4px left teal
  accent, 17px bold title, image upload is 100px with helper text, section
  labels are muted all-caps, fields have filled bg + accent focus ring, footer
  is white with correct button styles and new-product hint text.

---

- [ ] 4. **Add hover animation to `ImageUploadWidget`** (no-image state only)

  In `lib/views/widgets/image_upload_widget.dart`, add a `_hovered` boolean
  to `_ImageUploadWidgetState` and a `MouseRegion` around the existing tile
  `GestureDetector`. When `!hasImage`, the `AnimatedContainer` border color
  should animate between `AppColors.border_subtle` and
  `AppColors.accent_primary.withAlpha(120)` on hover.

  **Step-by-step**:

  1. Add `bool _hovered = false;` as a field in `_ImageUploadWidgetState`.

  2. The outermost `Stack`'s first child is currently a `MouseRegion` with only
     `cursor: SystemMouseCursors.click`. Expand it to also handle hover:
     ```dart
     MouseRegion(
       cursor: SystemMouseCursors.click,
       onEnter: (_) => setState(() => _hovered = true),
       onExit: (_) => setState(() => _hovered = false),
       child: GestureDetector( ... ),
     )
     ```

  3. In the `AnimatedContainer`'s `decoration`, change the `border` logic:
     ```dart
     border: Border.all(
       color: hasImage
           ? AppColors.accent_primary.withAlpha(60)
           : (_hovered
               ? AppColors.accent_primary.withAlpha(120)
               : AppColors.border_subtle),
       width: hasImage ? 2 : 1,
     ),
     ```
     The `AnimatedContainer` already has `duration: const Duration(milliseconds: 250)`,
     so the color transition is automatic — no additional `AnimationController`
     needed.

  Files: `lib/views/widgets/image_upload_widget.dart`

  Verify: `flutter build web --no-pub`. Open Add Product dialog, hover the
  image upload square — the border should animate to a teal tint. Moving the
  cursor away should animate back to gray. No change in behavior when an image
  is already loaded.

---

## Build & run commands

```bash
# Working directory: c:\Amalgamate\Projects\Trends CORE Apps\Retail POS\apps\shop_pos

# Fast compile check (no device needed)
flutter build web --no-pub

# Run in browser for visual verification
flutter run -d chrome --web-port 8080
```

## Dependency notes

- `Money.parse` is in `lib/cart.dart` — already imported at the top of
  `inventory_view.dart` via `import '../cart.dart';`. No new imports needed.
- `AppColors` is in `lib/theme/tokens.dart` — already imported via
  `import '../theme/tokens.dart';`. No new imports needed.
- `image_upload_widget.dart` already imports `../../theme/tokens.dart`.
- No new packages are required.
