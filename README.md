# Retail OS

A fintech-grade Retail Operating System for Kenyan general shops.
POS, inventory, credit, M-Pesa, cash control, delivery and an online
storefront — one isolated stack per shop.

> **Simple to sell. Hard to lose track of.**

The product is branded **ShopSmart** (see [PRODUCT.md](PRODUCT.md)); the
repository and infrastructure are named Retail OS.

---

## Status: audited 2026-10-12

Every claim below was executed on this branch (`cline/a2e41`, merged with
`origin/main`) and the results are reported as they actually came out —
including the failures.

| Area | State | Evidence |
|---|---|---|
| Monorepo, workspaces, CI | Working | `npm run typecheck` clean across 4 workspaces |
| Design tokens (TS + CSS + Dart from one source) | Working, no drift | `npm run build:tokens`, committed files unchanged |
| Control-plane schema (accounts, plans, billing, instances) | Valid | `prisma validate` passes |
| Shop-instance schema (sales, stock, credit, cash, delivery, storefront) | Valid | `prisma validate` passes |
| Migrations | **14/14 apply to a fresh Postgres 15** | Verified on a scratch database |
| Ledger immutability | **Enforced by DB triggers, verified** | `verify-immutability.sql`: "All immutability checks passed." |
| Payment abstraction + M-Pesa state machine | 30 tests passing | `packages/payment-provider` |
| Control-plane provisioning engine + CLI | 55 tests passing | `apps/control-plane-api` |
| Shop API (sales, pricing, storefront orders, M-Pesa, delivery) | 63 tests passing | `apps/shop-api` |
| Storefront (Next.js) tests | 1 passing | `apps/web` |
| Storefront lint (no gradients / no hard-coded colours) | **FAILING** — 2 gradients in `app/globals.css` | `npm run lint -w @retail-os/storefront` |
| Flutter POS tests | **47 passing, 6 failing** | `flutter test` (details in Known issues) |
| Flutter analyzer | **111 issues, 32 errors** — all in two orphaned files | `dart analyze lib` |
| CI (verify + publish images) | Working | verify → publish `shop-api`, `shop-pos`, `shop-web` to GHCR |
| Production deployment | Live | Nginx + Let's Encrypt on `www.gutagala.trendscore.co.ke` and `webshop.trendscore.co.ke` |
| Daraja integration | Adapter implemented server-side | `/payments/mpesa` with encrypted credential store; credentials still to be configured |
| Card payments | Deliberately excluded from v1 | `PaymentMethod` enum has no CARD |

**Verified, not assumed.** Commands actually run:

```
npm ci                                  OK
npm run build:tokens                    OK, no committed drift
npm run db:generate:control + shop      OK
npm run typecheck                       4/4 workspaces clean
npm test                                148 passing (30 + 55 + 63)
npm run plan:check                      ✓ dashboard matches checkboxes (14/224)
npm test -w @retail-os/storefront       1 passing
npm run lint -w @retail-os/storefront   ✗ 2 gradient usages found
prisma migrate deploy (fresh DB)        14/14 applied
psql verify-immutability.sql            All immutability checks passed
flutter test                            47 passed, 6 failed
dart analyze lib                        111 issues (32 errors, 3 warnings, 76 infos)
flutter build web                       ✓ Built build/web
```

---

## Live deployment

Two production hostnames are served by the same host
(`185.127.16.124`) from immutable `ghcr.io/amalgamate/*` image tags:

| Hostname | What runs there |
|---|---|
| `www.gutagala.trendscore.co.ke` | Flutter POS (web) + shop API |
| `webshop.trendscore.co.ke` (+ `www`) | Next.js storefront, `/api` proxied to the shop API |

Deploys run from `.github/workflows/deploy-pos.yml` after a green CI on
`main` (or manually via `workflow_dispatch`, which can also reset the
production super-admin PIN). The workflow verifies DNS first, transfers the
super-admin seed credentials as a short-lived protected file, provisions
Nginx + Let's Encrypt, and confirms public HTTPS for every host.
See [docs/SUPER_ADMIN_BOOTSTRAP.md](docs/SUPER_ADMIN_BOOTSTRAP.md).

---

