# POS App Health Report

**Date:** Investigation run (read-only)  
**Scope:** Flutter web POS (`apps/shop_pos`) + shop-api (`apps/shop-api`)

---

## Executive Summary

The app has a **fundamental architecture split**: the shop-api is a properly
designed database-backed REST API (Postgres via Prisma, JWT auth, full audit
trail), but the Flutter POS **never connects to it for any product, category,
customer, or sales data**. All data lives in `shared_preferences` (browser
`localStorage`) with 10 hardcoded demo products and 5 hardcoded users seeded on
every fresh load. Delete works visually but only removes from local storage —
nothing touches the database. The API has no DELETE endpoint for products at all,
and `ApiService` has no PATCH/DELETE for products either.

**What works:**
- The API health check (`GET /health`) is called.
- The API login (`POST /auth/login`) is defined but the POS login screen never
  calls it — users are authenticated against the hardcoded local list.
- The shop-api routes for products (GET/POST/PATCH/adjust-stock), categories
  (GET/POST/PATCH), customers, and sales are all implemented and correct.
- The Prisma schema is well-designed with proper audit trails and immutable
  ledger patterns.

**What is broken / missing:**
1. Products, categories, customers, and sales are never read from or written to
   the API.
2. `deleteProduct` only mutates in-memory state + `shared_preferences`. No API
   call. The API has no DELETE route for products at all.
3. 10 hardcoded demo products are seeded on every fresh start.
4. The seed script (`seed.ts`) correctly seeds only product *categories* (no
   products), but the Flutter app ignores this entirely.
5. No import feature exists anywhere — not in the API, not in the Flutter UI.
6. `ApiService.baseUrl` is hardcoded to `http://localhost:4000`; in production
   it would need to point to the deployed API. (There is a `serverUrl` setting
   in `PosState` but it is never passed to `ApiService`.)

---

## 1. Hardcoded Products — Exact Location

**File:** `apps/shop_pos/lib/pos_state.dart`

### How they arrive

`PosState`'s constructor (line ~405) calls `_initSampleData()` unconditionally,
then calls `_loadFromStorage()`. `_initSampleData()` calls three helpers in
sequence:

```dart
// pos_state.dart  constructor
PosState() {
  _initSampleData();      // ← seeds hardcoded data into memory first
  _loadFromStorage();     // ← THEN overwrites from shared_preferences if saved data exists
}
```

`_initSampleData()` calls:
- `_initDefaultUsers()` — creates 5 hardcoded `PosUser` objects (John Mwangi,
  Wanjiku Karanja, Amina Hassan, Otieno Juma, David Kamau) with plain-text PINs.
- `_initDefaultCategories()` — creates 10 hardcoded `PosCategory` objects
  (Dairy, Bakery, Beverages, Produce, Groceries, Snacks, Household, Health,
  Cleaning, Other).
- `_initDefaultProducts()` — creates **10 hardcoded `PosProduct` objects** with
  ids `prod_1`…`prod_10` (Fresh milk 500ml, White bread 400g, Farm eggs, Supa
  maize flour, Fresh tomatoes, Long-life yoghurt, Cooking oil, Sweet Bananas,
  Kenya Cane, Basmati Rice).

`_loadFromStorage()` then reads `products_json` from `shared_preferences`. If
the key exists, it overwrites the in-memory list. If it does **not** exist (first
install, or after clearing storage), the 10 demo products remain.

### Why products appeared on the live server

When the Docker image was first run on the live server, `shared_preferences` was
empty, so `_initDefaultProducts()` was the only source of data. The user then
browsed the app (which persists on any save operation), which wrote the demo
products to localStorage, making them look "installed."

### How to remove them

`_initSampleData()` must stop seeding products and users as defaults. The correct
fix is:

1. In `_initSampleData()`, set `products = []` and `users = []` instead of
   calling `_initDefaultUsers()` and `_initDefaultProducts()`.
2. Keep `_initDefaultCategories()` as a fallback only if `categories_json` is
   also empty (categories are needed for the app to function even before the API
   is connected).
3. Delete the `_initDefaultProducts()` and `_initDefaultUsers()` methods, or
   gate them behind a "Reset to demo" button that only owners can reach.
