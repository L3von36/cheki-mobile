import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/reference_patterns.dart';
import '../../core/scan_input.dart';
import '../../state/locale_controller.dart';
import '../widgets/reference_entry_sheet.dart';

/// Full-screen scanner that reads the transaction / reference number
/// printed on a paper receipt — the no-QR path, now with a camera.
///
/// How it works:
///   * ML Kit text recognition runs entirely ON-DEVICE; camera frames
///     never leave the phone (same privacy story as the QR scanner).
///   * ONLY the viewfinder window is read: a recognized line counts
///     only when its center sits inside the frame ([ScanRegionMapper]),
///     so amounts, account numbers and footers elsewhere on the receipt
///     never become candidates — aim the frame at the number and the
///     number alone is judged. Lines inside the frame are handed to
///     [extractReferenceCandidates], which ranks the numbers it finds
///     (labeled > RRN > bare > token) and filters out phone numbers and
///     account fields.
///   * A labeled / RRN-shaped number that survives three consecutive
///     OCR passes is accepted automatically — the same "agree before
///     trusting" rule the QR scanner applies via [ScanStabilizer].
///     Weaker candidates wait for an explicit tap, so a price or account
///     number is never verified by accident.
///   * The screen can always fall back to typing: Gallery OCR and the
///     manual entry sheet are one tap away, and a denied camera never
///     dead-ends verification.
///
/// Pops with the accepted reference string — the caller treats it
/// exactly like a scanned QR payload or a typed value.
class ReferenceScanScreen extends StatefulWidget {
  const ReferenceScanScreen({super.key});

  @override
  State<ReferenceScanScreen> createState() => _ReferenceScanScreenState();
}

enum _CameraState { checking, granted, denied, permanentlyDenied }