## Architecture

```
        STOREFRONT (Next.js — webshop.trendscore.co.ke)
                    │  /api (server-side proxy)
                    ▼
            SHOP API  ◄──────────────┐
                    │                │
        ┌───────────┼────────────┐   │        one API + one database
        ▼           ▼            ▼   │        per shop instance
   Catalogue    Orders/Pay   Delivery │
   (published)  (M-Pesa)   (riders)  │
        │           │            │   │
        └────► SHOP DATABASE ◄────┘   │
                                      │
   CONTROL PLANE API                  │
   accounts, plans, billing,          │
   instance registry, provisioning ───┘
   (provisioning engine + CLI today; HTTP API not yet built)

   POS (Flutter) ──► SHOP API  (web, Windows desktop, Android)
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
  control-plane-api/   provisioning engine + CLI; Prisma schema for accounts,
                       plans, billing, instances, hosts, deployments, health
                       (the HTTP API itself is not built yet — `src/index.ts`
                       does not exist; only the provisioning tests run)
  shop-api/            one deployment per shop; business data only
  shop_pos/            Flutter POS — web (production), Windows desktop, Android
  web/                 Next.js storefront (ShopSmart) — catalog, cart,
                       checkout with M-Pesa; own Dockerfile
packages/
  design-tokens/       tokens.json -> TS + CSS + Dart (single source)
  payment-provider/    PaymentProvider abstraction, M-Pesa state machine,
                       fake providers for tests
  brand-assets/        shared ShopSmart artwork
docs/
  adr/                 architecture decision records
  storefront/          a11y checklist + Lighthouse baseline template
  ui-uplift/           POS design audit artefacts
  COMMERCE_SCAFFOLD.md storefront / website-builder / social status
  SUPER_ADMIN_BOOTSTRAP.md
scripts/               lint checks (gradients, colours), icon generation,
                       deploy script, plan-progress checker
tools/live-preview.mjs
STOREFRONT_PLAN.md     12-phase storefront uplift plan (self-marking)
UI_UPLIFT_PLAN.md      8-phase POS design uplift plan (self-marking)
PRODUCT.md             product definition and constraints
.kiro/, .agents/       agent spec/scratch folders (not part of the runtime)
```

---

## Applications

### `apps/shop_pos` — the POS (Flutter)

The cashier and manager app. In production it is built for web and served
from the shop's own host; Windows and Android targets are configured.

- **Sells:** product grid → cart → checkout modal (CASH / M-PESA), receipt,
  sale history with reversal, hold/resume
- **Manages:** inventory + product editor (images, variants, publication),
  categories, customers + credit ledger, suppliers, purchase orders,
  cash drawer (shifts, moves, variance), reports, staff accounts & roles
- **Operates:** delivery orders + rider assignment, rider dashboard
  (role-gated), storefront orders inbox, M-Pesa integration screen
  (credentials, reconciliation), Website Builder (industry, launch
  checklist, publishing), Social Commerce prerequisites
- **Roles:** `SUPER_ADMIN`, `OWNER`, `MANAGER`, `CASHIER`, `STOCK_CLERK`,
  `RIDER` — tabs are gated by server-validated role data; riders get a
  dedicated dashboard and no POS tabs
- **Design:** generated `lib/theme/tokens.dart` from `packages/design-tokens`
  (never hand-edit), light/dark `AppPalette`, Lucide icons behind a
  generated `AppIcons` layer

### `apps/shop-api` — the shop instance API (Express + Prisma)

One container + one PostgreSQL database per shop. Mounted routes:

| Route | Purpose |
|---|---|
| `GET /health` | version, uptime, dependency checks |
| `/auth` | phone + PIN login, JWT, forced PIN change, role from DB |
| `/products` | catalogue, images, variants, web-shop publication, **public** `GET /products/storefront` |
| `/categories` | categories |
| `/customers` | customers, credit limits, ledger, archive |
| `/sales` | server-priced sales (the client cannot set totals), reversals |
| `/suppliers` | suppliers + archive |
| `/business` | shop profile, staff users, settings |
| `/delivery` | delivery orders, riders (incl. rider-scoped endpoints), location sharing |
| `/storefront/orders` | public checkout orders + status polling |
| `/payments/mpesa` | Daraja STK push, status, availability, reconciliation |

