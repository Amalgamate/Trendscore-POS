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
import { PREVIEW_PRODUCTS, type StoreProduct } from './store-data';

type CartLine = { productId: string; quantity: number };
type CatalogState = 'loading' | 'live' | 'sample' | 'error';
export type StorefrontProfile = {
  storeName: string;
  description: string;
  phone: string;
  email: string;
  address: string;
  county: string;
  logoUrl: string;
  openingHours: string;
  deliveryEnabled: boolean;
  deliveryDetails: string;
  pickupEnabled: boolean;
  pickupDetails: string;
  policies: {
    delivery: string;
    returns: string;
    privacy: string;
    terms: string;
  };
};

const EMPTY_STOREFRONT_PROFILE: StorefrontProfile = {
  storeName: 'ShopSmart Online Store',
  description: '',
  phone: '',
  email: '',
  address: '',
  county: '',
  logoUrl: '',
  openingHours: '',
  deliveryEnabled: false,
  deliveryDetails: '',
  pickupEnabled: false,
  pickupDetails: '',
  policies: { delivery: '', returns: '', privacy: '', terms: '' },
};

type CartContextValue = {
  products: StoreProduct[];
  catalogState: CatalogState;
  storefrontProfile: StorefrontProfile;
  items: CartLine[];
  itemCount: number;
  subtotal: number;
  hydrated: boolean;
  storageError: boolean;
  add: (productId: string) => void;
  setQuantity: (productId: string, quantity: number) => void;
  remove: (productId: string) => void;
};

const storageKey = 'shopsmart-storefront-cart';
const CartContext = createContext<CartContextValue | null>(null);

export function StoreCartProvider({ children }: { children: ReactNode }) {
  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [catalogState, setCatalogState] = useState<CatalogState>('loading');
  const [storefrontProfile, setStorefrontProfile] = useState<StorefrontProfile>(
    EMPTY_STOREFRONT_PROFILE,
  );
  const [items, setItems] = useState<CartLine[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const [storageError, setStorageError] = useState(false);

  useEffect(() => {
    const apiBase = process.env.NEXT_PUBLIC_SHOP_API_BASE_URL ?? '/api';
    fetch(`${apiBase.replace(/\/+$/, '')}/products/storefront`, {
      cache: 'no-store',
    })
      .then(async (response) => {
        if (!response.ok) throw new Error(`Store catalog request failed (${response.status}).`);
        const payload: unknown = await response.json();
        if (
          typeof payload !== 'object' ||
          payload === null ||
          !('data' in payload) ||
          !Array.isArray(payload.data)
        ) {
          throw new Error('Store catalog response has an invalid shape.');
        }
        const catalog = payload.data.map((entry): StoreProduct => {
          if (
            typeof entry !== 'object' ||
            entry === null ||
            !('id' in entry) ||
            typeof entry.id !== 'string' ||
            !('name' in entry) ||
            typeof entry.name !== 'string' ||
            !('category' in entry) ||
            typeof entry.category !== 'string' ||
            !('salePrice' in entry) ||
            typeof entry.salePrice !== 'number' ||
            !('available' in entry) ||
            typeof entry.available !== 'boolean'
          ) {
            throw new Error('Store catalog contains an invalid product.');
          }
          return {
            id: entry.id,
            name: entry.name,
            variantLabel:
              'variantLabel' in entry && typeof entry.variantLabel === 'string'
                ? entry.variantLabel
                : null,
            category: entry.category,
            description:
              'description' in entry && typeof entry.description === 'string'
                ? entry.description
                : '',
            salePrice: entry.salePrice,
            unit: 'unit' in entry && typeof entry.unit === 'string' ? entry.unit : 'pc',
            available: entry.available,
            imageUrl:
              'imageUrl' in entry && typeof entry.imageUrl === 'string'
                ? `${apiBase.replace(/\/+$/, '')}/${entry.imageUrl.replace(/^\/+/, '')}`
                : null,
            color: 'sage',
            mark: entry.category.toUpperCase(),
          };
        });
        setProducts(catalog);
        setCatalogState('live');
      })
      .catch((error: unknown) => {
        console.error('Could not load the published shop catalog.', error);
        if (process.env.NODE_ENV !== 'production') {
          setProducts(
            PREVIEW_PRODUCTS.map((product) => ({ ...product, preview: true })),
          );
          setCatalogState('sample');
        } else {
          setProducts([]);
          setCatalogState('error');
        }
      });
  }, []);

  useEffect(() => {
    const apiBase = process.env.NEXT_PUBLIC_SHOP_API_BASE_URL ?? '/api';
    fetch(`${apiBase.replace(/\/+$/, '')}/business/storefront`, {
      cache: 'no-store',
    })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error(`Store profile request failed (${response.status}).`);
        }
        const payload: unknown = await response.json();
        if (
          typeof payload !== 'object' ||
          payload === null ||
          !('data' in payload) ||
          typeof payload.data !== 'object' ||
          payload.data === null
        ) {
          throw new Error('Store profile response has an invalid shape.');
        }
        const data = payload.data as Record<string, unknown>;
        const policies =
          typeof data.policies === 'object' && data.policies !== null
            ? (data.policies as Record<string, unknown>)
            : {};
        const stringValue = (value: unknown) =>
          typeof value === 'string' ? value : '';
        if (typeof data.storeName !== 'string' || !data.storeName.trim()) {
          throw new Error('Store profile does not include a valid store name.');
        }
        setStorefrontProfile({
          storeName: data.storeName,
          description: stringValue(data.description),
          phone: stringValue(data.phone),
          email: stringValue(data.email),
          address: stringValue(data.address),
          county: stringValue(data.county),
          logoUrl: stringValue(data.logoUrl),
          openingHours: stringValue(data.openingHours),
          deliveryEnabled: data.deliveryEnabled === true,
          deliveryDetails: stringValue(data.deliveryDetails),
          pickupEnabled: data.pickupEnabled === true,
          pickupDetails: stringValue(data.pickupDetails),
          policies: {
            delivery: stringValue(policies.delivery),
            returns: stringValue(policies.returns),
            privacy: stringValue(policies.privacy),
            terms: stringValue(policies.terms),
          },
        });
      })
      .catch((error: unknown) => {
        console.error('Could not load the public storefront profile.', error);
        setStorefrontProfile(EMPTY_STOREFRONT_PROFILE);
      });
  }, []);

  useEffect(() => {
    if (catalogState === 'loading') return;
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
              products.some((product) => product.id === line.productId),
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
  }, [catalogState, products]);

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
      const product = products.find((item) => item.id === line.productId);
      return sum + (product?.salePrice ?? 0) * line.quantity;
    }, 0);
    return {
      products,
      catalogState,
      storefrontProfile,
      items,
      itemCount,
      subtotal,
      hydrated,
      storageError,
      add,
      setQuantity,
      remove,
    };
  }, [
    products,
    catalogState,
    storefrontProfile,
    items,
    hydrated,
    storageError,
    add,
    setQuantity,
    remove,
  ]);

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useStoreCart() {
  const value = useContext(CartContext);
  if (!value) throw new Error('useStoreCart must be used within StoreCartProvider');
  return value;
}
