import 'day_end_slip_stub.dart'
    if (dart.library.html) 'day_end_slip_web.dart'
    as platform;

String buildDayEndSlipHtml({
  required String shopName,
  required String branch,
  required String date,
  required String till,
  required String cashier,
  required List<({String label, String value})> rows,
}) {
  String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  final lines = rows
      .map(
        (row) =>
            '<div class="row"><span>${escape(row.label)}</span>'
            '<strong>${escape(row.value)}</strong></div>',
      )
      .join();
  return '''<!doctype html>
<html><head><meta charset="utf-8"><title>Z-Report ${escape(date)}</title>
<style>
@page { size: 80mm auto; margin: 4mm; }
* { box-sizing: border-box; }
body { font: 12px/1.4 Arial, sans-serif; color: #111; width: 72mm; margin: 0 auto; }
h1 { font-size: 17px; margin: 0 0 3px; text-align: center; }
.center { text-align: center; margin: 0 0 2px; }
.meta { margin: 8px 0; }
.row { display: flex; justify-content: space-between; gap: 5px; padding: 3px 0; border-bottom: 1px dotted #888; }
.row strong { text-align: right; white-space: nowrap; }
.footer { text-align: center; margin-top: 12px; }
@media print { body { width: 72mm; } }
</style></head><body>
<h1>${escape(shopName)}</h1><p class="center">${escape(branch)}</p>
<p class="center">DAY-END REPORT</p><div class="meta">Business day: ${escape(date)}<br>Till: ${escape(till)}<br>Cashier: ${escape(cashier)}</div>
$lines
<p class="footer">End of report</p>
<script>window.onload = () => { window.focus(); window.print(); };</script>
</body></html>''';
}

Future<bool> printDayEndSlip(String html) => platform.printHtml(html);
