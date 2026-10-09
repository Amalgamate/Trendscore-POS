import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/app_theme.dart';
import 'package:shop_pos/theme/app_typography.dart';
import 'package:shop_pos/theme/tokens.dart';

void main() {
  group('typography', () {
    test('theme text roles use Inter at the 14px body size', () {
      for (final t in [buildRetailOsTheme(), buildRetailOsDarkTheme()]) {
        expect(t.textTheme.bodyMedium!.fontFamily, AppFontFamily.sans);
        expect(t.textTheme.bodyMedium!.fontSize, 14);
        expect(t.textTheme.titleLarge!.fontWeight, FontWeight.w600);
      }
    });

    test('theme text colour follows the palette', () {
      expect(buildRetailOsTheme().textTheme.bodyMedium!.color, AppPalette.light.textPrimary);
      expect(buildRetailOsDarkTheme().textTheme.bodyMedium!.color, AppPalette.dark.textPrimary);
    });

    test('money() is tabular and accepts a colour', () {
      final s = AppTypography.money(color: const Color(0xFF123456));
      expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(s.color, const Color(0xFF123456));
    });

    test('all money-oriented AppType styles are tabular', () {
      for (final s in [
        AppType.posPrice,
        AppType.posTotal,
        AppType.money,
        AppType.moneyStrong,
        AppType.mono,
      ]) {
        expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
    });

    test('mono style uses JetBrains Mono', () {
      expect(AppType.mono.fontFamily, AppFontFamily.mono);
      expect(AppFontFamily.mono, 'JetBrains Mono');
    });
  });

  group('bundled fonts', () {
    test('every font asset declared in pubspec.yaml exists on disk', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final assets = RegExp(r'asset:\s*(assets/fonts/\S+\.ttf)')
          .allMatches(pubspec)
          .map((m) => m.group(1)!)
          .toList();
      expect(assets, isNotEmpty, reason: 'no fonts declared in pubspec.yaml');
      final missing = assets.where((a) => !File(a).existsSync()).toList();
      expect(missing, isEmpty, reason: 'Run `npm run sync:fonts` at the repo root. Missing: $missing');
    });

    test('both font families are declared', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: ${AppFontFamily.sans}'));
      expect(pubspec, contains('family: ${AppFontFamily.mono}'));
    });
  });
}
