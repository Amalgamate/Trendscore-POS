'use client';

import { useMemo, useState } from 'react';
import { PREVIEW_PRODUCTS, STORE_CATEGORIES, formatPreviewPrice } from './store-data';
import { useStoreCart } from './store-cart';

export function StorefrontHome() {
  const [category, setCategory] = useState<(typeof STORE_CATEGORIES)[number]>('All');
  const [query, setQuery] = useState('');
  const [addedProduct, setAddedProduct] = useState<string | null>(null);
  const { add } = useStoreCart();

  const products = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return PREVIEW_PRODUCTS.filter((product) => {
      const matchesCategory = category === 'All' || product.category === category;
      const matchesQuery =
        !normalizedQuery ||
        `${product.name} ${product.category} ${product.description}`
          .toLowerCase()
          .includes(normalizedQuery);
      return matchesCategory && matchesQuery;
    });
  }, [category, query]);

  return (
    <main>
      <div className="preview-ribbon" role="status">
        <span aria-hidden="true">PREVIEW</span>
        Sample products and prices are illustrative only — this store is not
        taking orders.
      </div>

      <section className="welcome-band" aria-labelledby="welcome-title">
      <div className="welcome-copy">
        <h1 id="welcome-title">A little more room to shop.</h1>
          <p>
            Browse a sample storefront and try the bag. Real products, stock,
            and checkout will connect to the shop when setup is complete.
          </p>
          <a className="button button-primary" href="#products">
            Browse the preview
          </a>
        </div>
        <div className="welcome-aside" aria-label="Preview status">
          <span className="status-dot" />
          <div>
            <strong>Preview mode</strong>
            <p>Sample items only. No orders or payments are submitted.</p>
          </div>
        </div>
      </section>

      <section className="catalog-section" id="products" aria-labelledby="catalog-title">
        <div className="catalog-intro">
          <div>
            <h2 id="catalog-title">A sample of what a shop can offer</h2>
            <p>These example products demonstrate how the online catalog can work.</p>
          </div>
          <label className="search-field">
            <span className="search-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24">
                <circle cx="10.8" cy="10.8" r="6.8" />
                <path d="m16 16 4.2 4.2" />
              </svg>
            </span>
            <span className="visually-hidden">Search sample products</span>
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search the preview"
            />
          </label>
        </div>

        <div className="catalog-toolbar">
          <div className="category-list" aria-label="Filter sample products">
            {STORE_CATEGORIES.map((item) => (
              <button
                className={`category-chip${category === item ? ' is-active' : ''}`}
                key={item}
                type="button"
                aria-pressed={category === item}
                onClick={() => setCategory(item)}
              >
                {item}
              </button>
            ))}
          </div>
          <span className="result-count">
            {products.length} sample {products.length === 1 ? 'item' : 'items'}
          </span>
        </div>

        {products.length ? (
          <div className="product-grid">
            {products.map((product) => (
              <article className="product-item" key={product.id}>
                <div className={`product-art art-${product.color}`} aria-hidden="true">
                  <span className="art-orbit" />
                  <span className="art-object">{product.mark.slice(0, 1)}</span>
                  <span className="art-label">{product.mark}</span>
                  <span className="sample-stamp">SAMPLE</span>
                </div>
                <div className="product-copy">
                  <div className="product-meta">
                    <span>{product.category}</span>
                    <span>Preview item</span>
                  </div>
                  <h3>{product.name}</h3>
                  <p>{product.description}</p>
                  <div className="product-buy-row">
                    <div>
                      <span className="price-caption">Illustrative price</span>
                      <strong>{formatPreviewPrice(product.previewPrice)}</strong>
                    </div>
                    <button
                      className="add-button"
                      type="button"
                      onClick={() => {
                        add(product.id);
                        setAddedProduct(product.id);
                        window.setTimeout(() => setAddedProduct(null), 1600);
                      }}
                      aria-label={`Add sample ${product.name} to preview bag`}
                    >
                      {addedProduct === product.id ? 'Added' : 'Add to bag'}
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="catalog-empty" role="status">
            <h3>No sample items match that search</h3>
            <p>Try another name or choose a different category.</p>
            <button
              className="button button-secondary"
              type="button"
              onClick={() => {
                setQuery('');
                setCategory('All');
              }}
            >
              Clear filters
            </button>
          </div>
        )}
      </section>

      <section className="store-next-step" aria-labelledby="next-step-title">
        <div>
          <p className="eyebrow">ONE CATALOG, ONE STOCK POSITION</p>
          <h2 id="next-step-title">Your online shop starts with your POS.</h2>
        </div>
        <p>
          Once storefront publishing is connected, the shop&apos;s own product
          details and availability can replace these sample items.
        </p>
      </section>
    </main>
  );
}
