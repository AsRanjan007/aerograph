import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Brand colors shared by the logo, splash and studio chrome.
abstract final class Brand {
  static const night = Color(0xFF07061A);
  static const deep = Color(0xFF110D33);
  static const violet = Color(0xFF8B5CF6);
  static const orchid = Color(0xFFC084FC);
  static const sky = Color(0xFF38BDF8);
  static const ink = Color(0xFFEEF2FF);
  static const mist = Color(0xFFA5B4FC);

  static const gradient = LinearGradient(colors: [orchid, violet, sky]);
}

/// Vector version of the Aerograph mark: one continuous light stroke that
/// paints an "A" and sweeps out to a glowing fingertip. [progress] animates
/// the stroke being drawn (used by the splash screen).
class AerographMarkPainter extends CustomPainter {
  AerographMarkPainter({this.progress = 1, this.showBackground = true});

  final double progress;
  final bool showBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1024;
    canvas.save();
    canvas.translate((size.width - 1024 * s) / 2, (size.height - 1024 * s) / 2);
    canvas.scale(s);

    if (showBackground) {
      final bg = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1024, 1024), const Radius.circular(224));
      canvas.drawRRect(
        bg,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.24),
            radius: 0.75,
            colors: [Color(0xFF1B1448), Color(0xFF0B0A22), Color(0xFF05050F)],
            stops: [0, 0.6, 1],
          ).createShader(const Rect.fromLTWH(0, 0, 1024, 1024)),
      );
    }

    // Orbit rings.
    canvas.save();
    canvas.translate(512, 540);
    canvas.rotate(-18 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 720, height: 240),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Brand.violet.withValues(alpha: 0.18 * progress),
    );
    canvas.restore();

    final path = Path()
      ..moveTo(260, 800)
      ..lineTo(512, 230)
      ..lineTo(764, 800)
      ..moveTo(300, 650)
      ..cubicTo(420, 600, 560, 640, 680, 600)
      ..cubicTo(770, 570, 820, 500, 830, 420);

    final drawn = _partial(path, progress);
    const shader = LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [Brand.orchid, Brand.violet, Brand.sky],
    );
    final rect = const Rect.fromLTWH(200, 200, 700, 650);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 70
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = shader.createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 50
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = shader.createShader(rect),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.6),
    );

    // Fingertip light.
    final head = _headOf(path, progress);
    if (head != null) {
      canvas.drawCircle(
        head,
        90,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white, const Color(0xFFBAE6FD), Brand.sky.withValues(alpha: 0)],
            stops: const [0, 0.35, 1],
          ).createShader(Rect.fromCircle(center: head, radius: 90)),
      );
      canvas.drawCircle(head, 22, Paint()..color = Colors.white);
    }

    // Sparkles fade in at the end.
    final sp = ((progress - 0.7) / 0.3).clamp(0.0, 1.0);
    if (sp > 0) {
      final p = Paint()..color = const Color(0xFFE0E7FF).withValues(alpha: sp);
      _sparkle(canvas, const Offset(870, 270), 40, p);
      _sparkle(canvas, const Offset(207, 380), 27, p);
    }
    canvas.restore();
  }

  void _sparkle(Canvas c, Offset o, double r, Paint p) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..lineTo(o.dx + r * 0.25, o.dy - r * 0.25)
      ..lineTo(o.dx + r, o.dy)
      ..lineTo(o.dx + r * 0.25, o.dy + r * 0.25)
      ..lineTo(o.dx, o.dy + r)
      ..lineTo(o.dx - r * 0.25, o.dy + r * 0.25)
      ..lineTo(o.dx - r, o.dy)
      ..lineTo(o.dx - r * 0.25, o.dy - r * 0.25)
      ..close();
    c.drawPath(path, p);
  }

  static Path _partial(Path path, double t) {
    if (t >= 1) return path;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    var remaining = total * t.clamp(0.0, 1.0);
    final out = Path();
    for (final m in metrics) {
      if (remaining <= 0) break;
      final len = math.min(remaining, m.length);
      out.addPath(m.extractPath(0, len), Offset.zero);
      remaining -= len;
    }
    return out;
  }

  static Offset? _headOf(Path path, double t) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    var remaining = total * t.clamp(0.0, 1.0);
    for (final m in metrics) {
      if (remaining <= m.length) return m.getTangentForOffset(remaining)?.position;
      remaining -= m.length;
    }
    return metrics.isEmpty ? null : metrics.last.getTangentForOffset(metrics.last.length)?.position;
  }

  @override
  bool shouldRepaint(AerographMarkPainter old) => old.progress != progress || old.showBackground != showBackground;
}

