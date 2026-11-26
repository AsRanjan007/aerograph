// Renders key screens to PNGs for visual review with a simulated hand.
// Run: flutter test test/tool/screens_render_test.dart --dart-define=OUT_DIR=/some/dir
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aerograph/app/settings.dart';
import 'package:aerograph/tracking/air_tracker.dart';
import 'package:aerograph/tracking/hand_pose.dart';
import 'package:aerograph/ui/splash_screen.dart';
import 'package:aerograph/ui/studio_screen.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const outDir = String.fromEnvironment('OUT_DIR');

class FakeTracker extends AirTracker {
  @override
  Future<void> start({bool front = true}) async {
    status = TrackerStatus.running;
    fps = 28;
    notifyListeners();
  }

  @override
  Future<void> stop() async {}

  void move(Offset p, HandPose pose) {
    pointer.value = AirPointer(visible: true, position: p, pose: pose, depth: 1.0);
  }
}

Future<void> loadFonts() async {
  const base = '/opt/sdk/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$base/$f.ttf').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$base/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

final _shot = GlobalKey();

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget host(Widget child) => RepaintBoundary(
  key: _shot,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5CF6), brightness: Brightness.dark),
      fontFamily: 'Roboto',
    ),
    home: child,
  ),
);

void main() {
  if (outDir.isEmpty) return;

  setUpAll(loadFonts);

  testWidgets('splash', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = AppSettings.memory()..onboarded = true;
    await tester.pumpWidget(host(SplashScreen(settings: s)));
    await tester.pump(const Duration(milliseconds: 2300));
    await capture(tester, '1_splash');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('studio flow', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = AppSettings.memory()
      ..onboarded = true
      ..cameraDim = 0.0;
    final t = FakeTracker();
    await tester.pumpWidget(host(StudioScreen(settings: s, tracker: t)));
    await tester.pump(const Duration(milliseconds: 100));

    // Paint a wavy line with the index finger, then lift with two fingers.
    for (var i = 0; i <= 40; i++) {
      t.move(Offset(40 + i * 7.5, 250 + 40 * math.sin(i / 40 * 2 * math.pi)), HandPose.point);
      await tester.pump(const Duration(milliseconds: 16));
    }
    t.move(const Offset(340, 250), HandPose.peace);
    await tester.pump(const Duration(milliseconds: 50));

    // Second stroke in another colour: a circle → sketch suggestions.
    s.update((x) => x.color = const Color(0xFF38BDF8));
    for (var i = 0; i <= 48; i++) {
      final a = i / 48 * 2 * math.pi;
      t.move(Offset(195 + 80 * math.cos(a), 480 + 80 * math.sin(a)), HandPose.point);
      await tester.pump(const Duration(milliseconds: 16));
    }
    t.move(const Offset(300, 400), HandPose.peace);
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, '2_studio_sketch_suggestions');

    // Pick the first suggestion → magic build.
    await tester.tap(find.text('Radiant Sun').first);
    await tester.pump(const Duration(milliseconds: 16)); // animation starts on this frame
    await tester.pump(const Duration(milliseconds: 1300));
    await capture(tester, '3_magic_building');
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('Neon').first);
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, '4_magic_done_light_panel');

    // Imagine sheet.
    await tester.tap(find.text('Imagine'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'a moon over the mountains');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await capture(tester, '5_imagine_sheet');

    await tester.tap(find.text('Moon & Mountain'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 5));
    t.move(const Offset(120, 600), HandPose.peace);
    await tester.pump(const Duration(milliseconds: 100));
    await capture(tester, '6_scene_built');
    await tester.pumpWidget(const SizedBox());
  });
}
