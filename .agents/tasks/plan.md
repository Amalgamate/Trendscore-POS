# Implementation Plan — Phase 1: Permanent Product Deletion

**Branch:** `pos-improvements`
**Repo root:** `c:\Amalgamate\Projects\Trends CORE Apps\Retail POS`
**Baselines to protect:**
- `npm test` → 148 tests pass (run from repo root)
- `npm run typecheck` → 0 errors
- `dart analyze lib` (from `apps/shop_pos`) → ≤ 166 issues

---

## Reading notes (discoveries from actual file reads)

- Migration `0001_immutable_ledgers` installs the trigger **`stock_movements_no_delete`** (calls `retail_os_forbid_mutation()`). That trigger and its peer `stock_movements_no_update` live in that file and must not be touched except as specified below.
- The existing `verify-immutability.sql` already has test 3 ("plain DELETE on stock_movements must be rejected"). New tests append after that section.
- `products.router.ts` `DELETE /:id` currently calls `prisma.product.update({ data: { active: false } })` — a soft-delete. It also admits STOCK_CLERK via `requireRole('OWNER', 'MANAGER', 'STOCK_CLERK')`. Both change.
- Prisma `Product` → `ProductImage` is `onDelete: Cascade`, so deleting the product row also removes its images automatically — no explicit image delete needed in the transaction.
- Prisma `Product` → `StockMovement` is `onDelete: Restrict`. The trigger replacement + the `$queryRaw SET LOCAL` is how we break past that restriction inside the controlled transaction.
- `SaleItem`, `PurchaseItem`, `RefundItem` all carry `onDelete: Restrict` on their `product` FK, so the history check must precede any DELETE attempt.
- `api_service.dart` has `deactivateProduct(productId)` (calls `DELETE /products/:id`) and `setProductActive()` (calls `PATCH`). `deleteProduct` does not exist yet in the service — this is a new method.
- `pos_state.dart` has `deleteProduct()` delegating to `deactivateProduct()`, and a `deactivateProduct()` that calls `ApiService.instance.deactivateProduct()`. Both need new behaviour.
- The Flutter `_confirmDelete` dialog in `inventory_view.dart` currently deactivates; it must become a permanent-delete flow.
- Test style from `create-sale.test.ts`: `vi.fn()` mocks on a hand-built Prisma stand-in, no real DB. Same pattern for the new test file.
- `npm test` runs `vitest run` inside `apps/shop-api/`. `npm run typecheck` runs `tsc --noEmit`.
- Plan progress dashboard: Phase 1 has 15 checkboxes. After Phase 1 the dashboard row should read `Done | 15 / 15` and Total should be `31 / 141`.

---

## Plan

- [ ] 1. **Write migration `0006_product_purge`**
  Drop the trigger `stock_movements_no_delete` that unconditionally rejects all DELETEs on `stock_movements`.
  Create a replacement trigger function `retail_os_stock_movements_purge_guard()` and a trigger
  `stock_movements_purge_guard` (BEFORE DELETE, FOR EACH ROW) that:
  - Reads `current_setting('app.purge_product_id', true)` (the `true` makes it return NULL rather than
    raise when the setting is absent).
  - Allows the DELETE only when that setting equals `OLD."productId"::text` AND
    no rows exist in `sale_items`, `purchase_items`, or `refund_items` for `OLD."productId"`.
  - Otherwise raises the same `restrict_violation` that the old function raised,
    keeping the error message identical: `'Table % is append-only. DELETE is not permitted…'`
  Leave `stock_movements_no_update` completely untouched.

  File: `apps/shop-api/prisma/migrations/0006_product_purge/migration.sql`

  Verify: apply with `psql -f migration.sql` on a scratch database and confirm the trigger exists.
  Full regression is verified in step 6. The migration itself does not need to pass `npm test` on its own — the test suite uses a mocked Prisma client, not a real DB.

---

