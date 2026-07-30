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
// The multi-part scan progress row sits directly under the viewfinder. Its
// band is reserved unconditionally so the caption never shifts when progress
// starts arriving mid-scan.
const _scannerProgressGap = 8.0;
const _scannerProgressHeight = 18.0;
const _scannerProgressReserve =
    _scannerProgressGap + _scannerProgressHeight + _scannerProgressGap;
const _scannerProgressBarHeight = 8.0;
// `Round N of M` badge metrics. The scanner reserves header space from these,
// so they must match what [_SigningRoundBadge] renders.
const _signingRoundBadgeGap = AppSpacing.xxs;
const _signingRoundBadgeVerticalPadding = 4.0;
const _signingRoundBadgeHorizontalPadding = 10.0;

/// The user-facing signing round represented by this view.
enum MobileIronwoodKeystoneSigningRound { denominationSplit, migrationBatch }

/// The visual state of a single Keystone signing request.
enum MobileIronwoodKeystoneSigningViewState { loading, ready, scanner }

/// A reusable mobile shell for one Keystone signing round.
///
/// This widget deliberately owns no QR encoding, camera, or migration state.
/// The parent provides the current visual state and supplies the QR/camera
/// children from the production integration.
class MobileIronwoodKeystoneSigningView extends StatelessWidget {
  const MobileIronwoodKeystoneSigningView({
    required this.state,
    required this.round,
    this.signingRoundLabel,
    this.signingMessageCountLabel,
    this.scanProgress,
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

  /// `Round N of M`, rendered as an emphasised badge in both the request and
  /// the scanner state. Null when the request fits in a single round.
  final String? signingRoundLabel;

  /// How many transactions the current request signs, e.g.
  /// `Signs 26 of 51 transactions`. Shown in the request state only.
  final String? signingMessageCountLabel;

  /// Multi-part UR scan progress in `0..1`, or null when there is nothing to
  /// report yet. Shown in [scanner] only.
  final double? scanProgress;

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
            signingRoundLabel: signingRoundLabel,
            signingMessageCountLabel: signingMessageCountLabel,
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
            signingRoundLabel: signingRoundLabel,
            signingMessageCountLabel: signingMessageCountLabel,
            onNext: onNext,
            onCancel: onCancel,
            onShowScanHelp: onShowScanHelp,
          ),
        ),
        MobileIronwoodKeystoneSigningViewState.scanner => _ScannerContent(
          camera: camera,
          round: round,
          signingRoundLabel: signingRoundLabel,
          scanProgress: scanProgress,
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
    required this.signingRoundLabel,
    required this.signingMessageCountLabel,
    required this.onNext,
    required this.onCancel,
    required this.onShowScanHelp,
  });

  final bool loading;
  final Widget? qrCode;
  final MobileIronwoodKeystoneSigningRound round;
  final String? signingRoundLabel;
  final String? signingMessageCountLabel;
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
                    if (signingRoundLabel != null) ...[
                      const SizedBox(height: _signingRoundBadgeGap),
                      _SigningRoundBadge(label: signingRoundLabel!),
                    ],
                    if (signingMessageCountLabel != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        signingMessageCountLabel!,
                        key: const ValueKey(
                          'mobile_ironwood_keystone_signing_message_count',
                        ),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
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
                      _KeystoneScanPrompt(
                        color: colors.text.secondary,
                        onShowHelp: onShowScanHelp,
                      ),
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
  const _KeystoneScanPrompt({required this.color, this.onShowHelp});

  final Color color;
  final VoidCallback? onShowHelp;

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
        // The help affordance trails the last word of the sentence rather
        // than the whole two-line block, so it reads as part of the prompt.
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                'then scan this QR code',
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            if (onShowHelp != null) ...[
              const SizedBox(width: 6),
              _KeystoneScanHelpButton(color: color, onShowHelp: onShowHelp!),
            ],
          ],
        ),
      ],
    );
  }
}

class _KeystoneScanHelpButton extends StatelessWidget {
  const _KeystoneScanHelpButton({
    required this.color,
    required this.onShowHelp,
  });

  static const _visualSize = 28.0;
  static const _tapSize = 44.0;

