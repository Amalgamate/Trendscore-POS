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
  /// available. We use withData:true so file_picker loads bytes in memory
  /// for us on every platform, avoiding any dart:io dependency.
  static Future<ImagePickResult?> pickAndProcess(
      {int maxEdgePx = productMaxPx}) async {
    try {
      // FilePicker.platform.pickFiles returns FilePickerResult? (nullable),
      // NOT a list. withData:true pre-loads bytes so we never need dart:io.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      // User cancelled or no file selected
      if (result == null || result.files.isEmpty) return null;

      final f = result.files.first;
      final bytes = f.bytes;

      if (bytes == null || bytes.isEmpty) return null;

      // On web we cannot use compute() (no isolate support for this use case).
      // Process synchronously — image is small so this is fine.
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

  /// Process raw bytes from a picked file on an isolate (or directly on web).
  static ImagePickResult? _processImageBytes(_ProcessArgs args) {
    try {
      // Decode the image
      final decoded = img.decodeImage(args.bytes);
      if (decoded == null) {
        // Fallback: encode raw bytes so the image is not lost
        final b64 = base64Encode(args.bytes);
        return ImagePickResult(
          base64Jpeg: 'data:image/jpeg;base64,$b64',
          sizeKb: args.bytes.length / 1024,
        );
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
      try {
        final b64 = base64Encode(args.bytes);
        return ImagePickResult(
          base64Jpeg: 'data:image/jpeg;base64,$b64',
          sizeKb: args.bytes.length / 1024,
        );
      } catch (_) {
        return null;
      }
    }
  }
}

/// Helper class for isolate arguments.
class _ProcessArgs {
  const _ProcessArgs(this.bytes, this.maxEdgePx);
  final Uint8List bytes;
  final int maxEdgePx;
}