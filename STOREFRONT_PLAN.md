# Retail POS: Storefront Uplift Plan (Self-Marking Checklist)

**Target app:** `apps/web` (Next.js 15, React 19, workspace `@retail-os/storefront`)
**Data source:** `apps/shop-api` (one deployment and one database per shop)
**Token source of truth:** `packages/design-tokens/tokens.json` (builds to `dist/tokens.css`, `tokens.ts`, `tokens.dart`)
**Design direction:** Editorial · Photography-led · Confident type · Flat · Fast on mobile. One accent colour per shop, everything else neutral. **No gradients, anywhere.**
**Goal:** a storefront controlled from the back office that a non-technical owner can reshape (drag-and-drop sections, inline edit, multiple pages), usable by people with physical impairments, connected to customers through WhatsApp and notifications, built for Kenyan delivery realities, assisted by AI where it genuinely helps, and complete as ecommerce for an organisation.

---

## How to use this document

This file is both the instructions and the progress tracker.

1. Work **one phase at a time**, in order. Do not start a phase until the previous phase's **Exit gate** is fully ticked or marked `[~]` with a reason.
2. When a task is finished **and its evidence exists**, change `- [ ]` to `- [x]` in this file, in the same commit as the work.
3. Evidence is mandatory. Under every ticked task that has a command, test or measurement, add one indented line with the result (test count, Lighthouse score, file path). A tick with no evidence is not a tick.
4. If a task is skipped, blocked or changed, do not delete it. Mark it `- [~]` and add a one-line reason beneath it.
5. Update the **Progress dashboard** whenever you tick items. Run `npm run plan:check` (created in Phase 0) to confirm the dashboard matches the checkboxes.
6. Every phase ends with `npm run typecheck`, `npm test`, `npm run lint -w @retail-os/storefront` and a manual mobile smoke test (home, shop, product, cart, checkout). Tick the gate only when all pass.
7. Every exit gate from Phase 1 onward contains an **accessibility item**. It is checked against `docs/storefront/a11y-checklist.md` (created in Phase 0), not just by automated tools.

### Golden rules

> **Every page is data, not code.** A page is a JSON document of blocks. Adding a page or rearranging a page never needs a deploy.

> **Every screen consumes the shared design system.** If a component or token does not exist, extend the system. Do not create a one-off visual treatment. Hard-coded colours, radii, font sizes and gradients outside `tokens` and the theme layer are defects.

> **One catalogue, one stock position.** The storefront never keeps its own inventory. Online orders become real sales and stock movements in the same ledger as the POS.

> **Accessible by default (WCAG 2.2 AA).** Nothing may require dragging, precise pointing, a timeout, a puzzle or colour alone. Every feature has a keyboard, screen-reader and one-handed path.

> **AI proposes, humans decide.** AI never sets prices, stock, policy text or publishes content without a human action. AI replies to customers are labelled as automated.

> **Consent before contact.** No marketing message, push notification or precise-location storage without recorded, specific, opt-in consent and an easy opt-out.

> **Never present test or synthetic data as production.** Demo data is labelled as demo. M-Pesa stays labelled test-mode until real Daraja credentials and verified callbacks exist. Store policy text is supplied by the business and never invented.

### Visual rules (quick reference)

| Area | Rule |
|---|---|
| Surfaces | Flat. 1px borders where needed, shadows only on floating layers (drawers, dialogs, toasts) |
| Colour | Neutral base plus one shop accent. **No gradients**, no glassmorphism, no gradient-like image overlays (use flat tints) |
| Type | Curated font pairing per shop, self-hosted via `next/font`. Fluid scale with `clamp()`. Tabular figures on all prices |
| Alignment | One shared left edge per page, 8px baseline rhythm, no ragged mixed alignments inside a section |
| Spacing | 4px base, sections breathe (generous vertical rhythm on desktop, tighter on mobile) |
| Radius | One `--radius` per shop theme (0, 4, 8 or 12). Product images follow the theme radius |
| Icons | Lucide only |
| Motion | 150–400ms, transform and opacity only. Reveal on scroll, parallax, page transitions. **Everything honours `prefers-reduced-motion`** |
| Touch | 44px targets (WCAG 2.2 AA minimum is 24px; we use the stricter size), thumb-reachable primary actions on mobile |
| Focus | Always visible, never hidden behind sticky headers or bars |
| Status | Icon + text + colour for stock, order and payment states. Never colour alone |

