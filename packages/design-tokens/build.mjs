/**
 * Design token generator.
 *
 * Reads tokens.json (single source of truth) and emits:
 *   - dist/index.ts   consumed by apps/web (Next.js)
 *   - dist/tokens.css custom properties for the marketing site
 *   - dist/tokens.dart consumed by apps/shop_pos (Flutter)
 *
 * Semantic tokens reference primitives via "{color.primitive.x}" and are
 * resolved here so no consumer ever has to perform alias lookups.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const tokensPath = join(__dirname, 'tokens.json');
const distDir = join(__dirname, 'dist');

/** Flatten a nested object into UPPER_SNAKE keys. */
function flatten(obj, prefix = '') {
  return Object.entries(obj).flatMap(([k, v]) =>
    v && typeof v === 'object' && !Array.isArray(v)
      ? flatten(v, `${prefix}${k}`)
      : [[`${prefix}${k}`.replace(/([A-Z])/g, '_$1').toUpperCase(), v]]
  );
}

const raw = JSON.parse(readFileSync(tokensPath, 'utf8'));

// Resolve "{color.primitive.x}" aliases.
function resolve(node) {
  if (Array.isArray(node)) return node.map(resolve);
  if (node && typeof node === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(node)) out[k] = resolve(v);
    return out;
  }
  if (typeof node === 'string') {
    const m = /^\{([^}]+)\}$/.exec(node);
    if (!m) return node;
    let cur = raw;
    for (const seg of m[1].split('.')) {
      if (cur == null) throw new Error(`Unresolved token alias: ${node}`);
      cur = cur[seg];
    }
    if (cur == null) throw new Error(`Unresolved token alias: ${node}`);
    return cur;
  }
  return node;
}

const colors = resolve(raw.color);
const { typography, spacing, radius, shadow, motion } = raw;

const HEADER = `// AUTO-GENERATED from packages/design-tokens/tokens.json
// Do not edit by hand. Run: npm run build:tokens
`;

const kebab = (k) => k.toLowerCase().replace(/_/g, '-');
const camel = (k) => k.replace(/([A-Z])/g, '_$1').toLowerCase();

// ---------------------------------------------------------------- TypeScript
function ts() {
  const semantic = flatten(colors.semantic);
  const primitive = flatten(colors.primitive);

  const tsLines = semantic
    .map(([k, v]) => `  ${k}: ${JSON.stringify(v)},`)
    .join('\n');

  const cssVars = [
    ...semantic,
    ...primitive.map(([k, v]) => [`PRIMITIVE_${k}`, v]),
  ]
    .map(([k, v]) => `  --color-${kebab(k)}: ${v};`)
    .join('\n');

  const section = (obj) =>
    Object.entries(obj)
      .map(([k, v]) => `  --${kebab(k)}: ${v};`)
      .join('\n');

  const index = `${HEADER}
/** Semantic colours. Fintech-grade: restrained, high-contrast, calm. */
export const color = {
${tsLines}
} as const;

/** Raw palette, for charts and status dots needing a specific shade. */
export const primitive = {
${primitive.map(([k, v]) => `  ${k}: ${JSON.stringify(v)},`).join('\n')}
} as const;

export const spacing = ${JSON.stringify(spacing)} as const;
export const radius = ${JSON.stringify(radius)} as const;
export const typography = ${JSON.stringify(typography)} as const;
export const shadow = ${JSON.stringify(shadow)} as const;
export const motion = ${JSON.stringify(motion)} as const;

/**
 * Format a KES amount for financial display.
 * Always 2dp, thousands separated. Money is never shown without decimals.
 */
export function formatKES(amount: number | string): string {
  const n = typeof amount === 'string' ? Number(amount) : amount;
  if (!Number.isFinite(n)) return 'KES 0.00';
  const sign = n < 0 ? '-' : '';
  return \`\${sign}KES \${Math.abs(n).toLocaleString('en-KE', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}\`;
}

/** Money value for a financial column, including negatives. */
export function formatAmount(amount: number | string): string {
  const n = typeof amount === 'string' ? Number(amount) : amount;
  if (!Number.isFinite(n)) return '0.00';
  return n.toLocaleString('en-KE', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export type ColorToken = keyof typeof color;
`;

  writeFileSync(join(distDir, 'index.ts'), index);
  writeFileSync(join(distDir, 'index.d.ts'), index);

  const css = `${HEADER}
:root {
${cssVars}
${section(spacing).replace(/--(\w+)/g, '--space-$1')}
${section(radius)}
${section(typography.size).replace(/--(\w+)/g, '--text-$1')}
${section(typography.weight).replace(/--(\w+)/g, '--weight-$1')}
${section(shadow)}
  --font-sans: ${typography.fontFamily};
  --font-mono: ${typography.monoFamily};
  --motion-fast: ${motion.fast};
  --motion-base: ${motion.base};
  --motion-easing: ${motion.easing};
}

*, *::before, *::after { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--color-bg-canvas);
  color: var(--color-text-primary);
  font-family: var(--font-sans);
  font-size: var(--text-base);
  -webkit-font-smoothing: antialiased;
}

/* Money must never use proportional digits. */
.tabular, .money { font-variant-numeric: tabular-nums; }
`;
  writeFileSync(join(distDir, 'tokens.css'), css);
}

