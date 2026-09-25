import 'package:flutter/material.dart';

import '../../theme/cheki_theme.dart';
import '../shell.dart';

/// Splash — deep navy screen with the shield logo, tagline and loader,
/// mirroring the design's launch screen. Auto-advances to the shell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ShellScreen()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ChekiPalette.splashGradient,
        )),
        child: Stack(
          children: [
            // Decorative soft circles.
            Positioned(
              top: -80,
              right: -60,
              child: _GlowCircle(size: 260, opacity: 0.05),
            ),
            Positioned(
              bottom: -120,
              left: -80,
              child: _GlowCircle(size: 340, opacity: 0.06),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.28,
              right: 28,
              child: _GlowCircle(size: 90, opacity: 0.05),
            ),
            // Center content.
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 0.7, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _controller,
                          curve: Curves.elasticOut,
                        ),
                      ),
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: Colors.white,
                          size: 58,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Cheki',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Scan  ·  Verify  ·  Be Sure',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Loader.
            Positioned(
              left: 0,
              right: 0,
              bottom: 84,
              child: Column(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final double opacity;

  const _GlowCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
    );
  }
}
