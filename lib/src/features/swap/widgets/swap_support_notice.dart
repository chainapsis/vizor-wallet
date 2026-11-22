import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_toast.dart';
import '../models/swap_models.dart';
import '../models/swap_support_details.dart';

export '../models/swap_support_details.dart' show swapNeedsSupportNotice;

/// The existing refund-policy design: a quiet question on Activity, then
/// a pane modal on desktop or the shared modal sheet on mobile.
class SwapSupportPrompt extends StatelessWidget {
  const SwapSupportPrompt({
    required this.onTap,
    required this.failedSwap,
    super.key,
  }) : depositClaimed = false;

  /// The prompt on a timeout whose deposit the user says they sent.
  const SwapSupportPrompt.depositClaimed({required this.onTap, super.key})
    : failedSwap = false,
      depositClaimed = true;

  final VoidCallback onTap;
  final bool failedSwap;
  final bool depositClaimed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    widthFactor: 1,
    child: IntrinsicWidth(
      child: Semantics(
        button: true,
        child: AppButton(
          key: const ValueKey('swap_support_prompt'),
          onPressed: onTap,
          variant: failedSwap
              ? AppButtonVariant.secondary
              : AppButtonVariant.ghost,
          size: AppButtonSize.large,
          height: kAppFormFactor == AppFormFactor.mobile
              ? AppButtonSizing.largeHeight
              : 36,
          growWithContent: true,
          constrainContent: true,
          trailing: const AppIcon(
            AppIcons.arrowForwardIos,
            size: AppIconSize.medium,
          ),
          child: Text(
            depositClaimed
                ? context.l10n.swapTimeoutGetHelp
                : failedSwap
                ? context.l10n.swapSupportFailedPrompt
                : context.l10n.swapSupportExpiredPrompt,
          ),
        ),
      ),
    ),
  );
}

class SwapSupportNotice extends StatefulWidget {
  const SwapSupportNotice({required this.intent, super.key});

  final SwapIntent intent;

  @override
  State<SwapSupportNotice> createState() => _SwapSupportNoticeState();
}

class _SwapSupportNoticeState extends State<SwapSupportNotice> {
  bool _copyFailed = false;

  @override
  void didUpdateWidget(covariant SwapSupportNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intent.id != widget.intent.id) {
      _copyFailed = false;
    }
  }

  Future<void> _copy({bool addressOnly = false}) async {
    final l10n = context.l10n;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: addressOnly
              ? swapSupportEmail
              : swapSupportDetails(l10n, widget.intent),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      // Mobile reports a failed copy with the destructive toast, as Settings
      // does for the viewing key; desktop keeps the inline line.
      if (kAppFormFactor == AppFormFactor.mobile) {
        showAppToast(
          context,
          addressOnly
              ? l10n.swapSupportEmailCopyFailed
              : l10n.swapSupportCopyFailed,
          iconName: AppIcons.warningCircle,
          tone: AppToastTone.destructive,
        );
      } else {
        setState(() => _copyFailed = true);
      }
      return;
    }
    unawaited(AppHaptics.copy());
    if (!mounted) return;
    setState(() => _copyFailed = false);
    showAppToast(
      context,
      addressOnly ? l10n.swapSupportEmailCopied : l10n.swapSupportDetailsCopied,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final failedSwap = widget.intent.status == SwapIntentStatus.failed;
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final title = failedSwap
        ? l10n.swapSupportFailedTitle
        : l10n.swapSupportExpiredTitle;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!mobile) ...[
          Text(
            title,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          failedSwap ? l10n.swapSupportFailedBody : l10n.swapSupportExpiredBody,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          l10n.swapSupportDirectHelp,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          label: l10n.commonCopyAddress,
          child: AppButton(
            key: const ValueKey('swap_support_copy_address'),
            onPressed: () => _copy(addressOnly: true),
            variant: AppButtonVariant.secondary,
            size: mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
            expand: true,
            constrainContent: true,
            growWithContent: true,
            trailing: const AppIcon(AppIcons.copy),
            child: const Text(swapSupportEmail),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Semantics(
          button: true,
          child: AppButton(
            key: const ValueKey('swap_support_copy'),
            onPressed: _copy,
            variant: AppButtonVariant.primary,
            size: mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
            height: mobile ? null : kAppModalButtonHeight,
            expand: true,
            constrainContent: true,
            growWithContent: true,
            trailing: const AppIcon(AppIcons.copy),
            child: Text(l10n.swapSupportCopyAction),
          ),
        ),
        if (_copyFailed) ...[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.swapSupportCopyFailed,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ],
    );
    return KeyedSubtree(
      key: const ValueKey('swap_support_notice'),
      child: mobile
          ? MobileModalScaffold(
              title: title,
              titleMaxLines: 2,
              onClose: () => Navigator.of(context).maybePop(),
              child: content,
            )
          : AppModalCard(child: SingleChildScrollView(child: content)),
    );
  }
}
