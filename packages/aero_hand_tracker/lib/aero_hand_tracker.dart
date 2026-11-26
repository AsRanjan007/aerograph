import 'package:flutter/services.dart';

/// Pixel layout of a camera frame handed to [AeroHandTracker.detect].
enum FrameFormat { nv21, bgra8888 }

/// One tracked hand: 21 landmarks in normalized image coordinates of the
/// upright (rotated) frame. `x`/`y` are in [0, 1], `z` is relative depth
/// (smaller = closer to the camera), wrist-origin, roughly in x-units.
class TrackedHand {
  TrackedHand({required this.landmarks, required this.handedness, required this.score});

  /// 21 points × (x, y, z).
  final List<Landmark> landmarks;

  /// "Left" or "Right" as reported by the model (from the camera's view).
  final String handedness;
  final double score;
}

class Landmark {
  const Landmark(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  @override
  String toString() => 'Landmark(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

class HandFrameResult {
  HandFrameResult({
    required this.hands,
    required this.imageWidth,
    required this.imageHeight,
    required this.inferenceMs,
  });

  final List<TrackedHand> hands;

  /// Size of the upright frame the landmarks are normalized against.
  final int imageWidth;
  final int imageHeight;
  final int inferenceMs;
}

/// Thin bridge to the native MediaPipe Hand Landmarker.
class AeroHandTracker {
  AeroHandTracker({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('aero_hand_tracker');

  final MethodChannel _channel;
  bool _ready = false;

  bool get isReady => _ready;

  /// Loads the `.task` model bundled as a Flutter asset.
  Future<void> initialize({
    String modelAsset = 'assets/models/hand_landmarker.task',
    int maxHands = 1,
    double minDetectionConfidence = 0.5,
    double minPresenceConfidence = 0.5,
    double minTrackingConfidence = 0.5,
    bool useGpu = false,
  }) async {
    await _channel.invokeMethod<void>('initialize', <String, Object>{
      'modelAsset': modelAsset,
      'maxHands': maxHands,
      'minDetectionConfidence': minDetectionConfidence,
      'minPresenceConfidence': minPresenceConfidence,
      'minTrackingConfidence': minTrackingConfidence,
      'useGpu': useGpu,
    });
    _ready = true;
  }

  /// Runs detection on one frame. [rotation] is the clockwise rotation in
  /// degrees needed to make the frame upright.
  Future<HandFrameResult> detect({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required FrameFormat format,
    required int rotation,
    required int timestampMs,
  }) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('detect', <String, Object>{
      'bytes': bytes,
      'width': width,
      'height': height,
      'bytesPerRow': bytesPerRow,
      'format': format.name,
      'rotation': rotation,
      'timestampMs': timestampMs,
    });
    return parseResult(raw ?? const <String, Object?>{});
  }

  Future<void> dispose() async {
    _ready = false;
    await _channel.invokeMethod<void>('dispose');
  }

  /// Exposed for tests.
  static HandFrameResult parseResult(Map<String, Object?> raw) {
    final hands = <TrackedHand>[];
    final list = (raw['hands'] as List<Object?>?) ?? const <Object?>[];
    for (final h in list) {
      final m = (h as Map<Object?, Object?>);
      final pts = (m['landmarks'] as List<Object?>).cast<num>();
      final lms = <Landmark>[
        for (var i = 0; i + 2 < pts.length; i += 3)
          Landmark(pts[i].toDouble(), pts[i + 1].toDouble(), pts[i + 2].toDouble()),
      ];
      hands.add(
        TrackedHand(
          landmarks: lms,
          handedness: (m['handedness'] as String?) ?? 'Unknown',
          score: ((m['score'] as num?) ?? 0).toDouble(),
        ),
      );
    }
    return HandFrameResult(
      hands: hands,
      imageWidth: ((raw['imageWidth'] as num?) ?? 0).toInt(),
      imageHeight: ((raw['imageHeight'] as num?) ?? 0).toInt(),
      inferenceMs: ((raw['inferenceMs'] as num?) ?? 0).toInt(),
    );
  }
}
