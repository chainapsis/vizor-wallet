import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../domain/swap_contract.dart';
import '../models/swap_address_formatting.dart';
import '../models/swap_deposit_qr_payload.dart';

class SwapDepositTokensPageContent extends StatelessWidget {
  const SwapDepositTokensPageContent({
    required this.asset,
    required this.amountText,
    required this.depositAddress,
    required this.expiresInLabel,
    required this.onDeposited,
    this.checking = false,
    this.checkWarning,
    this.expiresAt,
    this.now,
    this.memo,
    this.mobile = false,
    super.key,
  });

  final SwapAsset asset;
  final String amountText;
  final String depositAddress;
  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;
  final String? memo;
  final VoidCallback onDeposited;
  final bool checking;
  final String? checkWarning;

  /// Renders the Figma mobile deposit frame (4731:96923): a single
  /// full-width card with a large QR stacked over the amount, then the
  /// detail rows and a full-width primary action.
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return _SwapDepositPageShell(
      asset: asset,
      amountText: amountText,
      depositAddress: depositAddress,
      expiresInLabel: expiresInLabel,
      expiresAt: expiresAt,
      now: now,
      memo: memo,
      mobile: mobile,
      actionArea: _DepositConfirmActionArea(
        checking: checking,
        warning: checkWarning,
        buttonLabel: 'I’ve deposited tokens',
        onDeposited: onDeposited,
        mobile: mobile,
      ),
    );
  }
}

class SwapHardwareZecDepositPageContent extends StatelessWidget {
  const SwapHardwareZecDepositPageContent({
    required this.asset,
    required this.amountText,
    required this.depositAddress,
    required this.expiresInLabel,
    required this.onDepositZec,
    this.expiresAt,
    this.now,
    this.memo,
    this.mobile = false,
    super.key,
  });

  final SwapAsset asset;
  final String amountText;
  final String depositAddress;
  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;
  final String? memo;
  final VoidCallback onDepositZec;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return _SwapDepositPageShell(
      asset: asset,
      amountText: amountText,
      depositAddress: depositAddress,
      expiresInLabel: expiresInLabel,
      expiresAt: expiresAt,
      now: now,
      memo: memo,
      mobile: mobile,
      actionArea: _DepositConfirmActionArea(
        checking: false,
        warning: null,
        buttonLabel: 'Deposit ZEC',
        onDeposited: onDepositZec,
        mobile: mobile,
      ),
    );
  }
}

class _SwapDepositPageShell extends StatelessWidget {
  const _SwapDepositPageShell({
    required this.asset,
    required this.amountText,
    required this.depositAddress,
    required this.expiresInLabel,
    required this.actionArea,
    this.expiresAt,
    this.now,
    this.memo,
    this.mobile = false,
  });

