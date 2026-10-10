'use client';

import Link from 'next/link';
import { PREVIEW_PRODUCTS, formatPreviewPrice } from '../store-data';
import { useStoreCart } from '../store-cart';

export default function CartPage() {
  const { items, subtotal, hydrated, storageError, setQuantity, remove } =
    useStoreCart();

  const cartLines = items.flatMap((line) => {
    const product = PREVIEW_PRODUCTS.find((item) => item.id === line.productId);
    return product ? [{ ...line, product }] : [];
  });

  return (
    <main className="simple-page cart-page">
      <div className="page-heading-row">
        <div>
          <h1>Your bag</h1>
          <p className="page-intro">
            Sample items and illustrative prices only. This bag cannot be
            checked out.
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
          <p>Browse sample items and add a few to try the bag.</p>
          <Link className="button button-primary" href="/#products">
            Browse sample items
          </Link>
        </div>
      ) : (
        <div className="cart-layout">
          <section className="cart-lines" aria-label="Items in your preview bag">
            <div className="cart-list-heading">
              <h2>Sample items</h2>
              <span>
                {cartLines.reduce((sum, line) => sum + line.quantity, 0)} items
              </span>
            </div>
            {cartLines.map(({ product, quantity }) => (
              <article className="cart-line" key={product.id}>
                <div
                  className={`cart-art art-${product.color}`}
                  aria-hidden="true"
                >
                  <span>{product.mark.slice(0, 1)}</span>
                </div>
                <div className="cart-line-info">
                  <span className="product-category">{product.category}</span>
                  <h3>{product.name}</h3>
                  <p>Illustrative price · {formatPreviewPrice(product.previewPrice)}</p>
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
                    {formatPreviewPrice(product.previewPrice * quantity)}
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
              <span>Sample subtotal</span>
              <strong>{formatPreviewPrice(subtotal)}</strong>
            </div>
            <div className="summary-row summary-muted">
              <span>Delivery</span>
              <span>Not configured</span>
            </div>
            <p className="summary-note">
              Illustrative totals only. Delivery, stock checks, and real prices
              are not connected.
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
