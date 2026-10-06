import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

/// Result from [ImageService.pickAndProcess].
class ImagePickResult {
  const ImagePickResult({required this.base64Jpeg, required this.sizeKb});
  final String base64Jpeg; // full data URI: "data:image/jpeg;base64,..."
  final double sizeKb;
}

/// Handles image picking, center-crop to 1:1, JPEG compression.
/// Works on Flutter Web and Desktop/Mobile.
class ImageService {
  /// Max output edge length in pixels for product images.
  static const int productMaxPx = 512;

  /// Max output edge length for logo images.
  static const int logoMaxPx = 256;

  /// JPEG quality 0-100 used for compression.
  static const int jpegQuality = 62;

  /// Pick an image from the file system, center-crop to 1:1, compress.
  /// [maxEdgePx] controls the output size (default [productMaxPx]).
  static Future<ImagePickResult?> pickAndProcess(
      {int maxEdgePx = productMaxPx}) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
      );
      if (files.isEmpty) return null;

      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      if (kIsWeb) {
        return _processImageBytes(_ProcessArgs(bytes, maxEdgePx));
      } else {
        return await compute(_processImageBytes, _ProcessArgs(bytes, maxEdgePx));
      }
    } catch (e, stack) {
      debugPrint('[ImageService] Error picking image: $e\n$stack');
      return null;
    }
  }

  /// Process raw bytes from a picked file on an isolate.
  static ImagePickResult? _processImageBytes(_ProcessArgs args) {
    // Decode the image
    final decoded = img.decodeImage(args.bytes);
    if (decoded == null) return null;

    // Center-crop to 1:1
    final size = math.min(decoded.width, decoded.height);
    final x = (decoded.width - size) ~/ 2;
    final y = (decoded.height - size) ~/ 2;
    final cropped =
        img.copyCrop(decoded, x: x, y: y, width: size, height: size);

    // Resize down if needed
    final resized = (cropped.width > args.maxEdgePx)
        ? img.copyResize(cropped,
            width: args.maxEdgePx,
            height: args.maxEdgePx,
            interpolation: img.Interpolation.linear)
        : cropped;

    // Encode as JPEG
    final jpeg = img.encodeJpg(resized, quality: jpegQuality);
    final b64 = base64Encode(jpeg);
    final dataUri = 'data:image/jpeg;base64,$b64';

    return ImagePickResult(
      base64Jpeg: dataUri,
      sizeKb: jpeg.length / 1024,
    );
  }
}

/// Helper class for isolate arguments.
class _ProcessArgs {
  const _ProcessArgs(this.bytes, this.maxEdgePx);
  final Uint8List bytes;
  final int maxEdgePx;
}
