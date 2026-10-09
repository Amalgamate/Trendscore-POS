// AUTO-GENERATED from packages/design-tokens/tokens.json
// Do not edit by hand. Run: npm run build:tokens

// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'package:flutter/material.dart';

/// Design tokens for the Retail OS POS.
/// Mirrors packages/design-tokens/tokens.json exactly.

// ---------------------------------------------------------------- Colour

/// LEGACY light-only static colours. They cannot switch with dark mode.
/// New code must use `context.palette` (AppPalette) instead; this class is
/// removed once the Phase 3-5 view migrations are complete.
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
  static const Color accent_primary_hover = Color(0xFF0F766E);
  static const Color accent_primary_pressed = Color(0xFF115E59);
  static const Color accent_light = Color(0xFFF0FDFA);
  static const Color accent_inverse = Color(0xFF0F1F3D);
  static const Color status_success = Color(0xFF16A34A);
  static const Color status_warning = Color(0xFFD97706);
  static const Color status_danger = Color(0xFFDC2626);
  static const Color status_info = Color(0xFF2563EB);
  static const Color status_success_light = Color(0xFFF0FDF4);
  static const Color status_warning_light = Color(0xFFFFFBEB);
  static const Color status_danger_light = Color(0xFFFEF2F2);
  static const Color status_info_light = Color(0xFFEFF6FF);

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
  static const Color pteal800 = Color(0xFF115E59);
  static const Color pteal700 = Color(0xFF0F766E);
  static const Color pteal600 = Color(0xFF0D9488);
  static const Color pteal500 = Color(0xFF14B8A6);
  static const Color pteal400 = Color(0xFF2DD4BF);
  static const Color pteal050 = Color(0xFFF0FDFA);
  static const Color pgreen600 = Color(0xFF16A34A);
  static const Color pgreen400 = Color(0xFF4ADE80);
  static const Color pgreen050 = Color(0xFFF0FDF4);
  static const Color pred600 = Color(0xFFDC2626);
  static const Color pred400 = Color(0xFFF87171);
  static const Color pred050 = Color(0xFFFEF2F2);
  static const Color pamber600 = Color(0xFFD97706);
  static const Color pamber400 = Color(0xFFFBBF24);
  static const Color pamber050 = Color(0xFFFFFBEB);
  static const Color pblue600 = Color(0xFF2563EB);
  static const Color pblue400 = Color(0xFF60A5FA);
  static const Color pblue050 = Color(0xFFEFF6FF);
  static const Color pink1000 = Color(0xFF0B0D0F);
  static const Color pink950 = Color(0xFF111315);
  static const Color pink900 = Color(0xFF181B1F);
  static const Color pink800 = Color(0xFF1E2227);
  static const Color pink700 = Color(0xFF2A2F35);
  static const Color pink600 = Color(0xFF3A4048);
  static const Color pink500 = Color(0xFF8A9099);
  static const Color pink400 = Color(0xFFA5ABB3);
  static const Color pink100 = Color(0xFFF4F5F6);
  static const Color pteal_dark = Color(0xFF0F2A27);
  static const Color pgreen_dark = Color(0xFF10261A);
  static const Color pred_dark = Color(0xFF2E1517);
  static const Color pamber_dark = Color(0xFF2B2110);
  static const Color pblue_dark = Color(0xFF13233F);
}

