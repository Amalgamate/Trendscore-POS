# Requirements Document

## Introduction

The Delivery Management feature extends ShopSmart POS to support last-mile delivery operations for shops that dispatch goods to customers. The feature adds a RIDER role to the existing user system, a Delivery tab to the Flutter Web POS (apps/shop_pos), and a Rider Dashboard within the same app for riders. Delivery fees are charged to customer orders, and rider earnings are tracked using the existing append-only ledger pattern and paid out via M-Pesa.

All monetary values are in Kenyan Shillings (KES), stored as NUMERIC(14,2). The feature integrates with the existing Shop API (Node.js/Express + Prisma + PostgreSQL) without altering the multi-tenant isolation model described in ADR-0001.

---

## Glossary

- **Delivery Management System**: The end-to-end set of backend services, POS UI changes, and Rider App that together form this feature.
- **Delivery Order**: A record associating a sale with a rider, a destination, a delivery fee, and a lifecycle status.
- **Rider**: A user whose `UserRole` is `RIDER`; authenticated via phone + PIN, issued a JWT, and restricted to the Rider App endpoints.
- **Rider Dashboard**: A role-gated view (`RiderHomeView`) inside the existing Flutter application at `apps/shop_pos`. When a user with role `RIDER` logs in, the app renders `RiderHomeView` instead of the normal `MainShell`. Riders see only their trips and earnings — no POS tabs, no admin controls.
- **POS**: The existing Flutter Web application at `apps/shop_pos`.
- **Shop API**: The existing Node.js/Express backend at `apps/shop-api`.
- **RiderLedger**: The append-only table that records every credit or debit against a rider's earned-but-unpaid balance.
- **Base Fee**: A per-delivery flat amount set by a MANAGER or above and stored in `business_settings`.
- **Distance Top-up Rate**: A per-kilometre charge set by a MANAGER or above and stored in `business_settings`.
- **Delivery Fee**: The total charge billed to the customer: `base_fee + (distance_km × distance_topup_rate)`.
- **Rider Earnings**: The amount credited to the rider's `RiderLedger` upon delivery completion; equal to the Delivery Fee.
- **M-Pesa Payout**: A disbursement of rider earnings via the Daraja STK Push / B2C API, recorded as a RiderLedger debit.
- **EntityType.DELIVERY**: A new enum variant added to the existing `EntityType` enum, used to reference Delivery Orders from ledger entries and approvals.
- **DeliveryStatus**: An enum governing the lifecycle of a Delivery Order: `PENDING → ASSIGNED → IN_TRANSIT → DELIVERED → FAILED → CANCELLED`.
- **JWT**: A JSON Web Token issued by the Shop API; carries `sub` (userId), `role`, and `name` claims; verified on every request.

---

## Requirements

### Requirement 1 — Schema and Enum Extensions

**User Story:** As a platform developer, I want the database schema extended with delivery-specific models and enums, so that all other delivery features have a sound data foundation.

#### Acceptance Criteria

1. THE Delivery Management System SHALL add `RIDER` to the `UserRole` enum in `apps/shop-api/prisma/schema.prisma`.
2. THE Delivery Management System SHALL add `DELIVERY` to the `EntityType` enum in `apps/shop-api/prisma/schema.prisma`.
3. THE Delivery Management System SHALL define a `DeliveryStatus` enum with values `PENDING`, `ASSIGNED`, `IN_TRANSIT`, `DELIVERED`, `FAILED`, and `CANCELLED` in the Prisma schema.
4. THE Delivery Management System SHALL create a `DeliveryOrder` model with fields: `id` (UUID PK), `businessId` (UUID FK → Business), `saleId` (UUID FK → Sale, nullable), `riderId` (UUID FK → User, nullable), `status` (`DeliveryStatus`, default `PENDING`), `recipientName` (String), `recipientPhone` (String), `deliveryAddress` (String), `distanceKm` (NUMERIC(8,2)), `baseFee` (NUMERIC(14,2)), `topupRate` (NUMERIC(14,2)), `deliveryFee` (NUMERIC(14,2)), `assignedAt` (DateTime, nullable), `pickedUpAt` (DateTime, nullable), `deliveredAt` (DateTime, nullable), `failureReason` (String, nullable), `createdById` (UUID FK → User), `createdAt` (DateTime, default now), `updatedAt` (DateTime, @updatedAt).
5. THE Delivery Management System SHALL create a `RiderLedger` model that is append-only with fields: `id` (UUID PK), `businessId` (UUID FK → Business), `riderId` (UUID FK → User), `entryType` (`LedgerEntryType`), `amount` (NUMERIC(14,2)), `balance` (NUMERIC(14,2), running total after this entry), `entityType` (`EntityType`), `entityId` (UUID, nullable), `reference` (String, nullable), `note` (String, nullable), `createdAt` (DateTime, default now), `createdById` (UUID FK → User, nullable).
6. THE Delivery Management System SHALL add a `RiderPayout` model with fields: `id` (UUID PK), `businessId` (UUID FK → Business), `riderId` (UUID FK → User), `amount` (NUMERIC(14,2)), `mpesaPhone` (String), `mpesaReceipt` (String, nullable, unique), `checkoutRequestId` (String, nullable), `status` (`PaymentStatus`), `initiatedAt` (DateTime, default now), `settledAt` (DateTime, nullable), `riderLedgerEntryId` (UUID FK → RiderLedger).
7. THE Delivery Management System SHALL enforce append-only immutability on `RiderLedger` via a database trigger in the migration file, consistent with the pattern used for `CustomerLedger`.
8. IF a migration is run against an existing database, THEN THE Delivery Management System SHALL apply changes in a single Prisma migration without dropping or altering existing tables.

