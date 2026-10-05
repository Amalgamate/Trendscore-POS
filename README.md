# Retail OS

A fintech-grade Retail Operating System for Kenyan general shops.
POS, inventory, credit, M-Pesa, cash control and reporting — one isolated
stack per shop.

> **Simple to sell. Hard to lose track of.**

---

## Status: Phase 0 complete

Foundations only. No POS screens yet. What exists is the part that is
expensive to get wrong later.

| Area | State |
|---|---|
| Monorepo skeleton | Done |
| Design tokens (TS + Dart from one source) | Done, generated, tested |
| Control-plane schema (accounts, plans, billing, instances) | Valid |
| Shop-instance schema (sales, stock, credit, cash, audit) | Valid |
| Migrations | Applied to real Postgres 15 |
| Ledger immutability | **Enforced by DB triggers, verified** |
| Payment abstraction + M-Pesa state machine | 30 tests passing |
| Health endpoint | 5 tests passing |
| Flutter design tokens | 9 tests passing |
| CI (verify + publish images) | Written |
| Daraja integration | Deferred — adapter + fake only |

**Verified, not assumed.** Every claim above was executed:

```
payment-provider    30 tests passing, tsc clean
shop-api             5 tests passing, tsc clean
shop_pos             9 tests passing, flutter analyze clean
shop_instance db    2 migrations applied to Postgres 15
immutability        8 tamper attempts blocked, appends still work
```

---

## Architecture

```
            MARKETING SITE (Next.js — SEO matters here)
                          │
                          ▼
                  CONTROL PLANE API
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 ▼                  ▼
   Accounts/Auth    Billing (M-Pesa)    Provisioning
   Subscriptions    Reconciliation      (Phase 1)
        │                 │                  │
        └─────────► Instance Registry ◄──────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
     SHOP A             SHOP B            SHOP C
   ┌──────────┐      ┌──────────┐      ┌──────────┐
   │ shop_pos │      │ shop_pos │      │ shop_pos │  Flutter (desktop/tablet)
   │ shop-api │      │ shop-api │      │ shop-api │
   │ Postgres │      │ Postgres │      │ Postgres │  one database each
   │ Redis    │      │ Redis    │      │ Redis    │
   └──────────┘      └──────────┘      └──────────┘
```

**One business = one instance = one database.** See
[ADR-0001](docs/adr/0001-isolation.md) for why, the density wall at 50–300
shops, and the seam that keeps migration possible.

**A shop instance never calls the control plane on the POS hot path.**
Entitlement is pushed down and cached. If billing is down, shops keep
trading. See [ADR-0002](docs/adr/0002-mpesa-async.md).

---

## Repository layout

```
apps/
  control-plane-api/   accounts, plans, subscriptions, invoices,
                       payments, instances, provisioning, health
  shop-api/            one deployment per shop; business data only
  shop_pos/            Flutter POS (Windows desktop + Android)
  web/                 marketing site + control-plane admin (Phase 2)
packages/
  design-tokens/       tokens.json -> TS + CSS + Dart
  payment-provider/    PaymentProvider abstraction, M-Pesa state machine
infra/
  provisioning/        instance templates (Phase 1)
docs/adr/              architecture decision records
```

---

## Key decisions

### Money is never a float

`NUMERIC(14,2)` everywhere, enforced at the database level by migration
`0001_immutable_ledgers`. That migration fails loudly if any financial
column is ever changed to a float type.

### Financial records are append-only, enforced by the database

Application discipline is not enough — one careless `UPDATE` would corrupt
a shop's history with no trace. Triggers reject `UPDATE`/`DELETE` on
`customer_ledger`, `stock_movements`, `audit_logs`, `cash_movements` and
`sale_payments`.

Corrections happen through **reversing entries**, never mutation. The
audit trail shows the original decision and the correction.

Run `apps/shop-api/prisma/verify-immutability.sql` to prove it. It attempts
eight tampering operations and asserts each is rejected.

### M-Pesa TIMEOUT is not FAILED

This is the bug that costs real money. A customer who does not enter their
PIN causes a timeout — **and the payment can still settle later.** Treating
timeout as failure means handing over goods for money that arrives
afterwards, or refusing a customer who genuinely paid.

`UNKNOWN` and `TIMEOUT` are non-terminal and reconciled for 24 hours.
Idempotency keys are `UNIQUE` in the database, so a replayed Daraja
callback cannot double-credit a sale.

Safaricom is not required to develop against this system —
`FakeMpesaProvider` reproduces every failure mode deterministically,
including the dangerous late-settlement path.

### Design tokens have one source

`tokens.json` emits TypeScript (marketing site), CSS custom properties, and
Dart (POS). The POS copy is committed because Dart cannot resolve a
TypeScript source at runtime; CI fails if it drifts.

Money is always rendered with two decimals and tabular figures, in both
TypeScript and Dart, with tests.

---

## Local development

```bash
npm install
npm run build:tokens      # emits TS + CSS + Dart
npm test                  # 35 Node tests
```

### Database

```bash
docker run -d --name retailos_test \
  -e POSTGRES_PASSWORD=testpass -e POSTGRES_DB=shop_instance \
  -p 55432:5432 postgres:16-alpine

cd apps/shop-api && ./migrate-test.cmd
```

`migrate-test.cmd` resets the schema, applies every migration, and runs the
immutability verification. It is the Phase 0 gate.

### Flutter

```bash
cd apps/shop_pos
flutter test
flutter analyze
```

---

## Roadmap

| Phase | Gate |
|---|---|
| **0** Foundations | ✅ Done |
| **1** Provisioning, proven by hand first | 10 consecutive instances, zero manual steps; backup restore succeeds |
| **2** Onboarding funnel | Website → sellable shop in <10 min, unattended |
| **3** POS core | 200 cash + 50 M-Pesa sales, zero reconciliation drift |
| **4** Inventory & purchasing | Every SKU reconstructible from the movement ledger |
| **5** Credit & customers | Every balance equals the sum of its ledger |
| **6** Expenses, cash control, admin | Cash variance always attributable |
| **7** Reporting | — |
| **8** Offline | Full trading day disconnected; zero duplicate or lost sales |
| **9** Hardening | eTIMS evaluation, load test, penetration pass |

---

## Open items

- **Daraja credentials.** Sandbox and production pending. Adapter and fake
  exist; Phases 0–2 are fully unblocked without it.
- **Card payments.** Deliberately excluded from v1. Removing it means every
  sale is cash or settled into our own account — no third-party money in
  flight. A `CardProvider` drops in later without touching the POS.
- **eTIMS.** Deferred. Worth an early feasibility check; VAT-registered
  shops are a core segment.
