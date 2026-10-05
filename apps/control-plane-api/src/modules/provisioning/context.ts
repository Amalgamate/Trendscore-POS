import { randomUUID } from 'node:crypto';
import type { ProvisioningContext } from './types.js';

export interface BuildContextInput {
  businessName: string;
  ownerName: string;
  ownerPhone: string;
  ownerEmail?: string;
  businessType?: string;
  location?: string;
  /** Base domain, e.g. "retailos.co.ke". */
  baseDomain: string;
  backendImage: string;
  frontendImage: string;
  version: string;
  host: { name: string; region: string; dockerSocketPath: string };
  /** Root under which instance directories are created on the host. */
  instancesRoot?: string;
  resourceMemoryMb?: number;
  /** Injected for deterministic tests. */
  idFactory?: () => string;
}

/** Reserved subdomains that must never be handed to a shop. */
export const RESERVED_SLUGS = new Set([
  'www', 'mail', 'api', 'admin', 'app', 'pos', 'status', 'help',
  'support', 'docs', 'blog', 'cdn', 'assets', 'smtp', 'ftp', 'ns1', 'ns2',
  'dashboard', 'control', 'console', 'billing', 'shop', 'www2',
]);

/** Exposed for tests that assert the reserved list is enforced. */
export const RESERVED_TEST: string[] = [...RESERVED_SLUGS];

/**
 * Turn a business name into a DNS label.
 *
 * Handles the things Kenyan shop names actually contain: ampersands,
 * apostrophes, accents, emoji, leading digits, and runs of spaces.
 */
export function slugify(input: string): string {
  const base = input
    .normalize('NFKD')
    // Strip combining accents so "Café" becomes "cafe".
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-')
    .slice(0, 63)
    .replace(/-+$/g, '');

  // A DNS label must start with a letter or digit. "2024 Supplies" would
  // otherwise produce a leading digit, which is legal but confusing next
  // to our own numbered subdomains.
  return base || 'shop';
}

export function isSlugAvailable(slug: string, taken: Iterable<string>): boolean {
  if (RESERVED_SLUGS.has(slug)) return false;
  const set = new Set(taken);
  return !set.has(slug);
}

/** Find an available slug, suffixing a short discriminator if needed. */
export function resolveSlug(
  businessName: string,
  taken: Iterable<string>,
  suffixSource: string,
): string {
  const takenSet = new Set(taken);
  const preferred = slugify(businessName);

  if (isSlugAvailable(preferred, takenSet)) return preferred;

  // Deterministic suffix so the same business always lands on the same
  // subdomain across retries, rather than churning subdomains.
  const suffix = suffixSource.replace(/[^a-z0-9]/gi, '').toLowerCase().slice(0, 6) || 'shop';
  for (let n = 1; n <= 99; n++) {
    const candidate = `${preferred.slice(0, 55)}-${suffix}${n}`;
    if (isSlugAvailable(candidate, takenSet)) return candidate;
  }
  return `${preferred.slice(0, 50)}-${randomUUID().slice(0, 8)}`;
}

export function buildContext(input: BuildContextInput): ProvisioningContext {
  const idFactory = input.idFactory ?? randomUUID;
  const instanceId = idFactory();
  const shortId = instanceId.slice(0, 8);
  const slug = slugify(input.businessName);
  const instancesRoot = input.instancesRoot ?? '/var/lib/retail-os/instances';

  return {
    instanceId,
    shortId,
    businessName: input.businessName.trim(),
    slug,
    hostname: `${slug}.${input.baseDomain}`,
    ownerName: input.ownerName.trim(),
    ownerPhone: input.ownerPhone,
    ownerEmail: input.ownerEmail,
    businessType: input.businessType,
    location: input.location,
    backendImage: input.backendImage,
    frontendImage: input.frontendImage,
    version: input.version,
    host: input.host,
    instanceDir: `${instancesRoot}/${shortId}`,
    region: input.host.region,
    resourceMemoryMb: input.resourceMemoryMb ?? 1024,
  };
}
