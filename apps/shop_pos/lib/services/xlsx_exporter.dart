import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class XlsxSheet {
  const XlsxSheet(this.name, this.rows);

  final String name;
  final List<List<Object?>> rows;
}

Uint8List encodeXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) {
    throw ArgumentError.value(
      sheets,
      'sheets',
      'at least one worksheet required',
    );
  }
  final archive = Archive();

  void addFile(String path, String contents) {
    final bytes = utf8.encode(contents);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final sheetTypes = sheets.indexed.map((entry) {
    final index = entry.$1 + 1;
    return '<Override PartName="/xl/worksheets/sheet$index.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>';
  }).join();
  addFile(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '$sheetTypes</Types>',
  );
  addFile(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  addFile(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>${sheets.indexed.map((entry) {
          final index = entry.$1 + 1;
          return '<sheet name="${_escapeXml(entry.$2.name)}" sheetId="$index" r:id="rId$index"/>';
        }).join()}</sheets></workbook>',
  );
  addFile(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${sheets.indexed.map((entry) {
          final index = entry.$1 + 1;
          return '<Relationship Id="rId$index" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
              'Target="worksheets/sheet$index.xml"/>';
        }).join()}</Relationships>',
  );
  for (final entry in sheets.indexed) {
    final index = entry.$1 + 1;
    addFile('xl/worksheets/sheet$index.xml', _worksheetXml(entry.$2.rows));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _worksheetXml(List<List<Object?>> rows) {
  final rowXml = <String>[];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final cells = <String>[];
    for (
      var columnIndex = 0;
      columnIndex < rows[rowIndex].length;
      columnIndex++
    ) {
      final value = rows[rowIndex][columnIndex];
      final address = '${_columnName(columnIndex + 1)}${rowIndex + 1}';
      if (value is num) {
        if (!value.isFinite) {
          throw ArgumentError.value(value, 'cell', 'must be a finite number');
        }
        cells.add('<c r="$address"><v>$value</v></c>');
      } else {
        cells.add(
          '<c r="$address" t="inlineStr"><is><t xml:space="preserve">'
          '${_escapeXml(value?.toString() ?? '')}</t></is></c>',
        );
      }
    }
    rowXml.add('<row r="${rowIndex + 1}">${cells.join()}</row>');
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>${rowXml.join()}</sheetData></worksheet>';
}

String _columnName(int column) {
  var remaining = column;
  final letters = StringBuffer();
  while (remaining > 0) {
    remaining--;
    letters.writeCharCode(65 + remaining % 26);
    remaining ~/= 26;
  }
  return letters.toString().split('').reversed.join();
}

String _escapeXml(String value) => value
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
