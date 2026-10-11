# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Shop owners and managers operate the POS, maintain products and stock, configure the online store, and manage social publishing. Customers browse a shop's public storefront and place orders. Cashiers continue serving in-person sales through the POS.

## Product Purpose

ShopSmart is a Kenya-first retail operating system connecting in-person POS work with an online storefront and social commerce. Success means a shop can manage its catalog and inventory once, publish products to customer-facing channels, and reconcile online orders with its existing retail operations.

## Positioning

The POS remains the shop's source of truth for catalog, stock, sales, and reporting; the storefront and social channels extend that same operation instead of creating disconnected inventories.

## Operating Context

Shops may sell across varied industries, including fashion and electronics, and need setup that adapts catalog fields and workflows to the selected business type. Customers primarily use the storefront on mobile. Initial online checkout is planned around M-Pesa.

## Capabilities and Constraints

- The existing Flutter POS and shop API are the foundation; shop data is isolated per shop.
- Planned back-office modules are Website Builder and Social Commerce, with a separate public storefront.
- Planned setup captures business industry and configures appropriate product and inventory templates.
- Online orders must reconcile with POS stock, sales, and reports.
- WhatsApp should use official business integrations for messaging; the storefront may link directly to the shop's WhatsApp contact.
- Products support server-side descriptions, images, variant labels/groups, and
  owner/manager-controlled web-shop publication. The public catalog returns
  only active, published products and exposes availability without exact stock
  or cost.
- The storefront is a separate Next.js application. Production hosting and
  shop-specific hostname/API routing still need configuration.
- M-Pesa in the payment-provider package is currently a test provider. Production checkout requires the official Safaricom Daraja integration and verified callbacks.
- Social publishing depends on each platform's official OAuth, app review, permissions, account eligibility, and API capabilities. Shops connect their own accounts.
- Store policies are supplied and approved by each business; the product must not invent legal terms.

## Brand Commitments

The product is named ShopSmart and extends the existing ShopSmart POS identity.

## Evidence on Hand

The repository contains the Flutter POS, shop API, existing product and inventory workflows, design tokens, and a test M-Pesa provider. No production storefront, Daraja credentials, social developer applications, store-policy copy, or production catalog imagery has been provided.

## Product Principles

- Keep one authoritative catalog and stock position per shop.
- Make online orders visible and auditable in the same retail operation.
- Adapt setup and product data to different industries without fragmenting the core catalog.
- Use official, permissioned integrations and make unavailable capabilities explicit.
- Never represent test payments, synthetic catalog data, or pending platform approval as production functionality.
