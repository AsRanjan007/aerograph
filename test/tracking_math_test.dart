import 'dart:ui';

import 'package:aero_hand_tracker/aero_hand_tracker.dart';
import 'package:aerograph/tracking/frame_mapper.dart';
import 'package:aerograph/tracking/one_euro_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameMapper', () {
    test('identical aspect ratios map corners to corners', () {
      const m = FrameMapper(
        analysisSize: Size(240, 320),
        previewSize: Size(480, 640),
        screenSize: Size(390, 520),
        mirror: false,
      );
      expect(m.map(0, 0), const Offset(0, 0));
      final br = m.map(1, 1);
      expect(br.dx, closeTo(390, 1e-6));
      expect(br.dy, closeTo(520, 1e-6));
    });

    test('mirror flips x', () {
      const m = FrameMapper(
        analysisSize: Size(240, 320),
        previewSize: Size(240, 320),
        screenSize: Size(240, 320),
        mirror: true,
      );
      expect(m.map(0.25, 0.5).dx, closeTo(180, 1e-6));
    });

    test('taller screen crops the sides (cover)', () {
      const m = FrameMapper(
        analysisSize: Size(300, 400),
        previewSize: Size(300, 400),
        screenSize: Size(300, 650),
        mirror: false,
      );
      // centre stays centre
      final c = m.map(0.5, 0.5);
      expect(c.dx, closeTo(150, 1e-6));
      expect(c.dy, closeTo(325, 1e-6));
      // left edge of the frame is off-screen
      expect(m.map(0, 0.5).dx, lessThan(0));
      expect(m.map(0.5, 0).dy, closeTo(0, 1e-6));
    });
  });

  group('OneEuroFilter', () {
    test('first sample passes through', () {
      final f = OneEuroFilter();
      expect(f.filter(const Offset(10, 20), 0), const Offset(10, 20));
    });

    test('suppresses jitter on a still finger', () {
      final f = OneEuroFilter(minCutoff: 1.0, beta: 0.0);
      f.filter(const Offset(100, 100), 0);
      var out = Offset.zero;
      for (var i = 1; i < 30; i++) {
        out = f.filter(Offset(100 + (i.isEven ? 4 : -4), 100), i * 33);
      }
      expect((out.dx - 100).abs(), lessThan(2.5));
    });

    test('follows a fast move', () {
      final f = OneEuroFilter(minCutoff: 1.0, beta: 0.05);
      f.filter(Offset.zero, 0);
      var out = Offset.zero;
      for (var i = 1; i <= 10; i++) {
        out = f.filter(Offset(i * 40.0, 0), i * 33);
      }
      expect(out.dx, greaterThan(300));
    });
  });

  test('parses native results', () {
    final r = AeroHandTracker.parseResult({
      'hands': [
        {'landmarks': List<double>.generate(63, (i) => i / 100), 'handedness': 'Right', 'score': 0.97},
      ],
      'imageWidth': 240,
      'imageHeight': 320,
      'inferenceMs': 18,
    });
    expect(r.hands, hasLength(1));
    expect(r.hands.first.landmarks, hasLength(21));
    expect(r.hands.first.landmarks[1].x, closeTo(0.03, 1e-9));
    expect(r.imageHeight, 320);
    expect(r.inferenceMs, 18);
  });
}
