export type StoreCategory =
  | 'All'
  | 'Accessories'
  | 'Home'
  | 'Pantry'
  | 'Personal care';

export type StoreProduct = {
  id: string;
  name: string;
  category: Exclude<StoreCategory, 'All'>;
  description: string;
  previewPrice: number;
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
    previewPrice: 850,
    color: 'sand',
    mark: 'TOTE',
  },
  {
    id: 'stoneware-coffee-cup',
    name: 'Stoneware coffee cup',
    category: 'Home',
    description: 'A simple cup for a slower morning.',
    previewPrice: 620,
    color: 'clay',
    mark: 'HOME',
  },
  {
    id: 'wildflower-honey',
    name: 'Wildflower honey',
    category: 'Pantry',
    description: 'A small-batch pantry staple, shown as a preview item.',
    previewPrice: 540,
    color: 'honey',
    mark: 'PANTRY',
  },
  {
    id: 'daily-care-set',
    name: 'Daily care set',
    category: 'Personal care',
    description: 'A considered set for your everyday routine.',
    previewPrice: 1250,
    color: 'sage',
    mark: 'CARE',
  },
  {
    id: 'canvas-weekender',
    name: 'Canvas weekender',
    category: 'Accessories',
    description: 'A versatile bag for short trips and long days.',
    previewPrice: 2400,
    color: 'blue',
    mark: 'CARRY',
  },
  {
    id: 'linen-table-runner',
    name: 'Linen table runner',
    category: 'Home',
    description: 'An easy layer for a shared table.',
    previewPrice: 1100,
    color: 'rose',
    mark: 'HOME',
  },
];

export function formatPreviewPrice(amount: number) {
  return `KES ${new Intl.NumberFormat('en-KE').format(amount)}`;
}
