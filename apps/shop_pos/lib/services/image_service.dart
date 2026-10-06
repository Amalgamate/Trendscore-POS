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
  ///
  /// NOTE: This is a Flutter Web app (flutter build web). dart:io is NOT
  /// available. We use PlatformFile.readAsBytes() so file_picker loads bytes
  /// in memory for us on every platform, avoiding any dart:io dependency.
  static Future<ImagePickResult?> pickAndProcess(
      {int maxEdgePx = productMaxPx}) async {
    // FilePicker.pickFile() returns PlatformFile? (null = user cancelled).
    final file = await FilePicker.pickFile(
      type: FileType.image,
    );

    // User cancelled or no file selected.
    if (file == null) return null;

    final bytes = await file.readAsBytes();

    if (bytes.isEmpty) {
      throw StateError('The selected image could not be read. Try another image.');
    }

    // On web we cannot use compute() (no isolate support for this use case).
    if (kIsWeb) {
      return _processImageBytes(_ProcessArgs(bytes, maxEdgePx));
    }
    return compute(_processImageBytes, _ProcessArgs(bytes, maxEdgePx));
  }

  /// Process raw bytes from a picked file on an isolate (or directly on web).
  static ImagePickResult? _processImageBytes(_ProcessArgs args) {
    try {
      // Decode the image
      final decoded = img.decodeImage(args.bytes);
      if (decoded == null) {
        throw const FormatException('This image format could not be read. Try a JPEG, PNG or WebP image.');
      }

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
    } catch (e, st) {
      debugPrint('[ImageService] Error processing image: $e\n$st');
      rethrow;
    }
  }
}

/// Helper class for isolate arguments.
class _ProcessArgs {
  const _ProcessArgs(this.bytes, this.maxEdgePx);
  final Uint8List bytes;
  final int maxEdgePx;
}
