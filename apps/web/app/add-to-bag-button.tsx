'use client';

import { useEffect, useRef, useState } from 'react';
import type { StoreProduct } from './store-data';
import { useStoreCart } from './store-cart';

type AddToBagButtonProps = {
  product: StoreProduct;
  className?: string;
  addedLabel?: string;
  disabledLabel?: string;
};

export function AddToBagButton({
  product,
  className = 'add-button',
  addedLabel = 'Added',
  disabledLabel = 'Unavailable',
}: AddToBagButtonProps) {
  const { add } = useStoreCart();
  const [added, setAdded] = useState(false);
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(
    () => () => {
      if (resetTimer.current) clearTimeout(resetTimer.current);
    },
    [],
  );

  const animateToBag = (button: HTMLButtonElement) => {
    const bag = document.querySelector<HTMLElement>('[data-store-bag-target]');
    const source = button
      .closest<HTMLElement>('[data-product-presentation]')
      ?.querySelector<HTMLElement>('[data-flight-source]');
    if (
      !bag ||
      !source ||
      typeof source.animate !== 'function' ||
      typeof bag.animate !== 'function' ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches
    ) {
      return;
    }

    const sourceRect = source.getBoundingClientRect();
    const bagRect = bag.getBoundingClientRect();
    if (sourceRect.width === 0 || sourceRect.height === 0) return;

    const flight = source.cloneNode(true) as HTMLElement;
    flight.removeAttribute('data-flight-source');
    flight.setAttribute('aria-hidden', 'true');
    Object.assign(flight.style, {
      position: 'fixed',
      left: `${sourceRect.left}px`,
      top: `${sourceRect.top}px`,
      width: `${sourceRect.width}px`,
      height: `${sourceRect.height}px`,
      margin: '0',
      zIndex: '9999',
      pointerEvents: 'none',
      transformOrigin: 'center center',
      borderRadius: '10px',
      boxShadow: '0 14px 36px rgba(10, 22, 40, 0.22)',
    });
    document.body.appendChild(flight);

    const x = bagRect.left + bagRect.width / 2 - (sourceRect.left + sourceRect.width / 2);
    const y = bagRect.top + bagRect.height / 2 - (sourceRect.top + sourceRect.height / 2);
    const animation = flight.animate(
      [
        { transform: 'translate3d(0, 0, 0) scale(1)', opacity: 1 },
        {
          transform: `translate3d(${x}px, ${y}px, 0) scale(0.08)`,
          opacity: 0.12,
        },
      ],
      {
        duration: 680,
        easing: 'cubic-bezier(0.16, 1, 0.3, 1)',
        fill: 'forwards',
      },
    );
    animation.onfinish = () => flight.remove();
    animation.oncancel = () => flight.remove();
    bag.animate(
      [
        { transform: 'scale(1)' },
        { transform: 'scale(1.12)' },
        { transform: 'scale(1)' },
      ],
      { duration: 420, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
    );
  };

  const handleAdd = (button: HTMLButtonElement) => {
    if (!product.available) return;
    add(product.id);
    animateToBag(button);
    setAdded(true);
    if (resetTimer.current) clearTimeout(resetTimer.current);
    resetTimer.current = setTimeout(() => setAdded(false), 1500);
  };

  return (
    <button
      className={`${className}${added ? ' is-added' : ''}`}
      type="button"
      disabled={!product.available}
      onClick={(event) => handleAdd(event.currentTarget)}
      aria-label={
        !product.available
          ? `${product.name} is unavailable`
          : added
            ? `${product.name} added to bag`
            : `Add ${product.name} to bag`
      }
    >
      {added ? (
        <>
          <svg viewBox="0 0 20 20" aria-hidden="true">
            <path d="m4 10 4 4 8-8" />
          </svg>
          {addedLabel}
        </>
      ) : !product.available ? (
        disabledLabel
      ) : (
        'Add to bag'
      )}
    </button>
  );
}
