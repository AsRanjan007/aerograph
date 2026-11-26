import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../magic/claude_dream.dart';
import '../paint/brush.dart';

enum DrawGesture {
  point('Point', 'Raise only your index finger to paint. Two fingers lifts the brush.'),
  pinch('Pinch', 'Touch thumb and index together to paint. Release to lift the brush.');

  const DrawGesture(this.label, this.help);
  final String label;
  final String help;
}

enum MirrorMode { auto, on, off }

/// User preferences, persisted locally. The Claude API key lives in the
/// platform keychain/keystore, never in plain preferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._secure);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    final s = AppSettings._(prefs, secure);
    try {
      s._read();
    } catch (_) {
      // Corrupt or incompatible stored values: keep defaults.
    }
    try {
      s._apiKey = await secure.read(key: _kApiKey);
    } catch (_) {
      s._apiKey = null;
    }
    return s;
  }

  /// In-memory settings: used in tests, and as a fallback when device
  /// storage is unavailable.
  AppSettings.memory() : _prefs = null, _secure = null;

  final SharedPreferences? _prefs;
  final FlutterSecureStorage? _secure;

  static const _kApiKey = 'claude_api_key';

  BrushKind brush = BrushKind.neon;
  Color color = const Color(0xFFA855F7);
  double width = 7;
  double glow = 0.8;
  LightMode lightMode = LightMode.steady;
  double cameraDim = 0.35;
  DrawGesture drawGesture = DrawGesture.point;
  MirrorMode mirror = MirrorMode.auto;
  bool depthWidth = true;
  bool showSkeleton = false;
  bool palmUndo = true;
  bool frontCamera = true;
  double smoothing = 0.6;
  bool sketchSuggestions = true;
  String claudeModel = ClaudeDreamer.defaultModel;
  bool onboarded = false;

  String? _apiKey;
  String? get claudeApiKey => _apiKey;
  bool get hasClaudeKey => (_apiKey ?? '').trim().isNotEmpty;

  BrushStyle get brushStyle => BrushStyle(kind: brush, color: color, width: width, glow: glow);

  void _read() {
    final p = _prefs!;
    brush = BrushKind.byName(p.getString('brush'));
    color = Color(p.getInt('color') ?? color.toARGB32());
    width = p.getDouble('width') ?? width;
    glow = p.getDouble('glow') ?? glow;
    lightMode = LightMode.byName(p.getString('lightMode'));
    cameraDim = p.getDouble('cameraDim') ?? cameraDim;
    drawGesture = DrawGesture.values.firstWhere(
      (g) => g.name == p.getString('drawGesture'),
      orElse: () => DrawGesture.point,
    );
    mirror = MirrorMode.values.firstWhere((m) => m.name == p.getString('mirror'), orElse: () => MirrorMode.auto);
    depthWidth = p.getBool('depthWidth') ?? depthWidth;
    showSkeleton = p.getBool('showSkeleton') ?? showSkeleton;
    palmUndo = p.getBool('palmUndo') ?? palmUndo;
    frontCamera = p.getBool('frontCamera') ?? frontCamera;
    smoothing = p.getDouble('smoothing') ?? smoothing;
    sketchSuggestions = p.getBool('sketchSuggestions') ?? sketchSuggestions;
    claudeModel = p.getString('claudeModel') ?? claudeModel;
    onboarded = p.getBool('onboarded') ?? onboarded;
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await Future.wait([
        p.setString('brush', brush.name),
        p.setInt('color', color.toARGB32()),
        p.setDouble('width', width),
        p.setDouble('glow', glow),
        p.setString('lightMode', lightMode.name),
        p.setDouble('cameraDim', cameraDim),
        p.setString('drawGesture', drawGesture.name),
        p.setString('mirror', mirror.name),
        p.setBool('depthWidth', depthWidth),
        p.setBool('showSkeleton', showSkeleton),
        p.setBool('palmUndo', palmUndo),
        p.setBool('frontCamera', frontCamera),
        p.setDouble('smoothing', smoothing),
        p.setBool('sketchSuggestions', sketchSuggestions),
        p.setString('claudeModel', claudeModel),
        p.setBool('onboarded', onboarded),
      ]);
    } catch (e) {
      debugPrint('Aerograph: could not save settings ($e)');
    }
  }

  /// Apply a change, notify listeners and persist.
  void update(void Function(AppSettings s) change) {
    change(this);
    notifyListeners();
    _save();
  }

  Future<void> setClaudeApiKey(String? key) async {
    final k = key?.trim();
    _apiKey = (k == null || k.isEmpty) ? null : k;
    notifyListeners();
    final secure = _secure;
    if (secure == null) return;
    try {
      if (_apiKey == null) {
        await secure.delete(key: _kApiKey);
      } else {
        await secure.write(key: _kApiKey, value: _apiKey);
      }
    } catch (e) {
      debugPrint('Aerograph: secure storage unavailable ($e)');
    }
  }
}
