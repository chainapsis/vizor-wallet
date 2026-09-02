/// Desktop "Request ZEC" modal.
///
/// Presentation only: every value is a prop, every action is a callback, and
/// nothing here reads a provider or builds a transaction. The live QR is the
/// one thing that computes — it re-encodes whatever [ZecRequestView] currently
/// describes, so the code on screen always matches the link the buttons copy.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/app_modal_card.dart';
import '../../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/zcash/zip321_payment_request_builder.dart';
import 'request_amount_model.dart';
import 'request_qr_surface.dart';

/// Width of the request modal.
///
/// The same 396 the payment request card uses: a request and the request it
/// produces are two halves of one conversation, and they should not arrive in
/// differently sized frames.
const double kRequestModalCardWidth = 396;

/// Side of the QR inside the desktop modal.
const double kRequestModalQrSize = 160;

/// The desktop request modal's body.
///
/// Reading order top to bottom is the order the request is assembled: what you
/// are asking for, what you want to say about it, and only then the artefact
/// the payer receives. The QR sits below its inputs rather than beside them so
/// that it reads as the result of the form, not as a second thing to fill in.
class RequestAmountCard extends StatelessWidget {
  const RequestAmountCard({
    required this.request,
    this.onClose,
    this.onCopyLink,
    this.onSaveQrImage,
    this.onAddMessage,
    this.onToggleAmountUnit,
    this.onAmountChanged,
    this.onMessageChanged,
    this.messageExpanded = false,
    this.amountFocused = false,
    super.key,
  });

  final ZecRequestView request;
  final VoidCallback? onClose;
  final VoidCallback? onCopyLink;

  /// Receives the request QR as PNG bytes. Presentation only: writing the
  /// file is the caller's job.
  final ValueChanged<Uint8List>? onSaveQrImage;
  final VoidCallback? onAddMessage;
  final VoidCallback? onToggleAmountUnit;
  final ValueChanged<String>? onAmountChanged;
  final ValueChanged<String>? onMessageChanged;

  /// Renders the memo editor instead of the collapsed prompt.
  final bool messageExpanded;

  /// Autofocuses the amount field so a static preview shows the focus ring.
  final bool amountFocused;

  bool get _showsMessage => request.isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = request.requestUri;
    final summary = request.summaryAmountText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  kRequestFlowTitle,
                  key: const ValueKey('request_modal_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppIconHoverButton(
              key: const ValueKey('request_modal_close'),
              icon: AppIcons.cross,
              semanticLabel: 'Close request',
              onTap: onClose ?? _noop,
              iconColor: colors.icon.regular,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        RequestAmountField(
          request: request,
          focused: amountFocused,
          onChanged: onAmountChanged,
          onToggleUnit: onToggleAmountUnit,
        ),
        if (_showsMessage) ...[
          const SizedBox(height: AppSpacing.s),
          if (messageExpanded)
            RequestMessageField(
              text: request.messageText ?? '',
              onChanged: onMessageChanged,
            )
          else
            RequestAddMessageCard(onTap: onAddMessage),
        ],
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: RequestQrSurface(
            data: request.qrData,
            size: kRequestModalQrSize,
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: AppSpacing.s),
          RequestSummaryRow(
            amountText: summary,
            isShielded: request.isShielded,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey('request_copy_link_button'),
          expand: true,
          constrainContent: true,
          leading: const AppIcon(AppIcons.copy),
          // Disabled, not hidden: the action the modal exists for should stay
          // visible while the amount is still being typed, so nothing appears
          // to arrive late once the number is valid.
          onPressed: request.isReady ? (onCopyLink ?? _noop) : null,
          child: const Text(
            'Copy request link',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Secondary, under the link: a picture of the request is the fallback
        // for the places a link cannot go — a printed sheet, a slide, a chat
        // that mangles URIs.
        RequestQrExportButton(
          key: const ValueKey('request_save_qr_button'),
          uri: uri,
          label: 'Save QR image',
          icon: AppIcons.arrowDownCircle,
          variant: AppButtonVariant.secondary,
          onBytes: onSaveQrImage,
        ),
      ],
    );
  }

  static void _noop() {}
}

/// The amount input plus the two rows beneath it, mirroring the send
/// composer's amount block minus its Max affordance.
///
/// Max has no meaning in a request: the wallet is not spending, and offering
/// to request your entire balance is not a thing anyone asks for.
class RequestAmountField extends StatelessWidget {
  const RequestAmountField({
    required this.request,
    this.focused = false,
    this.onChanged,
    this.onToggleUnit,
    super.key,
  });

  final ZecRequestView request;
  final bool focused;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onToggleUnit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = request.fieldText;
    final hasText = text.isNotEmpty;
    final error = _trimmedOrNull(request.amountError);
    final isError = error != null;
    final valueColor = isError
        ? colors.text.destructive
        : hasText
        ? colors.text.accent
        : colors.text.muted;
    final affixStyle = AppTypography.labelLarge.copyWith(color: valueColor);
    final iconColor = isError
        ? colors.icon.destructive
        : hasText
        ? colors.icon.accent
        : colors.icon.regular;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          key: const ValueKey('request_amount_field'),
          label: 'Amount',
          labelStyle: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
          initialValue: text,
          hintText: '0.00',
          autofocus: focused,
          tone: isError
              ? AppTextFieldTone.destructive
              : AppTextFieldTone.neutral,
          borderColor: isError ? colors.border.utilityDestructive : null,
          textStyle: AppTypography.labelLarge.copyWith(
            color: isError ? colors.text.destructive : colors.text.accent,
          ),
          hintStyle: AppTypography.labelLarge.copyWith(
            color: isError ? colors.text.destructive : colors.text.muted,
          ),
          leading: AppIcon(
            request.amountInputIsUsd ? AppIcons.moneyBag : AppIcons.zcash,
            size: 20,
            color: iconColor,
          ),
          inlinePrefixText: request.amountInputIsUsd ? r'$' : null,
          inlinePrefixStyle: affixStyle,
          inlineSuffixText: request.amountInputIsUsd ? null : 'ZEC',
          inlineSuffixStyle: affixStyle,
          showClearButton: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xxs),
        if (isError) ...[
          _RequestAmountErrorRow(text: error),
          const SizedBox(height: AppSpacing.xxs),
        ],
        _RequestAmountConversionRow(
          text: request.conversionText,
          enterUsdMode: !request.amountInputIsUsd,
          onTap: onToggleUnit,
        ),
      ],
    );
  }
}