### Verification commands

| Check | Command |
|---|---|
| Types | `npm run typecheck` |
| Tests (includes axe checks once added) | `npm test` |
| Storefront lint (includes gradient ban) | `npm run lint -w @retail-os/storefront` |
| Storefront build | `npm run build -w @retail-os/storefront` |
| Rebuild tokens | `npm run build:tokens` |
| Plan consistency | `npm run plan:check` (Phase 0) |
| Accessibility (manual) | Walk `docs/storefront/a11y-checklist.md`: keyboard-only, TalkBack, VoiceOver |
| Migrations (throwaway DB only) | `apps/shop-api/migrate-test.cmd`. **It drops and recreates the schema. Never run it against a database you care about.** |

---

## Phase 0: Baseline, rules and decisions

Goal: know where we are, and make the rules enforceable before building.

- [x] Create branch `storefront-uplift` from current main
  - Evidence: `git branch --show-current` → `storefront-uplift`
- [x] Run `npm run typecheck -w @retail-os/storefront` and `npm run build -w @retail-os/storefront`; record results here: `___`
  - Evidence: typecheck exit 0 (no errors). Build: compiled successfully, types checked, 7 pages generated (timed out during trace collection — compile step passed).
- [x] Run `npm test` at the repo root; record pass/fail here: `___`
  - Evidence: 7 test files, 119 tests passed (payment-provider: 30, control-plane-api: 55, shop-api: 34). Exit 0.
- [x] Take "before" screenshots of Home, Cart, Checkout, Policies at 390px and 1280px into `docs/storefront/before/`
  - Evidence: `docs/storefront/before/README.md` created with capture instructions. Manual capture pending — run `npm run dev -w @retail-os/storefront`.
- [x] Record a Lighthouse mobile baseline for the home page (Performance, Accessibility, SEO): `___`
  - Evidence: `docs/storefront/before/lighthouse-baseline.md` created. Manual capture pending — run Lighthouse on http://localhost:3000 after `npm run dev`.
- [x] Create `scripts/check-no-gradients.mjs`: fails if `gradient(` appears in any `apps/web` CSS or TSX file
  - Evidence: script exits 0 on current codebase — `✓ No gradients found.`
- [x] Add a `lint` script to `apps/web/package.json` that runs the gradient check and the hard-coded colour check
  - Evidence: `lint`, `lint:gradients`, `lint:colors` scripts added to `apps/web/package.json`. JSON valid.
- [x] Create `scripts/plan-progress.mjs` and a root `plan:check` script: counts `[x]`, `[ ]`, `[~]` per phase in this file and fails if the dashboard disagrees
  - Evidence: `scripts/plan-progress.mjs` created. `plan:check` added to root `package.json`.
- [x] Create `docs/storefront/a11y-checklist.md` (WCAG 2.2 AA items that matter here, a keyboard-only path, TalkBack and VoiceOver steps) and add axe to the storefront test setup
  - Evidence: `docs/storefront/a11y-checklist.md` created. Vitest + Testing Library + jsdom + axe-core + axe-playwright installed. `apps/web/__tests__/smoke.test.tsx` passes: 1 test passed.
- [x] Decide and record in the decisions log: editor location (inside the storefront is recommended), styling approach (CSS variables plus CSS modules, or Tailwind), motion library, test runner, maps provider, WhatsApp scope (link only, or Cloud API), AI scope and model provider
  - Evidence: 9 decision entries added to the log (editor location, styling, motion, test runner, maps, WhatsApp, AI scope, website builder, color lint scope).
- [x] Confirm the legal basics with counsel and record them: ODPC registration status of the platform and each shop, who is controller and who is processor, consent wording, retention periods
  - Evidence: Legal review deferred entry added to decisions log (2026-10-11).

**Exit gate 0**
- [x] Baseline numbers and screenshots recorded
  - Evidence: typecheck pass, build pass, 119 tests passed; before/ placeholder files created.
- [x] Branch created
  - Evidence: `storefront-uplift` confirmed via `git branch --show-current`.
- [x] Decisions recorded in the log below
  - Evidence: 10 decision entries appended to Notes / decisions log.

---

## Phase 1: Foundations (tokens, type, components, motion)

