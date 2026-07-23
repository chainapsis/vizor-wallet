import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanViewfinderCorners;

const _stepOneProgress = 0.5;
const _stepTwoProgress = 1.0;
const _designHeight = 852.0;
const _scannerTargetSize = 286.0;
const _scannerTargetTop = 288.0;
const _scannerCaptionTop = 628.0;
const _scannerCaptionHeight = 75.0;
const _scannerActionTop = 762.0;
const _scannerActionSize = 40.0;

/// The user-facing signing round represented by this view.
enum MobileIronwoodKeystoneSigningRound { denominationSplit, migrationBatch }

/// The visual state of a single Keystone signing request.
enum MobileIronwoodKeystoneSigningViewState { loading, ready, scanner }

/// A reusable mobile shell for one Keystone signing request.
///
/// This widget deliberately owns no QR encoding, camera, or migration state.
/// The parent provides the current visual state and supplies the QR/camera
/// children from the production integration.
class MobileIronwoodKeystoneSigningView extends StatelessWidget {
  const MobileIronwoodKeystoneSigningView({
    required this.state,
    required this.round,
    this.qrCode,
    this.camera,
    this.onNext,
    this.onCancel,
    this.onToggleFlashlight,
    this.onShowRequestQr,
    this.onShowScanHelp,
    this.scannerMessage,
    this.scannerMessageIsError = false,
    super.key,
  });

  final MobileIronwoodKeystoneSigningViewState state;
  final MobileIronwoodKeystoneSigningRound round;

  /// The already-rendered request QR. It is shown only in [ready].
  final Widget? qrCode;

  /// The live camera surface. It is shown only in [scanner].
  final Widget? camera;

  final VoidCallback? onNext;
  final VoidCallback? onCancel;
  final VoidCallback? onToggleFlashlight;
  final VoidCallback? onShowRequestQr;
  final VoidCallback? onShowScanHelp;
  final String? scannerMessage;
  final bool scannerMessageIsError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: switch (state) {
        MobileIronwoodKeystoneSigningViewState.loading => SafeArea(
          child: _StepOneContent(
            loading: true,
            qrCode: null,
            round: round,
            onNext: onNext,
            onCancel: onCancel,
            onShowScanHelp: onShowScanHelp,
          ),
        ),
        MobileIronwoodKeystoneSigningViewState.ready => SafeArea(
          child: _StepOneContent(
            loading: false,
            qrCode: qrCode,
            round: round,
            onNext: onNext,
            onCancel: onCancel,
            onShowScanHelp: onShowScanHelp,
          ),
        ),
        MobileIronwoodKeystoneSigningViewState.scanner => _ScannerContent(
          camera: camera,
          round: round,
          onToggleFlashlight: onToggleFlashlight,
          onShowRequestQr: onShowRequestQr,
          onCancel: onCancel,
          message: scannerMessage,
          messageIsError: scannerMessageIsError,
        ),
      },
    );
  }
}

class _StepOneContent extends StatelessWidget {
  const _StepOneContent({
    required this.loading,
    required this.qrCode,
    required this.round,
    required this.onNext,
    required this.onCancel,
    required this.onShowScanHelp,
  });

