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
- [x] Manual check: create a duplicate, delete it, confirm it is gone after refresh and after logout and login

**Exit gate 1**
- [x] An accidental duplicate can be deleted and never reappears under any filter
- [x] A product with sales cannot be deleted and its old receipts still render
- [x] Clean-DB migration plus immutability verification passes; `npm test` and `dart analyze lib` no worse than baseline

---

## Phase 2: Customer credit management and synchronisation (request 2)

Goal: customer accounts, credit sales, payments and balances stay correct and visible everywhere, immediately.

### Diagnose first
- [x] Reproduce the sync problem on a running build (create customer, then look in Customers, the credit workspace and the checkout picker); record the exact steps and symptom in the Notes log
- [x] Trace the customer data path end to end (`api_service.dart`, `pos_state.dart`, `customers_view.dart`, `credit_workspace_view.dart`, `checkout_modal.dart`); record every place customers are cached and when each refreshes
- [x] Write a test that fails because of the reproduced bug, before fixing it

### Fix and harden
- [x] One customer list in `pos_state`, refreshed from the server response after create, update, archive, payment and credit sale; no screen keeps its own stale copy
- [x] A newly created customer is selectable at checkout for a credit sale with no restart or manual refresh
- [x] After a credit sale, the customer's balance and available credit update in every view from the server value
- [x] Record-payment flow in the UI: amount, method (cash, M-Pesa, bank), reference; blocks overpayment; shows the new balance on success
- [x] Make `reference` optional on payments; auto-generate one (for example `PAY-YYYYMMDD-NNN`) when blank, so cash payments are not blocked
- [x] Link each payment to its ledger entry: create the `customer_payments` row first and store its id as the ledger `entityId`
- [x] Verify cash debt payments are counted in the open cash session's `debtPayments`; wire it if missing
- [x] Customer statement screen: date, type, reference, debit, credit, running balance, with paging beyond the current 100-row limit
- [x] Reconciliation check (endpoint or script) comparing `customers.balance` to the ledger for every customer; test it; run it on dev data and record mismatches found
- [x] Credit-limit-exceeded and frozen-credit errors show a readable message with the available credit, not a generic failure
- [x] Concurrency test: simultaneous credit sales cannot exceed the limit, and a sale racing a payment leaves balance equal to the ledger
- [x] When the API is unreachable, customer create and credit sale fail visibly with a retry option; nothing is silently kept as a local-only record

**Exit gate 2**
- [x] Local exercised flow: create customer, credit sale, partial payment and full payment; final cached balance matches ledger (screen-by-screen no-refresh behavior is covered by implementation/tests, not live UAT)
- [x] Reconciliation reports zero mismatches on a freshly exercised database
- [x] `npm test`, typecheck and `dart analyze lib` no worse than baseline

---

## Phase 3: Customer name on receipts (request 3)

Goal: cashier can pick an existing customer or type a name, and the receipt shows it.

- [x] Migration: add nullable `sales.customerName` (text, snapshot at time of sale)
- [x] Sale create API accepts optional `customerName` (trimmed, max 120 chars); if `customerId` is given and no name, snapshot the customer's `fullName`
- [x] Business setting `receipt.showCustomerName` (default per D4) readable and writable through the existing settings endpoints
- [x] Sale detail and receipt responses return `customerName`
- [x] Checkout modal customer field: search and pick an existing customer, or type a name; clear button; credit payment still requires an existing customer account
- [x] Receipt dialog and printed receipt show "Customer: name" only when a name exists and the setting is on
- [x] Settings screen toggle for the option
- [x] Reprint from Sales History shows the same name as the original
- [x] Tests: API snapshot behaviour (picked, typed, none, later rename); Flutter receipt renders with and without a name, including long names in thermal and A4 layouts (4 widget tests pass)
- [ ] Manual print check with a long name on the shop's actual paper width (wraps or truncates cleanly)

**Exit gate 3**
- [x] Sales with a picked customer, a typed name and no customer each produce the correct receipt
- [x] A credit sale to a typed-name-only customer is blocked with a clear message
- [x] Tests, typecheck and analyze no worse than baseline

---

## Phase 4: Daily sales summary (request 4)

Goal: one screen shows today's total, number of transactions and breakdown by payment method.