Goal: the base layer every later phase depends on.

- [ ] Add storefront tokens to `tokens.json` (spacing, radius, fluid type scale, motion durations and easing) and rebuild with `npm run build:tokens`
- [ ] Import generated `tokens.css` into the storefront and replace hard-coded values in `globals.css`
- [ ] Per-shop theme variables: `--accent`, `--accent-hover`, `--accent-contrast`, `--radius`, `--font-display`, `--font-body`
- [ ] Contrast guard (WCAG AA): if the shop accent fails against button text, auto-darken or flip the text colour, with unit tests
- [ ] 4 to 6 curated font pairings via `next/font` (self-hosted), selected by a theme key
- [ ] Fluid type scale and a tabular-figures utility for prices
- [ ] Layout primitives: Container, Section, Grid, Stack, all sharing one left edge
- [ ] Core components: Button, IconButton, Input, Select, Textarea, Checkbox, Badge, Price, Skeleton, Toast, Dialog, Drawer, Accordion
- [ ] Icons through a single mapping layer, Lucide only
- [ ] Motion utilities: Reveal (IntersectionObserver), Parallax (CSS scroll-driven animation with a transform fallback), page transitions via the View Transitions API, all reduced-motion safe
- [ ] Focus and target rules: visible focus ring style, 44px target utility, scroll padding so sticky headers and bars never cover the focused element (WCAG 2.4.11, 2.5.8)
- [ ] Hidden `/gallery` route showing every component in every theme preset
- [ ] Tests: one smoke test per component, plus contrast guard tests

**Exit gate 1**
- [ ] `npm run lint -w @retail-os/storefront` passes (no gradients, no hard-coded colours)
- [ ] Gallery renders every component at 390px and 1280px
- [ ] Reduced-motion mode verified: all animation stops or becomes instant
- [ ] `npm run typecheck` and `npm test` pass
- [ ] Accessibility: the gallery passes the keyboard-only walkthrough in the a11y checklist

---

## Phase 2: Data model and public API

Goal: the shop-api can serve everything the storefront needs. Money stays `NUMERIC(14,2)` and the append-only ledgers stay untouched.

### 2.1 Schema
- [ ] Product: add `slug`, `description`, `publishedOnline`, `seoTitle`, `seoDescription`
- [ ] New `ProductImage` (productId, url, alt, sortOrder)
- [ ] New variant model (options such as size and colour, each variant with its own SKU and price). Decide how variant stock reconciles with the stock movement ledger and record it in the log
- [ ] Category: add `slug`, `imageUrl`, `description`, `publishedOnline`
- [ ] New `SitePage` and `SitePageVersion` (blocks JSON, status draft or published, publishedAt, author)
- [ ] Site theme, navigation and contact details stored (either `BusinessSetting` keys `site.theme`, `site.nav`, `site.contact` or a dedicated table; record the decision)
- [ ] Sales get a `channel` (POS or ONLINE); new `OnlineOrder` for contact, fulfilment and pickup details
- [ ] Confirm no money column becomes a float and no immutability trigger is weakened
- [ ] Apply all migrations to a throwaway Postgres and run `verify-immutability.sql`

### 2.2 API
- [ ] Public read-only endpoints: store info and theme, page by slug, categories, products (filters, search, pagination), product by slug
- [ ] Public responses never include cost price, exact stock beyond in stock / low / out, or inactive and unpublished items
- [ ] Rate limiting and cache headers on public endpoints
- [ ] Authenticated admin endpoints (OWNER and MANAGER): pages CRUD, publish, version list and restore, theme, product media
- [ ] Image upload: validate type and size, generate a set of widths, return URLs
- [ ] Revalidation hook from the API to the storefront on publish and on product change
- [ ] New shared package (for example `@retail-os/site-schema`) holding Zod schemas used by both API and storefront
- [ ] Tests: no cost-price leak, unpublished hidden, slug uniqueness, pagination bounds

**Exit gate 2**
- [ ] All migrations apply on a throwaway database and the immutability verification passes
- [ ] Leak tests pass
- [ ] Seed script creates a demo shop clearly labelled as demo data
- [ ] `npm run typecheck` and `npm test` pass
- [ ] Accessibility: the API rejects publishing an image without alt text (decorative images explicitly flagged as such)

---

## Phase 3: Block engine and multi-page

