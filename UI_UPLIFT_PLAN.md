# Retail POS: UI Uplift Plan (Self-Marking Checklist)

**Target app:** `apps/shop_pos` (Flutter web/desktop/mobile)
**Token source of truth:** `packages/design-tokens/tokens.json` (builds to `dist/tokens.dart`, `tokens.css`, `tokens.ts`)
**Design direction:** Mature · Operational · Premium · Dense · Fast · Calm. "Modern African commerce infrastructure."

---

## How to use this document

This file is both the instructions and the progress tracker.

1. Work **one phase at a time**, in order. Do not start a phase until the previous phase's **Exit gate** is fully ticked.
2. When a task is finished and verified, change `- [ ]` to `- [x]` **in this file**, in the same commit as the work.
3. Update the **Progress dashboard** at the bottom (counts and status) whenever you tick items.
4. If a task is skipped or changed, do not delete it. Mark it `- [~]` and add a one-line reason beneath it.
5. Every phase ends with `flutter analyze` clean and a manual smoke test (login, add item, checkout, receipt). Tick the gate only when both pass.

### The golden rule

> **Do not design individual screens independently. Every screen must consume the shared design system. If a component doesn't exist, extend the design system rather than creating a one-off visual treatment.**

Hard-coded `Color(...)`, `Colors.white`, raw radii, raw font sizes and raw paddings inside `views/` are defects. Anything visual comes from `theme/` or `shared/widgets/`.

### Visual rules (quick reference)

| Area | Rule |
|---|---|
| Surfaces | Flat, subtle 1px borders, minimal shadows (`sm` only on floating layers) |
| Colour | ~90% neutral + one accent (teal). No gradients, no glassmorphism |
| Type | Inter, 14px body is the workhorse. Tabular numerals on all money. JetBrains Mono for SKU/receipt |
| Spacing | 4px base; live mostly in 8 / 12 / 16 / 24 |
| Radius | Inputs/buttons 8, cards/dialogs 12, product tiles 10, badges/status pills full. No 24px sheets |
| Icons | Lucide only. No Material/Cupertino icons |
| Motion | 120–200ms, communicates state only |
| Status | Icon + text + colour. Never colour alone |

---

## Phase 0: Baseline and safety net

Goal: know where we are before changing anything.

- [x] Create branch `ui-uplift` from current main
- [x] Run `flutter analyze` and record the warning count here: `2 warnings + 44 infos, 0 errors` (via `dart analyze lib`; `flutter analyze` stalled at "Analyzing shop_pos…" twice, so use `dart analyze lib` as the Phase gate command)
- [x] Run `flutter test` and record pass/fail here: `27 passed, 1 failed` (widget test fails on the native runner: it imports `file_picker_web` / `dart:js_interop`, unavailable off-web. Fix: conditional import or run with `flutter test --platform chrome`)
- [ ] Take "before" screenshots of: Login, POS/Sell, Checkout modal, Receipt, Inventory, Customers, Sales History, Reports, Cash Drawer, Purchase Orders, Settings, More sheet (mobile width)
- [ ] Save screenshots to `docs/ui-uplift/before/`
- [x] Audit script created: `scripts/ui-audit.mjs` (counts Colors, Color(0x), radii, fontSize, EdgeInsets, Icons, SnackBar, shadows, gradients per file)
- [x] Run `node scripts/ui-audit.mjs` from the repo root; it writes `docs/ui-uplift/audit.md`. Record the grand total here: `1633` (Icons.* 288, fontSize 391, BorderRadius.circular 251, EdgeInsets 265, Color(0x) 237, Colors.* 119, SnackBar 50, BoxShadow 14, Radius.circular 14, Gradient 4, CupertinoIcons 0)
- [x] Review `theme/tokens.dart` against `tokens.json`: `lib/theme/tokens.dart` is identical to `dist/tokens.dart` (in sync). Finding: `build.mjs` hard-codes `AppSpacing`, `AppRadius`, `AppText` and `buildRetailOsTheme()` in the Dart emitter, so `tokens.json` spacing/radius/typography do NOT drive Dart yet (fixed in Phase 1.1)

