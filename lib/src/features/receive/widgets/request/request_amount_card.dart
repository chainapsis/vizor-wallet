/// Desktop "Request ZEC" modal, in two steps.
///
/// Step one composes the request (amount, optional message); step two is the
/// artefact it produces (QR, summary, and the two ways of handing it over).
/// They are separate steps for the same reason the mobile sheet splits them,
/// plus one the desktop window makes sharper: a single card carrying the form
/// *and* a scannable QR is taller than the app's minimum window, so it either
/// overflows or turns the modal into a scrolling page.
///
/// Presentation only: every value is a prop, every action is a callback, and
/// nothing here reads a provider or builds a transaction. The QR on step two
/// is the one thing that computes — it re-encodes whatever [ZecRequestView]
/// describes, so the code on screen always matches the link the buttons copy.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/amount_price_loading_bar.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/app_modal_card.dart';
import '../../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/zcash/zip321_payment_request_builder.dart';
import 'request_amount_formatters.dart';
import 'request_amount_model.dart';
import 'request_qr_surface.dart';

/// Width of the request modal.
///
/// The same 396 the payment request card uses: a request and the request it
/// produces are two halves of one conversation, and they should not arrive in
/// differently sized frames.
const double kRequestModalCardWidth = 396;

/// Width of the result step.
///
/// The result is a QR with two actions under it. At the compose width the
/// buttons stretched far past the code and the frame read as empty, so the
/// step takes the narrowest frame the header (back, title, close) and the
/// action labels fit in, and the code fills that frame edge to edge.
const double kRequestModalResultCardWidth = 288;

/// Side of the QR code itself inside the desktop modal: the result frame
/// minus the modal card's horizontal inset and the code's own white margin,
/// so the surface spans the full content width.
const double kRequestModalQrSize =
    kRequestModalResultCardWidth - AppSpacing.sm * 2 - AppSpacing.sm * 2;

/// Step one: what you are asking for.
///
/// Reading order top to bottom is the order the request is assembled: what you
/// are asking for, what you want to say about it, and then the one action that
/// turns those into a request. Nothing on this step is the request yet, so
/// nothing here shows a QR.
class RequestAmountCard extends StatelessWidget {
  const RequestAmountCard({
    required this.request,
    this.onClose,
    this.onNext,
    this.onAddMessage,
    this.onToggleAmountUnit,
    this.onAmountChanged,
    this.onMessageChanged,
    this.onCloseMessage,
    this.amountController,
    this.messageController,
    this.messageExpanded = false,
    this.amountFocused = false,
    super.key,
  });

  final ZecRequestView request;
  final VoidCallback? onClose;

  /// Advances to [RequestResultCard]. Disabled until the amount is usable.
  final VoidCallback? onNext;
  final VoidCallback? onAddMessage;
  final VoidCallback? onToggleAmountUnit;
  final ValueChanged<String>? onAmountChanged;
  final ValueChanged<String>? onMessageChanged;

  /// Collapses the memo editor back to [RequestAddMessageCard].
  final VoidCallback? onCloseMessage;

  /// Owns the amount text when the caller needs to rewrite it — switching
  /// units replaces the number in place, which a field holding its own
  /// initial value cannot do.
  final TextEditingController? amountController;

  /// Owns the message text, for the same reason.
  final TextEditingController? messageController;

  /// Renders the memo editor instead of the collapsed prompt.
  final bool messageExpanded;

  /// Autofocuses the amount field so a static preview shows the focus ring.
  final bool amountFocused;

  bool get _showsMessage => request.isShielded;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestModalHeader(onClose: onClose),
        const SizedBox(height: AppSpacing.sm),
        RequestAmountField(
          request: request,
          focused: amountFocused,
          controller: amountController,
          onChanged: onAmountChanged,
          onToggleUnit: onToggleAmountUnit,
        ),
        if (_showsMessage) ...[
          const SizedBox(height: AppSpacing.s),
          if (messageExpanded)
            RequestMessageField(
              text: request.messageText ?? '',
              controller: messageController,
              onChanged: onMessageChanged,
              onClose: onCloseMessage,
            )
          else
            RequestAddMessageCard(onTap: onAddMessage),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey('request_next_button'),
          expand: true,
          constrainContent: true,
          // Disabled, not hidden: the step's one action stays visible while
          // the amount is still being typed, so nothing appears to arrive
          // late once the number is valid.
          onPressed: request.isReady ? (onNext ?? _noop) : null,
          // The same label the mobile sheet uses: one commitment should not
          // have two names, and this press is the moment the address in the
          // link is fixed — worth naming rather than pointing at.
          child: const Text(
            'Create request',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static void _noop() {}
}

/// Step two: the request itself.
///
/// The QR, what it is asking for, and the two ways of handing it over. The
/// back chevron returns to step one with the composed amount and message
/// intact — this step edits nothing, it only publishes.
class RequestResultCard extends StatelessWidget {
  const RequestResultCard({
    required this.request,
    this.onBack,
    this.onClose,
    this.onCopyLink,
    this.onSaveQrImage,
    this.onSaveQrImageError,
    super.key,
  });

  final ZecRequestView request;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final VoidCallback? onCopyLink;

  /// Receives the request QR as PNG bytes. Presentation only: writing the
  /// file is the caller's job.
  final ValueChanged<Uint8List>? onSaveQrImage;

  /// Called when the QR could not be encoded at all, so the press is
  /// reported rather than swallowed.
  final VoidCallback? onSaveQrImageError;

  @override
  Widget build(BuildContext context) {
    final uri = request.requestUri;
    final summary = request.summaryAmountText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RequestModalHeader(onBack: onBack, onClose: onClose),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: RequestQrSurface(
            data: request.qrData,
            size: kRequestModalQrSize,
            padding: AppSpacing.sm,
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
          onError: onSaveQrImageError,
        ),
      ],
    );
  }

