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
  color: string;
  mark: string;
};

export function formatStorePrice(amount: number) {
  return `KES ${new Intl.NumberFormat('en-KE').format(amount)}`;
}
