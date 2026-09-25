import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';

/// Full-screen QR scanner styled per the design: dark camera view,
/// "Position the QR code within the frame" hint, green corner brackets,
/// and Flash / Gallery round buttons.
///
/// Recognizes bank receipt QR codes / links and pops with a parsed
/// [BankDetection] (bank + reference + optional account suffix).
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  final ImagePicker _picker = ImagePicker();
  bool _handled = false;
  bool _torchOn = false;

  // Subtle breathing animation on the brackets.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      final detection = detectReceipt(raw);
      if (detection == null) continue;
      _handled = true;
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.of(context).pop(detection);
      return;
    }
  }

  Future<void> _pickFromGallery() async {
    if (_handled) return;
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      _handled = true;
      final capture = await _controller.analyzeImage(image.path);
      if (!mounted) return;
      if (capture != null) {
        _onDetect(capture);
        if (_handled) return;
      }
      _handled = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No receipt QR code found in that image.'),
        ),
      );
    } catch (_) {
      _handled = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that image.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return _ScanErrorView(message: error.errorCode.name);
            },
          )),

          // Top bar + hint.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 22),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Scan Payment',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Position the QR code within the frame',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Viewfinder.
          const _ViewfinderOverlay(pulse: true),

          // Bottom action buttons: Flash + Gallery.
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundAction(
                  icon: _torchOn
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  label: 'Flash',
                  onTap: () async {
                    await _controller.toggleTorch();
                    if (mounted) setState(() => _torchOn = !_torchOn);
                  },
                ),
                _RoundAction(
                  icon: Icons.photo_outlined,
                  label: 'Gallery',
                  onTap: _pickFromGallery,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Corner-bracket viewfinder with dimmed surroundings.
class _ViewfinderOverlay extends StatelessWidget {
  final bool pulse;

  const _ViewfinderOverlay({this.pulse = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const size = 250.0;
          final top = constraints.maxHeight * 0.26;
          final left = (constraints.maxWidth - size) / 2;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _DimPainter(
                    window: Rect.fromLTWH(left, top, size, size),
                    radius: 22,
                  ),
                ),
              ),
              if (pulse)
                Positioned(
                  left: left,
                  top: top,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: _PulsingBrackets(),
                  ),
                )
              else
                Positioned(
                  left: left,
                  top: top,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(painter: _BracketPainter()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Breathing opacity + a soft scan line sweeping the window.
class _PulsingBrackets extends StatefulWidget {
  @override
  State<_PulsingBrackets> createState() => _PulsingBracketsState();
}

class _PulsingBracketsState extends State<_PulsingBrackets>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return CustomPaint(
          painter: _BracketPainter(
            opacity: 0.75 + 0.25 * (1 - (2 * t - 1).abs()),
            lineY: t,
          ),
        );
      },
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect window;
  final double radius;
  _DimPainter({required this.window, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(window, Radius.circular(radius)),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_DimPainter oldDelegate) => oldDelegate.window != window;
}

class _BracketPainter extends CustomPainter {
  final double opacity;
  final double? lineY;

  _BracketPainter({this.opacity = 1.0, this.lineY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF34D27B).withValues(alpha: opacity)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 38.0;
    const r = 22.0;

    void corner(Path path) => canvas.drawPath(path, paint);

    // Top-left
    corner(Path()
      ..moveTo(0, len)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(len, 0));
    // Top-right
    corner(Path()
      ..moveTo(size.width - len, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, len));
    // Bottom-left
    corner(Path()
      ..moveTo(0, size.height - len)
      ..lineTo(0, size.height - r)
      ..quadraticBezierTo(0, size.height, r, size.height)
      ..lineTo(len, size.height));
    // Bottom-right
    corner(Path()
      ..moveTo(size.width - len, size.height)
      ..lineTo(size.width - r, size.height)
      ..quadraticBezierTo(size.width, size.height, size.width, size.height - r)
      ..lineTo(size.width, size.height - len));

    // Sweeping scan line.
    final y = lineY;
    if (y != null) {
      final linePaint = Paint()
        ..color = const Color(0xFF34D27B).withValues(alpha: 0.35 * opacity)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final ly = 14 + (size.height - 28) * y;
      canvas.drawLine(Offset(14, ly), Offset(size.width - 14, ly), linePaint);
    }
  }

  @override
  bool shouldRepaint(_BracketPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.lineY != lineY;
}

class _ScanErrorView extends StatelessWidget {
  final String message;
  const _ScanErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded,
                color: Colors.white70, size: 42),
            const SizedBox(height: 14),
            const Text(
              'Camera unavailable',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant camera permission in system settings, or paste the '
              'receipt link into the verify form instead.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
