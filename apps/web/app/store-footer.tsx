import Link from 'next/link';

export function StoreFooter() {
  return (
    <footer className="store-footer">
      <div className="footer-main">
        <div>
          <Link className="wordmark footer-wordmark" href="/">
            <span className="wordmark-mark">S</span>
            <span>ShopSmart</span>
          </Link>
          <p>A storefront preview powered by ShopSmart.</p>
        </div>
        <nav className="policy-links" aria-label="Store policies">
          <Link href="/policies#delivery">Delivery</Link>
          <Link href="/policies#returns">Returns</Link>
          <Link href="/policies#privacy">Privacy</Link>
          <Link href="/policies#terms">Terms</Link>
        </nav>
      </div>
      <div className="footer-bottom">
        <span>Sample items only · Ordering is not enabled.</span>
        <span>© {new Date().getFullYear()} ShopSmart</span>
      </div>
    </footer>
  );
}
