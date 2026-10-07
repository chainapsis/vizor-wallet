import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import 'payment_link_action.dart';
import 'payment_link_card_motion.dart';
import 'payment_link_claim_checking_content.dart';
import 'payment_link_copy.dart';
import 'payment_link_wizard_chrome.dart';

enum PaymentLinkClaimDesktopState { loading, checking, waiting, ready, outcome }

/// A single scroll stage owns the card throughout preparation and reveal.
class PaymentLinkReceivedDesktopView extends StatelessWidget {
  const PaymentLinkReceivedDesktopView({
    required this.card,
    required this.onBack,
    this.state = PaymentLinkClaimDesktopState.ready,
    this.onClaim,
    this.onRevealMessage,
    this.decoration,
    this.statusContent,
    this.backLabel = 'Cards',
    this.title = 'You’ve received\na gift card!',
    this.messageTitle = kPaymentLinkMessageAttachedTitle,
    this.messageHint = 'Click on the card to reveal',
    this.claimLabel = 'Claim the gift card',
    this.cardActionLabel = kPaymentLinkRevealMessageSemanticLabel,
    this.waitingStatusLabel = 'Checking the gift…',
    this.waitingHeading = 'Your Gift Card\nis almost ready!',
    this.waitingPrimaryText = kPaymentLinkClaimWaitingDescription,
    this.waitingSecondaryText = kPaymentLinkWaitingDescription,
    super.key,
  });

  final Widget card;
  final PaymentLinkClaimDesktopState state;
  final VoidCallback onBack;
  final VoidCallback? onClaim;
  final VoidCallback? onRevealMessage;
  final Widget? decoration;
  final Widget? statusContent;
  final String backLabel;
  final String title;
  final String messageTitle;
  final String messageHint;
  final String claimLabel;
  final String cardActionLabel;
  final String waitingStatusLabel;
  final String waitingHeading;
  final String waitingPrimaryText;
  final String waitingSecondaryText;

