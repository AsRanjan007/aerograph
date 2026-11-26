import 'dart:math' as math;

import 'package:aero_hand_tracker/aero_hand_tracker.dart';
import 'package:aerograph/tracking/hand_pose.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a synthetic upright hand (wrist at bottom). [extended] flags are
/// index, middle, ring, pinky. Folded fingers curl back toward the palm.
List<Landmark> hand({
  required List<bool> extended,
  bool pinch = false,
  double angle = 0,
  double scale = 1,
}) {
  final pts = List<Landmark>.filled(21, const Landmark(0, 0, 0));
  Landmark at(double x, double y) {
    // rotate around wrist (0.5, 0.8)
    final dx = (x - 0.5) * scale, dy = (y - 0.8) * scale;
    final c = math.cos(angle), s = math.sin(angle);
    return Landmark(0.5 + dx * c - dy * s, 0.8 + dx * s + dy * c, 0);
  }

  pts[0] = at(0.5, 0.8);
  // thumb
  pts[1] = at(0.44, 0.76);
  pts[2] = at(0.4, 0.71);
  pts[3] = at(0.37, 0.67);
  pts[4] = pinch ? at(0.45, 0.47) : at(0.33, 0.63);
  const xs = [0.44, 0.5, 0.56, 0.61];
  for (var f = 0; f < 4; f++) {
    final base = 5 + f * 4;
    final x = xs[f];
    pts[base] = at(x, 0.62); // mcp
    pts[base + 1] = at(x, 0.54); // pip
    if (extended[f]) {
      pts[base + 2] = at(x, 0.48);
      pts[base + 3] = at(x, 0.42);
    } else {
      pts[base + 2] = at(x, 0.6);
      pts[base + 3] = at(x, 0.64);
    }
  }
  if (pinch) {
    // index curls so its tip meets the thumb tip
    pts[7] = at(0.45, 0.5);
    pts[8] = at(0.455, 0.475);
  }
  return pts;
}

void main() {
  test('index only is a point pose', () {
    expect(classifyPose(hand(extended: [true, false, false, false])).pose, HandPose.point);
  });

  test('index + middle is peace (brush lifted)', () {
    expect(classifyPose(hand(extended: [true, true, false, false])).pose, HandPose.peace);
  });

  test('all fingers is an open palm', () {
    expect(classifyPose(hand(extended: [true, true, true, true])).pose, HandPose.openPalm);
  });

  test('no fingers is a fist', () {
    expect(classifyPose(hand(extended: [false, false, false, false])).pose, HandPose.fist);
  });

  test('thumb meeting index is a pinch', () {
    expect(classifyPose(hand(extended: [false, false, false, false], pinch: true)).pose, HandPose.pinch);
  });

  test('classification is rotation invariant', () {
    for (final a in [0.0, 0.8, -1.2, math.pi / 2, math.pi]) {
      expect(classifyPose(hand(extended: [true, false, false, false], angle: a)).pose, HandPose.point, reason: 'angle $a');
      expect(classifyPose(hand(extended: [true, true, true, true], angle: a)).pose, HandPose.openPalm, reason: 'angle $a');
    }
  });

  test('hand size grows as the hand gets closer', () {
    final far = classifyPose(hand(extended: [true, false, false, false], scale: 0.6)).handSize;
    final near = classifyPose(hand(extended: [true, false, false, false], scale: 1.5)).handSize;
    expect(near, greaterThan(far * 2));
  });

  test('too few landmarks is none', () {
    expect(classifyPose(const []).pose, HandPose.none);
  });

  test('stabilizer ignores one-frame flickers', () {
    final s = PoseStabilizer(frames: 2);
    s.push(HandPose.point);
    s.push(HandPose.point);
    expect(s.stable, HandPose.point);
    expect(s.push(HandPose.peace), HandPose.point); // single flicker
    expect(s.push(HandPose.point), HandPose.point);
    s.push(HandPose.peace);
    expect(s.push(HandPose.peace), HandPose.peace);
  });
}