**Exit gate 0**
- [ ] Baseline numbers and screenshots recorded (numbers done; screenshots outstanding)
- [x] Branch created

---

## Phase 1: Foundations (tokens, type, icons, theme)

Goal: the base layer every later phase depends on. Low risk, high visible impact.

### 1.1 Tokens
- [x] Add to `tokens.json`: `surfaceSubtle`, `borderStrong` (verify), `primaryHover`, `primaryPressed`, `accentLight`, status "light" backgrounds (success/warning/danger/info)
  - Done under the repo's existing naming: `bgSubtle`, `borderStrong`, `accentPrimaryHover`, `accentPrimaryPressed`, `accentLight`, `status{Success,Warning,Danger,Info}Light`.
- [x] Add radius tokens `xs` 4, `sm` 6, `md` 8, `lg` 12, `xl` 16, `full` (plus `tile` 10 for product tiles)
- [~] Add spacing tokens up to `6xl` (4/8/12/16/20/24/32/40/48/64)
  - Values added, but keyed by pixel (`4`…`64`, Dart `AppSpacing.s4`…`s64`) instead of `xs`…`6xl`: the plan's `xl` (20) would silently change the existing `AppSpacing.xl` (24) in every view. Legacy `xs`…`xxxl` stay as aliases with unchanged values.
- [x] Add POS type tokens: `posPrice` (20–28), `posTotal` (28–36), `display` (32)
- [x] Add a **dark** semantic set (bg `#111315`, surface `#181B1F`, surface2 `#1E2227`, border `#2A2F35`, text `#F4F5F6`, secondary `#A5ABB3`)
  - `build.mjs` now fails the build if `color.dark` and `color.semantic` keys differ.
- [x] Extend `build.mjs` Dart emitter so `AppSpacing`, `AppRadius`, shadows, motion and `AppText` are generated from `tokens.json` (currently hard-coded strings in the generator)
  - Verified on the real repo: `dart analyze lib` = 2 warnings + 44 infos (identical to the Phase 0 baseline), `flutter test test/tokens_test.dart` = 19 passed. Also generates `AppPalette` light/dark `ThemeExtension`, `AppType`, `AppShadow`, `AppMotion`.
  - Behaviour change to eyeball: `AppRadius.sm` is now 6 (was 4). `AppText` and `AppColors` are kept as LEGACY light-only classes until the Phase 3–5 migrations.
- [x] Rebuild tokens (`npm run build:tokens`) and confirm `dist/tokens.dart` updates
- [x] Copy/sync generated `tokens.dart` into `apps/shop_pos/lib/theme/` (now `npm run sync:tokens`, which does both of the above)

### 1.2 Theme split
- [x] Split `theme/`: `tokens.dart` stays **generated** (colours, spacing, radius, type scale, shadows, motion). Hand-written files live beside it: `app_theme.dart` (ThemeData builders), `app_typography.dart` (font families, tabular helpers). Never hand-edit `tokens.dart`; change `tokens.json` or `build.mjs`
- [x] Remove `buildRetailOsTheme()` from the generator output in `build.mjs` and move it into hand-written `app_theme.dart`
- [x] `buildRetailOsTheme()` configures: `colorScheme`, `scaffoldBackgroundColor`, `textTheme`, `inputDecorationTheme`, `cardTheme`, `filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`, `dividerTheme`, `dataTableTheme`, `dialogTheme`, `bottomSheetTheme`, `snackBarTheme`, `tooltipTheme`
  - Verified: `dart analyze lib` = 46 issues (identical to baseline), `flutter test test/tokens_test.dart` = 26 passed. Light and dark are built by one shared function. `fontFamily` deliberately not set until Inter is bundled (1.3). Still to eyeball visually: inputs are now dense with 8px radius, cards/dialogs have 1px borders, buttons are 40px min height.
