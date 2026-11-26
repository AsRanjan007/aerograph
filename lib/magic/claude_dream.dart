import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;

import '../paint/brush.dart';
import 'art_library.dart';
import 'recommender.dart';

class DreamException implements Exception {
  DreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Optional: asks Claude to sketch any idea as glowing line art. Uses the
/// user's own Anthropic API key (stored in the device keychain/keystore).
/// Everything else in Aerograph works offline without it.
class ClaudeDreamer {
  ClaudeDreamer({required this.apiKey, this.model = defaultModel, http.Client? client})
    : _client = client ?? http.Client();

  static const defaultModel = 'claude-opus-5-5';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _system = '''
You are the imagination engine of Aerograph, an app where people paint with light in the air.
Turn the user's idea into simple, recognizable line art made of glowing strokes.

Coordinates: x and y are in 0..1 inside a portrait frame (x to the right, y downward).
The frame's width/height ratio is 0.75, so a visually round circle spans 0.75x as much in y as in x.
Rules:
- 4 to 16 strokes. Each stroke is one continuous polyline of 2 to 60 points.
- Prefer smooth curves sampled densely (8+ points) over jagged ones.
- Draw outlines only, like neon signs. No fills, no text, no letters.
- Keep everything inside 0.05..0.95 on both axes.
- palette: 3 or 4 hex colors (#RRGGBB) that glow well on a dark camera feed and fit the mood.
- Each stroke picks a palette index and a width multiplier between 0.5 and 1.6 (1 is normal).
- brush: one of neon, glow, ink, sparkle, rainbow, comet.
- title: 2 to 4 words.''';

  static Map<String, Object?> get _schema => {
    'type': 'object',
    'additionalProperties': false,
    'required': ['title', 'brush', 'palette', 'strokes'],
    'properties': {
      'title': {'type': 'string'},
      'brush': {
        'type': 'string',
        'enum': ['neon', 'glow', 'ink', 'sparkle', 'rainbow', 'comet'],
      },
      'palette': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'strokes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['color', 'width', 'points'],
          'properties': {
            'color': {'type': 'integer'},
            'width': {'type': 'number'},
            'points': {
              'type': 'array',
              'items': {
                'type': 'array',
                'items': {'type': 'number'},
              },
            },
          },
        },
      },
    },
  };

  Future<MagicArt> dream(String idea) async {
    final body = jsonEncode({
      'model': model,
      'max_tokens': 16000,
      'system': _system,
      // Low effort keeps the wait short; this is a playful sketch, not a proof.
      'output_config': {
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': _schema},
      },
      // If a safety classifier declines, let the server retry on its
      // recommended fallback model instead of failing outright.
      'fallbacks': 'default',
      'messages': [
        {'role': 'user', 'content': 'Idea: $idea'},
      ],
    });

    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2026-10-21',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));
    } on Exception catch (e) {
      throw DreamException('Could not reach Claude: $e');
    }

    if (res.statusCode == 401) throw DreamException('The Claude API key was rejected.');
    if (res.statusCode == 429) throw DreamException('Claude is busy (rate limited). Try again in a moment.');
    if (res.statusCode >= 500) throw DreamException('Claude is temporarily unavailable (${res.statusCode}).');
    if (res.statusCode != 200) {
      throw DreamException('Claude request failed (${res.statusCode}): ${_errorMessage(res.body)}');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    final stop = decoded['stop_reason'];
    if (stop == 'refusal') throw DreamException('Claude declined to draw that idea. Try another one.');
    if (stop == 'max_tokens') throw DreamException('The drawing was too detailed. Try a simpler idea.');

    final content = (decoded['content'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    if (content.isEmpty) throw DreamException('Claude returned no drawing.');
    return parseArt(content);
  }

  static String _errorMessage(String body) {
    try {
      final m = jsonDecode(body) as Map<String, Object?>;
      return ((m['error'] as Map<String, Object?>?)?['message'] as String?) ?? body;
    } catch (_) {
      return body;
    }
  }

  /// Validates and converts Claude's JSON into renderable art. Exposed for tests.
  static MagicArt parseArt(String json) {
    final Map<String, Object?> m;
    try {
      m = jsonDecode(json) as Map<String, Object?>;
    } on FormatException {
      throw DreamException('Claude returned an unreadable drawing.');
    }
    final colors = <Color>[for (final h in (m['palette'] as List<Object?>? ?? const []).whereType<String>()) ?_hex(h)];
    if (colors.isEmpty) colors.addAll(LightPalette.cosmic.colors);

    final paths = <ArtPath>[];
    for (final s in (m['strokes'] as List<Object?>? ?? const []).whereType<Map<String, Object?>>()) {
      final pts = <Offset>[];
      for (final p in (s['points'] as List<Object?>? ?? const []).whereType<List<Object?>>()) {
        if (p.length < 2 || p[0] is! num || p[1] is! num) continue;
        final x = (p[0]! as num).toDouble().clamp(0.0, 1.0);
        final y = (p[1]! as num).toDouble().clamp(0.0, 1.0);
        pts.add(Offset(x, y));
      }
      if (pts.length < 2) continue;
      final color = ((s['color'] as num?) ?? 0).toInt();
      final width = ((s['width'] as num?) ?? 1).toDouble().clamp(0.4, 2.0);
      paths.add(ArtPath(pts, color: color.abs() % colors.length, width: width));
    }
    if (paths.isEmpty) throw DreamException('Claude returned an empty drawing.');

    return MagicArt(
      title: (m['title'] as String?)?.trim().isNotEmpty == true ? (m['title']! as String).trim() : 'Dream',
      paths: paths,
      palette: LightPalette('Dream', colors),
      brush: BrushKind.byName(m['brush'] as String?),
      aspect: 0.75,
    );
  }

  static Color? _hex(String s) {
    final h = s.replaceFirst('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}
