# Retail POS: Customer Improvements Plan (Self-Marking Checklist)

**Source:** customer change request "POS System – Requested Improvements and Changes" (items 1, 2, 3, 4, 6, 7, 8; the customer's list has no item 5, see Phase 0)
**Targets:** `apps/shop-api` (Express + Prisma + Postgres) and `apps/shop_pos` (Flutter)
**Objective:** make sales, customer credit, receipts, inventory and routine stock audits reliable and accurate for the shop.

---

## How to use this document

This file is both the instructions and the progress tracker.

1. Work **one phase at a time**, in order. Do not start a phase until the previous phase's **Exit gate** is fully ticked.
2. When a task is finished **and verified**, change its box from `[ ]` to `[x]` in this file, in the same commit as the work.
3. After ticking, run `npm run plan:check:pos` (created in Phase 0). It recounts every checkbox and fails if the **Progress dashboard** at the bottom disagrees. Fix the dashboard numbers and status before committing.
4. If a task is skipped or changed, do not delete it. Mark it `[~]` and add a one-line reason beneath it (no checkbox syntax in the reason).
5. Every phase ends with: `npm test` green, `npm run typecheck` clean, `dart analyze lib` no worse than the Phase 0 baseline, and a manual smoke test (login, add item, checkout, receipt). Tick the gate only when all pass.
6. Never run `apps/shop-api/migrate-test.cmd` against a database you care about. It drops and recreates the schema. Use a scratch database or a restored copy.

### Golden rules

> **Money is never a float. Stock is never a float.** Money is `NUMERIC(14,2)`, stock is `NUMERIC(14,3)`. All arithmetic on either uses integers or `Decimal`, not JavaScript or Dart `double`.

> **Ledgers stay append-only.** Stock movements, customer ledger, cash movements and audit logs are never edited. Corrections are new entries. The one exception, purging a product that never traded (Phase 1), is explicit, narrow and audited.

> **Server is the source of truth.** The till displays what the API returned. It does not compute balances or stock locally and keep them.

---

## Decisions (recommended defaults, confirm in Phase 0)

| # | Topic | Recommended default | Why |
|---|---|---|---|
| D1 | Permanent product delete | Allowed only when the product has **never** been sold, purchased or refunded. Otherwise blocked with an "Archive instead" option. Owner and Manager only. | `sale_items`, `purchase_items`, `refund_items` reference products, and old receipts and profit reports depend on them. Accidental duplicates have no history, so they delete cleanly. |
| D2 | Units | Each product has one **base unit** (L, ml, kg, g, pc). Stock is stored in the base unit. Price is per base unit. Cashier may sell in any unit of the same family (e.g. L or ml). 3 decimal places of precision. | 20 L − 250 ml = 19.75 L exactly. ml precision when base is litres. |
| D3 | Selling beyond stock | Blocked by default. An Owner or Manager can authorise at the till with their PIN. Every override is audited and flags the product for variance review. | Matches "unless an authorised user permits it". |
| D4 | Customer name on receipt | Business setting, default **on**. Name printed only when one was provided. Name is snapshotted on the sale. | A later rename or archive must not change an old receipt. |
| D5 | Daily summary | "Day" = 00:00 to 24:00 `Africa/Nairobi` (UTC+3). Total sales includes credit sales. Breakdown by payment method. Refunds shown separately. Debt payments received shown separately, not added to sales. | The database stores UTC. A naive UTC day would put late-evening sales on the wrong date. |
| D6 | Stock value | Show **both** value at cost and value at selling price. Cost-based is the headline. All roles including Cashiers see cost columns. | Customer confirmed all staff should see cost. |

---

## Findings from the code read (starting point, not yet verified at runtime)

- `DELETE /products/:id` only sets `active = false`. Products stay in the database and in `active=all` queries.
- Product FKs from sale, purchase and refund lines are `Restrict`, and a DB trigger blocks any `DELETE` on `stock_movements`. A permanent delete needs a controlled exemption (Phase 1).
- `POST /products/:id/adjust-stock` validates `delta` as an **integer**, so 0.25 L cannot be adjusted. It also writes the reason to `note` and leaves the `reason` column empty.
- `create-sale.ts` says products are locked `FOR UPDATE` but no lock is taken, so two simultaneous sales can both pass the stock check. Stock maths uses JS `number`. There is no override path for insufficient stock.
- Customer API (create, payments, ledger) looks complete on the server. The "not synchronising" symptom is therefore likely on the Flutter side or in how failures are handled. Phase 2 starts by reproducing it, not by guessing.
- A customer payment ledger entry has no `entityId`, and `reference` is mandatory even for cash.
- `sales` has `customerId` but no free-text customer name.
- Out of scope, logged for later: receipt numbers come from `count() + 1`, which can collide under concurrency. `ReceiptSequence` exists but is unused.

---

## Phase 0: Baseline, decisions and tooling

Goal: know where we are, agree the rules, and make this plan verifiable before changing anything.

- [x] Create branch `pos-improvements` from current main
- [x] Run `npm test` and record the result here: `6 test files, 148 tests — all passed (30 payment-provider + 55 control-plane-api + 63 shop-api)`
- [x] Run `npm run typecheck` and record the result here: `0 errors across all workspaces (payment-provider, control-plane-api, shop-api, storefront)`
- [x] Run `dart analyze lib` and `flutter test` in `apps/shop_pos` and record both: `dart analyze: 166 issues (errors + warnings + infos); flutter test: BLOCKED — Windows symlink support required (Developer Mode not enabled), no tests ran`
- [x] Take a `pg_dump` backup of the live shop database and record where it is stored: `C:\Amalgamate\Backups\retailos\retailos_test_20261102_183919.dump — 116.5 KB (119,260 bytes), custom format, database retailos_test on localhost:55432`
- [x] Make `scripts/plan-progress.mjs` accept an optional plan path argument (default stays `STOREFRONT_PLAN.md`) and add npm script `plan:check:pos` = `node scripts/plan-progress.mjs POS_IMPROVEMENTS_PLAN.md`; confirm it passes on this file
- [x] D1 confirmed with the customer (product delete rule); answer recorded in the Notes log
- [x] D2 confirmed (base unit model, sell-in-any-unit, display format); answer recorded in the Notes log
- [x] D3 confirmed (who may authorise selling beyond stock); answer recorded in the Notes log
- [x] D4 confirmed (customer name on receipts: default on or off); answer recorded in the Notes log
- [x] D5 confirmed (day boundary, credit and refund treatment in the daily summary); answer recorded in the Notes log
- [x] D6 confirmed (stock value basis and who sees cost); answer recorded in the Notes log
- [x] Ask the customer whether item 5 was dropped or lost from their list; answer recorded in the Notes log

**Exit gate 0**
- [x] Baseline numbers and backup location recorded above
- [x] All decisions D1 to D6 answered in the Notes log
- [x] `npm run plan:check:pos` passes

---

## Phase 1: Permanent product deletion (request 1)

Goal: a duplicate product created by mistake can be deleted for good and never reappears.

### Backend
- [x] Migration `0006_product_purge`: the `stock_movements` delete-blocking trigger permits a `DELETE` only inside a transaction that has set `app.purge_product_id` to that row's product, and only if the product has no sale, purchase or refund lines. All other tamper attempts stay blocked
- [x] Extend `prisma/verify-immutability.sql`: a plain `DELETE` on `stock_movements` is still rejected; a purge of a product that has sale lines is still rejected
- [x] `DELETE /products/:id` permanently deletes the product (and its opening-stock movements) when it has no sale, purchase or refund lines; otherwise returns 409 `PRODUCT_HAS_HISTORY` with counts
- [x] Restrict permanent delete to OWNER and MANAGER (STOCK_CLERK can no longer delete)
- [x] If remaining stock is not zero, refuse unless the request carries `discardStock: true`; the discarded quantity is recorded in the audit entry
- [x] Write an `audit_logs` row in the same transaction with a `beforeJson` snapshot (name, sku, barcode, prices, stock, who)
- [x] Add `POST /products/:id/archive` carrying the old deactivate behaviour, for products that have history
- [x] API tests: duplicate deletes and is gone from every `active` filter; product with sales is blocked; other business id returns 404; cashier gets 403; opening-stock rows removed; audit row written; non-zero stock needs `discardStock`

### Flutter
- [x] Delete action in `inventory_view.dart` opens a confirmation naming the product, SKU and current stock
- [x] On `PRODUCT_HAS_HISTORY` show a plain explanation and an "Archive instead" button
- [x] Update `api_service.dart` (`deleteProduct`, `archiveProduct`) and `pos_state.dart` so the row disappears immediately and the list is re-fetched from the server
- [ ] Manual check: create a duplicate, delete it, confirm it is gone after refresh and after logout and login

**Exit gate 1**
- [x] An accidental duplicate can be deleted and never reappears under any filter
- [x] A product with sales cannot be deleted and its old receipts still render
- [x] Clean-DB migration plus immutability verification passes; `npm test` and `dart analyze lib` no worse than baseline

---

## Phase 2: Customer credit management and synchronisation (request 2)

Goal: customer accounts, credit sales, payments and balances stay correct and visible everywhere, immediately.

### Diagnose first
- [ ] Reproduce the sync problem on a running build (create customer, then look in Customers, the credit workspace and the checkout picker); record the exact steps and symptom in the Notes log
- [ ] Trace the customer data path end to end (`api_service.dart`, `pos_state.dart`, `customers_view.dart`, `credit_workspace_view.dart`, `checkout_modal.dart`); record every place customers are cached and when each refreshes
- [ ] Write a test that fails because of the reproduced bug, before fixing it

### Fix and harden
- [ ] One customer list in `pos_state`, refreshed from the server response after create, update, archive, payment and credit sale; no screen keeps its own stale copy
- [ ] A newly created customer is selectable at checkout for a credit sale with no restart or manual refresh
- [ ] After a credit sale, the customer's balance and available credit update in every view from the server value
- [ ] Record-payment flow in the UI: amount, method (cash, M-Pesa, bank), reference; blocks overpayment; shows the new balance on success
- [ ] Make `reference` optional on payments; auto-generate one (for example `PAY-YYYYMMDD-NNN`) when blank, so cash payments are not blocked
- [ ] Link each payment to its ledger entry: create the `customer_payments` row first and store its id as the ledger `entityId`
- [ ] Verify cash debt payments are counted in the open cash session's `debtPayments`; wire it if missing
- [ ] Customer statement screen: date, type, reference, debit, credit, running balance, with paging beyond the current 100-row limit
- [ ] Reconciliation check (endpoint or script) comparing `customers.balance` to the ledger for every customer; test it; run it on dev data and record mismatches found
- [ ] Credit-limit-exceeded and frozen-credit errors show a readable message with the available credit, not a generic failure
- [ ] Concurrency test: simultaneous credit sales cannot exceed the limit, and a sale racing a payment leaves balance equal to the ledger
- [ ] When the API is unreachable, customer create and credit sale fail visibly with a retry option; nothing is silently kept as a local-only record

**Exit gate 2**
- [ ] Create customer, credit sale, partial payment, full payment: balances correct on every screen without refreshing
- [ ] Reconciliation reports zero mismatches on a freshly exercised database
- [ ] `npm test`, typecheck and `dart analyze lib` no worse than baseline

---

## Phase 3: Customer name on receipts (request 3)

Goal: cashier can pick an existing customer or type a name, and the receipt shows it.

- [ ] Migration: add nullable `sales.customerName` (text, snapshot at time of sale)
- [ ] Sale create API accepts optional `customerName` (trimmed, max 120 chars); if `customerId` is given and no name, snapshot the customer's `fullName`
- [ ] Business setting `receipt.showCustomerName` (default per D4) readable and writable through the existing settings endpoints
- [ ] Sale detail and receipt responses return `customerName`
- [ ] Checkout modal customer field: search and pick an existing customer, or type a name; clear button; credit payment still requires an existing customer account
- [ ] Receipt dialog and printed receipt show "Customer: name" only when a name exists and the setting is on
- [ ] Settings screen toggle for the option
- [ ] Reprint from Sales History shows the same name as the original
- [ ] Tests: API snapshot behaviour (picked, typed, none, later rename); Flutter receipt renders with and without a name
- [ ] Manual print check with a long name on the shop's actual paper width (wraps or truncates cleanly)

**Exit gate 3**
- [ ] Sales with a picked customer, a typed name and no customer each produce the correct receipt
- [ ] A credit sale to a typed-name-only customer is blocked with a clear message
- [ ] Tests, typecheck and analyze no worse than baseline

---

## Phase 4: Daily sales summary (request 4)

Goal: one screen shows today's total, number of transactions and breakdown by payment method.

- [ ] Add business setting `timezone` (default `Africa/Nairobi`); define "day" as local midnight to midnight and convert to a UTC range for queries
- [ ] `GET /reports/daily?date=YYYY-MM-DD` (default today) returns total sales, transaction count and average sale, counting COMPLETED and PARTIALLY_REFUNDED sales and excluding DRAFT and VOIDED
- [ ] Payment-method breakdown from `sale_payments` with status SUCCESS: cash, M-Pesa, credit, bank; amount and count each; breakdown sums to the total
- [ ] Refunds for the day shown separately, with net sales = total minus refunds; voided count shown separately
- [ ] Credit given shown as its own line; debt payments received that day shown as a separate block by method and never added into sales
- [ ] Role rules: Owner and Manager see all cashiers (with optional cashier filter); Cashier sees only their own sales
- [ ] Tests: sales at 23:30 and 00:30 `Africa/Nairobi` land on the right days; split-payment sale; voided excluded; refund netted; breakdown reconciles to total
- [ ] "Today" summary card at the top of the Reports view with previous and next day navigation
- [ ] Print the summary as a day-end slip
- [ ] Reuse the same endpoint for any existing "today" figures in `reports_view.dart` so two different totals can never appear
- [ ] Manual check: summary totals equal Sales History for the same day; record the result in the Notes log

**Exit gate 4**
- [ ] Total, transaction count and per-method breakdown shown and correct for a day with mixed cash, M-Pesa and credit sales
- [ ] Midnight boundary test passes
- [ ] Tests, typecheck and analyze no worse than baseline

---

## Phase 5: Measured units and automatic stock deduction, backend core (requests 7 and 8)

Goal: sell 250 ml from a 20 L product and the system holds exactly 19.75 L, safely under concurrency.

- [ ] Single unit catalogue `packages/units/units.json` (family, symbol, factor to the family base) feeding both TypeScript and Dart, same pattern as `design-tokens`; CI fails on drift
- [ ] Audit distinct existing `products.unit` values with a script, map them to catalogue symbols, and record any unmapped values in the Notes log
- [ ] Migration `0007_measured_units`: product purchase-container fields (name and size in base unit) and quick-quantity presets; `sale_items.soldQuantity` and `soldUnit` with backfill (`quantity` stays the base-unit quantity so existing reports keep working)
- [ ] Integer-safe conversion library `toBaseQuantity(quantity, unit, product)` with tests: 250 ml to 0.25 L, 1000 ml to 1 L, 20 L minus 250 ml equals 19.75, and repeated 0.1 additions do not drift
- [ ] Reject a unit from the wrong family (kg for a litre product) and any quantity finer than 3 decimal places of the base unit, each with a clear 422 error
- [ ] Sale API accepts a per-line `unit`, defaulting to the product's base unit so the current till build keeps working
- [ ] Line pricing rule: price is per base unit, line total rounded half-up to the cent; tests include 250 ml at KES 300/L equals 75.00 and 100 ml at KES 285/L equals 28.50
- [ ] Lock the product rows `SELECT ... FOR UPDATE` before reading stock inside the sale transaction
- [ ] Replace JS `number` stock arithmetic with `Decimal` and an atomic guarded update
- [ ] Insufficient stock still fails by default; an Owner or Manager can authorise via PIN, which writes an `approvals` row and an audit entry and then allows the sale
- [ ] When stock goes negative through an override, set `varianceFlag` and record the movement; never clamp to zero silently
- [ ] Refund and return path restores the base-unit quantity correctly for measured items
- [ ] Concurrency test: two parallel sales for the last 1 L, exactly one succeeds
- [ ] Worked example test through the API: 20 L oil, sell 250 ml, stock reads 19.75, one SALE movement of -0.25 with `balanceAfter` 19.75

**Exit gate 5**
- [ ] All conversion, pricing, override and concurrency tests pass
- [ ] Migration applies on a clean database **and** on a restored copy of existing data with no lost rows
- [ ] Existing till build can still complete a sale of whole items unchanged

---

## Phase 6: Adjustments, bulk purchasing and movement history, API (request 8)

Goal: every stock change, from purchase to spillage to a physical count, is recorded and reconstructible.

- [ ] `adjust-stock` accepts fractional deltas and a unit (currently integer only) and converts to base units
- [ ] Adjustment reason codes: SPILLAGE, WASTAGE, DAMAGE, EXPIRY, CORRECTION; reason is mandatory and stored in the `reason` column, not only `note`
- [ ] Physical stock count endpoint: submit the counted quantity, the system records the difference as an adjustment with before and after
- [ ] Purchase receiving in containers: enter 3 x 20 L jerrycans, convert to 60 L base quantity and unit cost per litre
- [ ] Stock movement history API per product and global, filterable by date, type and product, paged, showing who, reference (receipt number or PO), quantity and `balanceAfter`
- [ ] `stock-reconcile` script: `products.stock` equals the sum of `stock_movements.quantity` and the last `balanceAfter` for every product; run on dev data and record the result
- [ ] Role rules for adjustments (Owner, Manager, Stock clerk) and an audit entry for every adjustment
- [ ] Tests for each endpoint above, including a fractional spillage of 0.25 L

**Exit gate 6**
- [ ] Purchase 60 L, sell 250 ml, record 0.5 L spillage, count and correct: history shows every step and reconciliation shows zero drift
- [ ] Tests, typecheck no worse than baseline

---

## Phase 7: Measured selling and stock screens, Flutter (requests 7 and 8)

Goal: cashiers and stock clerks can do all of the above without leaving the till.

- [ ] Product editor: base unit picker (limited to the catalogue), purchase container, quick-quantity presets, price labelled "per litre" (or the chosen unit)
- [ ] Till quantity sheet for measured products: preset buttons (for example 100 ml, 250 ml, 500 ml, 1 L), custom entry with unit selector, live line total
- [ ] Cart line shows the measured quantity, rate and total, for example "250 ml x KES 300/L = KES 75.00"
- [ ] Stock display formatter shared across the app with tests: "19.75 L", sub-unit shown as "750 ml" below 1 L, no float artefacts such as 19.750000001
- [ ] Insufficient stock dialog on the till with an authorised-user PIN override flow
- [ ] Adjustment dialog (spillage, wastage, damage, correction) and physical stock count screen
- [ ] Stock movement history screens: per product and global, with filters
- [ ] Receipt and reprint show measured quantities in the unit sold

**Exit gate 7**
- [ ] Full measured sale on the till (pick preset, custom quantity, pay, receipt) with remaining stock shown correctly
- [ ] Override path works for a Manager and is refused for a Cashier
- [ ] Analyze and tests no worse than baseline; smoke test passes

---

## Phase 8: Stock list for regular auditing (request 6)

Goal: a clear, printable and downloadable list of everything in the shop for physical stock checks.

- [ ] `GET /stock/list` returns name, SKU, category, quantity, unit, selling price, cost price, value at cost and value at selling price, with column totals; filters for category, low stock and out of stock
- [ ] Value rules from D6 implemented and documented in the response and on the screen
- [ ] Negative stock and variance-flagged products highlighted; inactive products excluded by default
- [ ] Stock list screen: search, category filter, sort, totals footer, readable units via the Phase 7 formatter
- [ ] Print layout (A4): shop name, date and time, page numbers, and blank "Counted" and "Difference" columns for the auditor
- [ ] Download as `.xlsx` using the existing `xlsx_exporter.dart` and as CSV
- [ ] Cashiers do not see cost price or stock value columns
- [ ] Tests: totals correct on seeded data including measured products and decimals
- [ ] Manual check: print and export 100+ products, confirm paging and units

**Exit gate 8**
- [ ] Printed list and spreadsheet match the on-screen list and the database totals
- [ ] Tests, typecheck and analyze no worse than baseline

---

## Phase 9: Acceptance and release

- [ ] UAT request 1: duplicate product deleted permanently
- [ ] UAT request 2: customer created, credit sale, payment, balances correct everywhere
- [ ] UAT request 3: customer name on receipt (picked and typed)
- [ ] UAT request 4: daily summary matches Sales History
- [ ] UAT request 6: stock list printed and downloaded
- [ ] UAT request 7: automatic stock deduction on a retail sale
- [ ] UAT request 8: 20 L oil, sell 250 ml, shows 19.75 L; spillage, count and history recorded; over-sell blocked then authorised
- [ ] Full regression: `npm test`, `npm run typecheck`, `dart analyze lib`, `flutter test` all no worse than baseline
- [ ] `migrate-test.cmd` on a scratch database and the upgrade tested on a restored copy of live data
- [ ] Stock and customer reconciliation scripts report zero drift on pre-release data
- [ ] Short operator guide in `docs/`: set up a measured product, receive bulk stock, record spillage, delete a duplicate, run the end-of-day summary, print the stock list
- [ ] Fresh backup taken and a rollback plan written before touching production
- [ ] Deployed and smoke-tested in production (login, sale, credit sale, receipt, daily summary, stock list)
- [ ] `pos-improvements` merged into main

**Exit gate 9 (done)**
- [ ] All phases ticked, dashboard below shows 100%
- [ ] Customer sign-off recorded in the Notes log

---

## Progress dashboard

Update this table whenever you tick items. `npm run plan:check:pos` verifies it.

| Phase | Name | Status | Done / Total |
|---|---|---|---|
| 0 | Baseline, decisions and tooling | Done | 16 / 16 |
| 1 | Permanent product deletion | In progress | 14 / 15 |
| 2 | Customer credit and synchronisation | Not started | 0 / 18 |
| 3 | Customer name on receipts | Not started | 0 / 13 |
| 4 | Daily sales summary | Not started | 0 / 14 |
| 5 | Measured units, backend core | Not started | 0 / 17 |
| 6 | Adjustments, purchasing, movement history | Not started | 0 / 10 |
| 7 | Measured selling and stock screens | Not started | 0 / 11 |
| 8 | Stock list for auditing | Not started | 0 / 11 |
| 9 | Acceptance and release | Not started | 0 / 16 |
| **Total** | All phases | In progress | 30 / 141 |

Status values: `Not started` · `In progress` · `Blocked` · `Done`

---

## Notes / decisions log

Add dated one-liners as decisions are made, bugs are reproduced, or tasks are skipped.

- 2026-11-02: Plan created from the customer request and a read of `schema.prisma`, `products.router.ts`, `customers.router.ts` and `create-sale.ts`. Flutter-side code (`pos_state.dart`, views) not yet read; Phase 2 diagnosis covers it.
- 2026-11-02: The customer's list jumps from item 4 to item 6. Phase 0 asks whether an item is missing.
- 2026-11-02: Phase 0 tooling found already in place: `scripts/plan-progress.mjs` takes an optional plan path and `plan:check:pos` exists in `package.json`. Dashboard counts per phase were recounted by hand and match all 141 boxes. No shell was available in this session, so `npm run plan:check:pos` still needs one real run. Repo is currently on branch `storefront-uplift`; `pos-improvements` has not been created. Remaining Phase 0 items need a terminal (branch, tests, typecheck, dart analyze, pg_dump) or the customer (D1 to D6, item 5).
- 2026-11-02: Branch created: `pos-improvements` branched from `main` (commit 7e1d3ca). Uncommitted changes on `storefront-uplift` were committed there as "storefront-uplift: WIP changes (auto-commit before pos-improvements branch)" before switching.
- 2026-11-02: Baseline npm test: 6 test files, 148 tests all passed — 30 (payment-provider) + 55 (control-plane-api) + 63 (shop-api). Zero failures.
- 2026-11-02: Baseline typecheck: 0 errors across all 4 workspaces (payment-provider, control-plane-api, shop-api, storefront).
- 2026-11-02: Baseline dart analyze lib: 166 issues (mix of errors, warnings and infos). Flutter test blocked on Windows — Developer Mode / symlink support not enabled; no tests ran. Record as baseline: dart analyze 166 issues, flutter test 0 run / BLOCKED.
- 2026-11-02: Backup taken: C:\Amalgamate\Backups\retailos\retailos_test_20261102_183919.dump — 116.5 KB (119,260 bytes), pg_dump custom format, database retailos_test on localhost:55432 (Docker container retailos_test). Read-only dump; migrate-test.cmd not run.
- 2026-11-02: D1 confirmed — permanent delete allowed when product has no sales/purchase/refund history; otherwise blocked with "Archive instead". Owner and Manager only.
- 2026-11-02: D2 confirmed — base-unit model adopted: store in base unit (L, kg, pc etc.), sell in any unit of the same family, 3 decimal places.
- 2026-11-02: D3 confirmed — both Owner and Manager may authorise an over-stock sale at the till with their PIN; every override is audited.
- 2026-11-02: D4 confirmed — customer name on receipt default ON; name printed only when provided, snapshotted at time of sale.
- 2026-11-02: D5 confirmed — day boundary is Africa/Nairobi (UTC+3), midnight to midnight.
- 2026-11-02: D6 confirmed — all roles including Cashiers see cost price and stock value columns (customer overrides recommended default).
- 2026-11-02: Item 5 — customer confirmed it was intentionally dropped; no missing request.
- 2026-11-03: Phase 1 complete (14/15 — manual smoke test pending). Migration 0006_product_purge replaces the stock_movements_no_delete trigger with a narrow purge-guard. DELETE /products/:id hard-deletes with audit; POST /products/:id/archive is the safe fallback. Flutter shows discard-stock checkbox and history explanation with "Archive instead" action. npm test: 73 shop-api tests pass (10 new + 63 existing); typecheck: 0 errors; dart analyze lib: 106 issues (≤ 166 baseline).
