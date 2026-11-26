import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../magic/magic_build.dart';
import '../magic/recommender.dart';
import '../paint/brush.dart';
import '../paint/stroke.dart';
import '../paint/stroke_renderer.dart';
import '../tracking/air_tracker.dart';
import '../tracking/hand_pose.dart';

const _renderer = StrokeRenderer();

/// Finished strokes. In steady light mode the strokes are recorded into a
/// cached picture so the expensive blurs are only replayed, not rebuilt.
class ArtLayerPainter extends CustomPainter {
  ArtLayerPainter({required this.history, required this.mode, required this.clock, required Listenable repaint})
    : super(repaint: repaint);

  final StrokeHistory history;
  final LightMode mode;
  final ValueNotifier<double> clock;

  static ui.Picture? _cache;
  static int _cacheRevision = -1;
  static int _cacheCount = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == LightMode.steady) {
      if (_cache == null || _cacheRevision != history.revision || _cacheCount != history.strokes.length) {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        for (final s in history.strokes) {
          _renderer.paintStroke(c, s);
        }
        _cache?.dispose();
        _cache = rec.endRecording();
        _cacheRevision = history.revision;
        _cacheCount = history.strokes.length;
      }
      canvas.drawPicture(_cache!);
      return;
    }
    final t = clock.value;
    for (final s in history.strokes) {
      _renderer.paintStroke(canvas, s, mode: mode, time: t);
    }
  }

  @override
  bool shouldRepaint(ArtLayerPainter old) => old.mode != mode || old.history != history;
}

class Particle {
  Particle(this.position, this.velocity, this.color, this.size, this.life);
  Offset position;
  Offset velocity;
  final Color color;
  final double size;
  double life; // seconds remaining
  late final double maxLife = life;
}

/// The stroke being painted, the magic build, particles and the cursor.
class LiveLayerPainter extends CustomPainter {
  LiveLayerPainter({
    required this.live,
    required this.magic,
    required this.magicProgress,
    required this.particles,
    required this.pointer,
    required this.penDown,
    required this.cursorColor,
    required this.holdProgress,
    required this.showSkeleton,
    required this.clock,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Stroke? Function() live;
  final MagicBuild? Function() magic;
  final double Function() magicProgress;
  final List<Particle> particles;
  final ValueNotifier<AirPointer> pointer;
  final bool Function() penDown;
  final Color Function() cursorColor;
  final double Function() holdProgress;
  final bool showSkeleton;
  final ValueNotifier<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final s = live();
    if (s != null) _renderer.paintStroke(canvas, s);

    final m = magic();
    if (m != null) {
      final p = magicProgress();
      for (final st in m.visibleAt(p)) {
        _renderer.paintStroke(canvas, st, mode: LightMode.shimmer, time: t);
      }
      final head = m.headAt(p);
      if (head != null && p < 1) _sparkHead(canvas, head, t);
    }

    for (final pt in particles) {
      final a = (pt.life / pt.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        pt.position,
        pt.size * (0.5 + a),
        Paint()
          ..color = pt.color.withValues(alpha: a)
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pt.size * 0.8),
      );
    }

    final ptr = pointer.value;
    if (!ptr.visible) return;
    if (showSkeleton && ptr.skeleton.length == 21) _skeleton(canvas, ptr.skeleton);
    _cursor(canvas, ptr, t);
  }

  void _sparkHead(Canvas canvas, Offset c, double t) {
    final r = 16 + 4 * math.sin(t * 14);
    canvas.drawCircle(
      c,
      r * 2.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            const Color(0xFFBAE6FD).withValues(alpha: 0.7),
            const Color(0xFF8B5CF6).withValues(alpha: 0),
          ],
          stops: const [0, 0.3, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 2.2)),
    );
  }

  void _skeleton(Canvas canvas, List<Offset> pts) {
    final bone = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in HandIdx.bones) {
      canvas.drawLine(pts[a], pts[b], bone);
    }
    final joint = Paint()..color = Colors.white.withValues(alpha: 0.6);
    for (final p in pts) {
      canvas.drawCircle(p, 3, joint);
    }
  }

  void _cursor(Canvas canvas, AirPointer ptr, double t) {
    final c = ptr.position;
    final color = cursorColor();
    final down = penDown();
    if (down) {
      canvas.drawCircle(
        c,
        22,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawCircle(c, 6, Paint()..color = Colors.white);
    } else {
      final r = 14 + 2 * math.sin(t * 4);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.9),
      );
      canvas.drawCircle(c, 3, Paint()..color = color);
    }

    final hp = holdProgress();
    if (hp > 0) {
      final rect = Rect.fromCircle(center: c, radius: 30);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * hp,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(LiveLayerPainter old) => old.showSkeleton != showSkeleton;
}

/// Small preview of a recommendation, drawn with its own palette and brush.
class ArtPreviewPainter extends CustomPainter {
  ArtPreviewPainter(this.art);
  final MagicArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final build = MagicBuild.layout(art: art, area: Offset.zero & size, glow: 0.7, widthScale: 0.55);
    for (final s in build.strokes) {
      _renderer.paintStroke(canvas, s);
    }
  }

  @override
  bool shouldRepaint(ArtPreviewPainter old) => old.art != art;
}
