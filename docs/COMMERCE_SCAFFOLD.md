# ShopSmart commerce scaffold

This repository now contains the first UI and application boundaries for:

- `apps/web`: a separate Next.js customer storefront (`/`, `/cart`,
  `/checkout`, and `/policies`).
- `Website Builder`: an owner/manager POS module with industry selection,
  store-launch checklist, delivery, policies, and checkout setup placeholders.
- `Social Commerce`: an owner/manager POS module listing official channel
  integration prerequisites and the future product-post workflow.

The POS product workspace and public catalog connection are implemented. Owners
and managers can save product descriptions, images, variants, and web-shop
publication status. The public API returns only published, active products and
does not expose cost or exact stock; the storefront shows a simple availability
status. The local storefront preview uses explicitly labeled sample products
only when the API is unreachable. Checkout does not collect customer details,
create orders, reserve stock, or accept payment. Real shop policies and customer
contact details remain unconfigured rather than being fabricated. Its WhatsApp
link appears only when a valid
`NEXT_PUBLIC_STORE_WHATSAPP_NUMBER` is supplied. Production should resolve
that number from the shop's server-side storefront configuration instead of a
single global environment variable.

## Integration sequence

1. Deploy the Next.js storefront at `webshop.trendscore.co.ke` and
   `www.webshop.trendscore.co.ke`. The production workflow builds a dedicated
   image, provisions Nginx routing and Let's Encrypt certificates, and proxies
   the storefront's `/api` requests to the shop-specific API. DNS must point
   both names to the deployment host before the workflow runs. Do not accept an
   arbitrary business ID from a public request.
2. Add stock reservations, commerce orders, idempotent order/payment attempts,
   append-only order status events, fulfillment, and reconciliation. Connect
   completed orders to POS stock, sales, and reports.
3. Replace test-only M-Pesa behavior with the official Safaricom Daraja
   provider. Validate signed/verified callbacks and reconcile uncertain or
   delayed results before marking an order paid.
4. Add per-shop official OAuth connections, encrypted token storage, webhook
   processing, revocation, and job queues for publishing and retry handling.
   Implement only API capabilities approved for the ShopSmart app and the
   customer's account.

The initial social channel candidates are Facebook, Instagram, Threads,
TikTok, Pinterest, YouTube, and X. WhatsApp Cloud API and Meta catalog sync are
additional integration surfaces. Platform permissions, content formats,
publishing availability, reviews, quotas, and commercial features differ;
the channel list is not a promise that every action can be automated.

## Inputs needed before production integrations

- Shop name, logo/brand assets, public contact details, domain choice, and DNS
  access for the storefront hostname.
- Product images, descriptions, categories, active price/stock rules, and
  industry-specific attributes and SKU/variant conventions.
- Delivery areas, fees, pickup options, cancellation/returns handling, and
  order fulfillment responsibilities.
- Shop-authored delivery, returns, privacy, and terms copy, reviewed and
  approved by the business before publication.
- Safaricom Daraja developer and production access, callback hostname, and
  settlement/reconciliation expectations.
- Meta developer/business setup and review; eligible Facebook/Instagram
  accounts. TikTok, Threads, Pinterest, YouTube, and X developer app/access as
  each channel is prioritized. Shops will authorize their own accounts.
- Approved object storage/media hosting and production API deployment.

Never paste API secrets, access tokens, PINs, or private keys into chat or
commit them. Store integration credentials in server-side secret storage.

## Local storefront development

Install the workspace dependencies from the repository root, set
`NEXT_PUBLIC_SHOP_API_BASE_URL` to the shop API base URL when the storefront is
not served behind a same-origin `/api` proxy, then run:

```powershell
npm run dev --workspace @retail-os/storefront
```

The storefront uses Next.js App Router for a separately deployable,
server-rendered public website. In production, Nginx routes the storefront
hostnames to this app and proxies `/api` to the configured shop API instance.

## Reference documentation checked

- [Instagram Content Publishing](https://developers.facebook.com/documentation/instagram-platform/content-publishing/)
- [Meta Catalog](https://developers.facebook.com/documentation/ads-commerce/catalog/)
- [WhatsApp Cloud API](https://developers.facebook.com/documentation/business-messaging/whatsapp/get-started)
- [TikTok Direct Post](https://developers.tiktok.com/docs/en/content-posting-api-reference-direct-post)
- [Threads API](https://developers.facebook.com/documentation/threads/)
- [Pinterest app access](https://developers.pinterest.com/docs/getting-started/connect-app/)
- [YouTube Data API video uploads](https://developers.google.com/youtube/v3/guides/uploading_a_video)
- [X Developer Platform](https://docs.x.com/overview)
- [Safaricom Developer Portal](https://developer.safaricom.co.ke/)
