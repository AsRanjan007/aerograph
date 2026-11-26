import 'package:material_ui/material_ui.dart';

import '../app/settings.dart';
import 'brand.dart';
import 'studio_screen.dart';

/// Animated intro: the mark paints itself, then the wordmark and the
/// author credit fade in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward()
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, a, _) => FadeTransition(
          opacity: a,
          child: StudioScreen(settings: widget.settings),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.night,
      body: GestureDetector(
        onTap: _go,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final draw = Curves.easeInOutCubic.transform((_c.value / 0.6).clamp(0.0, 1.0));
            final word = ((_c.value - 0.5) / 0.25).clamp(0.0, 1.0);
            final credit = ((_c.value - 0.68) / 0.22).clamp(0.0, 1.0);
            return Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: CustomPaint(painter: AerographMarkPainter(progress: draw)),
                      ),
                      const SizedBox(height: 24),
                      Opacity(
                        opacity: word,
                        child: Transform.translate(offset: Offset(0, 12 * (1 - word)), child: const Wordmark(size: 44)),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: word,
                        child: Text(
                          'PAINT THE AIR · TOUCH NOTHING',
                          style: TextStyle(color: Brand.mist.withValues(alpha: 0.85), letterSpacing: 3, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: Opacity(
                    opacity: credit,
                    child: const Center(child: AuthorCredit()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
