import { describe, expect, it } from 'vitest';
import {
  CreateStorefrontOrderSchema,
  hashOrderSecret,
  normalizeStorefrontPhone,
  storefrontOrderRequestHash,
} from '../src/modules/storefront/storefront-orders.router';

const firstProductId = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const secondProductId = '3be2eb75-15a1-437d-890a-32f517357a4e';

const validOrder = {
  idempotencyKey: 'ab674c37-1be4-4cb7-a7d0-850ab680bb86',
  customerName: 'Amina Wanjiku',
  customerPhone: '0712345678',
  customerEmail: 'amina@example.com',
  fulfillmentMethod: 'DELIVERY' as const,
  deliveryAddress: 'Westlands, Nairobi',
  privacyAccepted: true as const,
  lines: [{ productId: firstProductId, quantity: 2 }],
};

describe('storefront order input', () => {
  it('accepts delivery orders with valid Kenyan contact details', () => {
    expect(CreateStorefrontOrderSchema.safeParse(validOrder).success).toBe(true);
  });

  it('accepts pickup without requiring a delivery address', () => {
    const result = CreateStorefrontOrderSchema.safeParse({
      ...validOrder,
      fulfillmentMethod: 'PICKUP',
      deliveryAddress: undefined,
    });
    expect(result.success).toBe(true);
  });

  it.each([
    { ...validOrder, customerPhone: '12345' },
    { ...validOrder, fulfillmentMethod: 'DELIVERY', deliveryAddress: undefined },
    { ...validOrder, privacyAccepted: false },
    {
      ...validOrder,
      lines: [
        { productId: firstProductId, quantity: 1 },
        { productId: firstProductId, quantity: 2 },
      ],
    },
    { ...validOrder, lines: [{ productId: firstProductId, quantity: 0 }] },
  ])('rejects invalid checkout data %#', (order) => {
    expect(CreateStorefrontOrderSchema.safeParse(order).success).toBe(false);
  });

  it('normalizes Kenyan mobile numbers to E.164 format', () => {
    expect(normalizeStorefrontPhone('0712345678')).toBe('+254712345678');
    expect(normalizeStorefrontPhone('254112345678')).toBe('+254112345678');
    expect(normalizeStorefrontPhone('+254712345678')).toBe('+254712345678');
  });

  it('hashes order access secrets and canonicalizes line ordering', () => {
    expect(hashOrderSecret('secret')).not.toBe('secret');
    const first = CreateStorefrontOrderSchema.parse({
      ...validOrder,
      lines: [
        { productId: secondProductId, quantity: 1 },
        { productId: firstProductId, quantity: 2 },
      ],
    });
    const second = CreateStorefrontOrderSchema.parse({
      ...validOrder,
      idempotencyKey: '071c4c9b-7ce4-4f4d-adb0-618c755a1be8',
      lines: [
        { productId: firstProductId, quantity: 2 },
        { productId: secondProductId, quantity: 1 },
      ],
    });
    expect(storefrontOrderRequestHash(first)).toBe(
      storefrontOrderRequestHash(second),
    );
  });
});