4. On first load with an empty product list, show an empty-state prompt ("No
   products yet — add your first product or import a catalogue").

---

## 2. Delete Functionality — Why It Doesn't Work

### Flutter side

`deleteProduct` in `pos_state.dart`:

```dart
void deleteProduct(String productId) {
  products.removeWhere((p) => p.id == productId);
  notifyListeners();
  _persistAll();
}
```

This removes the product from the in-memory list and writes the updated list to
`shared_preferences`. **No API call is made.** So:
- If the API is the source of truth, the product reappears on the next page
  reload (because `loadInitialState` would re-fetch from the API — except it
  doesn't do that either).
- In the current all-local architecture, the visual delete *does* work, but only
  until the browser storage is cleared or the user opens the app on a different
  device.

### API side

`apps/shop-api/src/modules/products/products.router.ts` defines:
- `GET /products`
- `GET /products/barcode/:barcode`
- `GET /products/:id`
- `POST /products`
- `PATCH /products/:id`
- `POST /products/:id/adjust-stock`

**There is no `DELETE /products/:id` route.** The schema's `Product` model has
an `active` boolean, which is the intended soft-delete mechanism (the `PATCH`
route can set `active: false`). A hard delete is intentionally absent because
`SaleItem` holds a non-nullable FK to `Product` — deleting a product that has
been sold would violate the foreign key constraint.

### What needs to change

The correct delete strategy is a **soft delete**:

1. Add `PATCH /products/:id` with `{ active: false }` — this already exists in
   the API via `UpdateProductSchema` which includes `active`.
2. In `ApiService`, add an `updateProduct(id, payload)` method that calls
   `PATCH /products/:id`.
3. Change `PosState.deleteProduct()` to call `apiService.updateProduct(id, {active: false})`
   on the API, then remove from local state on success.
4. The `GET /products` list query already defaults to `active: true`, so
   deactivated products naturally drop off the list.

---

## 3. API Connectivity — What Exists vs What Is Called

### ApiService base URL

```dart
// api_service.dart
String baseUrl = 'http://localhost:4000';
```

This is hardcoded. There is a `serverUrl` field in `PosState` that the Settings
view can modify (default `'http://localhost:3000'` — note: different port), but
it is **never passed into `ApiService.instance`**. The two are completely
disconnected.

### API methods defined in ApiService

| Method | API call made | Notes |
|---|---|---|
| `checkHealth()` | `GET /health` | Called somewhere in settings to test connectivity |
| `login()` | `POST /auth/login` | Defined, but the login screen uses local PIN matching |
| `getProducts()` | `GET /products?limit=200` | Defined but never called |
| `createProduct()` | `POST /products` | Defined but never called |
| `adjustStock()` | `POST /products/:id/adjust-stock` | Defined but never called |
| `getCustomers()` | `GET /customers` | Defined but never called |
| `createCustomer()` | `POST /customers` | Defined but never called |
| `recordCustomerPayment()` | `POST /customers/:id/payments` | Defined but never called |
| `getSales()` | `GET /sales?limit=50` | Defined but never called |
| `submitSale()` | `POST /sales` | Defined but never called |
| `reverseSale()` | `POST /sales/:id/reverse` | Defined but never called |
| `getDashboardReport()` | `GET /business/reports/dashboard` | Defined but never called |

**Missing from ApiService:**
- `updateProduct(id, patch)` → `PATCH /products/:id`
- `deleteProduct(id)` → would be `PATCH /products/:id` with `{active: false}`
- `getCategories()` → `GET /categories`
- `createCategory()` → `POST /categories`
- `updateCategory()` → `PATCH /categories/:id`

### API routes that exist in shop-api

| Route | Auth required | Notes |
|---|---|---|
| `GET /health` | No | Works |
| `POST /auth/login` | No | PIN + phone → JWT |
| `GET /products` | Yes | Paged, filterable |
| `GET /products/barcode/:code` | Yes | |
| `GET /products/:id` | Yes | |
| `POST /products` | Yes | Creates + optional opening stock |
| `PATCH /products/:id` | Yes | Partial update; `active: false` = soft delete |
| `POST /products/:id/adjust-stock` | Yes | Signed delta + stock movement log |
| `GET /categories` | Yes | |
| `POST /categories` | Yes | |
| `PATCH /categories/:id` | Yes | |
| `GET /customers` | Yes | |
| `POST /customers` | Yes | |
| `POST /customers/:id/payments` | Yes | |
| `GET /sales` | Yes | |
| `POST /sales` | Yes | |
| `POST /sales/:id/reverse` | Yes | |
| `GET /business/reports/dashboard` | Yes | |

**Missing from the API:**
- `DELETE /categories/:id` — no delete for categories
- `DELETE /products/:id` — intentionally absent (soft delete via PATCH instead)
- `POST /products/bulk-import` — does not exist

---

## 4. Categories — Hardcoded or Database?

### In the API (Prisma schema)

`Category` is a proper database model in `schema.prisma`:
```prisma
model Category {
  id         String   @id @default(uuid())
  businessId String
  name       String
  colorHex   String   @default("#0D9488")
  sortOrder  Int      @default(0)
  // ...
  @@unique([businessId, name])
}
```

The seed script (`seed.ts`) creates 6 default categories on provisioning: Food,
Drinks, Household, Personal Care, Bakery, Frozen. These are empty — no products
are seeded.

### In the Flutter app

Categories in `PosState` are stored as `List<PosCategory>` in memory and
persisted to `categories_json` in `shared_preferences`. They are **completely
disconnected from the database**.

The Flutter category model (`PosCategory`) stores `colorValue` as an `int` and
`iconKey` as a string, while the API category model stores only `colorHex` (a
hex string) and has no `iconKey`. These schemas are mismatched and would need
reconciliation when wiring up the API.

---

## 5. Variants

`PosProduct` in the Flutter app has `groupId` and `variantLabel` fields for
grouping variants. The Prisma `Product` model has **no `groupId` or `variantLabel`
field**. The variant concept exists only in the Flutter client; it would need a
migration to add these columns to the `products` table before the API can
persist them.

---

## 6. Import Functionality — What Needs to Be Built

No import feature exists anywhere in the codebase. There is no:
- `POST /products/bulk-import` route in the API
- CSV or Excel parsing library in `pubspec.yaml`
- Import dialog or screen in the Flutter app
- File picker wired to a product import flow

What needs to be built for a complete import feature:

### API side
1. `POST /products/bulk-import` — accepts a JSON array of products (or a
   multipart CSV upload). Validates each row (name, salePrice required; SKU
   optional but unique per business). Creates products in a single transaction
   with opening stock movements. Returns a summary: `{created, updated, errors[]}`.
2. `POST /categories/bulk-import` — accepts a JSON array of category names,
   upserts them (no duplicates).

### Flutter side
3. An import dialog in the Inventory view with:
   - A file picker for CSV (or a manual JSON paste area for an MVP)
   - A column-mapping step (CSV header → product field)
   - A preview/validation table showing rows with errors highlighted
   - A "Confirm import" button that calls the API
4. The CSV format should minimally require: `name`, `sale_price`. Optional:
   `sku`, `barcode`, `category`, `cost_price`, `unit`, `initial_stock`,
   `low_stock_threshold`.

---

## 7. State Persistence — Summary

| Entity | How PosState stores it | API involvement |
|---|---|---|
| Products | `shared_preferences` key `products_json` | None |
| Categories | `shared_preferences` key `categories_json` | None |
| Users | `shared_preferences` key `users_json` | None |
| Customers | In-memory only — not persisted at all | None |
| Sales | In-memory only — not persisted at all | None |
| Cash shift | In-memory only | None |
| Session/login | `shared_preferences` keys `session_*` | None |
| Settings | `shared_preferences` keys per field | None |

Customers and sales are **lost on page reload**. This is the most critical data
integrity issue beyond the demo product problem.

---

## Prioritized Fix List

### P0 — Breaks data integrity on production

1. **Remove hardcoded demo products and users from `_initSampleData()`.**
   Set `products = []` and `users = []` instead of calling the `_initDefault*`
   methods. Show an empty state with an onboarding prompt.
   - File: `apps/shop_pos/lib/pos_state.dart`, `_initSampleData()` method.

2. **Wire login to the API.**
   The login screen must call `ApiService.login(phone, pin)` and store the
   returned JWT. On success, decode the JWT to get the user's role and name.
   Replace the local PIN comparison loop with the API call.
   - File: `apps/shop_pos/lib/views/login_view.dart`, `apps/shop_pos/lib/services/api_service.dart`.

3. **Wire `loadInitialState()` to fetch products from the API.**
   After a successful login, call `ApiService.getProducts()` and populate
   `products`. Fall back to `shared_preferences` cache if the API is unreachable
   (offline mode). Save the API response to `products_json` as the offline cache.
   - File: `apps/shop_pos/lib/pos_state.dart`, `loadInitialState()`.

### P1 — Core feature broken

4. **Fix `deleteProduct` to soft-delete via the API.**
   Add `ApiService.updateProduct(id, {active: false})` and call it from
   `deleteProduct`. On API success, remove from local state. On failure, show
   an error and keep the product in the list.
   - Files: `apps/shop_pos/lib/services/api_service.dart`,
     `apps/shop_pos/lib/pos_state.dart`.

5. **Wire `createProduct` / `saveProduct` to the API.**
   Call `ApiService.createProduct(payload)` or `ApiService.updateProduct()`.
   Use the API-returned `id` for new products (remove the
   `'prod_${DateTime.now().millisecondsSinceEpoch}'` client-generated id pattern
   — UUIDs should come from the server).
   - Files: `apps/shop_pos/lib/pos_state.dart`,
     `apps/shop_pos/lib/views/widgets/product_editor_dialog.dart`.

6. **Fix the `ApiService.baseUrl` / `serverUrl` disconnect.**
   `PosState.serverUrl` is configurable in settings but `ApiService.instance.baseUrl`
   never reads it. Add a listener or pass the URL during init:
   ```dart
   ApiService.instance.baseUrl = serverUrl;
   ```
   - Files: `apps/shop_pos/lib/pos_state.dart`,
     `apps/shop_pos/lib/services/api_service.dart`.

### P2 — Data lost on reload

7. **Persist sales and customers via the API.**
   `completeSale()` should call `ApiService.submitSale()`. `loadInitialState()`
   should call `ApiService.getSales()` to restore the ledger. Same pattern for
   customers.
   - File: `apps/shop_pos/lib/pos_state.dart`.

8. **Wire categories to the API.**
   Reconcile the `PosCategory` (colorValue int, iconKey) model with the API
   `Category` model (colorHex string, no iconKey). Either add `iconKey` to the
   Prisma schema or map between the two formats.
   - Files: `apps/shop-api/prisma/schema.prisma` (add iconKey column),
     `apps/shop_pos/lib/pos_state.dart`.

### P3 — New feature

9. **Build the bulk import feature (products, categories, variants).**
   - API: add `POST /products/bulk-import` in `products.router.ts`.
   - API: add `POST /categories/bulk-import` in `categories.router.ts`.
   - Flutter: add an import dialog with CSV file picker and column mapping.
   - Schema: add `groupId` (uuid, nullable) and `variantLabel` (string, nullable)
     columns to the Prisma `Product` model and generate a migration.

10. **Add `DELETE /categories/:id` to the categories API.**
    The Flutter category manager already has delete logic; the API endpoint is
    missing. Add a route that either deletes the category (if no products use it)
    or returns a 409 with a count of affected products.
    - File: `apps/shop-api/src/modules/categories/categories.router.ts`.

---

## Key Files Reference

| File | Role |
|---|---|
| `apps/shop_pos/lib/pos_state.dart` | All Flutter state, persistence, hardcoded seeds |
| `apps/shop_pos/lib/services/api_service.dart` | HTTP client — defined but mostly uncalled |
| `apps/shop_pos/lib/views/inventory_view.dart` | Inventory UI, delete call site (line 614) |
| `apps/shop-api/src/modules/products/products.router.ts` | Product CRUD — no DELETE route |
| `apps/shop-api/src/modules/categories/categories.router.ts` | Categories — no DELETE route |
| `apps/shop-api/src/index.ts` | Route registration, BUSINESS_ID scoping |
| `apps/shop-api/prisma/schema.prisma` | Database schema — no groupId/variantLabel on Product |
| `apps/shop-api/src/scripts/seed.ts` | Seeds categories only, no products — correct behaviour |
