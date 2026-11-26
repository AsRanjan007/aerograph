import 'dart:math' as math;
import 'dart:ui';

import '../paint/brush.dart';

/// One polyline of a template, in unit coordinates (0..1, y pointing down).
class ArtPath {
  const ArtPath(this.points, {this.color = 0, this.width = 1.0});
  final List<Offset> points;

  /// Index into the palette the art is rendered with.
  final int color;

  /// Multiplier on the brush width.
  final double width;
}

/// Where a template naturally sits when composed into a scene.
enum ArtLayer { sky, center, ground }

class ArtTemplate {
  const ArtTemplate({
    required this.id,
    required this.title,
    required this.keywords,
    required this.layer,
    required this.palette,
    required this.brush,
    required this.build,
    this.shapes = const {},
  });

  final String id;
  final String title;
  final List<String> keywords;
  final ArtLayer layer;
  final LightPalette palette;
  final BrushKind brush;
  final List<ArtPath> Function() build;

  /// Sketch shapes (from the shape recognizer) this template grows out of.
  final Set<String> shapes;
}

// ---------------------------------------------------------------------------
// Geometry helpers (unit space)
// ---------------------------------------------------------------------------

const _tau = math.pi * 2;

List<Offset> _circle(double cx, double cy, double r, {int n = 48, double start = -math.pi / 2, double sweep = _tau}) {
  return [
    for (var i = 0; i <= n; i++)
      Offset(cx + r * math.cos(start + sweep * i / n), cy + r * math.sin(start + sweep * i / n)),
  ];
}

List<Offset> _ellipse(double cx, double cy, double rx, double ry, {int n = 56, double rot = 0, double start = 0, double sweep = _tau}) {
  final c = math.cos(rot), s = math.sin(rot);
  return [
    for (var i = 0; i <= n; i++)
      () {
        final a = start + sweep * i / n;
        final x = rx * math.cos(a), y = ry * math.sin(a);
        return Offset(cx + x * c - y * s, cy + x * s + y * c);
      }(),
  ];
}

List<Offset> _poly(List<List<double>> xy) => [for (final p in xy) Offset(p[0], p[1])];

List<Offset> _bezier(Offset a, Offset c1, Offset c2, Offset b, {int n = 24}) {
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = i / n, u = 1 - t;
        return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t);
      }(),
  ];
}

List<Offset> _wave(double x0, double x1, double y, double amp, double cycles, {int n = 60, double phase = 0}) {
  return [
    for (var i = 0; i <= n; i++)
      Offset(x0 + (x1 - x0) * i / n, y + amp * math.sin(phase + _tau * cycles * i / n)),
  ];
}

List<Offset> _starShape(double cx, double cy, double rOuter, double rInner, {int points = 5}) {
  final out = <Offset>[];
  for (var i = 0; i <= points * 2; i++) {
    final r = i.isEven ? rOuter : rInner;
    final a = -math.pi / 2 + math.pi * i / points;
    out.add(Offset(cx + r * math.cos(a), cy + r * math.sin(a)));
  }
  return out;
}

List<Offset> _heart(double cx, double cy, double s, {int n = 80}) {
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = _tau * i / n;
        final x = 16 * math.pow(math.sin(t), 3);
        final y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
        return Offset(cx + x * s / 34, cy - y * s / 34);
      }(),
  ];
}

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------

List<ArtPath> _sun() => [
      ArtPath(_circle(0.5, 0.5, 0.2), color: 0, width: 1.3),
      for (var i = 0; i < 12; i++)
        () {
          final a = _tau * i / 12;
          final r0 = 0.27, r1 = i.isEven ? 0.42 : 0.36;
          return ArtPath([
            Offset(0.5 + r0 * math.cos(a), 0.5 + r0 * math.sin(a)),
            Offset(0.5 + r1 * math.cos(a), 0.5 + r1 * math.sin(a)),
          ], color: i.isEven ? 1 : 0);
        }(),
    ];

List<ArtPath> _moon() => [
      ArtPath([
        ..._circle(0.5, 0.5, 0.34, start: -math.pi * 0.35, sweep: -math.pi * 1.3),
        ..._bezier(const Offset(0.654, 0.803), const Offset(0.4, 0.72), const Offset(0.4, 0.28), const Offset(0.654, 0.197)),
      ], color: 0, width: 1.2),
      ArtPath(_starShape(0.83, 0.22, 0.05, 0.02), color: 2, width: 0.6),
      ArtPath(_starShape(0.76, 0.68, 0.035, 0.014), color: 2, width: 0.5),
    ];

List<ArtPath> _star() => [
      ArtPath(_starShape(0.5, 0.52, 0.42, 0.17), color: 0, width: 1.3),
      ArtPath(_starShape(0.5, 0.52, 0.2, 0.08), color: 1, width: 0.7),
    ];

List<ArtPath> _heartArt() => [
      ArtPath(_heart(0.5, 0.52, 0.8), color: 0, width: 1.3),
      ArtPath(_heart(0.5, 0.5, 0.45), color: 1, width: 0.8),
    ];