  final Color color;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Keystone QR scanning help',
      excludeSemantics: true,
      child: SizedBox.square(
        key: const ValueKey('mobile_ironwood_keystone_scan_help'),
        dimension: _visualSize,
        // The icon only occupies 28px of layout so it stays on the sentence
        // line, while the tap target overflows to the 44pt minimum.
        child: OverflowBox(
          maxWidth: _tapSize,
          maxHeight: _tapSize,
          child: GestureDetector(
            key: const ValueKey(
              'mobile_ironwood_keystone_scan_help_tap_target',
            ),
            behavior: HitTestBehavior.opaque,
            onTap: onShowHelp,
            child: SizedBox.square(
              dimension: _tapSize,
              child: Center(
                child: AppIcon(AppIcons.help, size: 20, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The `Round N of M` emphasis badge.
///
/// Follows the existing Ironwood flow badge pattern (`_DarkBadge` in
/// `ironwood_migration_flow/shared_widgets.dart`): an inverted fill with
/// inverse label text, so it stays legible on the window background and on
/// the camera scrim (where this view forces the dark palette).
class _SigningRoundBadge extends StatelessWidget {
  const _SigningRoundBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: const ValueKey('mobile_ironwood_keystone_signing_round'),
      decoration: ShapeDecoration(
        color: colors.background.inverse,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _signingRoundBadgeHorizontalPadding,
          vertical: _signingRoundBadgeVerticalPadding,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(color: colors.text.inverse),
        ),
      ),
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
    required this.signingRoundLabel,
    required this.scanProgress,
    required this.onToggleFlashlight,
    required this.onShowRequestQr,
    required this.onCancel,
    required this.message,
    required this.messageIsError,
  });

  final Widget? camera;
  final MobileIronwoodKeystoneSigningRound round;
  final String? signingRoundLabel;
  final double? scanProgress;
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
            final displayHeight = _measuredTextHeight(
              context,
              text: 'Step 2/2',
              style: AppTypography.displayLarge,
              maxWidth: constraints.maxWidth,
            );
            final titleHeight = _measuredTextHeight(
              context,
              text: 'Confirm with Keystone',
              style: AppTypography.bodyMediumStrong,
              maxWidth: constraints.maxWidth,
            );
            final signingRoundReserve = signingRoundLabel == null
                ? 0.0
                : _signingRoundBadgeGap +
                      _signingRoundBadgeVerticalPadding * 2 +
                      _measuredTextHeight(
                        context,
                        text: signingRoundLabel!,
                        style: AppTypography.labelSmall,
                        maxWidth: constraints.maxWidth,
                      );
            final headerReserve =
                topInset +
                kMobileTopNavHeight +
                AppSpacing.s +
                displayHeight +
                AppSpacing.s +
                titleHeight +
                signingRoundReserve;
            const chromeReserve =
                _scannerProgressReserve +
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
                  _scannerProgressReserve -
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
                      if (signingRoundLabel != null) ...[
                        const SizedBox(height: _signingRoundBadgeGap),
                        _SigningRoundBadge(label: signingRoundLabel!),
                      ],
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
                if (scanProgress != null)
                  Positioned(
                    top: targetRect.bottom + _scannerProgressGap,
                    left: targetRect.left,
                    width: targetRect.width,
                    height: _scannerProgressHeight,
                    child: _ScanProgressRow(progress: scanProgress!),
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

  double _measuredTextHeight(
    BuildContext context, {
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.height;
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
    final minTop = targetRect.bottom + _scannerProgressReserve;
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

/// Multi-part UR scan progress, sized to the viewfinder width and paired with
/// a numeric readout.
///
/// The signed Keystone response arrives as an animated multi-part QR, so the
/// user needs to see that frames are accumulating. The decoder only reports a
/// percentage (`UrDecodeResult.progress`), never a part count, so the numeric
/// readout is a percentage.
class _ScanProgressRow extends StatelessWidget {
  const _ScanProgressRow({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.0, 1.0);
    const track = Color(0x59FFFFFF);
    const fill = Color(0xFFFFFFFF);
    return Semantics(
      label: 'Scan progress',
      value: '${(normalized * 100).round()}%',
      child: Row(
        key: const ValueKey('mobile_ironwood_keystone_signing_scan_progress'),
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.full),
              child: SizedBox(
                height: _scannerProgressBarHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(decoration: BoxDecoration(color: track)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: normalized,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(color: fill),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${(normalized * 100).round()}%',
            key: const ValueKey(
              'mobile_ironwood_keystone_signing_scan_progress_value',
            ),
            style: AppTypography.labelSmall.copyWith(color: fill),
          ),
        ],
      ),
    );
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
