import 'dart:convert';
import 'dart:typed_data';

List<List<Object?>> buildStockAuditExportRows(
  List<Map<String, dynamic>> products,
) => [
  const [
    'Product',
    'SKU',
    'Category',
    'Quantity',
    'Unit',
    'Selling price (KES)',
    'Cost price (KES)',
    'Value at cost (KES)',
    'Value at selling price (KES)',
    'Counted',
    'Difference',
  ],
  for (final product in products)
    [
      product['name'],
      product['sku'] ?? '',
      product['category'] ?? '',
      product['quantity'],
      product['unit'] ?? 'units',
      product['salePrice'],
      product['costPrice'],
      product['valueAtCost'],
      product['valueAtSellingPrice'],
      '',
      '',
    ],
];

Uint8List buildStockAuditCsvBytes(List<List<Object?>> rows) => Uint8List.fromList(
  utf8.encode(
    rows
        .map(
          (row) => row
              .map((cell) {
                final value = cell?.toString() ?? '';
                return '"${value.replaceAll('"', '""')}"';
              })
              .join(','),
        )
        .join('\r\n'),
  ),
);
