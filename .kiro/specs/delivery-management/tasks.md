# Implementation Plan: Delivery Management

## Overview

Implements last-mile delivery operations across three layers: Prisma schema extensions (shop-api), a new `delivery.router.ts` with all delivery endpoints, updates to the Flutter Web POS (`shop_pos`) including a Delivery tab and a Rider Dashboard view. The plan follows the existing architectural constraints (multi-tenant isolation, append-only ledger, Zod validation, `requireAuth`/`requireRole` middleware). There is no separate rider app — the `apps/shop_pos` Flutter app serves both roles, with role-based routing in `main.dart` directing RIDER users to `RiderHomeView`.

---

## Tasks

- [ ] 1. Extend Prisma schema with delivery models and enums
  - [ ] 1.1 Add `RIDER` to `UserRole` enum and `DELIVERY` to `EntityType` enum in `apps/shop-api/prisma/schema.prisma`
    - Append `RIDER` to the `UserRole` enum block
    - Append `DELIVERY` to the `EntityType` enum block
    - _Requirements: 1.1, 1.2_

  - [ ] 1.2 Add `DeliveryStatus` enum and three new Prisma models (`DeliveryOrder`, `RiderLedger`, `RiderPayout`)
    - Define `DeliveryStatus` enum with values `PENDING`, `ASSIGNED`, `IN_TRANSIT`, `DELIVERED`, `FAILED`, `CANCELLED`
    - Add `DeliveryOrder` model with all fields, relations, and indexes as specified in the design
    - Add `RiderLedger` model with append-only comment, fields, relations, and indexes
    - Add `RiderPayout` model with fields and relations
    - Add back-relation fields to `User`, `Business`, and `Sale` models (no new columns)
    - _Requirements: 1.3, 1.4, 1.5, 1.6_

  - [ ] 1.3 Write and apply the Prisma migration for all delivery schema changes
    - Create migration file `prisma/migrations/XXXXXX_delivery_management/migration.sql`
    - Include `ALTER TYPE "UserRole" ADD VALUE IF NOT EXISTS 'RIDER'`
    - Include `ALTER TYPE "EntityType" ADD VALUE IF NOT EXISTS 'DELIVERY'`
    - Create `DeliveryStatus` enum, `delivery_orders`, `rider_ledger`, and `rider_payouts` tables
    - Add append-only `BEFORE UPDATE` and `BEFORE DELETE` triggers on `rider_ledger` reusing `retail_os_forbid_mutation()`
    - Ensure no existing tables are dropped or altered
    - _Requirements: 1.7, 1.8_

  - [ ]* 1.4 Write property test for RiderLedger append-only enforcement
    - **Property 6: RiderLedger is append-only**
    - **Validates: Requirements 1.5, 1.7**

- [ ] 2. Update auth router to support RIDER role
  - [ ] 2.1 Add `RIDER` to `StaffCreateSchema` and `StaffUpdateSchema` role enums in `apps/shop-api/src/modules/auth/auth.router.ts`
    - Extend both Zod enum arrays to include `'RIDER'`
    - Confirm existing PIN verification and phone normalisation paths are unchanged
    - _Requirements: 2.2, 2.5_

  - [ ]* 2.2 Write property test for RIDER JWT login claims
    - **Property 12: RIDER JWT login claims**
    - **Validates: Requirements 2.1**

  - [ ]* 2.3 Write property test for login updating lastLoginAt
    - **Property 18: Login updates lastLoginAt**
    - **Validates: Requirements 2.6**

- [ ] 3. Checkpoint — Ensure schema migration and auth tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Implement delivery configuration endpoints
  - [ ] 4.1 Create `apps/shop-api/src/modules/delivery/delivery.router.ts` with config routes
    - Scaffold `deliveryRouter(businessId: string): Router` exporting function
    - Implement `GET /delivery/config` — read `delivery.base_fee` and `delivery.distance_topup_rate` from `business_settings`, return `{ baseFee, distanceTopupRate }`; accessible to all authenticated non-RIDER roles
    - Implement `PUT /delivery/config` with Zod schema `{ baseFee: z.number().nonnegative(), distanceTopupRate: z.number().nonnegative() }`; restrict to MANAGER/OWNER/SUPER_ADMIN; upsert both `BusinessSetting` rows
    - Add the RIDER gate middleware (reject RIDER on any non-`/rider/*` path with 403)
    - Mount the router in `apps/shop-api/src/index.ts` under `/delivery`
    - _Requirements: 3.1, 3.2, 3.3, 8.3_

  - [ ]* 4.2 Write property test for delivery config round-trip
    - **Property 3: Delivery config round-trip**
    - **Validates: Requirements 3.2**

  - [ ]* 4.3 Write property test for negative config rejection
    - **Property 4: Negative config rejected**
    - **Validates: Requirements 3.3**

