import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';

import '../paint/brush.dart';
import '../paint/stroke.dart';
import '../paint/stroke_renderer.dart';

/// Renders artwork off-screen and saves it to the photo library.
class Exporter {
  const Exporter();

  static const _renderer = StrokeRenderer();

  /// Renders [strokes] at [logicalSize] × [pixelRatio]. When [photo] is given
  /// it is drawn underneath (cover-fitted, optionally mirrored), otherwise a
  /// deep night background is used.
  Future<Uint8List> render({
    required List<Stroke> strokes,
    required Size logicalSize,
    double pixelRatio = 2,
    ui.Image? photo,
    bool mirrorPhoto = false,
    double dim = 0.3,
    LightMode mode = LightMode.steady,
    double time = 0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);
    final rect = Offset.zero & logicalSize;
    if (photo != null) {
      final src = Size(photo.width.toDouble(), photo.height.toDouble());
      final fitted = applyBoxFit(BoxFit.cover, src, logicalSize);
      final srcRect = Alignment.center.inscribe(fitted.source, Offset.zero & src);
      canvas.save();
      if (mirrorPhoto) {
        canvas.translate(logicalSize.width, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawImageRect(photo, srcRect, rect, Paint()..filterQuality = FilterQuality.high);
      canvas.restore();
      canvas.drawRect(rect, Paint()..color = const Color(0xFF000000).withValues(alpha: dim));
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF15103A), Color(0xFF05050F)],
            radius: 1.1,
          ).createShader(rect),
      );
    }
    for (final s in strokes) {
      _renderer.paintStroke(canvas, s, mode: mode, time: time);
    }
    _signature(canvas, logicalSize);
    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (logicalSize.width * pixelRatio).round(),
      (logicalSize.height * pixelRatio).round(),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  void _signature(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Aerograph',
        style: TextStyle(color: Color(0x99EEF2FF), fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 14, size.height - tp.height - 14));
  }

  /// Takes a still from the camera for compositing. Returns null if the
  /// platform can't capture while streaming.
  Future<ui.Image?> capturePhoto(CameraController controller) async {
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('Aerograph capture failed: $e');
      return null;
    }
  }

  Future<void> saveToGallery(Uint8List png) async {
    if (!await Gal.hasPermission(toAlbum: true)) {
      await Gal.requestPermission(toAlbum: true);
    }
    await Gal.putImageBytes(png, album: 'Aerograph', name: 'aerograph_${DateTime.now().millisecondsSinceEpoch}');
  }
}