  static void _noop() {}
}

/// The title row both steps share: one title for the whole flow, the step's
/// own back affordance on the left when there is somewhere to go back to, and
/// the modal's ⨯ pinned right.
class RequestModalHeader extends StatelessWidget {
  const RequestModalHeader({this.onBack, this.onClose, super.key});

  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onBack = this.onBack;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          AppIconHoverButton(
            key: const ValueKey('request_modal_back'),
            icon: AppIcons.chevronBackward,
            semanticLabel: 'Back',
            onTap: onBack,
            iconColor: colors.icon.accent,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
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
          onTap: onClose ?? RequestAmountCard._noop,
          iconColor: colors.icon.regular,
        ),
      ],
    );
  }
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
    this.controller,
    this.onChanged,
    this.onToggleUnit,
    super.key,
  });

  final ZecRequestView request;
  final bool focused;
  final TextEditingController? controller;
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
          controller: controller,
          initialValue: controller == null ? text : null,
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
          // A desktop keyboard can type — and a paste can deliver — anything
          // at all, so the field refuses what a ZIP-321 amount cannot be
          // rather than letting the CTA go dead over it.
          inputFormatters: requestAmountInputFormatters(
            isUsd: request.amountInputIsUsd,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xxs),
        if (isError) ...[
          RequestAmountErrorRow(text: error),
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

/// The inline amount error: the warning glyph and the correction to make.
///
/// Public because the mobile sheet renders the same pair under its serif
/// amount — the two lanes read the identical draft, so they should say the
/// identical thing when it cannot be turned into a request.
class RequestAmountErrorRow extends StatelessWidget {
  const RequestAmountErrorRow({required this.text, super.key});

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
    final text = this.text;
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
              // No price for the typed amount yet: the same placeholder the
              // send composer shows, not a number nobody can vouch for.
              if (text == null) ...[
                Text(
                  r'$',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const AmountPriceLoadingBar(
                  key: ValueKey('request_amount_price_loading'),
                ),
              ] else
                Text(
                  text,
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
  const RequestMessageField({
    required this.text,
    this.controller,
    this.onChanged,
    this.onClose,
    super.key,
  });

  final String text;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  /// Collapses the editor back to the prompt. The clear button announces
  /// itself as "Close message", so it has to actually close it — emptying the
  /// text and leaving the editor open is not the action the label names.
  final VoidCallback? onClose;

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
      controller: controller,
      initialValue: controller == null ? text : null,
      hintText: 'Anyone you send the link to can read this',
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
      onClear: onClose,
      onChanged: onChanged,
    );
  }
}

/// Modal chrome for the desktop request steps: the pane scrim plus the
/// centered card, rendered inline so previews do not have to push a route.
class RequestAmountSurface extends StatelessWidget {
  const RequestAmountSurface({
    required this.request,
    this.step = RequestModalStep.compose,
    this.onClose,
    this.onNext,
    this.onBack,
    this.onCopyLink,
    this.onSaveQrImage,
    this.onSaveQrImageError,
    this.onAddMessage,
    this.onToggleAmountUnit,
    this.onAmountChanged,
    this.onMessageChanged,
    this.onCloseMessage,
    this.amountController,
    this.messageController,
    this.messageExpanded = false,
    this.background,
    super.key,
  });

  final ZecRequestView request;

  /// Which of the two cards is on screen.
  final RequestModalStep step;

  final VoidCallback? onClose;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final VoidCallback? onCopyLink;
  final ValueChanged<Uint8List>? onSaveQrImage;
  final VoidCallback? onSaveQrImageError;
  final VoidCallback? onAddMessage;
  final VoidCallback? onToggleAmountUnit;
  final ValueChanged<String>? onAmountChanged;
  final ValueChanged<String>? onMessageChanged;
  final VoidCallback? onCloseMessage;
  final TextEditingController? amountController;
  final TextEditingController? messageController;
  final bool messageExpanded;

  /// What the modal sits on. Defaults to the flat window colour.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = switch (step) {
      RequestModalStep.compose => RequestAmountCard(
        request: request,
        onClose: onClose,
        onNext: onNext,
        onAddMessage: onAddMessage,
        onToggleAmountUnit: onToggleAmountUnit,
        onAmountChanged: onAmountChanged,
        onMessageChanged: onMessageChanged,
        onCloseMessage: onCloseMessage,
        amountController: amountController,
        messageController: messageController,
        messageExpanded: messageExpanded,
      ),
      RequestModalStep.result => RequestResultCard(
        request: request,
        onBack: onBack,
        onClose: onClose,
        onCopyLink: onCopyLink,
        onSaveQrImage: onSaveQrImage,
        onSaveQrImageError: onSaveQrImageError,
      ),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        background ?? ColoredBox(color: colors.background.window),
        AppPaneModalOverlay(
          onDismiss: onClose ?? RequestAmountCard._noop,
          // Either step fits the app's minimum window on its own. The scroll
          // view is the floor under a bigger text scale or a translation that
          // wraps: the card grows into a scroll rather than into overflow.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight.isFinite
                      ? math.max(0, constraints.maxHeight - AppSpacing.sm * 2)
                      : 0,
                ),
                child: Center(
                  child: AppModalCard(
                    width: step == RequestModalStep.result
                        ? kRequestModalResultCardWidth
                        : kRequestModalCardWidth,
                    child: card,
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
