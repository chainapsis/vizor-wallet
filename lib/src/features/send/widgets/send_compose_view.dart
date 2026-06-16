import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';

/// Recipient address type used to choose the leading icon.
///
/// The wallet always spends from the shielded pool (sapling + orchard), so
/// the spend source does not need a separate field-level caption.
enum SendPoolRoute {
  /// No address entered yet.
  unknown,

  /// Recipient is a unified/sapling (shielded) address.
  shieldedToShielded,

  /// Recipient is a transparent address; memo is unavailable.
  shieldedToTransparent,
}

/// How the memo area is presented.
enum SendMemoMode {
  /// Collapsed "Add a memo" prompt card (shielded recipient, no memo yet).
  prompt,

  /// Expanded multi-line message field with a character counter.
  expanded,

  /// Recipient is transparent or not yet valid, so memo controls are hidden.
  transparentUnavailable,
}

/// Presentational, state-driven layout for the **Send** compose screen.
///
/// This widget owns no wallet/business logic — it renders a snapshot of the
/// compose form from immutable props so the layout and visual states can be
/// validated in Widgetbook before it is wired into `send_screen.dart`.
/// Callbacks are optional and default to no-ops in previews.
///
/// Validation and memo over-limit errors ride on [AppTextField.messageText] +
/// [AppTextField.tone].
class SendComposeView extends StatelessWidget {
  const SendComposeView({
    super.key,
    this.title = 'Send ZEC',
    this.recipientText = '',
    this.recipientHint = 'Zcash address',
    this.route = SendPoolRoute.unknown,
    this.amountText = '',
    this.amountHint = '0.00',
    this.maxLabel = 'Max: 150 ZEC',
    this.amountFocused = false,
    this.amountError,
    this.memoMode = SendMemoMode.prompt,
    this.memoText = '',
    this.memoHint = 'Add a message',
    this.memoCounter = '512/512',
    this.memoError,
    this.reviewEnabled = false,
    this.onReview,
    this.onContactsPressed,
    this.onAddMemo,
    this.formWidth = 396,
    this.contentWidth = 420,
    this.reviewButtonWidth = 196,
  });

  /// Serif page title. Defaults to the Figma copy `Send ZEC`; the live
  /// screen can thread the network-scoped currency ticker.
  final String title;

  // Recipient ("Send to") field.
  final String recipientText;
  final String recipientHint;
  final SendPoolRoute route;

  // Amount field.
  final String amountText;
  final String amountHint;
  final String maxLabel;

  /// Autofocuses the amount field so the focus ring is visible in static
  /// previews of the "amount entered" states.
  final bool amountFocused;
  final String? amountError;

  // Memo / message area.
  final SendMemoMode memoMode;
  final String memoText;
  final String memoHint;
  final String memoCounter;
  final String? memoError;

  // Primary CTA.
  final bool reviewEnabled;
  final VoidCallback? onReview;
  final VoidCallback? onContactsPressed;
  final VoidCallback? onAddMemo;

  final double formWidth;
  final double contentWidth;
  final double reviewButtonWidth;

  // Reserved space for the message overlay that AppTextField paints just below
  // each field. Mirrors the current send screen's spacing so the compose
  // layout stays vertically balanced.
  static const _overlayReserve = 20.0;
  static const _fieldGap = AppSpacing.xs;
  static const _multilineOverlayReserve = 24.0;
  static const _containerHorizontalPadding = AppSpacing.s;
  static const _containerVerticalPadding = AppSpacing.md;
  static const _sectionGap = 32.0;
  static const _fieldsVerticalPadding = AppSpacing.xs;

  bool get _expanded => memoMode == SendMemoMode.expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _recipientField(context),
        const SizedBox(height: _overlayReserve),
        const SizedBox(height: _fieldGap),
        _amountField(context),
        const SizedBox(height: _overlayReserve),
        const SizedBox(height: _fieldGap),
        _memo(context),
        if (_expanded) const SizedBox(height: _multilineOverlayReserve),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final minHeight = height == null
            ? 0.0
            : height < (_containerVerticalPadding * 2)
            ? 0.0
            : height - (_containerVerticalPadding * 2);

