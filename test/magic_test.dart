import 'dart:math' as math;
import 'dart:ui';

import 'package:aerograph/magic/art_library.dart';
import 'package:aerograph/magic/claude_dream.dart';
import 'package:aerograph/magic/magic_build.dart';
import 'package:aerograph/magic/recommender.dart';
import 'package:aerograph/magic/shape_recognizer.dart';
import 'package:aerograph/paint/brush.dart';
import 'package:flutter_test/flutter_test.dart';

List<Offset> circle({double r = 100, int n = 60, double noise = 0}) {
  final rnd = math.Random(1);
  return [
    for (var i = 0; i <= n; i++)
      Offset(
        200 + r * math.cos(2 * math.pi * i / n) + (rnd.nextDouble() - 0.5) * noise,
        200 + r * math.sin(2 * math.pi * i / n) + (rnd.nextDouble() - 0.5) * noise,
      ),
  ];
}

List<Offset> polygon(List<Offset> corners, {int per = 15}) {
  final out = <Offset>[];
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    for (var k = 0; k < per; k++) {
      out.add(Offset.lerp(a, b, k / per)!);
    }
  }
  out.add(corners.first);
  return out;
}

void main() {
  group('library', () {
    test('every template builds valid unit-space paths', () {
      final ids = <String>{};
      for (final t in artLibrary) {
        expect(ids.add(t.id), isTrue, reason: 'duplicate id ${t.id}');
        final paths = t.build();
        expect(paths, isNotEmpty, reason: t.id);
        for (final p in paths) {
          expect(p.points.length, greaterThanOrEqualTo(2), reason: t.id);
          for (final o in p.points) {
            expect(o.dx.isFinite && o.dy.isFinite, isTrue, reason: t.id);
            expect(o.dx, inInclusiveRange(-0.05, 1.05), reason: '${t.id} x=${o.dx}');
            expect(o.dy, inInclusiveRange(-0.05, 1.05), reason: '${t.id} y=${o.dy}');
          }
          expect(p.color, inInclusiveRange(0, 3), reason: t.id);
        }
      }
      expect(artLibrary.length, greaterThanOrEqualTo(25));
    });
  });

  group('recommender', () {
    final r = Recommender();

    test('matches a single idea', () {
      final recs = r.fromImagination('I want a glowing moon');
      expect(recs.first.title, 'Crescent Moon');
    });

    test('stems plurals and verbs', () {
      expect(r.fromImagination('mountains').first.title, 'Mountain Range');
      expect(r.fromImagination('flying birds').map((e) => e.title), contains('Flying Birds'));
    });

    test('tolerates a typo', () {
      expect(r.fromImagination('butterfy').first.title, 'Light Butterfly');
    });

    test('composes a scene from several ideas', () {
      final recs = r.fromImagination('a moon over the mountains');
      expect(recs.first.reason, contains('scene'));
      expect(recs.first.title, contains('Moon'));
      expect(recs.first.title, contains('Mountain'));
      expect(recs.first.art.aspect, closeTo(0.75, 1e-9));
    });

    test('applies the mood palette', () {
      final recs = r.fromImagination('flower at night');
      final flower = recs.firstWhere((x) => x.title == 'Blooming Flower');
      expect(flower.art.palette, LightPalette.cosmic);
    });

    test('never comes back empty', () {
      expect(r.fromImagination('qwzx plorb'), isNotEmpty);
      expect(r.fromImagination(''), isNotEmpty);
    });

    test('sketch suggestions follow the shape', () {
      final recs = r.fromSketch(const ShapeGuess('spiral', 0.9));
      expect(recs.map((e) => e.title), contains('Spiral Galaxy'));
      expect(r.fromSketch(const ShapeGuess('scribble', 0.9)), isEmpty);
    });
  });

  group('shape recognizer', () {
    const sr = ShapeRecognizer();

    test('circle', () => expect(sr.recognize(circle(noise: 8)).shape, 'circle'));

    test('triangle', () {
      final t = polygon(const [Offset(100, 300), Offset(200, 100), Offset(300, 300)]);
      expect(sr.recognize(t).shape, 'triangle');
    });

    test('square', () {
      final s = polygon(const [Offset(100, 100), Offset(300, 100), Offset(300, 300), Offset(100, 300)]);
      expect(sr.recognize(s).shape, 'square');
    });

    test('line', () {
      expect(sr.recognize([for (var i = 0; i < 30; i++) Offset(i * 10.0, i * 3.0)]).shape, 'line');
    });

    test('wave', () {
      expect(
        sr.recognize([for (var i = 0; i <= 80; i++) Offset(i * 5.0, 200 + 40 * math.sin(i / 80 * 4 * math.pi))]).shape,
        'wave',
      );
    });

    test('zigzag', () {
      final z = <Offset>[];
      const peaks = [
        Offset(0, 200),
        Offset(60, 100),
        Offset(120, 200),
        Offset(180, 100),
        Offset(240, 200),
        Offset(300, 100),
      ];
      for (var i = 0; i < peaks.length - 1; i++) {
        for (var k = 0; k < 12; k++) {
          z.add(Offset.lerp(peaks[i], peaks[i + 1], k / 12)!);
        }
      }
      z.add(peaks.last);
      expect(sr.recognize(z).shape, 'zigzag');
    });

    test('spiral', () {
      final s = [
        for (var i = 0; i <= 200; i++)
          () {
            final t = i / 200 * 6 * math.pi;
            final rr = 10 + t * 12;
            return Offset(200 + rr * math.cos(t), 200 + rr * math.sin(t));
          }(),
      ];
      expect(sr.recognize(s).shape, 'spiral');
    });

    test('too short is a scribble', () {
      expect(sr.recognize(const [Offset(0, 0), Offset(1, 1)]).shape, 'scribble');
    });
  });

  group('magic build', () {
    final art = Recommender().artFor(templateById('star')!);

    test('layout fits the art inside the area', () {
      const area = Rect.fromLTWH(0, 0, 400, 800);
      final b = MagicBuild.layout(art: art, area: area, glow: 0.8);
      for (final s in b.strokes) {
        for (final p in s.points) {
          expect(area.inflate(1).contains(p), isTrue);
        }
        expect(s.magic, isTrue);
      }
    });

    test('reveals progressively', () {
      final b = MagicBuild.layout(art: art, area: const Rect.fromLTWH(0, 0, 400, 400), glow: 0.8);
      double len(List s) => s.fold<double>(0, (a, x) => a + (x.length as double));
      expect(b.visibleAt(0), isEmpty);
      expect(len(b.visibleAt(0.5)), closeTo(b.totalLength / 2, 1));
      expect(b.visibleAt(1), b.strokes);
      expect(b.duration.inMilliseconds, inInclusiveRange(1600, 4200));
    });
  });

  group('Claude dream parsing', () {
    test('parses valid art and clamps coordinates', () {
      final art = ClaudeDreamer.parseArt('''
        {"title": "Lotus", "brush": "glow", "palette": ["#FF4D8D", "#38BDF8", "bad"],
         "strokes": [{"color": 3, "width": 9, "points": [[0.1, 0.2], [1.4, -0.2], [0.5, 0.5]]},
                     {"color": 0, "width": 1, "points": [[0.3, 0.3]]}]}''');
      expect(art.title, 'Lotus');
      expect(art.brush, BrushKind.glow);
      expect(art.palette.colors, hasLength(2));
      expect(art.paths, hasLength(1)); // single-point stroke dropped
      expect(art.paths.first.points[1], const Offset(1, 0));
      expect(art.paths.first.color, 1); // 3 % 2
      expect(art.paths.first.width, 2.0);
    });

    test('rejects empty drawings', () {
      expect(
        () => ClaudeDreamer.parseArt('{"title":"x","brush":"neon","palette":[],"strokes":[]}'),
        throwsA(isA<DreamException>()),
      );
      expect(() => ClaudeDreamer.parseArt('not json'), throwsA(isA<DreamException>()));
    });
  });
}
