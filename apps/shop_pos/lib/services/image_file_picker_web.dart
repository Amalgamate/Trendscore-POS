import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Web: opens the browser's native file chooser with a plain
/// `<input type="file" accept="image/*">` and returns the file's bytes, or
/// null if the user cancelled. No plugin involved.
///
/// Must be called synchronously from a user gesture (a tap handler), otherwise
/// the browser blocks the chooser.
Future<Uint8List?> pickImageBytes() {
  final completer = Completer<Uint8List?>();

  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final body = document.getProperty<JSObject>('body'.toJS);
  final input = document.callMethod<JSObject>('createElement'.toJS, 'input'.toJS);
  input.setProperty('type'.toJS, 'file'.toJS);
  input.setProperty('accept'.toJS, 'image/*'.toJS);
  input.getProperty<JSObject>('style'.toJS).setProperty('display'.toJS, 'none'.toJS);
  body.callMethod<JSAny?>('appendChild'.toJS, input);

  void cleanup() {
    try {
      body.callMethod<JSAny?>('removeChild'.toJS, input);
    } catch (_) {}
  }

  final onChange = ((JSObject _) {
    unawaited(_readFirstFile(input, completer).whenComplete(cleanup));
  }).toJS;

  final onCancel = ((JSObject _) {
    if (!completer.isCompleted) completer.complete(null);
    cleanup();
  }).toJS;

  input.callMethod<JSAny?>('addEventListener'.toJS, 'change'.toJS, onChange);
  input.callMethod<JSAny?>('addEventListener'.toJS, 'cancel'.toJS, onCancel);
  input.callMethod<JSAny?>('click'.toJS);

  return completer.future;
}

Future<void> _readFirstFile(JSObject input, Completer<Uint8List?> completer) async {
  try {
    final files = input.getProperty<JSObject>('files'.toJS);
    final count = files.getProperty<JSNumber>('length'.toJS).toDartInt;
    if (count == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.callMethod<JSObject>('item'.toJS, 0.toJS);
    final buffer = await file
        .callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS)
        .toDart;
    if (!completer.isCompleted) {
      completer.complete(buffer.toDart.asUint8List());
    }
  } catch (e) {
    if (!completer.isCompleted) {
      completer.completeError(Exception('The selected file could not be read ($e).'));
    }
  }
}
