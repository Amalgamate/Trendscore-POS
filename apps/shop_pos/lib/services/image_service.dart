import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'image_file_picker.dart';

/// Result from [ImageService.pickAndProcess].
class ImagePickResult {
  const ImagePickResult({required this.base64Jpeg, required this.sizeKb});
  final String base64Jpeg; // full data URI: "data:image/jpeg;base64,..."
  final double sizeKb;
}

/// Handles image picking, center-crop to 1:1, JPEG compression.
///
/// Decoding, cropping and resizing are done by the engine's native image
/// codec (the browser on web), so every format the browser can display works
/// (JPEG, PNG, WebP, GIF, BMP, AVIF...), EXIF rotation is respected, and large
/// phone photos do not freeze the UI. Only the final 512px JPEG encode runs in
/// Dart, which is fast at that size.
class ImageService {
  /// Max output edge length in pixels for product images.
  static const int productMaxPx = 512;

  /// Max output edge length for logo images.
  static const int logoMaxPx = 256;

  /// JPEG quality 0-100 used for compression.
  static const int jpegQuality = 72;

  /// Largest file we will try to decode (guards against multi-hundred-MB files).
  static const int maxInputBytes = 25 * 1024 * 1024;

  /// Pick an image from the file system, center-crop to 1:1, compress.
  /// Returns null if the user cancelled. Throws an [Exception] with a
  /// user-readable message on failure.
  static Future<ImagePickResult?> pickAndProcess(
      {int maxEdgePx = productMaxPx}) async {
    final Uint8List? picked;
    try {
      picked = await pickImageBytes();
    } catch (e) {
      throw Exception('The selected file could not be read ($e). Try another image.');
    }

    // User cancelled.
    if (picked == null) return null;
    final bytes = picked;
    if (bytes.isEmpty) {
      throw Exception('The selected image is empty or could not be read. Try another image.');
    }
    if (bytes.length > maxInputBytes) {
      throw Exception('That image is larger than 25 MB. Choose a smaller one.');
    }

    return _process(bytes, maxEdgePx);
  }

  static Future<ImagePickResult> _process(Uint8List bytes, int maxEdgePx) async {
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? square;
    try {
      try {
        codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        source = frame.image;
      } catch (_) {
        throw Exception(
            'This image format is not supported. Use a JPEG, PNG or WebP image.');
      }

      // Largest centered square, never upscaled beyond the source.
      final side = math.min(source.width, source.height);
      final out = math.min(side, maxEdgePx);
      final srcRect = ui.Rect.fromLTWH(
        (source.width - side) / 2,
        (source.height - side) / 2,
        side.toDouble(),
        side.toDouble(),
      );
      final dstRect = ui.Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, dstRect);
      // White backdrop so transparent PNGs do not turn black in a JPEG.
      canvas.drawRect(dstRect, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      canvas.drawImageRect(
        source,
        srcRect,
        dstRect,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      square = await picture.toImage(out, out);
      picture.dispose();

      final raw = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) {
        throw Exception('The image could not be processed. Try another image.');
      }

      final rgba = img.Image.fromBytes(
        width: out,
        height: out,
        bytes: raw.buffer,
        bytesOffset: raw.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final jpeg = img.encodeJpg(rgba, quality: jpegQuality);

      return ImagePickResult(
        base64Jpeg: 'data:image/jpeg;base64,${base64Encode(jpeg)}',
        sizeKb: jpeg.length / 1024,
      );
    } finally {
      square?.dispose();
      source?.dispose();
      codec?.dispose();
    }
  }
}
