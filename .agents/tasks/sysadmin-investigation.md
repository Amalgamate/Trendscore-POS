# System Admin Investigation — Retail POS

**Investigated by:** Kiro AI agent  
**Date:** 2026-05-10  
**Scope:** shop-api, control-plane-api, shop_pos Flutter app, Prisma schemas, CI/CD

---

## Summary Answer

**Yes, there is a system admin feature — but it is a per-shop platform super-admin seeded at provisioning time, not a central cross-shop admin UI or portal.**

The project uses a two-tier admin model:

1. **Per-shop OWNER role** — a standard user role inside each isolated shop database, with full shop management access (staff management, business settings, reports). All shop-API owners are equal; there is no elevated privilege.

2. **`isPlatformSuperAdmin` flag** — a boolean marker on the `User` model in each shop's database. The account still runs as `OWNER` role within that shop, but the flag identifies the Trends CORE / Retail OS operator account. This is seeded once at provisioning and is designed to be the "back-door" account for support/platform operations on a per-shop basis.

There is **no central admin portal, no cross-shop admin API, and no admin UI** (the `web/` app is currently a placeholder — no pages exist in it yet). Admin access to all shops today is operator-level: SSH to the host, run CLI scripts.

---

## Evidence

### 1. Role system — `apps/shop-api/prisma/schema.prisma`

```prisma
enum UserRole {
  OWNER
  MANAGER
  CASHIER
  STOCK_CLERK
}

model User {
  id                   String   @id @default(uuid()) @db.Uuid
  fullName             String
  phone                String   @unique
  pinHash              String
  mustChangePin        Boolean  @default(false)
  isPlatformSuperAdmin Boolean  @default(false)  // ← platform admin marker
  role                 UserRole @default(CASHIER)
  active               Boolean  @default(true)
  ...
}

model Permission { ... }
model RolePermission { ... }
```

- Four roles exist: `OWNER`, `MANAGER`, `CASHIER`, `STOCK_CLERK`.
- `isPlatformSuperAdmin` is a boolean flag, not a separate role. The account gets `role = OWNER`.
- `Permission` and `RolePermission` models exist for fine-grained overrides layered on top of roles, but appear to be schema scaffolding only — no seeded permissions found.

Migration `0002_required_pin_change` introduced both `mustChangePin` and `isPlatformSuperAdmin` columns.

---

### 2. Platform super-admin bootstrap script — `apps/shop-api/src/scripts/create-super-admin.ts`

```typescript
// Creates or updates the platform administrator in this shop database.
// Re-runs never reset credentials.
await prisma.user.upsert({
  where: { phone },
  update: {
    fullName: 'Retail OS Super Admin',
    pinHash,
    role: 'OWNER',
    active: true,
    mustChangePin: true,
    isPlatformSuperAdmin: true,
  },
  create: { ... },
});
```

Key behaviour:
- Creates an `OWNER`-role user with `isPlatformSuperAdmin: true`.
- Sets `mustChangePin: true` — the account cannot use any authenticated route until the PIN is changed.
- Idempotent: re-running will not reset a PIN that has already been changed.
- If the phone already exists with `isPlatformSuperAdmin: true`, it just ensures `role = OWNER` and `active = true` without touching the PIN hash.

---

### 3. Provisioning pipeline — `apps/control-plane-api/src/modules/provisioning/steps.ts`

The provisioning workflow has a dedicated `platform_admin` step (position 135, hidden from customers):

```typescript
{
  key: 'platform_admin',
  displayName: 'Setting up platform administrator',
  position: 135,
  customerVisible: false,
  async execute(ctx, deps) {
    const admin = deps.platformSuperAdmin;
    if (!admin) return { message: 'Platform administrator credentials are not configured' };
    await mustSucceed(
      deps, 'Platform administrator creation',
      composeArgs(ctx, 'exec', '-T', 'backend', 'node', 'dist/create-super-admin.js',
        admin.phone, admin.initialPin),
      ctx.instanceDir,
    );
    return { message: 'Platform administrator ready; initial PIN change required' };
  },
}
```

