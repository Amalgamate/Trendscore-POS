'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { PREVIEW_PRODUCTS } from './store-data';

type CartLine = { productId: string; quantity: number };
type CartContextValue = {
  items: CartLine[];
  itemCount: number;
  subtotal: number;
  hydrated: boolean;
  storageError: boolean;
  add: (productId: string) => void;
  setQuantity: (productId: string, quantity: number) => void;
  remove: (productId: string) => void;
};

const storageKey = 'shopsmart-storefront-preview-cart';
const CartContext = createContext<CartContextValue | null>(null);

export function StoreCartProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<CartLine[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const [storageError, setStorageError] = useState(false);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(storageKey);
      if (raw) {
        const parsed: unknown = JSON.parse(raw);
        if (
          Array.isArray(parsed) &&
          parsed.every(
            (line) =>
              typeof line?.productId === 'string' &&
              Number.isInteger(line?.quantity) &&
              line.quantity > 0 &&
              PREVIEW_PRODUCTS.some((product) => product.id === line.productId),
          )
        ) {
          setItems(parsed);
        } else {
          window.localStorage.removeItem(storageKey);
        }
      }
    } catch (error) {
      console.error('Could not read the saved storefront preview bag.', error);
      setStorageError(true);
    } finally {
      setHydrated(true);
    }
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    try {
      window.localStorage.setItem(storageKey, JSON.stringify(items));
      setStorageError(false);
    } catch (error) {
      console.error('Could not save the storefront preview bag.', error);
      setStorageError(true);
    }
  }, [hydrated, items]);

  const add = useCallback((productId: string) => {
    setItems((current) => {
      const existing = current.find((line) => line.productId === productId);
      if (existing) {
        return current.map((line) =>
          line.productId === productId
            ? { ...line, quantity: line.quantity + 1 }
            : line,
        );
      }
      return [...current, { productId, quantity: 1 }];
    });
  }, []);

  const setQuantity = useCallback((productId: string, quantity: number) => {
    setItems((current) =>
      quantity < 1
        ? current.filter((line) => line.productId !== productId)
        : current.map((line) =>
            line.productId === productId ? { ...line, quantity } : line,
          ),
    );
  }, []);

  const remove = useCallback(
    (productId: string) => setQuantity(productId, 0),
    [setQuantity],
  );

  const value = useMemo(() => {
    const itemCount = items.reduce((sum, line) => sum + line.quantity, 0);
    const subtotal = items.reduce((sum, line) => {
      const product = PREVIEW_PRODUCTS.find((item) => item.id === line.productId);
      return sum + (product?.previewPrice ?? 0) * line.quantity;
    }, 0);
    return {
      items,
      itemCount,
      subtotal,
      hydrated,
      storageError,
      add,
      setQuantity,
      remove,
    };
  }, [items, hydrated, storageError, add, setQuantity, remove]);

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useStoreCart() {
  const value = useContext(CartContext);
  if (!value) throw new Error('useStoreCart must be used within StoreCartProvider');
  return value;
}
