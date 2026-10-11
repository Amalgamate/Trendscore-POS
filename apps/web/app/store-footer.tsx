'use client';

import Link from 'next/link';
import Image from 'next/image';
import { useStoreCart } from './store-cart';

export function StoreFooter() {
  const { storefrontProfile } = useStoreCart();

  return (
    <footer className="store-footer">
      <div className="footer-main">
        <div>
          <Link className="wordmark footer-wordmark" href="/">
            <Image
              className="wordmark-logo"
              src="/shopsmart-leaf.svg"
              alt=""
              width={28}
              height={28}
            />
            <span>ShopSmart</span>
          </Link>
          <p>Online catalog for {storefrontProfile.storeName}.</p>
        </div>
        <nav className="policy-links" aria-label="Store policies">
          <Link href="/policies#delivery">Delivery</Link>
          <Link href="/policies#returns">Returns</Link>
          <Link href="/policies#privacy">Privacy</Link>
          <Link href="/policies#terms">Terms</Link>
        </nav>
      </div>
      <div className="footer-bottom">
        <span>Online ordering is not enabled yet.</span>
        <span>
          © {new Date().getFullYear()} {storefrontProfile.storeName}
        </span>
      </div>
    </footer>
  );
}
