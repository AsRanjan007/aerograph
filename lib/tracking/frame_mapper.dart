import 'dart:math' as math;
import 'dart:ui';

/// Maps normalized landmark coordinates from the upright analysis frame into
/// screen coordinates, matching how the camera preview is laid out (scaled
/// with BoxFit.cover and centered).
///
/// Both the analysis stream and the preview are assumed to be centered crops
/// of the same sensor field of view; the analysis frame is first fitted to the
/// preview's aspect ratio (cover), then the preview to the screen (cover).
class FrameMapper {
  const FrameMapper({
    required this.analysisSize,
    required this.previewSize,
    required this.screenSize,
    required this.mirror,
  });

  /// Upright analysis frame size (portrait for a portrait UI).
  final Size analysisSize;

  /// Upright preview size (portrait for a portrait UI).
  final Size previewSize;
  final Size screenSize;

  /// True when the preview is mirrored but the analysis frame is not
  /// (front camera on Android).
  final bool mirror;

  Offset map(double nx, double ny) {
    final x = mirror ? 1.0 - nx : nx;
    final aw = analysisSize.width, ah = analysisSize.height;
    final pw = previewSize.width, ph = previewSize.height;
    // analysis → preview (cover)
    final s1 = math.max(pw / aw, ph / ah);
    final px = x * aw * s1 - (aw * s1 - pw) / 2;
    final py = ny * ah * s1 - (ah * s1 - ph) / 2;
    // preview → screen (cover)
    final s2 = math.max(screenSize.width / pw, screenSize.height / ph);
    final sx = px * s2 - (pw * s2 - screenSize.width) / 2;
    final sy = py * s2 - (ph * s2 - screenSize.height) / 2;
    return Offset(sx, sy);
  }
}
