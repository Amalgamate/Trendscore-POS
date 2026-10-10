'use client';

import Link from 'next/link';
import { useStoreCart } from './store-cart';

export function StoreHeader() {
  const { itemCount, hydrated } = useStoreCart();

  return (
    <header className="store-header">
      <Link className="wordmark" href="/" aria-label="Store home">
        <span className="wordmark-mark">S</span>
        <span>ShopSmart <small>PREVIEW</small></span>
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/#products">Browse</Link>
        <Link href="/policies">Policies</Link>
      </nav>
      <Link className="bag-link" href="/cart" aria-label={`Preview bag, ${itemCount} items`}>
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M5 8h14l1 12H4L5 8Z" />
          <path d="M9 9V6a3 3 0 0 1 6 0v3" />
        </svg>
        <span className="bag-label">Bag</span>
        <span className="bag-count" aria-live="polite">
          {hydrated ? itemCount : 0}
        </span>
      </Link>
    </header>
  );
}