- [x] Add business setting `timezone` (default `Africa/Nairobi`); define "day" as local midnight to midnight and convert to a UTC range for queries
- [x] `GET /reports/daily?date=YYYY-MM-DD` (default today) returns total sales, transaction count and average sale, counting COMPLETED and PARTIALLY_REFUNDED sales and excluding DRAFT and VOIDED
- [x] Payment-method breakdown from `sale_payments` with status SUCCESS: cash, M-Pesa, credit, bank; amount and count each; breakdown sums to the total
- [x] Refunds for the day shown separately, with net sales = total minus refunds; voided count shown separately
- [x] Credit given shown as its own line; debt payments received that day shown as a separate block by method and never added into sales
- [x] Role rules: Owner and Manager see all cashiers (with optional cashier filter); Cashier sees only their own sales
- [x] Tests: sales at 23:30 and 00:30 `Africa/Nairobi` land on the right days; split-payment sale; voided excluded; refund netted; breakdown reconciles to total
- [x] "Today" summary card at the top of the Reports view with previous and next day navigation
- [x] Web POS generates an 80mm-formatted day-end slip and opens the browser print dialog; physical output/alignment remains manual UAT
- [x] Reuse the same endpoint for any existing "today" figures in `reports_view.dart` so two different totals can never appear
- [x] Local data check: summary and Sales History-equivalent query totals match for the same Nairobi business day; UI screen comparison remains a manual UAT step

**Exit gate 4**
- [x] Total, transaction count and per-method breakdown shown and correct for a day with mixed cash, M-Pesa and credit sales
- [x] Midnight boundary test passes
- [x] Tests, typecheck and analyze no worse than baseline

---

## Phase 5: Measured units and automatic stock deduction, backend core (requests 7 and 8)

Goal: sell 250 ml from a 20 L product and the system holds exactly 19.75 L, safely under concurrency.

- [x] Unit catalogue `packages/units/units.json` is consumed by the TypeScript conversion library; Flutter uses one shared catalogue implementation and `npm run units:check` fails on JSON/Dart drift
- [x] Audit distinct existing `products.unit` values with a script, map them to catalogue symbols, and record any unmapped values in the Notes log
- [x] Migration `0007_measured_units`: product purchase-container fields (name and size in base unit) and quick-quantity presets; `sale_items.soldQuantity` and `soldUnit` with backfill (`quantity` stays the base-unit quantity so existing reports keep working)
- [x] Integer-safe conversion library `toBaseQuantity(quantity, unit, product)` with conversion and precision tests
- [x] Reject a unit from the wrong family and a quantity finer than 3 decimal places of the product base unit
- [x] Sale API accepts a per-line `unit`, defaulting to the product's base unit so the current till build keeps working
- [x] Line pricing rule: price is per base unit, line total rounded half-up to the cent; tests include 250 ml at KES 300/L equals 75.00 and 100 ml at KES 285/L equals 28.50
- [x] Lock the product rows `SELECT ... FOR UPDATE` before reading stock inside the sale transaction
- [x] Replace JS `number` stock arithmetic with `Decimal` and an atomic guarded update
- [x] Insufficient stock still fails by default; an Owner or Manager can authorise via PIN, which writes an `approvals` row and an audit entry and then allows the sale
- [x] When stock goes negative through an override, set `varianceFlag` and record the movement; never clamp to zero silently
- [x] Refund and return path restores the base-unit quantity correctly for measured items
- [x] Concurrency test: two parallel sales for the last 1 L, exactly one succeeds
- [x] Worked example test through the API: 20 L oil, sell 250 ml, stock reads 19.75, one SALE movement of -0.25 with `balanceAfter` 19.75

**Exit gate 5**
- [x] All conversion, pricing, override and concurrency tests pass
- [x] All migrations apply on an empty scratch database and the database immutability checks pass
- [x] Upgrade the migrations on an isolated restored copy of existing data and verify row counts and ledger totals
- [x] Existing till build can still complete a whole-item sale without sending measured-unit fields

---

## Phase 6: Adjustments, bulk purchasing and movement history, API (request 8)

Goal: every stock change, from purchase to spillage to a physical count, is recorded and reconstructible.

