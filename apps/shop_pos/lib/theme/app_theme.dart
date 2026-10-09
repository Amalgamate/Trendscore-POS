import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'tokens.dart';

/// Light theme. Hand-written; colours, radii and sizes come from the
/// generated tokens.dart. Change tokens.json / build.mjs for values.
ThemeData buildRetailOsTheme() => _build(AppPalette.light, Brightness.light);

/// Dark theme, built from the same code path as light so the two cannot drift.
ThemeData buildRetailOsDarkTheme() => _build(AppPalette.dark, Brightness.dark);

ThemeData _build(AppPalette p, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

  // Text on the accent / danger fills. Light uses white; dark uses the
  // near-black ink because the lifted dark accent is too light for white text.
  final onFill = isDark ? p.bgInverse : p.textInverse;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accentPrimary,
    onPrimary: onFill,
    secondary: p.accentPrimary,
    onSecondary: onFill,
    error: p.statusDanger,
    onError: onFill,
    surface: p.bgSurface,
    onSurface: p.textPrimary,
    outline: p.borderStrong,
    outlineVariant: p.borderSubtle,
    surfaceContainerLowest: p.bgSurface,
    surfaceContainerLow: p.bgCanvas,
    surfaceContainer: p.bgSubtle,
    surfaceContainerHigh: p.bgSubtle,
    surfaceContainerHighest: p.bgSubtle,
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: BorderSide(color: color, width: width),
      );

  const buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: AppRadius.md),
  );
  const buttonPadding = WidgetStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.symmetric(horizontal: AppSpacing.s16),
  );
  const buttonText = WidgetStatePropertyAll<TextStyle>(
    TextStyle(fontSize: AppFontSize.base, fontWeight: FontWeight.w600),
  );
  const buttonMin = WidgetStatePropertyAll<Size>(Size(0, 40));

  bool isDisabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
  bool isHover(Set<WidgetState> s) => s.contains(WidgetState.hovered);
  bool isPressed(Set<WidgetState> s) => s.contains(WidgetState.pressed);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bgCanvas,
    textTheme: AppTypography.textTheme(base.textTheme, p),
    dividerTheme: DividerThemeData(color: p.borderSubtle, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bgInverse,
      foregroundColor: p.textInverse,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.bgSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s12,
      ),
      hintStyle: TextStyle(color: p.textTertiary),
      labelStyle: TextStyle(color: p.textSecondary),
      helperStyle: TextStyle(color: p.textTertiary, fontSize: AppFontSize.xs),
      errorStyle: TextStyle(color: p.statusDanger, fontSize: AppFontSize.xs),
      border: inputBorder(p.borderStrong),
      enabledBorder: inputBorder(p.borderStrong),
      disabledBorder: inputBorder(p.borderSubtle),
      focusedBorder: inputBorder(p.accentPrimary, 1.5),
      errorBorder: inputBorder(p.statusDanger),
      focusedErrorBorder: inputBorder(p.statusDanger, 1.5),
    ),
    cardTheme: CardThemeData(
      color: p.bgSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
        side: BorderSide(color: p.borderSubtle),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll<double>(0),
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
        backgroundColor: WidgetStateProperty.resolveWith<Color>((s) {
          if (isDisabled(s)) return p.bgSubtle;
          if (isPressed(s)) return p.accentPrimaryPressed;
          if (isHover(s)) return p.accentPrimaryHover;
          return p.accentPrimary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (s) => isDisabled(s) ? p.textTertiary : onFill,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll<double>(0),
        minimumSize: buttonMin,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
        side: WidgetStateProperty.resolveWith<BorderSide>(
          (s) => BorderSide(color: isDisabled(s) ? p.borderSubtle : p.borderStrong),
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (s) => (isHover(s) || isPressed(s)) && !isDisabled(s) ? p.bgSubtle : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (s) => isDisabled(s) ? p.textTertiary : p.textPrimary,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: buttonMin,
        shape: buttonShape,
        textStyle: buttonText,
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (s) => isDisabled(s) ? p.textTertiary : p.accentPrimary,
        ),
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll<Color>(p.bgSubtle),
      headingRowHeight: 44,
      dataRowMinHeight: 44,
      dataRowMaxHeight: 48,
      dividerThickness: 1,
      headingTextStyle: TextStyle(
        fontSize: AppFontSize.sm,
        fontWeight: FontWeight.w600,
        color: p.textSecondary,
      ),
      dataTextStyle: TextStyle(fontSize: AppFontSize.base, color: p.textPrimary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
        side: BorderSide(color: p.borderSubtle),
      ),
      titleTextStyle: TextStyle(
        fontSize: AppFontSize.lg,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
      contentTextStyle: TextStyle(fontSize: AppFontSize.base, color: p.textSecondary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bgSurface,
      modalBackgroundColor: p.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.lg.topLeft),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.accentInverse,
      contentTextStyle: TextStyle(fontSize: AppFontSize.base, color: p.textInverse),
      actionTextColor: AppColors.pteal400,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: TextStyle(fontSize: AppFontSize.xs, color: p.textInverse),
      decoration: BoxDecoration(
        color: p.bgInverse,
        borderRadius: AppRadius.sm,
        border: isDark ? Border.all(color: p.borderStrong) : null,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[p],
  );
}