class _ReferenceScanScreenState extends State<ReferenceScanScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _cameraDescription;
  TextRecognizer? _recognizer;
  final ImagePicker _picker = ImagePicker();
  _CameraState _cameraState = _CameraState.checking;

  bool _handled = false;
  bool _busy = false;
  bool _torchOn = false;

  List<ReferenceCandidate> _candidates = const [];
  String? _lastTop;
  int _agreements = 0;

  // A labeled/RRN-shaped number must be read this many consecutive OCR
  // passes before it is accepted without a tap.
  static const int _autoAcceptAgreements = 3;

  // Subtle breathing animation on the brackets — same rhythm as the QR
  // scanner so both screens feel like one product.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensurePermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _shutDownCamera();
    unawaited(_recognizer?.close());
    _recognizer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera plugin does not pause itself — free the device when the
    // app goes to the background and rebuild on the way back.
    if (state == AppLifecycleState.inactive) {
      _shutDownCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraState == _CameraState.granted && !_handled) {
        _startCamera();
      }
    }
  }

  Future<void> _ensurePermission() async {
    setState(() => _cameraState = _CameraState.checking);
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      await _startCamera();
    } else if (status.isPermanentlyDenied || status.isRestricted) {
      setState(() => _cameraState = _CameraState.permanentlyDenied);
    } else {
      setState(() => _cameraState = _CameraState.denied);
    }
  }

  Future<void> _startCamera() async {
    // A restart (lifecycle resume, retry) must not leak the old device.
    _shutDownCamera();
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _cameraState = _CameraState.denied);
        return;
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraDescription = description;
      final controller = CameraController(
        description,
        // 720p class: enough detail for a printed number line, cheap
        // enough that OCR keeps up with the stream on modest phones.
        ResolutionPreset.high,
        imageFormatGroup: ImageFormatGroup.nv21,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      setState(() => _cameraState = _CameraState.granted);
      unawaited(controller.startImageStream(_onFrame));
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraState = _CameraState.denied);
    }
  }

  void _shutDownCamera() {
    final controller = _controller;
    _controller = null;
    _busy = false;
    if (controller == null) return;
    unawaited(() async {
      try {
        await controller.stopImageStream();
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }());
  }

  /// Feeds one camera frame to the on-device recognizer. Frames that
  /// arrive while the previous one is still processing are dropped —
  /// OCR never queues up behind itself.
  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _handled || !mounted) return;
    // NV21 is the negotiated stream format on Android; anything else is
    // skipped rather than mis-decoded.
    if (image.format.group != ImageFormatGroup.nv21) return;
    final recognizer = _recognizer;
    if (recognizer == null) return;

    _busy = true;
    try {
      final plane = image.planes.first;
      final sensorOrientation = _cameraDescription?.sensorOrientation ?? 0;
      final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation ?? InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      // Ties the painted viewfinder to the pixels this frame's OCR
      // reports: rebuilt per frame from the live screen size and the
      // rotation-corrected dimensions of THIS frame.
      final mapper = ScanRegionMapper(
        screenSize: MediaQuery.of(context).size,
        uprightImageSize: uprightImageSize(
          frameWidth: image.width,
          frameHeight: image.height,
          sensorOrientation: sensorOrientation,
        ),
      );
      final result = await recognizer.processImage(inputImage);
      if (!mounted || _handled) return;
      _updateCandidates(result, mapper);
    } catch (_) {
      // One bad frame (camera warming up, device rotated mid-capture)
      // must never kill the scanner.
    } finally {
      _busy = false;
    }
  }

  void _updateCandidates(RecognizedText result, ScanRegionMapper mapper) {
    final viewfinder = numberScanViewfinderRect(mapper.screenSize);
    final found = <ReferenceCandidate>[];
    final linesInFrame = <String>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        // Viewfinder-only reading: a line whose center sits outside the
        // window is ignored even though OCR saw it — the window is what
        // the user aimed at.
        if (box == null || !mapper.containsCenterOf(viewfinder, box)) {
          continue;
        }
        linesInFrame.add(line.text);
        found.addAll(extractReferenceCandidates(line.text));
      }
    }
    if (found.isEmpty && linesInFrame.isNotEmpty) {
      // OCR sometimes splits a number across lines — re-scan the text
      // that actually came from inside the frame, joined.
      found.addAll(
        extractReferenceCandidates(linesInFrame.join(' ')),
      );
    }
    final ranked = _rankedWithVariants(found);

    final top = ranked.isEmpty ? null : ranked.first.value.toUpperCase();
    if (top != null && top == _lastTop) {
      _agreements++;
    } else {
      _agreements = 1;
      _lastTop = top;
    }

    setState(() => _candidates = ranked);

    if (top != null &&
        _agreements >= _autoAcceptAgreements &&
        ranked.first.rank <= autoAcceptMaxRank) {
      _accept(ranked.first.value);
    }
  }

  /// Ranks the raw OCR candidates and appends re-readings of the best
  /// candidate with confusable characters swapped (O↔0, I↔1, B↔8…). The
  /// camera misreads those regularly, and the bank's "not found" would
  /// otherwise send the user away even though the receipt is genuine.
  /// Variants land at rank 5 — visible as chips, never auto-accepted; the
  /// exact OCR read stays first and keeps the auto-accept path.
  List<ReferenceCandidate> _rankedWithVariants(List<ReferenceCandidate> found) {
    final ranked = dedupeAndRank(found);
    final top = ranked.isEmpty ? null : ranked.first;
    if (top == null || top.rank > autoAcceptMaxRank) return ranked;
    final present = ranked.map((c) => c.value.toUpperCase()).toSet();
    final variants = <ReferenceCandidate>[];
    for (final v in ambiguityVariants(top.value)) {
      if (present.contains(v)) continue;
      variants.add(ReferenceCandidate(v, 5));
      if (ranked.length + variants.length >= 7) break;
    }
    return [...ranked, ...variants];
  }

  void _accept(String value) {
    if (_handled) return;
    final text = value.trim();
    if (text.isEmpty) return;
    _handled = true;
    HapticFeedback.heavyImpact();
    if (mounted) Navigator.of(context).pop(text);
  }

  Future<void> _toggleTorch() async {
    try {
      final on = !_torchOn;
      await _controller?.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = on);
    } catch (_) {
      // Torch not available yet (camera still starting) — ignore.
    }
  }

  /// OCRs a picked gallery image — receipts are so often screenshotted
  /// or forwarded as photos that this path deserves first-class space.
  Future<void> _pickFromGallery() async {
    if (_handled) return;
    final s = context.read<LocaleController>().strings;
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final recognizer =
          _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      if (!mounted || _handled) return;
      // Gallery images have no viewfinder — the whole picture is the
      // region the user chose, so every line is a candidate.
      final found = <ReferenceCandidate>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          found.addAll(extractReferenceCandidates(line.text));
        }
      }
      if (found.isEmpty && result.text.trim().isNotEmpty) {
        found.addAll(
          extractReferenceCandidates(result.text.replaceAll('\n', ' ')),
        );
      }
      final ranked = _rankedWithVariants(found);
      if (ranked.isNotEmpty) {
        _accept(ranked.first.value);
        return;
      }
      _showToast(s.refScanNoNumberFound);
    } catch (_) {
      if (mounted) _showToast(s.scanImageUnreadable);
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ),
    );
  }

  /// Opens the manual entry sheet; a typed value pops this screen exactly
  /// like a scanned one, so a camera that can't read the print never
  /// blocks verification.
  Future<void> _openTyping() async {
    if (_handled) return;
    final value = await showReferenceEntrySheet(context);
    if (value == null || !mounted) return;
    _accept(value);
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
                            s.refScanTitle,
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
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      s.refScanHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_cameraState == _CameraState.granted)
            const _ViewfinderOverlay(pulse: true),

          // Status / detected numbers, just under the viewfinder.
          if (_cameraState == _CameraState.granted)
            Positioned(
              left: 24,
              right: 24,
              top: MediaQuery.of(context).size.height * 0.26 + 150 + 20,
              child: _candidates.isEmpty
                  ? Text(
                      s.refScanLooking,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    )
                  : _CandidateChips(
                      candidates: _candidates,
                      onSelected: _accept,
                    ),
            ),

          // Bottom action buttons — same grammar as the QR screen.
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
                        icon: Icons.keyboard_rounded,
                        label: s.refScanTypeInstead,
                        onTap: _openTyping,
                      ),
                    ],
                  )
                // Camera unavailable/denied: typing and gallery OCR still
                // work — the screen must never dead-end.
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoundAction(
                        icon: Icons.keyboard_rounded,
                        label: s.refScanTypeInstead,
                        onTap: _openTyping,
                      ),
                    ],
                  ),
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
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF34D27B)),
          );
        }
        return CameraPreview(controller);
      case _CameraState.denied:
        return _ErrorView(
          message: s.scanCameraPermissionNeeded,
          actionLabel: s.scanGrantPermission,
          onAction: _ensurePermission,
        );
      case _CameraState.permanentlyDenied:
        return _ErrorView(
          message: s.scanCameraOff,
          actionLabel: s.scanOpenSettings,
          onAction: openAppSettings,
        );
    }
  }
}