- [x] Add `buildRetailOsDarkTheme()` and wire `themeMode` (light / dark / system) in `MaterialApp`
  - `MaterialApp` gets `theme`, `darkTheme` and `themeMode`. Dark will look broken on legacy views (hard-coded light colours) until the Phase 3–5 migrations.
- [x] Persist theme choice via the existing `shared_preferences` state
  - Done with a standalone `ThemeController` (`lib/theme/theme_controller.dart`, key `ui.themeMode`) using `shared_preferences` directly, rather than adding it to the large `PosState`. Default is `ThemeMode.light`. No UI toggle yet: it is part of the Settings work in Phase 5.

### 1.3 Typography
- [x] Bundle **Inter** (assets under `assets/fonts/`, declared in `pubspec.yaml`) so web does not fall back to Roboto
  - Inter 400/500/600/700 via `npm run sync:fonts` (from `@expo-google-fonts/inter`, OFL licence copied alongside). Verified it carries the `tnum` feature. Browser check is in Exit gate 1.
- [x] Bundle **JetBrains Mono** for SKU, barcode, receipt numbers
  - 400/500. It has no `tnum` feature but is monospaced, so digits are already fixed-width. `AppType.mono` uses it; the legacy `AppText.receipt` still uses the platform `monospace` until the receipt is migrated in Phase 4.
- [~] Apply tabular figures (`FontFeature.tabularFigures()`) to all money/quantity text via a shared `AppText.money()` helper
  - Helper built as `AppTypography.money()` (hand-written file) because `AppText` is the legacy generated class. Rolling it out to every money text is Phase 2 (`AppMoneyText`) plus the Phase 3–5 view migrations.
- [x] Verify the type scale matches the table in "Visual rules" (14px body)
  - Covered by `test/typography_test.dart` (14px body, Inter, weights, palette colour, tabular money styles): 33 tests pass together with `tokens_test.dart`; `dart analyze lib` still 46 issues.

### 1.4 Icons
- [x] Add `lucide_icons` (or `lucide_icons_flutter`) to `pubspec.yaml`
  - `lucide_icons_flutter` 3.1.22.
- [x] Create `shared/icons.dart` as a single mapping layer so views never import Lucide directly by name sprinkled everywhere
  - Generated, not hand-written: `node scripts/gen-icons.mjs` resolves every concept in `scripts/icon-map.mjs` against the installed package (108 `AppIcons.*` concepts) and fails if a Lucide name is missing. To change an icon, edit `icon-map.mjs` and re-run it.
- [x] Replace all `Icons.*` and `CupertinoIcons.*` usages (track remaining count: `0`)
  - Done with `node scripts/migrate-icons.mjs --write`: 288 replacements in 16 files, 0 unmapped. Material outlined/rounded variants collapse into one Lucide icon. `dart analyze lib` = 46 issues (baseline), 33 tests pass. Re-run `node scripts/icon-report.mjs` to confirm the remaining count is 0.
- [x] Remove `cupertino_icons` from `pubspec.yaml` once count is 0
  - Removed; `flutter pub get` confirmed it is no longer depended on. `node scripts/icon-report.mjs` = 0 distinct icons, 0 usages.

**Exit gate 1**
- [~] App runs in light and dark with no visual crashes
  - Skipped by the owner on 2026-10-08; not verified. Dark mode is not the default (`ThemeController` defaults to light) and has no toggle yet.
- [x] No `Icons.` or `CupertinoIcons.` left in `lib/`
- [~] Inter renders on web build (verify in browser dev tools)
  - Skipped by the owner; not verified in a browser. The font files, `pubspec.yaml` declarations and a guard test (`typography_test.dart`) exist, so the build is wired correctly, but rendering was never inspected.
- [~] `flutter analyze` clean, smoke test passes
  - Analyzer: `dart analyze lib` = 46 issues, identical to the Phase 0 baseline (no new issues, but not zero). Tests: 33 pass across `tokens_test.dart` and `typography_test.dart`. Smoke test (login, add item, checkout, receipt) skipped by the owner; login itself was confirmed working by the owner.

---

## Phase 2: Shared component layer

Goal: one implementation of every UI primitive. Create under `lib/shared/widgets/`.