List<ArtPath> _flower() {
  final petals = <Offset>[];
  for (var i = 0; i <= 160; i++) {
    final t = _tau * i / 160;
    final r = 0.2 * (0.55 + 0.45 * math.cos(5 * t).abs());
    petals.add(Offset(0.5 + r * math.cos(t), 0.33 + r * math.sin(t)));
  }
  return [
    ArtPath(petals, color: 0, width: 1.1),
    ArtPath(_circle(0.5, 0.33, 0.045), color: 3, width: 1.0),
    ArtPath(_bezier(const Offset(0.5, 0.42), const Offset(0.47, 0.6), const Offset(0.53, 0.75), const Offset(0.5, 0.95)), color: 2),
    ArtPath(_bezier(const Offset(0.5, 0.72), const Offset(0.6, 0.62), const Offset(0.7, 0.62), const Offset(0.74, 0.66)), color: 2),
    ArtPath(_bezier(const Offset(0.74, 0.66), const Offset(0.66, 0.74), const Offset(0.56, 0.74), const Offset(0.5, 0.72)), color: 2),
    ArtPath(_bezier(const Offset(0.5, 0.82), const Offset(0.4, 0.72), const Offset(0.3, 0.72), const Offset(0.26, 0.76)), color: 2),
    ArtPath(_bezier(const Offset(0.26, 0.76), const Offset(0.34, 0.84), const Offset(0.44, 0.84), const Offset(0.5, 0.82)), color: 2),
  ];
}

List<ArtPath> _tree() {
  final canopy = <Offset>[];
  const bumps = 7;
  for (var i = 0; i <= 140; i++) {
    final t = _tau * i / 140;
    final r = 0.27 + 0.035 * math.cos(bumps * t);
    canopy.add(Offset(0.5 + r * math.cos(t), 0.38 + r * 0.9 * math.sin(t)));
  }
  return [
    ArtPath(canopy, color: 0, width: 1.1),
    ArtPath(_poly([[0.46, 0.95], [0.47, 0.62], [0.4, 0.52]]), color: 3, width: 1.2),
    ArtPath(_poly([[0.54, 0.95], [0.53, 0.6], [0.62, 0.5]]), color: 3, width: 1.2),
    ArtPath(_poly([[0.5, 0.64], [0.5, 0.46]]), color: 3, width: 0.9),
    ArtPath(_poly([[0.3, 0.95], [0.7, 0.95]]), color: 1, width: 0.8),
  ];
}

List<ArtPath> _mountains() => [
      ArtPath(_poly([[0.0, 0.9], [0.22, 0.45], [0.36, 0.66], [0.55, 0.22], [0.78, 0.62], [0.88, 0.5], [1.0, 0.9]]), color: 0, width: 1.2),
      ArtPath(_poly([[0.48, 0.36], [0.55, 0.22], [0.62, 0.36], [0.58, 0.33], [0.55, 0.38], [0.52, 0.33], [0.48, 0.36]]), color: 3, width: 0.8),
      ArtPath(_poly([[0.17, 0.55], [0.22, 0.45], [0.27, 0.55]]), color: 3, width: 0.7),
      ArtPath(_poly([[0.0, 0.95], [1.0, 0.95]]), color: 1, width: 0.7),
    ];

List<ArtPath> _waves() => [
      ArtPath(_wave(0.0, 1.0, 0.4, 0.06, 2.0), color: 0, width: 1.2),
      ArtPath(_wave(0.0, 1.0, 0.56, 0.05, 2.5, phase: 1.2), color: 1),
      ArtPath(_wave(0.0, 1.0, 0.72, 0.04, 3.0, phase: 2.4), color: 2, width: 0.9),
      ArtPath(_wave(0.05, 0.95, 0.86, 0.025, 4.0, phase: 0.6), color: 3, width: 0.7),
    ];

List<ArtPath> _rainbow() => [
      for (var i = 0; i < 5; i++)
        ArtPath(_circle(0.5, 0.82, 0.44 - i * 0.06, start: math.pi, sweep: math.pi, n: 48), color: i % 4, width: 1.1),
      ArtPath(_poly([[0.0, 0.85], [0.2, 0.85]]), color: 3, width: 0.6),
      ArtPath(_poly([[0.8, 0.85], [1.0, 0.85]]), color: 3, width: 0.6),
    ];

List<ArtPath> _lightning() => [
      ArtPath(_poly([[0.58, 0.02], [0.3, 0.5], [0.5, 0.5], [0.36, 0.98], [0.74, 0.4], [0.52, 0.4], [0.7, 0.02]]), color: 0, width: 1.3),
      ArtPath(_poly([[0.22, 0.2], [0.14, 0.32]]), color: 1, width: 0.6),
      ArtPath(_poly([[0.82, 0.62], [0.9, 0.74]]), color: 1, width: 0.6),
    ];

