import 'dart:ui';

import 'package:aerograph/paint/brush.dart';
import 'package:aerograph/paint/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = BrushStyle(kind: BrushKind.neon, color: Color(0xFFFFFFFF), width: 5, glow: 0.5);

Stroke line(double y) => Stroke(style: _style, points: [Offset(0, y), Offset(100, y)]);

void main() {
  test('addPoint skips points that barely moved', () {
    final s = Stroke(style: _style);
    expect(s.addPoint(Offset.zero), isTrue);
    expect(s.addPoint(const Offset(1, 1)), isFalse);
    expect(s.addPoint(const Offset(10, 0)), isTrue);
    expect(s.points, hasLength(2));
  });

  test('partial truncates by arc length', () {
    final s = Stroke(style: _style, points: const [Offset(0, 0), Offset(100, 0), Offset(100, 100)]);
    final half = s.partial(0.5);
    expect(half.length, closeTo(100, 1e-6));
    expect(half.points.last, const Offset(100, 0));
    final q = s.partial(0.25);
    expect(q.points.last.dx, closeTo(50, 1e-6));
  });

  test('undo removes a magic group as one step, redo restores it', () {
    final h = StrokeHistory();
    h.add(line(0));
    h.addAll([line(1), line(2), line(3)]);
    expect(h.strokes, hasLength(4));
    h.undo();
    expect(h.strokes, hasLength(1));
    h.redo();
    expect(h.strokes, hasLength(4));
  });

  test('clear is undoable via redo', () {
    final h = StrokeHistory()
      ..add(line(0))
      ..add(line(1));
    h.clear();
    expect(h.strokes, isEmpty);
    h.redo();
    expect(h.strokes, hasLength(2));
  });

  test('remove keeps group bookkeeping consistent', () {
    final h = StrokeHistory();
    final a = line(0);
    h.add(a);
    h.addAll([line(1), line(2)]);
    h.remove(a);
    expect(h.strokes, hasLength(2));
    h.undo();
    expect(h.strokes, isEmpty);
  });

  test('revision changes on every edit', () {
    final h = StrokeHistory();
    final r0 = h.revision;
    h.add(line(0));
    expect(h.revision, greaterThan(r0));
  });
}