/// Theme-aware semantic colours. Registered on ThemeData.extensions and read
/// with `context.palette`. Light and dark are generated from the same keys,
/// so a colour can never exist in one mode and be missing in the other.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgSubtle,
    required this.bgInverse,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.accentPrimary,
    required this.accentPrimaryHover,
    required this.accentPrimaryPressed,
    required this.accentLight,
    required this.accentInverse,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusDanger,
    required this.statusInfo,
    required this.statusSuccessLight,
    required this.statusWarningLight,
    required this.statusDangerLight,
    required this.statusInfoLight,
  });

  final Color bgCanvas;
  final Color bgSurface;
  final Color bgSubtle;
  final Color bgInverse;
  final Color borderSubtle;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color accentPrimary;
  final Color accentPrimaryHover;
  final Color accentPrimaryPressed;
  final Color accentLight;
  final Color accentInverse;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusDanger;
  final Color statusInfo;
  final Color statusSuccessLight;
  final Color statusWarningLight;
  final Color statusDangerLight;
  final Color statusInfoLight;

  static const AppPalette light = AppPalette(
    bgCanvas: Color(0xFFF9FAFB),
    bgSurface: Color(0xFFFFFFFF),
    bgSubtle: Color(0xFFF3F4F6),
    bgInverse: Color(0xFF0A1628),
    borderSubtle: Color(0xFFE5E7EB),
    borderStrong: Color(0xFFD1D5DB),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF374151),
    textTertiary: Color(0xFF6B7280),
    textInverse: Color(0xFFFFFFFF),
    accentPrimary: Color(0xFF0D9488),
    accentPrimaryHover: Color(0xFF0F766E),
    accentPrimaryPressed: Color(0xFF115E59),
    accentLight: Color(0xFFF0FDFA),
    accentInverse: Color(0xFF0F1F3D),
    statusSuccess: Color(0xFF16A34A),
    statusWarning: Color(0xFFD97706),
    statusDanger: Color(0xFFDC2626),
    statusInfo: Color(0xFF2563EB),
    statusSuccessLight: Color(0xFFF0FDF4),
    statusWarningLight: Color(0xFFFFFBEB),
    statusDangerLight: Color(0xFFFEF2F2),
    statusInfoLight: Color(0xFFEFF6FF),
  );

  static const AppPalette dark = AppPalette(
    bgCanvas: Color(0xFF111315),
    bgSurface: Color(0xFF181B1F),
    bgSubtle: Color(0xFF1E2227),
    bgInverse: Color(0xFF0B0D0F),
    borderSubtle: Color(0xFF2A2F35),
    borderStrong: Color(0xFF3A4048),
    textPrimary: Color(0xFFF4F5F6),
    textSecondary: Color(0xFFA5ABB3),
    textTertiary: Color(0xFF8A9099),
    textInverse: Color(0xFFF4F5F6),
    accentPrimary: Color(0xFF14B8A6),
    accentPrimaryHover: Color(0xFF2DD4BF),
    accentPrimaryPressed: Color(0xFF0D9488),
    accentLight: Color(0xFF0F2A27),
    accentInverse: Color(0xFF1E2227),
    statusSuccess: Color(0xFF4ADE80),
    statusWarning: Color(0xFFFBBF24),
    statusDanger: Color(0xFFF87171),
    statusInfo: Color(0xFF60A5FA),
    statusSuccessLight: Color(0xFF10261A),
    statusWarningLight: Color(0xFF2B2110),
    statusDangerLight: Color(0xFF2E1517),
    statusInfoLight: Color(0xFF13233F),
  );

  @override
  AppPalette copyWith({
    Color? bgCanvas,
    Color? bgSurface,
    Color? bgSubtle,
    Color? bgInverse,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? accentPrimary,
    Color? accentPrimaryHover,
    Color? accentPrimaryPressed,
    Color? accentLight,
    Color? accentInverse,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusDanger,
    Color? statusInfo,
    Color? statusSuccessLight,
    Color? statusWarningLight,
    Color? statusDangerLight,
    Color? statusInfoLight,
  }) {
    return AppPalette(
      bgCanvas: bgCanvas ?? this.bgCanvas,
      bgSurface: bgSurface ?? this.bgSurface,
      bgSubtle: bgSubtle ?? this.bgSubtle,
      bgInverse: bgInverse ?? this.bgInverse,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentPrimaryHover: accentPrimaryHover ?? this.accentPrimaryHover,
      accentPrimaryPressed: accentPrimaryPressed ?? this.accentPrimaryPressed,
      accentLight: accentLight ?? this.accentLight,
      accentInverse: accentInverse ?? this.accentInverse,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusDanger: statusDanger ?? this.statusDanger,
      statusInfo: statusInfo ?? this.statusInfo,
      statusSuccessLight: statusSuccessLight ?? this.statusSuccessLight,
      statusWarningLight: statusWarningLight ?? this.statusWarningLight,
      statusDangerLight: statusDangerLight ?? this.statusDangerLight,
      statusInfoLight: statusInfoLight ?? this.statusInfoLight,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bgCanvas: Color.lerp(bgCanvas, other.bgCanvas, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgSubtle: Color.lerp(bgSubtle, other.bgSubtle, t)!,
      bgInverse: Color.lerp(bgInverse, other.bgInverse, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentPrimaryHover: Color.lerp(accentPrimaryHover, other.accentPrimaryHover, t)!,
      accentPrimaryPressed: Color.lerp(accentPrimaryPressed, other.accentPrimaryPressed, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      accentInverse: Color.lerp(accentInverse, other.accentInverse, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusSuccessLight: Color.lerp(statusSuccessLight, other.statusSuccessLight, t)!,
      statusWarningLight: Color.lerp(statusWarningLight, other.statusWarningLight, t)!,
      statusDangerLight: Color.lerp(statusDangerLight, other.statusDangerLight, t)!,
      statusInfoLight: Color.lerp(statusInfoLight, other.statusInfoLight, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The active palette. Falls back to light if no theme registered one.
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

// --------------------------------------------------------------- Spacing

/// 4px base. Named by pixel value (s4 = 4px) so a name can never disagree
/// with its number. Layouts live mostly in s8 / s12 / s16 / s24.
class AppSpacing {
  const AppSpacing._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  // LEGACY aliases (same values as before the scale was introduced).
  static const double xs = s4;
  static const double sm = s8;
  static const double md = s12;
  static const double lg = s16;
  static const double xl = s24;
  static const double xxl = s32;
  static const double xxxl = s48;
}

// ---------------------------------------------------------------- Radius

class AppRadius {
  const AppRadius._();

  static const BorderRadius xs = BorderRadius.all(Radius.circular(4));
  static const BorderRadius sm = BorderRadius.all(Radius.circular(6));
  static const BorderRadius md = BorderRadius.all(Radius.circular(8));
  static const BorderRadius tile = BorderRadius.all(Radius.circular(10));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(12));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(16));
  static const BorderRadius full = BorderRadius.all(Radius.circular(9999));
}

// ------------------------------------------------------------ Typography

class AppFontSize {
  const AppFontSize._();

  static const double xs = 12;
  static const double sm = 13;
  static const double base = 14;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 22;
  static const double xxl = 28;
  static const double xxxl = 34;
  static const double posPrice = 24;
  static const double posTotal = 32;
  static const double display = 32;
}

class AppFontFamily {
  const AppFontFamily._();
  static const String sans = 'Inter';
  static const String mono = 'JetBrains Mono';
}

/// Colour-free text styles. Colour comes from the theme / AppPalette so the
/// same style works in light and dark. Money styles are tabular by construction.
class AppType {
  const AppType._();

  static const TextStyle caption = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.xs, fontWeight: FontWeight.w400);
  static const TextStyle small = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.sm, fontWeight: FontWeight.w400);
  static const TextStyle body = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.base, fontWeight: FontWeight.w400);
  static const TextStyle bodyStrong = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.base, fontWeight: FontWeight.w600);
  static const TextStyle bodyLarge = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.md, fontWeight: FontWeight.w400);
  static const TextStyle title = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.lg, fontWeight: FontWeight.w600);
  static const TextStyle heading = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.xl, fontWeight: FontWeight.w600);
  static const TextStyle headline = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.xxl, fontWeight: FontWeight.w700);
  static const TextStyle display = TextStyle(fontFamily: AppFontFamily.sans, fontSize: AppFontSize.display, fontWeight: FontWeight.w700, letterSpacing: -0.5);

  /// Product tile price.
  static const TextStyle posPrice = TextStyle(
    fontFamily: AppFontFamily.sans,
    fontSize: AppFontSize.posPrice,
    fontWeight: FontWeight.w600,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Cart TOTAL.
  static const TextStyle posTotal = TextStyle(
    fontFamily: AppFontFamily.sans,
    fontSize: AppFontSize.posTotal,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Money inside tables and lists.
  static const TextStyle money = TextStyle(
    fontFamily: AppFontFamily.sans,
    fontSize: AppFontSize.base,
    fontWeight: FontWeight.w500,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
  static const TextStyle moneyStrong = TextStyle(
    fontFamily: AppFontFamily.sans,
    fontSize: AppFontSize.base,
    fontWeight: FontWeight.w600,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// SKU, barcode, receipt and reference numbers.
  static const TextStyle mono = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontSize: AppFontSize.sm,
    fontWeight: FontWeight.w400,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// LEGACY text styles with light-mode colour baked in. They cannot follow
/// dark mode. Replace with AppType + palette colour during the Phase 3-5
/// view migrations, then delete.
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

// ---------------------------------------------------------------- Shadow

/// Flat by default. `sm` is for floating layers only; `md` for menus/dialogs.
class AppShadow {
  const AppShadow._();

  static const List<BoxShadow> sm = <BoxShadow>[BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color.fromRGBO(16, 24, 40, 0.05))];
  static const List<BoxShadow> md = <BoxShadow>[BoxShadow(offset: Offset(0, 4), blurRadius: 12, color: Color.fromRGBO(16, 24, 40, 0.08))];
}

// ---------------------------------------------------------------- Motion

/// Motion communicates state only. 120-200ms.
class AppMotion {
  const AppMotion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Curve easing = Cubic(0.2, 0, 0, 1);
}

// ----------------------------------------------------------------- Money

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
