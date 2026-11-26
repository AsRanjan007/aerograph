import 'dart:math' as math;
import 'dart:ui';

/// What a free-hand air sketch most likely is.
class ShapeGuess {
  const ShapeGuess(this.shape, this.confidence);

  /// One of: circle, triangle, square, star, heart, spiral, zigzag, wave,
  /// line, arc, infinity, scribble.
  final String shape;
  final double confidence;

  @override
  String toString() => 'ShapeGuess($shape, ${confidence.toStringAsFixed(2)})';
}

/// Feature-based recognizer for single strokes. Deliberately simple and
/// deterministic: air strokes are noisy, so it looks at robust global
/// features (closure, radial spread, corners, turning) rather than templates.
class ShapeRecognizer {
  const ShapeRecognizer();

  static const _n = 64;

  ShapeGuess recognize(List<Offset> raw) {
    if (raw.length < 6) return const ShapeGuess('scribble', 0);
    final pts = resample(raw, _n);
    final len = _pathLength(pts);
    if (len < 1e-6) return const ShapeGuess('scribble', 0);
    final bounds = _bounds(pts);
    final diag = math.max(1e-6, math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height));
    final gap = (pts.first - pts.last).distance;
    final closed = gap < diag * 0.28;
    final straightness = gap / len; // 1 = straight line

    // Turning angles.
    final turns = <double>[];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = pts[i] - pts[i - 1];
      final b = pts[i + 1] - pts[i];
      if (a.distance < 1e-9 || b.distance < 1e-9) {
        turns.add(0);
        continue;
      }
      turns.add(_wrap(math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)));
    }
    final totalTurn = turns.fold<double>(0, (s, t) => s + t);
    final absTurn = turns.fold<double>(0, (s, t) => s + t.abs());
    final corners = _corners(pts, closed: closed);

    if (!closed && straightness > 0.9) return ShapeGuess('line', straightness);

    // Sign changes of smoothed turning → wave / zigzag.
    var signChanges = 0;
    var lastSign = 0;
    for (var i = 0; i + 4 <= turns.length; i += 4) {
      final s = turns.sublist(i, i + 4).fold<double>(0, (a, b) => a + b);
      if (s.abs() < 0.08) continue;
      final sign = s > 0 ? 1 : -1;
      if (lastSign != 0 && sign != lastSign) signChanges++;
      lastSign = sign;
    }

    if (totalTurn.abs() > math.pi * 3.2 && !closed) {
      return ShapeGuess('spiral', math.min(1, totalTurn.abs() / (math.pi * 5)));
    }

    if (closed) {
      final c = _centroid(pts);
      final radii = [for (final p in pts) (p - c).distance];
      final mean = radii.reduce((a, b) => a + b) / radii.length;
      final variance = radii.fold<double>(0, (s, r) => s + (r - mean) * (r - mean)) / radii.length;
      final cv = math.sqrt(variance) / math.max(1e-6, mean);

      // Figure eight: closed, low net turning, high absolute turning.
      if (totalTurn.abs() < math.pi * 0.8 && absTurn > math.pi * 3) {
        return const ShapeGuess('infinity', 0.7);
      }
      if (corners >= 8 || (corners >= 5 && cv > 0.25)) return ShapeGuess('star', math.min(1, corners / 10));
      if (cv < 0.16 && corners <= 2) return ShapeGuess('circle', 1 - cv * 3);
      if (corners == 3) return const ShapeGuess('triangle', 0.8);
      if (corners == 4) return const ShapeGuess('square', 0.75);
      if (_looksLikeHeart(pts, bounds)) return const ShapeGuess('heart', 0.6);
      if (cv < 0.24) return ShapeGuess('circle', 0.6 - cv);
      return ShapeGuess(corners <= 4 ? 'triangle' : 'star', 0.4);
    }

    if (corners >= 3 && signChanges >= 2) return ShapeGuess('zigzag', math.min(1, corners / 5));
    if (signChanges >= 2) return ShapeGuess('wave', math.min(1, signChanges / 4));
    if (absTurn > math.pi * 0.6 && signChanges == 0) return const ShapeGuess('arc', 0.7);
    if (corners >= 2) return const ShapeGuess('zigzag', 0.5);
    return const ShapeGuess('scribble', 0.3);
  }

  /// A heart has a dip at the top center and a point at the bottom.
  bool _looksLikeHeart(List<Offset> pts, Rect b) {
    final topCenter = Offset(b.center.dx, b.top);
    final bottomCenter = Offset(b.center.dx, b.bottom);
    var nearTopCenter = double.infinity, nearBottom = double.infinity;
    for (final p in pts) {
      nearTopCenter = math.min(nearTopCenter, (p - topCenter).distance);
      nearBottom = math.min(nearBottom, (p - bottomCenter).distance);
    }
    return nearTopCenter > b.height * 0.12 && nearBottom < b.height * 0.08;
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }

  /// Counts sharp direction changes using a wider window, which is robust to
  /// hand tremor.
  int _corners(List<Offset> pts, {required bool closed}) {
    const k = 4;
    // For closed shapes walk the loop cyclically so the corner where the
    // stroke starts and ends is counted too.
    final ring = closed ? pts.sublist(0, pts.length - 1) : pts;
    final n = ring.length;
    Offset at(int i) => closed ? ring[((i % n) + n) % n] : ring[i];
    final from = closed ? 0 : k;
    final to = closed ? n : n - k;
    var count = 0;
    var cooldown = 0;
    for (var i = from; i < to; i++) {
      if (cooldown > 0) {
        cooldown--;
        continue;
      }
      final a = at(i) - at(i - k);
      final b = at(i + k) - at(i);
      if (a.distance < 1e-9 || b.distance < 1e-9) continue;
      final ang = _wrap(math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)).abs();
      if (ang > math.pi * 0.42) {
        count++;
        cooldown = k;
      }
    }
    // A corner straddling the seam can be seen at both ends of the scan.
    if (closed && count > 0) {
      final first = _turnAt(at, 0, k), last = _turnAt(at, n - 1, k);
      if (first > math.pi * 0.42 && last > math.pi * 0.42) count--;
    }
    return count;
  }

  static double _turnAt(Offset Function(int) at, int i, int k) {
    final a = at(i) - at(i - k);
    final b = at(i + k) - at(i);
    if (a.distance < 1e-9 || b.distance < 1e-9) return 0;
    return _wrap(math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)).abs();
  }

  static double _pathLength(List<Offset> pts) {
    var l = 0.0;
    for (var i = 1; i < pts.length; i++) {
      l += (pts[i] - pts[i - 1]).distance;
    }
    return l;
  }

  static Rect _bounds(List<Offset> pts) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static Offset _centroid(List<Offset> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  /// Resamples a polyline into [n] equidistant points.
  static List<Offset> resample(List<Offset> pts, int n) {
    final total = _pathLength(pts);
    if (total == 0) return List.filled(n, pts.first);
    final interval = total / (n - 1);
    final out = <Offset>[pts.first];
    var acc = 0.0;
    var prev = pts.first;
    for (var i = 1; i < pts.length; i++) {
      var cur = pts[i];
      var d = (cur - prev).distance;
      while (acc + d >= interval && out.length < n) {
        final t = (interval - acc) / d;
        final q = Offset.lerp(prev, cur, t)!;
        out.add(q);
        prev = q;
        d = (cur - prev).distance;
        acc = 0;
      }
      acc += d;
      prev = cur;
    }
    while (out.length < n) {
      out.add(pts.last);
    }
    return out;
  }
}
