# Implementation Plan

Replace all hardcoded demo data (customers and sales) in the Flutter POS app with live API calls.

## Background

The POS app currently seeds hardcoded customers and sales in `_initSampleData()` (around line 1650) and never fetches them from the API. The API methods `getCustomers()` and `getSales()` exist but are unused. Products and categories already sync from the API in `_finishAuthenticatedLogin()` via `syncCatalogueFromApi()`.

**Decision**: Map API responses using new `fromApi()` factory constructors on `PosCustomer` and `SaleRecord`. This matches the existing pattern used by `PosUser.fromApi()` and `PosProduct._productFromApi()`.

## Implementation Steps

- [ ] 1. Add `PosCustomer.fromApi()` factory constructor in `lib/pos_state.dart` after the `PosCustomer` constructor (around line 356, right after `Money get availableCredit`).
      Map API fields: `id` → `id`, `fullName` → `name`, `phone` → `phone`, `creditLimit` (decimal KES) → `Money.parse(creditLimit.toString())`, `balance` (decimal) → `Money.parse(balance.toString())`.
      Map `ledger` array: for each entry, convert `entryType` "DEBIT" → `LedgerEntryType.saleDebit`, "CREDIT" → `LedgerEntryType.paymentCredit`; parse `amount` (decimal) → `Money.parse(amount.toString())`; parse `balance` → `runningBalance` as Money; convert `createdAt` (ISO 8601 string) → `DateTime.parse(createdAt)`.
      Files: `apps/shop_pos/lib/pos_state.dart`
      Verify: `flutter analyze --no-fatal-infos` in `apps/shop_pos` — no new errors.

- [ ] 2. Add `SaleRecord.fromApi()` factory constructor in `lib/pos_state.dart` after the `SaleRecord` class definition (around line 305, right after `bool get isReversed`).
      Map API fields: `receiptNumber` → `receiptNumber`, `createdAt` (ISO string) → `timestamp` via `DateTime.parse()`, `cashier.fullName` → `cashier` (string), `customer?.fullName` → customer name for lookup (see step 3).
      Map `items` array: each item → `SaleRecordItem(productId: item['productId'], productName: item['productName'], unitPrice: Money.parse(item['unitPrice'].toString()), quantity: item['quantity'], lineTotal: Money.parse(item['lineTotal'].toString()))`.
      Map `subtotal`, `total`, `vatAmount` (all decimals) → Money via `Money.parse()`.
      Map `payments[0].method`: "CASH" → `SalePaymentMethod.cash`, "MPESA" → `SalePaymentMethod.mpesa`, "CREDIT" → `SalePaymentMethod.credit`, "BANK" → `SalePaymentMethod.cash` (fallback — BANK not in Flutter enum), default → `SalePaymentMethod.cash`.
      Map `payments[0].reference` → `paymentReference`.
      Map `status`: "COMPLETED" → `SaleStatus.completed`, "REFUNDED" or "VOIDED" → `SaleStatus.reversed`, default → `SaleStatus.completed`.
      For cash sales, extract `cashTendered` and `changeDue` from payments metadata if present (set to null if not).
      Files: `apps/shop_pos/lib/pos_state.dart`
      Verify: `flutter analyze --no-fatal-infos` — no new errors.

- [ ] 3. Modify `SaleRecord.fromApi()` to accept an optional `customersMap` parameter (`Map<String, PosCustomer>?`) for customer lookup.
      If `customer?.fullName` exists in the API response and `customersMap` is provided, look up the customer by matching `fullName` case-insensitively. If found, assign to `customer` field; otherwise set to null.
      This allows sales to reference the same `PosCustomer` instances loaded earlier.
      Files: `apps/shop_pos/lib/pos_state.dart`
      Verify: `flutter analyze --no-fatal-infos` — no new errors.

- [ ] 4. Remove hardcoded customers and sales from `_initSampleData()` in `lib/pos_state.dart` (around line 1650).
      Remove the entire `customers = [...]` block (lines ~1662-1712) and replace with `customers = [];`.
      Remove the entire `sales = [...]` block (lines ~1714-1782) and replace with `sales = [];`.
      Keep the `shift = CashShift(...)` initialization and the cash sale movement recording (lines ~1784-1798) — but remove the movement that records the hardcoded sale (the `shift.movements.add(...)` block referencing 'RCP-2026-1041').
      Files: `apps/shop_pos/lib/pos_state.dart`
      Verify: `flutter analyze --no-fatal-infos` — no new errors.