// ---------------------------------------------------------------------- Dart
function dart() {
  const hex = (v) => `0xFF${String(v).replace('#', '').toUpperCase()}`;

  const semanticFields = Object.entries(colors.semantic)
    .map(([k, v]) => `  static const Color ${camel(k)} = Color(${hex(v)});`)
    .join('\n');

  const primitiveFields = Object.entries(colors.primitive)
    .map(([k, v]) => `  static const Color p${camel(k)} = Color(${hex(v)});`)
    .join('\n');

  const dartSrc = `${HEADER}
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'package:flutter/material.dart';

/// Design tokens for the Retail OS POS.
/// Mirrors packages/design-tokens/tokens.json exactly.
class AppColors {
  const AppColors._();

${semanticFields}

  /// Raw palette for charts and status dots.
${primitiveFields}
}

class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadius {
  const AppRadius._();
  static const BorderRadius sm = BorderRadius.all(Radius.circular(4));
  static const BorderRadius md = BorderRadius.all(Radius.circular(8));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(12));
}

class AppText {
  const AppText._();

  static const TextStyle xs = TextStyle(fontSize: 12, color: AppColors.text_tertiary);
  static const TextStyle sm = TextStyle(fontSize: 13, color: AppColors.text_secondary);
  static const TextStyle base = TextStyle(fontSize: 14, color: AppColors.text_primary);
  static const TextStyle md = TextStyle(fontSize: 16, color: AppColors.text_primary);
  static const TextStyle lg = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text_primary);
  static const TextStyle xl = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text_primary);
  static const TextStyle xxl = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text_primary);

  /// Large financial figure for totals. Tabular by construction.
  static const TextStyle amountXL = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: AppColors.text_primary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    letterSpacing: -0.5,
  );
  static const TextStyle amountLg = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.text_primary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
  static const TextStyle amountMd = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.text_primary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Thermal receipt / ledger reference text.
  static const TextStyle receipt = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    color: AppColors.text_primary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// Format a KES amount. Money is never rendered without 2 decimal places.
String formatKES(num amount, {bool showCurrency = true}) {
  final sign = amount < 0 ? '-' : '';
  final parts = amount.abs().toStringAsFixed(2).split('.');
  final grouped = _group(parts[0]);
  return '\$sign\${showCurrency ? 'KES ' : ''}\$grouped.\${parts[1]}';
}

String _group(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}

ThemeData buildRetailOsTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg_canvas,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent_primary,
      secondary: AppColors.accent_primary,
      surface: AppColors.bg_surface,
      error: AppColors.status_danger,
    ),
    dividerColor: AppColors.border_subtle,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text_primary,
      displayColor: AppColors.text_primary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg_inverse,
      foregroundColor: AppColors.text_inverse,
      elevation: 0,
    ),
  );
}
`;
  writeFileSync(join(distDir, 'tokens.dart'), dartSrc);
}

mkdirSync(distDir, { recursive: true });
ts();
dart();
console.log('[design-tokens] emitted index.ts, index.d.ts, tokens.css, tokens.dart');