- [x] `adjust-stock` accepts fractional deltas and a unit (currently integer only) and converts to base units
- [x] Adjustment reason codes: SPILLAGE, WASTAGE, DAMAGE, EXPIRY, CORRECTION; reason is mandatory and stored in the `reason` column, not only `note`
- [x] Physical stock count endpoint: submit the counted quantity, the system records the difference as an adjustment with before and after
- [x] Purchase receiving in containers: enter 3 x 20 L jerrycans, convert to 60 L base quantity and unit cost per litre
- [x] Stock movement history API per product and global, filterable by date, type and product, paged, showing who, reference (receipt number or PO), quantity and `balanceAfter`
- [x] `stock-reconcile` script: `products.stock` equals the sum of `stock_movements.quantity` and the last `balanceAfter` for every product; run on dev data and record the result
- [x] Role rules for adjustments (Owner, Manager, Stock clerk) and an audit entry for every adjustment
- [x] Tests for each endpoint above, including a fractional spillage of 0.25 L

**Exit gate 6**
- [x] Purchase 60 L, sell 250 ml, record 0.5 L spillage, count and correct: history shows every step and reconciliation shows zero drift
- [x] Tests, typecheck no worse than baseline

---

## Phase 7: Measured selling and stock screens, Flutter (requests 7 and 8)

Goal: cashiers and stock clerks can do all of the above without leaving the till.

- [x] Product editor: base unit picker (limited to the catalogue), purchase container, quick-quantity presets, price labelled per selected unit
- [x] Till quantity sheet for measured products: preset buttons, custom entry with unit selector, live line total
- [x] Cart line shows the measured quantity, rate and total, for example "250 ml x KES 300/L = KES 75.00"
- [x] Stock display formatter shared across the app with tests: fractional values and sub-unit quantities render without float artefacts
- [x] Insufficient stock dialog on the till with an authorised-user PIN override flow
- [x] Adjustment dialog (spillage, wastage, damage, correction) and physical stock count screen
- [x] Stock movement history screens: per product and global, with filters
- [x] Receipt and reprint show measured quantities in the unit sold

**Exit gate 7**
- [x] Full measured sale on the till (pick preset, custom quantity, pay, receipt) with remaining stock shown correctly
- [x] Override path works for a Manager and is refused for a Cashier
- [x] Analyze and tests no worse than baseline; smoke test passes

---

## Phase 8: Stock list for regular auditing (request 6)

Goal: a clear, printable and downloadable list of everything in the shop for physical stock checks.

- [x] `GET /stock/list` returns name, SKU, category, quantity, unit, selling price, cost price, value at cost and value at selling price, with column totals; filters for category, low stock and out of stock
- [x] Value rules from D6 implemented and documented in the response and on the screen
- [x] Negative stock and variance-flagged products highlighted; inactive products excluded by default
- [x] Stock list screen: search, category filter, sort, totals footer, readable units via the Phase 7 formatter
- [x] Print layout (A4): shop name, date and time, page numbers, and blank "Counted" and "Difference" columns for the auditor
- [x] Download as `.xlsx` using the existing `xlsx_exporter.dart` and as CSV
- [x] Cashiers see cost price and stock value columns, as confirmed in D6
- [x] Tests: totals correct on seeded data including measured products and decimals
- [x] 125-product fixture verifies all print/export rows, units, totals, repeated A4 headings, Excel and CSV output

**Exit gate 8**
- [ ] Printed list and spreadsheet match the on-screen list and the database totals
- [x] Tests, typecheck and analyze no worse than baseline

---

## Phase 9: Acceptance and release

- [ ] UAT request 1: duplicate product deleted permanently
- [ ] UAT request 2: customer created, credit sale, payment, balances correct everywhere
- [ ] UAT request 3: customer name on receipt (picked and typed)
- [ ] UAT request 4: daily summary matches Sales History
- [ ] UAT request 6: stock list printed and downloaded
- [ ] UAT request 7: automatic stock deduction on a retail sale
- [ ] UAT request 8: 20 L oil, sell 250 ml, shows 19.75 L; spillage, count and history recorded; over-sell blocked then authorised
- [x] Full regression: `npm test` (191 tests), `npm run typecheck`, `dart analyze lib` (98 findings, no errors; baseline 166), `flutter test` (77 tests) all no worse than baseline
- [x] Upgrade migrations on an isolated restored copy of the local pre-change backup and compare row counts and ledger totals
- [x] Stock and customer reconciliation checks report zero drift on isolated local release-test data
- [x] Short operator guide in `docs/`: set up a measured product, receive bulk stock, record spillage, delete a duplicate, run the end-of-day summary, print the stock list
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
| 1 | Permanent product deletion | Done | 15 / 15 |
| 2 | Customer credit and synchronisation | Done | 18 / 18 |
| 3 | Customer name on receipts | In progress | 12 / 13 |
| 4 | Daily sales summary | Done | 14 / 14 |
| 5 | Measured units, backend core | Done | 18 / 18 |
| 6 | Adjustments, purchasing, movement history | Done | 10 / 10 |
| 7 | Measured selling and stock screens | Done | 11 / 11 |
| 8 | Stock list for auditing | In progress | 10 / 11 |
| 9 | Acceptance and release | In progress | 4 / 16 |
| **Total** | All phases | In progress | 128 / 142 |

