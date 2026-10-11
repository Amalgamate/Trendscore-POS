'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { AddToBagButton } from '../../add-to-bag-button';
import { StoreProductArt } from '../../store-product-art';
import { formatStorePrice } from '../../store-data';
import { useStoreCart } from '../../store-cart';

export default function StorefrontProductPage() {
  const { products, catalogState } = useStoreCart();
  const { productId } = useParams<{ productId: string }>();
  const product = products.find((item) => item.id === productId);

  if (catalogState === 'loading') {
    return (
      <main className="simple-page product-detail-page" aria-live="polite">
        <p>Loading product details…</p>
      </main>
    );
  }

  if (!product && catalogState === 'error') {
    return (
      <main className="simple-page product-detail-page">
        <Link className="back-link" href="/#products">
          <span aria-hidden="true">←</span> Back to products
        </Link>
        <div className="catalog-empty product-not-found" role="alert">
          <h1>Product details are unavailable</h1>
          <p>The shop catalog could not be loaded. Please try again later.</p>
          <Link className="button button-secondary" href="/">
            Return to the storefront
          </Link>
        </div>
      </main>
    );
  }

  if (!product) {
    return (
      <main className="simple-page product-detail-page">
        <Link className="back-link" href="/#products">
          <span aria-hidden="true">←</span> Back to products
        </Link>
        <div className="catalog-empty product-not-found" role="status">
          <h1>Product not available</h1>
          <p>This item may have been removed from the shop catalog.</p>
          <Link className="button button-primary" href="/#products">
            Browse products
          </Link>
        </div>
      </main>
    );
  }

  return (
    <main className="simple-page product-detail-page">
      <nav className="product-breadcrumb" aria-label="Breadcrumb">
        <Link href="/#products">Products</Link>
        <span aria-hidden="true">/</span>
        <span aria-current="page">{product.name}</span>
      </nav>

      <div className="product-detail-layout" data-product-presentation>
        <StoreProductArt
          product={product}
          className="product-detail-art"
          decorative={false}
        />
        <section className="product-detail-copy">
          <p className="product-detail-category">{product.category}</p>
          <h1>{product.name}</h1>
          {product.variantLabel && (
            <p className="product-detail-variant">{product.variantLabel}</p>
          )}
          <p className="product-detail-price">{formatStorePrice(product.salePrice)}</p>
          {product.description && (
            <p className="product-detail-description">{product.description}</p>
          )}
          <div
            className={`product-detail-availability${product.available ? ' is-available' : ' is-unavailable'}`}
            role="status"
          >
            <span aria-hidden="true" />
            {product.available ? 'Available from the shop' : 'Currently out of stock'}
          </div>
          {product.unit && (
            <p className="product-detail-unit">Sold by {product.unit}</p>
          )}
          <div className="product-detail-actions">
            <AddToBagButton
              product={product}
              className="button button-primary product-detail-add"
              addedLabel="Added to bag"
              disabledLabel="Out of stock"
            />
            <Link className="product-view-bag" href="/cart">
              View bag
            </Link>
          </div>
          <p className="product-detail-note">
            Price and availability come from the shop’s live catalog.
          </p>
        </section>
      </div>
      <Link className="back-link product-detail-back" href="/#products">
        <span aria-hidden="true">←</span> Continue browsing
      </Link>
    </main>
  );
}