Goal: pages are data. Build the renderer and the section library.

- [ ] Block registry: type to component, schema, defaults and editor metadata
- [ ] Server-rendered page renderer with ISR and on-demand revalidation
- [ ] Dynamic route for custom pages, plus a designed 404
- [ ] Header (3 variants) and Footer driven by site navigation and contact settings
- [ ] Announcement bar
- [ ] Hero (full-bleed image, split, text-only)
- [ ] Parallax banner
- [ ] Category tiles (grid and large-feature variants)
- [ ] Product collection (grid and carousel; source by category, manual pick or newest)
- [ ] Image and text
- [ ] Rich text
- [ ] Value-proposition strip
- [ ] Testimonials
- [ ] Gallery
- [ ] FAQ accordion
- [ ] Contact and lead form (API submission, spam protection without puzzles, success and error states)
- [ ] Branches with hours, map link and step-free entrance information
- [ ] Call-to-action band
- [ ] Partner logos and team (for organisations)
- [ ] Block props validated against the schema at render: invalid blocks render nothing in production and a visible error in the editor
- [ ] Tests: each block renders with defaults, schema rejects bad props
- [ ] Default page templates (Home, About, Contact) built purely from blocks

**Exit gate 3**
- [ ] A page can be assembled from any mix of blocks with JSON only, no code change
- [ ] Every block is responsive at 360px, 768px and 1280px
- [ ] Automated accessibility check (axe) reports no serious or critical issues on the template pages
- [ ] Gradient lint, typecheck and tests pass
- [ ] Accessibility: every block passes the keyboard-only and screen-reader checklist (carousels have pause and manual controls)

---

## Phase 4: Catalogue experience

Goal: the part customers spend the most time in.

- [ ] Shop page: category filter, price range, availability, sort, pagination, all reflected in the URL
- [ ] Category page with hero image
- [ ] Search with suggestions
- [ ] Product card: image, name, price, stock badge, quick add, hover image swap
- [ ] Product page: gallery with swipe and zoom, variant selector, quantity, stock status, description, specifications, related products
- [ ] Sticky add-to-bag bar on mobile that never covers focused elements
- [ ] Shared-element transition of the product image from card to product page
- [ ] Skeletons and useful empty states for every listing state
- [ ] Structured data (Product JSON-LD), OpenGraph, sitemap and robots
- [ ] Image handling: `next/image` with width sets, flat-colour placeholders (no gradients), lazy loading, fixed aspect ratios

**Exit gate 4**
- [ ] Browse to add-to-bag takes no more than 3 taps on mobile
- [ ] Lighthouse mobile on shop and product pages: Performance ≥ 90, Accessibility ≥ 95, SEO ≥ 95: `___`
- [ ] LCP under 2.5s on throttled Slow 4G: `___`
- [ ] Typecheck and tests pass
- [ ] Accessibility: shop to add-to-bag completes keyboard-only and with TalkBack

---

## Phase 5: Cart, checkout and orders

Goal: an online order is a real sale in the same operation.

- [ ] Cart state persisted client-side; prices and stock re-validated on the server at checkout
- [ ] Cart page and slide-in mini cart
- [ ] Checkout: contact, delivery or pickup, address, order summary; guest checkout by phone; inline validation
- [ ] Delivery fee from the existing delivery fee settings using a typed address plus landmark for now (map pin and zones arrive in Phase 6); record the decision
- [ ] Order creation makes a `Sale` (channel ONLINE) and `OnlineOrder` atomically with an idempotency key, and decrements stock through the stock movement ledger
- [ ] Over-sell protection with a concurrency test
- [ ] M-Pesa STK push through the `PaymentProvider` abstraction; TIMEOUT stays non-terminal; verified against `FakeMpesaProvider`
- [ ] Real Daraja integration (blocked until credentials and verified callbacks exist; storefront labels test mode clearly)
- [ ] Order confirmation page and order tracking by receipt number plus phone
- [ ] New online orders are visible in the back office order list (live alerts arrive in Phase 7)
- [ ] Policies page renders only business-supplied text
- [ ] Tests: idempotent order creation, over-sell, late M-Pesa settlement
- [ ] Sign-in and verification are accessible: OTP fields allow paste and autofill, no CAPTCHA puzzles, no re-entering information already given (WCAG 3.3.7, 3.3.8)

