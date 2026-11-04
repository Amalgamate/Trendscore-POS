import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/units.dart';

void main() {
  test('formats fractional and sub-unit stock without floating point drift', () {
    expect(StockUnitFormatter.format(19750, 'l'), '19.75 L');
    expect(StockUnitFormatter.format(750, 'l'), '750 ml');
    expect(StockUnitFormatter.format(20000, 'l'), '20 L');
    expect(StockUnitFormatter.format(12340, 'kg'), '12.34 kg');
  });

  test('catalogue identifies same-family units and rejects cross-family units', () {
    expect(ProductUnitCatalogue.compatible('ml', 'l'), isTrue);
    expect(ProductUnitCatalogue.compatible('kg', 'g'), isTrue);
    expect(ProductUnitCatalogue.compatible('kg', 'l'), isFalse);
    expect(ProductUnitCatalogue.compatible('unknown', 'l'), isFalse);
  });

  test('converts measured quantities in integer base milli-units', () {
    expect(ProductUnitCatalogue.toBaseMilli(250, 'ml', 'l'), 250);
    expect(ProductUnitCatalogue.toBaseMilli(0.25, 'l', 'l'), 250);
    expect(ProductUnitCatalogue.toBaseMilli(1, 'dozen', 'pc'), 12000);
    expect(ProductUnitCatalogue.toBaseMilli(0.0001, 'l', 'l'), isNull);
    expect(ProductUnitCatalogue.toBaseMilli(1, 'kg', 'l'), isNull);
  });
}
