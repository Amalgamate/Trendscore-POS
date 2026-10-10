import 'package:flutter/material.dart';

import 'tokens.dart';

/// Hand-written typography helpers that sit beside the generated tokens.
/// Sizes and weights come from tokens.dart (AppFontSize / AppType); change
/// tokens.json, never the numbers here.
class AppTypography {
  const AppTypography._();

  /// Tabular (fixed-width) digits so money and quantities never shift.
  static const List<FontFeature> tabular = <FontFeature>[FontFeature.tabularFigures()];

  /// Returns [style] with tabular figures switched on.
  static TextStyle withTabularFigures(TextStyle style) => style.copyWith(fontFeatures: tabular);

  /// The one place money and quantity text gets its style: tabular figures so
  /// columns of amounts never jitter. Views should use AppMoneyText (Phase 2)
  /// rather than building money styles by hand.
  static TextStyle money({TextStyle base = AppType.money, Color? color}) =>
      withTabularFigures(base).copyWith(color: color);

  /// Maps the Material text roles onto the Retail OS scale (14px body), sets
  /// Inter and applies palette colours so the same scale works in light and dark.
  /// Inter is bundled via pubspec.yaml (`npm run sync:fonts`).
  static TextTheme textTheme(TextTheme base, AppPalette p) {
    TextStyle? role(TextStyle? s, double size, FontWeight weight) =>
        s?.copyWith(fontSize: size, fontWeight: weight);

    final sized = base.copyWith(
      displaySmall: role(base.displaySmall, AppFontSize.display, FontWeight.w700),
      headlineMedium: role(base.headlineMedium, AppFontSize.xxl, FontWeight.w700),
      headlineSmall: role(base.headlineSmall, AppFontSize.xl, FontWeight.w600),
      titleLarge: role(base.titleLarge, AppFontSize.lg, FontWeight.w600),
      titleMedium: role(base.titleMedium, AppFontSize.md, FontWeight.w600),
      titleSmall: role(base.titleSmall, AppFontSize.base, FontWeight.w600),
      bodyLarge: role(base.bodyLarge, AppFontSize.md, FontWeight.w400),
      bodyMedium: role(base.bodyMedium, AppFontSize.base, FontWeight.w400),
      bodySmall: role(base.bodySmall, AppFontSize.xs, FontWeight.w400),
      labelLarge: role(base.labelLarge, AppFontSize.base, FontWeight.w500),
      labelMedium: role(base.labelMedium, AppFontSize.sm, FontWeight.w500),
      labelSmall: role(base.labelSmall, AppFontSize.xs, FontWeight.w500),
    );
    return sized.apply(
      fontFamily: AppFontFamily.sans,
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );
  }
}