/// Ashutosh Ranjan's "AR" signature monogram, as vector paths.
class ArSignaturePainter extends CustomPainter {
  const ArSignaturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Source art box: x 60..270, y 58..228.
    const box = Rect.fromLTRB(60, 58, 270, 228);
    final s = math.min(size.width / box.width, size.height / box.height);
    canvas.save();
    canvas.translate((size.width - box.width * s) / 2 - box.left * s, (size.height - box.height * s) / 2 - box.top * s);
    canvas.scale(s);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFA66BFF), Color(0xFF7C6CF6), Color(0xFF4C8DF6)],
        stops: [0, 0.55, 1],
      ).createShader(box);

    final p = Path()
      // hook
      ..moveTo(118, 96)
      ..cubicTo(96, 84, 66, 92, 64, 124)
      ..cubicTo(63, 142, 72, 154, 84, 160)
      ..lineTo(90, 150)
      ..cubicTo(80, 145, 76, 136, 77, 124)
      ..cubicTo(79, 104, 98, 98, 114, 106)
      ..close()
      // A left leg
      ..moveTo(150, 62)
      ..lineTo(164, 62)
      ..lineTo(112, 222)
      ..lineTo(96, 222)
      ..close()
      // crossbar curl
      ..moveTo(84, 160)
      ..cubicTo(100, 172, 132, 170, 168, 158)
      ..lineTo(166, 148)
      ..cubicTo(134, 158, 104, 160, 90, 150)
      ..close()
      // R stem
      ..addRect(const Rect.fromLTRB(152, 62, 168, 222))
      // R bowl
      ..moveTo(160, 62)
      ..lineTo(196, 62)
      ..cubicTo(236, 62, 252, 82, 252, 106)
      ..cubicTo(252, 132, 232, 150, 196, 150)
      ..lineTo(166, 150)
      ..lineTo(166, 138)
      ..lineTo(194, 138)
      ..cubicTo(222, 138, 236, 126, 236, 106)
      ..cubicTo(236, 86, 222, 74, 194, 74)
      ..lineTo(160, 74)
      ..close()
      // R leg
      ..moveTo(196, 144)
      ..lineTo(212, 144)
      ..lineTo(258, 222)
      ..lineTo(240, 222)
      ..close()
      // serifs
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(86, 218, 36, 6), const Radius.circular(2)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(142, 218, 36, 6), const Radius.circular(2)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(232, 218, 34, 6), const Radius.circular(2)));
    canvas.drawPath(p, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArSignaturePainter oldDelegate) => false;
}

/// "Designed & developed by Ashutosh Ranjan" credit with the AR monogram.
class AuthorCredit extends StatelessWidget {
  const AuthorCredit({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mark = compact ? 30.0 : 44.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: mark * 1.25,
          height: mark,
          child: const CustomPaint(painter: ArSignaturePainter()),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Designed & developed by',
              style: TextStyle(
                color: Brand.mist.withValues(alpha: 0.8),
                fontSize: compact ? 10 : 12,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              'Ashutosh Ranjan',
              style: TextStyle(color: Brand.ink, fontSize: compact ? 14 : 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}

/// Gradient "Aerograph" wordmark.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => Brand.gradient.createShader(r),
      child: Text(
        'Aerograph',
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, letterSpacing: size * 0.04, color: Colors.white),
      ),
    );
  }
}
