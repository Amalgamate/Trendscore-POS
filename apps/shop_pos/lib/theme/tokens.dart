// AUTO-GENERATED from packages/design-tokens/tokens.json
// Do not edit by hand. Run: npm run build:tokens

// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'package:flutter/material.dart';

/// Design tokens for the Retail OS POS.
/// Mirrors packages/design-tokens/tokens.json exactly.
class AppColors {
  const AppColors._();

  static const Color bg_canvas = Color(0xFFF9FAFB);
  static const Color bg_surface = Color(0xFFFFFFFF);
  static const Color bg_subtle = Color(0xFFF3F4F6);
  static const Color bg_inverse = Color(0xFF0A1628);
  static const Color border_subtle = Color(0xFFE5E7EB);
  static const Color border_strong = Color(0xFFD1D5DB);
  static const Color text_primary = Color(0xFF111827);
  static const Color text_secondary = Color(0xFF374151);
  static const Color text_tertiary = Color(0xFF6B7280);
  static const Color text_inverse = Color(0xFFFFFFFF);
  static const Color accent_primary = Color(0xFF0D9488);
  static const Color accent_light = Color(0xFFF0FDFA);
  static const Color accent_inverse = Color(0xFF0F1F3D);
  static const Color status_success = Color(0xFF16A34A);
  static const Color status_warning = Color(0xFFD97706);
  static const Color status_danger = Color(0xFFDC2626);
  static const Color status_info = Color(0xFF2563EB);

  /// Raw palette for charts and status dots.
  static const Color pnavy900 = Color(0xFF0A1628);
  static const Color pnavy800 = Color(0xFF0F1F3D);
  static const Color pnavy700 = Color(0xFF1B2F52);
  static const Color pslate900 = Color(0xFF111827);
  static const Color pslate700 = Color(0xFF374151);
  static const Color pslate500 = Color(0xFF6B7280);
  static const Color pslate400 = Color(0xFF9CA3AF);
  static const Color pslate300 = Color(0xFFD1D5DB);
  static const Color pslate200 = Color(0xFFE5E7EB);
  static const Color pslate100 = Color(0xFFF3F4F6);
  static const Color pslate050 = Color(0xFFF9FAFB);
  static const Color pwhite = Color(0xFFFFFFFF);
  static const Color pteal700 = Color(0xFF0F766E);
  static const Color pteal600 = Color(0xFF0D9488);
  static const Color pteal500 = Color(0xFF14B8A6);
  static const Color pteal050 = Color(0xFFF0FDFA);
  static const Color pgreen600 = Color(0xFF16A34A);
  static const Color pgreen050 = Color(0xFFF0FDF4);
  static const Color pred600 = Color(0xFFDC2626);
  static const Color pred050 = Color(0xFFFEF2F2);
  static const Color pamber600 = Color(0xFFD97706);
  static const Color pamber050 = Color(0xFFFFFBEB);
  static const Color pblue600 = Color(0xFF2563EB);
  static const Color pblue050 = Color(0xFFEFF6FF);
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
  return '$sign${showCurrency ? 'KES ' : ''}$grouped.${parts[1]}';
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
