import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../domain/swap_contract.dart';
import 'swap_copy_feedback.dart';
import 'swap_asset_icon.dart';

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

  @override
  Widget build(BuildContext context) {
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
              qrData: _qrPayload(depositAddress, memo),
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
          ),
          _DepositConfirmActionArea(
            checking: checking,
            warning: checkWarning,
            onDeposited: onDeposited,
          ),
        ],
      ),
    );
  }
}

class _DepositConfirmActionArea extends StatelessWidget {
  const _DepositConfirmActionArea({
    required this.checking,
    required this.warning,
    required this.onDeposited,
  });

  static const _buttonHeight = 44.0;
  static const _buttonWidth = 256.0;
  static const _buttonTopGap = AppSpacing.xl + AppSpacing.sm;
  static const _height = _buttonTopGap + _buttonHeight;

  final bool checking;
  final String? warning;
  final VoidCallback onDeposited;

  @override
  Widget build(BuildContext context) {
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
            child: _DepositConfirmButtonLabel(checking: checking),
          ),
        ],
      ),
    );
  }
}

class _DepositConfirmButtonLabel extends StatelessWidget {
  const _DepositConfirmButtonLabel({required this.checking});

  final bool checking;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(checking ? 'Checking' : "I've deposited", maxLines: 1),
        if (checking) ...[
          const SizedBox(width: AppSpacing.xxs),
          const AppIcon(
            AppIcons.loader,
            key: ValueKey('swap_deposit_confirm_loader'),
          ),
        ],
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
          Column(
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
                textAlign: TextAlign.center,
                style: AppTypography.displaySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This deposit address is no longer valid. Please, start another swap transaction.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          AppButton(
            key: const ValueKey('swap_deposit_restart_button'),
            onPressed: onRestart,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.large,
            minWidth: 256,
            leading: const AppIcon(AppIcons.renew),
            child: const Text('Restart Swap'),
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
  });

  final String expiresInLabel;
  final DateTime? expiresAt;
  final DateTime Function()? now;

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
    final delaySeconds = secondsToNextMinuteLabel < secondsUntilCountdown
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
    if (_remaining.inHours >= 1) return '${_remaining.inHours}hrs';
    return '${_remaining.inMinutes}mins';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RichText(
      key: const ValueKey('swap_deposit_expiry_label'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: AppTypography.labelLarge.copyWith(color: colors.text.homeCard),
        children: [
          TextSpan(
            text: 'Deposit within ',
            style: TextStyle(
              color: colors.text.homeCard.withValues(alpha: 0.72),
            ),
          ),
          TextSpan(text: _expiresInLabel),
        ],
      ),
    );
  }
}

class _DepositQrCode extends StatelessWidget {
  const _DepositQrCode({required this.data, required this.asset});

  final String data;
  final SwapAsset asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('swap_deposit_tokens_qr_code'),
      width: 194,
      height: 194,
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(AppRadii.small),
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
          Container(
            key: const ValueKey('swap_deposit_qr_logo'),
            width: 34,
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: SwapAssetIcon(asset: asset, size: 30, showChainBadge: false),
          ),
        ],
      ),
    );
  }
}

class _DepositDetailsList extends StatelessWidget {
  const _DepositDetailsList({
    required this.amountText,
    required this.depositAddress,
  });

  final String amountText;
  final String depositAddress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('swap_deposit_details'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DepositDetailRow(
            label: 'Amount',
            value: amountText,
            copyText: amountText,
            toastMessage: 'Amount Copied',
            copyKey: const ValueKey('swap_copy_deposit_amount'),
          ),
          _DepositDetailRow(
            label: 'One-time address',
            value: _compactAddress(depositAddress),
            copyText: depositAddress,
            toastMessage: 'Address Copied',
            copyKey: const ValueKey('swap_copy_deposit_address'),
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
  });

  final String label;
  final String value;
  final String copyText;
  final String toastMessage;
  final Key copyKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      key: copyKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        copySwapText(
                          context,
                          text: copyText,
                          toastMessage: toastMessage,
                        );
                      },
                      child: AppIcon(
                        AppIcons.copy,
                        size: AppIconSize.medium,
                        color: colors.icon.regular.withValues(alpha: 0.72),
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

String _qrPayload(String address, String? memo) {
  final normalizedMemo = memo?.trim();
  if (normalizedMemo == null || normalizedMemo.isEmpty) return address;
  return '$address?memo=$normalizedMemo';
}

String _formatCountdown(Duration remaining) {
  final totalSeconds = remaining.inSeconds <= 0 ? 0 : remaining.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _compactAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.length <= 18) return trimmed;
  return '${trimmed.substring(0, 9)} ... ${trimmed.substring(trimmed.length - 7)}';
}