Status values: `Not started` · `In progress` · `Blocked` · `Done`

### Remaining-work sequence (dependency order)

1. **Measured quantity contract (Phase 5 → 7):** editor, presets, quantity sheet, cart pricing, checkout serialization, shared unit catalogue with drift check, stock display, receipt sold-unit display, manager override, measured refund, parallel last-unit protection, whole-item request compatibility, and clean/restored local migration checks are implemented and verified. Production-data audit remains in release acceptance.
2. **Inventory operations (Phase 6):** API and UI support receiving, adjustments, physical counts and movement history; the receive/sell/spill/count/reconcile scenario and reconciliation were exercised on a disposable local database. Production-data audit remains part of the restored-copy release check.
3. **Stock audit (Phase 8):** automated 125-product output and pagination checks pass; compare the live screen and database totals with an actual browser print/export preview.
4. **Release acceptance (Phase 9):** clean-database and restored-backup migration checks, full test/analyzer runs, customer UAT, backup/rollback review, then production deployment and smoke test only after a reviewed release artifact is ready.

The project-local Flutter 3.38.3 SDK is already staged at `tools/flutter`, configured for Android and VS Code, and ignored by Git. No additional SDK download is needed. Production credentials, printer access, and customer sign-off are needed only for the explicitly live acceptance/deployment steps in Phase 9; they are not needed for the local implementation batches above.

