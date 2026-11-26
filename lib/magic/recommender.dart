import 'dart:math' as math;
import 'dart:ui';

import '../paint/brush.dart';
import 'art_library.dart';
import 'shape_recognizer.dart';

/// A ready-to-build piece of art: unit-space paths plus how to light them.
class MagicArt {
  const MagicArt({
    required this.title,
    required this.paths,
    required this.palette,
    required this.brush,
    this.aspect = 1.0,
  });

  final String title;
  final List<ArtPath> paths;
  final LightPalette palette;
  final BrushKind brush;

  /// Width / height of the art's natural frame.
  final double aspect;
}

enum RecommendationSource { imagination, sketch, mood, ai }

class Recommendation {
  const Recommendation({required this.art, required this.reason, required this.score, required this.source});

  final MagicArt art;

  /// Short human explanation: why this was suggested.
  final String reason;
  final double score;
  final RecommendationSource source;

  String get title => art.title;
}

/// Turns what the user imagines (free text) or sketches (a stroke) into
/// ranked art suggestions from the built-in library, including composed
/// scenes when several ideas are mentioned ("moon over the mountains").
class Recommender {
  Recommender({List<ArtTemplate>? library}) : library = library ?? artLibrary;

  final List<ArtTemplate> library;

  static const _stop = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'of',
    'in',
    'on',
    'at',
    'to',
    'with',
    'my',
    'me',
    'i',
    'is',
    'it',
    'for',
    'over',
    'under',
    'by',
    'from',
    'some',
    'very',
    'want',
    'draw',
    'paint',
    'make',
    'show',
    'like',
    'that',
    'this',
    'into',
    'above',
    'below',
    'near',
    'big',
    'small',
    'little',
    'beautiful',
    'please',
    'glowing',
    'glow',
    'neon',
    'light',
    'lights',
    'shiny',
    'bright',
    'can',
    'you',
    'imagine',
  };

  /// Mood words → palette. Applied when the user describes a feeling or time.
  static const Map<String, LightPalette> _moods = {
    'night': LightPalette.cosmic,
    'dark': LightPalette.cosmic,
    'space': LightPalette.cosmic,
    'mystic': LightPalette.cosmic,
    'cosmic': LightPalette.cosmic,
    'galaxy': LightPalette.cosmic,
    'midnight': LightPalette.cosmic,
    'dream': LightPalette.cosmic,
    'sunset': LightPalette.sunset,
    'warm': LightPalette.sunset,
    'evening': LightPalette.sunset,
    'summer': LightPalette.sunset,
    'sunrise': LightPalette.sunset,
    'love': LightPalette.love,
    'romantic': LightPalette.love,
    'romance': LightPalette.love,
    'pink': LightPalette.love,
    'valentine': LightPalette.love,
    'ocean': LightPalette.ocean,
    'sea': LightPalette.ocean,
    'calm': LightPalette.ocean,
    'blue': LightPalette.ocean,
    'water': LightPalette.ocean,
    'peace': LightPalette.ocean,
    'forest': LightPalette.forest,
    'nature': LightPalette.forest,
    'green': LightPalette.forest,
    'spring': LightPalette.forest,
    'fresh': LightPalette.forest,
    'fire': LightPalette.fire,
    'angry': LightPalette.fire,
    'passion': LightPalette.fire,
    'hot': LightPalette.fire,
    'red': LightPalette.fire,
    'diwali': LightPalette.fire,
    'winter': LightPalette.frost,
    'cold': LightPalette.frost,
    'snow': LightPalette.frost,
    'ice': LightPalette.frost,
    'white': LightPalette.frost,
    'frozen': LightPalette.frost,
    'gold': LightPalette.gold,
    'golden': LightPalette.gold,
    'royal': LightPalette.gold,
    'rich': LightPalette.gold,
    'luxury': LightPalette.gold,
    'yellow': LightPalette.gold,
    'storm': LightPalette.electric,
    'electric': LightPalette.electric,
    'energy': LightPalette.electric,
    'power': LightPalette.electric,
    'party': LightPalette.aurora,
    'happy': LightPalette.aurora,
    'magic': LightPalette.aurora,
    'colorful': LightPalette.aurora,
    'aurora': LightPalette.aurora,
    'purple': LightPalette.cosmic,
    'violet': LightPalette.cosmic,
  };

  static List<String> tokenize(String text) {
    final words = text.toLowerCase().split(RegExp(r"[^a-z]+")).where((w) => w.isNotEmpty);
    return [
      for (final w in words)
        if (!_stop.contains(w)) w,
    ];
  }

  /// Light stemming so "mountains", "flying", "stars" match keywords.
  static String stem(String w) {
    if (w.length > 5 && w.endsWith('ing')) return w.substring(0, w.length - 3);
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.endsWith('es') && !w.endsWith('ses')) return w.substring(0, w.length - 2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    if (w.length > 5 && w.endsWith('ed')) return w.substring(0, w.length - 2);
    return w;
  }

  static int _editDistance(String a, String b) {
    if ((a.length - b.length).abs() > 2) return 3;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var diag = prev[0];
      prev[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final tmp = prev[j];
        prev[j] = math.min(math.min(prev[j] + 1, prev[j - 1] + 1), diag + (a[i - 1] == b[j - 1] ? 0 : 1));
        diag = tmp;
      }
    }
    return prev[b.length];
  }

  /// Score of one word against one keyword: 3 exact, 2 stem/prefix, 1 typo.
  static double _wordScore(String word, String keyword) {
    if (word == keyword) return 3;
    final ws = stem(word), ks = stem(keyword);
    if (ws == ks) return 2.6;
    if (ws.length >= 4 && ks.length >= 4 && (ks.startsWith(ws) || ws.startsWith(ks))) return 2;
    if (ws.length >= 5 && _editDistance(ws, ks) <= 1) return 1.2;
    return 0;
  }

  double scoreTemplate(ArtTemplate t, List<String> words) {
    var score = 0.0;
    for (final w in words) {
      var best = 0.0;
      for (var i = 0; i < t.keywords.length; i++) {
        // Earlier keywords are more central to the template.
        final s = _wordScore(w, t.keywords[i]) * (i == 0 ? 1.4 : 1.0);
        if (s > best) best = s;
      }
      score += best;
    }
    return score;
  }

  LightPalette? moodPalette(List<String> words) {
    for (final w in words) {
      final p = _moods[w] ?? _moods[stem(w)];
      if (p != null) return p;
    }
    return null;
  }

  MagicArt artFor(ArtTemplate t, {LightPalette? palette}) =>
      MagicArt(title: t.title, paths: t.build(), palette: palette ?? t.palette, brush: t.brush);

  /// Ranked suggestions for a free-text idea. Always returns something: when
  /// nothing matches literally, it falls back to the detected mood, then to
  /// crowd favourites.
  List<Recommendation> fromImagination(String text, {int limit = 6}) {
    final words = tokenize(text);
    final mood = moodPalette(words);
    final scored = <(ArtTemplate, double)>[for (final t in library) (t, scoreTemplate(t, words))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final matched = scored.where((e) => e.$2 >= 1.2).toList();

    final out = <Recommendation>[];

    // A composed scene when the idea mentions two or more things.
    if (matched.length >= 2) {
      final picks = _distinctLayers(matched.map((e) => e.$1).take(4).toList());
      if (picks.length >= 2) {
        out.add(
          Recommendation(
            art: composeScene(picks, palette: mood),
            reason: 'Your whole idea as one scene',
            score: matched.take(picks.length).fold<double>(0, (s, e) => s + e.$2) + 1,
            source: RecommendationSource.imagination,
          ),
        );
      }
    }

    for (final (t, s) in matched) {
      if (out.length >= limit) break;
      out.add(
        Recommendation(
          art: artFor(t, palette: mood),
          reason: 'Matches "${_matchedWord(t, words) ?? t.keywords.first}"',
          score: s,
          source: RecommendationSource.imagination,
        ),
      );
    }

    if (out.length < limit && mood != null) {
      for (final t in library.where((t) => t.palette == mood)) {
        if (out.length >= limit) break;
        if (out.any((r) => r.art.title == t.title)) continue;
        out.add(
          Recommendation(
            art: artFor(t, palette: mood),
            reason: 'Fits the ${mood.name.toLowerCase()} mood',
            score: 0.5,
            source: RecommendationSource.mood,
          ),
        );
      }
    }

    if (out.length < math.min(3, limit)) {
      for (final id in const ['galaxy', 'heart', 'star', 'butterfly', 'aurora']) {
        if (out.length >= math.min(3, limit)) break;
        final t = templateById(id)!;
        if (out.any((r) => r.art.title == t.title)) continue;
        out.add(
          Recommendation(
            art: artFor(t, palette: mood),
            reason: 'A favourite to start with',
            score: 0.1,
            source: RecommendationSource.mood,
          ),
        );
      }
    }
    return out;
  }

  /// Suggestions grown from a sketched stroke.
  List<Recommendation> fromSketch(ShapeGuess guess, {int limit = 4}) {
    if (guess.shape == 'scribble' || guess.confidence < 0.3) return const [];
    final matches = library.where((t) => t.shapes.contains(guess.shape)).toList();
    return [
      for (final t in matches.take(limit))
        Recommendation(
          art: artFor(t),
          reason: 'Your ${guess.shape} could become this',
          score: guess.confidence,
          source: RecommendationSource.sketch,
        ),
    ];
  }

  String? _matchedWord(ArtTemplate t, List<String> words) {
    String? best;
    var bestScore = 0.0;
    for (final w in words) {
      for (final k in t.keywords) {
        final s = _wordScore(w, k);
        if (s > bestScore) {
          bestScore = s;
          best = w;
        }
      }
    }
    return best;
  }

  /// Keeps at most one template per layer so the scene doesn't overlap
  /// (one in the sky, one in the middle, one on the ground).
  List<ArtTemplate> _distinctLayers(List<ArtTemplate> ts) {
    final seen = <ArtLayer>{};
    final out = <ArtTemplate>[];
    for (final t in ts) {
      if (seen.add(t.layer)) out.add(t);
    }
    // Two centers? allow a second item if we only found one layer.
    if (out.length == 1 && ts.length > 1) out.add(ts[1]);
    return out;
  }

  static String _cap(String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';

  static const _stretchable = {'mountains', 'waves', 'aurora', 'rainbow'};

  /// Lays templates out in a portrait frame by layer: sky at the top,
  /// center in the middle, ground at the bottom.
  MagicArt composeScene(List<ArtTemplate> parts, {LightPalette? palette}) {
    const aspect = 0.75; // portrait frame
    final slots = <ArtLayer, Rect>{
      ArtLayer.sky: const Rect.fromLTWH(0.42, 0.0, 0.55, 0.36),
      ArtLayer.center: const Rect.fromLTWH(0.25, 0.3, 0.5, 0.36),
      ArtLayer.ground: const Rect.fromLTWH(0.0, 0.62, 1.0, 0.38),
    };
    final used = <ArtLayer>{};
    final paths = <ArtPath>[];
    var colorShift = 0;
    for (final t in parts) {
      var rect = slots[t.layer]!;
      if (used.contains(t.layer)) {
        // Second item in the same layer: put it on the left side.
        rect = Rect.fromLTWH(0.05, rect.top, rect.width, rect.height);
      }
      used.add(t.layer);
      // Keep each part visually square inside its slot: in unit space a
      // square has height = width * aspect (frame is wider than tall by 1/aspect).
      final w = math.min(rect.width, rect.height / aspect);
      final unitRect = _stretchable.contains(t.id)
          ? rect
          : Rect.fromCenter(center: rect.center, width: w, height: w * aspect);
      for (final p in t.build()) {
        paths.add(
          ArtPath(
            [
              for (final o in p.points)
                Offset(unitRect.left + o.dx * unitRect.width, unitRect.top + o.dy * unitRect.height),
            ],
            color: (p.color + colorShift) % 4,
            width: p.width,
          ),
        );
      }
      colorShift++;
    }
    final names = parts.map((t) => _cap(t.keywords.first)).toList();
    final title = names.length == 2
        ? '${names[0]} & ${names[1]}'
        : '${names.take(names.length - 1).join(', ')} & ${names.last}';
    return MagicArt(
      title: title,
      paths: paths,
      palette: palette ?? parts.first.palette,
      brush: parts.first.brush == BrushKind.rainbow ? BrushKind.neon : parts.first.brush,
      aspect: aspect,
    );
  }
}