The step is **optional** — if `POS_SUPER_ADMIN_PHONE` / `POS_SUPER_ADMIN_PIN` environment variables are not set, provisioning continues without error.

---

### 4. CLI provisioning — `apps/control-plane-api/src/cli/provision.ts`

```typescript
const platformAdminPhone = process.env.POS_SUPER_ADMIN_PHONE;
const platformAdminPin   = process.env.POS_SUPER_ADMIN_PIN;

if (Boolean(platformAdminPhone) !== Boolean(platformAdminPin)) {
  throw new Error('Set both POS_SUPER_ADMIN_PHONE and POS_SUPER_ADMIN_PIN, or leave both unset.');
}
```

The PIN is redacted from logged command output:
```typescript
const safeArgs = args.includes('create-super-admin.js')
  ? [...args.slice(0, -1), '[initial PIN redacted]']
  : args;
```

---

### 5. CI/CD — `.github/workflows/deploy-pos.yml`

```yaml
POS_SUPER_ADMIN_PHONE: ${{ secrets.POS_SUPER_ADMIN_PHONE }}
POS_SUPER_ADMIN_PIN:   ${{ secrets.POS_SUPER_ADMIN_PIN }}
```

Both secrets are mandatory at deployment. The workflow validates their presence and format before proceeding. Credentials are written to a short-lived JSON file on the remote host, used once, then deleted.

---

### 6. Documentation — `docs/SUPER_ADMIN_BOOTSTRAP.md`

Explicitly documents the per-shop isolation model:

> "The account has owner access within that shop. Shop databases stay isolated, so this is a separately stored account in each installation, not a central cross-shop session."

For existing shops provisioned before this feature was added, the doc says:
> "Existing shops need the database migration and one-time super-admin creation script run against each shop database before those shops gain the account."

---

### 7. Auth middleware — `apps/shop-api/src/lib/auth.middleware.ts`

```typescript
export function requireRole(...roles: string[]) {
  return (req, res, next) => {
    const auth = res.locals.auth as AuthLocals | undefined;
    if (!auth) return sendError(res, 401, 'NO_TOKEN', 'Authentication is required.');
    if (!roles.includes(auth.role)) {
      return sendError(res, 403, 'FORBIDDEN', 'Your account does not have permission to do this.');
    }
    return next();
  };
}
```

`isPlatformSuperAdmin` is **not checked** by `requireRole` or `requireAuth`. The platform super-admin is authorized identically to any other OWNER — there is no elevated API privilege at runtime. The flag is purely a marker for idempotent re-provisioning.

---

### 8. Staff management endpoints — `apps/shop-api/src/modules/auth/auth.router.ts`

OWNER-only staff management routes exist and are functional:

| Method | Path | Guard | Purpose |
|--------|------|-------|---------|
| GET | `/auth/users` | `OWNER` | List all staff accounts |
| POST | `/auth/users` | `OWNER` | Create a staff account |
| PATCH | `/auth/users/:id` | `OWNER` | Update name, phone, PIN, role, active |
| POST | `/auth/change-pin` | authenticated | Change own PIN |
| POST | `/auth/login` | public | PIN login, returns JWT |

Safeguards on PATCH:
- An owner cannot deactivate or demote their own account.
- If only one active owner exists, demotion is blocked (prevents lock-out).

---

### 9. Flutter POS — `apps/shop_pos/lib/views/settings_view.dart`

The Settings screen has a "Users, Roles & Staff Access Control" section with:
- Staff card list showing name, role badge, phone, active/inactive status.
- "Add Staff Member" button → modal dialog with name, phone, PIN, role fields.
- Edit button per staff card → same modal pre-populated.
- Role colour-coding: OWNER (amber), MANAGER (violet), CASHIER (green), STOCK_CLERK (blue).
- Calls `widget.state.addUser()` / `widget.state.updateUser()` which hit the `POST /auth/users` and `PATCH /auth/users/:id` API routes.