        return Center(
          child: SizedBox(
            width: contentWidth,
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _containerHorizontalPadding,
                vertical: _containerVerticalPadding,
              ),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: _sectionGap),
                      SizedBox(
                        width: formWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: _fieldsVerticalPadding,
                          ),
                          child: fields,
                        ),
                      ),
                      const SizedBox(height: _sectionGap),
                      SizedBox(
                        width: reviewButtonWidth,
                        child: AppButton(
                          key: const ValueKey('send_review_button'),
                          onPressed: reviewEnabled ? (onReview ?? _noop) : null,
                          variant: AppButtonVariant.primary,
                          minWidth: reviewButtonWidth,
                          trailing: const AppIcon(AppIcons.chevronForward),
                          child: const Text('Review'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _recipientField(BuildContext context) {
    final colors = context.colors;
    final hasText = recipientText.isNotEmpty;

    final leadingName = switch (route) {
      SendPoolRoute.unknown => AppIcons.plane,
      SendPoolRoute.shieldedToShielded => AppIcons.shieldKeyhole,
      SendPoolRoute.shieldedToTransparent => AppIcons.transparentBalance,
    };
    final leadingColor = switch (route) {
      SendPoolRoute.unknown =>
        hasText ? colors.icon.accent : colors.icon.regular,
      SendPoolRoute.shieldedToShielded => colors.icon.brandCrimson,
      SendPoolRoute.shieldedToTransparent => colors.icon.muted,
    };
    return AppTextField(
      key: const ValueKey('send_address_field'),
      label: 'Send to',
      rightSlot: _SendRecipientLink(onTap: onContactsPressed),
      initialValue: recipientText,
      hintText: recipientHint,
      leading: AppIcon(leadingName, size: 20, color: leadingColor),
      showClearButton: true,
      keyboardType: TextInputType.text,
    );
  }

  Widget _amountField(BuildContext context) {
    final colors = context.colors;
    final hasText = amountText.isNotEmpty;
    final isError = amountError != null && amountError!.trim().isNotEmpty;

    return AppTextField(
      key: const ValueKey('send_amount_field'),
      label: 'Amount',
      rightLabel: maxLabel,
      initialValue: amountText,
      hintText: amountHint,
      autofocus: amountFocused,
      tone: isError ? AppTextFieldTone.destructive : AppTextFieldTone.neutral,
      leading: AppIcon(
        AppIcons.zcash,
        size: 20,
        color: hasText ? colors.icon.accent : colors.icon.regular,
      ),
      messageText: isError ? amountError : null,
      showClearButton: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }

  Widget _memo(BuildContext context) {
    switch (memoMode) {
      case SendMemoMode.prompt:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: _SendAddMemoCard(onTap: onAddMemo),
        );
      case SendMemoMode.transparentUnavailable:
        return const SizedBox.shrink();
      case SendMemoMode.expanded:
        final colors = context.colors;
        final isError = memoError != null && memoError!.trim().isNotEmpty;
        return AppTextField(
          key: const ValueKey('send_memo_field'),
          label: 'Message',
          rightSlot: Text(
            memoCounter,
            style: AppTypography.labelMedium.copyWith(
              color: isError ? colors.text.destructive : colors.text.secondary,
            ),
          ),
          initialValue: memoText,
          hintText: memoHint,
          tone: isError
              ? AppTextFieldTone.destructive
              : AppTextFieldTone.neutral,
          leading: AppIcon(
            AppIcons.users,
            size: 20,
            color: colors.icon.regular,
          ),
          messageText: isError ? memoError : null,
          minLines: 6,
          maxLines: 6,
          textStyle: AppTypography.bodyMedium.copyWith(
            color: colors.text.accent,
          ),
          showClearButton: true,
          clearButtonRequiresText: false,
          clearButtonSemanticLabel: 'Close message',
        );
    }
  }

  static void _noop() {}
}

/// Right-hand "Send to" affordance for opening the contact picker.
class _SendRecipientLink extends StatelessWidget {
  const _SendRecipientLink({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Contacts',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(width: 2),
          AppIcon(
            AppIcons.chevronForward,
            size: 12,
            color: colors.text.secondary,
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: 'Open contacts',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('send_contacts_button'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: row,
        ),
      ),
    );
  }
}

/// Collapsed memo prompt: a tappable card inviting the user to attach an
/// encrypted message. When [onTap] is null the card renders inert (the
/// transparent-recipient "memo unavailable" presentation).
class _SendAddMemoCard extends StatelessWidget {
  const _SendAddMemoCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = Container(
      key: const ValueKey('send_add_memo_card'),
      width: double.infinity,
      height: 128,
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: _sendInputSurfaceShadow(colors),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.scroll, size: 16, color: colors.icon.accent),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Add a memo',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Encrypted, for shielded addresses only.',
            textAlign: TextAlign.center,
            style: AppTypography.labelMedium.copyWith(color: colors.text.muted),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

List<BoxShadow> _sendInputSurfaceShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
  ];
}
