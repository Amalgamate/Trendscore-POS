# Design Document — Delivery Management

## Overview

The Delivery Management feature extends ShopSmart POS with last-mile delivery operations. It adds a `RIDER` role to the existing user system, delivery-specific Prisma models, a new `delivery.router.ts` in the shop-api, a new Delivery tab (index 8) in the Flutter Web POS (`apps/shop_pos`), and a Rider Dashboard (`RiderHomeView`) inside the same `apps/shop_pos` app. When a user with role `RIDER` logs in, the app renders `RiderHomeView` instead of the normal `MainShell`; all other roles continue to the full POS sidebar.

The design follows every architectural constraint already in place:

- **Multi-tenant isolation (ADR-0001):** `businessId` is scoped via the `BUSINESS_ID` environment variable, never from a JWT claim.
- **Append-only financials:** `RiderLedger` follows the same pattern as `CustomerLedger`; corrections are reversing entries, never UPDATEs.
- **Money is `NUMERIC(14,2)` everywhere** — no floats.
- **JWT middleware (`requireAuth` + `requireRole`):** Delivery routes compose the existing middleware without modification.
- **Zod validation for all request bodies and query strings.**

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                 shop-api (Node.js/Express)        │
│  /auth/*         ← existing (RIDER added)        │
│  /delivery/*     ← new delivery.router.ts        │
│    /delivery/config          (GET, PUT)           │
│    /delivery/orders          (GET, POST)          │
│    /delivery/orders/:id      (GET)                │
│    /delivery/orders/:id/assign  (PATCH)           │
│    /delivery/orders/:id/status  (PATCH)           │
│    /delivery/orders/:id/cancel  (PATCH)           │
│    /delivery/riders          (GET)                │
│    /delivery/riders/:id/ledger  (GET)             │
│    /delivery/riders/:id/payout  (POST)            │
│    /delivery/riders/:id/payouts (GET)             │
│    /delivery/rider/orders    ← RIDER-scoped       │
│    /delivery/rider/earnings  ← RIDER-scoped       │
│  PostgreSQL via Prisma                            │
└──────────────────┬──────────────────────────────┘
                   │ HTTP/JSON (JWT Bearer)
                   │
        ┌──────────┴──────────────────────┐
        │         apps/shop_pos           │
        │         Flutter Web/Mobile      │
        │                                 │
        │  role != RIDER → MainShell      │
        │    (full POS + Delivery tab)    │
        │                                 │
        │  role == RIDER → RiderHomeView  │
        │    (trips + earnings only)      │
        └─────────────────────────────────┘
```

---

## Component Breakdown

### 1. Prisma Schema Extensions (`apps/shop-api/prisma/schema.prisma`)

Add to existing enums and create three new models. All changes land in a single migration file.

**Enum additions:**

```prisma
enum UserRole {
  SUPER_ADMIN
  OWNER
  MANAGER
  CASHIER
  STOCK_CLERK
  RIDER          // ← new
}

enum EntityType {
  SALE
  PURCHASE
  REFUND
  ADJUSTMENT
  EXPENSE
  CUSTOMER_PAYMENT
  SUPPLIER_PAYMENT
  CASH_SESSION
  OPENING_BALANCE
  DELIVERY        // ← new
}

enum DeliveryStatus {  // ← new enum
  PENDING
  ASSIGNED
  IN_TRANSIT
  DELIVERED
  FAILED
  CANCELLED
}
```

**New models:**

```prisma
model DeliveryOrder {
  id              String         @id @default(uuid()) @db.Uuid
  businessId      String         @db.Uuid
  saleId          String?        @db.Uuid
  riderId         String?        @db.Uuid
  status          DeliveryStatus @default(PENDING)
  recipientName   String
  recipientPhone  String
  deliveryAddress String
  distanceKm      Decimal        @db.Decimal(8, 2)
  /// Snapshotted from business_settings at order creation time.
  baseFee         Decimal        @db.Decimal(14, 2)
  topupRate       Decimal        @db.Decimal(14, 2)
  /// Computed: baseFee + distanceKm × topupRate. Stored for fast queries.
  deliveryFee     Decimal        @db.Decimal(14, 2)
  assignedAt      DateTime?
  pickedUpAt      DateTime?
  deliveredAt     DateTime?
  failureReason   String?
  createdById     String         @db.Uuid
  createdAt       DateTime       @default(now())
  updatedAt       DateTime       @updatedAt

  business  Business @relation(fields: [businessId], references: [id], onDelete: Restrict)
  sale      Sale?    @relation(fields: [saleId],    references: [id], onDelete: SetNull)
  rider     User?    @relation("RiderDeliveries",   fields: [riderId],     references: [id], onDelete: SetNull)
  createdBy User     @relation("DeliveryCreatedBy", fields: [createdById], references: [id], onDelete: Restrict)

  @@index([businessId, createdAt])
  @@index([riderId, status])
  @@index([saleId])
  @@map("delivery_orders")
}

/// APPEND-ONLY. Corrections are always new entries, never UPDATE or DELETE.
/// Trigger in migration enforces this at the DB level.
model RiderLedger {
  id          String          @id @default(uuid()) @db.Uuid
  businessId  String          @db.Uuid
  riderId     String          @db.Uuid
  entryType   LedgerEntryType
  amount      Decimal         @db.Decimal(14, 2)
  /// Running balance AFTER this entry.
  balance     Decimal         @db.Decimal(14, 2)
  entityType  EntityType
  entityId    String?         @db.Uuid
  reference   String?
  note        String?
  createdAt   DateTime        @default(now())
  createdById String?         @db.Uuid

  rider    User     @relation("RiderLedgerEntries", fields: [riderId],     references: [id], onDelete: Restrict)
  business Business @relation(fields: [businessId], references: [id], onDelete: Restrict)

  @@index([riderId, createdAt])
  @@index([businessId, createdAt])
  @@map("rider_ledger")
}

model RiderPayout {
  id                 String        @id @default(uuid()) @db.Uuid
  businessId         String        @db.Uuid
  riderId            String        @db.Uuid
  amount             Decimal       @db.Decimal(14, 2)
  mpesaPhone         String
  mpesaReceipt       String?       @unique
  checkoutRequestId  String?
  status             PaymentStatus
  initiatedAt        DateTime      @default(now())
  settledAt          DateTime?
  riderLedgerEntryId String        @db.Uuid

  rider        User        @relation("RiderPayouts",      fields: [riderId],            references: [id], onDelete: Restrict)
  business     Business    @relation(fields: [businessId], references: [id], onDelete: Restrict)
  ledgerEntry  RiderLedger @relation(fields: [riderLedgerEntryId], references: [id], onDelete: Restrict)

  @@index([riderId, initiatedAt])
  @@index([status])
  @@map("rider_payouts")
}
```

The `User` model gains two new back-relation fields (no new columns):

```prisma
riderDeliveries     DeliveryOrder[]  @relation("RiderDeliveries")
deliveriesCreated   DeliveryOrder[]  @relation("DeliveryCreatedBy")
riderLedgerEntries  RiderLedger[]    @relation("RiderLedgerEntries")
riderPayouts        RiderPayout[]    @relation("RiderPayouts")
```

The `Business` model gains back-relations for `DeliveryOrder`, `RiderLedger`, and `RiderPayout`.

The `Sale` model gains a back-relation:

```prisma
deliveryOrders DeliveryOrder[]
```

---

### 2. Migration File

A new migration at `prisma/migrations/XXXXXX_delivery_management/migration.sql` will:

1. Add `RIDER` to the `UserRole` enum (`ALTER TYPE "UserRole" ADD VALUE IF NOT EXISTS 'RIDER'`).
2. Add `DELIVERY` to the `EntityType` enum.
3. Create the `DeliveryStatus` enum.
4. Create the `delivery_orders`, `rider_ledger`, and `rider_payouts` tables.
5. Add append-only triggers for `rider_ledger` (matching the pattern in `0001_immutable_ledgers`):

```sql
CREATE TRIGGER rider_ledger_no_update
BEFORE UPDATE ON rider_ledger
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

CREATE TRIGGER rider_ledger_no_delete
BEFORE DELETE ON rider_ledger
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();
```

6. Add the new `deliveryFee` money columns to the numeric invariant check in the `DO $$` block.

---

### 3. Delivery Router (`apps/shop-api/src/modules/delivery/delivery.router.ts`)

One file exports `deliveryRouter(businessId: string): Router`. It is mounted in `index.ts` alongside the existing routers:

```typescript
app.use('/delivery', deliveryRouter(BUSINESS_ID));
```

The router is split into three logical groups:

#### 3a. Delivery Configuration

| Method | Path              | Auth                        |
|--------|-------------------|-----------------------------|
| GET    | `/delivery/config` | `requireAuth` (any role except RIDER) |
| PUT    | `/delivery/config` | `requireAuth`, `requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN')` |

`GET` reads `business_settings` keys `delivery.base_fee` and `delivery.distance_topup_rate`, returning `{ baseFee, distanceTopupRate }`.

`PUT` validates `{ baseFee: z.number().nonnegative(), distanceTopupRate: z.number().nonnegative() }` via Zod, then upserts both `BusinessSetting` rows using Prisma's `upsert` with `@@unique([businessId, key])`.

#### 3b. Delivery Order Lifecycle

| Method | Path                               | Roles                                   |
|--------|------------------------------------|------------------------------------------|
| POST   | `/delivery/orders`                  | CASHIER, MANAGER, OWNER, SUPER_ADMIN     |
| GET    | `/delivery/orders`                  | CASHIER, MANAGER, OWNER, SUPER_ADMIN     |
| GET    | `/delivery/orders/:id`              | CASHIER, MANAGER, OWNER, SUPER_ADMIN     |
| PATCH  | `/delivery/orders/:id/assign`       | MANAGER, OWNER, SUPER_ADMIN              |
| PATCH  | `/delivery/orders/:id/status`       | MANAGER, OWNER, SUPER_ADMIN              |
| PATCH  | `/delivery/orders/:id/cancel`       | MANAGER, OWNER, SUPER_ADMIN              |

**POST `/delivery/orders`**

Zod body schema:

```typescript
const CreateDeliveryOrderSchema = z.object({
  saleId:          z.string().uuid().optional(),
  recipientName:   z.string().trim().min(1).max(120),
  recipientPhone:  z.string().min(9).max(24),
  deliveryAddress: z.string().trim().min(1),
  distanceKm:      z.number().nonnegative(),
});
```

Handler logic (inside `prisma.$transaction`):

1. Read `business_settings` for `delivery.base_fee` and `delivery.distance_topup_rate` (defaults to `0` if not set).
2. Compute `deliveryFee = baseFee + distanceKm × topupRate` (using `Decimal` arithmetic, never floats).
3. Create `DeliveryOrder` with `status: PENDING`, snapshotting `baseFee`, `topupRate`, and `deliveryFee`.
4. If `saleId` is present: update `Sale.total` by adding `deliveryFee`, create a `SalePayment` row with `method: CASH` (or a new `DELIVERY_FEE` pseudo-method via a note field), `note: 'DELIVERY_FEE'`.
5. Write an `AuditLog` entry with `entityType: 'DELIVERY_ORDER'`, `action: 'CREATE'`.

**PATCH `/delivery/orders/:id/assign`**

Validates `{ riderId: z.string().uuid() }`. Checks the target user is active and has role `RIDER`; if not, returns 422 `INVALID_RIDER`. Transitions `PENDING → ASSIGNED`, sets `assignedAt = now()`. Writes audit log.

**PATCH `/delivery/orders/:id/status`**

Validates `{ status: z.enum([...]), failureReason: z.string().optional() }`.

State machine (legal transitions only):

```
ASSIGNED  → IN_TRANSIT  (sets pickedUpAt)
ASSIGNED  → FAILED
IN_TRANSIT → DELIVERED  (sets deliveredAt, triggers RiderLedger CREDIT)
IN_TRANSIT → FAILED
```

Any other `(current, requested)` pair returns 422 `INVALID_TRANSITION`.

On `DELIVERED`: inside the same transaction, create an append-only `RiderLedger` CREDIT entry for the rider, deriving the new `balance` as the previous balance plus `deliveryFee`. Write audit log.

**PATCH `/delivery/orders/:id/cancel`**

Accepts only `PENDING` or `ASSIGNED` orders. Sets `status: CANCELLED`, records `failureReason`. Writes audit log.

#### 3c. Rider Earnings and Payouts

| Method | Path                                  | Roles                              |
|--------|---------------------------------------|------------------------------------|
| GET    | `/delivery/riders`                     | MANAGER, OWNER, SUPER_ADMIN        |
| GET    | `/delivery/riders/:riderId/ledger`     | MANAGER, OWNER, SUPER_ADMIN        |
| POST   | `/delivery/riders/:riderId/payout`     | MANAGER, OWNER, SUPER_ADMIN        |
| GET    | `/delivery/riders/:riderId/payouts`    | MANAGER, OWNER, SUPER_ADMIN        |

**GET `/delivery/riders`** fetches all active `User` records with `role: RIDER`. For each rider, derives `pendingBalance` by summing `RiderLedger` entries: `SUM(CASE WHEN entryType='CREDIT' THEN amount ELSE -amount END)`.

**POST `/delivery/riders/:riderId/payout`**

```typescript
const CreatePayoutSchema = z.object({
  amount:     z.number().positive(),
  mpesaPhone: z.string().min(9).max(24),
});
```

Handler:
1. Normalise phone with the existing `normalizePhone` helper. If invalid, return 400 `INVALID_PHONE`.
2. Compute available balance from `RiderLedger`. If `amount > balance`, return 422 `INSUFFICIENT_BALANCE`.
3. Initiate M-Pesa B2C via the existing Daraja integration (the `mpesaService` pattern already present in the codebase). Record `checkoutRequestId`.
4. Inside a transaction: create `RiderPayout` with `status: PENDING`; create `RiderLedger` DEBIT entry referencing the payout; update the rider's running balance.

**M-Pesa Callback Handler** (`POST /delivery/mpesa/b2c-callback` — unauthenticated, validated by Daraja signature):
- On success: update `RiderPayout.status = SUCCESS`, `settledAt`, `mpesaReceipt`.
- On failure: update `RiderPayout.status = FAILED`; create a reversing `RiderLedger` CREDIT entry of equal amount.

#### 3d. Rider-Scoped Endpoints (RIDER role only)

Both routes sit under `/delivery/rider/*` and are guarded by `requireRole('RIDER')`.

```
GET /delivery/rider/orders
GET /delivery/rider/earnings
```

**GET `/delivery/rider/orders`**: Returns `DeliveryOrder` rows where `riderId = auth.userId` and `status IN (ASSIGNED, IN_TRANSIT)`. The server compares `auth.userId` (derived from the verified JWT `sub` claim as refreshed from the DB by `requireAuth`) to `DeliveryOrder.riderId`, so no rider can see another's orders.

**GET `/delivery/rider/earnings`**: Returns `{ pendingBalance, entries: [...] }` for `riderId = auth.userId` only, with pagination.

---

### 4. RIDER Access Gate in `requireAuth`

The existing `requireAuth` middleware already refreshes the user's role from the DB on every request. No changes are needed there.

The RIDER gate is a new guard applied to all non-rider routes by mounting the delivery router with a sub-middleware:

```typescript
// In delivery.router.ts, before the RIDER-only routes:
// Any authenticated RIDER hitting a non-rider route gets 403.
router.use((req, res, next) => {
  const auth = res.locals.auth as AuthLocals;
  if (auth?.role === 'RIDER') {
    const isRiderPath = req.path.startsWith('/rider/');
    if (!isRiderPath) {
      return sendError(res, 403, 'FORBIDDEN', 'Your account does not have permission to do this.');
    }
  }
  return next();
});
```

All other existing routers (`/products`, `/sales`, etc.) are unaffected — `requireRole` rejects RIDER implicitly because RIDER is not in any of their allowed role lists.

---

### 5. Auth Router Updates (`apps/shop-api/src/modules/auth/auth.router.ts`)

Two schema additions only — no logic changes:

```typescript
const StaffCreateSchema = z.object({
  // ...existing fields...
  role: z.enum(['SUPER_ADMIN', 'OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK', 'RIDER']),
});

const StaffUpdateSchema = z.object({
  // ...existing fields...
  role: z.enum(['SUPER_ADMIN', 'OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK', 'RIDER']).optional(),
  // ...
});
```

---

### 6. Flutter Web POS — Delivery Tab (`apps/shop_pos`)

#### 6a. `_accessibleTabs` change in `main.dart`

Add index 8 for CASHIER, MANAGER, OWNER, SUPER_ADMIN; exclude for STOCK_CLERK:

```dart
Set<int> _accessibleTabs(PosUser? user) {
  if (user == null) return const <int>{};
  return switch (user.role) {
    PosUserRole.superAdmin => const <int>{0, 1, 2, 3, 4, 5, 6, 7, 8},
    PosUserRole.owner      => const <int>{0, 1, 2, 3, 4, 5, 6, 7, 8},
    PosUserRole.manager    => const <int>{0, 1, 2, 3, 4, 5, 7, 8},
    PosUserRole.cashier    => const <int>{0, 1, 4, 8},
    PosUserRole.stockClerk => const <int>{2, 7},
  };
}
```

Clamp in `initState` updates from `0..7` to `0..8`.

#### 6b. `views` list in `build()`

Append the new `DeliveryView` at index 8:

```dart
final views = [
  _PosTerminalView(state: widget.state, onOpenSync: ...),
  SalesHistoryView(state: widget.state),
  InventoryView(state: widget.state),
  CustomersView(state: widget.state),
  CashDrawerView(state: widget.state),
  ReportsView(state: widget.state),
  SettingsView(state: widget.state),
  PurchaseOrdersView(state: widget.state),
  DeliveryView(state: widget.state),   // ← index 8
];
```

#### 6c. Navigation items

In `_NavigationSidebar._build()`, add to the nav items list (after tab 7 / Orders):

```dart
(tab: 8, icon: AppIcons.shipping, label: 'Delivery'),
```

`AppIcons.shipping` (`LucideIcons.truck`) is already defined — no new icon needed.

In `_MobileBottomNav`, tab 8 is accessible via the "More" sheet (the primary mobile tabs stay as indices 0–3).

#### 6d. `DeliveryView` widget (`apps/shop_pos/lib/views/delivery_view.dart`)

Structure:

```
DeliveryView
├── TabBar: [Orders (CASHIER+) | Riders (MANAGER+) | Config (MANAGER+)]
├── _DeliveryOrdersTab
│   ├── Row: [search / filter by status] + [+ New Delivery button]
│   ├── _DeliveryOrderList (paginated)
│   └── _CreateDeliveryOrderDialog
│       ├── Fields: recipientName, recipientPhone, deliveryAddress, distanceKm
│       ├── Pre-submit: call GET /delivery/config → show computed fee to cashier
│       └── Confirm: POST /delivery/orders
├── _RidersTab (MANAGER+)
│   ├── Rider list with pending earnings balance
│   ├── Per-rider: Assign to pending order / view ledger / initiate payout
│   └── _InitiatePayoutDialog: amount, mpesaPhone
└── _DeliveryConfigTab (MANAGER+)
    ├── Base fee input
    └── Per-km top-up input
```

Status chips use the existing `AppColors` tokens:

| Status      | Color                        |
|-------------|------------------------------|
| PENDING     | `AppColors.status_warning`   |
| ASSIGNED    | `AppColors.status_info`      |
| IN_TRANSIT  | `AppColors.accent_primary`   |
| DELIVERED   | `AppColors.status_success`   |
| FAILED      | `AppColors.status_danger`    |
| CANCELLED   | `AppColors.text_tertiary`    |

#### 6e. `ApiService` additions (`apps/shop_pos/lib/services/api_service.dart`)

New methods following the existing pattern:

```dart
Future<Map<String, dynamic>?> getDeliveryConfig();
Future<bool> updateDeliveryConfig(double baseFee, double distanceTopupRate);
Future<Map<String, dynamic>?> createDeliveryOrder(Map<String, dynamic> payload);
Future<List<Map<String, dynamic>>?> getDeliveryOrders({String? status, int page = 1});
Future<Map<String, dynamic>?> getDeliveryOrder(String id);
Future<Map<String, dynamic>?> assignRider(String orderId, String riderId);
Future<Map<String, dynamic>?> updateDeliveryStatus(String orderId, String status, {String? failureReason});
Future<bool> cancelDeliveryOrder(String orderId, String reason);
Future<List<Map<String, dynamic>>?> getRiders();
Future<List<Map<String, dynamic>>?> getRiderLedger(String riderId, {int page = 1});
Future<bool> initiateRiderPayout(String riderId, double amount, String mpesaPhone);
```

---

### 7. Rider Dashboard (`apps/shop_pos`)

There is no separate rider application. The existing `apps/shop_pos` Flutter app serves both the full POS and the Rider Dashboard. Role-based routing is applied immediately after login.

#### 7a. Post-login routing in `main.dart`

After a successful `POST /auth/login`, the app decodes the JWT and checks the role. The routing fork sits at the point where `MainShell` would normally be pushed:

```dart
// In main.dart (or pos_state.dart), after authentication succeeds:
if (currentLoggedInUser.role == PosUserRole.rider) {
  // Render the Rider Dashboard — no sidebar, no POS tabs
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => RiderHomeView(state: posState)),
    (_) => false,
  );
} else {
  // Render the full POS as before
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => MainShell(state: posState)),
    (_) => false,
  );
}
```

`RIDER` is added to the `PosUserRole` enum and all related switches (`roleDisplay`, `rolePermissions`, color token, `toJson`/`fromApi`, `_accessibleTabs`). Because `RIDER` never reaches `_accessibleTabs` (the `MainShell` is never mounted for a rider), the accessible-tabs switch can return an empty set for that role.

#### 7b. `RiderHomeView` (`apps/shop_pos/lib/views/rider_home_view.dart`)

A top-level widget — no `Scaffold` sidebar, no tab bar shared with the POS. Structure:

```
RiderHomeView
├── AppBar: "Rider Dashboard" + logout button
├── Earnings banner (top)
│   ├── GET /delivery/rider/earnings → display pendingBalance formatted as KES
│   └── Tapping opens scrollable ledger history
└── Active orders list
    ├── GET /delivery/rider/orders (ASSIGNED, IN_TRANSIT)
    ├── Cards: status chip, recipient name/phone, delivery address, delivery fee
    └── Tapping a card navigates to RiderOrderDetailView
```

#### 7c. `RiderOrderDetailView` (`apps/shop_pos/lib/views/rider_order_detail_view.dart`)

Shows full order information. Two action buttons:

| Current Status | Button      | Calls                                              |
|----------------|-------------|-----------------------------------------------------|
| ASSIGNED       | "Pick Up"   | `PATCH /delivery/orders/:id/status` → `IN_TRANSIT` |
| IN_TRANSIT     | "Delivered" | `PATCH /delivery/orders/:id/status` → `DELIVERED`  |

All calls use the rider's JWT, which is already held in the shared `PosState` / `SharedPreferences` store — no new secure storage library is needed.

On HTTP 401 the existing `ApiService` logout callback clears the token and returns the user to the login screen, which is identical to the existing POS behaviour.

#### 7d. Rider-scoped API methods in `api_service.dart`

Two new methods added to the existing `apps/shop_pos/lib/services/api_service.dart`, following the same pattern as other methods:

```dart
Future<Map<String, dynamic>?> getRiderOrders();
Future<Map<String, dynamic>?> getRiderEarnings();
```

Both attach `Authorization: Bearer <token>` via the existing header helper; both call the rider-scoped Shop API endpoints (`GET /delivery/rider/orders` and `GET /delivery/rider/earnings`).

No new `flutter_secure_storage` or `http` dependency is required — `apps/shop_pos` already has both.

---

## Data Flow Diagrams

### Delivery Order Creation (POS → API → DB)

```
Cashier (POS)
  → POST /delivery/orders { saleId?, recipientName, recipientPhone, deliveryAddress, distanceKm }
    → read business_settings delivery.base_fee, delivery.distance_topup_rate
    → deliveryFee = baseFee + distanceKm × topupRate   [Decimal arithmetic]
    → tx: INSERT delivery_orders (status=PENDING, snapshotted fees)
    → tx: if saleId → UPDATE sales.total += deliveryFee
               INSERT sale_payments (note='DELIVERY_FEE')
    → tx: INSERT audit_logs (entityType='DELIVERY_ORDER', action='CREATE')
  ← 201 { deliveryOrder }
```

### Order DELIVERED → Rider Ledger Credit

```
Manager (POS)
  → PATCH /delivery/orders/:id/status { status: "DELIVERED" }
    → validate transition IN_TRANSIT → DELIVERED
    → tx: UPDATE delivery_orders SET status=DELIVERED, deliveredAt=now()
    → tx: read last RiderLedger entry balance for this rider
    → tx: INSERT rider_ledger (entryType=CREDIT, amount=deliveryFee,
              balance=prevBalance+deliveryFee, entityType=DELIVERY, entityId=orderId)
    → tx: INSERT audit_logs
  ← 200 { deliveryOrder }
```

### M-Pesa Payout Flow

```
Manager (POS)
  → POST /delivery/riders/:riderId/payout { amount, mpesaPhone }
    → validate amount ≤ availableBalance
    → call Daraja B2C API → returns checkoutRequestId
    → tx: INSERT rider_payouts (status=PENDING, checkoutRequestId)
    → tx: INSERT rider_ledger (entryType=DEBIT, amount, balance=prevBalance-amount,
              entityType=DELIVERY, entityId=payoutId)
  ← 201 { payout }

Daraja (async callback)
  → POST /delivery/mpesa/b2c-callback
    → verify Daraja signature
    → if success:
        UPDATE rider_payouts SET status=SUCCESS, settledAt, mpesaReceipt
    → if failure:
        UPDATE rider_payouts SET status=FAILED
        INSERT rider_ledger (entryType=CREDIT, amount, balance=prevBalance+amount)
              [reversing entry]
```

---

## Error Codes Reference

| HTTP | Code                  | Trigger                                              |
|------|-----------------------|------------------------------------------------------|
| 400  | `VALIDATION_ERROR`    | Zod schema failure                                   |
| 400  | `INVALID_PHONE`       | Phone number fails Kenyan normalisation              |
| 403  | `FORBIDDEN`           | Role not permitted on this route                     |
| 403  | `PIN_CHANGE_REQUIRED` | `mustChangePin = true` (existing behaviour)          |
| 404  | `NOT_FOUND`           | Order or rider not found                             |
| 422  | `INVALID_RIDER`       | Assigned user is not an active RIDER                 |
| 422  | `INVALID_TRANSITION`  | Status transition violates state machine             |
| 422  | `INSUFFICIENT_BALANCE`| Payout amount exceeds rider's available balance      |

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Delivery fee arithmetic

*For any* non-negative `baseFee`, non-negative `distanceKm`, and non-negative `topupRate`, the computed `deliveryFee` stored on the `DeliveryOrder` SHALL equal `baseFee + distanceKm × topupRate` using `Decimal` (non-floating-point) arithmetic.

**Validates: Requirements 4.1**

---

### Property 2: Fee snapshot immutability

*For any* delivery order, changing `delivery.base_fee` or `delivery.distance_topup_rate` in `business_settings` after the order was created SHALL NOT alter the order's `baseFee`, `topupRate`, or `deliveryFee` fields.

**Validates: Requirements 3.4**

---

### Property 3: Delivery config round-trip

*For any* valid `(baseFee ≥ 0, distanceTopupRate ≥ 0)` pair, calling `PUT /delivery/config` followed immediately by `GET /delivery/config` SHALL return exactly the same `baseFee` and `distanceTopupRate` values.

**Validates: Requirements 3.2**

---

### Property 4: Negative config rejected

*For any* `baseFee < 0` or `distanceTopupRate < 0`, `PUT /delivery/config` SHALL return HTTP 400 `VALIDATION_ERROR`.

**Validates: Requirements 3.3**

---

### Property 5: Delivered order triggers rider ledger credit

*For any* delivery order that transitions to `DELIVERED`, exactly one `RiderLedger` entry of `entryType = CREDIT` with `amount = deliveryFee` and `entityType = DELIVERY` referencing that order SHALL be created in the same database transaction.

**Validates: Requirements 4.8**

---

### Property 6: RiderLedger is append-only

*For any* existing `RiderLedger` row, any attempt to `UPDATE` or `DELETE` that row SHALL raise a database-level exception (`restrict_violation`) and leave the row unchanged.

**Validates: Requirements 1.5, 1.7**

---

### Property 7: Running balance correctness

*For any* sequence of `RiderLedger` entries for a given rider, the `balance` field of each entry SHALL equal the algebraic sum of all preceding entries' `amount` values (credits positive, debits negative), plus the current entry's signed amount.

**Validates: Requirements 5.1, 5.3**

---

### Property 8: Payout reversal on M-Pesa failure

*For any* `RiderPayout` that receives a failure callback, a new `RiderLedger` CREDIT entry of the exact same `amount` SHALL be created, restoring the rider's balance to its pre-payout value.

**Validates: Requirements 5.5**

---

### Property 9: Insufficient balance rejected

*For any* payout request where `amount > availableBalance`, `POST /delivery/riders/:riderId/payout` SHALL return HTTP 422 `INSUFFICIENT_BALANCE` and neither a `RiderPayout` record nor a `RiderLedger` debit entry SHALL be created.

**Validates: Requirements 5.6**

---

### Property 10: Illegal delivery status transitions rejected

*For any* `(currentStatus, requestedStatus)` pair not in the set `{(ASSIGNED, IN_TRANSIT), (ASSIGNED, FAILED), (IN_TRANSIT, DELIVERED), (IN_TRANSIT, FAILED)}`, `PATCH /delivery/orders/:id/status` SHALL return HTTP 422 `INVALID_TRANSITION` and leave the order's status unchanged.

**Validates: Requirements 4.7, 4.10**

---

### Property 11: RIDER JWT restricted to rider-scoped routes

*For any* request bearing a valid RIDER-role JWT to any route outside `/auth/*` and `/delivery/rider/*`, the Shop API SHALL return HTTP 403 `FORBIDDEN`.

**Validates: Requirements 2.3, 8.3**

---

### Property 12: RIDER JWT login claims

*For any* active user with `role = RIDER`, a successful `POST /auth/login` SHALL return a JWT whose decoded payload contains `sub = userId`, `role = "RIDER"`, and `name = fullName`, with an expiry no more than 8 hours from issuance.

**Validates: Requirements 2.1**

---

### Property 13: Rider order isolation

*For any* authenticated rider calling `GET /delivery/rider/orders`, the returned orders SHALL contain only orders where `riderId` matches the JWT `sub` claim (as validated server-side from the database), and SHALL NOT include orders belonging to any other rider.

**Validates: Requirements 7.5, 7.11, 8.3**

---

### Property 14: Payout role restriction

*For any* request to `POST /delivery/riders/:riderId/payout` made with a JWT whose `role` is `CASHIER`, `STOCK_CLERK`, or `RIDER`, the Shop API SHALL return HTTP 403 `FORBIDDEN` before executing any business logic.

**Validates: Requirements 8.1**

---

### Property 15: Order list ordering

*For any* set of delivery orders for a business, `GET /delivery/orders` SHALL return them ordered by `createdAt` descending — i.e., for any two adjacent entries in the result, the first entry's `createdAt` SHALL be ≥ the second's.

**Validates: Requirements 4.3**

---

### Property 16: Delivery audit trail completeness

*For any* `DeliveryOrder` creation, status update, assignment, or cancellation, exactly one new `AuditLog` entry with `entityType = 'DELIVERY_ORDER'` and the corresponding `entityId` SHALL be created in the same transaction.

**Validates: Requirements 4.11**

---

### Property 17: Invalid rider assignment rejected

*For any* `riderId` that does not resolve to an active `User` with `role = RIDER`, `PATCH /delivery/orders/:id/assign` SHALL return HTTP 422 `INVALID_RIDER` and leave the order's status and `riderId` unchanged.

**Validates: Requirements 4.6**

---

### Property 18: Login updates lastLoginAt

*For any* rider (or any user) that successfully authenticates via `POST /auth/login`, the `User.lastLoginAt` field in the database SHALL be updated to a timestamp within the same second as the login response.

**Validates: Requirements 2.6**
