/// GitHub sign-in via the OAuth 2.0 Device Flow (v1.19.0).
///
/// The app requests a device code, opens BetterAuth's verification page in
/// the system browser, and polls until the user approves there. No deep
/// links, no in-app cookie dance: the poll hands the app its own bearer
/// session token directly (RFC 8628), which the server-side bridge accepts
/// on every /v1 route.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/cloud/cloud_api.dart';
import '../../../state/auth_controller.dart';
import '../../../state/locale_controller.dart';
import '../../../theme/mahtem_theme.dart';
import '../../widgets/pressable.dart';

/// Runs the GitHub device flow and completes the sign-in. Resolves with
/// the auth outcome (the CALLER handles post-sign-in work — trial sync,
/// navigation — exactly like a password sign-in).
Future<AuthResult?> showGitHubSignIn(BuildContext context) async {
  final result = await showModalBottomSheet<AuthResult>(
    context: context,
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GitHubSignInSheet(),
  );
  return result;
}

class _GitHubSignInSheet extends StatefulWidget {
  const _GitHubSignInSheet();

  @override
  State<_GitHubSignInSheet> createState() => _GitHubSignInSheetState();
}

enum _Stage { starting, waiting, expired, denied, notEnabled, failed }

class _GitHubSignInSheetState extends State<_GitHubSignInSheet> {
  _Stage _stage = _Stage.starting;
  String? _userCode;
  Timer? _pollTimer;
  Duration _interval = const Duration(seconds: 5);
  DateTime _deadline = DateTime.now().add(const Duration(minutes: 15));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final api = CloudApi();
    final enabled = await api.githubSignInEnabled();
    if (!enabled) {
      if (mounted) setState(() => _stage = _Stage.notEnabled);
      return;
    }
    try {
      final code = await api.betterAuthDeviceCode();
      _interval = Duration(seconds: code.intervalSeconds);
      _deadline = DateTime.now().add(Duration(seconds: code.expiresInSeconds));
      if (!mounted) return;
      setState(() {
        _userCode = code.userCode;
        _stage = _Stage.waiting;
      });
      final uri = Uri.tryParse(
        code.verificationUriComplete ?? code.verificationUri,
      );
      if (uri != null) {
        // Best-effort: the code is always visible on the sheet, so a
        // blocked browser launch is recoverable by hand.
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      }
      _schedulePoll();
    } on CloudApiException {
      if (!mounted) return;
      setState(() => _stage = _Stage.failed);
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(_interval, _pollOnce);
  }

  Future<void> _pollOnce() async {
    if (!mounted || _stage != _Stage.waiting || _userCode == null) return;
    if (DateTime.now().isAfter(_deadline)) {
      setState(() => _stage = _Stage.expired);
      return;
    }
    final auth = context.read<AuthController>();
    try {
      final (outcome, session) =
          await CloudApi().betterAuthDeviceToken(_userCode!);
      switch (outcome) {
        case BetterAuthPollOutcome.pending:
          _schedulePoll();
        case BetterAuthPollOutcome.slowDown:
          _interval *= 2;
          _schedulePoll();
        case BetterAuthPollOutcome.expired:
          if (mounted) setState(() => _stage = _Stage.expired);
        case BetterAuthPollOutcome.denied:
          if (mounted) setState(() => _stage = _Stage.denied);
        case BetterAuthPollOutcome.success:
          if (session == null) {
            if (mounted) setState(() => _stage = _Stage.failed);
            return;
          }
          final result = await auth.completeGitHubSignIn(session);
          if (mounted) {
            Navigator.of(context).pop(result);
          }
      }
    } on CloudApiException {
      // Transport blip mid-poll — keep waiting; the deadline ends it.
      _schedulePoll();
    } catch (_) {
      _schedulePoll();
    }
  }

  Future<void> _openBrowser() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final code = await CloudApi().betterAuthDeviceCode();
      _interval = Duration(seconds: code.intervalSeconds);
      _deadline = DateTime.now().add(Duration(seconds: code.expiresInSeconds));
      final uri = Uri.tryParse(
        code.verificationUriComplete ?? code.verificationUri,
      );
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The old code keeps polling; a fresh one is only a nicety.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? MahtemPalette.dCard : Colors.white;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final inkDim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;

    final String title;
    final String? body;
    switch (_stage) {
      case _Stage.starting:
      case _Stage.waiting:
        title = strings.githubSheetTitle;
        body = strings.githubSheetBody;
      case _Stage.expired:
        title = strings.githubSheetTitle;
        body = strings.githubExpired;
      case _Stage.denied:
        title = strings.githubSheetTitle;
        body = strings.githubDenied;
      case _Stage.notEnabled:
        title = strings.githubSheetTitle;
        body = strings.githubNotEnabled;
      case _Stage.failed:
        title = strings.githubSheetTitle;
        body = strings.genericAuthError;
    }

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.code_rounded, size: 20, color: MahtemPalette.green),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                color: inkDim,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            if (_stage == _Stage.waiting && _userCode != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: MahtemPalette.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: MahtemPalette.green.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      strings.githubDeviceCodeLabel,
                      style: TextStyle(
                        color: inkDim,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _userCode!,
                      style: const TextStyle(
                        color: MahtemPalette.green,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    strings.githubWaiting,
                    style: TextStyle(color: inkDim, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Pressable(
                onTap: _busy ? null : _openBrowser,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? MahtemPalette.dBorder
                          : MahtemPalette.lBorder,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text(
                          strings.githubOpenBrowser,
                          style: TextStyle(
                            color: ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
            if (_stage == _Stage.expired || _stage == _Stage.failed) ...[
              const SizedBox(height: 16),
              Pressable(
                onTap: () {
                  setState(() => _stage = _Stage.starting);
                  _start();
                },
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: MahtemPalette.buttonGradient),
                    borderRadius: BorderRadius.all(Radius.circular(13)),
                  ),
                  child: Text(
                    strings.retry,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                strings.cancel,
                style: TextStyle(color: inkDim, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
