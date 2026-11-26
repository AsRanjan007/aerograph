import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;

import 'brush.dart';
import 'stroke.dart';

/// Draws light strokes. Shared by the live canvas and the exporter so saved
/// images look exactly like the screen.
class StrokeRenderer {
  const StrokeRenderer();

  /// [time] is seconds since start, used by animated light modes.
  void paintStroke(Canvas canvas, Stroke stroke, {LightMode mode = LightMode.steady, double time = 0}) {
    final pts = stroke.points;
    if (pts.isEmpty) return;
    final style = stroke.style;
    final intensity = _intensity(mode, time, stroke.seed);
    final color = _modeColor(style.color, mode, time, stroke.seed);

    if (pts.length == 1) {
      _dot(canvas, pts.first, style, color, intensity);
      return;
    }

    switch (style.kind) {
      case BrushKind.neon:
        final path = smoothPath(pts);
        _halo(canvas, path, color, style.width * 3.2, style.glow * intensity, sigma: style.width * 1.6);
        _line(canvas, path, color, style.width);
        _line(canvas, path, const Color(0xFFFFFFFF).withValues(alpha: 0.85), style.width * 0.38);
      case BrushKind.glow:
        final path = smoothPath(pts);
        _halo(canvas, path, color, style.width * 5, style.glow * intensity, sigma: style.width * 2.8);
        _line(canvas, path, color.withValues(alpha: 0.75), style.width * 1.2, blur: style.width * 0.5);
      case BrushKind.ink:
        final path = smoothPath(pts);
        if (style.glow > 0.05) {
          _halo(canvas, path, color, style.width * 1.8, style.glow * 0.5 * intensity, sigma: style.width);
        }
        _line(canvas, path, color, style.width);
      case BrushKind.sparkle:
        final path = smoothPath(pts);
        _halo(canvas, path, color, style.width * 2.4, style.glow * 0.8 * intensity, sigma: style.width * 1.4);
        _line(canvas, path, color.withValues(alpha: 0.9), style.width * 0.55);
        _sparkles(canvas, stroke, color, mode, time);
      case BrushKind.rainbow:
        _rainbow(canvas, stroke, style, intensity, mode, time);
      case BrushKind.comet:
        _comet(canvas, pts, style, color, intensity);
    }
  }

  double _intensity(LightMode mode, double t, int seed) {
    switch (mode) {
      case LightMode.steady:
        return 1;
      case LightMode.pulse:
        return 0.65 + 0.45 * (0.5 + 0.5 * math.sin(t * 3.2 + (seed % 100) * 0.06));
      case LightMode.shimmer:
        return 0.8 + 0.3 * math.sin(t * 9 + (seed % 360));
      case LightMode.aurora:
        return 0.9 + 0.15 * math.sin(t * 1.4 + (seed % 50) * 0.1);
    }
  }

  Color _modeColor(Color c, LightMode mode, double t, int seed) {
    if (mode != LightMode.aurora) return c;
    final hsv = HSVColor.fromColor(c);
    final shift = 40 * math.sin(t * 0.8 + (seed % 100) * 0.05);
    return hsv.withHue((hsv.hue + shift) % 360).toColor();
  }

  static Path smoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  void _line(Canvas canvas, Path path, Color color, double width, {double blur = 0}) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    canvas.drawPath(path, p);
  }

  void _halo(Canvas canvas, Path path, Color color, double width, double strength, {required double sigma}) {
    if (strength <= 0.01) return;
    final p = Paint()
      ..color = color.withValues(alpha: (0.55 * strength).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * (0.6 + strength * 0.6)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * (0.6 + strength));
    canvas.drawPath(path, p);
  }

  void _dot(Canvas canvas, Offset c, BrushStyle style, Color color, double intensity) {
    canvas.drawCircle(
      c,
      style.width * 2.2,
      Paint()
        ..color = color.withValues(alpha: 0.5 * style.glow * intensity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, style.width * 1.5),
    );
    canvas.drawCircle(c, style.width * 0.6, Paint()..color = color);
  }

  void _sparkles(Canvas canvas, Stroke stroke, Color color, LightMode mode, double time) {
    final rnd = math.Random(stroke.seed);
    final pts = stroke.points;
    final w = stroke.style.width;
    final star = Paint()..color = const Color(0xFFFFFFFF);
    final glow = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.9);
    var acc = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) acc += (pts[i] - pts[i - 1]).distance;
      if (acc < w * 2.6) continue;
      acc = 0;
      final jitter = Offset((rnd.nextDouble() - 0.5) * w * 3, (rnd.nextDouble() - 0.5) * w * 3);
      final phase = rnd.nextDouble() * math.pi * 2;
      final tw = mode == LightMode.steady ? 0.75 : 0.5 + 0.5 * math.sin(time * 6 + phase);
      final r = w * (0.25 + rnd.nextDouble() * 0.6) * (0.5 + tw);
      final c = pts[i] + jitter;
      canvas.drawCircle(c, r * 1.8, glow);
      _star(canvas, c, r, star);
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r * 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _rainbow(Canvas canvas, Stroke stroke, BrushStyle style, double intensity, LightMode mode, double time) {
    final pts = stroke.points;
    final baseHue = HSVColor.fromColor(style.color).hue;
    final flow = mode == LightMode.steady ? 0.0 : time * 60;
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final seg = (pts[i] - pts[i - 1]).distance;
      acc += seg;
      final hue = (baseHue + acc * 0.9 + flow) % 360;
      final c = HSVColor.fromAHSV(1, hue, 0.75, 1).toColor();
      final halo = Paint()
        ..color = c.withValues(alpha: 0.45 * style.glow * intensity)
        ..strokeWidth = style.width * 3
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, style.width * 1.4);
      canvas.drawLine(pts[i - 1], pts[i], halo);
      canvas.drawLine(
        pts[i - 1],
        pts[i],
        Paint()
          ..color = c
          ..strokeWidth = style.width
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _comet(Canvas canvas, List<Offset> pts, BrushStyle style, Color color, double intensity) {
    final n = pts.length;
    for (var i = 1; i < n; i++) {
      final t = i / (n - 1); // 0 at tail, 1 at head
      final w = style.width * (0.15 + 1.25 * t);
      final halo = Paint()
        ..color = color.withValues(alpha: 0.5 * style.glow * intensity * t)
        ..strokeWidth = w * 3
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.2 + 0.5);
      canvas.drawLine(pts[i - 1], pts[i], halo);
      canvas.drawLine(
        pts[i - 1],
        pts[i],
        Paint()
          ..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.5 * t)!.withValues(alpha: 0.3 + 0.7 * t)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }
  }
}