- [ ] `AppButton` with variants: primary, secondary, ghost, destructive; sizes: md, lg (POS touch size); loading and disabled states
- [ ] `AppIconButton`
- [ ] `AppInput` (label above field, helper/error text, prefix/suffix, numeric/money variant)
- [ ] `AppSearchField` (supports barcode scanner input and `Ctrl+K` focus)
- [ ] `AppCard` (flat, 1px border, radius 12)
- [ ] `AppKpiCard` (label, value, delta with arrow + text; no floating icon circles)
- [ ] `AppBadge` / `AppStatusPill` (icon + text + colour for Paid, Pending, Failed, Refunded, Cancelled, Low stock, Out of stock)
- [ ] `AppDialog` (compact, radius 12, title + close, actions row)
- [ ] `AppBottomSheet` (radius 12 top, drag handle)
- [ ] `AppTable` (sticky header, 44–48px rows, sortable columns, right-aligned numbers, hover/selected states, pagination, bulk select, empty state)
- [ ] `AppEmptyState` (title, one-line hint, single action, no illustrations)
- [ ] `AppSkeleton` (list, table, card variants)
- [ ] `AppToast` helper replacing raw `SnackBar` (success/info/error)
- [ ] `AppSectionHeader` and `AppPageHeader`
- [ ] `AppMoneyText` (KSh formatting via `intl`, tabular figures)
- [ ] Add `intl` to `pubspec.yaml` if not already present
- [ ] Create a hidden dev route `/gallery` (or a debug-only screen) showing every component in light and dark
- [ ] Add widget tests: one golden or smoke test per component

**Exit gate 2**
- [ ] Every component above exists, is token-driven and appears in the gallery
- [ ] No component contains a hard-coded colour, radius or font size
- [ ] Tests pass, analyzer clean

---

## Phase 3: App shell and navigation

Goal: replace the tab-index + "More" sheet with a proper responsive shell. Currently `PosShell` in `main.dart` drives navigation with `_activeTabIndex`.

- [ ] Create `core/responsive/breakpoints.dart`: mobile <600, tablet 600–1023, desktop 1024–1439, large 1440+
- [ ] Create `AppShell` widget with three layouts:
  - [ ] Desktop: 240px sidebar + 64px top bar + workspace
  - [ ] Tablet: 72px collapsed rail + workspace, cart as drawer
  - [ ] Mobile: bottom navigation + full-width workspace, cart as bottom sheet
- [ ] `AppSidebar` with sections (MAIN / BUSINESS / SYSTEM), collapse toggle, and store + online status footer
- [ ] Navigation item states: default, hover, pressed, active (subtle tint, not a bright pill), disabled
- [ ] `AppTopBar`: page title, global search (`Ctrl+K`), user menu, lock-till button, sync/online indicator
- [ ] Keep existing role gating (`_accessibleTabs`): hidden or disabled items per role (owner, manager, cashier, stockClerk); use a toast, not a SnackBar, for denied access
- [ ] Keep the inactivity auto-lock behaviour intact
- [ ] Remove the old "More" sheet (or move secondary items into a tidy overflow menu on mobile)
- [ ] Migrate `main.dart`: strip inline styling (24px radius, `Colors.white`, 14px radii) and use shell + tokens

**Exit gate 3**
- [ ] All 8 sections reachable on desktop, tablet and mobile widths
- [ ] Role restrictions verified for each role (4 roles x allowed/denied)
- [ ] Auto-lock still works
- [ ] No hard-coded styles left in `main.dart`

---

## Phase 4: POS "Cashier mode" (the most important screen)

Goal: speed. Dense is secondary here; large touch targets and zero friction.

