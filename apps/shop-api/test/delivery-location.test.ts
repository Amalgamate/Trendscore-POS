import { describe, expect, it } from 'vitest';
import { RiderLocationSchema } from '../src/modules/delivery/delivery.router';

describe('rider location updates', () => {
  const validLocation = {
    latitude: -1.286389,
    longitude: 36.817223,
    accuracy: 8.5,
    recordedAt: '2026-10-11T04:00:00.000Z',
  };

  it('accepts a timestamped coordinate within supported ranges', () => {
    expect(RiderLocationSchema.safeParse(validLocation).success).toBe(true);
  });

  it.each([
    { ...validLocation, latitude: -91 },
    { ...validLocation, longitude: 181 },
    { ...validLocation, accuracy: 0 },
    { ...validLocation, accuracy: 10001 },
    { ...validLocation, recordedAt: 'not-a-date' },
  ])('rejects invalid location data %#', (location) => {
    expect(RiderLocationSchema.safeParse(location).success).toBe(false);
  });
});