---

### Requirement 2 — Rider Authentication

**User Story:** As a rider, I want to log in with my phone number and PIN, so that I can access my assigned trips and earnings securely.

#### Acceptance Criteria

1. WHEN a POST request is submitted to `/auth/login` with a valid phone and PIN belonging to a `RIDER` role user, THE Shop API SHALL return a JWT with claims `{ sub, role: "RIDER", name }` and an 8-hour expiry.
2. THE Shop API SHALL validate `RIDER` accounts using the same argon2id PIN verification and phone normalisation logic used for all other roles.
3. WHILE a `RIDER` JWT is active, THE Shop API SHALL reject requests to any endpoint not in the rider-scoped route group with HTTP 403 `FORBIDDEN`.
4. IF a RIDER account has `mustChangePin: true`, THEN THE Shop API SHALL respond with HTTP 403 `PIN_CHANGE_REQUIRED` on any request other than `POST /auth/change-pin`, consistent with existing role behaviour.
5. THE Shop API SHALL include `RIDER` in the `StaffCreateSchema` and `StaffUpdateSchema` validation enums so that OWNER and SUPER_ADMIN staff can create and manage rider accounts.
6. WHEN a rider authenticates successfully, THE Shop API SHALL update the `lastLoginAt` timestamp on the User record.

---

### Requirement 3 — Delivery Configuration

**User Story:** As a manager, I want to set the base delivery fee and per-km top-up rate, so that delivery fees are calculated consistently across all orders.

#### Acceptance Criteria

1. THE Shop API SHALL expose `GET /delivery/config` (authenticated, any role) that returns the current `base_fee` and `distance_topup_rate` from `business_settings`.
2. THE Shop API SHALL expose `PUT /delivery/config` (authenticated, MANAGER or above) that accepts `{ baseFee: NUMERIC(14,2), distanceTopupRate: NUMERIC(14,2) }` and persists both values to `business_settings` under keys `delivery.base_fee` and `delivery.distance_topup_rate`.
3. WHEN `PUT /delivery/config` is called with a `baseFee` less than 0 or a `distanceTopupRate` less than 0, THE Shop API SHALL respond with HTTP 400 `VALIDATION_ERROR`.
4. WHEN a delivery order is created, THE Delivery Management System SHALL snapshot the current `baseFee` and `distanceTopupRate` into the `DeliveryOrder.baseFee` and `DeliveryOrder.topupRate` fields so that subsequent config changes do not alter historic order fees.

---

### Requirement 4 — Delivery Order Lifecycle (Shop API)

**User Story:** As a cashier, I want to create a delivery order when checking out a customer, and as a manager I want to assign a rider and track the delivery to completion.

#### Acceptance Criteria

