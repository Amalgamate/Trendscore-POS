import Link from 'next/link';

export default function StorefrontHome() {
  return (
    <>
      {/* THESIS: A customer storefront connected to the shop's existing POS catalog, not a separate inventory.
          OWN-WORLD: ShopSmart navy, white, and teal; clear commerce controls and calm product-first typography.
          STORY: Customers discover a shop, browse its published items, and continue toward a trustworthy checkout.
          FIRST VIEWPORT: Store identity and bag in the header, a concise welcome, then the POS-published catalog.
          FORM: Mobile-first storefront scaffold; product, order, and payment data stay absent until connected to the shop API. */}
      <main>
        <section className="welcome-band" aria-labelledby="welcome-title">
          <div className="welcome-copy">
            <p className="eyebrow">SHOPSMART ONLINE STORE</p>
            <h1 id="welcome-title">Your shop, open online.</h1>
            <p>
              Products published from the shop&apos;s POS catalog will appear
              here for customers to browse and buy.
            </p>
            <a className="button button-primary" href="#products">
              Explore the store
            </a>
          </div>
          <div className="welcome-aside" aria-label="Store setup status">
            <span className="status-dot" />
            <div>
              <strong>Store setup in progress</strong>
              <p>Published products will show here when the catalog is connected.</p>
            </div>
          </div>
        </section>

        <section className="catalog-section" id="products" aria-labelledby="catalog-title">
          <div className="section-heading">
            <div>
              <p className="eyebrow">THE CATALOG</p>
              <h2 id="catalog-title">Shop products</h2>
            </div>
          </div>
          <div className="empty-catalog">
            <div className="empty-mark" aria-hidden="true">
              <svg viewBox="0 0 48 48" fill="none">
                <path d="M8 18h32l-3 22H11L8 18Z" stroke="currentColor" strokeWidth="2" />
                <path d="M17 19v-5a7 7 0 0 1 14 0v5" stroke="currentColor" strokeWidth="2" />
                <path d="M18 27h12" stroke="currentColor" strokeWidth="2" />
              </svg>
            </div>
            <h3>Products are on their way</h3>
            <p>
              When this shop publishes products from its POS, they&apos;ll be
              available to browse here.
            </p>
            <Link className="text-link" href="/policies">
              Store information <span aria-hidden="true">→</span>
            </Link>
          </div>
        </section>
      </main>
    </>
  );
}