List<Offset> _cloudPath(double cx, double cy, double s) {
  final pts = <Offset>[];
  pts.addAll(_circle(cx - 0.22 * s, cy + 0.04 * s, 0.13 * s, start: math.pi * 0.5, sweep: math.pi * 1.1, n: 16));
  pts.addAll(_circle(cx - 0.04 * s, cy - 0.06 * s, 0.18 * s, start: math.pi * 1.05, sweep: math.pi * 0.95, n: 20));
  pts.addAll(_circle(cx + 0.18 * s, cy + 0.0 * s, 0.14 * s, start: math.pi * 1.4, sweep: math.pi * 1.1, n: 16));
  pts.add(Offset(cx - 0.22 * s, cy + 0.17 * s));
  return pts;
}

List<ArtPath> _cloud() => [
      ArtPath(_cloudPath(0.52, 0.45, 1.35), color: 0, width: 1.2),
      for (var i = 0; i < 4; i++)
        ArtPath(_poly([[0.3 + i * 0.13, 0.78], [0.27 + i * 0.13, 0.9]]), color: 1, width: 0.7),
    ];

List<ArtPath> _butterfly() {
  final wing = <Offset>[];
  for (var i = 0; i <= 240; i++) {
    final t = 12 * math.pi * i / 240;
    final r = math.exp(math.cos(t)) - 2 * math.cos(4 * t) - math.pow(math.sin(t / 12), 5);
    wing.add(Offset(0.5 + 0.085 * r * math.sin(t), 0.52 - 0.085 * r * math.cos(t)));
  }
  return [
    ArtPath(wing, color: 0, width: 0.8),
    ArtPath(_poly([[0.5, 0.36], [0.5, 0.66]]), color: 2, width: 1.2),
    ArtPath(_bezier(const Offset(0.5, 0.36), const Offset(0.48, 0.28), const Offset(0.44, 0.22), const Offset(0.4, 0.2)), color: 2, width: 0.6),
    ArtPath(_bezier(const Offset(0.5, 0.36), const Offset(0.52, 0.28), const Offset(0.56, 0.22), const Offset(0.6, 0.2)), color: 2, width: 0.6),
  ];
}

List<ArtPath> _fish() => [
      ArtPath([
        ..._bezier(const Offset(0.15, 0.5), const Offset(0.3, 0.22), const Offset(0.62, 0.22), const Offset(0.75, 0.5)),
        ..._bezier(const Offset(0.75, 0.5), const Offset(0.62, 0.78), const Offset(0.3, 0.78), const Offset(0.15, 0.5)),
      ], color: 0, width: 1.2),
      ArtPath(_poly([[0.72, 0.5], [0.92, 0.32], [0.88, 0.5], [0.92, 0.68], [0.72, 0.5]]), color: 1),
      ArtPath(_circle(0.28, 0.45, 0.025), color: 3, width: 0.8),
      ArtPath(_bezier(const Offset(0.42, 0.32), const Offset(0.38, 0.42), const Offset(0.38, 0.58), const Offset(0.42, 0.68)), color: 2, width: 0.7),
      ArtPath(_circle(0.1, 0.32, 0.025), color: 3, width: 0.5),
      ArtPath(_circle(0.06, 0.22, 0.018), color: 3, width: 0.5),
    ];

List<ArtPath> _birds() {
  List<Offset> bird(double cx, double cy, double s) => [
        ..._bezier(Offset(cx - 0.12 * s, cy - 0.02 * s), Offset(cx - 0.08 * s, cy - 0.08 * s), Offset(cx - 0.03 * s, cy - 0.06 * s), Offset(cx, cy)),
        ..._bezier(Offset(cx, cy), Offset(cx + 0.03 * s, cy - 0.06 * s), Offset(cx + 0.08 * s, cy - 0.08 * s), Offset(cx + 0.12 * s, cy - 0.02 * s)),
      ];
  return [
    ArtPath(bird(0.42, 0.45, 2.2), color: 0, width: 1.2),
    ArtPath(bird(0.72, 0.3, 1.4), color: 1),
    ArtPath(bird(0.2, 0.25, 1.1), color: 2, width: 0.9),
    ArtPath(bird(0.7, 0.66, 1.0), color: 3, width: 0.8),
  ];
}

List<ArtPath> _rocket() => [
      ArtPath([
        ..._bezier(const Offset(0.4, 0.72), const Offset(0.36, 0.45), const Offset(0.42, 0.22), const Offset(0.5, 0.06)),
        ..._bezier(const Offset(0.5, 0.06), const Offset(0.58, 0.22), const Offset(0.64, 0.45), const Offset(0.6, 0.72)),
        const Offset(0.4, 0.72),
      ], color: 0, width: 1.2),
      ArtPath(_circle(0.5, 0.36, 0.055), color: 1),
      ArtPath(_poly([[0.39, 0.56], [0.28, 0.74], [0.4, 0.72]]), color: 1),
      ArtPath(_poly([[0.61, 0.56], [0.72, 0.74], [0.6, 0.72]]), color: 1),
      ArtPath(_poly([[0.44, 0.74], [0.47, 0.88], [0.5, 0.8], [0.53, 0.95], [0.56, 0.74]]), color: 2, width: 1.1),
      ArtPath(_poly([[0.47, 0.76], [0.5, 0.86], [0.53, 0.76]]), color: 3, width: 0.7),
    ];