- [ ] 5. Add API calls for customers and sales in `_finishAuthenticatedLogin()` in `lib/pos_state.dart` (around line 685-697).
      After `await syncCatalogueFromApi();` (line 694) and before `await persistSession(user);` (line 695), add:
      ```dart
      try {
        final remoteCustomers = await ApiService.instance.getCustomers();
        if (remoteCustomers != null) {
          customers = remoteCustomers.map((json) => PosCustomer.fromApi(json)).toList();
        } else {
          customers = [];
        }
      } catch (e) {
        debugPrint('Could not fetch customers from API: $e');
        customers = [];
      }

      try {
        final remoteSales = await ApiService.instance.getSales();
        if (remoteSales != null) {
          final customersMap = {for (final c in customers) c.name.toLowerCase(): c};
          sales = remoteSales.map((json) => SaleRecord.fromApi(json, customersMap: customersMap)).toList();
        } else {
          sales = [];
        }
      } catch (e) {
        debugPrint('Could not fetch sales from API: $e');
        sales = [];
      }
      ```
      This ensures customers and sales are fetched from the API on every authenticated login, with graceful fallback to empty lists on error.
      Files: `apps/shop_pos/lib/pos_state.dart`
      Verify: `flutter analyze --no-fatal-infos` — no new errors.

- [ ] 6. Run the widget test to confirm the demo data flag still works.
      The test uses `PosState(includeDemoProducts: true)` which should still seed demo products and an initial shift, but now customers and sales start empty.
      Files: `apps/shop_pos/test/widget_test.dart` (no changes needed)
      Verify: `flutter test test/widget_test.dart` in `apps/shop_pos` — all tests pass.

- [ ] 7. Verify the full build and test suite.
      Run the full Flutter build and test pipeline to confirm no regressions.
      Files: all files in `apps/shop_pos`
      Verify: `flutter test` in `apps/shop_pos` — all tests pass.

## API Response Mapping Reference

### API Customer Response
```json
{
  "id": "uuid",
  "fullName": "Mama Oliech Kitchen",
  "phone": "+254 722 102 304",
  "creditLimit": 25000.00,
  "balance": 4200.00,
  "status": "ACTIVE",
  "notes": "...",
  "createdAt": "2024-01-01T00:00:00.000Z",
  "ledger": [
    {
      "id": "uuid",
      "createdAt": "2024-01-01T00:00:00.000Z",
      "entryType": "DEBIT",
      "amount": 5200.00,
      "balance": 5200.00,
      "reference": "RCP-2026-1039",
      "note": "..."
    }
  ]
}
```

### API Sale Response
```json
{
  "id": "uuid",
  "receiptNumber": "RCP-2026-1040",
  "status": "COMPLETED",
  "subtotal": 315.00,
  "vatAmount": 42.00,
  "total": 315.00,
  "cashier": { "fullName": "John Mwangi" },
  "customer": { "fullName": "Mama Oliech", "phone": "+254..." },
  "items": [
    {
      "productId": "uuid",
      "productName": "Fresh milk 500ml",
      "sku": "MLK-500",
      "quantity": 2,
      "unitPrice": 65.00,
      "lineTotal": 130.00
    }
  ],
  "payments": [
    {
      "method": "MPESA",
      "amount": 315.00,
      "reference": "MPESA: QDH189XP01"
    }
  ],
  "createdAt": "2024-01-01T00:00:00.000Z"
}
```

### Flutter Money Class Usage
- `Money.parse("4200.00")` for decimal strings
- `Money.shillings(4200)` for whole shillings (integer)
- `Money(420000)` for minor units directly

### Enum Mappings
**LedgerEntryType**: API "DEBIT" → `saleDebit`, "CREDIT" → `paymentCredit`

**SalePaymentMethod**: API "CASH" → `cash`, "MPESA" → `mpesa`, "CREDIT" → `credit`, "BANK" → `cash` (fallback)

**SaleStatus**: API "COMPLETED" → `completed`, "REFUNDED"/"VOIDED" → `reversed`

## Notes

- The existing demo products and categories remain unchanged — they already sync from the API via `syncCatalogueFromApi()`.
- The `CashShift` initialization in `_initSampleData()` must remain — it creates the opening shift for the till drawer.
- The widget test passes `includeDemoProducts: true` which seeds demo products but now leaves customers and sales empty until login.
- API errors fallback gracefully to empty lists so the POS remains usable offline or when the API is unavailable.
