/// Mobile "Request ZEC" page, in two steps.
///
/// Step one composes the request (amount in Pay's card, an optional message
/// from Send's message sheet); step two is the artefact (QR, amount, link)
/// with the two ways of handing it over. They are
/// separate steps rather than one long page because a phone cannot show a
/// scannable QR and a focused numeric keypad at the same time, and because
/// "Create request" is the moment worth confirming — after it, the address in
/// the link is fixed.
///
/// Each step is a whole page body (header, content, bottom actions) laid out
/// like Pay's steps; `MobileReceiveRequestScreen` supplies the scaffold.
///
/// Presentation only: no providers, no routing, no clipboard or share calls.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart'
    show InputDecoration, Scaffold, TextField;
import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';

import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/mobile_sticky_bottom_action.dart'
    show kMobileFooterGap;
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/amount_price_loading_bar.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_amount_card.dart';
import '../../../../core/widgets/mobile/mobile_serif_amount.dart';
import '../../../../core/widgets/pool_badge.dart';
import '../../../../core/feedback/app_haptics.dart';
import 'request_amount_card.dart' show RequestAmountErrorRow;
import 'request_amount_formatters.dart';
import 'request_amount_model.dart';
import 'request_qr_surface.dart';

/// Side of the QR on the result step.
const double kRequestQrSize = 236;

/// Step one: what you are asking for.
class RequestAmountComposeStep extends StatelessWidget {
  const RequestAmountComposeStep({
    required this.request,
    this.onBack,
    this.onToggleAmountUnit,
    this.onAddMessage,
    this.onCreateRequest,
    this.onAmountChanged,
    this.amountController,
    this.amountFocusNode,
    super.key,
  });

  final ZecRequestView request;

  /// Leaves the page. Without one the header's back pops the route.
  final VoidCallback? onBack;
  final VoidCallback? onToggleAmountUnit;

  /// Opens the message sheet (Send's memo sheet).
  final VoidCallback? onAddMessage;
  final VoidCallback? onCreateRequest;
  final ValueChanged<String>? onAmountChanged;

  /// Supplied by the live page, which owns the text so a unit switch can
  /// rewrite the number in place. Without one the amount is a static display,
  /// which is what the previews want.
  final TextEditingController? amountController;

  /// Supplied by the live page so it can raise the keyboard once the page
  /// has opened. Without one the field autofocuses.
  final FocusNode? amountFocusNode;

