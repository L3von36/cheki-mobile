import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cheki_theme.dart';

/// A one-shot confetti burst fired when a receipt verifies as genuine.
/// Lightweight: a single [CustomPainter] over an [AnimatedBuilder], no
/// packages. Plays for ~2.6s, then removes itself from the tree.
class ConfettiBurst extends StatefulWidget {
  final EdgeInsets position;

  const ConfettiBurst({super.key, this.position = const EdgeInsets.all(0)});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _particles = List.generate(64, (i) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 0.45 + rng.nextDouble() * 0.75;
      return _Particle(
        angle: angle,
        speed: speed,
        color: _colors[i % _colors.length],
        size: 4 + rng.nextDouble() * 5,
        shape: _ParticleShape.values[i % _ParticleShape.values.length],
        spin: (rng.nextDouble() - 0.5) * 12,
        wobble: rng.nextDouble() * math.pi * 2,
        drift: (rng.nextDouble() - 0.5) * 40,
      );
    });
    _controller.forward();
  }

  static const List<Color> _colors = [
    ChekiPalette.green,
    Color(0xFF7BF0A8),
    ChekiPalette.amber,
    ChekiPalette.red,
    Color(0xFF5EC9F8),
    Color(0xFFF8D35E),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.position,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isCompleted) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(
              particles: _particles,
              progress: Curves.easeOut.transform(_controller.value),
            ),
          );
        },
      ),
    );
  }
}

enum _ParticleShape { rect, circle, streamer }

class _Particle {
  final double angle;
  final double speed;
  final Color color;
  final double size;
  final _ParticleShape shape;
  final double spin;
  final double wobble;
  final double drift;

  _Particle({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.shape,
    required this.spin,
    required this.wobble,
    required this.drift,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.18);
    final maxDist = size.height * 0.62;

    for (final p in particles) {
      // Explode outward, then gravity takes over.
      final t = progress;
      final ease = 1 - math.pow(1 - t, 3).toDouble();
      final dist = p.speed * maxDist * ease;
      final gravity = 190 * t * t;
      final wobbleX = math.sin(t * math.pi * 3 + p.wobble) * 9;

      final dx = math.cos(p.angle) * dist + p.drift * t + wobbleX;
      final dy = math.sin(p.angle) * dist * 0.7 + gravity;

      final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      final paint = Paint()..color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * t + p.wobble);

      switch (p.shape) {
        case _ParticleShape.rect:
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.55,
            ),
            paint,
          );
        case _ParticleShape.circle:
          canvas.drawCircle(Offset.zero, p.size * 0.42, paint);
        case _ParticleShape.streamer:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: p.size * 1.5,
                height: p.size * 0.34,
              ),
              const Radius.circular(2),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