- [ ] 5. Implement delivery order lifecycle endpoints
  - [ ] 5.1 Implement `POST /delivery/orders` (order creation)
    - Zod body: `CreateDeliveryOrderSchema` as specified in the design
    - Read `baseFee` and `topupRate` from `business_settings`
    - Compute `deliveryFee = baseFee + distanceKm × topupRate` using `Decimal` arithmetic (no floats)
    - Inside `prisma.$transaction`: create `DeliveryOrder` (status `PENDING`, snapshotted fees); if `saleId` present update `Sale.total` and insert `SalePayment` with `note: 'DELIVERY_FEE'`; insert `AuditLog`
    - Return 201 with the created order
    - _Requirements: 4.1, 4.2, 4.11, 3.4_

  - [ ]* 5.2 Write property test for delivery fee arithmetic
    - **Property 1: Delivery fee arithmetic**
    - **Validates: Requirements 4.1**

  - [ ]* 5.3 Write property test for fee snapshot immutability
    - **Property 2: Fee snapshot immutability**
    - **Validates: Requirements 3.4**

  - [ ] 5.4 Implement `GET /delivery/orders` and `GET /delivery/orders/:id`
    - `GET /delivery/orders`: paginated list, ordered by `createdAt` descending; roles CASHIER and above
    - `GET /delivery/orders/:id`: single order with rider name; roles CASHIER and above
    - _Requirements: 4.3, 4.4_

  - [ ]* 5.5 Write property test for order list ordering
    - **Property 15: Order list ordering**
    - **Validates: Requirements 4.3**

  - [ ] 5.6 Implement `PATCH /delivery/orders/:id/assign`
    - Validate `{ riderId: z.string().uuid() }`
    - Check target user is active and `role === RIDER`; return 422 `INVALID_RIDER` if not
    - Transition `PENDING → ASSIGNED`, set `assignedAt = now()`
    - Write `AuditLog` entry
    - _Requirements: 4.5, 4.6, 4.11_

  - [ ]* 5.7 Write property test for invalid rider assignment rejection
    - **Property 17: Invalid rider assignment rejected**
    - **Validates: Requirements 4.6**

  - [ ] 5.8 Implement `PATCH /delivery/orders/:id/status`
    - Accept `{ status, failureReason? }` with Zod validation
    - Enforce state machine: `ASSIGNED→IN_TRANSIT` (set `pickedUpAt`), `ASSIGNED→FAILED`, `IN_TRANSIT→DELIVERED` (set `deliveredAt`), `IN_TRANSIT→FAILED`; any other pair returns 422 `INVALID_TRANSITION`
    - On `DELIVERED`: inside the same transaction, read last `RiderLedger` balance, insert CREDIT entry (`amount = deliveryFee`, `entityType = DELIVERY`, `entityId = orderId`)
    - Write `AuditLog` entry
    - _Requirements: 4.7, 4.8, 4.10, 4.11_

  - [ ]* 5.9 Write property test for illegal status transitions rejected
    - **Property 10: Illegal delivery status transitions rejected**
    - **Validates: Requirements 4.7, 4.10**

  - [ ]* 5.10 Write property test for delivered order triggering rider ledger credit
    - **Property 5: Delivered order triggers rider ledger credit**
    - **Validates: Requirements 4.8**

  - [ ] 5.11 Implement `PATCH /delivery/orders/:id/cancel`
    - Accept only `PENDING` or `ASSIGNED` orders; transition to `CANCELLED`, record `failureReason`
    - Write `AuditLog` entry
    - Return 422 `INVALID_TRANSITION` for orders in any other status
    - _Requirements: 4.9, 4.11_

  - [ ]* 5.12 Write property test for delivery audit trail completeness
    - **Property 16: Delivery audit trail completeness**
    - **Validates: Requirements 4.11**

