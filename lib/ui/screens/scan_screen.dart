import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/scan_input.dart';

/// Full-screen QR scanner: dark camera view, "Position the QR code within
/// the frame" hint, green corner brackets, and Flash / Gallery buttons.
///
/// Robust by design:
///   * explicit camera-permission flow (request, recover, open settings)
///   * readings must agree before they are trusted — [ScanStabilizer]
///     collapses the per-frame stream into one code
///   * the accepted payload is popped UNTOUCHED — bank detection, BOA QR
///     decryption and Telebirr invoice extraction are owned by the stylepos
///     receipt verifier, which pops its own friendly explanation for any
///     payload it cannot use, so scanning never dead-ends
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _CameraState { checking, granted, denied, permanentlyDenied }

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _controller;
  final ImagePicker _picker = ImagePicker();
  final ScanStabilizer _stabilizer = ScanStabilizer();
  _CameraState _cameraState = _CameraState.checking;
  bool _handled = false;
  bool _torchOn = false;

  // Subtle breathing animation on the brackets.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    setState(() => _cameraState = _CameraState.checking);
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      _startCamera();
    } else if (status.isPermanentlyDenied ||
        status.isRestricted) {
      setState(() => _cameraState = _CameraState.permanentlyDenied);
    } else {
      setState(() => _cameraState = _CameraState.denied);
    }
  }

  void _startCamera() {
    _controller?.dispose();
    _controller = MobileScannerController(
      // Every frame feeds the stabilizer, which needs repeated readings to
      // separate a stable decode from decoder noise — so "normal" speed.
      // No format lock: bank apps print several 2-D symbologies and the
      // sanitizer + detector decide what is a receipt anyway.
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() => _cameraState = _CameraState.granted);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Returns true when the capture was consumed — a stable reading pops the
  /// screen with the raw payload.
  bool _onDetect(BarcodeCapture capture) {
    if (_handled) return true;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      // Only trust the reading once the camera stream stabilizes on it.
      final stable = _stabilizer.feed(raw);
      if (stable == null) continue;
      _tryAccept(stable);
      return _handled;
    }
    return _handled;
  }

  /// Pops with the untouched payload — the receipt verifier decides what it
  /// is (receipt link, BOA slip QR, Telebirr blob, plain reference).
  void _tryAccept(String payload) {
    _handled = true;
    HapticFeedback.heavyImpact();
    if (mounted) Navigator.of(context).pop(payload.trim());
  }

  Future<void> _pickFromGallery() async {
    if (_handled) return;
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final controller = _controller;
      if (controller == null) return;
      final capture = await controller.analyzeImage(image.path);
      if (!mounted) return;
      // Gallery images decode exactly once — accept directly, no need for
      // the camera stream's stability rule.
      if (capture != null) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw == null || raw.trim().isEmpty) continue;
          _tryAccept(raw);
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No receipt QR code found in that image.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not read that image.'),
          ),
        );
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller?.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Torch not available yet (camera still starting) — ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCamera()),

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
                  const SizedBox(height: 5),
                  Text(
                    'Use the QR printed on a payment receipt — '
                    'not a pay or receive-money QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_cameraState == _CameraState.granted)
            // Viewfinder.
            const _ViewfinderOverlay(pulse: true),

          // Bottom action buttons: Flash + Gallery.
          if (_cameraState == _CameraState.granted)
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
                    onTap: _toggleTorch,
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

  Widget _buildCamera() {
    switch (_cameraState) {
      case _CameraState.checking:
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF34D27B)),
        );
      case _CameraState.granted:
        return MobileScanner(
          controller: _controller!,
          onDetect: _onDetect,
          errorBuilder: (context, error) {
            return _ScanErrorView(
              message: 'The camera could not start (${error.errorCode.name}). '
                  'Close this screen and try again.',
              actionLabel: 'Retry',
              onAction: _startCamera,
            );
          },
        );
      case _CameraState.denied:
        return _ScanErrorView(
          message: 'Camera permission is needed to scan receipt QR codes.',
          actionLabel: 'Grant permission',
          onAction: _ensurePermission,
        );
      case _CameraState.permanentlyDenied:
        return _ScanErrorView(
          message: 'Camera access is turned off for Mahtem. Enable it in '
              'system settings, or paste the receipt link instead.',
          actionLabel: 'Open settings',
          onAction: openAppSettings,
        );
    }
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
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ScanErrorView({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF34D27B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
