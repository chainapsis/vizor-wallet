import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_wrap_card.dart';
import 'payment_link_batch_deck.dart';
import 'payment_link_cards_layout.dart';
import 'payment_link_confirm_modal.dart';
import 'payment_link_gift_card.dart';
import 'payment_link_wizard_chrome.dart';

/// Why a batch is not shareable yet.
enum PaymentLinkBatchPendingKind {
  /// The funding transaction was accepted; its confirmation is still loading.
  confirming,

  /// The broadcast result is unknown, so the batch must not be created again.
  unconfirmedBroadcast,

  /// Some members are missing or not funded.
  incomplete,
}

/// The one place a batch reports card-use checking, instead of every card.
/// Checks run on their own, so there is no manual action.
class PaymentLinkBatchUsageActivity {
  const PaymentLinkBatchUsageActivity({
    this.checking = false,
    this.failed = false,
    this.checkedText,
  });

  final bool checking;
  final bool failed;

  /// For example "Checked 2m ago"; null before the first check.
  final String? checkedText;
}

/// The place to manage and share the individual cards in a batch.
///
/// On a roomy pane the summary stays put on the left and only the card list
/// scrolls on the right, grouped by use like the created-card list. Narrow
/// panes and large text stack the two and let the pane scroll.
class PaymentLinkBatchDetailDesktopView extends StatelessWidget {
  const PaymentLinkBatchDetailDesktopView({
    required this.count,
    required this.artwork,
    required this.amountPerCardText,
    required this.dateText,
    required this.ready,
    required this.onBack,
    this.backArtworks = const [],
    this.sections = const [],
    this.onExport,
    this.onCheckStatus,
    this.usageActivity = const PaymentLinkBatchUsageActivity(),
    this.pendingKind = PaymentLinkBatchPendingKind.unconfirmedBroadcast,
    this.justCreated = false,
    super.key,
  });

  static const _summaryWidth = 280.0;

  final int count;
  final PaymentLinkCardArtwork artwork;

  /// The designs behind the front card when the group mixes designs.
  final List<PaymentLinkCardArtwork> backArtworks;
  final String amountPerCardText;

  /// When the batch was created, for example "September 23".
  final String dateText;
  final bool ready;
  final VoidCallback onBack;

  /// Use groups in display order; empty groups are skipped.
  final List<PaymentLinkCardsSection> sections;
  final VoidCallback? onExport;
  final VoidCallback? onCheckStatus;
  final PaymentLinkBatchUsageActivity usageActivity;
  final PaymentLinkBatchPendingKind pendingKind;
  final bool justCreated;