- [ ] 6. Checkpoint — Ensure all delivery order endpoint tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Implement rider earnings and M-Pesa payout endpoints
  - [ ] 7.1 Implement `GET /delivery/riders` and rider ledger/payout history endpoints
    - `GET /delivery/riders`: fetch all active RIDER users; for each, compute `pendingBalance` from `RiderLedger` using `SUM(CASE WHEN entryType='CREDIT' THEN amount ELSE -amount END)`
    - `GET /delivery/riders/:riderId/ledger`: paginated, chronological `RiderLedger` entries for the rider; MANAGER and above
    - `GET /delivery/riders/:riderId/payouts`: paginated `RiderPayout` history, ordered by `initiatedAt` descending; MANAGER and above
    - _Requirements: 5.1, 5.2, 5.8_

  - [ ]* 7.2 Write property test for running balance correctness
    - **Property 7: Running balance correctness**
    - **Validates: Requirements 5.1, 5.3**

  - [ ] 7.3 Implement `POST /delivery/riders/:riderId/payout`
    - Validate `{ amount: z.number().positive(), mpesaPhone: z.string().min(9).max(24) }`
    - Normalise phone with existing `normalizePhone` helper; return 400 `INVALID_PHONE` on failure
    - Compute available balance from `RiderLedger`; return 422 `INSUFFICIENT_BALANCE` if `amount > balance`
    - Initiate M-Pesa B2C disbursement via existing `mpesaService` pattern; store `checkoutRequestId`
    - Inside transaction: create `RiderPayout` (status `PENDING`); insert `RiderLedger` DEBIT referencing payout
    - Return 201 with payout record
    - _Requirements: 5.3, 5.6, 5.7, 8.1_

  - [ ]* 7.4 Write property test for insufficient balance rejection
    - **Property 9: Insufficient balance rejected**
    - **Validates: Requirements 5.6**

  - [ ] 7.5 Implement M-Pesa B2C callback handler (`POST /delivery/mpesa/b2c-callback`)
    - Validate Daraja signature
    - On success: update `RiderPayout.status = SUCCESS`, set `settledAt`, record `mpesaReceipt`
    - On failure: update `RiderPayout.status = FAILED`; insert reversing `RiderLedger` CREDIT entry of equal amount
    - _Requirements: 5.4, 5.5_

  - [ ]* 7.6 Write property test for payout reversal on M-Pesa failure
    - **Property 8: Payout reversal on M-Pesa failure**
    - **Validates: Requirements 5.5**

  - [ ]* 7.7 Write property test for payout role restriction
    - **Property 14: Payout role restriction**
    - **Validates: Requirements 8.1**

- [ ] 8. Implement rider-scoped endpoints and RIDER access gate
  - [ ] 8.1 Implement `GET /delivery/rider/orders` and `GET /delivery/rider/earnings`
    - Both routes under `/delivery/rider/*`, guarded by `requireRole('RIDER')`
    - `GET /delivery/rider/orders`: return `DeliveryOrder` where `riderId = auth.userId` and `status IN (ASSIGNED, IN_TRANSIT)`; server-side JWT `sub` claim validation
    - `GET /delivery/rider/earnings`: return `{ pendingBalance, entries: [...] }` for `riderId = auth.userId` with pagination
    - _Requirements: 7.4, 7.5, 7.8, 7.9, 7.11, 8.3_

  - [ ]* 8.2 Write property test for RIDER JWT restricted to rider-scoped routes
    - **Property 11: RIDER JWT restricted to rider-scoped routes**
    - **Validates: Requirements 2.3, 8.3**

  - [ ]* 8.3 Write property test for rider order isolation
    - **Property 13: Rider order isolation**
    - **Validates: Requirements 7.5, 7.11, 8.3**

- [ ] 9. Checkpoint — Ensure all shop-api tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Add Delivery tab to Flutter Web POS (`apps/shop_pos`)
  - [ ] 10.1 Update `_accessibleTabs` and navigation in `main.dart`
    - Extend `_accessibleTabs` switch to include index 8 for SUPER_ADMIN, OWNER, MANAGER, and CASHIER roles; exclude for STOCK_CLERK
    - Update `initState` tab index clamp from `0..7` to `0..8`
    - Add index-8 entry to `_NavigationSidebar` nav items list: `(tab: 8, icon: AppIcons.shipping, label: 'Delivery')`
    - _Requirements: 6.1, 6.2, 6.3, 6.9_

  - [ ] 10.2 Add `DeliveryView` widget and wire it into the `views` list in `main.dart`
    - Append `DeliveryView(state: widget.state)` at index 8 of the `views` list
    - Create `apps/shop_pos/lib/views/delivery_view.dart` with the three-tab structure: _DeliveryOrdersTab, _RidersTab (MANAGER+), _DeliveryConfigTab (MANAGER+)
    - _Requirements: 6.4, 6.6, 6.7_

  - [ ] 10.3 Implement `_CreateDeliveryOrderDialog` within `_DeliveryOrdersTab`
    - Fields: recipientName, recipientPhone, deliveryAddress, distanceKm
    - Pre-submit: call `GET /delivery/config` and compute fee display before final confirmation
    - On confirm: call `POST /delivery/orders` and show returned `deliveryFee` to cashier
    - Display error message on 422 `INVALID_RIDER` response from assignment requests
    - _Requirements: 6.4, 6.5, 6.8_

  - [ ] 10.4 Add delivery API methods to `apps/shop_pos/lib/services/api_service.dart`
    - Add all delivery-related methods: `getDeliveryConfig`, `updateDeliveryConfig`, `createDeliveryOrder`, `getDeliveryOrders`, `getDeliveryOrder`, `assignRider`, `updateDeliveryStatus`, `cancelDeliveryOrder`, `getRiders`, `getRiderLedger`, `initiateRiderPayout`
    - Follow the existing method pattern in `api_service.dart`
    - _Requirements: 6.5, 6.6, 6.7_

