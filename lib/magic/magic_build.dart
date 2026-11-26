import 'dart:math' as math;
import 'dart:ui';

import '../paint/brush.dart';
import '../paint/stroke.dart';
import 'recommender.dart';

/// A magic build in progress: the art laid out on screen as strokes, revealed
/// one after another as [progress] goes 0 → 1.
class MagicBuild {
  MagicBuild._(this.art, this.strokes, this._cumulative, this.totalLength);

  factory MagicBuild.layout({
    required MagicArt art,
    required Rect area,
    required double glow,
    double widthScale = 1.0,
  }) {
    final target = fitRect(area, art.aspect);
    final base = (target.shortestSide / 85).clamp(3.0, 10.0) * widthScale;
    final strokes = <Stroke>[];
    final rnd = math.Random(art.title.hashCode);
    for (final p in art.paths) {
      if (p.points.length < 2) continue;
      final color = art.palette.colors[p.color % art.palette.colors.length];
      final style = BrushStyle(kind: art.brush, color: color, width: base * p.width, glow: glow);
      strokes.add(Stroke(
        style: style,
        magic: true,
        seed: rnd.nextInt(1 << 30),
        points: densify([
          for (final o in p.points) Offset(target.left + o.dx * target.width, target.top + o.dy * target.height),
        ], base * 1.5),
      ));
    }
    final cumulative = <double>[];
    var total = 0.0;
    for (final s in strokes) {
      total += s.length;
      cumulative.add(total);
    }
    return MagicBuild._(art, strokes, cumulative, total);
  }

  final MagicArt art;
  final List<Stroke> strokes;
  final List<double> _cumulative;
  final double totalLength;

  /// Longer art takes longer, within limits that keep it feeling magical.
  Duration get duration => Duration(milliseconds: (900 + totalLength * 0.9).clamp(1600, 4200).round());

  /// Splits long straight segments so curve smoothing keeps corners crisp
  /// (polygons like roofs and lightning stay sharp, not rounded).
  static List<Offset> densify(List<Offset> pts, double step) {
    if (pts.length < 2 || step <= 0) return pts;
    final out = <Offset>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final n = ((b - a).distance / step).floor();
      for (var k = 1; k < n; k++) {
        out.add(Offset.lerp(a, b, k / n)!);
      }
      out.add(b);
    }
    return out;
  }

  /// Largest rect of [aspect] (w/h) centred in [area], with breathing room.
  static Rect fitRect(Rect area, double aspect) {
    final inset = area.deflate(area.shortestSide * 0.08);
    var w = inset.width;
    var h = w / aspect;
    if (h > inset.height) {
      h = inset.height;
      w = h * aspect;
    }
    return Rect.fromCenter(center: inset.center, width: w, height: h);
  }

  /// Strokes visible at [progress]; the last one may be partial.
  List<Stroke> visibleAt(double progress) {
    if (progress >= 1) return strokes;
    final target = totalLength * progress.clamp(0.0, 1.0);
    final out = <Stroke>[];
    var start = 0.0;
    for (var i = 0; i < strokes.length; i++) {
      final end = _cumulative[i];
      if (end <= target) {
        out.add(strokes[i]);
      } else {
        final len = end - start;
        if (len > 0 && target > start) out.add(strokes[i].partial((target - start) / len));
        break;
      }
      start = end;
    }
    return out;
  }

  /// Where the "pen of light" is at [progress].
  Offset? headAt(double progress) {
    final v = visibleAt(progress);
    if (v.isEmpty || v.last.points.isEmpty) return null;
    return v.last.points.last;
  }
}
