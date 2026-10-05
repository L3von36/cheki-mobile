import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/reference_patterns.dart';
import '../../core/scan_input.dart';
import '../../state/locale_controller.dart';
import 'reference_scan_screen.dart';

/// Full-screen QR scanner: dark camera view, "Position the QR code within
/// the frame" hint, green corner brackets, and Flash / Gallery /
/// Scan-number buttons.
///
/// Camera-only by design: every path here is optical (live QR decode,
/// gallery decode, or the OCR number scanner). Typing a reference lives
/// on the Verify tab and inside the number scanner, so this screen never
/// reaches for the keyboard.
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
  TextRecognizer? _recognizer;
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
    _recognizer?.close();
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
      // OCR fallback: most receipt screenshots (Telebirr / M-Pesa
      // transaction detail screens, forwarded SMS) carry no QR at all —
      // only the printed number. Same extraction the number scanner uses,
      // accepting only what the rank / shape rule trusts.
      final recognizer =
          _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      if (!mounted) return;
      final found = <ReferenceCandidate>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          found.addAll(extractReferenceCandidates(line.text));
        }
      }
      if (found.isEmpty && result.text.trim().isNotEmpty) {
        // OCR sometimes splits a number across lines.
        found.addAll(
          extractReferenceCandidates(result.text.replaceAll('\n', ' ')),
        );
      }
      final pick = bestGalleryCandidate(found);
      if (pick != null) {
        _tryAccept(pick.value);
        return;
      }
      if (!mounted) return;
      final s = context.read<LocaleController>().strings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(s.scanNoReceiptFound),
        ),
      );
    } catch (_) {
      if (mounted) {
        final s = context.read<LocaleController>().strings;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(s.scanImageUnreadable),
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

  /// Opens the OCR scanner that reads the transaction / reference number
  /// printed on the receipt. The QR camera is paused while the OCR screen
  /// owns the device camera; when the user comes back without a number
  /// the QR camera resumes, and when a number was captured it flows
  /// through the exact same pipeline as a QR payload.
  Future<void> _openReferenceScan() async {
    if (_handled) return;
    try {
      await _controller?.stop();
    } catch (_) {
      // Camera already stopping — the OCR screen manages its own device.
    }
    if (!mounted) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ReferenceScanScreen()),
    );
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      // Back without a number — bring the QR camera back up.
      try {
        await _controller?.start();
      } catch (_) {
        // Restart failures are surfaced by the error builder on the next
        // frame; nothing else to do here.
      }
      return;
    }
    if (!mounted) return;
    _tryAccept(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleController>().strings;
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
                        Expanded(
                          child: Text(
                            s.scanTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
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
                    s.scanPositionHint,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    s.scanUsageHint,
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

          // Bottom action buttons — all optical, no keyboard.
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 26,
            child: _cameraState == _CameraState.granted
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundAction(
                        icon: _torchOn
                            ? Icons.flashlight_on_rounded
                            : Icons.flashlight_off_rounded,
                        label: s.scanFlash,
                        onTap: _toggleTorch,
                      ),
                      _RoundAction(
                        icon: Icons.photo_outlined,
                        label: s.scanGallery,
                        onTap: _pickFromGallery,
                      ),
                      _RoundAction(
                        icon: Icons.document_scanner_rounded,
                        label: s.scanNumberAction,
                        onTap: _openReferenceScan,
                      ),
                    ],
                  )
                // Camera unavailable/denied: the error view above carries
                // retry / settings — this screen stays camera-only.
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    final s = context.watch<LocaleController>().strings;
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
              message: s.scanCameraError(error.errorCode.name),
              actionLabel: s.scanRetry,
              onAction: _startCamera,
            );
          },
        );
      case _CameraState.denied:
        return _ScanErrorView(
          message: s.scanCameraPermissionNeeded,
          actionLabel: s.scanGrantPermission,
          onAction: _ensurePermission,
        );
      case _CameraState.permanentlyDenied:
        return _ScanErrorView(
          message: s.scanCameraOff,
          actionLabel: s.scanOpenSettings,
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
    final s = context.watch<LocaleController>().strings;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded,
                color: Colors.white70, size: 42),
            const SizedBox(height: 14),
            Text(
              s.scanCameraUnavailable,
              style: const TextStyle(
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