  @override
  Widget build(BuildContext context) => PaymentLinkPane(
    backLabel: 'Gift Cards',
    onBack: onBack,
    // Above the Align, which would loosen the pane's visible-height minimum.
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 880.0);
        final split =
            !paymentLinkUsesLargeText(context) &&
            width >= 640 &&
            constraints.minHeight >= 360;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: split ? constraints.minHeight : null,
            child: split ? _split(context) : _stacked(context),
          ),
        );
      },
    ),
  );

  // No right padding: the card list keeps it as its scrollbar's gutter.
  Widget _split(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s,
      AppSpacing.xs,
      0,
      AppSpacing.sm,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _summaryWidth,
          child: _summary(context, showDeck: true),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _cardList(context, scrollable: true)),
      ],
    ),
  );

  Widget _stacked(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s,
      AppSpacing.xs,
      AppSpacing.s,
      AppSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summary(context, showDeck: false),
        const SizedBox(height: AppSpacing.sm),
        _cardList(context, scrollable: false),
      ],
    ),
  );

  Widget _summary(BuildContext context, {required bool showDeck}) {
    final colors = context.colors;
    final largeText = paymentLinkUsesLargeText(context);
    return ReviewWrapCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDeck)
          AspectRatio(
            aspectRatio:
                PaymentLinkBatchDeck.width / PaymentLinkBatchDeck.height,
            child: PaymentLinkBatchDeck(
              backArtworks: backArtworks,
              card: PaymentLinkGiftCard(
                artwork: artwork,
                amountText: amountPerCardText,
                showCaret: false,
              ),
              count: count,
              playReveal: justCreated,
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The same title before and after the cards are ready: a longer
            // one wraps at this width and pushes the action down.
            Text(
              '$count gift cards',
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Created $dateText',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
        if (ready)
          AppButton(
            key: const ValueKey('payment_link_batch_detail_export'),
            onPressed: onExport,
            size: AppButtonSize.mediumLarge,
            expand: true,
            // Large text wraps the label instead of overflowing.
            growWithContent: largeText,
            constrainContent: largeText,
            leading: const Center(
              child: AppIcon(AppIcons.arrowDownward, size: AppIconSize.medium),
            ),
            child: const Text('Save all links as CSV'),
          )
        else
          AppButton(
            key: const ValueKey('payment_link_batch_check_status'),
            onPressed: onCheckStatus,
            variant: pendingKind == PaymentLinkBatchPendingKind.confirming
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            size: AppButtonSize.mediumLarge,
            expand: true,
            child: const Text('Check status'),
          ),
      ],
    );
  }

  Widget _cardList(BuildContext context, {required bool scrollable}) {
    final colors = context.colors;
    final inset = EdgeInsets.only(right: scrollable ? AppSpacing.s : 0);
    // The status ends at the trailing edge, so a changing label grows toward
    // the title and keeps its one-line height.
    final heading = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          'Cards in this group',
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        if (ready) _UsageActivityLine(activity: usageActivity),
      ],
    );
    // Cards cannot be shared until the payment is settled.
    if (!ready) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: inset, child: heading),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: inset,
            child: _PendingLine(kind: pendingKind),
          ),
        ],
      );
    }
    final rows = <Widget>[
      for (final (index, section)
          in sections.where((section) => section.cards.isNotEmpty).indexed) ...[
        Semantics(
          header: true,
          child: Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : AppSpacing.sm,
              bottom: AppSpacing.xxs,
            ),
            child: Text(
              '${section.label} · ${section.cards.length}',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        ...section.cards,
      ],
    ];
    return Column(
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: inset, child: heading),
        const SizedBox(height: AppSpacing.sm),
        if (scrollable)
          Expanded(child: _ScrollingCardList(rows: rows))
        else
          ...rows,
      ],
    );
  }
}

/// The card list beside the fixed summary. The scrollbar only shows on
/// hover, so the rows fade out at the bottom edge while more follow. The pane
/// behind is translucent, so the fade masks the rows rather than painting a
/// colour over them.
class _ScrollingCardList extends StatefulWidget {
  const _ScrollingCardList({required this.rows});

  final List<Widget> rows;

  @override
  State<_ScrollingCardList> createState() => _ScrollingCardListState();
}

class _ScrollingCardListState extends State<_ScrollingCardList> {
  bool _moreBelow = false;

