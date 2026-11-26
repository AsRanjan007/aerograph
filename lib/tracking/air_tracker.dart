import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:aero_hand_tracker/aero_hand_tracker.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'frame_mapper.dart';
import 'hand_pose.dart';
import 'one_euro_filter.dart';

/// Snapshot of the tracked hand in screen space.
class AirPointer {
  const AirPointer({
    required this.visible,
    this.position = Offset.zero,
    this.pose = HandPose.none,
    this.depth = 1.0,
    this.skeleton = const [],
    this.timestampMs = 0,
  });

  static const hidden = AirPointer(visible: false);

  final bool visible;

  /// Filtered brush tip position (logical pixels).
  final Offset position;
  final HandPose pose;

  /// Hand size relative to a typical arm's-length hand. >1 = closer.
  final double depth;

  /// All 21 landmarks in screen space (unfiltered), for the overlay.
  final List<Offset> skeleton;
  final int timestampMs;
}

enum TrackerStatus { starting, noPermission, noCamera, running, error }

/// Owns the camera, streams frames to the native hand landmarker, and turns
/// the results into a smooth on-screen pointer.
class AirTracker extends ChangeNotifier {
  AirTracker({AeroHandTracker? tracker}) : _tracker = tracker ?? AeroHandTracker();

  final AeroHandTracker _tracker;
  final OneEuroFilter _filter = OneEuroFilter();
  final PoseStabilizer _stabilizer = PoseStabilizer(frames: 2);

  CameraController? controller;
  TrackerStatus status = TrackerStatus.starting;
  String? errorMessage;

  /// Set when the hand model could not load; the camera still runs and
  /// touch painting still works.
  String? trackingError;

  /// Latest pointer. Listen to [pointer] for per-frame updates.
  final ValueNotifier<AirPointer> pointer = ValueNotifier(AirPointer.hidden);

  /// Frames processed per second (smoothed).
  double fps = 0;
  int lastInferenceMs = 0;

  Size screenSize = Size.zero;
  bool usePinch = false;
  bool? mirrorOverride;

  bool _busy = false;
  bool _disposed = false;
  int _lastFrameMs = 0;
  int _lastSeenMs = 0;
  bool _front = true;

  bool get isFront => _front;

  /// 0..1 → filter tuning. Higher = smoother but laggier.
  set smoothing(double v) {
    final s = v.clamp(0.0, 1.0);
    _filter.minCutoff = 3.0 - 2.4 * s; // 3.0 .. 0.6 Hz
    _filter.beta = 0.05 - 0.04 * s;
  }

  Future<void> start({bool front = true}) async {
    _front = front;
    status = TrackerStatus.starting;
    notifyListeners();
    try {
      if (!_tracker.isReady) {
        try {
          await _tracker.initialize(maxHands: 1);
          trackingError = null;
        } catch (e) {
          trackingError = '$e';
          debugPrint('Aerograph: hand tracking unavailable: $e');
        }
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        status = TrackerStatus.noCamera;
        notifyListeners();
        return;
      }
      final wanted = front ? CameraLensDirection.front : CameraLensDirection.back;
      final cam = cameras.firstWhere((c) => c.lensDirection == wanted, orElse: () => cameras.first);
      _front = cam.lensDirection == CameraLensDirection.front;

      final c = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      controller = c;
      _filter.reset();
      _stabilizer.reset();
      await c.startImageStream(_onFrame);
      status = TrackerStatus.running;
      notifyListeners();
    } on CameraException catch (e) {
      status = (e.code.contains('Denied') || e.code.contains('denied') || e.code.contains('Permission'))
          ? TrackerStatus.noPermission
          : TrackerStatus.error;
      errorMessage = e.description ?? e.code;
      notifyListeners();
    } catch (e) {
      status = TrackerStatus.error;
      errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final c = controller;
    controller = null;
    pointer.value = AirPointer.hidden;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      await c.dispose();
    }
  }

  Future<void> switchCamera() async {
    await stop();
    await start(front: !_front);
  }

  /// Clockwise rotation that makes the analysis frame upright for a
  /// portrait-locked UI.
  int get _rotation {
    final c = controller;
    if (c == null) return 0;
    if (Platform.isIOS) return 0; // camera plugin delivers upright frames on iOS
    return c.description.sensorOrientation;
  }

  bool get _mirror {
    final o = mirrorOverride;
    if (o != null) return o;
    // Android frames are raw sensor images; the preview is mirrored for the
    // front camera. iOS frames are already mirrored like the preview.
    return _front && Platform.isAndroid;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _disposed || !_tracker.isReady) return;
    _busy = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final plane = image.planes.first;
      final result = await _tracker.detect(
        bytes: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        format: Platform.isAndroid ? FrameFormat.nv21 : FrameFormat.bgra8888,
        rotation: _rotation,
        timestampMs: now,
      );
      if (_disposed) return;
      lastInferenceMs = result.inferenceMs;
      if (_lastFrameMs != 0) {
        final inst = 1000 / math.max(1, now - _lastFrameMs);
        fps = fps == 0 ? inst : fps * 0.9 + inst * 0.1;
      }
      _lastFrameMs = now;
      _handle(result, now);
    } catch (e) {
      debugPrint('Aerograph tracking error: $e');
    } finally {
      _busy = false;
    }
  }

  void _handle(HandFrameResult r, int now) {
    final c = controller;
    if (c == null || screenSize.isEmpty || r.hands.isEmpty || r.imageWidth == 0) {
      // Keep the last pointer briefly so a dropped frame doesn't end a stroke.
      if (now - _lastSeenMs > 220 && pointer.value.visible) {
        pointer.value = AirPointer.hidden;
        _filter.reset();
        _stabilizer.reset();
      }
      return;
    }
    _lastSeenMs = now;
    final hand = r.hands.first;
    final lm = hand.landmarks;
    final reading = classifyPose(lm);
    var pose = _stabilizer.push(reading.pose);

    final ps = c.value.previewSize;
    final preview = ps == null
        ? Size(r.imageWidth.toDouble(), r.imageHeight.toDouble())
        : Size(math.min(ps.width, ps.height), math.max(ps.width, ps.height));
    final mapper = FrameMapper(
      analysisSize: Size(r.imageWidth.toDouble(), r.imageHeight.toDouble()),
      previewSize: preview,
      screenSize: screenSize,
      mirror: _mirror,
    );
    final skeleton = [for (final p in lm) mapper.map(p.x, p.y)];

    Offset tip;
    if (usePinch) {
      final a = lm[HandIdx.thumbTip], b = lm[HandIdx.indexTip];
      tip = mapper.map((a.x + b.x) / 2, (a.y + b.y) / 2);
    } else {
      tip = skeleton[HandIdx.indexTip];
    }
    if (pose == HandPose.none) pose = reading.pose;

    pointer.value = AirPointer(
      visible: true,
      position: _filter.filter(tip, now),
      pose: pose,
      depth: (reading.handSize / 0.2).clamp(0.4, 2.5),
      skeleton: skeleton,
      timestampMs: now,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _tracker.dispose();
    pointer.dispose();
    super.dispose();
  }
}