- [ ] Two-pane layout: product area (left) + persistent **Current Sale** cart (right, ~360–420px) on desktop
- [ ] Top row: search/scan field + customer selector
- [ ] Category chips row (pills allowed here as filters)
- [ ] Compact product tile (radius 10): image/placeholder, name, price (`posPrice`), stock line; click adds to cart
- [ ] Stock states on tiles: Low stock and Out of stock badges; out-of-stock disabled
- [ ] Barcode scanner input adds product without mouse focus (global key buffer or focused hidden field)
- [ ] Cart lines: product, qty stepper (`[-] 2 [+]`) plus direct keyboard qty edit, unit price, line discount, line total
- [ ] Cart summary: subtotal, discount, tax, **TOTAL** (`posTotal` size)
- [ ] Primary **Pay** button, full width, large
- [ ] Hold sale / resume sale
- [ ] Checkout modal redesign (`checkout_modal.dart`): total, payment method buttons **M-PESA | CASH | CARD** (M-Pesa first-class, not buried), amount received, change due, **Complete Sale**
- [ ] Payment success confirmation (short animation, 150–250ms), then receipt
- [ ] Receipt dialog (`receipt_dialog.dart`) uses mono font for numbers and tokens throughout
- [ ] Keyboard shortcuts: `F1` search, `F2` customer, `F3` discount, `F4` hold, `F5` pay, `F6` cash, `F7` M-Pesa, `F8` card, `Esc` cancel, `Enter` confirm, `Ctrl+K` global search
- [ ] Shortcut hints shown in tooltips/button labels
- [ ] Tablet: cart opens as drawer; Mobile: "View Cart (KSh x)" sticky bar opens bottom sheet then payment
- [ ] Loading skeletons for product grid; useful empty state when no products

**Exit gate 4**
- [ ] A full sale (scan, edit qty, discount, M-Pesa, receipt) completes without touching the mouse
- [ ] Same flow works on tablet and mobile layouts
- [ ] Time-to-first-sale sanity check: no more than 3 clicks from POS screen to payment
- [ ] No hard-coded styles in the POS, checkout or receipt files

---

## Phase 5: Manager mode (dense data screens)

Goal: information density and scannability. Use `AppTable` everywhere.

- [ ] **Inventory** (`inventory_view.dart`): table with search, category and stock filters, sortable columns, bulk select, `+ Add Product`; status pills for stock levels
- [ ] **Product editor dialog** (`product_editor_dialog.dart`): labels above inputs, compact layout, token styling
- [ ] **Category manager dialog**: token styling, compact
- [ ] **Customers** (`customers_view.dart`): table, search, detail panel or dialog
- [ ] **Sales History** (`sales_history_view.dart`): table with Date, Customer, Payment, Total, Status; filters by date range and payment method
- [ ] **Purchase Orders** (`purchase_orders_view.dart`): table + status pills
- [ ] **Cash Drawer** (`cash_drawer_view.dart`): clear open/close flow, restrained KPI cards
- [ ] **Reports** (`reports_view.dart`): dashboard layout "TODAY" KPIs (Sales, Orders), sales performance chart, recent sales table; only decision-useful information
- [ ] Add `fl_chart` (or equivalent) only if a chart is actually needed; keep charts flat, no gradients, no animated counters
- [ ] **Settings** (`settings_view.dart`): grouped sections, include theme (light/dark/system) and brand colour setting (see Phase 6)
- [ ] **Login** (`login_view.dart`): calm, centred, shop logo, PIN entry with large keypad targets
- [ ] Table rules enforced everywhere: 14px text, 44–48px rows, numbers right-aligned, text left-aligned, sticky header, hover and selected states, pagination
- [ ] Every list has a loading skeleton and a meaningful empty state ("No products yet. Add your first product to start selling.")

**Exit gate 5**
- [ ] All views use `AppTable`, `AppCard`, `AppBadge` etc. and contain no hard-coded styles
- [ ] Audit script/grep from Phase 0 shows zero violations in `views/`
- [ ] Reports readable at desktop and tablet widths

---

## Phase 6: Multi-tenant branding and polish

