import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

enum KeystonePcztQrStagePhase { preparing, ready, working, failed }

class KeystonePcztQrStage extends StatelessWidget {
  const KeystonePcztQrStage({
    required this.phase,
    required this.urParts,
    required this.error,
    super.key,
  });

  final KeystonePcztQrStagePhase phase;
  final List<String> urParts;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 230,
      height: 230,
      child: switch (phase) {
        KeystonePcztQrStagePhase.ready => _AnimatedKeystoneQr(urParts: urParts),
        KeystonePcztQrStagePhase.failed => Center(
          child: Text(
            error ?? 'Keystone signing could not be prepared.',
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
        semanticLabel: 'Preparing QR',
      ),
    );
  }
}

class _AnimatedKeystoneQr extends StatefulWidget {
  const _AnimatedKeystoneQr({required this.urParts});

  final List<String> urParts;

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
    if (oldWidget.urParts != widget.urParts) {
      _index = 0;
      _frames.clear();
      _startTimer();
    }
  }

  QrImage _frameAt(int index) {
    return _frames[index] ??= QrImage(
      QrCode.fromData(
        data: widget.urParts[index],
        errorCorrectLevel: QrErrorCorrectLevel.L,
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.urParts.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
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
    // Figma (render-measured from 4654:62168 / 4654:63922): the QR ink is
    // drawn directly on the modal panel in both themes — no backing card.
    // Light paints #141818 modules on the #f7f7f7 panel; dark inverts the
    // ink and paints #f7f7f7 modules on the #232828 panel. Both use the
    // smooth symbol (adjacent modules merge into rounded runs; isolated
    // modules render as dots) with bullseye finder eyes painted over the
    // symbol's own eye pattern; the eye knockout matches the panel color.
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final moduleColor = isDark
        ? const Color(0xFFF7F7F7)
        : const Color(0xFF141818);
    final frame = _frameAt(_index);
    return SizedBox(
      width: 230,
      height: 230,
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
