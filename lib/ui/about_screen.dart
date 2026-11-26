import 'package:material_ui/material_ui.dart';

import 'brand.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.night,
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Brand.ink, title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          Center(child: SizedBox(width: 140, height: 140, child: CustomPaint(painter: AerographMarkPainter()))),
          const SizedBox(height: 16),
          const Center(child: Wordmark(size: 38)),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'PAINT THE AIR · TOUCH NOTHING',
              style: TextStyle(color: Brand.mist.withValues(alpha: 0.8), letterSpacing: 3, fontSize: 12),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Aerograph turns your phone camera into a brush you never touch. Your fingertip paints strokes '
            'in the air; the app tracks 21 points of your hand in real time, on device, and renders the '
            'movement as light.',
            style: TextStyle(color: Brand.ink, height: 1.5),
          ),
          const SizedBox(height: 24),
          const _Guide(icon: Icons.back_hand_outlined, title: 'Raise your index finger', body: 'Only the index finger up paints. Two fingers up lifts the brush so you can move freely.'),
          const _Guide(icon: Icons.pinch_outlined, title: 'Or pinch to paint', body: 'Switch to pinch mode in Settings: thumb and index together paint, apart lifts.'),
          const _Guide(icon: Icons.open_in_full, title: 'Closer = thicker', body: 'Move your hand toward the camera for bold light, away for fine lines.'),
          const _Guide(icon: Icons.front_hand_outlined, title: 'Open palm to undo', body: 'Hold an open palm still for a second to remove the last stroke.'),
          const _Guide(icon: Icons.auto_awesome, title: 'Imagine', body: 'Type what you imagine. Pick a recommendation and watch it build itself in the air.'),
          const SizedBox(height: 32),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/branding/ar_signature.jpg', width: 120, height: 120, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 14),
          const Center(child: AuthorCredit()),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Hand tracking: MediaPipe Hand Landmarker (Apache 2.0).',
              style: TextStyle(color: Brand.mist.withValues(alpha: 0.6), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.deep, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Brand.orchid, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body, style: TextStyle(color: Brand.mist.withValues(alpha: 0.8), fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}
