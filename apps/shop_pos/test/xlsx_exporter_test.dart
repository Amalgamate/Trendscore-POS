import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/xlsx_exporter.dart';

void main() {
  test('encodes worksheet values as a valid Excel workbook archive', () {
    final bytes = encodeXlsx([
      const XlsxSheet('Summary', [
        ['Metric', 'Amount'],
        ['Gross & net', 1234.5],
        ['<shop>', 'ShopSmart'],
      ]),
    ]);
    final archive = ZipDecoder().decodeBytes(bytes);
    final workbook = archive.findFile('xl/workbook.xml');
    final worksheet = archive.findFile('xl/worksheets/sheet1.xml');
    final contentTypes = archive.findFile('[Content_Types].xml');

    expect(workbook, isNotNull);
    expect(worksheet, isNotNull);
    expect(contentTypes, isNotNull);
    final worksheetXml = utf8.decode(worksheet!.content as List<int>);
    expect(worksheetXml, contains('Gross &amp; net'));
    expect(worksheetXml, contains('&lt;shop&gt;'));
    expect(worksheetXml, contains('<v>1234.5</v>'));
  });
}
