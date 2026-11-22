import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../services/keystone_qr_encoder.dart';

enum KeystonePcztQrStagePhase { preparing, ready, working, failed }

const _scanOptimizedQrInk = Color(0xFF000000);
// Keep every Keystone signing screen on the same camera-friendly cadence.
// Screens select their layout, but cannot override the animation timing.
const keystoneQrFrameInterval = Duration(milliseconds: 200);

/// One playback clock can drive a request's normal and enlarged QR surfaces.
class KeystoneQrPlaybackController extends ValueNotifier<int> {
  KeystoneQrPlaybackController(List<String> parts) : super(0) {
    updateParts(parts);
  }

  List<String> _parts = const [];
  Timer? _timer;

  void updateParts(List<String> parts) {
    if (listEquals(parts, _parts)) return;
    _parts = List.unmodifiable(parts);
    _timer?.cancel();
    value = 0;
    if (_parts.length > 1) {
      _timer = Timer.periodic(keystoneQrFrameInterval, (_) {
        value = (value + 1) % _parts.length;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class KeystonePcztQrStage extends StatelessWidget {
  const KeystonePcztQrStage({
    required this.phase,
    required this.urParts,
    required this.error,
    this.size = 230,
    this.scanOptimized = true,
    this.wholePixelModules = false,
    this.quietZone,
    this.playback,
    super.key,
  });

  final KeystonePcztQrStagePhase phase;
  final List<String> urParts;
  final String? error;
  final double size;
  final bool scanOptimized;
  final bool wholePixelModules;
  final PrettyQrQuietZone? quietZone;
  final KeystoneQrPlaybackController? playback;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: size,
      height: size,
      child: switch (phase) {
        KeystonePcztQrStagePhase.ready => _AnimatedKeystoneQr(
          urParts: urParts,
          size: size,
          scanOptimized: scanOptimized,
          wholePixelModules: wholePixelModules,
          quietZone: quietZone,
          playback: playback,
        ),
        KeystonePcztQrStagePhase.failed => Center(
          child: Text(
            error ?? context.l10n.commonKeystoneSigningCouldNotBePrepared,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.destructive,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        KeystonePcztQrStagePhase.working ||
        KeystonePcztQrStagePhase.preparing => const _QrStageLoader(),
      },
    );
  }
}

class _QrStageLoader extends StatelessWidget {
  const _QrStageLoader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppIcon(
        AppIcons.loader,
        size: 24,
        color: context.colors.icon.regular,
        semanticLabel: context.l10n.keystonePreparingQr,
      ),
    );
  }
}

class _AnimatedKeystoneQr extends StatefulWidget {
  const _AnimatedKeystoneQr({
    required this.urParts,
    required this.size,
    required this.scanOptimized,
    required this.wholePixelModules,
    required this.quietZone,
    required this.playback,
  });

  final List<String> urParts;
  final double size;
  final bool scanOptimized;
  final bool wholePixelModules;
  final PrettyQrQuietZone? quietZone;
  final KeystoneQrPlaybackController? playback;

  @override
  State<_AnimatedKeystoneQr> createState() => _AnimatedKeystoneQrState();
}

class _AnimatedKeystoneQrState extends State<_AnimatedKeystoneQr> {
  int _index = 0;
  Timer? _timer;
  final Map<int, QrImage> _frames = {};

  @override
  void initState() {
    super.initState();
    widget.playback?.addListener(_onPlayback);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _AnimatedKeystoneQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback?.removeListener(_onPlayback);
      widget.playback?.addListener(_onPlayback);
      _startTimer();
    }
    if (oldWidget.urParts != widget.urParts ||
        oldWidget.scanOptimized != widget.scanOptimized ||
        oldWidget.quietZone != widget.quietZone) {
      _index = 0;
      _frames.clear();
      _startTimer();
    }
  }

  QrImage _frameAt(int index) {
    return _frames[index] ??= widget.scanOptimized
        ? encodeKeystoneQrImage(widget.urParts[index])
        : QrImage(
            QrCode.fromData(
              data: widget.urParts[index],
              errorCorrectLevel: QrErrorCorrectLevel.L,
            ),
          );
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.playback != null) return;
    if (widget.urParts.length <= 1) return;
    _timer = Timer.periodic(keystoneQrFrameInterval, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.urParts.length;
      });
    });
  }

  @override
  void dispose() {
    widget.playback?.removeListener(_onPlayback);
    _timer?.cancel();
    super.dispose();
  }

  void _onPlayback() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urParts.isEmpty) return const SizedBox.shrink();
    // Hardware-wallet PCZT QR is scan-first: use high-contrast square modules
    // on the QR surface with an explicit quiet zone. The decorative Figma
    // treatment is retained only for explicit non-scanning previews.
    // Figma (render-measured from 4654:62168 / 4654:63922): the decorative QR
    // ink is drawn directly on the modal panel in both themes, using the
    // accent icon token with bullseye finder eyes painted over the symbol's
    // own eye pattern; the eye knockout matches the panel color.
    final colors = context.colors;
    final moduleColor = colors.icon.accent;
    final frame = _frameAt(
      (widget.playback?.value ?? _index) % widget.urParts.length,
    );
    if (widget.wholePixelModules) {
      return ColoredBox(
        color: colors.surface.qrCode,
        child: CustomPaint(
          painter: _WholePixelQrPainter(
            frame,
            MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      );
    }
    if (widget.scanOptimized) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: ColoredBox(
          color: colors.surface.qrCode,
          child: PrettyQrView(
            qrImage: frame,
            decoration: PrettyQrDecoration(
              quietZone: widget.quietZone ?? const PrettyQrQuietZone.modules(3),
              shape: const PrettyQrSquaresSymbol(color: _scanOptimizedQrInk),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PrettyQrView(
            qrImage: frame,
            decoration: PrettyQrDecoration(
              quietZone: PrettyQrQuietZone.zero,
              shape: PrettyQrSmoothSymbol(color: moduleColor),
            ),
          ),
          CustomPaint(
            painter: _BullseyeFinderEyesPainter(
              moduleCount: frame.moduleCount,
              moduleColor: moduleColor,
              knockoutColor: context.colors.background.base,
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps camera-facing module edges sharp at the display's physical resolution.
class _WholePixelQrPainter extends CustomPainter {
  const _WholePixelQrPainter(this.frame, this.pixelRatio);

  final QrImage frame;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    const quietZone = 4;
    final count = frame.moduleCount;
    final pitch = (size.shortestSide * pixelRatio / (count + 2 * quietZone))
        .floor();
    if (pitch < 1) return;
    final left = ((size.width * pixelRatio - count * pitch) / 2).floor();
    final top = ((size.height * pixelRatio - count * pitch) / 2).floor();
    final ink = Paint()
      ..color = _scanOptimizedQrInk
      ..isAntiAlias = false;
    canvas.save();
    canvas.scale(1 / pixelRatio);
    for (var row = 0; row < count; row++) {
      final y = (top + row * pitch).toDouble();
      for (var column = 0; column < count; column++) {
        if (frame.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTWH(
              (left + column * pitch).toDouble(),
              y,
              pitch.toDouble(),
              pitch.toDouble(),
            ),
            ink,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WholePixelQrPainter old) =>
      frame != old.frame || pixelRatio != old.pixelRatio;
}

/// Replaces the smooth symbol's square finder patterns with the Figma
/// bullseye eyes: a one-module-thick ring (outer Ø 7 modules) around a
/// three-module center disc.
class _BullseyeFinderEyesPainter extends CustomPainter {
  const _BullseyeFinderEyesPainter({
    required this.moduleCount,
    required this.moduleColor,
    required this.knockoutColor,
  });

  final int moduleCount;
  final Color moduleColor;
  final Color knockoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width / moduleCount;
    final knockout = Paint()..color = knockoutColor;
    final ring = Paint()
      ..color = moduleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = m;
    final disc = Paint()..color = moduleColor;

    for (final origin in [
      Offset.zero,
      Offset((moduleCount - 7) * m, 0),
      Offset(0, (moduleCount - 7) * m),
    ]) {
      // Cover the symbol's own finder pattern (7×7 modules, slightly
      // inflated so no anti-aliased fringe survives underneath).
      canvas.drawRect(
        Rect.fromLTWH(origin.dx - 0.5, origin.dy - 0.5, 7 * m + 1, 7 * m + 1),
        knockout,
      );
      final center = origin + Offset(3.5 * m, 3.5 * m);
      canvas.drawCircle(center, 3 * m, ring);
      canvas.drawCircle(center, 1.5 * m, disc);
    }
  }

  @override
  bool shouldRepaint(_BullseyeFinderEyesPainter oldDelegate) {
    return moduleCount != oldDelegate.moduleCount ||
        moduleColor != oldDelegate.moduleColor ||
        knockoutColor != oldDelegate.knockoutColor;
  }
}
