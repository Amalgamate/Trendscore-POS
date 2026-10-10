import Link from 'next/link';

export function StoreHeader() {
  return (
    <header className="store-header">
      <Link className="wordmark" href="/" aria-label="Store home">
        <span className="wordmark-mark">S</span>
        <span>Your shop</span>
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/">Shop</Link>
        <Link href="/policies">Store information</Link>
      </nav>
      <Link className="bag-link" href="/cart">
        Bag <span aria-hidden="true">0</span>
      </Link>
    </header>
  );
}
