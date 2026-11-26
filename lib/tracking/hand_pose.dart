import 'dart:math' as math;

import 'package:aero_hand_tracker/aero_hand_tracker.dart';

/// MediaPipe hand landmark indices.
abstract final class HandIdx {
  static const wrist = 0;
  static const thumbCmc = 1, thumbMcp = 2, thumbIp = 3, thumbTip = 4;
  static const indexMcp = 5, indexPip = 6, indexDip = 7, indexTip = 8;
  static const middleMcp = 9, middlePip = 10, middleDip = 11, middleTip = 12;
  static const ringMcp = 13, ringPip = 14, ringDip = 15, ringTip = 16;
  static const pinkyMcp = 17, pinkyPip = 18, pinkyDip = 19, pinkyTip = 20;

  /// Bone pairs for drawing a skeleton overlay.
  static const bones = <(int, int)>[
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (0, 5),
    (5, 6),
    (6, 7),
    (7, 8),
    (5, 9),
    (9, 10),
    (10, 11),
    (11, 12),
    (9, 13),
    (13, 14),
    (14, 15),
    (15, 16),
    (13, 17),
    (0, 17),
    (17, 18),
    (18, 19),
    (19, 20),
  ];
}

enum HandPose { none, point, peace, pinch, openPalm, fist, other }

class PoseReading {
  const PoseReading({
    required this.pose,
    required this.indexExtended,
    required this.middleExtended,
    required this.ringExtended,
    required this.pinkyExtended,
    required this.thumbExtended,
    required this.pinchRatio,
    required this.handSize,
  });

  final HandPose pose;
  final bool indexExtended, middleExtended, ringExtended, pinkyExtended, thumbExtended;

  /// Thumb-tip to index-tip distance divided by hand size. < ~0.35 is a pinch.
  final double pinchRatio;

  /// Wrist → middle-finger MCP distance in normalized image units. Larger
  /// means the hand is closer to the camera.
  final double handSize;
}

double _d(Landmark a, Landmark b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Rotation-invariant pose classification from 21 landmarks. A finger counts
/// as extended when its tip is clearly farther from the wrist than its PIP
/// joint, which holds for any hand orientation.
PoseReading classifyPose(List<Landmark> lm, {double pinchThreshold = 0.35}) {
  if (lm.length < 21) {
    return const PoseReading(
      pose: HandPose.none,
      indexExtended: false,
      middleExtended: false,
      ringExtended: false,
      pinkyExtended: false,
      thumbExtended: false,
      pinchRatio: 1,
      handSize: 0,
    );
  }
  final w = lm[HandIdx.wrist];
  bool ext(int tip, int pip) => _d(lm[tip], w) > _d(lm[pip], w) * 1.12;

  final index = ext(HandIdx.indexTip, HandIdx.indexPip);
  final middle = ext(HandIdx.middleTip, HandIdx.middlePip);
  final ring = ext(HandIdx.ringTip, HandIdx.ringPip);
  final pinky = ext(HandIdx.pinkyTip, HandIdx.pinkyPip);
  final thumb = _d(lm[HandIdx.thumbTip], lm[HandIdx.pinkyMcp]) > _d(lm[HandIdx.thumbIp], lm[HandIdx.pinkyMcp]) * 1.08;

  final size = math.max(1e-6, _d(w, lm[HandIdx.middleMcp]));
  final pinchRatio = _d(lm[HandIdx.thumbTip], lm[HandIdx.indexTip]) / size;

  final fingers = [index, middle, ring, pinky].where((e) => e).length;
  HandPose pose;
  if (pinchRatio < pinchThreshold && !middle) {
    pose = HandPose.pinch;
  } else if (index && !middle && !ring && !pinky) {
    pose = HandPose.point;
  } else if (index && middle && !ring && !pinky) {
    pose = HandPose.peace;
  } else if (fingers >= 4) {
    pose = HandPose.openPalm;
  } else if (fingers == 0) {
    pose = HandPose.fist;
  } else {
    pose = HandPose.other;
  }
  return PoseReading(
    pose: pose,
    indexExtended: index,
    middleExtended: middle,
    ringExtended: ring,
    pinkyExtended: pinky,
    thumbExtended: thumb,
    pinchRatio: pinchRatio,
    handSize: size,
  );
}

/// Debounces raw per-frame poses: a new pose must persist for [frames]
/// consecutive frames before it is reported. Prevents single-frame
/// misclassifications from breaking a stroke.
class PoseStabilizer {
  PoseStabilizer({this.frames = 2});
  final int frames;

  HandPose _stable = HandPose.none;
  HandPose _candidate = HandPose.none;
  int _count = 0;

  HandPose get stable => _stable;

  HandPose push(HandPose raw) {
    if (raw == _stable) {
      _candidate = raw;
      _count = 0;
      return _stable;
    }
    if (raw == _candidate) {
      _count++;
    } else {
      _candidate = raw;
      _count = 1;
    }
    if (_count >= frames) {
      _stable = raw;
      _count = 0;
    }
    return _stable;
  }

  void reset() {
    _stable = HandPose.none;
    _candidate = HandPose.none;
    _count = 0;
  }
}