  @override
  Widget build(BuildContext context) {
    final ready = state == PaymentLinkClaimDesktopState.ready;
    final checking =
        state == PaymentLinkClaimDesktopState.loading ||
        state == PaymentLinkClaimDesktopState.checking;
    final outcome = state == PaymentLinkClaimDesktopState.outcome;
    final canReveal = ready && onRevealMessage != null;
    final headingStyle = AppTypography.displayLarge.copyWith(
      color: context.colors.text.accent,
    );
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: context.colors.text.secondary,
    );
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 520,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double textHeight(String text, TextStyle style, double maxWidth) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.maybeLocaleOf(context),
                )..layout(maxWidth: maxWidth);
                final height = painter.height;
                painter.dispose();
                return height;
              }

              // Reserve every heading before discovering funding. The original
              // desktop card offset is retained at the default text size.
              final headingHeight = [
                144.0,
                for (final text in [
                  kPaymentLinkClaimCheckingHeading,
                  waitingHeading,
                  title,
                  kPaymentLinkRedeemTheCardTitle,
                ])
                  textHeight(text, headingStyle, width) + AppSpacing.lg,
              ].reduce(math.max);
              final pillHeight = [
                36.0,
                for (final label in [
                  'Checking the gift… 100%',
                  'Wait 3:45 to claim',
                  waitingStatusLabel,
                ])
                  textHeight(label, bodyStyle, math.max(1, width - 44)),
              ].reduce(math.max);
              final detailsHeight = [
                118.0,
                textHeight(
                      kPaymentLinkClaimCheckingDescription,
                      bodyStyle,
                      width,
                    ) +
                    AppSpacing.lg +
                    pillHeight,
                textHeight(
                      waitingPrimaryText,
                      AppTypography.bodyMediumStrong,
                      width,
                    ) +
                    textHeight(waitingSecondaryText, bodyStyle, width) +
                    AppSpacing.lg +
                    pillHeight,
                24 +
                    AppSpacing.xs * 2 +
                    textHeight(
                      messageTitle,
                      AppTypography.bodyMediumStrong,
                      math.min(width, 165),
                    ) +
                    textHeight(messageHint, bodyStyle, math.min(width, 165)),
              ].reduce(math.max);
              final actionHeight = [
                36.0,
                for (final label in ['Claim the gift card', claimLabel])
                  textHeight(
                        label,
                        AppTypography.labelLarge,
                        math.max(1, width - AppSpacing.s * 2),
                      ) +
                      AppSpacing.xxs * 2,
              ].reduce(math.max);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (ready && decoration != null)
                    Positioned.fill(child: decoration!),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 42.5),
                      SizedBox(
                        height: headingHeight,
                        width: double.infinity,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(
                            checking
                                ? kPaymentLinkClaimCheckingHeading
                                : outcome
                                ? kPaymentLinkRedeemTheCardTitle
                                : ready
                                ? title
                                : waitingHeading,
                            textAlign: TextAlign.center,
                            style: headingStyle,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          key: const ValueKey('payment_link_claim_card_slot'),
                          width: PaymentLinkCardMotion.defaultWidth,
                          height: PaymentLinkCardMotion.defaultHeight,
                          child: PaymentLinkAction(
                            key: const ValueKey(
                              'payment_link_reveal_message_action',
                            ),
                            onPressed: canReveal ? onRevealMessage : null,
                            button: canReveal,
                            semanticLabel: canReveal ? cardActionLabel : null,
                            builder: (context, _, focused) =>
                                PaymentLinkActionFocusRing(
                                  focused: focused,
                                  borderRadius: AppRadii.large,
                                  child: PaymentLinkCardMotion(
                                    celebrate: ready,
                                    enableTilt: ready,
                                    child: IgnorePointer(
                                      ignoring: canReveal || !ready,
                                      child: TickerMode(
                                        enabled: !outcome,
                                        child: card,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28.5),
                      ConstrainedBox(
                        constraints: BoxConstraints(minHeight: detailsHeight),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (outcome)
                                statusContent ?? const SizedBox.shrink()
                              else
                                checking
                                    ? PaymentLinkClaimCheckingDetails(
                                        status: PaymentLinkDashedStatusPill(
                                          label: waitingStatusLabel,
                                        ),
                                        statusSpacing: AppSpacing.lg,
                                      )
                                    : !ready
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            waitingPrimaryText,
                                            textAlign: TextAlign.center,
                                            style: AppTypography
                                                .bodyMediumStrong
                                                .copyWith(
                                                  color: context
                                                      .colors
                                                      .text
                                                      .accent,
                                                ),
                                          ),
                                          Text(
                                            waitingSecondaryText,
                                            textAlign: TextAlign.center,
                                            style: bodyStyle,
                                          ),
                                          const SizedBox(height: AppSpacing.lg),
                                          PaymentLinkDashedStatusPill(
                                            label: waitingStatusLabel,
                                          ),
                                        ],
                                      )
                                    : canReveal
                                    ? _messageBlock(context, bodyStyle)
                                    : const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: actionHeight,
                        child: ready
                            ? Center(
                                child: IntrinsicWidth(
                                  child: AppButton(
                                    key: const ValueKey(
                                      'payment_link_claim_button',
                                    ),
                                    onPressed: onClaim,
                                    size: AppButtonSize.mediumLarge,
                                    growWithContent: true,
                                    constrainContent: true,
                                    child: Text(claimLabel),
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _messageBlock(BuildContext context, TextStyle bodyStyle) => SizedBox(
    key: const ValueKey('payment_link_received_message_block'),
    width: 165,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: SvgPicture.asset(
              'assets/illustrations/payment_links/payment_link_envelope.svg',
              key: const ValueKey('payment_link_received_message_icon'),
              width: 20,
              height: 16,
              semanticsLabel: kPaymentLinkGiftMessageLabel,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          messageTitle,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: context.colors.text.brandCrimson,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(messageHint, textAlign: TextAlign.center, style: bodyStyle),
      ],
    ),
  );
}
