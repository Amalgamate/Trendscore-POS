import type { StoreProduct } from './store-data';

type StoreProductArtProps = {
  product: StoreProduct;
  className?: string;
  decorative?: boolean;
};

export function StoreProductArt({
  product,
  className = '',
  decorative = true,
}: StoreProductArtProps) {
  const imageAlt = `${product.name}${product.variantLabel ? `, ${product.variantLabel}` : ''}`;

  return (
    <div
      className={`product-art art-${product.color}${className ? ` ${className}` : ''}`}
      data-flight-source
      aria-hidden={decorative || !product.imageUrl ? true : undefined}
    >
      {product.imageUrl ? (
        <img
          src={product.imageUrl}
          alt={decorative ? '' : imageAlt}
          loading={decorative ? 'lazy' : 'eager'}
        />
      ) : (
        <>
          <span className="art-orbit" />
          <span className="art-object">{product.mark.slice(0, 1)}</span>
          <span className="art-label">{product.mark}</span>
        </>
      )}
    </div>
  );
}