List<ArtPath> _house() => [
      ArtPath(_poly([[0.22, 0.5], [0.22, 0.9], [0.78, 0.9], [0.78, 0.5]]), color: 0, width: 1.2),
      ArtPath(_poly([[0.14, 0.54], [0.5, 0.18], [0.86, 0.54]]), color: 1, width: 1.2),
      ArtPath(_poly([[0.44, 0.9], [0.44, 0.7], [0.56, 0.7], [0.56, 0.9]]), color: 2),
      ArtPath(_poly([[0.28, 0.58], [0.38, 0.58], [0.38, 0.68], [0.28, 0.68], [0.28, 0.58]]), color: 3, width: 0.8),
      ArtPath(_poly([[0.62, 0.58], [0.72, 0.58], [0.72, 0.68], [0.62, 0.68], [0.62, 0.58]]), color: 3, width: 0.8),
      ArtPath(_poly([[0.66, 0.34], [0.66, 0.22], [0.72, 0.22], [0.72, 0.4]]), color: 1, width: 0.8),
    ];

List<ArtPath> _galaxy() {
  List<Offset> arm(double phase) => [
        for (var i = 0; i <= 90; i++)
          () {
            final t = i / 90 * 3.2 * math.pi;
            final r = 0.02 * math.exp(0.3 * t);
            return Offset(0.5 + r * math.cos(t + phase), 0.5 + r * 0.8 * math.sin(t + phase));
          }(),
      ];
  return [
    ArtPath(arm(0), color: 0, width: 1.1),
    ArtPath(arm(math.pi), color: 1, width: 1.1),
    ArtPath(_circle(0.5, 0.5, 0.04), color: 3, width: 1.4),
    ArtPath(_starShape(0.16, 0.18, 0.03, 0.012), color: 3, width: 0.5),
    ArtPath(_starShape(0.86, 0.8, 0.03, 0.012), color: 3, width: 0.5),
  ];
}

List<ArtPath> _planet() => [
      ArtPath(_circle(0.5, 0.5, 0.24), color: 0, width: 1.2),
      ArtPath(_ellipse(0.5, 0.5, 0.42, 0.1, rot: -0.35, start: 0.05, sweep: math.pi - 0.1), color: 1, width: 1.1),
      ArtPath(_ellipse(0.5, 0.5, 0.42, 0.1, rot: -0.35, start: math.pi + 0.6, sweep: math.pi - 1.2), color: 1, width: 1.1),
      ArtPath(_wave(0.32, 0.66, 0.44, 0.012, 2), color: 2, width: 0.6),
      ArtPath(_circle(0.86, 0.2, 0.035), color: 3, width: 0.7),
    ];

List<ArtPath> _crown() => [
      ArtPath(_poly([[0.18, 0.72], [0.12, 0.3], [0.32, 0.5], [0.5, 0.2], [0.68, 0.5], [0.88, 0.3], [0.82, 0.72], [0.18, 0.72]]), color: 0, width: 1.3),
      ArtPath(_poly([[0.18, 0.8], [0.82, 0.8]]), color: 0, width: 1.1),
      ArtPath(_circle(0.12, 0.26, 0.03), color: 1, width: 0.8),
      ArtPath(_circle(0.5, 0.16, 0.035), color: 2, width: 0.8),
      ArtPath(_circle(0.88, 0.26, 0.03), color: 1, width: 0.8),
      ArtPath(_circle(0.5, 0.62, 0.04), color: 2, width: 0.8),
    ];

List<ArtPath> _infinity() => [
      ArtPath([
        for (var i = 0; i <= 120; i++)
          () {
            final t = _tau * i / 120;
            final d = 1 + math.pow(math.sin(t), 2);
            return Offset(0.5 + 0.4 * math.cos(t) / d, 0.5 + 0.4 * math.sin(t) * math.cos(t) / d);
          }(),
      ], color: 0, width: 1.3),
    ];

List<ArtPath> _music() => [
      ArtPath(_ellipse(0.3, 0.75, 0.08, 0.055, rot: -0.4), color: 0, width: 1.2),
      ArtPath(_ellipse(0.68, 0.68, 0.08, 0.055, rot: -0.4), color: 0, width: 1.2),
      ArtPath(_poly([[0.37, 0.73], [0.37, 0.22], [0.75, 0.14], [0.75, 0.66]]), color: 1, width: 1.1),
      ArtPath(_poly([[0.37, 0.32], [0.75, 0.24]]), color: 1, width: 1.1),
      ArtPath(_wave(0.08, 0.92, 0.92, 0.02, 3), color: 2, width: 0.6),
    ];

List<ArtPath> _diamond() => [
      ArtPath(_poly([[0.2, 0.35], [0.35, 0.18], [0.65, 0.18], [0.8, 0.35], [0.5, 0.88], [0.2, 0.35]]), color: 0, width: 1.3),
      ArtPath(_poly([[0.2, 0.35], [0.8, 0.35]]), color: 1, width: 0.8),
      ArtPath(_poly([[0.35, 0.18], [0.42, 0.35], [0.5, 0.88], [0.58, 0.35], [0.65, 0.18]]), color: 1, width: 0.7),
      ArtPath(_poly([[0.42, 0.35], [0.5, 0.18], [0.58, 0.35]]), color: 2, width: 0.7),
      ArtPath(_starShape(0.84, 0.16, 0.04, 0.015, points: 4), color: 3, width: 0.5),
    ];