1. THE Shop API SHALL expose `POST /delivery/orders` (authenticated, CASHIER or above) that accepts `{ saleId?, recipientName, recipientPhone, deliveryAddress, distanceKm }`, computes `deliveryFee = baseFee + distanceKm × distanceTopupRate`, creates a `DeliveryOrder` with status `PENDING`, and returns the created order.
2. WHEN `POST /delivery/orders` is called, THE Shop API SHALL add the `deliveryFee` to the associated sale's total and create a corresponding `SalePayment` entry with a `DELIVERY_FEE` note if a `saleId` is provided.
3. THE Shop API SHALL expose `GET /delivery/orders` (authenticated, CASHIER or above) that returns a paginated list of delivery orders for the business, ordered by `createdAt` descending.
4. THE Shop API SHALL expose `GET /delivery/orders/:id` (authenticated, CASHIER or above) that returns a single delivery order with its associated rider name.
5. THE Shop API SHALL expose `PATCH /delivery/orders/:id/assign` (authenticated, MANAGER or above) that accepts `{ riderId }`, transitions the order from `PENDING` to `ASSIGNED`, sets `assignedAt` to the current timestamp, and returns the updated order.
6. WHEN `PATCH /delivery/orders/:id/assign` is called with a `riderId` that does not resolve to an active User with role `RIDER`, THE Shop API SHALL respond with HTTP 422 `INVALID_RIDER`.
7. THE Shop API SHALL expose `PATCH /delivery/orders/:id/status` (authenticated, MANAGER or above) that accepts `{ status, failureReason? }` and validates that the requested transition follows the sequence `ASSIGNED → IN_TRANSIT → DELIVERED` or `ASSIGNED|IN_TRANSIT → FAILED`, setting `pickedUpAt` on transition to `IN_TRANSIT` and `deliveredAt` on transition to `DELIVERED`.
8. WHEN a delivery order transitions to `DELIVERED`, THE Shop API SHALL create an append-only `RiderLedger` credit entry for the rider equal to `deliveryFee`, with `entityType = DELIVERY` and `entityId` referencing the `DeliveryOrder`.
9. THE Shop API SHALL expose `PATCH /delivery/orders/:id/cancel` (authenticated, MANAGER or above) that transitions a `PENDING` or `ASSIGNED` order to `CANCELLED` and records the reason in `failureReason`.
10. IF a status transition is requested that violates the defined sequence, THEN THE Shop API SHALL respond with HTTP 422 `INVALID_TRANSITION`.
11. WHEN a delivery order is created, updated, or cancelled, THE Shop API SHALL write an `AuditLog` entry with `entityType = 'DELIVERY_ORDER'` and the relevant `entityId`.

---

### Requirement 5 — Rider Earnings and M-Pesa Payouts (Shop API)

**User Story:** As a manager, I want to view a rider's earnings ledger and initiate M-Pesa payouts, so that riders are paid accurately and transparently.

#### Acceptance Criteria

1. THE Shop API SHALL expose `GET /delivery/riders` (authenticated, MANAGER or above) that returns a list of all active users with role `RIDER`, each including the rider's current pending earnings balance derived from `RiderLedger`.
2. THE Shop API SHALL expose `GET /delivery/riders/:riderId/ledger` (authenticated, MANAGER or above) that returns a paginated, chronologically ordered list of `RiderLedger` entries for the specified rider.
3. THE Shop API SHALL expose `POST /delivery/riders/:riderId/payout` (authenticated, MANAGER or above) that accepts `{ amount, mpesaPhone }`, validates that `amount` does not exceed the rider's available `RiderLedger` balance, initiates an M-Pesa B2C disbursement, creates a `RiderPayout` record with status `PENDING`, and creates an append-only `RiderLedger` debit entry with `entityType = DELIVERY` and `entityId` referencing the `RiderPayout`.
4. WHEN the M-Pesa callback confirms a successful disbursement, THE Shop API SHALL update `RiderPayout.status` to `SUCCESS`, set `settledAt` to the callback timestamp, and record the M-Pesa receipt number in `RiderPayout.mpesaReceipt`.
5. WHEN the M-Pesa callback reports a failure, THE Shop API SHALL update `RiderPayout.status` to `FAILED` and reverse the `RiderLedger` debit by creating a new CREDIT entry of equal amount referencing the failed payout.
6. IF `POST /delivery/riders/:riderId/payout` is called with an `amount` greater than the rider's available balance, THEN THE Shop API SHALL respond with HTTP 422 `INSUFFICIENT_BALANCE`.
7. IF `POST /delivery/riders/:riderId/payout` is called with an `mpesaPhone` that fails Kenyan phone number validation, THEN THE Shop API SHALL respond with HTTP 400 `INVALID_PHONE`.
8. THE Shop API SHALL expose `GET /delivery/riders/:riderId/payouts` (authenticated, MANAGER or above) that returns a paginated history of `RiderPayout` records for the rider, ordered by `initiatedAt` descending.

---

### Requirement 6 — Delivery Tab in ShopSmart POS (Flutter Web)

**User Story:** As a cashier, I want a Delivery tab in the POS, so that I can create delivery orders; as a manager, I want to manage rider assignments and monitor deliveries from the same tab.

#### Acceptance Criteria