Money is `DECIMAL` in the database and `decimal.js` integer cents in the
application. Financial tables are append-only via database triggers
(`prisma/verify-immutability.sql` proves it — eight tamper attempts are
rejected while appends still work). 14 migrations, all verified.

### `apps/control-plane-api` — the control plane

Today this is the **provisioning engine and its CLI**
(`src/cli/provision.ts`) plus the control-plane Prisma schema (accounts,
OTP, businesses, plans, subscriptions, invoices, payments, instances,
hosts, domains, deployments, health checks, backups, audit).
55 tests cover slug generation, validation, compose-template rendering and
step orchestration. The Express HTTP API described in older documents does
not exist yet — `npm run dev` in this workspace fails until `src/index.ts`
is written.

### `apps/web` — the storefront (Next.js 15 / React 19)

Customer-facing shop: home, product pages, cart, checkout (creates orders
via `/storefront/orders` and pays via `/payments/mpesa` with status
polling), policies page, WhatsApp link. Dev mode proxies `/api` to
`shop-api`; in production Nginx does. Ships its own `Dockerfile`
(published as `shop-web`). Sample products appear **only** when the API is
unreachable and are labelled as such; store policies are never invented.

---

## Key decisions

### Money is never a float

`DECIMAL` columns, `decimal.js` integer cents in the API, integer minor
units in Dart. The build fails loudly if a financial column is ever changed
to a float type (see `apps/shop-api/test/pricing.test.ts`).

### Financial records are append-only, enforced by the database

Application discipline is not enough — one careless `UPDATE` would corrupt
a shop's history with no trace. Triggers reject `UPDATE`/`DELETE` on
`customer_ledger`, `stock_movements`, `audit_logs`, `cash_movements` and
`sale_payments`. Corrections happen through **reversing entries**, never
mutation. Run `apps/shop-api/prisma/verify-immutability.sql` to prove it —
it attempts eight tampering operations and asserts each is rejected.

### M-Pesa TIMEOUT is not FAILED

A customer who does not enter their PIN causes a timeout — **and the
payment can still settle later.** Treating timeout as failure means
handing over goods for money that arrives afterwards, or refusing a
customer who genuinely paid. `UNKNOWN` and `TIMEOUT` are non-terminal and
reconciled for 24 hours; idempotency keys are `UNIQUE` in the database, so
a replayed Daraja callback cannot double-credit a sale.

The shop API ships a real `DarajaMpesaAdapter` (STK push, status query,
callback handling) with an AES-256-GCM encrypted credential store, while
`packages/payment-provider` keeps deterministic fake providers that
reproduce every failure mode — including the dangerous late-settlement
path — so development never needs Safaricom. See
[ADR-0002](docs/adr/0002-mpesa-async.md).

### Design tokens have one source

`tokens.json` emits TypeScript (storefront), CSS custom properties, and
Dart (POS). The POS copy is committed because Dart cannot resolve a
TypeScript source at runtime. Never hand-edit
`apps/shop_pos/lib/theme/tokens.dart`; change `tokens.json` or
`packages/design-tokens/build.mjs`. Money is always rendered with two
decimals and tabular figures, in both TypeScript and Dart.

---

## Local development

Prerequisites: **Node 20+** (verified on Node 26 / npm 11), **Flutter 3.38.x**
(Dart ^3.10.1), **Docker**.

### JavaScript workspace

```bash
npm ci
npm run build:tokens        # emits TS + CSS + Dart from tokens.json
npm run db:generate:control # both Prisma clients must be generated
npm run db:generate:shop    # before typecheck/test — CI does the same
npm run typecheck           # 4 workspaces
npm test                    # 148 Node tests
npm run plan:check          # STOREFRONT_PLAN dashboard vs checkboxes
```

### Database

For a throwaway verification database (exactly what CI runs):

```bash
docker run -d --name retailos_test \
  -e POSTGRES_PASSWORD=testpass -e POSTGRES_DB=shop_instance \
  -p 55432:5432 postgres:15-alpine

cd apps/shop-api
DATABASE_URL=postgresql://postgres:testpass@127.0.0.1:55432/shop_instance \
DIRECT_URL=$DATABASE_URL npx prisma migrate deploy
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f prisma/verify-immutability.sql
```