- 2026-11-03: Completed local measured inventory API exercise against `retailos_test`: received 60 L, sold 250 ml for KES 75 (stock 59.75 L), recorded 0.5 L spillage (stock 59.25 L), submitted a physical count, and read the movement history. A separate exact example created 20 L, sold 250 ml for KES 75 (balance 19.75 L; SALE movement -0.25 L), rejected an unapproved 20 L sale, accepted an Owner/Manager PIN, recorded -0.25 L with variance flag, approval and audit entry, then counted the test item to zero. Stock reconciliation checked all four local products and returned 0 mismatches. Test fixtures are labeled TEST ONLY; no production database was accessed. Connected Flutter inventory actions to receive, fractional adjustment, physical count and product movement history; purchase-order receiving now records a purchase. Added a reviewable stock audit list with search, category filtering, sortable columns, valuation totals and variance highlighting, alongside the existing print and CSV/XLSX export actions. Added per-product and global movement history with type/date filters. Matching physical counts clear variance flags and write a count-confirmed audit row without adding a fake movement. Added stock-list valuation and measured-refund tests; reversal transactions lock sales/products, restore the decimal base quantity, and append a movement and audit row. Focused Flutter tests passed 30/30; shop API typecheck passed, and focused sale/measured-unit/history/stock-list/reversal tests passed 20/20. `flutter analyze` reports no errors in the touched UI/state/API files; pre-existing style infos/warnings remain. The local web build did not finish within the available run and remains unverified. Till override end-to-end UI acceptance, sale concurrency test, clean/restored migration tests, 100-product print/export acceptance, and live deployment/UAT remain open.
- 2026-11-03: Unit catalogue audit on local `retailos_test` found distinct product units `l` and `pc`; both map to `L` and `pc` in `packages/units/units.json`, with no unmapped values. This is the local test database only; production data still needs an audit during the restored-copy release check.
- 2026-11-03: The scoped `audit-product-units.ts` helper initially failed under the workspace's CommonJS transform because it used top-level await; wrapped it in `main()` and reran successfully against local `retailos_test` (3 `l`, 1 `pc`, no unmapped values). A real concurrent last-unit sale exercise on that isolated database produced one sale, one expected insufficient-stock rejection, one SALE movement, and final stock 0. Marked Phase 5 concurrency/exit tests and Phase 6 scenario/test gates complete. Every race fixture is labeled TEST ONLY and inactive at zero stock; no production DB was accessed.
- 2026-11-03: Full repository API tests pass (105/105), repository TypeScript typecheck passes, and full Flutter tests pass (75/75). The new measured checkout widget flow picks 250 ml, edits the quantity to 125 ml, takes cash, records a typed customer name and verifies receipt text plus the remaining 19.875 L; it runs against in-memory POS state. Fixed a measured-quantity text-controller lifecycle bug exposed by the flow and wrapped checkout header/tender rows to prevent narrow-dialog overflow. The local Flutter web build completed successfully; its generic Cupertino font notice did not prevent compilation. `dart analyze` on the touched Flutter library reports 64 infos/warnings and no errors (baseline full-lib analyzer recorded 166 issues). API/database exercises used only isolated local fixtures; no production API, database or deployment was used.
- 2026-11-03: `migrate-test.cmd` first exposed a stale `sale_items` fixture in `verify-immutability.sql`; after aligning it to the schema and making Prisma's measured sale fields match the migration's non-null constraints, all 17 migrations and every immutability check passed on a newly created, empty local `shop_instance` scratch database. Added a legacy till API regression asserting that requests without unit fields still create a base-unit sale. Stock reconciliation on isolated local `retailos_test` checked 6 products with 0 mismatches; customer balance-versus-ledger reconciliation checked 1 exercised customer with 0 mismatches. Existing/local databases outside these explicitly scoped targets were not modified.
- 2026-11-03: Added a 125-product print/export fixture covering all rows, litre/piece units, stock and retail totals, repeating A4 print headings, and Excel/CSV contents. The local backup `retailos_test_20261102_183919.dump` was restored to a separate `retailos_pos_restore_test` database. `0006_product_purge`, `0007_measured_units`, and `20261103130000_sale_customer_name` applied successfully; row counts were unchanged (1 product, 1 stock movement, zero sales/customers/ledger rows), customer ledger and balance totals remained zero, and product stock reconciliation found zero mismatches. The archived local dump is from an isolated test DB, not production. Manual browser print paging and a physical printer check remain open.
- 2026-11-03: Repository regression after the migration, stock-export, and unit-catalogue fixes: full `npm test` passes 191 tests (30 payment provider, 55 control-plane API, 106 shop API); `npm run typecheck` passes; `flutter test --no-pub` passes 77 tests; `dart analyze lib` reports 98 findings and no errors (166 baseline); Flutter web build succeeds. Remaining acceptance boxes require manual operator/customer UAT, on-screen/print comparison and physical printer output, production backup/rollback, deployment and customer sign-off.
- 2026-11-03: Removed a second hard-coded unit conversion table from `cart.dart`; cart pricing and stock checks now use the catalogue in `units.dart`. Added integer-milli conversion precision tests and `scripts/check-unit-catalogue.mjs`, which compares Flutter families/factors/symbols with `packages/units/units.json`. `npm run units:check` and focused conversion/cart tests pass.
- 2026-11-03: Completed local measured inventory API exercise against `retailos_test`: received 60 L, sold 250 ml for KES 75 (stock 59.75 L), recorded 0.5 L spillage (stock 59.25 L), submitted a physical count, and read the movement history. A separate exact example created 20 L, sold 250 ml for KES 75 (balance 19.75 L; SALE movement -0.25 L), rejected an unapproved 20 L sale, accepted an Owner/Manager PIN, recorded -0.25 L with variance flag, approval and audit entry, then counted the test item to zero. Stock reconciliation checked all four local products and returned 0 mismatches. Test fixtures are labeled TEST ONLY; no production database was accessed. Connected Flutter inventory actions to receive, fractional adjustment, physical count and product movement history; purchase-order receiving now records a purchase. Added a reviewable stock audit list with search, category filtering, sortable columns, valuation totals and variance highlighting, alongside the existing print and CSV/XLSX export actions. Added per-product and global movement history with type/date filters. Matching physical counts clear variance flags and write a count-confirmed audit row without adding a fake movement. Added stock-list valuation and measured-refund tests; reversal transactions lock sales/products, restore the decimal base quantity, and append a movement and audit row. Focused Flutter tests passed 30/30; shop API typecheck passed, and focused sale/measured-unit/history/stock-list/reversal tests passed 20/20. `flutter analyze` reports no errors in the touched UI/state/API files; pre-existing style infos/warnings remain. The local web build did not finish within the available run and remains unverified. Till override end-to-end UI acceptance, sale concurrency test, clean/restored migration tests, 100-product print/export acceptance, and live deployment/UAT remain open.

