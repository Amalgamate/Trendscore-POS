import { describe, expect, it } from 'vitest';
import { buildContext, isSlugAvailable, resolveSlug, slugify, RESERVED_TEST } from '../../src/modules/provisioning/context.js';
import { createSecretGenerator } from '../../src/modules/provisioning/adapters.js';

describe('slugify', () => {
  it('lowercases and hyphenates', () => {
    expect(slugify('James Mini Mart')).toBe('james-mini-mart');
  });

  it('strips accents rather than dropping the letters', () => {
    // Kenyan shop names commonly carry accents.
    expect(slugify('Café Mwangi')).toBe('cafe-mwangi');
  });

  it('expands ampersands to "and"', () => {
    expect(slugify('Fish & Chips')).toBe('fish-and-chips');
  });

  it('collapses punctuation and runs of separators', () => {
    expect(slugify("James's  Store!!  Ltd")).toBe('james-s-store-ltd');
    expect(slugify('A---B')).toBe('a-b');
  });

  it('handles emoji without producing an empty label', () => {
    expect(slugify('🛒 Shop').length).toBeGreaterThan(0);
    expect(slugify('!!!')).toBe('shop');
    expect(slugify('')).toBe('shop');
  });

  it('never exceeds the DNS label limit', () => {
    const long = slugify('A'.repeat(200));
    expect(long.length).toBeLessThanOrEqual(63);
    expect(long.endsWith('-')).toBe(false);
  });

  it('is always a valid DNS label', () => {
    for (const name of ['James Mini Mart', '123 Store', '-leading', 'trailing-', 'Ünïcode Ltd']) {
      expect(slugify(name)).toMatch(/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/);
    }
  });
});

describe('slug availability', () => {
  it('refuses reserved infrastructure subdomains', () => {
    for (const reserved of RESERVED_TEST) {
      expect(isSlugAvailable(reserved, [])).toBe(false);
    }
  });

  it('refuses a taken slug', () => {
    expect(isSlugAvailable('taken', ['taken'])).toBe(false);
    expect(isSlugAvailable('free', ['taken'])).toBe(true);
  });

  it('suffixes deterministically when the preferred slug is taken', () => {
    const first = resolveSlug('James Mini Mart', ['james-mini-mart'], 'ACC123');
    expect(first).not.toBe('james-mini-mart');
    expect(first.startsWith('james-mini-mart-')).toBe(true);
    // Same inputs must yield the same subdomain, or a retry would move the
    // shop's address and break a link it already gave the customer.
    expect(resolveSlug('James Mini Mart', ['james-mini-mart'], 'ACC123')).toBe(first);
  });

  it('keeps suffixing until it finds a free slot', () => {
    const taken = ['james-mini-mart', 'james-mini-mart-acc1231'];
    const slug = resolveSlug('James Mini Mart', taken, 'ACC123');
    expect(taken).not.toContain(slug);
  });

  it('avoids a reserved name', () => {
    expect(resolveSlug('Admin', [], 'X1')).not.toBe('admin');
  });
});

describe('buildContext', () => {
  const input = {
    businessName: 'James Mini Mart',
    ownerName: 'James Kamau',
    ownerPhone: '254712345678',
    baseDomain: 'retailos.co.ke',
    backendImage: 'ghcr.io/acme/shop-api:0.1.0',
    frontendImage: 'ghcr.io/acme/shop-pos:0.1.0',
    version: '0.1.0',
    host: { name: 'ke-host-01', region: 'ke-nairobi-1', dockerSocketPath: '/var/run/docker.sock' },
    idFactory: () => '11111111-2222-3333-4444-555555555555',
  };

  it('derives a full hostname', () => {
    expect(buildContext(input).hostname).toBe('james-mini-mart.retailos.co.ke');
  });

  it('uses a short id derived from the instance id', () => {
    expect(buildContext(input).shortId).toBe('11111111');
  });

  it('scopes the instance directory to the short id', () => {
    expect(buildContext(input).instanceDir).toContain('11111111');
  });

  it('applies a default memory cap', () => {
    expect(buildContext(input).resourceMemoryMb).toBe(1024);
  });

  it('inherits the region from the host', () => {
    expect(buildContext(input).region).toBe('ke-nairobi-1');
  });
});

describe('secret generator', () => {
  const s = createSecretGenerator();

  it('produces distinct values on each call', () => {
    expect(s.password()).not.toBe(s.password());
    expect(s.token()).not.toBe(s.token());
  });

  it('generates passwords of the requested length', () => {
    expect(s.password(48)).toHaveLength(48);
  });

  it('omits characters that are ambiguous when read aloud', () => {
    // An operator will eventually read a password to support on the phone.
    for (let i = 0; i < 50; i++) {
      expect(s.password(64)).not.toMatch(/[0O1lI]/);
    }
  });

  it('generates url-safe tokens', () => {
    expect(s.token(24)).toMatch(/^[A-Za-z0-9_-]+$/);
  });
});
