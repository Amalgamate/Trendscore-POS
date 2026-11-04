import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/day_end_slip.dart';

void main() {
  test('day-end slip contains identifying details and summary totals', () {
    final html = buildDayEndSlipHtml(
      shopName: 'Guta Gala & Co',
      branch: 'Nairobi',
      date: '2026-11-03',
      till: 'Till 1',
      cashier: 'Grace',
      rows: const [(label: 'Net sales', value: 'KES 100.00')],
    );

    expect(html, contains('Guta Gala &amp; Co'));
    expect(html, contains('Business day: 2026-11-03'));
    expect(html, contains('Till: Till 1'));
    expect(html, contains('Cashier: Grace'));
    expect(html, contains('Net sales'));
    expect(html, contains('KES 100.00'));
    expect(html, contains('@page { size: 80mm auto;'));
  });

  test('day-end slip escapes markup in shop and row values', () {
    final html = buildDayEndSlipHtml(
      shopName: '<img src=x onerror=alert(1)>',
      branch: 'Main',
      date: '2026-11-03',
      till: 'Till 1',
      cashier: 'Cashier',
      rows: const [(label: '<script>', value: '"unsafe" & value')],
    );

    expect(html, contains('&lt;img src=x onerror=alert(1)&gt;'));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('&quot;unsafe&quot; &amp; value'));
    expect(html, isNot(contains('<span><script>')));
  });
}