  final SwapAsset asset;
  final String amountText;
  final String depositAddress;
  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;
  final String? memo;
  final Widget actionArea;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    if (mobile) return _buildMobile(context);
    return _buildDesktop(context);
  }

  Widget _buildMobile(BuildContext context) {
    // Figma 4731:96923: the screen title comes from the host top nav
    // ("Review quote"), so the content starts with the full-width QR card.
    return Column(
      key: const ValueKey('swap_deposit_tokens_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('swap_activity_deposit_qr_panel'),
          child: _MobileDepositQrCard(
            asset: asset,
            qrData: swapDepositQrPayload(depositAddress, memo),
            amountText: amountText,
            expiresInLabel: expiresInLabel,
            expiresAt: expiresAt,
            now: now,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _DepositDetailsList(
          amountText: amountText,
          depositAddress: depositAddress,
          memo: memo,
          mobile: true,
        ),
        actionArea,
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('swap_deposit_tokens_panel'),
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Deposit tokens',
            key: const ValueKey('swap_deposit_tokens_title'),
            textAlign: TextAlign.center,
            style: AppTypography.displaySmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          KeyedSubtree(
            key: const ValueKey('swap_activity_deposit_qr_panel'),
            child: _DepositQrCard(
              asset: asset,
              qrData: swapDepositQrPayload(depositAddress, memo),
              amountText: amountText,
              expiresInLabel: expiresInLabel,
              expiresAt: expiresAt,
              now: now,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DepositDetailsList(
            amountText: amountText,
            depositAddress: depositAddress,
            memo: memo,
          ),
          actionArea,
        ],
      ),
    );
  }
}

/// Figma 4731:96923 deposit card: a full-width rounded surface with the
/// large QR stacked over the amount and the deposit countdown, all
/// centred. Desktop keeps the side-by-side [_DepositQrCard].
class _MobileDepositQrCard extends StatelessWidget {
  const _MobileDepositQrCard({
    required this.asset,
    required this.qrData,
    required this.amountText,
    required this.expiresInLabel,
    required this.expiresAt,
    required this.now,
  });

  static const _width = 337.0;
  static const _height = 452.0;
  static const _radius = 48.0;
  static const _padding = AppSpacing.s;
  static const _qrSize = 313.0;
  static const _qrPadding = AppSpacing.sm;
  static const _qrLogoSize = 57.0;

  final SwapAsset asset;
  final String qrData;
  final String amountText;
  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth.clamp(0.0, _width).toDouble()
            : _width;
        final qrSize = (cardWidth - _padding * 2)
            .clamp(0.0, _qrSize)
            .toDouble();
        final qrScale = _qrSize == 0 ? 1.0 : qrSize / _qrSize;
        return Center(
          child: Container(
            key: const ValueKey('swap_deposit_qr_card'),
            width: cardWidth,
            height: _height,
            padding: const EdgeInsets.all(_padding),
            decoration: BoxDecoration(
              color: colors.background.homeCard,
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _DepositQrCode(
                  data: qrData,
                  asset: asset,
                  size: qrSize,
                  padding: _qrPadding,
                  radius: AppRadii.xLarge,
                  logoSize: _qrLogoSize * qrScale,
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 99,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        Text(
                          amountText,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineLarge.copyWith(
                            color: colors.text.homeCard,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        _DepositExpiryLine(
                          expiresInLabel: expiresInLabel,
                          expiresAt: expiresAt,
                          now: now,
                          centered: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DepositConfirmActionArea extends StatelessWidget {
  const _DepositConfirmActionArea({
    required this.checking,
    required this.warning,
    required this.buttonLabel,
    required this.onDeposited,
    this.mobile = false,
  });

  static const _buttonHeight = 44.0;
  static const _buttonWidth = 256.0;
  static const _buttonTopGap = AppSpacing.xl + AppSpacing.sm;
  static const _height = _buttonTopGap + _buttonHeight;

  final bool checking;
  final String? warning;
  final String buttonLabel;
  final VoidCallback onDeposited;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    if (mobile) {
      // Figma pins a full-width primary action below the detail rows.
      return Column(
        key: const ValueKey('swap_deposit_confirm_action_area'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (warning != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _DepositCheckWarning(message: warning!),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const ValueKey('swap_deposit_confirm_button'),
            onPressed: checking ? null : onDeposited,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            expand: true,
            constrainContent: true,
            child: _DepositConfirmButtonLabel(
              checking: checking,
              buttonLabel: buttonLabel,
            ),
          ),
        ],
      );
    }
    return SizedBox(
      key: const ValueKey('swap_deposit_confirm_action_area'),
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          if (warning != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: _buttonHeight + AppSpacing.sm,
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: _buttonWidth,
                  child: _DepositCheckWarning(message: warning!),
                ),
              ),
            ),
          AppButton(
            key: const ValueKey('swap_deposit_confirm_button'),
            onPressed: checking ? null : onDeposited,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            minWidth: _buttonWidth,
            trailing: checking ? null : const AppIcon(AppIcons.arrowForwardIos),
            child: _DepositConfirmButtonLabel(
              checking: checking,
              buttonLabel: buttonLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _DepositConfirmButtonLabel extends StatelessWidget {
  const _DepositConfirmButtonLabel({
    required this.checking,
    required this.buttonLabel,
  });

  final bool checking;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    if (!checking) {
      return Text(buttonLabel, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Checking', maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(width: AppSpacing.xxs),
        const AppIcon(
          AppIcons.loader,
          key: ValueKey('swap_deposit_confirm_loader'),
        ),
      ],
    );
  }
}

class _DepositCheckWarning extends StatelessWidget {
  const _DepositCheckWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('swap_deposit_check_warning'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          AppIcons.warning,
          size: AppIconSize.medium,
          color: colors.icon.destructive,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ),
      ],
    );
  }
}

class SwapDepositTimeoutPageContent extends StatelessWidget {
  const SwapDepositTimeoutPageContent({required this.onRestart, super.key});

  static const _lightIllustration =
      'assets/illustrations/swap_deposit_timeout_illustration_light.png';
  static const _darkIllustration =
      'assets/illustrations/swap_deposit_timeout_illustration_dark.png';

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return SizedBox(
      key: const ValueKey('swap_deposit_timeout_panel'),
      width: 274,
      height: 388,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            isDark ? _darkIllustration : _lightIllustration,
            key: const ValueKey('swap_deposit_timeout_illustration'),
            width: 210,
            height: 160,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: AppSpacing.base),
          SizedBox(
            width: 274,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.time,
                      size: AppIconSize.medium,
                      color: colors.text.secondary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Time’s up',
                      key: const ValueKey('swap_deposit_timeout_label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Swap failed',
                  key: const ValueKey('swap_deposit_timeout_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'This deposit address is no longer valid.\nPlease, start another swap transaction.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          SizedBox(
            width: 256,
            height: 44,
            child: AppButton(
              key: const ValueKey('swap_deposit_restart_button'),
              onPressed: onRestart,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.large,
              minWidth: 256,
              leading: const AppIcon(AppIcons.renew),
              child: const Text('Restart swap'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DepositQrCard extends StatelessWidget {
  const _DepositQrCard({
    required this.asset,
    required this.qrData,
    required this.amountText,
    required this.expiresInLabel,
    required this.expiresAt,
    required this.now,
  });

  final SwapAsset asset;
  final String qrData;
  final String amountText;
  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_deposit_qr_card'),
      width: 400,
      height: 210,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DepositQrCode(data: qrData, asset: asset),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 174,
                height: 194,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          amountText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSmall.copyWith(
                            color: colors.text.homeCard,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        _DepositExpiryLine(
                          expiresInLabel: expiresInLabel,
                          expiresAt: expiresAt,
                          now: now,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DepositExpiryLine extends StatefulWidget {
  const _DepositExpiryLine({
    required this.expiresInLabel,
    required this.expiresAt,
    required this.now,
    this.centered = false,
  });

  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;
  final bool centered;

  @override
  State<_DepositExpiryLine> createState() => _DepositExpiryLineState();
}

class _DepositExpiryLineState extends State<_DepositExpiryLine> {
  static const _countdownThreshold = Duration(minutes: 15);

  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = _remainingToDeadline();
    _scheduleTimer();
  }

  @override
  void didUpdateWidget(covariant _DepositExpiryLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt ||
        oldWidget.expiresInLabel != widget.expiresInLabel ||
        oldWidget.now != widget.now) {
      _remaining = _remainingToDeadline();
      _scheduleTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = null;
    final expiresAt = widget.expiresAt;
    if (expiresAt == null) return;

    final remaining = _remainingToDeadline();
    if (remaining <= Duration.zero) return;
    if (remaining < _countdownThreshold) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      return;
    }

    final secondsToNextMinuteLabel = remaining.inSeconds.remainder(60) + 1;
    final secondsUntilCountdown =
        remaining.inSeconds - _countdownThreshold.inSeconds + 1;
    final delaySeconds =
        secondsToNextMinuteLabel < secondsUntilCountdown
            ? secondsToNextMinuteLabel
            : secondsUntilCountdown;
    _timer = Timer(Duration(seconds: delaySeconds), _tick);
  }

  void _tick([Timer? _]) {
    if (!mounted) return;
    setState(() {
      _remaining = _remainingToDeadline();
    });
    _scheduleTimer();
  }

  Duration _remainingToDeadline() {
    final expiresAt = widget.expiresAt;
    if (expiresAt == null) return Duration.zero;
    final now = widget.now?.call() ?? DateTime.now();
    return expiresAt.difference(now);
  }

  String get _expiresInLabel {
    final expiresAt = widget.expiresAt;
    if (expiresAt == null) return widget.expiresInLabel;
    if (_remaining <= Duration.zero) return '00:00';
    if (_remaining < _countdownThreshold) {
      return _formatCountdown(_remaining);
    }
    if (_remaining.inHours >= 1) {
      return _formatDepositDurationLabel(_remaining);
    }
    return _formatMinuteLabel(_remaining.inMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.homeCard,
    );
    if (widget.centered) {
      return Row(
        key: const ValueKey('swap_deposit_expiry_label'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Deposit within',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: 2,
            ),
            child: Text(
              _expiresInLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      );
    }
    return Row(
      key: const ValueKey('swap_deposit_expiry_label'),
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          child: Text(
            'Deposit within',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: 2,
          ),
          child: Text(
            _expiresInLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _DepositQrCode extends StatelessWidget {
  const _DepositQrCode({
    required this.data,
    required this.asset,
    this.size = 194,
    this.padding = AppSpacing.s,
    this.radius = AppRadii.small,
    this.logoSize = 34,
  });

  final String data;
  final SwapAsset asset;

  /// Outer side length. Desktop pins 194; mobile uses Figma's 313px QR wrap.
  final double size;
  final double padding;
  final double radius;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_deposit_tokens_qr_code'),
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colors.surface.qrCode,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          PrettyQrView.data(
            data: data,
            errorCorrectLevel: QrErrorCorrectLevel.M,
            decoration: const PrettyQrDecoration(
              quietZone: PrettyQrQuietZone.zero,
              shape: PrettyQrSmoothSymbol(roundFactor: 0.75),
            ),
          ),
          _DepositQrNetworkLogo(asset: asset, size: logoSize),
        ],
      ),
    );
  }
}

class _DepositQrNetworkLogo extends StatelessWidget {
  const _DepositQrNetworkLogo({required this.asset, this.size = 34});

  final SwapAsset asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final logo = Container(
      key: const ValueKey('swap_deposit_qr_logo'),
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface.qrCode,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: ClipOval(
        child: Image.asset(
          asset.chainIconAsset,
          fit: BoxFit.cover,
          semanticLabel: asset.chainLabel,
          errorBuilder:
              (context, _, _) => _DepositQrNetworkLogoFallback(asset: asset),
        ),
      ),
    );
    if (Overlay.maybeOf(context) == null) return logo;
    return AppTooltip(message: asset.chainLabel, tapToShow: true, child: logo);
  }
}

class _DepositQrNetworkLogoFallback extends StatelessWidget {
  const _DepositQrNetworkLogoFallback({required this.asset});

  final SwapAsset asset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label =
        asset.chainLabel.trim().isEmpty ? asset.chainTicker : asset.chainLabel;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        label.trim().isEmpty ? '?' : label.trim().substring(0, 1).toUpperCase(),
        style: AppTypography.labelSmall.copyWith(color: colors.text.muted),
      ),
    );
  }
}

class _DepositDetailsList extends StatelessWidget {
  const _DepositDetailsList({
    required this.amountText,
    required this.depositAddress,
    this.memo,
    this.mobile = false,
  });

  final String amountText;
  final String depositAddress;
  final String? memo;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('swap_deposit_details'),
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? AppSpacing.s : AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DepositDetailRow(
            label: 'Amount to deposit',
            value: amountText,
            copyText: amountText,
            toastMessage: 'Amount copied',
            copyKey: const ValueKey('swap_copy_deposit_amount'),
            rightKey: const ValueKey('swap_deposit_amount_right_item'),
            mobile: mobile,
          ),
          _DepositDetailRow(
            label: 'One-time address',
            value: compactSwapAddress(depositAddress),
            copyText: depositAddress,
            toastMessage: 'Address copied',
            copyKey: const ValueKey('swap_copy_deposit_address'),
            rightKey: const ValueKey('swap_deposit_address_right_item'),
            mobile: mobile,
          ),
          if (memo?.trim().isNotEmpty ?? false)
            _DepositDetailRow(
              label: 'Memo',
              value: memo!.trim(),
              copyText: memo!.trim(),
              toastMessage: 'Memo copied',
              copyKey: const ValueKey('swap_copy_deposit_memo'),
              rightKey: const ValueKey('swap_deposit_memo_right_item'),
              mobile: mobile,
            ),
        ],
      ),
    );
  }
}

class _DepositDetailRow extends StatelessWidget {
  const _DepositDetailRow({
    required this.label,
    required this.value,
    required this.copyText,
    required this.toastMessage,
    required this.copyKey,
    required this.rightKey,
    this.mobile = false,
  });

  static const _mobileLabelMaxWidth = 134.0;

  final String label;
  final String value;
  final String copyText;
  final String toastMessage;
  final Key copyKey;
  final Key rightKey;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelText = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(color: colors.text.secondary),
      ),
    );
    final valueTextStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.accent,
    );
    final valueText = Text(
      value,
      maxLines: 1,
      softWrap: false,
      overflow: mobile ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: valueTextStyle,
    );
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          if (mobile)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _mobileLabelMaxWidth),
              child: labelText,
            )
          else
            Flexible(fit: FlexFit.loose, child: labelText),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Padding(
              key: rightKey,
              padding: EdgeInsets.fromLTRB(
                mobile ? AppSpacing.xs : 0,
                mobile ? AppSpacing.xxs : 0,
                AppSpacing.xxs,
                mobile ? AppSpacing.xxs : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child:
                        mobile
                            ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: valueText,
                            )
                            : valueText,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      key: copyKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        copyTextWithToast(
                          context,
                          text: copyText,
                          toastMessage: toastMessage,
                        );
                      },
                      child: SizedBox.square(
                        dimension: 20,
                        child: AppIcon(
                          AppIcons.copy,
                          size: 20,
                          color: colors.icon.regular.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCountdown(Duration remaining) {
  final totalSeconds = remaining.inSeconds <= 0 ? 0 : remaining.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatDepositDurationLabel(Duration remaining) {
  if (remaining <= Duration.zero) return '00:00';
  if (remaining.inHours >= 1) {
    final hours = (remaining.inSeconds / Duration.secondsPerHour).ceil();
    return _formatHourLabel(hours);
  }
  return _formatMinuteLabel(remaining.inMinutes);
}

String _formatHourLabel(int hours) {
  return hours == 1 ? '1hr' : '${hours}hrs';
}

String _formatMinuteLabel(int minutes) {
  return minutes == 1 ? '1min' : '${minutes}mins';
}
