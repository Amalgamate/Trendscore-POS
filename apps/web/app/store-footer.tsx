import Link from 'next/link';

export function StoreFooter() {
  return (
    <footer className="store-footer">
      <div className="footer-main">
        <div>
          <Link className="wordmark footer-wordmark" href="/">
            <span className="wordmark-mark">S</span>
            <span>Your shop</span>
          </Link>
          <p>Online store powered by ShopSmart.</p>
        </div>
        <nav className="policy-links" aria-label="Store policies">
          <Link href="/policies#delivery">Delivery</Link>
          <Link href="/policies#returns">Returns</Link>
          <Link href="/policies#privacy">Privacy</Link>
          <Link href="/policies#terms">Terms</Link>
        </nav>
      </div>
      <div className="footer-bottom">
        <span>Store policies will be published by the shop.</span>
        <span>© {new Date().getFullYear()} ShopSmart</span>
      </div>
    </footer>
  );
}
