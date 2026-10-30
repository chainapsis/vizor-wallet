// Deterministic visual fixture; never imported by the production entry point.
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../src/features/home/widgets/mobile/shield/mobile_shield_backdrop.dart';
import '../src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import '../src/features/home/widgets/mobile/shield/keystone_shield_morph.dart';
import '../src/features/home/widgets/mobile/shield/keystone_shield_footer.dart';
import '../src/features/home/widgets/mobile/shield/keystone_shield_scanner_surface.dart';

const keystoneShieldPreviewParts = [
  'ur:zcash-pczt/oyadhdcxlkahssqzwfvslofzoxwkrewngotktbmwjkwdcmnefsaaehrlolkskncnktlbaypkvoonhknt',
  'ur:zcash-pczt/oyadhdcxlkahssqzwfvslofzoxwkrewngotktbmwjkwdcmnefsaaehrlolkskncnktlbaypkvoonhkaa',
];

enum _Stage { review, preparing, qr, scanner, broadcasting, succeeded }

class KeystoneShieldMotionPreview extends StatefulWidget {
  const KeystoneShieldMotionPreview({
    this.backdrop,
    this.onSubmitted,
    this.onClose,
    super.key,
  });
  final MobileShieldBackdrop? backdrop;
  final VoidCallback? onSubmitted;
  final VoidCallback? onClose;
  @override
  State<KeystoneShieldMotionPreview> createState() =>
      _KeystoneShieldMotionPreviewState();
}

class _KeystoneShieldMotionPreviewState
    extends State<KeystoneShieldMotionPreview> {
  _Stage _stage = _Stage.review;
  Timer? _timer;
  var _qrReady = false;
  var _progress = 0;
  var _decoding = false;

  void _after(Duration duration, VoidCallback callback) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      if (mounted) callback();
    });
  }

  void _start() {
    setState(() => _stage = _Stage.preparing);
    _after(
      const Duration(seconds: 2),
      () => setState(() => _stage = _Stage.qr),
    );
  }

  void _scan() {
    setState(() {
      _stage = _Stage.scanner;
      _progress = 0;
      _decoding = false;
    });
    _after(const Duration(seconds: 4), () {
      setState(() => _progress = 48);
      _after(const Duration(seconds: 3), () {
        setState(() {
          _progress = 100;
          _decoding = true;
        });
        _after(const Duration(seconds: 1), () {
          setState(() => _stage = _Stage.broadcasting);
          _after(const Duration(seconds: 3), () {
            widget.onSubmitted?.call();
            setState(() => _stage = _Stage.succeeded);
          });
        });
      });
    });
  }

  void _showQr() {
    _timer?.cancel();
    setState(() {
      _stage = _Stage.qr;
      _decoding = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hardware = _stage == _Stage.qr || _stage == _Stage.scanner;
    final scanner = _stage == _Stage.scanner;
    return MobileShieldScene(
      backdrop: widget.backdrop,
      phase: _stage == _Stage.review
          ? MobileShieldPhase.review
          : _stage == _Stage.succeeded
          ? MobileShieldPhase.succeeded
          : hardware
          ? MobileShieldPhase.hardware
          : MobileShieldPhase.working,
      amount: '14.12',
      resultAmount: '14.1199',
      title: _stage == _Stage.review
          ? 'Transparent Balance'
          : _stage == _Stage.succeeded
          ? 'Shielded successfully'
          : scanner
          ? 'Scan your Keystone signature'
          : _stage == _Stage.qr
          ? 'Approve with Keystone'
          : 'Shielding your balance…',
      onCommit: _start,
      onClose: widget.onClose,
      onComplete: widget.onClose,
      canLeave: _stage != _Stage.broadcasting,
      keystoneFocus: KeystoneShieldFocus(
        stage: _stage == _Stage.qr
            ? KeystoneShieldFocusStage.qr
            : scanner
            ? KeystoneShieldFocusStage.scanner
            : KeystoneShieldFocusStage.cloud,
        urParts: keystoneShieldPreviewParts,
        onQrReadyChanged: (ready) {
          if (mounted && _qrReady != ready) setState(() => _qrReady = ready);
        },
        scannerBuilder: (constraints, morph) => KeystoneShieldScannerSurface(
          constraints: constraints,
          morph: morph,
          progress: _progress,
          decoding: _decoding,
          cameraBuilder: (_) => const ColoredBox(color: Color(0xFF000000)),
          onToggleTorch: () {},
        ),
      ),
      footer: hardware
          ? KeystoneShieldFooter(
              showQr: !scanner,
              onCancel: widget.onClose,
              onNext: _qrReady ? _scan : null,
              onShowQr: _decoding ? null : _showQr,
            )
          : null,
    );
  }
}