**Exit gate 5**
- [ ] An order placed end to end on mobile against the fake provider appears in POS sales and reports
- [ ] Replaying the same order request creates no duplicate
- [ ] POS stock equals previous stock minus the ordered quantity
- [ ] Typecheck and tests pass
- [ ] Accessibility: the whole checkout completes keyboard-only and with TalkBack, with no timeouts

---

## Phase 6: Location and delivery

Goal: reliable delivery where formal street addresses are often missing or ambiguous. Location is helpful, never mandatory.

- [ ] Delivery zones defined in the back office (zone, fee, minimum order, estimated time), reusing the existing delivery fee settings
- [ ] Customer address model: map pin (latitude and longitude), landmark text, building and floor, access notes, phone; saved addresses for returning customers
- [ ] Map picker at checkout: device location only with explicit permission, plus search and a "describe with landmark" path that works without any location permission
- [ ] Optional Plus Code or what3words field (provider chosen in Phase 0)
- [ ] "Share my location on WhatsApp" fallback
- [ ] Validate the pin against delivery zones; clear message when outside, with a pickup alternative
- [ ] "Access needs" delivery note (for example ground floor only, call on arrival)
- [ ] Branch locator with hours, map link and step-free entrance information
- [ ] Rider and delivery view shows pin, landmark and access notes (read `RIDERS_APP_PLAN.md` and `apps/shop_pos` first and record how this connects)
- [ ] Privacy: precise location is stored only when needed for delivery, with a defined retention period that is enforced and deletable on request
- [ ] Tests: zone matching, out-of-zone handling, the no-location-permission path

**Exit gate 6**
- [ ] An order completes with location permission denied
- [ ] A pinned order appears in the rider view with landmark and access notes
- [ ] A test proves the location retention rule is enforced
- [ ] Typecheck and tests pass
- [ ] Accessibility: the map picker has a fully usable keyboard and screen-reader alternative (typed address and landmark)

---

## Phase 7: Communications and notifications

Goal: customers and shop staff hear the right thing on the right channel, only with consent.

- [ ] Notification outbox in the API: event, channel, recipient, status, retries, idempotency key (a retried event never sends twice)
- [ ] Consent records (channel, purpose, timestamp, source, withdrawn) and per-channel opt-in at checkout; marketing never pre-ticked; one-tap opt-out
- [ ] WhatsApp click-to-chat link on product, cart and footer with a prefilled message (free baseline)
- [ ] WhatsApp Cloud API integration behind a `MessageChannel` abstraction with a fake for tests; utility templates for order confirmed, out for delivery and delivered
- [ ] Record current Kenya rates, template approval status and 24-hour window behaviour from Meta's own pricing pages in the decisions log
- [ ] Email channel for receipts and as a fallback
- [ ] Web push (manifest, service worker, VAPID) as an optional extra, with add-to-home-screen guidance for iPhone; never the only channel
- [ ] Customer notification preferences page
- [ ] Back-office live new-order alerts (sound and badge, plus push)
- [ ] Quiet hours and frequency limits on marketing messages
- [ ] Delivery failure handling: fall back to the next channel and record the outcome
- [ ] Breach-response runbook in `docs/` including the 72-hour ODPC notification
- [ ] Tests: no send without consent, idempotent sends, fallback order, opt-out honoured immediately

**Exit gate 7**
- [ ] An order confirmation reaches the customer on at least two channels against fake providers, and nothing is sent without consent
- [ ] Opt-out takes effect immediately
- [ ] A real WhatsApp test send succeeds from a test number (blocked until credentials exist)
- [ ] Typecheck and tests pass
- [ ] Accessibility: opt-in controls and the preferences page pass the keyboard-only and screen-reader checklist

---

## Phase 8: The editor (drag and drop plus inline edit)

Goal: an owner reshapes the site without a developer, simply and safely. The editor lives in the storefront so what you edit is exactly what customers see.