- [ ] Per-shop accent colour: derive `primary`, `primaryHover`, `accentLight` from the shop's brand colour (setting stored with existing brand logo settings)
- [ ] Contrast guard: if the chosen brand colour fails WCAG AA against white button text, auto-darken or flip text colour
- [ ] Logo shown in sidebar/top bar and on receipts (existing `brandLogoBase64` / `brandLogoUrl`)
- [ ] Reset-to-default brand option
- [ ] Replace all remaining `SnackBar` usage with `AppToast`; keep dialogs for critical actions only
- [ ] Motion pass: durations 120–200ms, easing `cubic-bezier(0.2, 0, 0, 1)`; remove any decorative animation
- [ ] Accessibility: focus rings visible, keyboard tab order sane, minimum 44px touch targets in POS, status never colour-only
- [ ] Text scaling check (system font scale 1.3x) on POS screen
- [ ] Dark mode review of every screen (contrast, borders, no pure black)
- [ ] Performance check: product grid with 1,000+ items scrolls smoothly; lists use lazy builders

**Exit gate 6**
- [ ] A shop with a custom brand colour looks correct in light and dark
- [ ] No `SnackBar` left in `lib/`
- [ ] Accessibility checklist above passes

---

## Phase 7: Final review and cleanup

- [ ] Re-run the hard-coded style audit: result should be zero outside `theme/` and `shared/widgets/`
- [ ] Remove dead code and unused imports; `flutter analyze` reports zero warnings
- [ ] Take "after" screenshots of every screen listed in Phase 0 into `docs/ui-uplift/after/`
- [ ] Write `docs/ui-uplift/README.md`: how to add a new component, how to change tokens, how to rebuild `design-tokens`
- [ ] Add an ADR in `docs/adr/` recording the design-system decisions (Inter, Lucide, token source of truth, two-mode design)
- [ ] Update root `README.md` with a pointer to the design system docs
- [ ] Production web build tested (`flutter build web`) and served via `serve.mjs` / Dockerfile
- [ ] Merge `ui-uplift` into main

**Exit gate 7 (done)**
- [ ] All phases ticked, dashboard below shows 100%

---

## Progress dashboard

Update this table whenever you tick items.

| Phase | Name | Status | Done / Total |
|---|---|---|---|
| 0 | Baseline and safety net | In progress | 7 / 10 |
| 1 | Foundations | Done | 25 / 25 |
| 2 | Shared component layer | Not started | 0 / 21 |
| 3 | App shell and navigation | Not started | 0 / 17 |
| 4 | POS cashier mode | Not started | 0 / 23 |
| 5 | Manager mode | Not started | 0 / 18 |
| 6 | Branding and polish | Not started | 0 / 14 |
| 7 | Final review and cleanup | Not started | 0 / 10 |

Status values: `Not started` · `In progress` · `Blocked` · `Done`

---

## Notes / decisions log

Add dated one-liners here as decisions are made (library choices, skipped tasks, deviations from the plan).

