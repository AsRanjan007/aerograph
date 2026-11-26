import 'dart:math' as math;
import 'dart:ui';

import 'brush.dart';

class Stroke {
  Stroke({required this.style, List<Offset>? points, this.magic = false, int? seed})
    : points = points ?? <Offset>[],
      seed = seed ?? math.Random().nextInt(1 << 30);

  final BrushStyle style;
  final List<Offset> points;

  /// Created by the magic builder rather than by hand.
  final bool magic;

  /// Stable randomness for sparkle placement / hue offsets.
  final int seed;

  /// Adds a point if it moved far enough from the previous one, keeping the
  /// stroke light and the curve smooth.
  bool addPoint(Offset p, {double minDistance = 2.5}) {
    if (points.isNotEmpty && (points.last - p).distance < minDistance) return false;
    points.add(p);
    return true;
  }

  double get length {
    var l = 0.0;
    for (var i = 1; i < points.length; i++) {
      l += (points[i] - points[i - 1]).distance;
    }
    return l;
  }

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Returns a copy truncated to [fraction] (0..1) of its arc length.
  Stroke partial(double fraction) {
    if (fraction >= 1 || points.length < 2) return this;
    final target = length * fraction.clamp(0.0, 1.0);
    final out = <Offset>[points.first];
    var acc = 0.0;
    for (var i = 1; i < points.length; i++) {
      final seg = (points[i] - points[i - 1]).distance;
      if (acc + seg >= target) {
        final t = seg == 0 ? 0.0 : (target - acc) / seg;
        out.add(Offset.lerp(points[i - 1], points[i], t)!);
        break;
      }
      acc += seg;
      out.add(points[i]);
    }
    return Stroke(style: style, points: out, magic: magic, seed: seed);
  }
}

/// Undo/redo-able list of strokes.
class StrokeHistory {
  final List<Stroke> strokes = [];
  final List<List<Stroke>> _redo = [];

  /// Incremented on every change; painters use it to know when to repaint.
  int revision = 0;

  bool get canUndo => strokes.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void add(Stroke s) => addAll([s]);

  /// Adds a group that undoes as one step (e.g. one magic build).
  void addAll(List<Stroke> group) {
    if (group.isEmpty) return;
    strokes.addAll(group);
    _groups.add(group.length);
    _redo.clear();
    revision++;
  }

  final List<int> _groups = [];

  void undo() {
    if (_groups.isEmpty) return;
    final n = _groups.removeLast();
    final removed = strokes.sublist(strokes.length - n);
    strokes.removeRange(strokes.length - n, strokes.length);
    _redo.add(removed);
    revision++;
  }

  void redo() {
    if (_redo.isEmpty) return;
    final group = _redo.removeLast();
    strokes.addAll(group);
    _groups.add(group.length);
    revision++;
  }

  /// Removes one specific stroke (used when a sketch is transformed by magic).
  void remove(Stroke s) {
    final i = strokes.indexOf(s);
    if (i < 0) return;
    // Find which group holds it and shrink that group.
    var start = 0;
    for (var g = 0; g < _groups.length; g++) {
      if (i < start + _groups[g]) {
        _groups[g]--;
        if (_groups[g] == 0) _groups.removeAt(g);
        break;
      }
      start += _groups[g];
    }
    strokes.removeAt(i);
    revision++;
  }

  void clear() {
    if (strokes.isEmpty) return;
    _redo.add(List.of(strokes));
    strokes.clear();
    _groups.clear();
    revision++;
  }
}
