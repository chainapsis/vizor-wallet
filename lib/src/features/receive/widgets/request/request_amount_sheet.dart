/// Mobile "Request ZEC" sheet, in two steps.
///
/// Step one composes the request (amount, optional message); step two is the
/// artefact (QR, summary, link) with the two ways of handing it over. They are
/// separate steps rather than one long sheet because a phone cannot show a
/// scannable QR and a focused numeric keypad at the same time, and because
/// "Create request" is the moment worth confirming — after it, the address in
/// the link is fixed.
///
/// Presentation only: no providers, no routing, no clipboard or share calls.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/amount_price_loading_bar.dart';
import '../../../../core/widgets/app_icon.dart';
import 'request_amount_card.dart'
    show RequestAmountErrorRow, RequestMessageField;
import 'request_amount_formatters.dart';
import 'request_amount_model.dart';
import 'request_qr_surface.dart';

/// The serif amount metrics from the mobile send amount step, mirrored so the
/// two "type an amount" screens are the same screen to a user's eye.
const double _kRequestAmountFontSize = 48;
const double _kRequestAmountLineHeightPx = 40;
const double _kRequestAmountUnitFontSize = 38;
const double _kRequestAmountUsdPrefixFontSize = 40;

/// Side of the QR on the result step.
const double kRequestSheetQrSize = 236;

/// Step one: what you are asking for.
class RequestAmountSheetCompose extends StatelessWidget {
  const RequestAmountSheetCompose({
    required this.request,
    this.onClose,
    this.onToggleAmountUnit,
    this.onAddMessage,
    this.onCreateRequest,
    this.onAmountChanged,
    this.onMessageChanged,
    this.onCloseMessage,
    this.amountController,
    this.messageController,
    this.messageExpanded = false,
    super.key,
  });

  final ZecRequestView request;
  final VoidCallback? onClose;
  final VoidCallback? onToggleAmountUnit;
  final VoidCallback? onAddMessage;
  final VoidCallback? onCreateRequest;
  final ValueChanged<String>? onAmountChanged;
  final ValueChanged<String>? onMessageChanged;

  /// Collapses the memo editor back to [RequestMessageRow].
  final VoidCallback? onCloseMessage;

  /// Supplied by the live sheet, which owns the text so a unit switch can
  /// rewrite the number in place. Without one the amount is a static display,
  /// which is what the previews want.
  final TextEditingController? amountController;
  final TextEditingController? messageController;

  /// Renders the memo editor in place of the collapsed row.
  final bool messageExpanded;