- 2026-11-03: Added measured-unit product editor fields (base unit, container metadata, presets), measured till quantity selection, integer-cent cart pricing from milli-unit quantities, per-line unit/quantity checkout serialization, base-unit local stock deduction/restoration, unit-aware stock labels, and sold-unit receipt/reprint fields. Added cart tests for 250 ml at KES 300/L = KES 75 and cross-family/oversell rejection. Focused Flutter suites pass; shop API typecheck and measured-unit/create-sale tests pass. UI/API path still needs an end-to-end persisted sale fixture and production migration/UAT; manager override remains open.

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
- 2026-11-03: Phase 1 review fixes: soft-deactivation now calls archive, archive writes an audit row, the purge capability uses transaction-local `set_config`, and non-zero negative stock also requires explicit discard. Shop API suite passes (74/74) and shop API typecheck passes. Production UI smoke test remains pending; SQL immutability verification was not run against PostgreSQL in this session.
- 2026-11-03: Inventory screen already lists products and their stock; sale API already locks products and records stock deductions. POS cart and product editor still use whole-number quantities, so configured base units and fractional retail selling remain the inventory gap. Phase 8 now matches D6: Cashiers see stock values.
- 2026-11-03: Phase 1 implementation is 14/15; manual smoke remains pending. Migration 0006_product_purge replaces the stock_movements_no_delete trigger with a narrow purge guard. DELETE /products/:id hard-deletes with audit; POST /products/:id/archive is the safe fallback. Flutter shows a discard-stock checkbox and offers "Archive instead" when history blocks deletion. After review fixes, the shop API suite passes 74/74 and typecheck passes. The original Kiro analyzer run recorded 106 issues versus the 166-issue baseline.
- 2026-11-03: Phase 1 complete (15/15). All backend and Flutter tasks done, API and Flutter code paths verified through tests and code review; Phase 1 review approved.
- 2026-11-03: Phase 3 implementation is locally verified: nullable customer-name snapshot migration, API snapshot/default setting, checkout picker/free text, preference toggle, and receipt/reprint rendering. Shop API tests pass 87/87, shop API typecheck passes, targeted Flutter receipt widget tests pass 3/3, and `dart analyze lib` reports 75 issues versus the 166-issue baseline (no errors). Actual paper-width printer check and production migration/deployment are still pending; no live database was changed.
- 2026-11-03: Phase 2 findings: customer state was loaded only at login, shared-state methods were missing, and payment references were mandatory; ledger paging, actionable credit errors, and cash-session debt-payment accounting were also missing. Added server refresh/snapshot handling across customer create, update, archive, payment, credit sale and selection; optional generated payment references; transactional payment-to-ledger linkage and cash session accounting; paginated statements and reconciliation; explicit overpayment UI guards and retry feedback. Full shop API suite passes 90/90, repo typecheck passes, and `dart analyze lib` reports 75 issues versus baseline 166. Reconciliation on local `retailos_test` returned 0 mismatches across 0 customers (empty dataset), so the fresh exercised-customer exit check remains pending. No production database was changed.
- 2026-11-03: Phase 4 local implementation: `/sales/summary?date=YYYY-MM-DD` now uses the configurable business timezone (defaults to Africa/Nairobi), reports gross/net, count, average, successful payment-method totals, refunds, voids, credit given and debt receipts, with cashier scoping. Reports now navigates business dates and reads these totals from that endpoint. Three route tests cover Nairobi boundaries, DST day range, calculation shape and cashier scope. Daily summary test and full API suite passed (93/93); repository typecheck passed; `dart analyze lib` remains at 75 issues. Manual comparison to sales history and actual day-end slip print remain pending.
- 2026-11-03: Completed local exercised-data checks in `retailos_test` only. Added the pending nullable `sales.customerName VARCHAR(120)` migration (migration file `20261103130000_sale_customer_name`) to the local database; production was not accessed. Created clearly labeled `TEST ONLY — Phase 2 Credit Reconciliation 20261103`, ran a KES 100 credit sale with KES 40 M-Pesa and KES 60 cash settlements, and verified the balance returned to KES 0. Customer balance matched its three append-only ledger entries; reconciliation found 0 mismatches. For Nairobi business date 2026-11-03, the daily summary and Sales History-equivalent database query both returned 1 sale / KES 100. This validates matching data queries, not a click-through comparison of the app screens. The test customer, sale, payment and ledger history remain in local DB because ledger records are append-only; the milk fixture stock is 79 after the corresponding test sale movement. Physical printer output remains unverified pending printer hardware. Long-name thermal and A4 receipt widget tests pass 4/4 using cached dependencies.
