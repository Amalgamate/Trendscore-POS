# Product editor rebuild: image upload fix, save validation, and UI modernisation

The change addresses three failure modes in the inventory product editor: file_picker not initialising on web (causing silent upload failures), save validation producing false errors, and an outdated modal UI. The approach is surgical — the web bootstrap script gets a load-order fix, the price/cost parsing is replaced with a defensive try-catch around `Money.parse`, and the editor dialog is redesigned with a new `_modalInputDeco` helper while the existing `_inputDeco` used in the stock-adjustment dialog is left untouched.

Watch for: **(confirmed)** `deprecated_member_use` lint at `inventory_view.dart:177` — a `TextFormField` `value:` parameter flagged since v3.33.0, may be pre-existing; **(confirmed)** four `curly_braces_in_flow_control_structures` warnings in `inventory_view.dart` at lines 579, 580, 603, 604 — need braces added.

**Verdict**: APPROVED

---

## High-level view

The `defer` attribute is absent from the file_picker script tag and the script loads synchronously before `flutter_bootstrap.js` — the correct load order for the web plugin to register before Flutter initialises.

Price and cost parsing wrap `Money.parse` in individual try-catch blocks, leaving `parsedPrice` null on any parse failure. The validation gate — `name.isEmpty || parsedPrice == null || parsedPrice.minorUnits <= 0` — closes the false-positive path: a blank or non-numeric price field can no longer produce a confusing success path. The zero-price guard (`minorUnits <= 0`) additionally rejects a submitted `0.00`.

`_modalInputDeco` is a new top-level function alongside `_inputDeco`. The two coexist without conflict: `_inputDeco` is used exclusively in the stock-adjustment dialog, `_modalInputDeco` throughout the product editor. No fields were removed — the editor contains name, category, SKU, barcode, selling price, cost price, opening/current stock, low-stock threshold, notes, and image upload.

`ImageUploadWidget` gained `MouseRegion` wrapping the main tile with `_hovered` state. The `AnimatedContainer` border switches from `AppColors.border_subtle` to `AppColors.accent_primary.withAlpha(120)` on hover when no image is set.

The analysis output contains 34 issues, all `info` or `warning` — no `error` level. Four `curly_braces_in_flow_control_structures` items and one `deprecated_member_use` are in the changed file and should be cleaned up.

---

<details>
<summary>Issues (2)</summary>

1. **Lint warnings in inventory_view.dart** — Four `curly_braces_in_flow_control_structures` warnings at lines 579, 580, 603, 604 are in the changed file. Add curly braces to the flagged `if` statements.
2. **deprecated_member_use at inventory_view.dart:177** — A `TextFormField` uses `value:` instead of `initialValue:`, deprecated since Flutter v3.33.0. Determine whether pre-existing; if introduced here, replace `value:` with `initialValue:`.

</details>

---

<details>
<summary>Details</summary>

### Price/cost parsing and save validation

Both price and cost fields strip commas and `KES`/`kes` tokens, then call `Money.parse` inside a try-catch. `parsedPrice` stays null if the field is blank or malformed. The validation block rejects the form if `name.isEmpty || parsedPrice == null || parsedPrice.minorUnits <= 0` (confirmed). Cost follows the same pattern but a null `parsedCost` is valid and passes through.

The zero-price guard is new: previously any string-based parsing without `minorUnits > 0` could silently accept a `0.00` price entry.

### _modalInputDeco alongside _inputDeco

`_modalInputDeco` uses `filled: true`, `fillColor: AppColors.bg_subtle`, rounded borders (`BorderRadius.circular(8)`) with a 1.5px accent focus ring, and 14×12 content padding. `_inputDeco` retains its plain `OutlineInputBorder` with 12×10 padding. The stock-adjustment dialog exclusively uses `_inputDeco`; the product editor exclusively uses `_modalInputDeco` (confirmed). No field was removed from either dialog.

### Hover state in ImageUploadWidget

`_hovered` is toggled by `MouseRegion`'s `onEnter`/`onExit` callbacks. The `AnimatedContainer` border references `_hovered` inside the `!hasImage` branch: hovered → `AppColors.accent_primary.withAlpha(120)`; at rest → `AppColors.border_subtle`; 250ms transition. When an image is already set, the border stays `AppColors.accent_primary.withAlpha(60)` regardless of hover (confirmed).

</details>

---

<details>
<summary>File map</summary>

- `web/index.html` — `defer` removed from file_picker script tag; loads synchronously before Flutter bootstrap
- `lib/views/inventory_view.dart` — price/cost parsing replaced with `Money.parse` try-catch; validation updated; `_modalInputDeco` added; `_inputDeco` and stock-adjustment dialog unchanged
- `lib/views/widgets/image_upload_widget.dart` — `MouseRegion` and `_hovered` state added; border animates on hover when no image is set

Full diff: `git diff main -- apps/shop_pos`

</details>