1. THE POS SHALL add a Delivery tab at index 8 in the `_NavigationSidebar` and `_MobileBottomNav`, visible to users with role `CASHIER`, `MANAGER`, `OWNER`, or `SUPER_ADMIN`.
2. WHEN the POS renders the `_accessibleTabs` set for a `CASHIER`, THE POS SHALL include tab index 8 in the accessible set.
3. WHEN the POS renders the `_accessibleTabs` set for a `MANAGER`, `OWNER`, or `SUPER_ADMIN`, THE POS SHALL include tab index 8 in the accessible set.
4. THE POS SHALL display a Delivery Order creation form accessible to CASHIER and above, with fields for recipient name, recipient phone, delivery address, and distance in kilometres.
5. WHEN a CASHIER submits the Delivery Order creation form, THE POS SHALL call `POST /delivery/orders` on the Shop API and display the returned `deliveryFee` to the cashier before confirming.
6. THE POS SHALL display a list of all delivery orders for the business, showing order status, recipient name, assigned rider, and delivery fee.
7. WHEN a MANAGER, OWNER, or SUPER_ADMIN views the Delivery tab, THE POS SHALL display controls to assign an available rider to a `PENDING` order and to update an order's status.
8. WHEN the Shop API returns HTTP 422 `INVALID_RIDER` in response to an assignment request, THE POS SHALL display an error message stating that the selected rider is unavailable.
9. IF a STOCK_CLERK is logged in, THE POS SHALL NOT include tab index 8 in the accessible set for that user.

---

### Requirement 7 — Rider Dashboard (apps/shop_pos)

**User Story:** As a rider, I want the same POS app to show me a Rider Dashboard after I log in, displaying my assigned trips and accumulated earnings, so that I can fulfil deliveries and track my pay without needing a separate application.

#### Acceptance Criteria

1. WHEN a user with `role = RIDER` completes login in `apps/shop_pos`, THE POS SHALL render `RiderHomeView` (located at `apps/shop_pos/lib/views/rider_home_view.dart`) instead of the normal `MainShell` with the sidebar. No separate Flutter project is required.
2. THE Rider Dashboard SHALL present a phone + PIN login screen that calls `POST /auth/login` on the Shop API and stores the returned JWT using `SharedPreferences` (the same mechanism used by the rest of `apps/shop_pos`).
3. WHEN the POS receives a JWT with `role: "RIDER"`, THE POS SHALL navigate to `RiderHomeView`; WHEN the JWT contains any other role, the POS SHALL continue to the existing `MainShell` flow. A RIDER user SHALL NOT see any POS tabs or admin controls.
4. THE Rider Dashboard SHALL display a list of delivery orders where `riderId` matches the authenticated rider and `status` is `ASSIGNED` or `IN_TRANSIT`, retrieved via `GET /delivery/rider/orders`.
5. THE Rider Dashboard SHALL expose a rider-scoped endpoint `GET /delivery/rider/orders` in the Shop API that returns only the orders assigned to the authenticated rider, enforced server-side by comparing the JWT `sub` claim to `DeliveryOrder.riderId`.
6. WHEN a rider taps an assigned order, THE Rider Dashboard SHALL display the recipient name, phone, delivery address, and delivery fee for that order.
7. THE Rider Dashboard SHALL allow a rider to transition an `ASSIGNED` order to `IN_TRANSIT` and an `IN_TRANSIT` order to `DELIVERED` via `PATCH /delivery/orders/:id/status`, using the rider's JWT for authentication.
8. WHILE the rider is authenticated, THE Rider Dashboard SHALL display the rider's current pending earnings balance retrieved from a rider-scoped endpoint `GET /delivery/rider/earnings`.
9. THE Shop API SHALL expose `GET /delivery/rider/earnings` (authenticated, RIDER role only) that returns the authenticated rider's current pending earnings balance and a paginated list of the rider's `RiderLedger` entries.
10. IF the Rider Dashboard JWT expires or is rejected by the Shop API with HTTP 401, THEN THE POS SHALL clear the stored token and redirect the rider to the login screen.
11. THE Rider Dashboard SHALL NOT display or expose earnings data belonging to any rider other than the currently authenticated rider, enforced by server-side JWT sub-claim validation.

---

### Requirement 8 — Access Control and Data Isolation

**User Story:** As a system owner, I want delivery data access controlled by role, so that riders see only their own data and cashiers cannot trigger payouts.

#### Acceptance Criteria

1. THE Shop API SHALL reject any request to `POST /delivery/riders/:riderId/payout` made with a JWT whose role is `CASHIER`, `STOCK_CLERK`, or `RIDER`, responding with HTTP 403 `FORBIDDEN`.
2. THE Shop API SHALL reject any request to `PATCH /delivery/orders/:id/assign` or `PATCH /delivery/orders/:id/status` made with a JWT whose role is `CASHIER` or `STOCK_CLERK`, responding with HTTP 403 `FORBIDDEN`.
3. WHEN a RIDER JWT is used on any endpoint outside of `/auth/*`, `/delivery/rider/*`, the rider-scoped endpoints SHALL be the only accessible routes; all other business routes SHALL respond with HTTP 403 `FORBIDDEN`.
4. THE Shop API SHALL validate on every request that the user record in the database is active and that the role from the database matches the role claimed in the JWT, consistent with the existing `requireAuth` middleware pattern.
5. THE POS SHALL transmit the JWT as a Bearer token in the `Authorization` header on every API request made from `RiderHomeView`, and SHALL NOT persist the raw PIN in local storage.