List<ArtPath> _balloons() {
  List<ArtPath> balloon(double cx, double cy, double s, int c) => [
        ArtPath(_ellipse(cx, cy, 0.11 * s, 0.14 * s, start: -math.pi / 2), color: c, width: 1.1),
        ArtPath(_poly([[cx - 0.015, cy + 0.14 * s + 0.02], [cx, cy + 0.14 * s], [cx + 0.015, cy + 0.14 * s + 0.02]]), color: c, width: 0.6),
        ArtPath(_bezier(Offset(cx, cy + 0.14 * s + 0.02), Offset(cx + 0.05, cy + 0.3), Offset(0.5 - 0.04, 0.8), const Offset(0.5, 0.95)), color: 3, width: 0.5),
      ];
  return [
    ...balloon(0.32, 0.3, 1.1, 0),
    ...balloon(0.62, 0.22, 1.2, 1),
    ...balloon(0.5, 0.45, 1.0, 2),
  ];
}

List<ArtPath> _snowflake() => [
      for (var i = 0; i < 6; i++)
        () {
          final a = _tau * i / 6 - math.pi / 2;
          Offset at(double r, [double da = 0]) => Offset(0.5 + r * math.cos(a + da), 0.5 + r * math.sin(a + da));
          return ArtPath([
            at(0.0), at(0.42), at(0.3), at(0.38, 0.35), at(0.3), at(0.38, -0.35), at(0.3),
            at(0.18), at(0.25, 0.5), at(0.18), at(0.25, -0.5),
          ], color: i % 2, width: 1.0);
        }(),
      ArtPath(_circle(0.5, 0.5, 0.06, n: 6, start: -math.pi / 2), color: 2, width: 0.8),
    ];

List<ArtPath> _flame() => [
      ArtPath([
        ..._bezier(const Offset(0.5, 0.95), const Offset(0.18, 0.88), const Offset(0.22, 0.5), const Offset(0.42, 0.3)),
        ..._bezier(const Offset(0.42, 0.3), const Offset(0.42, 0.45), const Offset(0.5, 0.48), const Offset(0.52, 0.06)),
        ..._bezier(const Offset(0.52, 0.06), const Offset(0.72, 0.3), const Offset(0.86, 0.66), const Offset(0.5, 0.95)),
      ], color: 2, width: 1.3),
      ArtPath([
        ..._bezier(const Offset(0.5, 0.9), const Offset(0.34, 0.84), const Offset(0.36, 0.62), const Offset(0.48, 0.48)),
        ..._bezier(const Offset(0.48, 0.48), const Offset(0.66, 0.64), const Offset(0.68, 0.84), const Offset(0.5, 0.9)),
      ], color: 1, width: 1.0),
      ArtPath(_ellipse(0.5, 0.8, 0.05, 0.08), color: 0, width: 0.8),
    ];

List<ArtPath> _cat() => [
      ArtPath([
        ..._circle(0.5, 0.55, 0.3, start: -math.pi * 0.3, sweep: math.pi * 1.6 - 0.0 + math.pi * 0.0, n: 50),
      ], color: 0, width: 1.2),
      ArtPath(_poly([[0.27, 0.36], [0.24, 0.12], [0.43, 0.27]]), color: 0, width: 1.2),
      ArtPath(_poly([[0.73, 0.36], [0.76, 0.12], [0.57, 0.27]]), color: 0, width: 1.2),
      ArtPath(_ellipse(0.39, 0.5, 0.035, 0.05), color: 1),
      ArtPath(_ellipse(0.61, 0.5, 0.035, 0.05), color: 1),
      ArtPath(_poly([[0.47, 0.6], [0.53, 0.6], [0.5, 0.64], [0.47, 0.6]]), color: 2, width: 0.8),
      ArtPath([..._circle(0.465, 0.66, 0.035, start: 0, sweep: math.pi, n: 10)], color: 2, width: 0.7),
      ArtPath([..._circle(0.535, 0.66, 0.035, start: 0, sweep: math.pi, n: 10)], color: 2, width: 0.7),
      for (final dy in [-0.02, 0.03])
        ArtPath(_poly([[0.36, 0.63 + dy], [0.1, 0.6 + dy * 2]]), color: 3, width: 0.5),
      for (final dy in [-0.02, 0.03])
        ArtPath(_poly([[0.64, 0.63 + dy], [0.9, 0.6 + dy * 2]]), color: 3, width: 0.5),
    ];

List<ArtPath> _sailboat() => [
      ArtPath(_poly([[0.12, 0.7], [0.88, 0.7], [0.74, 0.84], [0.26, 0.84], [0.12, 0.7]]), color: 0, width: 1.2),
      ArtPath(_poly([[0.5, 0.7], [0.5, 0.1]]), color: 1, width: 1.0),
      ArtPath(_poly([[0.5, 0.14], [0.8, 0.62], [0.5, 0.62]]), color: 2, width: 1.1),
      ArtPath(_poly([[0.48, 0.2], [0.24, 0.62], [0.48, 0.62]]), color: 2, width: 1.0),
      ArtPath(_wave(0.02, 0.98, 0.9, 0.02, 4), color: 3, width: 0.7),
    ];

