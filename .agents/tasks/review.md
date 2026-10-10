# Product database wiring: seeding gate, delete/deactivate API, and CSV import

Five changes land together: a compile-time flag to suppress demo products at startup, a DELETE route on the API that soft-deletes scoped by `businessId`, `deactivateProduct` and `updateProduct` on the API client, a `deactivateProduct` method in `PosState` that calls the API before updating local state, and a CSV import dialog in `InventoryView`. All five tasks are present and working. There are no blocking compile errors or security holes in this diff. The only issue worth flagging is a maintenance hazard from a local-only `deleteProduct` method that diverges from the API's soft-delete semantics.

**Watch for:**
- **confirmed** — `deleteProduct` in `pos_state.dart` is a local-only hard-purge with no API call. It is not called from any UI path in this diff, but it remains reachable code that silently bypasses the server if called by a future contributor.
- **possible** — The UUID regex in `deactivateProduct` uses `[1-8]` as the version nibble rather than the standard `[1-5]`. UUIDs v6–v8 (time-ordered variants) would be rejected as non-API products and silently skip the API call.

**Verdict**: APPROVED

---

## High-level view

The seeding gate is correct: `_includeDemoProducts` defaults to `false` via `bool.fromEnvironment('POS_DEMO_DATA', defaultValue: false)`. `_initSampleData` branches on `includeProducts` and assigns an empty list when false. `loadInitialState` additionally strips `prod_1`–`prod_10` IDs from persisted storage and rewrites the list, so devices that stored demo data on an older build are cleaned on the next launch.

The DELETE route performs a `findFirst` scoped to `businessId` before the soft-delete update, returning 404 for products belonging to other businesses. It is idempotent — already-deactivated products return 200 with the current state. The PATCH route also has the `findFirst` ownership check; the prior review's concern about PATCH missing `businessId` scope was incorrect.

Both `deactivateProduct` (DELETE) and `updateProduct` (PATCH) are present in `ApiService`. `PosState.deactivateProduct` calls the API only when there is a valid token and the product ID matches a UUID regex, leaving locally-created `prod_${timestamp}` IDs as local-only operations. The CSV parser is a correct RFC 4180 implementation with `""` escaping, CRLF/LF support, BOM stripping, unclosed-quote detection, and blank-row skipping. Price and stock validation guards negative values.

---

<details>
<summary>Issues (1)</summary>

1. **`deleteProduct` local-only hard-purge** — `pos_state.dart` exposes `deleteProduct(String productId)` which removes the product from the in-memory list and persists — no API call. The UI currently calls `deactivateProduct` for the delete action, so no user-visible breakage exists today. But the method is reachable and its name implies a delete action that silently diverges from the API's soft-delete. Either remove it, or add an API call to match `deactivateProduct`'s behavior.

</details>

---

<details>
<summary>Details</summary>

## Seeding gate

```dart
static const bool _includeDemoProducts = bool.fromEnvironment(
  'POS_DEMO_DATA',
  defaultValue: false,
);
```

`_initSampleData(includeProducts: _includeDemoProducts)` assigns `products = <PosProduct>[]` when false. `loadInitialState` strips IDs matching `^prod_(?:[1-9]|10)$` from any persisted list and rewrites storage. The regex covers `prod_1` through `prod_10` and nothing else — correct.

## DELETE route `businessId` scope

```ts
const existing = await prisma.product.findFirst({
  where: { id: req.params.id, businessId },
  select: { id: true, active: true },
});
if (!existing) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
```

Products from other businesses return 404 rather than being deactivated. The update then uses `{ id: existing.id }` — already confirmed to belong to this business — so no cross-tenant write is possible.

## UUID version nibble in `deactivateProduct`

```dart
final isApiProduct = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(productId);
```

The version nibble `[1-8]` accepts UUIDs v1–v8. Standard RFC 4122 defines v1–v5 only; v6–v8 are draft extensions that Prisma does not generate. In practice this is harmless — Prisma generates v4 UUIDs — but is worth noting if the UUID generation strategy ever changes.

## CSV import

`_parseCsv` is a character-by-character state machine. It handles:
- `""` inside a quoted field as a literal `"`
- CRLF and bare LF as row terminators
- UTF-8 BOM stripping before parsing
- Unclosed-quote detection (throws `FormatException`)
- Blank-row skipping

The validation line:
```dart
if (name.isEmpty || sku.isEmpty || category.isEmpty || stock < 0 || price.isZero || price.minorUnits < 0)
```
guards against zero, negative, and unparseable prices. The preview-and-confirm dialog shows up to 6 rows and the import count before committing.

## Task completion check

| Task | Present | Notes |
|------|---------|-------|
| 1. Demo seeding removed from `_initSampleData` | ✓ | Default `false`; load-time cleanup; correct |
| 2. DELETE route in `products.router.ts` | ✓ | `businessId`-scoped; idempotent; correct |
| 3. `deactivateProduct` + `updateProduct` in `api_service.dart` | ✓ | Both methods present and correct |
| 4. `deleteProduct` / `deactivateProduct` in `pos_state.dart` calls API | ✓ | `deactivateProduct` calls the API; UI wired to it |
| 5. CSV import dialog in `inventory_view.dart` | ✓ | Parser correct; preview guard present |

</details>

---

<details>
<summary>File map</summary>

| File | What changed |
|------|-------------|
| `apps/shop_pos/lib/pos_state.dart` | `_initSampleData` branches on `includeProducts`; `_includeDemoProducts` defaults to `false`; new `deactivateProduct` calls the API; `loadInitialState` strips demo IDs from persisted state |
| `apps/shop-api/src/modules/products/products.router.ts` | New `DELETE /:id` route; soft-deletes via `active: false` after `businessId`-scoped ownership check |
| `apps/shop_pos/lib/services/api_service.dart` | `deactivateProduct` (DELETE) and `updateProduct` (PATCH) added |
| `apps/shop_pos/lib/views/inventory_view.dart` | `_importProductsCsv` + `_parseCsv` added; "Import CSV" button wired in header; delete confirmation calls `deactivateProduct` |

Full diff: `git diff main -- apps/shop_pos/lib apps/shop-api/src`

</details>