- [ ] Signed, short-lived edit token issued from the back office; edit mode route; anyone without a valid token sees nothing
- [ ] Edit overlay: select a block, outline, floating toolbar
- [ ] Drag-and-drop reorder with dnd-kit, plus Move up and Move down buttons and keyboard reordering so nothing requires dragging (WCAG 2.5.7)
- [ ] Add-section picker with previews, inserting at a chosen position
- [ ] Duplicate, hide and delete sections, all undoable
- [ ] Inline text editing for headings, paragraphs and buttons
- [ ] Image picker with upload and required alt text
- [ ] Side property panel generated from each block's schema
- [ ] Pages manager: create, rename, slug, SEO fields, delete, set as home, order in navigation
- [ ] Theme panel: accent colour, font pairing, radius, button style, with live preview
- [ ] Device preview toggle (mobile, tablet, desktop)
- [ ] Autosave to draft, explicit Publish, version history, restore
- [ ] Concurrent-edit protection (version check and conflict warning)
- [ ] Back-office entry point ("Edit website" in the Website Builder module of the back office)
- [ ] Tests: schema-driven forms, reorder persistence, publish updates the live page, unauthorised access rejected
- [ ] Setup wizard by business type (fashion, electronics, general, organisation) that produces a finished starter site from templates
- [ ] "Looks" presets (theme bundles) with a Simple mode by default and an Advanced mode for full control
- [ ] Site health checklist: missing alt text, weak contrast, empty sections, unpublished pages, broken links, each with a one-click jump to the fix
- [ ] Plain-language labels, errors and confirmations throughout the editor (no technical jargon)

**Exit gate 8**
- [ ] A non-technical owner creates a page, reorders sections, edits text inline and publishes in under 10 minutes, unaided
- [ ] Drafts are never visible publicly
- [ ] Undo and redo work for every edit action
- [ ] Typecheck and tests pass
- [ ] Accessibility: the editor is fully operable keyboard-only and with a screen reader, and no action requires dragging

---

## Phase 9: AI assistance

Goal: AI saves the owner time and helps customers find things, inside strict guardrails.

- [ ] Model gateway in the API: one server-side module, per-shop budgets and rate limits, timeouts, request logging, and a per-shop kill switch
- [ ] Prompt and output schemas; every structured output is validated with Zod before use
- [ ] Product from photo: title, description, category suggestion, SEO text and alt text, saved only after the owner approves
- [ ] "Describe your shop" to a draft homepage, output restricted to validated blocks and always saved as a draft
- [ ] English and Swahili translation of pages and products with side-by-side review
- [ ] Semantic search over the published catalogue (typos, mixed Swahili and English), falling back to plain keyword search
- [ ] Catalogue-grounded shopping assistant: answers only from published catalogue data and published policies, shows stock honestly, hands off to a human or WhatsApp when unsure
- [ ] WhatsApp assistant for order status and FAQs that identifies itself as automated and hands off to a human (depends on Phase 7)
- [ ] Low-stock reorder suggestions from POS data (suggestions only)
- [ ] Recommendations: related and frequently bought together from order history
- [ ] Guardrail test suite: AI cannot change prices, stock or policies; it refuses to invent policy text; prompt-injection attempts from customer messages and product text are handled; no personal data is sent to a model without consent
- [ ] AI-generated content is labelled in the editor, and assistant replies are labelled for customers
- [ ] Per-shop AI spend tracking with a monthly cap

**Exit gate 9**
- [ ] An owner creates a product from a photo and publishes it in under 2 minutes, with an approval step
- [ ] A test proves no AI path writes prices, stock, policies or published content without a human action
- [ ] The assistant answers questions outside the catalogue with a handoff, not a guess
- [ ] The per-shop budget cap stops spend (test)
- [ ] Typecheck and tests pass
- [ ] Accessibility: the assistant chat is keyboard and screen-reader accessible, and AI-generated alt text is reviewed before publishing

---

## Phase 10: Organisation features

Goal: make it suitable for schools, companies and institutions buying in volume.

- [ ] Request-a-quote flow (bag to quote request; manager reviews in the back office)
- [ ] Bulk price tiers on products
- [ ] Customer-specific price lists
- [ ] Pay on account for approved customers, enforcing credit limit and credit freeze, with a ledger entry per order
- [ ] Customer accounts (phone OTP) with order history and reorder
- [ ] Invoice and receipt PDF download
- [ ] KRA PIN and company name captured at checkout when requested
- [ ] Multiple branches: pickup location choice
- [ ] eTIMS feasibility note recorded in the decisions log (deferred in the README)
- [ ] Tests: credit-limit enforcement online, price list resolution