- [ ] 2. **Extend `verify-immutability.sql`**
  Append two new test blocks after the existing test 3 (plain DELETE on stock_movements) — keeping all
  existing tests intact and still at the top.

  **Test 3d — plain DELETE without `app.purge_product_id` still rejected.**
  Uses the same fixture product `55555555…` and movement `66666666…` already inserted above.
  Attempts a bare `DELETE FROM stock_movements` (no SET LOCAL) and expects `restrict_violation`.

  **Test 3e — DELETE with `app.purge_product_id` set but the product HAS sale_items is rejected.**
  Insert a minimal `sale` row, then a `sale_items` row referencing product `55555555…`.
  Run inside a `BEGIN`/`ROLLBACK` sub-block so the sale rows do not persist:
  ```sql
  DO $$
  BEGIN
    BEGIN
      PERFORM set_config('app.purge_product_id',
                         '55555555-5555-5555-5555-555555555555', true);
      DELETE FROM stock_movements WHERE id = '66666666-...';
      RAISE EXCEPTION 'FAIL: purge was allowed with sale_items present';
    EXCEPTION WHEN restrict_violation THEN
      RAISE NOTICE 'PASS: purge blocked when product has sale_items';
    END;
  END;
  $$;
  ```
  (Full fixture IDs to match the existing file's UUID style are in the file itself.)

  File: `apps/shop-api/prisma/verify-immutability.sql`

  Verify: `psql -f apps/shop-api/prisma/verify-immutability.sql` against a database where migration
  `0006_product_purge` has been applied. All `PASS:` notices printed, no `FAIL:` lines, script exits 0.

---

- [ ] 3. **Rewrite `DELETE /products/:id` in `products.router.ts`**
  Replace the current soft-delete handler entirely. New behaviour:

  a. Auth: `requireAuth` + `requireRole('OWNER', 'MANAGER')` — remove STOCK_CLERK.

  b. Business scope: `prisma.product.findFirst({ where: { id, businessId } })` — 404 if not found
  (this already scopes by `businessId` since the router is mounted per-business).

  c. History check: three `prisma.*.count()` calls in parallel (`saleItems`, `purchaseItems`,
  `refundItems` all filtered by `productId`). If any count > 0, return:
  ```json
  { "code": "PRODUCT_HAS_HISTORY", "counts": { "saleItems": N, "purchaseItems": N, "refundItems": N } }
  ```
  as a 409 using `sendError(res, 409, 'PRODUCT_HAS_HISTORY', 'Product has transaction history …', { counts })`.
  Check the signature of `sendError` in `src/lib/http.ts` first; if it does not accept a fourth details
  argument, spread the counts into the message or adjust as needed without changing the function signature.

  d. Stock guard: read `product.stock`. If `Number(product.stock) > 0` and `req.body.discardStock !== true`,
  return `sendError(res, 422, 'NON_ZERO_STOCK', 'Product has stock…', { stock: Number(product.stock) })`.
  Stock is read from the `product` found in step (b) — no second query needed.

  e. Purge transaction (all in `prisma.$transaction`):
  1. `SET LOCAL app.purge_product_id = '<id>'` via `tx.$queryRaw(Prisma.sql`SET LOCAL …`)` — this scopes
     the permission to this transaction only.
  2. `tx.stockMovement.deleteMany({ where: { productId: id } })` — removes opening-stock rows; the new
     trigger function allows this because the SET LOCAL is in place and no sale/purchase/refund rows exist.
  3. `tx.product.delete({ where: { id } })` — Prisma cascade removes `ProductImage` rows automatically
     (schema has `onDelete: Cascade`).
  4. `tx.auditLog.create({ data: { businessId, userId: auth.userId, action: 'PRODUCT_PURGE', entityType: 'PRODUCT', entityId: id, beforeJson: { name, sku, barcode, costPrice: Number(product.costPrice), salePrice: Number(product.salePrice), stock: Number(product.stock), discardedQty: Number(product.stock) > 0 ? Number(product.stock) : 0, userId: auth.userId } } })`.

  f. Return `send200(res, { id, purged: true })`.

  Add the Zod body schema:
  ```typescript
  const DeleteProductSchema = z.object({ discardStock: z.boolean().optional() });
  ```
  Parse it with `parseBody` before the history check (but make body optional so a plain DELETE with no
  body still works — use `.safeParse` if `parseBody` would 400 on an empty body, or default to `{}`).

  File: `apps/shop-api/src/modules/products/products.router.ts`

  Verify: `npm run typecheck` (from repo root) → 0 errors.

---

- [ ] 4. **Add `POST /products/:id/archive`**
  New route in the same `productsRouter`, immediately after the DELETE handler.
  - `requireAuth` + `requireRole('OWNER', 'MANAGER')`.
  - Find product by `{ id, businessId }` — 404 if not found.
  - If already inactive (`!product.active`), return `send200(res, { id, active: false })` immediately (idempotent).
  - Otherwise: `prisma.product.update({ where: { id }, data: { active: false } })`.
  - Return `send200(res, { id, active: false })`.

  File: `apps/shop-api/src/modules/products/products.router.ts`

  Verify: `npm run typecheck` → 0 errors.

---

- [ ] 5. **Write API tests `test/products-delete.test.ts`**
  Follow the exact mock pattern from `test/create-sale.test.ts`: import from `vitest`, build a
  `makePrisma()` helper that returns a mock `PrismaClient` and a `tx` object with `vi.fn()` for every
  method used, pass the mock through `prisma.$transaction`.

  Because `products.router.ts` uses the module-level `prisma` singleton (imported from `../../lib/prisma`),
  mock that module: `vi.mock('../../src/lib/prisma', () => ({ prisma: mockPrismaClient }))`.

  Test cases (one `describe` block per scenario, `it()` assertions):

  1. **No-history product, zero stock → deleted and gone.**
     `saleItem.count`, `purchaseItem.count`, `refundItem.count` all resolve `0`.
     `product.stock` is `0`. Expect `stockMovement.deleteMany` called with `{ where: { productId } }`,
     `product.delete` called with the id, `auditLog.create` called with `action: 'PRODUCT_PURGE'`,
     response 200 `{ id, purged: true }`.

  2. **Product with sale_items → 409 PRODUCT_HAS_HISTORY with counts.**
     `saleItem.count` resolves `3`, others `0`. Expect 409, `code: 'PRODUCT_HAS_HISTORY'`,
     `counts.saleItems === 3`.

  3. **Wrong businessId → 404.**
     `product.findFirst` resolves `null`. Expect 404.

  4. **CASHIER role → 403.**
     Set `res.locals.auth.role = 'CASHIER'`. Expect 403 before any DB query.

  5. **STOCK_CLERK role → 403.**
     Same as above with `'STOCK_CLERK'`.

  6. **Opening-stock movements removed.**
     Verify `stockMovement.deleteMany` is called (same as case 1, but assert call args explicitly).

  7. **`auditLog.create` called with correct `beforeJson`.**
     Product has `name: 'Test', sku: 'T-001', stock: 0`. Assert `beforeJson.name === 'Test'` and
     `beforeJson.discardedQty === 0`.

  8. **Non-zero stock without `discardStock` → 422 NON_ZERO_STOCK.**
     `product.stock = 5`. No `discardStock` in body. Expect 422, `code: 'NON_ZERO_STOCK'`, `stock: 5`.

  9. **Non-zero stock with `discardStock: true` → succeeds, audit records discarded qty.**
     `product.stock = 5`, `body.discardStock = true`. Expect 200. Assert `auditLog.create` called with
     `beforeJson.discardedQty === 5`.

  10. **Archive route sets `active: false` (idempotent).**
      `POST /products/:id/archive`. `product.active = true` first call → `product.update` called,
      returns `{ id, active: false }`. Second call with `product.active = false` → update NOT called,
      still returns `{ id, active: false }`.

  File: `apps/shop-api/test/products-delete.test.ts`

  Verify: `npm test` (from repo root, runs `vitest run` in `apps/shop-api`) → 148 + new tests pass,
  0 failures. Check specifically that the 148 existing tests still pass.

---

- [ ] 6. **Update `api_service.dart` — `deleteProduct` and `archiveProduct`**
  Make the following targeted changes to `apps/shop_pos/lib/services/api_service.dart`:

  a. **Replace the existing `deactivateProduct` method** (the one that sends `DELETE /products/:id`).
  The new method is `deleteProduct(String productId, { bool discardStock = false })`:
  ```dart
  Future<({bool ok, String? errorCode, Map<String, dynamic>? details})>
      deleteProduct(String productId, {bool discardStock = false}) async {
    lastError = null;
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/products/$productId'),
        headers: _headers,
        body: discardStock ? jsonEncode({'discardStock': true}) : null,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return (ok: true, errorCode: null, details: null);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>?;
      final code = error?['code'] as String?;
      final det = error?['details'] as Map<String, dynamic>?;
      lastError = error?['message'] as String? ?? 'Could not delete product.';
      return (ok: false, errorCode: code, details: det);
    } catch (e) {
      lastError = 'Could not delete the product on the shop API.';
      debugPrint('API deleteProduct error: $e');
      return (ok: false, errorCode: null, details: null);
    }
  }
  ```
  Keep `deactivateProduct` as a thin compatibility shim calling the old PATCH pattern, because
  `setProductActive` and the import de-duplicate flow still call it. **Do not remove `deactivateProduct`
  or `setProductActive`** — they are used by other code paths.

  b. **Add `archiveProduct(String productId)`**:
  ```dart
  Future<bool> archiveProduct(String productId) async {
    lastError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/products/$productId/archive'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return true;
      lastError = _messageFromResponse(res.body) ??
          'Could not archive product (${ res.statusCode}).';
      return false;
    } catch (e) {
      lastError = 'Could not archive the product on the shop API.';
      debugPrint('API archiveProduct error: $e');
      return false;
    }
  }
  ```

  File: `apps/shop_pos/lib/services/api_service.dart`

  Verify: `dart analyze lib` (from `apps/shop_pos`) → issue count ≤ 166 (no regressions).

---

- [ ] 7. **Update `pos_state.dart` — typed exceptions and new methods**
  Make the following targeted changes to `apps/shop_pos/lib/pos_state.dart`:

  a. **Add two typed exception classes near the top of the file** (after `PosException`):
  ```dart
  /// Thrown when a permanent delete is blocked because the product has history.
  class ProductHasHistoryException implements Exception {
    ProductHasHistoryException({required this.counts});
    final Map<String, dynamic> counts; // {'saleItems': N, 'purchaseItems': N, 'refundItems': N}
    @override
    String toString() => 'Product has transaction history and cannot be deleted.';
  }

  /// Thrown when a permanent delete is blocked because stock is non-zero
  /// and discardStock was not confirmed.
  class ProductHasStockException implements Exception {
    ProductHasStockException({required this.stock});
    final int stock;
    @override
    String toString() => 'Product has $stock unit(s) in stock. Confirm discard to proceed.';
  }
  ```

  b. **Rewrite `deleteProduct(String productId)`** (currently delegates to `deactivateProduct`):
  ```dart
  Future<void> deleteProduct(String productId, {bool discardStock = false}) async {
    final isApiProduct = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(productId);
    if (isApiProduct) {
      if (!ApiService.instance.hasToken) {
        throw PosException('Sign in before deleting a product.');
      }
      final result = await ApiService.instance.deleteProduct(
        productId, discardStock: discardStock,
      );
      if (!result.ok) {
        if (result.errorCode == 'PRODUCT_HAS_HISTORY') {
          throw ProductHasHistoryException(counts: result.details ?? {});
        }
        if (result.errorCode == 'NON_ZERO_STOCK') {
          throw ProductHasStockException(
            stock: (result.details?['stock'] as num?)?.toInt() ?? 0,
          );
        }
        throw PosException(
          ApiService.instance.lastError ?? 'Could not delete product.',
        );
      }
    }
    products.removeWhere((p) => p.id == productId);
    notifyListeners();
    await _persistAll();
    // Re-fetch catalogue from server to ensure consistency.
    if (isApiProduct && ApiService.instance.hasToken) {
      await syncCatalogueFromApi();
    }
  }
  ```

  c. **Add `archiveProduct(String productId)`**:
  ```dart
  Future<void> archiveProduct(String productId) async {
    final isApiProduct = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(productId);
    if (isApiProduct) {
      if (!ApiService.instance.hasToken) {
        throw PosException('Sign in before archiving a product.');
      }
      final ok = await ApiService.instance.archiveProduct(productId);
      if (!ok) {
        throw PosException(
          ApiService.instance.lastError ?? 'Could not archive product.',
        );
      }
    }
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      products[idx] = products[idx].copyWith(isActive: false);
    }
    notifyListeners();
    await _persistAll();
    if (isApiProduct && ApiService.instance.hasToken) {
      await syncCatalogueFromApi();
    }
  }
  ```

  File: `apps/shop_pos/lib/pos_state.dart`

  Verify: `dart analyze lib` (from `apps/shop_pos`) → issue count ≤ 166.

---

- [ ] 8. **Update `inventory_view.dart` — permanent-delete dialog flow**
  Replace the existing `_confirmDelete(PosProduct product)` method in
  `apps/shop_pos/lib/views/inventory_view.dart` with the new three-stage flow below.
  Keep all other methods (`_showStockAdjustDialog`, `_toggleActive`, `_duplicateProduct`, etc.) unchanged.

  **New `_confirmDelete` logic (replace entire method):**

  ```dart
  Future<void> _confirmDelete(PosProduct product) async {
    // Stage 1: basic confirm dialog with product details.
    // The dialog has a "Discard stock" checkbox only when stock > 0.
    bool discardStock = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(children: [
            Icon(AppIcons.deleteForever, color: AppColors.status_danger),
            SizedBox(width: 8),
            Text('Permanently Delete Product?'),
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
                      style: const TextStyle(fontWeight: FontWeight.bold,
                                             color: AppColors.text_primary)),
                    TextSpan(text: ' (SKU: ${product.sku}).'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Current stock: ${product.stock} units',
                style: const TextStyle(fontSize: 13, color: AppColors.text_secondary)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.status_danger.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.status_danger.withAlpha(60)),
                ),
                child: const Text(
                  'This cannot be undone. Only products with no sales history can be permanently deleted.',
                  style: TextStyle(fontSize: 12, color: AppColors.status_danger),
                ),
              ),
              // Discard-stock checkbox — shown only when stock > 0.
              if (product.stock > 0) ...[
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Discard current stock (${product.stock} units)',
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
              // Disable button if stock > 0 and discard not ticked.
              onPressed: (product.stock > 0 && !discardStock)
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
      if (_selectedProduct?.id == product.id) setState(() => _selectedProduct = null);
      else setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${product.name}" permanently deleted.')),
      );
    } on ProductHasHistoryException catch (e) {
      // Stage 3a: product has history — dismiss and offer archive.
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
      // Stage 3b: should not reach here (button disabled above) — defensive fallback.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tick "Discard current stock" to delete a product with stock.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete product: $error')),
      );
    }
  }
  ```

  Add the import for the new exception classes at the top of the file:
  ```dart
  import '../pos_state.dart'; // already imported — just confirm ProductHasHistoryException
                               // and ProductHasStockException are visible
  ```
  (No new import needed since `pos_state.dart` is already imported.)

  File: `apps/shop_pos/lib/views/inventory_view.dart`

  Verify: `dart analyze lib` (from `apps/shop_pos`) → issue count ≤ 166.

---

- [ ] 9. **Tick Phase 1 checkboxes and update `POS_IMPROVEMENTS_PLAN.md`**
  Change all 15 `- [ ]` items in the **Phase 1** section to `- [x]`.
  Update the **Progress dashboard** table:
  - Phase 1 row: `Done | 15 / 15`
  - Total row: `In progress | 31 / 141`
  Add a dated Notes log entry:
  ```
  - YYYY-MM-DD: Phase 1 complete. Migration 0006_product_purge replaces the stock_movements_no_delete
    trigger with a narrow purge-guard. DELETE /products/:id hard-deletes with audit; POST
    /products/:id/archive is the safe fallback. Flutter shows discard-stock checkbox and history
    explanation with "Archive instead" action.
  ```
  (Use the actual commit date.)

  File: `POS_IMPROVEMENTS_PLAN.md`

  Verify: `npm run plan:check:pos` (from repo root) → prints `Dashboard matches checkboxes`.

---

- [ ] 10. **Run full verification and commit**
  Run these commands in order from the repo root and confirm each passes before the next:

  ```
  npm test          # must still report 148 + new tests, 0 failures
  npm run typecheck # must report 0 errors
  ```

  Then from `apps/shop_pos`:
  ```
  dart analyze lib  # must report ≤ 166 issues
  ```

  Stage exactly these files (no others):
  ```
  apps/shop-api/prisma/migrations/0006_product_purge/migration.sql
  apps/shop-api/prisma/verify-immutability.sql
  apps/shop-api/src/modules/products/products.router.ts
  apps/shop-api/test/products-delete.test.ts
  apps/shop_pos/lib/services/api_service.dart
  apps/shop_pos/lib/pos_state.dart
  apps/shop_pos/lib/views/inventory_view.dart
  POS_IMPROVEMENTS_PLAN.md
  ```

  Commit message (exact):
  ```
  Phase 1: permanent product deletion
  ```

  Do NOT push.

  Verify: `git log --oneline -1` shows the commit on `pos-improvements` with the correct message.
  `git diff HEAD --name-only` shows only the eight files listed above.

---

## Dependency order summary

Steps 1 and 2 (migration + SQL verification) are independent and can be written first; they have no
TypeScript or Dart dependencies. Steps 3 and 4 (backend routes) depend only on the migration existing.
Step 5 (API tests) depends on steps 3 and 4 existing. Steps 6, 7, and 8 (Flutter) are independent of
each other but all depend on the API contract established in steps 3 and 4. Step 9 (plan tick) can
be done any time after confirming all work is correct. Step 10 (commit) is last.

## Constraints reminder

- Money and stock returned from Prisma are `Decimal` objects — always wrap with `Number(...)` in TypeScript
  before embedding in JSON or doing comparisons, never use the raw `Decimal` as a number.
- The `$queryRaw SET LOCAL` for `app.purge_product_id` must be the **first** statement inside the
  `$transaction` callback, before `deleteMany` — `SET LOCAL` is scoped to the current transaction and
  takes effect immediately.
- Do not touch any other plan file (not `STOREFRONT_PLAN.md`, not any other phase file).
- Do not start Phase 2.

---

## Phase 1 verification results (2026-11-03, iteration 2 — review findings fixed)

| Check | Result |
|---|---|
| `npm test` (shop-api vitest) | **74 tests passed** (63 existing + 11 new), 0 failures |
| `npm run typecheck` (shop-api tsc) | **0 errors** |
| `dart analyze lib` (shop_pos) | **106 issues** (≤ 166 baseline) |

### Review findings addressed
- **deactivateProduct-shim-hits-hard-delete** (blocking): `ApiService.deactivateProduct` now calls `POST /products/:id/archive` instead of `DELETE /products/:id`.
- **archive-route-no-audit-log** (blocking): Archive route now wraps in `$transaction` and creates an `auditLog` row with `action: 'PRODUCT_ARCHIVED'`.
- **test-3e-implicit-cleanup** (advisory): Test 3e in `verify-immutability.sql` now uses `SAVEPOINT before_3e` / `ROLLBACK TO SAVEPOINT before_3e` so inserted sale data is cleaned up within the test block.
- **test7-duplicate-assertion** (advisory): Removed the duplicate dead first `mockResolvedValue` call in test 8 (the earlier redundant mock that was immediately overridden).
