export type StoreCategory =
  | 'All'
  | 'Accessories'
  | 'Home'
  | 'Pantry'
  | 'Personal care';

export type StoreProduct = {
  id: string;
  name: string;
  variantLabel?: string | null;
  category: string;
  description: string;
  salePrice: number;
  unit?: string;
  available: boolean;
  imageUrl?: string | null;
  preview?: boolean;
  color: string;
  mark: string;
};

export const STORE_CATEGORIES: StoreCategory[] = [
  'All',
  'Accessories',
  'Home',
  'Pantry',
  'Personal care',
];

export const PREVIEW_PRODUCTS: StoreProduct[] = [
  {
    id: 'woven-market-tote',
    name: 'Woven market tote',
    category: 'Accessories',
    description: 'A roomy everyday carry for market days.',
    salePrice: 850,
    available: true,
    color: 'sand',
    mark: 'TOTE',
  },
  {
    id: 'stoneware-coffee-cup',
    name: 'Stoneware coffee cup',
    category: 'Home',
    description: 'A simple cup for a slower morning.',
    salePrice: 620,
    available: true,
    color: 'clay',
    mark: 'HOME',
  },
  {
    id: 'wildflower-honey',
    name: 'Wildflower honey',
    category: 'Pantry',
    description: 'A small-batch pantry staple, shown as a preview item.',
    salePrice: 540,
    available: true,
    color: 'honey',
    mark: 'PANTRY',
  },
  {
    id: 'daily-care-set',
    name: 'Daily care set',
    category: 'Personal care',
    description: 'A considered set for your everyday routine.',
    salePrice: 1250,
    available: true,
    color: 'sage',
    mark: 'CARE',
  },
  {
    id: 'canvas-weekender',
    name: 'Canvas weekender',
    category: 'Accessories',
    description: 'A versatile bag for short trips and long days.',
    salePrice: 2400,
    available: true,
    color: 'blue',
    mark: 'CARRY',
  },
  {
    id: 'linen-table-runner',
    name: 'Linen table runner',
    category: 'Home',
    description: 'An easy layer for a shared table.',
    salePrice: 1100,
    available: true,
    color: 'rose',
    mark: 'HOME',
  },
];

export function formatStorePrice(amount: number) {
  return `KES ${new Intl.NumberFormat('en-KE').format(amount)}`;
}