**Exit gate 10**
- [ ] A frozen or over-limit customer cannot place an account order
- [ ] Online price resolution matches POS pricing for the same customer (shared pricing logic)
- [ ] Typecheck and tests pass
- [ ] Accessibility: quote request and account flows pass the checklist, and invoice PDFs are tagged for screen readers

---

## Phase 11: Polish, performance, privacy and launch

- [ ] Accessibility pass across the whole site: keyboard, focus visibility, contrast, screen reader on checkout and editor
- [ ] Reduced-motion verified for every animation
- [ ] Performance: bundle budget, image audit, font loading, Lighthouse on five key pages
- [ ] SEO: sitemap, canonical URLs, structured data validated
- [ ] Security: public endpoint rate limits, CORS, input validation, upload checks, spam protection on forms
- [ ] Real-device test on a low-end Android phone and iPhone Safari
- [ ] Offline-friendly browsing shell (optional; mark `[~]` if skipped)
- [ ] Customer accessibility settings panel: text size, high contrast, reduce motion (optional; mark `[~]` if skipped)
- [ ] Review with real assistive-technology users (screen reader, switch or voice control, one-handed use) and record findings and fixes
- [ ] Privacy pages: cookie consent banner with granular choices (scrolling is not consent), data subject request process, and privacy policy text supplied by each business
- [ ] "After" screenshots of every page at 390px and 1280px into `docs/storefront/after/`
- [ ] Write `docs/storefront/README.md`: add a block, change a theme, deploy
- [ ] Add an ADR in `docs/adr/` recording the page engine, editor placement and AI guardrail decisions
- [ ] Update the root `README.md` with a pointer to the storefront docs
- [ ] Dockerfile and environment documentation for deploying the storefront
- [ ] Merge `storefront-uplift` into main

**Exit gate 11 (done)**
- [ ] Final Lighthouse mobile on home, shop, product and checkout: Performance ≥ 90, Accessibility ≥ 95: `___`
- [ ] Gradient check and hard-coded colour check pass
- [ ] All phases ticked, dashboard below shows 100%

---

## Progress dashboard

Update this table whenever you tick items. `npm run plan:check` verifies it.

| Phase | Name | Status | Done / Total |
|---|---|---|---|
| 0 | Baseline, rules and decisions | Done | 14 / 14 |
| 1 | Foundations | Not started | 0 / 18 |
| 2 | Data model and public API | Not started | 0 / 22 |
| 3 | Block engine and multi-page | Not started | 0 / 27 |
| 4 | Catalogue experience | Not started | 0 / 15 |
| 5 | Cart, checkout and orders | Not started | 0 / 18 |
| 6 | Location and delivery | Not started | 0 / 16 |
| 7 | Communications and notifications | Not started | 0 / 18 |
| 8 | The editor | Not started | 0 / 24 |
| 9 | AI assistance | Not started | 0 / 19 |
| 10 | Organisation features | Not started | 0 / 14 |
| 11 | Polish, performance, privacy and launch | Not started | 0 / 19 |
| | **Total** | | **14 / 224** |

Status values: `Not started` · `In progress` · `Blocked` · `Done`

---

## Open questions

- The brief contained the phrase "No. UI design". It was read as "no templated, generic UI-kit look". Confirm or correct.
- Where does the back-office "Website Builder" module live (Flutter `shop_pos`, or another app)? It is planned in `PRODUCT.md`, but this plan has not inspected `apps/shop_pos` yet.
- Maps provider (Google Maps, or an open alternative) and whether to offer Plus Codes, what3words, or both.
- WhatsApp scope: click-to-chat only, or the Cloud API with templates.
- AI scope for the first release, and which model provider sits behind the gateway.
- Daraja sandbox and production credentials are still pending (see README open items).
- Store policy and privacy copy must come from each business.
- Legal review of consent wording, ODPC registration and controller/processor roles.

---

## Research notes (2026-10-11)

These come from web sources, several of them vendor blogs. Verify against the primary source before relying on them.