  bool _track(ScrollMetrics metrics, int depth) {
    if (depth != 0) return false;
    final moreBelow = metrics.extentAfter > 0.5;
    if (moreBelow != _moreBelow) setState(() => _moreBelow = moreBelow);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) =>
          _track(notification.metrics, notification.depth),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) =>
            _track(notification.metrics, notification.depth),
        child: TweenAnimationBuilder<double>(
          key: const ValueKey('payment_link_batch_list_more_below'),
          tween: Tween(end: _moreBelow ? 1 : 0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (context, fade, list) => ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFFFFFFF),
                const Color(0xFFFFFFFF),
                Color.fromRGBO(255, 255, 255, 1 - fade),
              ],
              stops: [
                0,
                rect.height <= AppSpacing.base
                    ? 0
                    : 1 - AppSpacing.base / rect.height,
                1,
              ],
            ).createShader(rect),
            child: list,
          ),
          // The rows stop short of the right padding, and the 6px thumb sits
          // in the middle of it rather than over the row actions.
          child: AppPaneScrollbar(
            crossAxisMargin: 3,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.only(
                right: AppSpacing.s,
                bottom: AppSpacing.xs,
              ),
              children: widget.rows,
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageActivityLine extends StatelessWidget {
  const _UsageActivityLine({required this.activity});

  final PaymentLinkBatchUsageActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('payment_link_batch_usage_activity'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          activity.checking
              ? AppIcons.loader
              : activity.failed
              ? AppIcons.warningCircle
              : AppIcons.time,
          size: AppIconSize.medium,
          color: colors.icon.regular,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Semantics(
            liveRegion: true,
            child: Text(
              activity.checking
                  ? 'Checking card use…'
                  : activity.failed
                  ? 'Couldn’t check every card'
                  : activity.checkedText ?? 'Card use not checked yet',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingLine extends StatelessWidget {
  const _PendingLine({required this.kind});

  final PaymentLinkBatchPendingKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = switch (kind) {
      PaymentLinkBatchPendingKind.confirming =>
        'Links become shareable once the payment confirms.',
      PaymentLinkBatchPendingKind.unconfirmedBroadcast =>
        'Vizor hasn’t confirmed that the payment was sent. Keep these cards and check again before sharing any links.',
      PaymentLinkBatchPendingKind.incomplete =>
        'Not every card in this group is ready. Don’t share any links until they all are.',
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            kind == PaymentLinkBatchPendingKind.confirming
                ? AppIcons.loader
                : AppIcons.warningCircle,
            size: AppIconSize.medium,
            color: colors.icon.regular,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the batch list, shaped like a created-card row: a thumbnail of
/// the card the recipient gets, its number, any status the section does not
/// already say, and its own share actions.
class PaymentLinkBatchMemberRow extends StatelessWidget {
  const PaymentLinkBatchMemberRow({
    required this.index,
    required this.artwork,
    required this.statusLabel,
    this.used = false,
    this.note,
    this.updateFailed = false,
    this.onCopyLink,
    this.onShowQr,
    super.key,
  });

  final int index;
  final PaymentLinkCardArtwork artwork;

  /// The full status, for the row's accessible name.
  final String statusLabel;

  /// Dims a card that has already been used.
  final bool used;

  /// A status worth showing under the number, such as "Use detected".
  final String? note;
  final bool updateFailed;
  final VoidCallback? onCopyLink;
  final VoidCallback? onShowQr;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final number = index.toString().padLeft(2, '0');
    final details = [?note, if (updateFailed) 'Couldn’t update'].join(' · ');
    return Semantics(
      container: true,
      label:
          'Card $number, $statusLabel${updateFailed ? ', update failed' : ''}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
                child: SizedBox(
                  width: 48,
                  height: 32,
                  child: Opacity(
                    opacity: used ? 0.4 : 1,
                    child: Image.asset(artwork.assetPath, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Card $number',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: used
                            ? colors.text.secondary
                            : colors.text.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            PaymentLinkIconAction(
              icon: AppIcons.copy,
              semanticLabel: 'Copy link for card $number',
              onPressed: onCopyLink,
            ),
            const SizedBox(width: AppSpacing.xxs),
            PaymentLinkIconAction(
              icon: AppIcons.qr,
              semanticLabel: 'Show QR code for card $number',
              onPressed: onShowQr,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirms the bearer-secret risk before the native save panel opens.
class PaymentLinkBatchExportModal extends StatelessWidget {
  const PaymentLinkBatchExportModal({
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkConfirmModal(
      iconName: AppIcons.lock,
      title: 'Save gift card links',
      body:
          'Anyone with this file can claim these cards. Save it somewhere '
          'private.',
      confirmLabel: 'Choose location',
      cancelLabel: 'Cancel',
      onConfirm: onConfirm,
      onCancel: onCancel,
      confirmKey: const ValueKey('payment_link_batch_export_confirm'),
      cancelKey: const ValueKey('payment_link_batch_export_cancel'),
    );
  }
}