- 2026-10-07: Plan created. Existing token system ("Retail OS": navy + teal, Inter, 4px grid) is retained as the foundation.
- 2026-10-07: Phase 0 findings: `lib/theme/tokens.dart` is generated and in sync, but the generator hard-codes spacing/radius/text. `main.dart` is ~86 KB and `inventory_view.dart` ~72 KB, so the component migration will be done file by file, not in one pass.
- 2026-10-07: Phase 0 audit baseline recorded: grand total 1633 across 17 files with findings (24 scanned). Worst offenders: `main.dart` 255, `inventory_view.dart` 192, `login_view.dart` 145, `settings_view.dart` 145, `reports_view.dart` 141, `customers_view.dart` 139. `CupertinoIcons` already 0, so the `cupertino_icons` removal in 1.4 may be only a pubspec cleanup.
- 2026-10-07: Widget-test fix applied (UNVERIFIED until `flutter test` is re-run): removed the `file_picker_web` import and `webOptions` arg from `lib/services/image_file_picker_stub.dart`. The web build uses `image_file_picker_web.dart`, so web behaviour is unchanged. If `FilePicker.pickFile` turns out to require `webOptions`, revert with git and use `--platform chrome` for that test instead.
- 2026-10-07: Phase 1 pre-read finding (decision needed before 1.1/1.2): generated `AppColors` are `static const`, and `AppText` styles bake colours in. Neither can switch with light/dark. Dark mode needs theme-aware colours (a generated `ThemeExtension` such as `AppPalette` read via `context`), and `AppText` must stop carrying colour. This affects how every view is migrated in Phases 3-5.
- 2026-10-07: Currency display uses `formatKES()` ("KES 1,234.00", always 2dp). Keep it; the design doc's "KSh" wording is not adopted unless decided otherwise.
- 2026-10-08: 1.1 decisions: (a) dark-mode approach = generated `AppPalette` `ThemeExtension` (`context.palette`), registered on the theme; `AppColors` and `AppText` stay as LEGACY light-only classes until Phase 3-5 migrations delete them. (b) Spacing is keyed by pixel (`s4`…`s64`) with legacy `xs`…`xxxl` aliases, because the plan's `xl`=20 would silently shift existing `xl`=24 usages. (c) `AppRadius.sm` changes 4 → 6 per the plan. (d) New `npm run sync:tokens` copies the generated Dart into the app; CI still runs `build:tokens` and diffs. (e) Bumped tokens to 1.2.0.
- 2026-10-08: 1.2 decisions: theme split into hand-written `app_theme.dart` / `app_typography.dart` beside the generated `tokens.dart`; light and dark are built by one shared function from `AppPalette`. Theme mode persisted by a standalone `ThemeController` (key `ui.themeMode`) rather than `PosState`; default is `ThemeMode.light` until the Phase 3-5 view migrations, because legacy views hard-code light colours. No dark-mode toggle UI yet (Phase 5 Settings).
- 2026-10-08: 1.3 decisions: Inter (400/500/600/700) and JetBrains Mono (400/500) are bundled from npm (`@expo-google-fonts/*`, OFL) via `npm run sync:fonts`, so the TTFs are reproducible rather than hand-downloaded; OFL texts ship alongside. The tabular-figures helper is `AppTypography.money()` (not `AppText.money()`), because `AppText` is the legacy generated class. Rolling it out to all money text is Phase 2 (`AppMoneyText`) plus the view migrations.
- 2026-10-08: 1.4 decisions: icons use `lucide_icons_flutter` 3.1.22 behind a generated `AppIcons` layer (108 concepts) driven by `scripts/icon-map.mjs`; views never import Lucide directly. Material outlined/rounded variants collapse to one Lucide icon. Approximations: `addToCart`/`removeFromCart` both use the cart icon, `lockClock` uses a clock, `oil`/`waterDrop` use a droplet. The shop-defined category icons change appearance but are stored by key, so saved data is unaffected. `cupertino_icons` removed. `scripts/icon-report.mjs` overwrites `docs/ui-uplift/icons-used.json`; running it after the migration empties that file, which only weakens `gen-icons.mjs`'s coverage warning.
- 2026-10-08: Local-dev note (found while trying to log in for the Exit gate 1 smoke test): the web build's default server URL is the page origin plus `/api` (a production-proxy assumption), so `flutter run` needs the app's server URL set to the API directly. shop-api CORS allows only `localhost:8080` and `localhost:3000`, so run Flutter web with `--web-port 8080`. MAKU's Vite dev server also defaults to port 4000, the same as shop-api: give one of them a different port. There is no `.env.example`; shop-api needs `DATABASE_URL`, `DIRECT_URL`, `BUSINESS_ID` and `JWT_SECRET`. Never run `apps/shop-api/migrate-test.cmd` against a database you care about: it drops and recreates the schema.
- 2026-10-08: Phase 1 closed by the owner with three Exit gate 1 checks skipped (light/dark run, Inter in browser, smoke test), marked `[~]` above rather than ticked. Dashboard total corrected from 31 to 25: the Phase 1 section has 25 checkboxes (8 + 5 + 4 + 4 + 4 gate); the earlier 31 was an over-count. Known unverified risk carried into Phase 2: the new theme (dense 8px-radius inputs, bordered cards/dialogs, 40px buttons) and the Lucide icons have never been looked at in the running app.