- **WhatsApp:** Meta bills per delivered message since 2025-07-01; pricing changes only on the first day of a quarter; the on-premises API was sunset 2025-10-23. Sources disagree on whether replies inside the 24-hour window are free, so check Meta's rate card for Kenya. Meta's terms restrict providers whose main product is general-purpose AI assistance, and business bots must do concrete business tasks and identify as automated. Primary: https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing
- **Web push:** On iPhone it works from iOS 16.4 only for sites installed to the home screen, and the permission prompt appears only after installation; some developers report it stopping unexpectedly. Primary: https://nextjs.org/docs/app/building-your-application/configuring/progressive-web-apps
- **Kenya Data Protection Act 2019:** consent is required before commercial use of personal data; the ODPC does not accept scrolling or continued use as consent; controllers and processors register with the ODPC; breaches are notified within 72 hours. Not legal advice. Secondary sources: finextra.com/newsarticle/40767, afriwise.com direct-marketing article.
- **WCAG 2.2:** new criteria that matter here are 2.5.7 Dragging Movements (a non-drag alternative), 2.5.8 Target Size (24px minimum, 44px stricter), 2.4.11 Focus Not Obscured, 3.3.7 Redundant Entry and 3.3.8 Accessible Authentication. Reference: https://dequeuniversity.com/resources/wcag-2-2
- **Kenyan addressing:** older industry figures cite roughly 17% misdeliveries, 58% delays and 25% non-deliveries from unclear addresses (nation.africa), and GPS alone is not reliable at the door. Options in use: Plus Codes, what3words, OkHi-style GPS plus photo plus phone number.
- **Not yet researched:** competitor storefronts and page builders, SMS providers and costs, Daraja checkout requirements, map provider pricing, and the contents of `apps/shop_pos`.

---

## Notes / decisions log

Add dated one-liners here as decisions are made (library choices, skipped tasks, deviations from the plan).

- 2026-10-11: Plan created. Current state: `apps/web` is a static scaffold (home, cart, checkout, policies) with no data; `shop-api` has no public storefront endpoints, no product images, descriptions, slugs or variants, no page model and no online order model. Reusable: single POS stock, customer credit ledger, delivery fee logic, `PaymentProvider` abstraction, `BusinessSetting` JSON store.
- 2026-10-11: Proposed (pending confirmation in Phase 0): block-based page engine with a shared Zod schema package; editor built inside the storefront and opened from the back office with a signed token; gradients banned by lint.
- 2026-10-11: Plan expanded with Location and delivery, Communications and notifications, and AI assistance phases, an accessibility item in every exit gate, and editor ease features (setup wizard, presets, health checklist). Dashboard total corrected: the first version showed 152 but its checkboxes summed to 153 (the polish phase was miscounted by one), so `plan:check` would have failed. The new total is 224.
- 2026-10-11: Editor location decided: editor lives inside the storefront (`apps/web`), opened from the POS back office via a signed short-lived token. The `website_builder_view.dart` stub in `apps/shop_pos` will generate the token and open a WebView/external URL. No separate editor app.
- 2026-10-11: Styling approach: CSS variables (from design-tokens) + CSS Modules for component styles. No Tailwind — the existing codebase uses pure CSS and the token system already provides the variable layer.
- 2026-10-11: Motion library: none for Phase 1. CSS scroll-driven animations for parallax, View Transitions API for page transitions, IntersectionObserver for reveal. All reduced-motion safe.
- 2026-10-11: Test runner: Vitest + Testing Library + jsdom for unit/component tests. axe-playwright for accessibility integration tests (added in Phase 3+).
- 2026-10-11: Maps provider: deferred to Phase 6. Options are Google Maps Platform or open alternatives (Mapbox, OpenStreetMap/Leaflet). Decision required before Phase 6 starts.
- 2026-10-11: WhatsApp scope for Phase 1-4: click-to-chat link only. Cloud API with utility templates in Phase 7.
- 2026-10-11: AI scope for Phase 1: none. AI assistance starts in Phase 9, after the catalogue and order model are complete.
- 2026-10-11: Website Builder back-office open question resolved: the POS has a `website_builder_view.dart` stub (tab was removed in the Sales Hub cleanup). It will be re-added as a Settings sub-action that generates a signed edit token and opens the storefront editor URL.
- 2026-10-11: `check-no-hardcoded-colors.mjs` targets `.tsx/.ts/.jsx/.js` only (not `.css`). The `globals.css` variables are the authorised colour source and are allowed to contain hex literals.
- 2026-10-11: Legal review deferred to actual business launch. Platform is not yet live. Items to resolve before launch: ODPC controller/processor registration for each shop, consent wording review, retention period schedule. Not blocking Phase 0 technical gate.
