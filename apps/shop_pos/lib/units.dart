/// Integer-safe display helpers for inventory quantities.
///
/// Stored stock is represented in thousandths of the product's base unit.
/// Keeping formatting here avoids double artefacts such as `19.750000001`.
class StockUnitFormatter {
  const StockUnitFormatter._();

  static String format(int milliUnits, String unit) {
    final symbol = _symbols[unit] ?? unit;
    final abs = milliUnits.abs();
    final whole = abs ~/ 1000;
    final fraction = abs % 1000;
    final sign = milliUnits < 0 ? '-' : '';

    if (fraction == 0) return '$sign$whole $symbol';

    if (unit == 'l' && abs < 1000) return '$sign$abs ml';
    if (unit == 'kg' && abs < 1000) return '$sign$abs g';

    final decimal = fraction.toString().padLeft(3, '0').replaceFirst(
      RegExp(r'0+$'),
      '',
    );
    return '$sign$whole.$decimal $symbol';
  }

  static const _symbols = {'ml': 'ml', 'l': 'L', 'g': 'g', 'kg': 'kg', 'pc': 'pc'};
}

/// Unit IDs and factors mirror `packages/units/units.json`.
/// Keep IDs stable: they are persisted with products and sale lines.
class ProductUnitCatalogue {
  const ProductUnitCatalogue._();

  static const families = <String, List<String>>{
    'volume': ['ml', 'l'],
    'mass': ['g', 'kg'],
    'count': ['pc', 'dozen'],
  };

  static const factorsToBase = <String, int>{
    'ml': 1,
    'l': 1000,
    'g': 1,
    'kg': 1000,
    'pc': 1,
    'dozen': 12,
  };

  static const symbols = <String, String>{
    'ml': 'ml',
    'l': 'L',
    'g': 'g',
    'kg': 'kg',
    'pc': 'pc',
    'dozen': 'dozen',
  };

  static String familyOf(String unit) => families.entries
      .firstWhere((entry) => entry.value.contains(unit), orElse: () => const MapEntry('', []))
      .key;

  static bool compatible(String soldUnit, String baseUnit) =>
      familyOf(soldUnit).isNotEmpty && familyOf(soldUnit) == familyOf(baseUnit);

  /// Converts a quantity with at most 3 decimal places to milli-units of the
  /// product's base unit, using integer factors from the shared catalogue.
  static int? toBaseMilli(num quantity, String soldUnit, String baseUnit) {
    if (!compatible(soldUnit, baseUnit) || quantity <= 0) return null;
    final quantityMilli = (quantity * 1000).round();
    if ((quantityMilli / 1000 - quantity).abs() > 1e-9) return null;
    final numerator = quantityMilli * factorsToBase[soldUnit]!;
    final denominator = factorsToBase[baseUnit]!;
    if (numerator % denominator != 0) return null;
    return numerator ~/ denominator;
  }
}
