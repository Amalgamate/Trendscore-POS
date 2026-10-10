'use client';

import { useMemo, useState } from 'react';
import { formatStorePrice } from './store-data';
import { useStoreCart } from './store-cart';

export function StorefrontHome() {
  const [category, setCategory] = useState('All');
  const [query, setQuery] = useState('');
  const [addedProduct, setAddedProduct] = useState<string | null>(null);
  const {
    add,
    products: catalogProducts,
    catalogState,
    storefrontProfile,
  } = useStoreCart();
  const categories = useMemo(
    () => ['All', ...new Set(catalogProducts.map((product) => product.category))],
    [catalogProducts],
  );

  const filteredProducts = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return catalogProducts.filter((product) => {
      const matchesCategory = category === 'All' || product.category === category;
      const matchesQuery =
        !normalizedQuery ||
        `${product.name} ${product.variantLabel ?? ''} ${product.category} ${product.description}`
          .toLowerCase()
          .includes(normalizedQuery);
      return matchesCategory && matchesQuery;
    });
  }, [category, query, catalogProducts]);

  return (
    <main>
      {catalogState === 'sample' && (
        <div className="preview-ribbon" role="status">
          <span aria-hidden="true">PREVIEW</span>
          Live catalog is not connected. These sample products and prices are
          illustrative only.
        </div>
      )}
      {catalogState === 'error' && (
        <div className="preview-ribbon" role="alert">
          <span aria-hidden="true">NOTICE</span>
          The shop catalog is temporarily unavailable. Please try again later.
        </div>
      )}

      <section className="welcome-band" aria-labelledby="welcome-title">
      <div className="welcome-copy">
        <h1 id="welcome-title">
          Shop the {storefrontProfile.storeName} catalog.
        </h1>
          <p>
            {storefrontProfile.description ||
              'Explore products selected by the shop. Availability is checked against the live catalog; online ordering is not enabled yet.'}
          </p>
          <a className="button button-primary" href="#products">
            Browse products
          </a>
        </div>
        <div className="welcome-aside" aria-label="Preview status">
          <span
            className={`status-dot${catalogState === 'live' ? ' is-live' : ''}${catalogState === 'error' ? ' is-error' : ''}`}
          />
          <div>
            <strong>
              {catalogState === 'live'
                ? 'Published catalog'
                : catalogState === 'error'
                  ? 'Catalog unavailable'
                  : 'Catalog preview'}
            </strong>
            <p>
              {catalogState === 'live'
                ? `${catalogProducts.length} published ${catalogProducts.length === 1 ? 'product' : 'products'}`
                : catalogState === 'error'
                  ? 'Published products could not be loaded. No sample products are being shown.'
                  : 'Showing illustrative products; no orders or payments are submitted.'}
            </p>
          </div>
        </div>
      </section>

      <section className="catalog-section" id="products" aria-labelledby="catalog-title">
        <div className="catalog-intro">
          <div>
            <h2 id="catalog-title">Products selected for the web shop</h2>
            <p>Product availability and prices come from the shop catalog.</p>
          </div>
          <label className="search-field">
            <span className="search-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24">
                <circle cx="10.8" cy="10.8" r="6.8" />
                <path d="m16 16 4.2 4.2" />
              </svg>
            </span>
            <span className="visually-hidden">Search products</span>
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search products"
            />
          </label>
        </div>

        <div className="catalog-toolbar">
          <div className="category-list" aria-label="Filter products">
            {categories.map((item) => (
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
            {filteredProducts.length} {filteredProducts.length === 1 ? 'item' : 'items'}
          </span>
        </div>

        {catalogState === 'loading' ? (
          <div className="catalog-empty" role="status">Loading the shop catalog…</div>
        ) : catalogState === 'error' ? (
          <div className="catalog-empty" role="alert">
            <h3>Products are temporarily unavailable</h3>
            <p>Please try again later.</p>
          </div>
        ) : filteredProducts.length ? (
          <div className="product-grid">
            {filteredProducts.map((product) => (
              <article className="product-item" key={product.id}>
                <div className={`product-art art-${product.color}`} aria-hidden="true">
                  {product.imageUrl ? (
                    <img src={product.imageUrl} alt="" />
                  ) : (
                    <>
                      <span className="art-orbit" />
                      <span className="art-object">{product.mark.slice(0, 1)}</span>
                      <span className="art-label">{product.mark}</span>
                      {product.preview && <span className="sample-stamp">SAMPLE</span>}
                    </>
                  )}
                </div>
                <div className="product-copy">
                  <div className="product-meta">
                    <span>{product.category}</span>
                    <span>{product.available ? 'Available' : 'Out of stock'}</span>
                  </div>
                  <h3>{product.name}{product.variantLabel ? ` · ${product.variantLabel}` : ''}</h3>
                  <p>{product.description || ' '}</p>
                  <div className="product-buy-row">
                    <div>
                      <span className="price-caption">Price</span>
                      <strong>{formatStorePrice(product.salePrice)}</strong>
                    </div>
                    <button
                      className="add-button"
                      type="button"
                      disabled={!product.available}
                      onClick={() => {
                        add(product.id);
                        setAddedProduct(product.id);
                        window.setTimeout(() => setAddedProduct(null), 1600);
                      }}
                      aria-label={`Add ${product.name} to bag`}
                    >
                      {!product.available
                        ? 'Unavailable'
                        : addedProduct === product.id
                          ? 'Added'
                          : 'Add to bag'}
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="catalog-empty" role="status">
            <h3>{catalogProducts.length ? 'No products match that search' : 'No products are published yet'}</h3>
            <p>{catalogProducts.length ? 'Try another name or choose a different category.' : 'The shop has not published web-shop products yet.'}</p>
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

      <StoreDetails />

      <section className="store-next-step" aria-labelledby="next-step-title">
        <div>
          <p className="eyebrow">ONE CATALOG, ONE STOCK POSITION</p>
          <h2 id="next-step-title">Your online shop starts with your POS.</h2>
        </div>
        <p>
          This catalog comes from the shop&apos;s POS. Online orders remain
          unavailable until delivery and verified payment checkout are ready.
        </p>
      </section>
    </main>
  );
}

function StoreDetails() {
  const { storefrontProfile: profile } = useStoreCart();
  const address = [profile.address, profile.county].filter(Boolean).join(', ');
  const hasDetails = Boolean(
    profile.logoUrl ||
      profile.phone ||
      profile.email ||
      address ||
      profile.openingHours ||
      (profile.deliveryEnabled && profile.deliveryDetails) ||
      (profile.pickupEnabled && profile.pickupDetails),
  );

  if (!hasDetails) return null;

  return (
    <section className="store-details" aria-labelledby="store-details-title">
      <div className="store-details-heading">
        {profile.logoUrl && (
          <img
            className="store-details-logo"
            src={profile.logoUrl}
            alt={`${profile.storeName} logo`}
          />
        )}
        <div>
          <p className="eyebrow">VISIT OR CONTACT THE SHOP</p>
          <h2 id="store-details-title">{profile.storeName}</h2>
        </div>
      </div>
      <div className="store-details-grid">
        {address && (
          <div>
            <h3>Address</h3>
            <p>{address}</p>
          </div>
        )}
        {profile.phone && (
          <div>
            <h3>Phone</h3>
            <p><a href={`tel:${profile.phone}`}>{profile.phone}</a></p>
          </div>
        )}
        {profile.email && (
          <div>
            <h3>Email</h3>
            <p><a href={`mailto:${profile.email}`}>{profile.email}</a></p>
          </div>
        )}
        {profile.openingHours && (
          <div>
            <h3>Opening hours</h3>
            <p className="store-details-multiline">{profile.openingHours}</p>
          </div>
        )}
        {profile.deliveryEnabled && profile.deliveryDetails && (
          <div>
            <h3>Delivery</h3>
            <p className="store-details-multiline">{profile.deliveryDetails}</p>
          </div>
        )}
        {profile.pickupEnabled && profile.pickupDetails && (
          <div>
            <h3>Store pickup</h3>
            <p className="store-details-multiline">{profile.pickupDetails}</p>
          </div>
        )}
      </div>
    </section>
  );
}