class _RequestAmountErrorRow extends StatelessWidget {
  const _RequestAmountErrorRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.warning, size: 16, color: colors.text.destructive),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            text,
            key: const ValueKey('request_amount_error_text'),
            maxLines: 1,
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

/// The unit switch, which doubles as the converted-value readout — the same
/// control the send composer uses, so the gesture transfers.
class _RequestAmountConversionRow extends StatelessWidget {
  const _RequestAmountConversionRow({
    required this.text,
    required this.enterUsdMode,
    required this.onTap,
  });

  final String? text;
  final bool enterUsdMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: enterUsdMode ? 'Enter amount in USD' : 'Enter amount in ZEC',
        child: GestureDetector(
          key: const ValueKey('request_amount_mode_toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.doubleArrowVertical,
                size: 16,
                color: enabled ? colors.icon.muted : colors.icon.disabled,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                text ?? r'$ 0',
                key: const ValueKey('request_amount_conversion_text'),
                style: AppTypography.labelLarge.copyWith(
                  color: enabled ? colors.text.muted : colors.text.disabled,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The collapsed message prompt — the send composer's memo card, without its
/// fixed height so a translated help line can wrap instead of clipping.
class RequestAddMessageCard extends StatelessWidget {
  const RequestAddMessageCard({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = Container(
      key: const ValueKey('request_add_message_card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface.input.primary,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.scroll, size: 16, color: colors.icon.accent),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  kRequestAddMessageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kRequestMessageHelpText,
            textAlign: TextAlign.center,
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.muted,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: kRequestAddMessageLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}

/// The expanded memo editor with the protocol's own byte counter.
///
/// The counter is bytes, not characters, because that is the limit the memo
/// field actually has — a message that fits on screen can still be over.
class RequestMessageField extends StatelessWidget {
  const RequestMessageField({required this.text, this.onChanged, super.key});

  final String text;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final used = zip321MemoByteLength(text);
    final overLimit = used > kZip321MaxMemoBytes;

    return AppTextField(
      key: const ValueKey('request_message_field'),
      label: 'Message',
      labelStyle: AppTypography.labelLarge.copyWith(
        color: colors.text.secondary,
      ),
      rightSlot: Text(
        '$used/$kZip321MaxMemoBytes',
        key: const ValueKey('request_message_counter'),
        style: AppTypography.labelLarge.copyWith(
          color: overLimit ? colors.text.destructive : colors.text.secondary,
        ),
      ),
      initialValue: text,
      hintText: 'Only the recipient can read this',
      tone: overLimit ? AppTextFieldTone.destructive : AppTextFieldTone.neutral,
      borderColor: overLimit ? colors.border.utilityDestructive : null,
      leading: AppIcon(AppIcons.scroll, size: 20, color: colors.icon.regular),
      messageText: overLimit ? 'Message is too long' : null,
      minLines: 3,
      maxLines: 3,
      textStyle: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
      showClearButton: true,
      clearButtonRequiresText: false,
      clearButtonSemanticLabel: 'Close message',
      onChanged: onChanged,
    );
  }
}

/// Modal chrome for [RequestAmountCard]: the pane scrim plus the centered
/// card, rendered inline so previews do not have to push a route.
class RequestAmountSurface extends StatelessWidget {
  const RequestAmountSurface({
    required this.request,
    this.onClose,
    this.onCopyLink,
    this.onSaveQrImage,
    this.onAddMessage,
    this.onToggleAmountUnit,
    this.messageExpanded = false,
    this.background,
    super.key,
  });

  final ZecRequestView request;
  final VoidCallback? onClose;
  final VoidCallback? onCopyLink;
  final ValueChanged<Uint8List>? onSaveQrImage;
  final VoidCallback? onAddMessage;
  final VoidCallback? onToggleAmountUnit;
  final bool messageExpanded;

  /// What the modal sits on. Defaults to the flat window colour.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        background ?? ColoredBox(color: colors.background.window),
        AppPaneModalOverlay(
          onDismiss: onClose ?? RequestAmountCard._noop,
          // The card is taller with the message editor open than a short
          // window is. It scrolls rather than overflowing, so the primary
          // action stays reachable instead of being clipped off the bottom.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight - AppSpacing.sm * 2
                      : 0,
                ),
                child: Center(
                  child: AppModalCard(
                    width: kRequestModalCardWidth,
                    child: RequestAmountCard(
                      request: request,
                      onClose: onClose,
                      onCopyLink: onCopyLink,
                      onSaveQrImage: onSaveQrImage,
                      onAddMessage: onAddMessage,
                      onToggleAmountUnit: onToggleAmountUnit,
                      messageExpanded: messageExpanded,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
