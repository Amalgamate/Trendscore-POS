String buildStockAuditHtml({
  required String shopName,
  required DateTime printedAt,
  required List<Map<String, dynamic>> products,
}) {
  String escape(Object? input) => (input?.toString() ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  String money(Object? input) {
    final value = input is num ? input.toDouble() : double.tryParse('$input');
    return value == null ? '—' : value.toStringAsFixed(2);
  }

  final totalCost = products.fold<double>(
    0,
    (sum, p) => sum + ((p['valueAtCost'] as num?)?.toDouble() ?? 0),
  );
  final totalRetail = products.fold<double>(
    0,
    (sum, p) => sum + ((p['valueAtSellingPrice'] as num?)?.toDouble() ?? 0),
  );
  final rows = products.map((p) {
    final flags = [
      if (p['varianceFlag'] == true) 'VARIANCE',
      if (((p['quantity'] as num?)?.toDouble() ?? 0) < 0) 'NEGATIVE',
    ].join(', ');
    return '<tr><td>${escape(p['name'])}</td><td>${escape(p['sku'])}</td>'
        '<td>${escape(p['category'])}</td><td class="num">${escape(p['quantity'])} ${escape(p['unit'] ?? 'units')}</td>'
        '<td class="num">${money(p['costPrice'])}</td><td class="num">${money(p['valueAtCost'])}</td>'
        '<td class="count"></td><td class="count"></td><td>${escape(flags)}</td></tr>';
  }).join();
  final date = printedAt.toLocal();
  final timestamp =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>Stock audit — ${escape(shopName)}</title><style>
@page { size: A4 portrait; margin: 14mm 10mm 16mm; }
* { box-sizing: border-box; } body { font: 9pt Arial, sans-serif; color: #111; }
h1 { margin: 0 0 4px; font-size: 16pt; } .meta { color: #444; margin-bottom: 12px; }
table { width: 100%; border-collapse: collapse; } th, td { border: 1px solid #777; padding: 4px; }
th { background: #eee; text-align: left; } .num { text-align: right; white-space: nowrap; }
.count { width: 12%; } tfoot { font-weight: bold; }
thead { display: table-header-group; } tr { break-inside: avoid; }
.page-footer { position: fixed; bottom: -10mm; right: 0; color: #555; font-size: 8pt; }
.page-footer:after { content: "Page " counter(page) " of " counter(pages); }
@media screen { body { max-width: 210mm; margin: 16px auto; } }
</style></head><body><h1>${escape(shopName)} — Stock Audit</h1>
<div class="meta">Printed: ${escape(timestamp)} · Products: ${products.length}</div>
<table><thead><tr><th>Product</th><th>SKU</th><th>Category</th><th>Available stock</th><th>Cost / unit (KES)</th><th>Value at cost (KES)</th><th>Counted</th><th>Difference</th><th>Flags</th></tr></thead>
<tbody>$rows</tbody><tfoot><tr><td colspan="5">Totals</td><td class="num">${totalCost.toStringAsFixed(2)}</td><td></td><td></td><td>Retail value: KES ${totalRetail.toStringAsFixed(2)}</td></tr></tfoot></table>
<div class="page-footer"></div><script>window.onload = () => { window.focus(); window.print(); };</script></body></html>''';
}
