import 'dart:math' as math;
import 'dart:ui';

/// One Euro filter (Casiez et al. 2012): low jitter when the fingertip is
/// still, low lag when it moves fast. Operates on screen-space offsets.
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.2, this.beta = 0.02, this.dCutoff = 1.0});

  double minCutoff;
  double beta;
  final double dCutoff;

  Offset? _x;
  Offset _dx = Offset.zero;
  int? _lastMs;

  void reset() {
    _x = null;
    _dx = Offset.zero;
    _lastMs = null;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  Offset filter(Offset value, int timestampMs) {
    final prev = _x;
    final last = _lastMs;
    _lastMs = timestampMs;
    if (prev == null || last == null) {
      _x = value;
      return value;
    }
    final dt = math.max(1, timestampMs - last) / 1000.0;
    final rawDx = (value - prev) / dt;
    final aD = _alpha(dCutoff, dt);
    _dx = Offset.lerp(_dx, rawDx, aD)!;
    final cutoff = minCutoff + beta * _dx.distance;
    final a = _alpha(cutoff, dt);
    final next = Offset.lerp(prev, value, a)!;
    _x = next;
    return next;
  }
}
