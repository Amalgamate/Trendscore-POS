import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/tokens.dart';

void main() {
  group('formatKES', () {
    test('always renders two decimal places', () {
      // Money is never shown without decimals — a POS that displays
      // "KES 900" for a 900.00 sale is indistinguishable from 900.40.
      expect(formatKES(900), 'KES 900.00');
      expect(formatKES(0), 'KES 0.00');
      expect(formatKES(0.5), 'KES 0.50');
    });

    test('groups thousands', () {
      expect(formatKES(2450), 'KES 2,450.00');
      expect(formatKES(1234567.89), 'KES 1,234,567.89');
    });

    test('handles negatives for cash variance and ledger columns', () {
      expect(formatKES(-1500.5), '-KES 1,500.50');
    });

    test('can omit the currency symbol for table columns', () {
      expect(formatKES(2450, showCurrency: false), '2,450.00');
    });

    test('handles exact boundary values', () {
      expect(formatKES(999.999), 'KES 1,000.00');
      expect(formatKES(1000000), 'KES 1,000,000.00');
    });
  });

  group('design tokens', () {
    test('money styles are tabular so digits do not shift', () {
      expect(AppText.amountXL.fontFeatures, isNotNull);
      expect(AppText.amountXL.fontFeatures!.isNotEmpty, isTrue);
    });

    test('risk colour is used for danger, not for ordinary borders', () {
      // Red is reserved for risk/error/debt per the design direction.
      expect(AppColors.status_danger, isNot(AppColors.border_subtle));
      expect(AppColors.status_danger.toARGB32(), 0xFFDC2626);
      expect(AppColors.accent_primary.toARGB32(), 0xFF0D9488);
    });

    test('theme builds without error', () {
      expect(buildRetailOsTheme().useMaterial3, isTrue);
    });
  });
}