No admin-specific screen exists in the Flutter app beyond this standard Settings panel.

---

### 10. Control-plane admin — `apps/web/`

The README states:
> `web/` — marketing site + control-plane admin (Phase 2)

The current `web/` directory contains `app/`, `components/`, and `public/` folders but **no source files** — it is a stub. Phase 2 is listed as "Onboarding funnel" in the roadmap. A control-plane admin UI is explicitly planned but does not exist yet.

---

### 11. Control-plane schema — `apps/control-plane-api/prisma/schema.prisma`

The control-plane database has an `Account` model (public-facing shop owner signup) and an `AuditLog` model, but **no admin user model, no admin role, and no admin-only endpoints**. The control-plane is currently CLI-only.

---

## What Exists vs What Doesn't

| Feature | Status |
|---------|--------|
| Per-shop OWNER/MANAGER/CASHIER/STOCK_CLERK roles | ✅ Implemented |
| Staff management API (CRUD users) | ✅ Implemented |
| Staff management UI in Flutter POS | ✅ Implemented |
| PIN-based auth with JWT, role enforcement | ✅ Implemented |
| Platform super-admin bootstrap (per-shop) | ✅ Implemented |
| Provisioning pipeline runs `create-super-admin.js` | ✅ Implemented |
| `isPlatformSuperAdmin` flag in schema + migration | ✅ Implemented |
| Fine-grained `Permission` / `RolePermission` models | ✅ Schema only — no data seeded, no API |
| Central cross-shop admin API | ❌ Does not exist |
| Admin portal / admin web UI | ❌ Planned (Phase 2), not started |
| Platform super-admin with elevated API privileges | ❌ The flag is a marker only — same access as any OWNER |
| Control-plane HTTP endpoints (POST /control/instances, etc.) | ❌ Planned but not built — CLI only |

---

## Conclusions and Recommendations

### 1. The `isPlatformSuperAdmin` flag gives no extra API power

The flag is only checked in `create-super-admin.ts` to prevent re-seeding from resetting a changed PIN. No API route checks it for elevated access. If you need the platform admin to have capabilities that a shop owner shouldn't have (e.g., viewing audit logs, unlocking accounts, resetting PINs without the old one), you will need to add a `requireRole('OWNER')` + `isPlatformSuperAdmin` check or a dedicated privilege tier.

**Recommendation:** If platform-level access is needed (e.g., support staff logging in to diagnose a shop), consider adding a `PLATFORM_ADMIN` role or checking `isPlatformSuperAdmin` in `auth.middleware.ts` to extend what it can do beyond regular `OWNER`. Document what that extra access entails.

### 2. `Permission` / `RolePermission` models are scaffolding only

The schema has fine-grained permission tables but nothing seeds them and no API reads them. Either implement the permission system or remove the tables to avoid misleading future developers.

**Recommendation:** Either wire up the Permission/RolePermission tables (check permissions in `requireRole` or a new `requirePermission` middleware), or mark them as Phase 6+ work and add a comment in the schema so they are not mistaken for live infrastructure.

### 3. No mechanism to add a super-admin to existing shops

The docs note that existing shops need the migration and the script run manually. There is no API or automated path for this.

**Recommendation:** When Phase 1 provisioning is complete, add a control-plane CLI command (e.g., `provision-admin --instance <id>`) that SSHes in and runs `create-super-admin.js` against the shop's running container. This keeps the operation consistent and audited.

### 4. Control-plane has no admin API yet

The `POST /control/instances` HTTP endpoint mentioned in `provision.ts` comments does not exist. All provisioning is manual CLI today.

**Recommendation:** This is already tracked under Phase 2 (Onboarding funnel). No action needed now, but the `provision()` function in `runner.ts` is ready to be wrapped in an HTTP handler without changes to the core logic.

### 5. The `web/` admin panel is Phase 2 work

Nothing to do now. The README roadmap is accurate: Phase 2 = onboarding funnel + control-plane admin. The placeholder directories are correct.
