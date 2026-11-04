import 'dart:js_interop';

@JS('window.open')
external JSAny? _openPrintWindow(String url, String name);

@JS()
extension type _PrintWindow(JSObject _) implements JSObject {
  external _PrintDocument get document;
}

@JS()
extension type _PrintDocument(JSObject _) implements JSObject {
  external void open();
  external void write(String value);
  external void close();
}

Future<bool> printHtml(String document) async {
  final opened = _openPrintWindow('', 'shop_pos_day_end_slip');
  if (opened == null) return false;
  final printWindow = opened as _PrintWindow;

  printWindow.document
    ..open()
    ..write(document)
    ..close();
  return true;
}
