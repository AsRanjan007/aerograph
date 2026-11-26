import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../app/settings.dart';
import '../magic/magic_build.dart';
import '../magic/recommender.dart';
import '../magic/shape_recognizer.dart';
import '../paint/brush.dart';
import '../paint/stroke.dart';
import '../services/exporter.dart';
import '../tracking/air_tracker.dart';
import '../tracking/hand_pose.dart';
import 'brand.dart';
import 'canvas_layers.dart';
import 'imagine_sheet.dart';
import 'settings_sheet.dart';

/// The air canvas: live camera, hand tracking, light strokes and magic.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.settings, this.tracker});

  final AppSettings settings;

  /// Injected in tests; created on demand otherwise.
  final AirTracker? tracker;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AirTracker _tracker = widget.tracker ?? AirTracker();
  final StrokeHistory _history = StrokeHistory();
  final Recommender _recommender = Recommender();
  final ShapeRecognizer _shapes = const ShapeRecognizer();
  final Exporter _exporter = const Exporter();
  final List<Particle> _particles = [];
  final math.Random _rnd = math.Random();

  /// Seconds since the studio opened; drives animated light.
  final ValueNotifier<double> _clock = ValueNotifier(0);

  /// Bumped whenever finished strokes change.
  final ValueNotifier<int> _artRevision = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;

  Stroke? _live;
  bool _penDown = false;
  bool _touchDrawing = false;

  MagicBuild? _magic;
  late final AnimationController _magicCtrl = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _finishMagic();
    });

  List<Recommendation> _suggestions = const [];
  Stroke? _suggestionSource;

  double _palmHold = 0; // seconds the open palm has been held
  static const _palmHoldNeeded = 1.1;

  bool _panelOpen = false;
  bool _saving = false;
  double _noHandSeconds = 0;

  AppSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySettings();
    _s.addListener(_applySettings);
    _tracker.pointer.addListener(_onPointer);
    _tracker.addListener(_onTrackerChanged);
    _tracker.start(front: _s.frontCamera);
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOnboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _s.removeListener(_applySettings);
    _tracker.pointer.removeListener(_onPointer);
    _tracker.removeListener(_onTrackerChanged);
    _ticker.dispose();
    _magicCtrl.dispose();
    if (widget.tracker == null) _tracker.dispose();
    _clock.dispose();
    _artRevision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _endStroke();
      _tracker.stop();
    } else if (state == AppLifecycleState.resumed && _tracker.controller == null) {
      _tracker.start(front: _s.frontCamera);
    }
  }

  void _applySettings() {
    _tracker.usePinch = _s.drawGesture == DrawGesture.pinch;
    _tracker.smoothing = _s.smoothing;
    _tracker.mirrorOverride = switch (_s.mirror) {
      MirrorMode.auto => null,
      MirrorMode.on => true,
      MirrorMode.off => false,
    };
    if (mounted) setState(() {});
  }

  void _onTrackerChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Frame loop
  // ---------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;
    _clock.value = elapsed.inMicroseconds / 1e6;

    for (final p in _particles) {
      p.life -= dt;
      p.position += p.velocity * dt;
      p.velocity = p.velocity * (1 - 1.8 * dt) + const Offset(0, -12) * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);

    final ptr = _tracker.pointer.value;
    if (ptr.visible && ptr.pose == HandPose.openPalm && _s.palmUndo && !_penDown && _magic == null) {
      _palmHold += dt;
      if (_palmHold >= _palmHoldNeeded) {
        _palmHold = -0.8; // cool-down so one long hold doesn't undo everything
        _undo();
      }
    } else if (_palmHold > 0) {
      _palmHold = 0;
    } else if (_palmHold < 0) {
      _palmHold = math.min(0, _palmHold + dt);
    }

    if (ptr.visible) {
      _noHandSeconds = 0;
    } else {
      final before = _noHandSeconds;
      _noHandSeconds += dt;
      if (before < 3 && _noHandSeconds >= 3 && mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Painting
  // ---------------------------------------------------------------------------

  void _onPointer() {
    if (_touchDrawing) return;
    final ptr = _tracker.pointer.value;
    final wantsDown =
        ptr.visible &&
        _magic == null &&
        (_s.drawGesture == DrawGesture.pinch ? ptr.pose == HandPose.pinch : ptr.pose == HandPose.point);
    if (wantsDown) {
      final widthFactor = _s.depthWidth ? ptr.depth.clamp(0.5, 2.2) : 1.0;
      _addPoint(ptr.position, widthFactor: widthFactor);
    } else if (_penDown) {
      _endStroke();
    }
    if (mounted && (ptr.visible != _wasVisible || ptr.pose != _lastPose)) {
      _wasVisible = ptr.visible;
      _lastPose = ptr.pose;
      setState(() {});
    }
  }

  bool _wasVisible = false;
  HandPose _lastPose = HandPose.none;

  void _addPoint(Offset p, {double widthFactor = 1}) {
    if (!_penDown || _live == null) {
      _penDown = true;
      _live = Stroke(style: _s.brushStyle.copyWith(width: _s.width * widthFactor));
      _dismissSuggestions();
    }
    if (_live!.addPoint(p)) _emit(p, _s.color, count: _s.brush == BrushKind.sparkle ? 3 : 1);
  }

  void _endStroke() {
    final s = _live;
    _live = null;
    _penDown = false;
    if (s == null) return;
    if (s.points.length < 2 && s.length < 4) return;
    _history.add(s);
    _artRevision.value = _history.revision;
    _suggestFromSketch(s);
    if (mounted) setState(() {});
  }

  void _emit(Offset at, Color color, {int count = 1, double speed = 40, double life = 0.7}) {
    for (var i = 0; i < count; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final v = Offset(math.cos(a), math.sin(a)) * (speed * (0.3 + _rnd.nextDouble()));
      _particles.add(Particle(at, v, color, 2 + _rnd.nextDouble() * 3, life * (0.5 + _rnd.nextDouble())));
    }
    if (_particles.length > 400) _particles.removeRange(0, _particles.length - 400);
  }

  void _suggestFromSketch(Stroke s) {
    if (!_s.sketchSuggestions) return;
    final guess = _shapes.recognize(s.points);
    final recs = _recommender.fromSketch(guess);
    if (recs.isEmpty) return;
    setState(() {
      _suggestions = recs;
      _suggestionSource = s;
    });
  }

  void _dismissSuggestions() {
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestions = const [];
      _suggestionSource = null;
    });
  }

  void _undo() {
    _endStroke();
    _history.undo();
    _artRevision.value = _history.revision;
    _dismissSuggestions();
    setState(() {});
  }

  void _redo() {
    _history.redo();
    _artRevision.value = _history.revision;
    setState(() {});
  }

  void _clear() {
    _endStroke();
    _history.clear();
    _artRevision.value = _history.revision;
    _dismissSuggestions();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Canvas cleared'),
        action: SnackBarAction(label: 'Undo', onPressed: _redo),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Magic
  // ---------------------------------------------------------------------------

  Future<void> _openImagine() async {
    _endStroke();
    final rec = await ImagineSheet.show(context, _s, _recommender);
    if (rec != null && mounted) _startMagic(rec);
  }

  void _startMagic(Recommendation rec, {Stroke? replacing}) {
    final size = MediaQuery.of(context).size;
    Rect area;
    if (replacing != null) {
      // Grow the art out of the sketch: centre on it, at least half the screen wide.
      final b = replacing.bounds;
      final side = math.max(math.max(b.width, b.height) * 1.3, size.width * 0.55);
      area = Rect.fromCenter(center: b.center, width: side, height: side / rec.art.aspect);
      _history.remove(replacing);
      _artRevision.value = _history.revision;
    } else {
      area = Rect.fromLTRB(0, size.height * 0.1, size.width, size.height * 0.72);
    }
    final build = MagicBuild.layout(art: rec.art, area: area, glow: _s.glow);
    setState(() {
      _magic = build;
      _panelOpen = false;
      _suggestions = const [];
      _suggestionSource = null;
    });
    _magicCtrl
      ..duration = build.duration
      ..forward(from: 0);
  }

  void _finishMagic() {
    final m = _magic;
    if (m == null) return;
    _history.addAll(m.strokes);
    _artRevision.value = _history.revision;
    for (final s in m.strokes) {
      if (s.points.isEmpty) continue;
      _emit(s.points[s.points.length ~/ 2], s.style.color, count: 6, speed: 120, life: 1.1);
    }
    setState(() => _magic = null);
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save({required bool withPhoto}) async {
    if (_saving) return;
    _endStroke();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final size = MediaQuery.of(context).size;
    final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    try {
      final c = _tracker.controller;
      final photo = withPhoto && c != null ? await _exporter.capturePhoto(c) : null;
      final png = await _exporter.render(
        strokes: List.of(_history.strokes),
        logicalSize: size,
        pixelRatio: ratio,
        photo: photo,
        mirrorPhoto: _tracker.isFront,
        dim: _s.cameraDim,
        mode: _s.lightMode,
        time: _clock.value,
      );
      await _exporter.saveToGallery(png);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            withPhoto && photo == null ? 'Saved artwork (camera photo unavailable)' : 'Saved to your gallery',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseSave() async {
    final withPhoto = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Brand.night,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Brand.orchid),
              title: const Text('Light + camera photo', style: TextStyle(color: Brand.ink)),
              subtitle: Text(
                'Your art over what the camera sees',
                style: TextStyle(color: Brand.mist.withValues(alpha: 0.7)),
              ),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined, color: Brand.sky),
              title: const Text('Light only', style: TextStyle(color: Brand.ink)),
              subtitle: Text(
                'Your art on a night background',
                style: TextStyle(color: Brand.mist.withValues(alpha: 0.7)),
              ),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (withPhoto != null) await _save(withPhoto: withPhoto);
  }

  // ---------------------------------------------------------------------------
  // Onboarding
  // ---------------------------------------------------------------------------

  Future<void> _maybeOnboard() async {
    if (_s.onboarded || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Brand.night,
        title: const Text('Paint with light', style: TextStyle(color: Brand.ink)),
        content: Text(
          'Prop your phone up and step back so your hand is in view.\n\n'
          '• Index finger up: paint\n'
          '• Two fingers up: lift the brush\n'
          '• Open palm, hold: undo\n'
          '• Imagine: tell Aerograph an idea and watch it appear',
          style: TextStyle(color: Brand.mist.withValues(alpha: 0.9), height: 1.5),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Start painting'))],
      ),
    );
    _s.update((x) => x.onboarded = true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _tracker.screenSize = size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CameraBackground(tracker: _tracker),
          IgnorePointer(
            child: ColoredBox(color: Colors.black.withValues(alpha: _s.cameraDim)),
          ),
          // Touch drawing too, for when you'd rather use a finger on glass.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              _touchDrawing = true;
              _addPoint(d.localPosition);
            },
            onPanUpdate: (d) => _addPoint(d.localPosition),
            onPanEnd: (_) {
              _endStroke();
              _touchDrawing = false;
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: ArtLayerPainter(
                  history: _history,
                  mode: _s.lightMode,
                  clock: _clock,
                  repaint: _s.lightMode == LightMode.steady ? _artRevision : Listenable.merge([_artRevision, _clock]),
                ),
                foregroundPainter: LiveLayerPainter(
                  live: () => _live,
                  magic: () => _magic,
                  magicProgress: () => _magicCtrl.value,
                  particles: _particles,
                  pointer: _tracker.pointer,
                  penDown: () => _penDown,
                  cursorColor: () => _s.color,
                  holdProgress: () => (_palmHold / _palmHoldNeeded).clamp(0.0, 1.0),
                  showSkeleton: _s.showSkeleton,
                  clock: _clock,
                  repaint: _clock,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  tracker: _tracker,
                  penDown: _penDown,
                  onFlip: () async {
                    _s.update((x) => x.frontCamera = !x.frontCamera);
                    await _tracker.switchCamera();
                  },
                  onSettings: () => SettingsSheet.show(context, _s),
                ),
                if (_noHandSeconds >= 3 && _tracker.status == TrackerStatus.running && _magic == null)
                  _Hint(gesture: _s.drawGesture),
                if (_tracker.status != TrackerStatus.running && _tracker.status != TrackerStatus.starting)
                  _CameraProblem(
                    tracker: _tracker,
                    onRetry: () => _tracker.start(front: _s.frontCamera),
                  ),
                const Spacer(),
                if (_suggestions.isNotEmpty)
                  _SuggestionStrip(
                    suggestions: _suggestions,
                    onPick: (r) => _startMagic(r, replacing: _suggestionSource),
                    onDismiss: _dismissSuggestions,
                  ),
                if (_panelOpen) _LightPanel(settings: _s),
                _BottomBar(
                  settings: _s,
                  panelOpen: _panelOpen,
                  onTogglePanel: () => setState(() => _panelOpen = !_panelOpen),
                  onImagine: _openImagine,
                ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: size.height * 0.24,
            child: SafeArea(
              child: _SideRail(
                canUndo: _history.canUndo,
                canRedo: _history.canRedo,
                saving: _saving,
                onUndo: _undo,
                onRedo: _redo,
                onClear: _history.canUndo ? _clear : null,
                onSave: _history.canUndo ? _chooseSave : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraBackground extends StatelessWidget {
  const _CameraBackground({required this.tracker});
  final AirTracker tracker;

  @override
  Widget build(BuildContext context) {
    final c = tracker.controller;
    if (c == null || !c.value.isInitialized) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF15103A), Brand.night], radius: 1.1)),
      );
    }
    final ps = c.value.previewSize!;
    final portrait = Size(math.min(ps.width, ps.height), math.max(ps.width, ps.height));
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: portrait.width, height: portrait.height, child: CameraPreview(c)),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.tracker, required this.penDown, required this.onFlip, required this.onSettings});
  final AirTracker tracker;
  final bool penDown;
  final VoidCallback onFlip;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final ptr = tracker.pointer.value;
    final (label, color) = switch (tracker.status) {
      TrackerStatus.starting => ('Starting camera…', Brand.mist),
      TrackerStatus.running when !ptr.visible => ('Show your hand', Brand.mist),
      TrackerStatus.running when penDown => ('Painting', const Color(0xFF4ADE80)),
      TrackerStatus.running when ptr.pose == HandPose.openPalm => ('Hold to undo', const Color(0xFFFDE047)),
      TrackerStatus.running => ('Brush lifted', Brand.sky),
      _ => ('Camera off', const Color(0xFFFF8FA3)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          SizedBox(width: 34, height: 34, child: CustomPaint(painter: AerographMarkPainter())),
          if (MediaQuery.of(context).size.width >= 430) ...[const SizedBox(width: 8), const Wordmark(size: 20)],
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _Glass(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Brand.ink, fontSize: 12),
                        ),
                      ),
                      if (tracker.status == TrackerStatus.running && tracker.fps > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${tracker.fps.round()} fps',
                          style: TextStyle(color: Brand.mist.withValues(alpha: 0.6), fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: onFlip,
            icon: const Icon(Icons.cameraswitch_outlined, color: Brand.ink),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.tune, color: Brand.ink),
          ),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 20});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Brand.night.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: child,
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.gesture});
  final DrawGesture gesture;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: _Glass(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(gesture == DrawGesture.pinch ? Icons.pinch_outlined : Icons.back_hand_outlined, color: Brand.orchid),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                gesture == DrawGesture.pinch
                    ? 'Hold your hand up to the camera and pinch to paint.'
                    : 'Hold your hand up to the camera and raise your index finger to paint.',
                style: const TextStyle(color: Brand.ink, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.tracker, required this.onRetry});
  final AirTracker tracker;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = switch (tracker.status) {
      TrackerStatus.noPermission =>
        'Aerograph needs the camera to see your fingertip. Allow camera access in Settings, then retry.',
      TrackerStatus.noCamera => 'No camera found. You can still paint by touching the screen.',
      _ =>
        'The camera could not start${tracker.errorMessage == null ? '' : ': ${tracker.errorMessage}'}. You can still paint by touch.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _Glass(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.videocam_off_outlined, color: Color(0xFFFF8FA3)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(msg, style: const TextStyle(color: Brand.ink, fontSize: 13)),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({required this.suggestions, required this.onPick, required this.onDismiss});
  final List<Recommendation> suggestions;
  final ValueChanged<Recommendation> onPick;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: _Glass(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Brand.orchid),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      suggestions.first.reason,
                      style: const TextStyle(color: Brand.ink, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, size: 18, color: Brand.mist),
                  ),
                ],
              ),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final r = suggestions[i];
                    return GestureDetector(
                      onTap: () => onPick(r),
                      child: Container(
                        width: 82,
                        decoration: BoxDecoration(
                          color: Brand.night.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: r.art.palette.colors.first.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: CustomPaint(size: Size.infinite, painter: ArtPreviewPainter(r.art)),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                              child: Text(
                                r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Brand.ink, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LightPanel extends StatelessWidget {
  const _LightPanel({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: _Glass(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final b in BrushKind.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(b.label),
                          selected: s.brush == b,
                          onSelected: (_) => s.update((x) => x.brush = b),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in LightPalette.swatches)
                      GestureDetector(
                        onTap: () => s.update((x) => x.color = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: s.color == c ? Colors.white : Colors.transparent, width: 3),
                            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: s.color == c ? 14 : 6)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _row(Icons.line_weight, 'Size', s.width, 2, 20, (v) => s.update((x) => x.width = v)),
              _row(Icons.light_mode_outlined, 'Glow', s.glow, 0, 1, (v) => s.update((x) => x.glow = v)),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in LightMode.values)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: s.lightMode == m,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => s.update((x) => x.lightMode = m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, double v, double min, double max, ValueChanged<double> onChanged) => Row(
    children: [
      Icon(icon, color: Brand.mist, size: 18),
      const SizedBox(width: 6),
      SizedBox(
        width: 40,
        child: Text(label, style: const TextStyle(color: Brand.ink, fontSize: 12)),
      ),
      Expanded(
        child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ),
    ],
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.settings,
    required this.panelOpen,
    required this.onTogglePanel,
    required this.onImagine,
  });
  final AppSettings settings;
  final bool panelOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback onImagine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          _Glass(
            radius: 28,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onTogglePanel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: settings.color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: settings.color, blurRadius: 10 * settings.glow)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      settings.brush.label,
                      style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    Icon(panelOpen ? Icons.expand_more : Icons.expand_less, color: Brand.mist, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: Brand.gradient,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Brand.violet.withValues(alpha: 0.6), blurRadius: 18)],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: onImagine,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Imagine',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.canUndo,
    required this.canRedo,
    required this.saving,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSave,
  });

  final bool canUndo, canRedo, saving;
  final VoidCallback onUndo, onRedo;
  final VoidCallback? onClear, onSave;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, color: onTap == null ? Colors.white24 : Brand.ink),
    );
    return _Glass(
      radius: 24,
      child: Column(
        children: [
          btn(Icons.undo, 'Undo', canUndo ? onUndo : null),
          btn(Icons.redo, 'Redo', canRedo ? onRedo : null),
          btn(Icons.delete_outline, 'Clear', onClear),
          saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : btn(Icons.save_alt, 'Save', onSave),
        ],
      ),
    );
  }
}
