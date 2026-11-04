import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/stock_audit_export.dart';
import 'package:shop_pos/services/stock_audit_print.dart';
import 'package:shop_pos/services/xlsx_exporter.dart';

void main() {
  test(
    'A4 stock audit includes audit columns, totals, metadata and paging',
    () {
      final html = buildStockAuditHtml(
        shopName: 'Guta Gala',
        printedAt: DateTime(2026, 11, 3, 10, 30),
        products: [
          {
            'name': 'Milk',
            'sku': 'MILK-1',
            'category': 'Dairy',
            'quantity': 19.75,
            'unit': 'L',
            'costPrice': 200,
            'valueAtCost': 3950,
            'valueAtSellingPrice': 5925,
            'varianceFlag': false,
          },
        ],
      );

      expect(html, contains('size: A4 portrait'));
      expect(html, contains('Counted'));
      expect(html, contains('Difference'));
      expect(html, contains('Guta Gala'));
      expect(html, contains('2026-11-03 10:30'));
      expect(html, contains('Page " counter(page)'));
      expect(html, contains('3950.00'));
      expect(html, contains('5925.00'));
    },
  );

  test('stock audit escapes product and shop markup', () {
    final html = buildStockAuditHtml(
      shopName: '<script>alert(1)</script>',
      printedAt: DateTime(2026),
      products: [
        {
          'name': '<img src=x>',
          'quantity': 0,
          'valueAtCost': 0,
          'valueAtSellingPrice': 0,
          'varianceFlag': true,
        },
      ],
    );
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('&lt;img src=x&gt;'));
    expect(html, contains('VARIANCE'));
    expect(html, isNot(contains('<img src=x>')));
  });

  test('100+ product print, Excel and CSV outputs retain units and every row', () {
    final products = List.generate(
      125,
      (index) => <String, dynamic>{
        'name': 'TEST Product ${index + 1}',
        'sku': 'TEST-${(index + 1).toString().padLeft(3, '0')}',
        'category': index.isEven ? 'Dairy' : 'Household',
        'quantity': 19.75,
        'unit': index.isEven ? 'L' : 'pc',
        'salePrice': 300.0,
        'costPrice': 200.0,
        'valueAtCost': 3950.0,
        'valueAtSellingPrice': 5925.0,
        'varianceFlag': false,
      },
    );

    final printHtml = buildStockAuditHtml(
      shopName: 'Guta Gala TEST ONLY',
      printedAt: DateTime(2026, 11, 3, 10, 30),
      products: products,
    );
    expect(printHtml, contains('Products: 125'));
    expect(RegExp(r'<tr><td>TEST Product ').allMatches(printHtml), hasLength(125));
    expect(printHtml, contains('19.75 L'));
    expect(printHtml, contains('19.75 pc'));
    expect(printHtml, contains('thead { display: table-header-group; }'));
    expect(printHtml, contains('tr { break-inside: avoid; }'));
    expect(printHtml, contains('493750.00'));
    expect(printHtml, contains('Retail value: KES 740625.00'));

    final rows = buildStockAuditExportRows(products);
    expect(rows, hasLength(126));
    expect(rows.first, contains('Unit'));
    expect(rows[1], contains('L'));
    expect(rows[2], contains('pc'));

    final workbook = ZipDecoder().decodeBytes(
      encodeXlsx([XlsxSheet('Stock Audit', rows)]),
    );
    final sheet = utf8.decode(
      workbook.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(RegExp(r'<row r="\d+">').allMatches(sheet), hasLength(126));
    expect(sheet, contains('TEST Product 125'));
    expect(sheet, contains('19.75'));

    final csv = utf8.decode(buildStockAuditCsvBytes(rows));
    expect(csv.split('\r\n'), hasLength(126));
    expect(csv, contains('"TEST Product 125"'));
    expect(csv, contains('"19.75"'));
    expect(csv, contains('"pc"'));
  });
}