  @override
  Widget build(BuildContext context) {
    final amountError = request.amountError?.trim();

    return MobileModalScaffold(
      title: kRequestFlowTitle,
      onClose: onClose ?? _noop,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          _SerifAmountDisplay(
            request: request,
            controller: amountController,
            onChanged: onAmountChanged,
          ),
          // Said next to where it broke, in the desktop card's words: red
          // digits and a dead CTA state that something is wrong without
          // saying what, and the two causes need opposite corrections.
          if (amountError != null && amountError.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(child: RequestAmountErrorRow(text: amountError)),
          ],
          const SizedBox(height: AppSpacing.s),
          _AmountUnitToggle(
            text: request.conversionText,
            enterUsdMode: !request.amountInputIsUsd,
            onTap: onToggleAmountUnit,
          ),
          const SizedBox(height: AppSpacing.base),
          // A transparent address cannot carry a memo at all, so the row is
          // absent rather than disabled: an inert control invites a tap that
          // can never do anything.
          if (request.isShielded) ...[
            if (messageExpanded)
              RequestMessageField(
                text: request.messageText ?? '',
                controller: messageController,
                onChanged: onMessageChanged,
                onClose: onCloseMessage,
              )
            else
              RequestMessageRow(
                message: request.effectiveMessage,
                onTap: onAddMessage,
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            key: const ValueKey('request_create_button'),
            expand: true,
            constrainContent: true,
            onPressed: request.isReady ? (onCreateRequest ?? _noop) : null,
            child: const Text(
              'Create request',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}

/// Step two: the request itself.
class RequestAmountSheetResult extends StatelessWidget {
  const RequestAmountSheetResult({
    required this.request,
    this.onBack,
    this.onClose,
    this.onShareRequest,
    this.onShareError,
    this.onCopyLink,
    super.key,
  });

  final ZecRequestView request;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  /// Receives the share message and the request QR as PNG bytes, so the
  /// caller can hand a payer both at once — some apps show the picture, some
  /// only carry the link, and a request should survive either.
  final FutureOr<void> Function(String text, Uint8List png)? onShareRequest;

  /// Called when the QR could not be encoded, so the share that never
  /// happened says so instead of looking like one that did.
  final VoidCallback? onShareError;

  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final uri = request.requestUri;
    final summary = request.summaryAmountText;
    final onShare = onShareRequest;

    return MobileModalScaffold(
      title: kRequestFlowTitle,
      onClose: onClose ?? _noop,
      leading: _BackChevron(onTap: onBack),
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: RequestQrSurface(
              data: request.qrData,
              size: kRequestSheetQrSize,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: AppSpacing.sm),
            RequestSummaryRow(
              amountText: summary,
              isShielded: request.isShielded,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          RequestQrExportButton(
            key: const ValueKey('request_share_button'),
            uri: uri,
            label: 'Share request',
            icon: AppIcons.share,
            onBytes: onShare == null
                ? null
                : (png) => onShare(request.shareText ?? uri!, png),
            onError: onShareError,
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            label: 'Copy link',
            excludeSemantics: true,
            child: AppButton(
              key: const ValueKey('request_copy_link_button'),
              variant: AppButtonVariant.secondary,
              expand: true,
              constrainContent: true,
              onPressed: request.isReady ? (onCopyLink ?? _noop) : null,
              child: const Text(
                'Copy link',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}

/// The big serif amount, in the mobile send step's exact type.
class _SerifAmountDisplay extends StatelessWidget {
  const _SerifAmountDisplay({
    required this.request,
    this.controller,
    this.onChanged,
  });

  final ZecRequestView request;

  /// When present the number is a live field; when absent it is text.
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = request.amountError?.trim().isNotEmpty ?? false;
    final text = request.fieldText.trim();
    final amountStyle = AppTypography.displayLarge.copyWith(
      color: hasError
          ? colors.text.destructive
          : text.isEmpty
          ? colors.text.disabled
          : colors.text.accent,
      fontSize: _kRequestAmountFontSize,
      height: _kRequestAmountLineHeightPx / _kRequestAmountFontSize,
      fontWeight: FontWeight.w500,
    );
    final unitStyle = amountStyle.copyWith(
      color: amountStyle.color?.withValues(alpha: 0.5),
      fontSize: _kRequestAmountUnitFontSize,
      height: _kRequestAmountLineHeightPx / _kRequestAmountUnitFontSize,
    );
    final prefixStyle = unitStyle.copyWith(
      fontSize: _kRequestAmountUsdPrefixFontSize,
      height: _kRequestAmountLineHeightPx / _kRequestAmountUsdPrefixFontSize,
    );
    final display = text.isEmpty ? '0' : text;

    return Row(
      key: const ValueKey('request_amount_display'),
      crossAxisAlignment: CrossAxisAlignment.baseline,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (request.amountInputIsUsd) ...[
          Text(r'$', style: prefixStyle),
          const SizedBox(width: AppSpacing.xs),
        ],
        // A long amount shrinks rather than truncating: half a number is
        // worse than a small one. The editable form sizes itself to its text
        // instead, so the unit stays beside the number rather than being
        // pushed to the far edge of the sheet.
        Flexible(
          child: controller == null
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(display, maxLines: 1, style: amountStyle),
                )
              : _SerifAmountInput(
                  controller: controller!,
                  onChanged: onChanged,
                  style: amountStyle,
                  hintStyle: amountStyle.copyWith(color: colors.text.disabled),
                  cursorColor: colors.text.accent,
                  isUsd: request.amountInputIsUsd,
                ),
        ),
        if (!request.amountInputIsUsd) ...[
          const SizedBox(width: AppSpacing.xs),
          Text('ZEC', style: unitStyle),
        ],
      ],
    );
  }
}

/// The amount field behind the serif display: the same type, sized to its own
/// text so the `ZEC` suffix stays attached to the number.
class _SerifAmountInput extends StatelessWidget {
  const _SerifAmountInput({
    required this.controller,
    required this.onChanged,
    required this.style,
    required this.hintStyle,
    required this.cursorColor,
    required this.isUsd,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final TextStyle style;
  final TextStyle hintStyle;
  final Color cursorColor;

  /// Which unit the field is collecting, which is all the formatters need:
  /// dollars stop at cents, ZEC at a zatoshi.
  final bool isUsd;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _kRequestAmountMinWidth),
        child: TextField(
          key: const ValueKey('request_amount_input'),
          controller: controller,
          onChanged: onChanged,
          autofocus: true,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: style,
          cursorColor: cursorColor,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // A comma-decimal keypad emits `,` for the decimal key, which the
          // ZIP-321 builder refuses; without this the field is a dead end on
          // every phone set to such a locale.
          inputFormatters: requestAmountInputFormatters(isUsd: isUsd),
          textInputAction: TextInputAction.done,
          decoration: InputDecoration.collapsed(
            hintText: '0',
            hintStyle: hintStyle,
          ),
        ),
      ),
    );
  }
}

/// Enough width for a single digit plus its caret, so an empty field is still
/// a place to type rather than a hairline.
const double _kRequestAmountMinWidth = 40;

class _AmountUnitToggle extends StatelessWidget {
  const _AmountUnitToggle({
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
    // Without a live price the switch cannot be taken, so it is drawn as the
    // inert control it is — the desktop row already does this, and a
    // full-strength arrow invites a tap that does nothing and says nothing.
    final enabled = onTap != null;
    final labelColor = enabled ? colors.text.secondary : colors.text.disabled;
    return Center(
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
                size: 20,
                color: enabled ? colors.text.secondary : colors.icon.disabled,
              ),
              const SizedBox(width: AppSpacing.xxs),
              // No price for the typed amount yet: the same placeholder the
              // send composer shows, not a number nobody can vouch for.
              if (text == null) ...[
                Text(
                  r'$',
                  style: AppTypography.labelLarge.copyWith(color: labelColor),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const AmountPriceLoadingBar(
                  key: ValueKey('request_amount_price_loading'),
                  animated: true,
                ),
              ] else
                Text(
                  text,
                  key: const ValueKey('request_amount_conversion_text'),
                  style: AppTypography.labelLarge.copyWith(color: labelColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The message row on step one.
///
/// Empty it is the prompt; filled it shows the message it will attach, so the
/// user can see what a payer will read without opening the editor again.
class RequestMessageRow extends StatelessWidget {
  const RequestMessageRow({required this.message, this.onTap, super.key});

  final String? message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = message?.trim();
    final hasMessage = text != null && text.isNotEmpty;

    final row = Container(
      key: const ValueKey('request_message_row'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: colors.surface.input.primary,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          AppIcon(
            AppIcons.scroll,
            size: AppIconSize.medium,
            color: colors.icon.accent,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kRequestAddMessageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (hasMessage) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    text,
                    key: const ValueKey('request_message_preview'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppIcon(
            AppIcons.chevronForward,
            size: AppIconSize.medium,
            color: colors.icon.regular,
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: kRequestAddMessageLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class _BackChevron extends StatelessWidget {
  const _BackChevron({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        key: const ValueKey('request_sheet_back'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.md,
          height: AppSpacing.md,
          child: Center(
            child: AppIcon(
              AppIcons.chevronBackward,
              size: AppIconSize.medium,
              color: colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline sheet presentation used by previews: the scrim plus the bottom-
/// anchored card, without pushing a route.
class RequestAmountSheetSurface extends StatelessWidget {
  const RequestAmountSheetSurface({
    required this.child,
    this.background,
    super.key,
  });

  final Widget child;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        background ?? ColoredBox(color: colors.background.window),
        ColoredBox(color: colors.background.neutralScrim),
        SafeArea(
          bottom: false,
          minimum: const EdgeInsets.only(top: AppSpacing.base),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MobileModalCard(child: child),
          ),
        ),
      ],
    );
  }
}