For day-to-day local work see
[apps/shop-api/LOCAL_DEVELOPMENT.md](apps/shop-api/LOCAL_DEVELOPMENT.md) —
it describes the active `retailos_test` container (port 55432),
`.env.local`, and the POS preview that proxies `/api` to the API on port
4001. Never run migrations against a database you care about without
checking `prisma migrate status` first; the old `migrate-test.cmd` (now
gitignored) dropped and recreated the schema.

### Flutter POS

```bash
cd apps/shop_pos
flutter pub get
flutter test        # see Known issues — 6 tests currently fail
dart analyze lib    # see Known issues — 32 errors in orphaned files
flutter build web   # verified passing
```

### Storefront

```bash
npm run dev  -w @retail-os/storefront   # http://localhost:3000
npm test    -w @retail-os/storefront
npm run lint -w @retail-os/storefront   # currently failing — see Known issues
```

---

## CI and deployment

`.github/workflows/ci.yml`

1. **Verify** (every push/PR): `npm ci` → generate both Prisma clients →
   build tokens → `npm run typecheck` → `npm test` → validate both Prisma
   schemas → deploy shop migrations to a Postgres 16 service and run
   `verify-immutability.sql`.
2. **Publish** (after verify; pushes only from `main`, PRs build without
   pushing): immutable images `shop-api`, `shop-pos`, `shop-web` to
   `ghcr.io/amalgamate/*`, tagged with the version and `sha-<commit>`.

