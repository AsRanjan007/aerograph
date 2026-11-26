import 'package:flutter/painting.dart';

enum BrushKind {
  neon('Neon', 'Hot white core with a colored halo'),
  glow('Glow', 'Soft wide light'),
  ink('Ink', 'Solid crisp line'),
  sparkle('Sparkle', 'Glittering star dust'),
  rainbow('Rainbow', 'Hue flows along the stroke'),
  comet('Comet', 'Tapered trail of light');

  const BrushKind(this.label, this.description);
  final String label;
  final String description;

  static BrushKind byName(String? name, [BrushKind fallback = BrushKind.neon]) =>
      BrushKind.values.firstWhere((b) => b.name == name, orElse: () => fallback);
}

/// How finished strokes behave over time.
enum LightMode {
  steady('Steady'),
  pulse('Pulse'),
  shimmer('Shimmer'),
  aurora('Aurora');

  const LightMode(this.label);
  final String label;

  static LightMode byName(String? name) =>
      LightMode.values.firstWhere((m) => m.name == name, orElse: () => LightMode.steady);
}

class BrushStyle {
  const BrushStyle({
    required this.kind,
    required this.color,
    required this.width,
    required this.glow,
  });

  final BrushKind kind;
  final Color color;

  /// Core width in logical pixels.
  final double width;

  /// Light intensity 0..1 — scales halo size and opacity.
  final double glow;

  BrushStyle copyWith({BrushKind? kind, Color? color, double? width, double? glow}) => BrushStyle(
        kind: kind ?? this.kind,
        color: color ?? this.color,
        width: width ?? this.width,
        glow: glow ?? this.glow,
      );
}

/// Curated light palettes. Each is a set of colors that glow well together on
/// a dark camera feed.
class LightPalette {
  const LightPalette(this.name, this.colors);
  final String name;
  final List<Color> colors;

  static const aurora = LightPalette('Aurora', [
    Color(0xFF7CF7C8), Color(0xFF38BDF8), Color(0xFF8B5CF6), Color(0xFFE879F9),
  ]);
  static const sunset = LightPalette('Sunset', [
    Color(0xFFFFD166), Color(0xFFFF9F43), Color(0xFFFF5E7E), Color(0xFFC084FC),
  ]);
  static const ocean = LightPalette('Ocean', [
    Color(0xFF22D3EE), Color(0xFF38BDF8), Color(0xFF3B82F6), Color(0xFFA5F3FC),
  ]);
  static const forest = LightPalette('Forest', [
    Color(0xFF4ADE80), Color(0xFFA3E635), Color(0xFF2DD4BF), Color(0xFFFDE68A),
  ]);
  static const love = LightPalette('Love', [
    Color(0xFFFF4D8D), Color(0xFFFF8FB1), Color(0xFFF43F5E), Color(0xFFFBCFE8),
  ]);
  static const cosmic = LightPalette('Cosmic', [
    Color(0xFFA855F7), Color(0xFF6366F1), Color(0xFF38BDF8), Color(0xFFF0ABFC),
  ]);
  static const fire = LightPalette('Fire', [
    Color(0xFFFFE066), Color(0xFFFF9F1C), Color(0xFFFF4D00), Color(0xFFFF006E),
  ]);
  static const frost = LightPalette('Frost', [
    Color(0xFFE0F2FE), Color(0xFFBAE6FD), Color(0xFF7DD3FC), Color(0xFFC7D2FE),
  ]);
  static const gold = LightPalette('Gold', [
    Color(0xFFFFE08A), Color(0xFFFFC94D), Color(0xFFF5B700), Color(0xFFFFF4CC),
  ]);
  static const electric = LightPalette('Electric', [
    Color(0xFF60A5FA), Color(0xFFFDE047), Color(0xFFE0F2FE), Color(0xFF818CF8),
  ]);

  static const all = [aurora, sunset, ocean, forest, love, cosmic, fire, frost, gold, electric];

  /// Quick swatches shown in the studio color row.
  static const swatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFA855F7),
    Color(0xFF6366F1),
    Color(0xFF38BDF8),
    Color(0xFF22D3EE),
    Color(0xFF4ADE80),
    Color(0xFFFDE047),
    Color(0xFFFF9F43),
    Color(0xFFFF4D8D),
    Color(0xFFF43F5E),
  ];
}