  @override
  Widget build(BuildContext context) {
    final amountError = request.amountError?.text(context.l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileTopNav.back(
          title: requestFlowTitle(context.l10n),
          onBack: onBack,
        ),
        // A raised keyboard on a short phone can leave less room than the
        // card and the message line need. They scroll so the action stays
        // above the keyboard.
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('request_compose_fields'),
            padding: const EdgeInsets.fromLTRB(
              kMobilePageMargin,
              AppSpacing.sm,
              kMobilePageMargin,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Pay's amount card, without an asset to pick.
                MobileAmountCard(
                  key: const ValueKey('request_amount_card'),
                  amount: _SerifAmountDisplay(
                    request: request,
                    controller: amountController,
                    focusNode: amountFocusNode,
                    onChanged: onAmountChanged,
                  ),
                  conversion: _AmountUnitToggle(
                    text: request.conversionText,
                    enterUsdMode: !request.amountInputIsUsd,
                    onTap: onToggleAmountUnit,
                  ),
                ),
                // Said next to where it broke, in the desktop card's words:
                // red digits and a dead CTA state that something is wrong
                // without saying what, and the two causes need opposite
                // corrections.
                if (amountError != null && amountError.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s),
                  Center(child: RequestAmountErrorRow(text: amountError)),
                ],
                // A transparent address cannot carry a memo at all, so the
                // line is absent rather than disabled: an inert control
                // invites a tap that can never do anything.
                if (request.isShielded) ...[
                  const SizedBox(height: AppSpacing.md),
                  RequestMessageLine(
                    message: request.effectiveMessage,
                    onTap: onAddMessage,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kMobilePageMargin,
            AppSpacing.s,
            kMobilePageMargin,
            kMobileFooterGap,
          ),
          child: AppButton(
            key: const ValueKey('request_create_button'),
            expand: true,
            constrainContent: true,
            onPressed: request.isReady ? (onCreateRequest ?? _noop) : null,
            child: Text(
              context.l10n.receiveRequestCreate,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  static void _noop() {}
}

/// Step two: the request itself.
class RequestAmountResultStep extends StatelessWidget {
  const RequestAmountResultStep({
    required this.request,
    this.onBack,
    this.onShareRequest,
    this.onShareError,
    this.onCopyLink,
    super.key,
  });

  final ZecRequestView request;

  /// Returns to step one with the draft intact.
  final VoidCallback? onBack;

  /// Receives the request QR as PNG bytes for a single-image share.
  final FutureOr<void> Function(Uint8List png)? onShareRequest;

  /// Called when the QR could not be encoded, so the share that never
  /// happened says so instead of looking like one that did.
  final VoidCallback? onShareError;

  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final uri = request.requestUri;
    final amount = request.summaryZecAmount;
    final onShare = onShareRequest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileTopNav.back(
          title: requestFlowTitle(context.l10n),
          onBack: onBack,
        ),
        // The QR and the amount it asks for sit together in the middle of
        // the room between the header and the buttons, and scroll only when
        // a short phone or large text leaves too little of it.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              key: const ValueKey('request_result_body'),
              padding: const EdgeInsets.symmetric(
                horizontal: kMobilePageMargin,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      RequestQrSurface(
                        data: request.qrData,
                        size: kRequestQrSize,
                      ),
                      if (amount != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _RequestHeroAmount(amount: amount),
                        const SizedBox(height: AppSpacing.xs),
                        PoolBadge(isShielded: request.isShielded),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kMobilePageMargin,
            AppSpacing.s,
            kMobilePageMargin,
            kMobileFooterGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RequestQrExportButton(
                key: const ValueKey('request_share_button'),
                uri: uri,
                label: context.l10n.receiveRequestShare,
                icon: AppIcons.share,
                onBytes: onShare,
                onError: onShareError,
              ),
              const SizedBox(height: AppSpacing.s),
              Semantics(
                button: true,
                label: context.l10n.commonCopyLink,
                excludeSemantics: true,
                child: AppButton(
                  key: const ValueKey('request_copy_link_button'),
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  constrainContent: true,
                  onPressed: request.isReady ? (onCopyLink ?? _noop) : null,
                  child: Text(
                    context.l10n.commonCopyLink,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static void _noop() {}
}

/// The requested amount under the QR, in the Home balance card's serif. A
/// long amount shrinks to fit between the page margins.
class _RequestHeroAmount extends StatelessWidget {
  const _RequestHeroAmount({required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.text.accent;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        key: const ValueKey('request_summary_amount'),
        TextSpan(
          children: [
            TextSpan(
              text: '$amount ',
              style: kMobileSerifAmountStyle.copyWith(color: color),
            ),
            TextSpan(
              text: kZcashDefaultCurrencyTicker,
              style: kMobileSerifTickerStyle.copyWith(color: color),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

/// The amount in Pay's card type: Young Serif at `displayLarge`, its unit at
/// 38 and half strength.
class _SerifAmountDisplay extends StatelessWidget {
  const _SerifAmountDisplay({
    required this.request,
    this.controller,
    this.focusNode,
    this.onChanged,
  });

  final ZecRequestView request;

  /// When present the number is a live field; when absent it is text.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = request.amountError != null;
    final text = request.fieldText.trim();
    final amountStyle = AppTypography.displayLarge.copyWith(
      color: hasError ? colors.text.destructive : colors.text.accent,
    );
    final hintStyle = amountStyle.copyWith(color: colors.text.muted);
    final unitStyle = amountStyle.copyWith(
      color: amountStyle.color?.withValues(alpha: 0.5),
      fontSize: _kRequestAmountUnitFontSize,
      height: _kRequestAmountUnitLineHeightPx / _kRequestAmountUnitFontSize,
    );
    final prefixStyle = unitStyle;
    return Center(
      child: Row(
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
          // pushed to the far edge of the page.
          Flexible(
            child: controller == null
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: text.isEmpty
                        ? Text('0', maxLines: 1, style: hintStyle)
                        : Text(text, maxLines: 1, style: amountStyle),
                  )
                : _SerifAmountInput(
                    controller: controller!,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    style: amountStyle,
                    hintStyle: hintStyle,
                    cursorColor: colors.text.accent,
                    isUsd: request.amountInputIsUsd,
                  ),
          ),
          if (!request.amountInputIsUsd) ...[
            const SizedBox(width: AppSpacing.xs),
            Text('ZEC', style: unitStyle), // l10n-ignore: currency code
          ],
        ],
      ),
    );
  }
}

/// Pay's unit type beside the amount.
const double _kRequestAmountUnitFontSize = 38;
const double _kRequestAmountUnitLineHeightPx = 40;

/// The amount field behind the serif display: the same type, sized to its own
/// text so the `ZEC` suffix stays attached to the number.
class _SerifAmountInput extends StatelessWidget {
  const _SerifAmountInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.style,
    required this.hintStyle,
    required this.cursorColor,
    required this.isUsd,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
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
          focusNode: focusNode,
          onChanged: onChanged,
          autofocus: focusNode == null,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: style,
          cursorColor: cursorColor,
          cursorWidth: 3,
          cursorRadius: const Radius.circular(AppRadii.full),
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
        label: enterUsdMode
            ? context.l10n.commonEnterAmountInUsd
            : context.l10n.receiveRequestEnterZec,
        child: GestureDetector(
          key: const ValueKey('request_amount_mode_toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  unawaited(AppHaptics.selection());
                  onTap!();
                },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.doubleArrowVertical,
                size: 20,
                color: enabled ? colors.icon.regular : colors.icon.disabled,
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

/// The message line under the amount card on step one.
///
/// Empty it is the prompt; filled it shows the message it will attach, so the
/// user can see what a payer will read without opening the sheet again. A tap
/// opens the message sheet either way.
class RequestMessageLine extends StatelessWidget {
  const RequestMessageLine({required this.message, this.onTap, super.key});

  final String? message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = message?.trim();
    final hasMessage = text != null && text.isNotEmpty;
    final style = AppTypography.labelLarge.copyWith(color: colors.text.accent);

    final line = ConstrainedBox(
      key: const ValueKey('request_message_row'),
      // A comfortable tap target around a single line of text.
      constraints: const BoxConstraints(minHeight: 44),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: hasMessage
              ? [
                  Flexible(
                    child: Text(
                      text,
                      key: const ValueKey('request_message_preview'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: style,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  AppIcon(
                    AppIcons.expand,
                    size: AppIconSize.medium,
                    color: colors.icon.muted,
                  ),
                ]
              : [Text(context.l10n.commonAddAMessage, style: style)],
        ),
      ),
    );

    if (onTap == null) return line;
    return Semantics(
      button: true,
      label: hasMessage
          ? context.l10n.commonMessage
          : context.l10n.commonAddAMessage,
      value: hasMessage ? text : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: line,
      ),
    );
  }
}

/// The page presentation used by previews: a step in the same scaffold
/// `MobileReceiveRequestScreen` gives it (window background, safe area, room
/// made for the keyboard), without pushing a route.
class RequestAmountPreviewPage extends StatelessWidget {
  const RequestAmountPreviewPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: SafeArea(child: child),
    );
  }
}
