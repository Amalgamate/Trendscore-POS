'use client';

import Link from 'next/link';
import { formatStorePrice } from '../store-data';
import { useStoreCart } from '../store-cart';

export default function CartPage() {
  const {
    products,
    catalogState,
    items,
    subtotal,
    hydrated,
    storageError,
    setQuantity,
    remove,
  } = useStoreCart();

  const cartLines = items.flatMap((line) => {
    const product = products.find((item) => item.id === line.productId);
    return product ? [{ ...line, product }] : [];
  });

  return (
    <main className="simple-page cart-page">
      <div className="page-heading-row">
        <div>
          <h1>Your bag</h1>
          <p className="page-intro">
            Your selected shop products. Online checkout is not enabled yet.
          </p>
        </div>
        <Link className="back-link" href="/#products">
          <span aria-hidden="true">←</span> Continue browsing
        </Link>
      </div>

      {storageError && (
        <p className="inline-warning" role="status">
          Your browser could not save this preview bag. It may clear when you
          leave this page.
        </p>
      )}

      {!hydrated ? (
        <div className="catalog-empty" aria-live="polite">
          Loading your bag…
        </div>
      ) : cartLines.length === 0 ? (
        <div className="cart-empty">
          <div className="empty-mark" aria-hidden="true">
            <svg viewBox="0 0 48 48" fill="none">
              <path
                d="M8 18h32l-3 22H11L8 18Z"
                stroke="currentColor"
                strokeWidth="2"
              />
              <path
                d="M17 19v-5a7 7 0 0 1 14 0v5"
                stroke="currentColor"
                strokeWidth="2"
              />
            </svg>
          </div>
          <h2>Your bag is empty</h2>
          <p>
            {catalogState === 'live'
              ? 'Browse published products and add a few to your bag.'
              : 'Browse sample items and add a few to try the bag.'}
          </p>
          <Link className="button button-primary" href="/#products">
            {catalogState === 'live' ? 'Browse products' : 'Browse sample items'}
          </Link>
        </div>
      ) : (
        <div className="cart-layout">
          <section className="cart-lines" aria-label="Items in your bag">
            <div className="cart-list-heading">
              <h2>Selected products</h2>
              <span>
                {cartLines.reduce((sum, line) => sum + line.quantity, 0)} items
              </span>
            </div>
            {cartLines.map(({ product, quantity }) => (
              <article className="cart-line" key={product.id}>
                <div className={`cart-art art-${product.color}`}>
                  {product.imageUrl ? (
                    <img src={product.imageUrl} alt="" />
                  ) : (
                    <span aria-hidden="true">{product.mark.slice(0, 1)}</span>
                  )}
                </div>
                <div className="cart-line-info">
                  <span className="product-category">{product.category}</span>
                  <h3>{product.name}{product.variantLabel ? ` · ${product.variantLabel}` : ''}</h3>
                  <p>{formatStorePrice(product.salePrice)}</p>
                  <button
                    className="remove-link"
                    type="button"
                    onClick={() => remove(product.id)}
                    aria-label={`Remove ${product.name} from bag`}
                  >
                    Remove
                  </button>
                </div>
                <div className="cart-line-controls">
                  <strong>
                    {formatStorePrice(product.salePrice * quantity)}
                  </strong>
                  <div className="quantity-control" aria-label={`Quantity of ${product.name}`}>
                    <button
                      type="button"
                      onClick={() => setQuantity(product.id, quantity - 1)}
                      aria-label={`Decrease ${product.name} quantity`}
                    >
                      −
                    </button>
                    <span aria-live="polite">{quantity}</span>
                    <button
                      type="button"
                      onClick={() => setQuantity(product.id, quantity + 1)}
                      aria-label={`Increase ${product.name} quantity`}
                    >
                      +
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </section>

          <aside className="cart-summary" aria-label="Bag summary">
            <h2>Summary</h2>
            <div className="summary-row">
              <span>Subtotal</span>
              <strong>{formatStorePrice(subtotal)}</strong>
            </div>
            <div className="summary-row summary-muted">
              <span>Delivery</span>
              <span>Not configured</span>
            </div>
            <p className="summary-note">
              Delivery and verified online payment are still being connected.
            </p>
            <Link className="button button-disabled" href="/checkout">
              Checkout unavailable
            </Link>
            <Link className="text-link summary-policies" href="/policies">
              Review store information
            </Link>
          </aside>
        </div>
      )}
    </main>
  );
}