List<ArtPath> _smile() => [
      ArtPath(_circle(0.5, 0.5, 0.4), color: 0, width: 1.3),
      ArtPath(_ellipse(0.37, 0.4, 0.035, 0.06), color: 1),
      ArtPath(_ellipse(0.63, 0.4, 0.035, 0.06), color: 1),
      ArtPath(_circle(0.5, 0.52, 0.22, start: math.pi * 0.15, sweep: math.pi * 0.7, n: 30), color: 2, width: 1.2),
    ];

List<ArtPath> _castle() => [
      ArtPath(_poly([
        [0.12, 0.92], [0.12, 0.42], [0.12, 0.36], [0.18, 0.36], [0.18, 0.42], [0.24, 0.42], [0.24, 0.36], [0.3, 0.36],
        [0.3, 0.55], [0.7, 0.55], [0.7, 0.36], [0.76, 0.36], [0.76, 0.42], [0.82, 0.42], [0.82, 0.36], [0.88, 0.36], [0.88, 0.92], [0.12, 0.92],
      ]), color: 0, width: 1.2),
      ArtPath(_poly([[0.38, 0.55], [0.38, 0.3], [0.62, 0.3], [0.62, 0.55]]), color: 0, width: 1.1),
      ArtPath(_poly([[0.35, 0.3], [0.5, 0.1], [0.65, 0.3]]), color: 1, width: 1.1),
      ArtPath(_poly([[0.5, 0.1], [0.5, 0.03], [0.58, 0.05], [0.5, 0.07]]), color: 2, width: 0.7),
      ArtPath([..._circle(0.5, 0.82, 0.08, start: math.pi, sweep: math.pi, n: 16), const Offset(0.58, 0.92), const Offset(0.42, 0.92), const Offset(0.42, 0.82)], color: 3, width: 0.9),
    ];

List<ArtPath> _aurora() => [
      for (var i = 0; i < 4; i++)
        ArtPath([
          for (var k = 0; k <= 60; k++)
            Offset(k / 60, 0.25 + i * 0.12 + 0.07 * math.sin(k / 60 * _tau * 1.3 + i * 0.9) + 0.03 * math.sin(k / 60 * _tau * 3.7 + i)),
        ], color: i % 4, width: 1.6 - i * 0.2),
    ];

List<ArtPath> _dragonfly() => [
      ArtPath(_poly([[0.5, 0.25], [0.5, 0.9]]), color: 2, width: 1.2),
      ArtPath(_circle(0.5, 0.22, 0.04), color: 2),
      ArtPath(_ellipse(0.31, 0.34, 0.19, 0.06, rot: -0.2), color: 0, width: 0.9),
      ArtPath(_ellipse(0.69, 0.34, 0.19, 0.06, rot: 0.2), color: 0, width: 0.9),
      ArtPath(_ellipse(0.33, 0.46, 0.16, 0.05, rot: 0.25), color: 1, width: 0.9),
      ArtPath(_ellipse(0.67, 0.46, 0.16, 0.05, rot: -0.25), color: 1, width: 0.9),
    ];

