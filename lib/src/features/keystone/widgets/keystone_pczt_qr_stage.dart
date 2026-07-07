import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../../l10n/app_localizations.dart';

enum KeystonePcztQrStagePhase { preparing, ready, working, failed }

const _scanOptimizedQrInk = Color(0xFF000000);

class KeystonePcztQrStage extends StatelessWidget {
  const KeystonePcztQrStage({
    required this.phase,
    required this.urParts,
    required this.error,
    this.size = 230,
    this.scanOptimized = true,
    this.quietZone,
    this.frameInterval = const Duration(milliseconds: 100),
    super.key,
  });

  final KeystonePcztQrStagePhase phase;
  final List<String> urParts;
  final String? error;
  final double size;
  final bool scanOptimized;
  final PrettyQrQuietZone? quietZone;
  final Duration frameInterval;

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
          quietZone: quietZone,
          frameInterval: frameInterval,
        ),
        KeystonePcztQrStagePhase.failed => Center(
          child: Text(
            error ?? AppLocalizations.of(context).keystoneSignPrepareError,
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
        semanticLabel: AppLocalizations.of(context).keystonePreparingQr,
      ),
    );
  }
}

class _AnimatedKeystoneQr extends StatefulWidget {
  const _AnimatedKeystoneQr({
    required this.urParts,
    required this.size,
    required this.scanOptimized,
    required this.quietZone,
    required this.frameInterval,
  });

  final List<String> urParts;
  final double size;
  final bool scanOptimized;
  final PrettyQrQuietZone? quietZone;
  final Duration frameInterval;

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
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _AnimatedKeystoneQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urParts != widget.urParts ||
        oldWidget.scanOptimized != widget.scanOptimized ||
        oldWidget.quietZone != widget.quietZone ||
        oldWidget.frameInterval != widget.frameInterval) {
      _index = 0;
      _frames.clear();
      _startTimer();
    }
  }

  QrImage _frameAt(int index) {
    return _frames[index] ??= QrImage(
      QrCode.fromData(
        data: widget.urParts[index],
        errorCorrectLevel: widget.scanOptimized
            ? QrErrorCorrectLevel.M
            : QrErrorCorrectLevel.L,
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.urParts.length <= 1) return;
    _timer = Timer.periodic(widget.frameInterval, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.urParts.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    final frame = _frameAt(_index);
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
