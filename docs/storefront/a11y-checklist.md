# Storefront Accessibility Checklist (WCAG 2.2 AA)

## How to use
Walk through each item manually for keyboard-only, TalkBack (Android) and VoiceOver (iOS/macOS).
Mark ✅ when passing, ❌ when failing (with description), ➖ when not applicable.

## Keyboard-only walkthrough
- [ ] Tab order follows visual/logical reading order on every page
- [ ] All interactive elements reachable by Tab / Shift+Tab
- [ ] No keyboard trap — Esc closes modals and drawers
- [ ] Focus ring always visible, never hidden behind sticky elements (WCAG 2.4.11)
- [ ] Sticky header has `scroll-padding-top` so focused elements aren't obscured
- [ ] Skip-to-content link is the first focusable element on every page
- [ ] Carousels: arrow keys move between items, Esc exits (if applicable)
- [ ] Drag-and-drop actions have keyboard equivalents — Move Up/Down buttons (WCAG 2.5.7)

## Pointer and touch
- [ ] All interactive targets ≥ 44×44px (stricter than WCAG 2.5.8 minimum of 24px)
- [ ] No action requires a drag gesture without a non-drag alternative
- [ ] Touch targets don't overlap on mobile viewport (390px)

## Colour and contrast
- [ ] Normal text ≥ 4.5:1 contrast ratio (WCAG 1.4.3)
- [ ] Large text (18px+ or 14px+ bold) ≥ 3:1 contrast ratio
- [ ] UI components and focus ring ≥ 3:1 against adjacent colour
- [ ] Information never conveyed by colour alone — always icon + text + colour (WCAG 1.4.1)
- [ ] Shop accent colour auto-darken/flip tested against button text

## Images and media
- [ ] All meaningful images have descriptive alt text
- [ ] Decorative images have `alt=""` and `aria-hidden="true"`
- [ ] No image alt text is "image of" or filename
- [ ] AI-generated alt text reviewed by a human before publish

## Forms
- [ ] Every input has a visible, associated `<label>` (not placeholder only)
- [ ] Error messages identify the field and explain the fix (WCAG 3.3.1, 3.3.3)
- [ ] No information re-entered that was already given in the same session (WCAG 3.3.7)
- [ ] No CAPTCHA or puzzle for authentication (WCAG 3.3.8)
- [ ] OTP fields allow paste and browser autofill
- [ ] Required fields clearly indicated (not by colour alone)

## Screen reader (TalkBack / VoiceOver)
- [ ] Page `<title>` is unique and descriptive on every page
- [ ] Landmark regions used: `<header>`, `<nav>`, `<main>`, `<footer>`
- [ ] Heading hierarchy: one `<h1>` per page, logical h2→h3 nesting
- [ ] Dynamic content changes announced via `aria-live` regions
- [ ] Modals and drawers: focus moves in, trapped inside, returns on close
- [ ] Buttons and links have descriptive accessible names (not "click here")
- [ ] Icon-only buttons have `aria-label`
- [ ] Price components read as "KES 1,234.50" not "1 , 2 3 4 . 5 0"
- [ ] Stock status conveyed in text, not colour alone
- [ ] Cart item count announced when updated

## Motion and animation
- [ ] All animations honour `prefers-reduced-motion: reduce`
- [ ] No animation triggers automatically and lasts >5 seconds without pause control (WCAG 2.2.2)
- [ ] Page transitions don't cause vestibular discomfort (transform + opacity only, no spin/zoom)

## Notifications and timeouts
- [ ] No content auto-removes in <20 seconds without user control
- [ ] Toast notifications don't time out while the user's focus is inside them
- [ ] No session timeout without warning and ability to extend

## Editor-specific (Phase 8)
- [ ] Drag-and-drop section reorder has Move Up / Move Down keyboard buttons
- [ ] All editor controls keyboard accessible
- [ ] Image picker requires alt text before inserting
- [ ] Publish confirmation dialog is keyboard accessible
- [ ] Version history table is screen-reader accessible

## Automated (axe)
- [ ] `@axe-core/react` or `axe-playwright` integrated in test suite
- [ ] No critical or serious axe violations on: Home, Shop, Product, Cart, Checkout, Policies
- [ ] Test runs in CI and fails on new violations
