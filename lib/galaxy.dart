import 'dart:math';
import 'package:flutter/material.dart';

const kPurple = Color(0xFF7C3AED);
const kCyan = Color(0xFF22D3EE);
const kPink = Color(0xFFEC4899);
const kGold = Color(0xFFFBBF24);
const kMuted = Color(0xFFA5A1C2);

class _Star {
  final double x, y, size, phase;
  const _Star(this.x, this.y, this.size, this.phase);
}

class GalaxyBackground extends StatefulWidget {
  final Widget child;
  const GalaxyBackground({super.key, required this.child});
  @override
  State<GalaxyBackground> createState() => _GalaxyBackgroundState();
}

class _GalaxyBackgroundState extends State<GalaxyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  late final List<_Star> stars = List.generate(120, (i) {
    final r = Random(i * 7919 + 13);
    return _Star(r.nextDouble(), r.nextDouble(), r.nextDouble() * 1.6 + 0.4, r.nextDouble() * 6.28);
  });

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) => CustomPaint(painter: _GalaxyPainter(stars, c.value)),
          ),
        ),
      ),
      widget.child,
    ]);
  }
}

class _GalaxyPainter extends CustomPainter {
  final List<_Star> stars;
  final double t;
  _GalaxyPainter(this.stars, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05030F), Color(0xFF0B0620), Color(0xFF120A2E)],
        ).createShader(rect),
    );
    final a = t * 2 * pi;
    _nebula(canvas, size, Offset(size.width * (0.2 + 0.05 * sin(a)), size.height * 0.2), size.width * 0.8, kPurple, 0.28);
    _nebula(canvas, size, Offset(size.width * 0.85, size.height * (0.5 + 0.04 * cos(a))), size.width * 0.7, kPink, 0.16);
    _nebula(canvas, size, Offset(size.width * 0.2, size.height * 0.85), size.width * 0.8, kCyan, 0.14);
    final p = Paint();
    for (final s in stars) {
      final tw = 0.45 + 0.55 * sin(t * 2 * pi * 30 + s.phase).abs();
      p.color = Colors.white.withValues(alpha: tw * 0.9);
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.size * 0.6, p);
    }
  }

  void _nebula(Canvas canvas, Size size, Offset center, double radius, Color color, double alpha) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter old) => true;
}
