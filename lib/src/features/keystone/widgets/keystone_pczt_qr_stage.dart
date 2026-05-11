import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';

enum KeystonePcztQrStagePhase { preparing, ready, working, failed }

class KeystonePcztQrStage extends StatelessWidget {
  const KeystonePcztQrStage({
    required this.phase,
    required this.urParts,
    required this.error,
    this.preparingLabel = 'Preparing QR...',
    this.workingLabel = 'Broadcasting...',
    super.key,
  });

  final KeystonePcztQrStagePhase phase;
  final List<String> urParts;
  final String? error;
  final String preparingLabel;
  final String workingLabel;

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
        KeystonePcztQrStagePhase.working => Center(
          child: Text(
            workingLabel,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        KeystonePcztQrStagePhase.preparing => Center(
          child: Text(
            preparingLabel,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      },
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
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.urParts.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
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
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: QrImageView(
          data: widget.urParts[_index],
          size: 226,
          backgroundColor: const Color(0xFFFFFFFF),
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF141818),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF141818),
          ),
          errorCorrectionLevel: QrErrorCorrectLevel.L,
        ),
      ),
    );
  }
}
