# ADR-0001: One shop = one instance = one database

- **Status:** Accepted
- **Date:** 2026-10-05
- **Supersedes:** nothing

## Context

We are building a multi-tenant SaaS POS for Kenyan retail. The obvious
design is a single database with a `shop_id` column on every table. That
was rejected. The alternative — a fully isolated stack per shop — is what
we committed to.

## Decision

**One business = one POS instance = one PostgreSQL database.**

The control plane (`apps/control-plane-api`) manages accounts, plans,
subscriptions, invoices, payments, instance provisioning and health. It
**never** stores shop business data. There is no `shop_id` foreign key
into a shared transaction table anywhere in the control plane.

Each shop runs `apps/shop-api` against its own PostgreSQL database.

```
Control Plane DB                Shop A DB      Shop B DB
├── accounts                    ├── products   ├── products
├── businesses                  ├── sales      ├── sales
├── subscriptions               ├── customers  ├── customers
├── invoices                    ├── ledger     ├── ledger
├── payments                    └── audit      └── audit
└── instances  ──provisions──►
```

## Why

1. **Blast radius.** A bug or a bad migration in one shop's data cannot
   touch another shop's money. For a product whose entire pitch is "your
   financial data is safe", this is the property that makes the pitch true.
2. **Compliance and trust.** We can answer "where is shop X's data, and who
   can reach it" without a row-level security audit. Physical separation
   is a stronger answer than a policy.
3. **The credit ledger is the product.** Once a shop's customer ledger can
   be silently altered by any tenant, we cannot honestly sell financial
   trust.

## Consequences

### Accepted costs

- **No cross-shop aggregate query.** "All shops on the platform" analytics
  run in the control plane over billing data only. We never JOIN business
  data across shops, by design.
- **Operational overhead per shop.** Each instance needs its own migration,
  backup and health check. This is why provisioning is automated and
  observable from day one.
- **Density.** One Postgres container per shop costs roughly 350-500MB RSS.
  An 8GB host holds ~10-12 shops.

### The density wall (known, planned, not solved today)

The per-shop container does not scale indefinitely. Planned tiers:

| Shop count | Topology | Isolation |
|---|---|---|
| 0-50 | Dedicated Postgres container per shop | Process-level |
| 50-300 | One Postgres **cluster** per host, one **database** per shop | Data-level (separate DBs, separate roles, no cross-DB joins) |
| 300+ | Managed per-shop databases, or shared cluster + RLS | Depends on provider |

Postgres natively supports many databases per cluster, so the 50-300 tier
gains roughly 12x density while keeping **data** isolation intact. Only the
process is shared.

**The rule that makes this migration possible: shop code must never know
which tier it runs on.** All database access goes through a single module
boundary. If feature code issues raw SQL against a connection string, we
lose the ability to migrate and this decision quietly becomes permanent.

## Alternatives rejected

- **Shared database, `shop_id` column.** Cheapest to operate, easiest
  cross-tenant analytics. Rejected: a single missing `WHERE shop_id` leaks
  one shop's customers to another, and the blast radius of any bug spans
  every customer.
- **Shared database, row-level security.** Better, but RLS is famously
  easy to get subtly wrong, and a mistake is invisible until it isn't.
  Rejected for v1; reconsider at 300+ shops if the dedicated-cluster tier
  proves too expensive.
- **Per-shop schema, shared cluster.** Rejected: schema-per-shop is the
  same isolation argument as shared-database with weaker guarantees and a
  worse migration story than separate databases.