`.github/workflows/deploy-pos.yml` — triggered by a green CI on `main` or
manually: verifies DNS for every hostname, configures SSH, transfers
GHCR credentials and the super-admin seed file as short-lived protected
files, runs `scripts/deploy-pos.sh` (containers + Nginx + Let's Encrypt),
then asserts public HTTPS — including
`https://webshop.trendscore.co.ke/api/products/storefront`.
The manual dispatch can optionally reset the production super-admin PIN.

## Plans and progress

Two self-marking checklists drive ongoing work; `npm run plan:check`
verifies their dashboards against their own checkboxes:

| Plan | Tracked progress | Notes |
|---|---|---|
| [STOREFRONT_PLAN.md](STOREFRONT_PLAN.md) | **14 / 224** (Phase 0 done) | The checkboxes lag reality: `main` shipped product publication, the public catalog, cart and M-Pesa checkout *outside* the plan's phase discipline (see `docs/COMMERCE_SCAFFOLD.md`). Treat the plan's Phases 2–5 as partially done and re-baseline before continuing. |
| [UI_UPLIFT_PLAN.md](UI_UPLIFT_PLAN.md) | **32 / 138** (Phase 0 7/10, Phase 1 25/25) | `main` redesigned several views (sidebar, checkout, inventory, delivery, settings) without ticking Phase 2+ boxes; re-baseline before continuing. |

---

## Known issues (from the 2026-10-12 audit)

Nothing below blocks the production images (`flutter build web` passes and
CI is green), but each item is real and was reproduced:

1. **`flutter test`: 47 passed, 6 failed.**
   - `session_persistence_test.dart` does not compile — it expects
     `PosState.sessionExpiresAt` / `sessionDurationMinutes`, which do not
     exist (the session feature it tests was removed or never landed).
   - `tokens_test.dart` does not compile — it still calls
     `buildRetailOsTheme()`, which moved from `theme/tokens.dart` to
     `theme/app_theme.dart`.
   - `commerce_scaffold_test.dart` — "website builder exposes industry and
     launch checklist" fails.
   - `widget_test.dart` — 3 failures: checkout affordances assertion, a tap
     on demo product "Fresh milk 500ml" that no longer renders, and a
     product-editor layout overflow on a compact phone size.
2. **`dart analyze lib`: 111 issues (32 errors).** Every error lives in two
   files that are *orphaned* — never imported, so they don't affect the
   build: `views/credit_workspace_view.dart` (31, references `PosState`
   APIs that don't exist) and `views/staff_management_view.dart` (1).
   Also orphaned: `views/app_menu_view.dart`, `views/social_commerce_view.dart`.
   Staff management and customer credit are implemented inline in
   `settings_view.dart` / `customers_view.dart` instead. Delete or finish
   the four orphaned files.
3. **Storefront lint fails.** `check-no-gradients.mjs` finds 2
   `linear-gradient` usages in `apps/web/app/globals.css` (lines 115 and
   1828) — against the storefront plan's "no gradients, anywhere" rule.
4. **`control-plane-api` has no entry point.** `src/index.ts` (referenced
   by `dev`/`build`/`start`) and `prisma/seed.ts` do not exist; only the
   provisioning module and its tests work.
5. **Broken `seed` scripts.** `apps/shop-api`'s `npm run seed` points at
   `prisma/seed.ts`; the real script is `src/scripts/seed.ts`.
6. **No `.env.example`.** `shop-api` needs `DATABASE_URL`, `DIRECT_URL`,
   `BUSINESS_ID` and `JWT_SECRET`; storefront needs
   `NEXT_PUBLIC_STORE_WHATSAPP_NUMBER` etc. — none are documented in-repo
   outside `LOCAL_DEVELOPMENT.md` prose.
7. **Generated Dart is not drift-checked.** CI builds `tokens.json` but no
   longer diffs the committed `apps/shop_pos/lib/theme/tokens.dart`, and
   the `sync:tokens` / `sync:fonts` scripts referenced in UI_UPLIFT_PLAN.md
   don't exist in any `package.json` (only `scripts/sync-fonts.mjs`).
8. **Docs lag code.** `docs/COMMERCE_SCAFFOLD.md` still says checkout
   creates no orders and accepts no payment — the shipped checkout does
   both. `apps/shop_pos/README.md` is still the Flutter template.

## Roadmap

Progress is tracked in [STOREFRONT_PLAN.md](STOREFRONT_PLAN.md) (storefront,
12 phases) and [UI_UPLIFT_PLAN.md](UI_UPLIFT_PLAN.md) (POS, 8 phases).
Current status at audit time:

| Where | Status |
|---|---|
| **Storefront** (STOREFRONT_PLAN) | Phase 0 (baseline, rules, accessibility checklist) done — 14/224 ticks. Product publication, public catalog and checkout already shipped in code ahead of the plan; re-baseline Phases 2–5 before continuing. |
| **POS** (UI_UPLIFT_PLAN) | Phase 0 baseline done; Phase 1 foundations done (tokens, theme split, Lucide icons); the running POS already covers Phases 3–6 functionality (sell, inventory, customers, cash, reports, staff, delivery); design conformance 100% in the shipped views; remaining phases are design-system migration of legacy views. |
| **Provisioning** (Phase 1 of the original plan) | Provisioning engine + CLI + tests complete; rolling out 10-instance runs is the remaining gate. |
| **Offline** (Phase 8) | Not started — only sync diagnostics exist in the POS. |
| **Hardening** (Phase 9) | Not started — eTIMS, load testing and penetration testing pending. |

Original phase gates (POS core milestones): **Phase 3** — 200 cash + 50
M-Pesa sales, zero reconciliation drift (gated by automated reconciliation
tests). **Phase 2** onboarding funnel — website → sellable shop in under 10
minutes, unattended. **Phase 4** inventory — every SKU reconstructible
from the movement ledger.

---

## Open items

- **Safaricom Daraja credentials.** The adapter, encrypted credential
  store and STK-push flows exist server-side; per-shop sandbox/production
  credentials and callback verification are still required.
- **Card payments.** Deliberately excluded from v1 — the `PaymentMethod`
  enum has no CARD, and every sale is cash or settled into our own
  account. A `CardProvider` drops in without touching the POS later.
- **eTIMS.** Deferred. Worth an early feasibility check for VAT-registered
  shops.
- **Social commerce.** First-party OAuth, app review and account
  connections are each platform's responsibility; shops authorise their
  own accounts. Store policy and privacy copy must come from the business.
- **Concerns.** Legal review pending: ODPC registration status, controller
  vs processor roles, consent wording, retention periods. No production
  storefront data has been provided yet.