- [ ] 11. Implement Rider Dashboard in `apps/shop_pos`
  - [ ] 11.1 Add `rider` to `PosUserRole` enum and all related switches
    - Add `rider` value to the `PosUserRole` enum in the Dart models
    - Update all `switch` / `if` branches that enumerate roles: `roleDisplay`, `rolePermissions`, color token, `toJson`, `fromApi`, and `_accessibleTabs` (return empty set for RIDER — the rider never reaches `MainShell`)
    - _Requirements: 7.1, 7.3_

  - [ ] 11.2 Add post-login routing in `main.dart`
    - After authentication, check `currentLoggedInUser.role`
    - If `role == PosUserRole.rider`, navigate with `pushAndRemoveUntil` to `RiderHomeView`; otherwise navigate to the existing `MainShell` as before
    - A RIDER user SHALL see no POS tabs, no sidebar, and no admin controls
    - _Requirements: 7.1, 7.3_

  - [ ] 11.3 Create `lib/views/rider_home_view.dart`
    - Top-level `Scaffold` with AppBar ("Rider Dashboard") and a logout button
    - Earnings banner: call `getRiderEarnings()` → display `pendingBalance` formatted as KES; tapping opens scrollable ledger history
    - Active orders list: call `getRiderOrders()` → display cards for `ASSIGNED` and `IN_TRANSIT` orders (status chip, recipient name/phone, delivery address, delivery fee); tapping navigates to `RiderOrderDetailView`
    - _Requirements: 7.4, 7.6, 7.8_

  - [ ] 11.4 Create `lib/views/rider_order_detail_view.dart`
    - Display full order information (recipient name, phone, delivery address, delivery fee, current status)
    - "Pick Up" button for `ASSIGNED` orders → calls `PATCH /delivery/orders/:id/status` with `IN_TRANSIT`
    - "Delivered" button for `IN_TRANSIT` orders → calls `PATCH /delivery/orders/:id/status` with `DELIVERED`
    - On HTTP 401: clear stored token and redirect to login screen (reuse existing `ApiService` logout callback)
    - _Requirements: 7.6, 7.7, 7.10_

  - [ ] 11.5 Add rider-scoped API methods to `api_service.dart`
    - Add `getRiderOrders()` calling `GET /delivery/rider/orders`
    - Add `getRiderEarnings()` calling `GET /delivery/rider/earnings`
    - Follow the existing method pattern; attach `Authorization: Bearer <token>` via the existing header helper
    - _Requirements: 7.4, 7.8, 7.5, 7.9_

- [ ] 12. Final checkpoint — Ensure all tests pass across all apps
  - Ensure all tests pass, ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at sensible boundaries
- Property tests validate universal correctness properties; unit tests validate specific examples and edge cases
- The shop-api implementation uses TypeScript; the POS (including the Rider Dashboard) uses Dart/Flutter
- All monetary arithmetic must use `Decimal` (never floats) on both the backend and in Dart (`double` is acceptable in Dart for display only; the source of truth values come from the API as strings/decimals)
- There is no separate rider Flutter project — `apps/shop_pos` serves both the full POS and the Rider Dashboard via role-based routing in `main.dart`

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["1.4", "2.1"] },
    { "id": 4, "tasks": ["2.2", "2.3", "4.1"] },
    { "id": 5, "tasks": ["4.2", "4.3", "5.1"] },
    { "id": 6, "tasks": ["5.2", "5.3", "5.4"] },
    { "id": 7, "tasks": ["5.5", "5.6"] },
    { "id": 8, "tasks": ["5.7", "5.8"] },
    { "id": 9, "tasks": ["5.9", "5.10", "5.11"] },
    { "id": 10, "tasks": ["5.12", "7.1", "8.1"] },
    { "id": 11, "tasks": ["7.2", "7.3", "8.2", "8.3"] },
    { "id": 12, "tasks": ["7.4", "7.5"] },
    { "id": 13, "tasks": ["7.6", "7.7", "10.1"] },
    { "id": 14, "tasks": ["10.2"] },
    { "id": 15, "tasks": ["10.3", "10.4", "11.1"] },
    { "id": 16, "tasks": ["11.2"] },
    { "id": 17, "tasks": ["11.3", "11.5"] },
    { "id": 18, "tasks": ["11.4"] }
  ]
}
```
