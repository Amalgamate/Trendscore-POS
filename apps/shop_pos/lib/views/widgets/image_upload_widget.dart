import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/image_service.dart';
import '../../theme/tokens.dart';

/// A reusable 1:1 image upload widget.
/// Shows a placeholder/preview and triggers [ImageService.pickAndProcess]
/// on tap. Calls [onImagePicked] with the base64 data URI, or
/// [onImageCleared] when the user removes the image.
class ImageUploadWidget extends StatefulWidget {
  const ImageUploadWidget({
    super.key,
    this.currentBase64,
    required this.onImagePicked,
    this.onImageCleared,
    this.onError,
    this.size = 120.0,
    this.label = 'Upload Image',
    this.borderRadius = 12.0,
    this.isLogo = false,
  });

  /// Current image as base64 data URI (if any).
  final String? currentBase64;

  /// Called with the new base64 data URI after picking.
  final ValueChanged<String> onImagePicked;

  /// Called when user taps the clear button.
  final VoidCallback? onImageCleared;

  /// Called with a readable message when picking/processing fails (and with an
  /// empty string when a new attempt starts, so callers can clear the message).
  /// If null, a SnackBar is shown instead.
  final ValueChanged<String>? onError;

  /// Widget size (square).
  final double size;

  /// Label shown under the upload icon when no image is set.
  final String label;

  final double borderRadius;

  /// If true, picks at logoMaxPx resolution instead of productMaxPx.
  final bool isLogo;

  @override
  State<ImageUploadWidget> createState() => _ImageUploadWidgetState();
}

class _ImageUploadWidgetState extends State<ImageUploadWidget>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _hovered = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulse = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_loading) return;
    widget.onError?.call('');
    try {
      // Must be invoked synchronously from the tap so the browser allows the
      // file chooser to open.
      final pickFuture = ImageService.pickAndProcess(
        maxEdgePx: widget.isLogo ? ImageService.logoMaxPx : ImageService.productMaxPx,
      );
      if (mounted) {
        setState(() => _loading = true);
        _pulseCtrl.repeat(reverse: true);
      }
      final result = await pickFuture;
      if (result != null && mounted) {
        widget.onImagePicked(result.base64Jpeg);
      }
    } catch (error, stack) {
      debugPrint('[ImageUploadWidget] upload failed: $error\n$stack');
      if (mounted) {
        final message = error.toString().replaceFirst(RegExp(r'^(Exception|StateError|FormatException): ?'), '');
        if (widget.onError != null) {
          widget.onError!('Could not upload image: $message');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not upload image: $message')),
          );
        }
      }
    } finally {
      if (mounted) {
        _pulseCtrl.stop();
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.currentBase64 != null && widget.currentBase64!.isNotEmpty;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main tile
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pick,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: hasImage ? Colors.black : AppColors.bg_subtle,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: hasImage
                        ? AppColors.accent_primary.withAlpha(60)
                        : (_hovered
                            ? AppColors.accent_primary.withAlpha(120)
                            : AppColors.border_subtle),
                    width: hasImage ? 2 : 1,
                  ),
                  boxShadow: hasImage
                      ? [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 8, offset: const Offset(0, 4))]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius - 1),
                  child: _buildContent(hasImage),
                ),
              ),
            ),
          ),

          // Loading overlay
          if (_loading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                ),
                child: ScaleTransition(
                  scale: _pulse,
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent_primary),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Clear button
          if (hasImage && !_loading && widget.onImageCleared != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: widget.onImageCleared,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 4)],
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(bool hasImage) {
    if (hasImage) {
      try {
        final clean = widget.currentBase64!.split(',').last.replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(clean);
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: widget.size,
              height: widget.size,
              gaplessPlayback: true,
              errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
            ),
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Change',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      } catch (_) {
        return _buildPlaceholder();
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: widget.size * 0.3,
          color: AppColors.accent_primary.withAlpha(160),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: widget.size < 100 ? 9 : 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text_tertiary,
            ),
          ),
        ),
      ],
    );
  }
}