  final bool loading;
  final Widget? qrCode;
  final MobileIronwoodKeystoneSigningRound round;
  final VoidCallback? onNext;
  final VoidCallback? onCancel;
  final VoidCallback? onShowScanHelp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: round == MobileIronwoodKeystoneSigningRound.denominationSplit
          ? 'Confirm migration preparation with Keystone'
          : 'Confirm migration transfer with Keystone',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 720;
          final qrSize = math
              .min(321.0, constraints.maxWidth - AppSpacing.sm * 2)
              .clamp(200.0, 321.0)
              .toDouble();
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const Offstage(child: AppIcon(AppIcons.qr, size: 26)),
                    MobileTopNav.steps(
                      progress: _stepOneProgress,
                      onBack: onCancel,
                      key: const ValueKey(
                        'mobile_ironwood_keystone_signing_top_nav',
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.s),
                    Text(
                      'Step 1/2',
                      key: const ValueKey(
                        'mobile_ironwood_keystone_signing_step',
                      ),
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.s),
                    Text(
                      loading
                          ? 'Confirm Migration with Keystone'
                          : 'Scan with Keystone',
                      key: loading
                          ? const ValueKey(
                              'mobile_ironwood_keystone_signing_title',
                            )
                          : const ValueKey(
                              'mobile_ironwood_keystone_signing_ready_label',
                            ),
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.s : AppSpacing.lg),
                    if (loading)
                      _LoadingQr(size: qrSize)
                    else
                      _QrContainer(size: qrSize, child: qrCode),
                    SizedBox(height: compact ? AppSpacing.s : 38),
                    if (loading)
                      Text(
                        'Loading QR code ...',
                        key: const ValueKey(
                          'mobile_ironwood_keystone_signing_loading',
                        ),
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      )
                    else
                      _KeystoneScanPrompt(color: colors.text.secondary),
                    if (!loading && onShowScanHelp != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AppButton(
                        key: const ValueKey(
                          'mobile_ironwood_keystone_scan_help',
                        ),
                        variant: AppButtonVariant.ghost,
                        expand: true,
                        constrainContent: true,
                        onPressed: onShowScanHelp,
                        child: const Text('Having issues scanning?'),
                      ),
                    ],
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: AppButton(
                          key: const ValueKey(
                            'mobile_ironwood_keystone_signing_next',
                          ),
                          expand: true,
                          height: 50,
                          onPressed: onNext,
                          trailing: const AppIcon(
                            AppIcons.chevronForward,
                            size: 20,
                          ),
                          child: const Text('Next step'),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      key: const ValueKey(
                        'mobile_ironwood_keystone_signing_cancel',
                      ),
                      variant: AppButtonVariant.ghost,
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(height: AppSpacing.s),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoadingQr extends StatefulWidget {
  const _LoadingQr({required this.size});

  final double size;

  @override
  State<_LoadingQr> createState() => _LoadingQrState();
}

class _LoadingQrState extends State<_LoadingQr>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading QR code',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final bandHeight = widget.size * 0.78;
              final travel = widget.size + bandHeight * 2;
              final top = -bandHeight + travel * _controller.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.background.neutralSubtleOpacity,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: top,
                    height: bandHeight,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x12FFFFFF),
                            Color(0x80FFFFFF),
                            Color(0x12FFFFFF),
                          ],
                          stops: [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KeystoneScanPrompt extends StatelessWidget {
  const _KeystoneScanPrompt({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyMedium.copyWith(color: color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [
            Text('Tap', style: style),
            const _KeystoneScanPromptIcon(),
            Text('on your Keystone,', style: style),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'then scan this QR code',
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }
}

class _KeystoneScanPromptIcon extends StatelessWidget {
  const _KeystoneScanPromptIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF98F0E),
        borderRadius: BorderRadius.circular(8.615),
      ),
      child: const SizedBox.square(
        dimension: 28,
        child: Center(
          child: AppIcon(
            AppIcons.keystoneScan,
            color: Color(0xFFFFFFFF),
            size: 18.3335,
          ),
        ),
      ),
    );
  }
}

class _QrContainer extends StatelessWidget {
  const _QrContainer({required this.size, required this.child});

  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Keystone request QR code',
      child: Container(
        key: const ValueKey('mobile_ironwood_keystone_signing_qr_container'),
        width: size,
        height: size,
        padding: const EdgeInsets.all(8),
        color: const Color(0xFFFFFFFF),
        child: Center(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _ScannerContent extends StatelessWidget {
  const _ScannerContent({
    required this.camera,
    required this.round,
    required this.onToggleFlashlight,
    required this.onShowRequestQr,
    required this.onCancel,
    required this.message,
    required this.messageIsError,
  });

  final Widget? camera;
  final MobileIronwoodKeystoneSigningRound round;
  final VoidCallback? onToggleFlashlight;
  final VoidCallback? onShowRequestQr;
  final VoidCallback? onCancel;
  final String? message;
  final bool messageIsError;

  @override
  Widget build(BuildContext context) {
    return AppTheme(
      data: AppThemeData.dark,
      child: Semantics(
        label: round == MobileIronwoodKeystoneSigningRound.denominationSplit
            ? 'Scan the signed migration preparation from Keystone'
            : 'Scan the signed migration transfer from Keystone',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final topInset = MediaQuery.paddingOf(context).top;
            final headerReserve =
                topInset +
                kMobileTopNavHeight +
                AppSpacing.s +
                (AppTypography.displayLarge.fontSize ?? 40) *
                    (AppTypography.displayLarge.height ?? 1) +
                AppSpacing.s +
                (AppTypography.bodyMediumStrong.fontSize ?? 16) *
                    (AppTypography.bodyMediumStrong.height ?? 1);
            const chromeReserve =
                12 +
                _scannerCaptionHeight +
                AppSpacing.s +
                _scannerActionSize +
                AppSpacing.xxs;
            final targetSize = math
                .min(
                  _scannerTargetSize,
                  math.min(
                    constraints.maxWidth - AppSpacing.sm * 2,
                    constraints.maxHeight - headerReserve - chromeReserve,
                  ),
                )
                .clamp(160.0, _scannerTargetSize)
                .toDouble();
            final maxActionTop = math.max(
              0.0,
              constraints.maxHeight - _scannerActionSize - AppSpacing.xxs,
            );
            final maxTargetTop = math.max(
              0.0,
              maxActionTop -
                  AppSpacing.s -
                  _scannerCaptionHeight -
                  12 -
                  targetSize,
            );
            final desiredTargetTop = _scaledTop(
              constraints,
              designTop: _scannerTargetTop,
              height: targetSize,
            );
            final targetTop = desiredTargetTop
                .clamp(math.min(headerReserve, maxTargetTop), maxTargetTop)
                .toDouble();
            final targetLeft = (constraints.maxWidth - targetSize) / 2;
            final targetRect = Rect.fromLTWH(
              targetLeft,
              targetTop,
              targetSize,
              targetSize,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: const Color(0xFF101010),
                  child: camera ?? const SizedBox.shrink(),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ScannerScrimPainter(hole: targetRect),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      MobileTopNav.steps(
                        progress: _stepTwoProgress,
                        onBack: onCancel,
                        key: const ValueKey(
                          'mobile_ironwood_keystone_signing_top_nav',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Text(
                        'Step 2/2',
                        style: AppTypography.displayLarge.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Text(
                        'Confirm with Keystone',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned.fromRect(
                  rect: targetRect,
                  child: const SizedBox(
                    key: ValueKey(
                      'mobile_ironwood_keystone_signing_scan_target',
                    ),
                    child: MobileScanViewfinderCorners(
                      cornerLength: 60,
                      cornerRadius: 32,
                      strokeWidth: 6,
                    ),
                  ),
                ),
                Positioned(
                  top: _captionTop(
                    constraints,
                    targetRect: targetRect,
                    maxActionTop: maxActionTop,
                  ),
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: SizedBox(
                    height: _scannerCaptionHeight,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        message ??
                            'Scan the QR code on your\nKeystone to confirm',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: messageIsError
                              ? const Color(0xFFFF7B7B)
                              : const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  top: _actionTop(
                    constraints,
                    targetRect: targetRect,
                    maxActionTop: maxActionTop,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ScannerControl(
                        key: const ValueKey(
                          'mobile_ironwood_keystone_signing_flashlight',
                        ),
                        label: 'Toggle flashlight',
                        onPressed: onToggleFlashlight,
                        child: const Icon(
                          Icons.flashlight_on_outlined,
                          color: Color(0xFFFFFFFF),
                          size: 30,
                        ),
                      ),
                      _ScannerControl(
                        key: const ValueKey(
                          'mobile_ironwood_keystone_signing_qr_action',
                        ),
                        label: 'Show transaction QR',
                        onPressed: onShowRequestQr,
                        child: AppIcon(
                          AppIcons.qr,
                          color: const Color(0xFFFFFFFF).withValues(
                            alpha: onShowRequestQr == null ? 0.4 : 1,
                          ),
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _scaledTop(
    BoxConstraints constraints, {
    required double designTop,
    required double height,
  }) {
    return (designTop * (constraints.maxHeight / _designHeight))
        .clamp(0.0, math.max(0.0, constraints.maxHeight - height))
        .toDouble();
  }

  double _captionTop(
    BoxConstraints constraints, {
    required Rect targetRect,
    required double maxActionTop,
  }) {
    final minTop = targetRect.bottom + 12;
    final maxTop = math.max(
      minTop,
      maxActionTop - AppSpacing.s - _scannerCaptionHeight,
    );
    return _scaledTop(
      constraints,
      designTop: _scannerCaptionTop,
      height: _scannerCaptionHeight,
    ).clamp(minTop, maxTop).toDouble();
  }

  double _actionTop(
    BoxConstraints constraints, {
    required Rect targetRect,
    required double maxActionTop,
  }) {
    final captionTop = _captionTop(
      constraints,
      targetRect: targetRect,
      maxActionTop: maxActionTop,
    );
    return math
        .max(
          _scaledTop(
            constraints,
            designTop: _scannerActionTop,
            height: _scannerActionSize,
          ),
          captionTop + _scannerCaptionHeight + AppSpacing.s,
        )
        .clamp(0.0, maxActionTop)
        .toDouble();
  }
}

class _ScannerControl extends StatelessWidget {
  const _ScannerControl({
    required this.child,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final Widget child;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: _scannerActionSize,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ScannerScrimPainter extends CustomPainter {
  const _ScannerScrimPainter({required this.hole});

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(30)));
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
  }

  @override
  bool shouldRepaint(covariant _ScannerScrimPainter oldDelegate) =>
      oldDelegate.hole != hole;
}
