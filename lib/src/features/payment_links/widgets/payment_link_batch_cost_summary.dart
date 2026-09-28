import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../send/widgets/send_review_layout.dart';
import '../services/payment_link_service.dart';
import 'payment_link_copy.dart';
import 'payment_link_skeleton.dart';
import 'payment_link_wizard_chrome.dart';

/// What a group costs: **You will spend** while configuring, and the rows
/// and **Total** of the one-card review while reviewing.
class PaymentLinkBatchCostSummary extends StatelessWidget {
  const PaymentLinkBatchCostSummary({
    required this.count,
    required this.amountText,
    required this.messageText,
    required this.spendable,
    required this.quote,
    required this.preparing,
    required this.waitingForSync,
    required this.reviewing,
    required this.error,
    this.onRetry,
    super.key,
  });

  final int count;
  final String amountText;
  final String messageText;
  final BigInt? spendable;
  final PaymentLinkBatchQuote? quote;
  final bool preparing;

  /// The fee waits for wallet sync; shown as pending rather than an error.
  final bool waitingForSync;
  final bool reviewing;
  final String? error;
  final VoidCallback? onRetry;

  TextStyle _labelStyle(BuildContext context) =>
      AppTypography.labelLarge.copyWith(color: context.colors.text.secondary);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewWrapCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._summary(context),
            if (error != null) _errorBlock(context),
          ],
        ),
      ],
    );
  }

  Widget _errorBlock(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            AppIcons.warning,
            size: AppIconSize.medium,
            color: context.colors.icon.destructive,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              error!,
              key: const ValueKey('payment_link_bulk_error'),
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ),
        ],
      ),
      if (onRetry != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton(
            onPressed: onRetry,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            child: const Text('Try again'),
          ),
        ),
      ],
    ],
  );

  List<Widget> _summary(BuildContext context) {
    final colors = context.colors;
    final amount = parseZecAmount(amountText);
    final hasAmount = amount != null && amount > BigInt.zero;
    final redeemFee = BigInt.from(kPaymentLinkClaimFeeReserveZatoshi);
    final perCard = hasAmount ? amount + redeemFee : null;
    final cards = perCard == null ? null : perCard * BigInt.from(count);
    final total = quote?.totalDeductedZatoshi;
    // Only the network fee, and so the total, waits on the quote or on sync.
    final feePending =
        hasAmount &&
        quote == null &&
        error == null &&
        (preparing || waitingForSync);
    final shortfall = spendable == null
        ? null
        : total != null
        ? (total > spendable! ? total - spendable! : null)
        : cards != null && cards > spendable!
        ? cards - spendable!
        : null;
    String money(BigInt? value) =>
        value == null ? '—' : '${formatZecAmount(value)} ZEC';
    Widget caption(String text) => Text(
      text,
      style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
    );

    // A skeleton inside the line box of the text it stands for, so the swap
    // to the real value never changes the height.
    Widget sized(Widget skeleton, TextStyle style) => ExcludeSemantics(
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Opacity(opacity: 0, child: Text('0 ZEC', style: style)),
          skeleton,
        ],
      ),
    );
    final heroStyle = AppTypography.headlineMedium.copyWith(
      color: colors.text.accent,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final shortfallLine = shortfall == null
        ? null
        : _line(
            context,
            'Additional ZEC needed',
            total == null ? 'At least ${money(shortfall)}' : money(shortfall),
            error: true,
          );
    final message = messageText.trim();
    final Widget? feeLoading = !feePending
        ? null
        : waitingForSync
        // Sync can take a while, so say why instead of animating.
        ? Text(
            'Waiting for sync',
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.muted,
            ),
          )
        : Semantics(
            label: 'Calculating network fee',
            child: sized(
              _quoteSkeleton(
                context,
                key: const ValueKey('payment_link_bulk_fee_skeleton'),
                width: 68,
                height: 14,
              ),
              AppTypography.bodyMediumStrong,
            ),
          );
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line(context, 'Per card', money(perCard)),
        caption(
          '${formatZecAmount(amount ?? BigInt.zero)} ZEC + '
          '${formatZecAmount(redeemFee)} ZEC redeem fee',
        ),
        const SizedBox(height: AppSpacing.xs),
        _line(context, '× $count cards', money(cards)),
        const SizedBox(height: AppSpacing.xs),
        _line(
          context,
          'Network fee',
          money(quote?.fundingFeeZatoshi),
          loading: feeLoading,
        ),
        if (reviewing && message.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          // Collapsed to one line so a signing error keeps its room.
          _BatchMessageRows(message: message),
        ],
      ],
    );

    // Review reads like the one-card review: the rows, then the total.
    if (reviewing) {
      return [
        rows,
        const ReviewWrapDivider(),
        Semantics(
          liveRegion: true,
          label: feePending ? 'Calculating total' : null,
          child: _line(
            context,
            kPaymentLinkTotalDeductedLabel,
            money(total),
            emphasis: true,
            loading: feePending
                ? sized(
                    _quoteSkeleton(
                      context,
                      key: const ValueKey('payment_link_bulk_total_skeleton'),
                      width: 96,
                      height: 14,
                    ),
                    AppTypography.bodyMediumStrong,
                  )
                : null,
          ),
        ),
        ?shortfallLine,
      ];
    }

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You will spend', style: _labelStyle(context)),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          liveRegion: true,
          label: feePending ? 'Calculating total' : null,
          child: feePending
              ? sized(
                  _quoteSkeleton(
                    context,
                    key: const ValueKey('payment_link_bulk_total_skeleton'),
                    width: 132,
                    height: 25,
                  ),
                  heroStyle,
                )
              : Text(
                  hasAmount && total != null ? money(total) : '—',
                  style: heroStyle,
                ),
        ),
      ],
    );
    // The rows join once there is an amount to calculate from.
    if (!hasAmount) return [heading];
    return [heading, const ReviewWrapDivider(), rows, ?shortfallLine];
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    bool error = false,
    bool emphasis = false,
    Widget? loading,
  }) {
    final colors = context.colors;
    // The one-card review's rows: a regular label (strong for the total) and
    // a strong value.
    final labelStyle =
        (emphasis ? AppTypography.bodyMediumStrong : AppTypography.bodyMedium)
            .copyWith(
              color: error ? colors.text.destructive : colors.text.secondary,
            );
    final valueStyle = AppTypography.bodyMediumStrong.copyWith(
      color: error ? colors.text.destructive : colors.text.primary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final valueText =
        loading ?? Text(value, style: valueStyle, textAlign: TextAlign.end);
    final icon = error
        ? Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xxs),
            child: AppIcon(
              AppIcons.warning,
              size: AppIconSize.medium,
              color: colors.icon.destructive,
            ),
          )
        : null;
    if (paymentLinkUsesLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ?icon,
              Flexible(child: valueText),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        const SizedBox(width: AppSpacing.xs),
        ?icon,
        valueText,
      ],
    );
  }

  Widget _quoteSkeleton(
    BuildContext context, {
    required Key key,
    required double width,
    required double height,
  }) {
    final color = context.colors.text.secondary;
    return PaymentLinkSkeletonBar(
      key: key,
      width: width,
      height: height,
      colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.26)],
    );
  }
}

/// The message every card carries, expandable like the Send review's memo.
class _BatchMessageRows extends StatefulWidget {
  const _BatchMessageRows({required this.message});

  final String message;

  @override
  State<_BatchMessageRows> createState() => _BatchMessageRowsState();
}

class _BatchMessageRowsState extends State<_BatchMessageRows> {
  var _expanded = false;

  // The list row insets its label and pill by xxs; widening it by the same
  // lines its text up with the plain rows above.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => OverflowBox(
      fit: OverflowBoxFit.deferToChild,
      minWidth: constraints.maxWidth + 2 * AppSpacing.xxs,
      maxWidth: constraints.maxWidth + 2 * AppSpacing.xxs,
      child: ReviewMemoRows(
        label: 'Message on every card',
        memoText: widget.message,
        expanded: _expanded,
        onToggle: () => setState(() => _expanded = !_expanded),
      ),
    ),
  );
}