/// Chips listing the numbers found in the frame — tap one to verify it.
class _CandidateChips extends StatelessWidget {
  final List<ReferenceCandidate> candidates;
  final ValueChanged<String> onSelected;

  const _CandidateChips({
    required this.candidates,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleController>().strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.refScanFoundTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final candidate in candidates.take(5))
              GestureDetector(
                onTap: () => onSelected(candidate.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: candidate.rank <= autoAcceptMaxRank
                          ? const Color(0xFF34D27B)
                          : Colors.white24,
                      width: candidate.rank <= autoAcceptMaxRank ? 1.6 : 1,
                    ),
                  ),
                  child: Text(
                    candidate.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
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

/// Wide rounded-rect viewfinder (a number line, not a square) with dimmed
/// surroundings, breathing corner brackets and a sweeping scan line.
///
/// The rectangle comes from [numberScanViewfinderRect] — the same source
/// the OCR region filter uses, so paint and reading agree by design.
class _ViewfinderOverlay extends StatelessWidget {
  final bool pulse;

  const _ViewfinderOverlay({this.pulse = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final window = numberScanViewfinderRect(
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _DimPainter(
                    window: window,
                    radius: 20,
                  ),
                ),
              ),
              Positioned(
                left: window.left,
                top: window.top,
                child: SizedBox(
                  width: window.width,
                  height: window.height,
                  child: pulse
                      ? _PulsingBrackets()
                      : CustomPaint(painter: _BracketPainter()),
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
    const len = 34.0;
    const r = 20.0;

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

class _ErrorView extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ErrorView({
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