/// The built-in imagination library.
final List<ArtTemplate> artLibrary = [
  ArtTemplate(id: 'sun', title: 'Radiant Sun', layer: ArtLayer.sky, palette: LightPalette.sunset, brush: BrushKind.glow, build: _sun, shapes: {'circle'},
      keywords: ['sun', 'sunny', 'sunrise', 'sunset', 'day', 'summer', 'warm', 'bright', 'morning', 'shine', 'golden', 'hope']),
  ArtTemplate(id: 'moon', title: 'Crescent Moon', layer: ArtLayer.sky, palette: LightPalette.frost, brush: BrushKind.neon, build: _moon, shapes: {'circle', 'arc'},
      keywords: ['moon', 'night', 'crescent', 'lunar', 'dream', 'sleep', 'dark', 'calm', 'midnight', 'lullaby', 'peace']),
  ArtTemplate(id: 'star', title: 'Wishing Star', layer: ArtLayer.sky, palette: LightPalette.gold, brush: BrushKind.sparkle, build: _star, shapes: {'star', 'zigzag'},
      keywords: ['star', 'wish', 'shine', 'sparkle', 'twinkle', 'magic', 'famous', 'success', 'dream', 'night', 'bright']),
  ArtTemplate(id: 'heart', title: 'Glowing Heart', layer: ArtLayer.center, palette: LightPalette.love, brush: BrushKind.neon, build: _heartArt, shapes: {'heart', 'circle'},
      keywords: ['heart', 'love', 'romance', 'valentine', 'care', 'kind', 'friend', 'crush', 'kiss', 'wedding', 'mom', 'mother', 'family', 'sweet']),
  ArtTemplate(id: 'flower', title: 'Blooming Flower', layer: ArtLayer.ground, palette: LightPalette.love, brush: BrushKind.glow, build: _flower, shapes: {'circle', 'spiral'},
      keywords: ['flower', 'bloom', 'garden', 'spring', 'rose', 'petal', 'blossom', 'nature', 'lotus', 'tulip', 'beautiful', 'grow']),
  ArtTemplate(id: 'tree', title: 'Tree of Light', layer: ArtLayer.ground, palette: LightPalette.forest, brush: BrushKind.glow, build: _tree, shapes: {'circle', 'line'},
      keywords: ['tree', 'forest', 'nature', 'wood', 'park', 'jungle', 'green', 'leaf', 'life', 'earth', 'grow', 'roots']),
  ArtTemplate(id: 'mountains', title: 'Mountain Range', layer: ArtLayer.ground, palette: LightPalette.frost, brush: BrushKind.neon, build: _mountains, shapes: {'triangle', 'zigzag'},
      keywords: ['mountain', 'hill', 'hike', 'adventure', 'peak', 'everest', 'himalaya', 'travel', 'landscape', 'climb', 'snow', 'trek']),
  ArtTemplate(id: 'waves', title: 'Ocean Waves', layer: ArtLayer.ground, palette: LightPalette.ocean, brush: BrushKind.glow, build: _waves, shapes: {'wave', 'line'},
      keywords: ['ocean', 'sea', 'wave', 'beach', 'water', 'surf', 'river', 'calm', 'tide', 'blue', 'flow', 'vacation']),
  ArtTemplate(id: 'rainbow', title: 'Light Rainbow', layer: ArtLayer.sky, palette: LightPalette.aurora, brush: BrushKind.rainbow, build: _rainbow, shapes: {'arc', 'line'},
      keywords: ['rainbow', 'color', 'colour', 'colorful', 'pride', 'hope', 'rain', 'happy', 'joy', 'bright', 'promise']),
  ArtTemplate(id: 'lightning', title: 'Lightning Bolt', layer: ArtLayer.sky, palette: LightPalette.electric, brush: BrushKind.neon, build: _lightning, shapes: {'zigzag', 'line'},
      keywords: ['lightning', 'storm', 'thunder', 'power', 'energy', 'electric', 'fast', 'flash', 'speed', 'bolt', 'strong', 'zeus']),
  ArtTemplate(id: 'cloud', title: 'Dreamy Cloud', layer: ArtLayer.sky, palette: LightPalette.frost, brush: BrushKind.glow, build: _cloud, shapes: {'wave', 'circle'},
      keywords: ['cloud', 'sky', 'rain', 'weather', 'fluffy', 'dream', 'soft', 'heaven', 'float', 'monsoon']),
  ArtTemplate(id: 'butterfly', title: 'Light Butterfly', layer: ArtLayer.center, palette: LightPalette.aurora, brush: BrushKind.neon, build: _butterfly, shapes: {'infinity', 'circle'},
      keywords: ['butterfly', 'wing', 'fly', 'freedom', 'change', 'transform', 'beauty', 'garden', 'spring', 'grace']),
  ArtTemplate(id: 'fish', title: 'Swimming Fish', layer: ArtLayer.center, palette: LightPalette.ocean, brush: BrushKind.neon, build: _fish, shapes: {'circle', 'wave'},
      keywords: ['fish', 'ocean', 'sea', 'swim', 'aquarium', 'underwater', 'river', 'water', 'koi', 'nemo']),
  ArtTemplate(id: 'birds', title: 'Flying Birds', layer: ArtLayer.sky, palette: LightPalette.sunset, brush: BrushKind.ink, build: _birds, shapes: {'wave', 'arc'},
      keywords: ['bird', 'fly', 'flight', 'sky', 'freedom', 'wing', 'seagull', 'migrate', 'flock', 'free']),
  ArtTemplate(id: 'rocket', title: 'Rocket Launch', layer: ArtLayer.center, palette: LightPalette.fire, brush: BrushKind.neon, build: _rocket, shapes: {'triangle', 'line'},
      keywords: ['rocket', 'space', 'launch', 'mission', 'future', 'startup', 'nasa', 'isro', 'mars', 'astronaut', 'blast', 'ambition']),
  ArtTemplate(id: 'house', title: 'Cozy Home', layer: ArtLayer.ground, palette: LightPalette.gold, brush: BrushKind.neon, build: _house, shapes: {'square', 'triangle'},
      keywords: ['home', 'house', 'family', 'cozy', 'building', 'village', 'cottage', 'warm', 'shelter']),
  ArtTemplate(id: 'galaxy', title: 'Spiral Galaxy', layer: ArtLayer.sky, palette: LightPalette.cosmic, brush: BrushKind.sparkle, build: _galaxy, shapes: {'spiral'},
      keywords: ['galaxy', 'space', 'universe', 'cosmos', 'cosmic', 'spiral', 'nebula', 'stars', 'infinite', 'milky', 'astronomy', 'mystery']),
  ArtTemplate(id: 'planet', title: 'Ringed Planet', layer: ArtLayer.sky, palette: LightPalette.cosmic, brush: BrushKind.neon, build: _planet, shapes: {'circle'},
      keywords: ['planet', 'saturn', 'space', 'orbit', 'world', 'earth', 'astronomy', 'alien', 'jupiter', 'cosmos']),
  ArtTemplate(id: 'crown', title: 'Royal Crown', layer: ArtLayer.center, palette: LightPalette.gold, brush: BrushKind.sparkle, build: _crown, shapes: {'zigzag', 'square'},
      keywords: ['crown', 'king', 'queen', 'royal', 'princess', 'prince', 'win', 'champion', 'leader', 'boss', 'gold', 'victory']),
  ArtTemplate(id: 'infinity', title: 'Infinity Loop', layer: ArtLayer.center, palette: LightPalette.cosmic, brush: BrushKind.comet, build: _infinity, shapes: {'infinity'},
      keywords: ['infinity', 'forever', 'endless', 'eternal', 'loop', 'math', 'always', 'unlimited', 'bond']),
  ArtTemplate(id: 'music', title: 'Music Notes', layer: ArtLayer.center, palette: LightPalette.aurora, brush: BrushKind.neon, build: _music, shapes: {'line', 'circle'},
      keywords: ['music', 'song', 'sing', 'melody', 'dance', 'party', 'concert', 'beat', 'rhythm', 'guitar', 'tune', 'dj']),
  ArtTemplate(id: 'diamond', title: 'Brilliant Diamond', layer: ArtLayer.center, palette: LightPalette.frost, brush: BrushKind.sparkle, build: _diamond, shapes: {'triangle', 'square'},
      keywords: ['diamond', 'gem', 'jewel', 'rich', 'precious', 'luxury', 'crystal', 'ring', 'treasure', 'shine']),
  ArtTemplate(id: 'balloons', title: 'Party Balloons', layer: ArtLayer.center, palette: LightPalette.sunset, brush: BrushKind.glow, build: _balloons, shapes: {'circle'},
      keywords: ['balloon', 'birthday', 'party', 'celebrate', 'celebration', 'fun', 'kid', 'festival', 'surprise', 'anniversary']),
  ArtTemplate(id: 'snowflake', title: 'Snowflake', layer: ArtLayer.sky, palette: LightPalette.frost, brush: BrushKind.sparkle, build: _snowflake, shapes: {'star', 'zigzag'},
      keywords: ['snow', 'snowflake', 'winter', 'cold', 'ice', 'christmas', 'frozen', 'frost', 'december', 'chill']),
  ArtTemplate(id: 'flame', title: 'Living Flame', layer: ArtLayer.center, palette: LightPalette.fire, brush: BrushKind.glow, build: _flame, shapes: {'triangle', 'wave'},
      keywords: ['fire', 'flame', 'hot', 'passion', 'burn', 'energy', 'camp', 'diwali', 'diya', 'candle', 'phoenix', 'spirit']),
  ArtTemplate(id: 'cat', title: 'Neon Cat', layer: ArtLayer.center, palette: LightPalette.aurora, brush: BrushKind.neon, build: _cat, shapes: {'circle', 'triangle'},
      keywords: ['cat', 'kitten', 'kitty', 'pet', 'meow', 'cute', 'animal', 'whisker']),
  ArtTemplate(id: 'sailboat', title: 'Sailboat', layer: ArtLayer.ground, palette: LightPalette.ocean, brush: BrushKind.neon, build: _sailboat, shapes: {'triangle'},
      keywords: ['boat', 'sail', 'ship', 'sea', 'voyage', 'travel', 'ocean', 'journey', 'explore', 'harbor']),
  ArtTemplate(id: 'smile', title: 'Big Smile', layer: ArtLayer.center, palette: LightPalette.gold, brush: BrushKind.neon, build: _smile, shapes: {'circle', 'arc'},
      keywords: ['smile', 'happy', 'joy', 'emoji', 'fun', 'laugh', 'face', 'cheer', 'positive', 'good']),
  ArtTemplate(id: 'castle', title: 'Fairy Castle', layer: ArtLayer.ground, palette: LightPalette.cosmic, brush: BrushKind.sparkle, build: _castle, shapes: {'square', 'zigzag'},
      keywords: ['castle', 'fairy', 'fantasy', 'kingdom', 'princess', 'magic', 'tale', 'palace', 'disney', 'dream']),
  ArtTemplate(id: 'aurora', title: 'Aurora Lights', layer: ArtLayer.sky, palette: LightPalette.aurora, brush: BrushKind.glow, build: _aurora, shapes: {'wave'},
      keywords: ['aurora', 'northern', 'borealis', 'iceland', 'mystic', 'sky', 'night', 'magic']),
  ArtTemplate(id: 'dragonfly', title: 'Dragonfly', layer: ArtLayer.center, palette: LightPalette.forest, brush: BrushKind.neon, build: _dragonfly, shapes: {'line'},
      keywords: ['dragonfly', 'insect', 'bug', 'pond', 'summer', 'wing', 'garden', 'dragon']),
];

ArtTemplate? templateById(String id) {
  for (final t in artLibrary) {
    if (t.id == id) return t;
  }
  return null;
}
