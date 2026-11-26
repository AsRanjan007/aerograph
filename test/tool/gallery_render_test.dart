// Renders every art template to a contact sheet PNG for visual review.
// Run: flutter test test/tool/gallery_render_test.dart --dart-define=OUT=/path/gallery.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aerograph/magic/art_library.dart';
import 'package:aerograph/magic/magic_build.dart';
import 'package:aerograph/magic/recommender.dart';
import 'package:aerograph/paint/stroke_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('render gallery', () async {
    const out = String.fromEnvironment('OUT');
    if (out.isEmpty) return;
    final rec = Recommender();
    final arts = [
      for (final t in artLibrary) rec.artFor(t),
      rec.fromImagination('moon over the mountains').first.art,
      rec.fromImagination('birthday balloons and music at night').first.art,
    ];
    const cell = 220.0, cols = 6;
    final rows = (arts.length / cols).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, cell * cols, 2000), Paint()..color = const Color(0xFF07061A));
    const r = StrokeRenderer();
    for (var i = 0; i < arts.length; i++) {
      final area = Rect.fromLTWH((i % cols) * cell, (i ~/ cols) * cell, cell, cell);
      final b = MagicBuild.layout(art: arts[i], area: area, glow: 0.8, widthScale: 0.7);
      for (final s in b.strokes) {
        r.paintStroke(canvas, s);
      }
    }
    final img = await recorder.endRecording().toImage((cell * cols).round(), (cell * rows).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(out).writeAsBytesSync(data!.buffer.asUint8List());
  });
}
