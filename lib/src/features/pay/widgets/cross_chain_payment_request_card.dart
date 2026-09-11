import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/payments/cross_chain_payment_request.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/full_address_viewer.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../send/widgets/payment_request_card.dart'
    show PaymentRequestRequesterDetailsCard;
import '../../swap/domain/swap_asset.dart';
import '../../swap/models/swap_slippage_formatting.dart';
import '../../swap/widgets/swap_asset_icon.dart';
import '../models/payment_request_resolution.dart';

/// Request review content shared by the desktop modal and mobile sheet.
/// The host owns the surrounding surface and executes no payment from here.
class CrossChainPaymentRequestCard extends StatefulWidget {
  const CrossChainPaymentRequestCard({
    required this.request,
    required this.resolution,
    required this.onContinue,
    required this.onCancel,
    required this.onNetworkSelected,
    required this.onRetry,
    this.onEdit,
    this.isLoading = false,
    this.loadingMessage = 'Checking payment options…',
    this.isPreparingReview = false,
    this.selectedChain,
    this.availabilityMessage,
    this.estimatedZecAmount,
    this.slippageBps,
    this.onOpenSlippage,
    this.isMobile = false,
    super.key,
  });

  final CrossChainPaymentRequest request;
  final PaymentRequestResolution resolution;
  final VoidCallback onContinue;
  final VoidCallback onCancel;
  final ValueChanged<String> onNetworkSelected;
  final VoidCallback onRetry;
  final VoidCallback? onEdit;
  final bool isLoading;
  final String loadingMessage;
  final bool isPreparingReview;
  final String? selectedChain;
  final String? availabilityMessage;
  final double? estimatedZecAmount;
  final int? slippageBps;
  final VoidCallback? onOpenSlippage;
  final bool isMobile;

  @override
  State<CrossChainPaymentRequestCard> createState() =>
      _CrossChainPaymentRequestCardState();
}

class _CrossChainPaymentRequestCardState
    extends State<CrossChainPaymentRequestCard> {
  final _scrollController = ScrollController();
  bool _addressExpanded = false;
  bool _requesterExpanded = false;
  bool _networkPickerExpanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CrossChainPaymentRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id != widget.request.id) {
      _addressExpanded = false;
      _requesterExpanded = false;
      _networkPickerExpanded = false;
    }
  }

  String get _networkLabel {
    final request = widget.request;
    if (request.isEvm) {
      if (request.chainId case final chainId?) {
        return evmPaymentNetworks[chainId]?.label ??
            'Unsupported network (chain ID $chainId)';
      }
      for (final network in evmPaymentNetworks.values) {
        if (network.chain == widget.selectedChain) return network.label;
      }
      return 'Select network';
    }
    return switch (request.chain) {
      'btc' => 'Bitcoin',
      'ltc' => 'Litecoin',
      'sol' => 'Solana',
      _ => 'Network unavailable',
    };
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final resolution = widget.resolution;
    final amount = resolution.amountText;
    final hasAmount =
        resolution.asset != null && amount != null && amount.isNotEmpty;
    final statusMessage =
        request.unsupportedReason ??
        widget.availabilityMessage ??
        resolution.message;
    final canContinue =
        resolution.isReady &&
        !resolution.needsNetwork &&
        !widget.isLoading &&
        !widget.isPreparingReview &&
        widget.availabilityMessage == null &&
        request.unsupportedReason == null;
    final canRetry =
        !widget.isLoading &&
        !widget.isPreparingReview &&
        widget.availabilityMessage != null &&
        request.unsupportedReason == null;
    final sectionGap = widget.isMobile ? AppSpacing.sm : AppSpacing.md;
    final requester = request.label?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final note = request.message?.trim();
    final hasRequester = requester != null && requester.isNotEmpty;
    final hasNote = note != null && note.isNotEmpty;

    final details = SingleChildScrollView(
      key: const ValueKey('cross_chain_payment_request_scroll'),
      controller: _scrollController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasRequester || hasNote) ...[
            PaymentRequestRequesterDetailsCard(
              requester: hasRequester ? requester : null,
              note: hasNote ? note : null,
              expanded: _requesterExpanded,
              onToggle: hasNote
                  ? () =>
                        setState(() => _requesterExpanded = !_requesterExpanded)
                  : null,
            ),
            SizedBox(height: sectionGap),
          ],
          _transactionContent(context, hasAmount: hasAmount),
          if (widget.slippageBps != null &&
              resolution.isReady &&
              request.unsupportedReason == null) ...[
            const SizedBox(height: AppSpacing.xs),
            _slippageControl(context),
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          SizedBox(height: sectionGap),
          if (constraints.hasBoundedHeight)
            Flexible(
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thumbColor: context.colors.surface.scrollbarThumb,
                child: details,
              ),
            )
          else
            details,
          if (widget.isLoading ||
              widget.isPreparingReview ||
              statusMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                widget.isPreparingReview
                    ? 'Preparing payment review…'
                    : widget.isLoading
                    ? widget.loadingMessage
                    : statusMessage!,
                key: const ValueKey('cross_chain_payment_request_status'),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ],
          SizedBox(height: sectionGap),
          AppButton(
            key: const ValueKey('cross_chain_payment_request_continue'),
            onPressed: canRetry
                ? widget.onRetry
                : canContinue
                ? widget.onContinue
                : null,
            expand: true,
            constrainContent: true,
            child: Text(
              widget.isPreparingReview
                  ? 'Preparing…'
                  : widget.isLoading
                  ? 'Checking…'
                  : canRetry
                  ? 'Try again'
                  : resolution.isReady && !hasAmount
                  ? 'Enter amount'
                  : 'Review payment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onEdit != null && hasAmount && resolution.isReady) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              key: const ValueKey('cross_chain_payment_request_edit'),
              onPressed: widget.isLoading || widget.isPreparingReview
                  ? null
                  : widget.onEdit,
              variant: AppButtonVariant.ghost,
              expand: true,
              child: const Text('Edit'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            'Payment request',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Semantics(
        label: 'Close payment request',
        child: AppButton(
          key: const ValueKey('cross_chain_payment_request_cancel'),
          onPressed: widget.onCancel,
          variant: AppButtonVariant.ghost,
          height: widget.isMobile ? 44 : 32,
          minWidth: widget.isMobile ? 44 : 32,
          contentPadding: EdgeInsets.zero,
          child: AppIcon(
            AppIcons.cross,
            size: AppIconSize.medium,
            color: context.colors.icon.regular,
          ),
        ),
      ),
    ],
  );

  Widget _slippageControl(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Slippage',
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
      Semantics(
        label: 'Change slippage',
        child: AppButton(
          key: const ValueKey('cross_chain_payment_request_slippage'),
          onPressed: widget.isLoading || widget.isPreparingReview
              ? null
              : widget.onOpenSlippage,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.small,
          height: widget.isMobile ? 44 : 32,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatSwapSlippage(widget.slippageBps!)),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(AppIcons.cog, size: 16, color: context.colors.icon.muted),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _transactionContent(BuildContext context, {required bool hasAmount}) {
    final request = widget.request;
    final estimatedZec = widget.estimatedZecAmount;
    final showEstimate =
        hasAmount &&
        widget.resolution.isReady &&
        !widget.isLoading &&
        widget.availabilityMessage == null &&
        request.unsupportedReason == null &&
        estimatedZec != null &&
        estimatedZec.isFinite &&
        estimatedZec > 0;
    final radius = BorderRadius.circular(AppRadii.large);
    return Container(
      key: const ValueKey('cross_chain_payment_request_transaction'),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: context.colors.border.regular),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Detail(
                  label: 'Recipient gets',
                  child: _assetAmount(context, hasAmount: hasAmount),
                ),
                if (request.needsNetwork && request.unsupportedReason == null)
                  _networkPicker(context),
                if (showEstimate) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const ReviewWrapDivider(),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    key: const ValueKey('payment_request_zec_estimate'),
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      Text(
                        'Estimated spend',
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                      Text(
                        estimatedZec < 0.0001
                            ? '< 0.0001 ZEC'
                            : '≈ ${SwapAsset.zec.formatAmount(estimatedZec)} ZEC',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: context.colors.text.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (request.address.isNotEmpty)
            ReviewWrapCard(
              mainAxisSize: MainAxisSize.min,
              padding: const EdgeInsets.all(AppSpacing.sm),
              children: [_recipient(context)],
            ),
        ],
      ),
    );
  }

  Widget _assetAmount(BuildContext context, {required bool hasAmount}) {
    final request = widget.request;
    final resolution = widget.resolution;
    final asset = resolution.asset;
    final hasNetworkPicker =
        request.needsNetwork && request.unsupportedReason == null;
    final value = hasAmount
        ? resolution.amountText!
        : resolution.needsNetwork
        ? 'Network not specified'
        : request.amount == null
        ? 'Amount not specified'
        : widget.isLoading
        ? 'Loading amount…'
        : 'Amount unavailable';
    final amountStyle =
        (hasAmount
                ? AppTypography.headlineLarge
                : AppTypography.bodyMediumStrong)
            .copyWith(color: context.colors.text.accent);
    final amount = Text(
      value,
      key: const ValueKey('cross_chain_payment_request_amount'),
      softWrap: true,
      style: amountStyle,
    );
    final identity = Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (asset != null)
          Text(
            asset.symbol,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        if (asset != null && !hasNetworkPicker)
          Text(
            '·',
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.muted,
            ),
          ),
        if (!hasNetworkPicker)
          Text(
            _networkLabel,
            key: const ValueKey('cross_chain_payment_request_network'),
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
      ],
    );
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        amount,
        if (asset != null || !hasNetworkPicker) ...[
          const SizedBox(height: AppSpacing.xxs),
          identity,
        ],
      ],
    );
    const iconSize = 48.0;
    final icon = asset == null
        ? null
        : ExcludeSemantics(
            child: SwapAssetIcon(
              key: const ValueKey('payment_request_asset_icon'),
              asset: asset,
              size: iconSize,
              badgeScale: 20 / iconSize,
              overhangScale: 4 / iconSize,
              showChainBadge: asset.symbol.toLowerCase() != asset.chainTicker,
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (icon == null) return summary;
          final measure = TextPainter(
            text: TextSpan(text: value, style: amountStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final stackAmount =
              hasAmount &&
              measure.width + iconSize + AppSpacing.sm > constraints.maxWidth;
          measure.dispose();
          // Give long exact amounts the full card width instead of shrinking
          // their digits or leaving the final digit beside the icon alone.
          if (stackAmount) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: identity),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                amount,
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: summary),
            ],
          );
        },
      ),
    );
  }

  Widget _networkPicker(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: AppSpacing.sm),
      DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: widget.selectedChain == null || widget.isPreparingReview
                ? BorderSide.none
                : BorderSide(color: context.colors.border.strong),
          ),
        ),
        child: _disclosureButton(
          key: const ValueKey('payment_request_select_network'),
          label: _networkLabel,
          expanded: _networkPickerExpanded,
          variant: AppButtonVariant.secondary,
          onPressed: widget.isPreparingReview
              ? null
              : () => setState(
                  () => _networkPickerExpanded = !_networkPickerExpanded,
                ),
        ),
      ),
      if (widget.selectedChain != null) ...[
        const SizedBox(height: AppSpacing.xxs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            'Selected by you',
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      ],
      if (_networkPickerExpanded) ...[
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final network in evmPaymentNetworks.values)
              Semantics(
                selected: widget.selectedChain == network.chain,
                child: AppButton(
                  key: ValueKey('payment_network_${network.chain}'),
                  onPressed: widget.isPreparingReview
                      ? null
                      : () {
                          setState(() => _networkPickerExpanded = false);
                          widget.onNetworkSelected(network.chain);
                        },
                  variant: widget.selectedChain == network.chain
                      ? AppButtonVariant.primary
                      : AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  height: widget.isMobile ? 44 : null,
                  child: Text(
                    widget.request.contractAddress == null
                        ? '${network.nativeSymbol} · ${network.label}'
                        : network.label,
                  ),
                ),
              ),
          ],
        ),
      ],
    ],
  );

  void _toggleAddress() => setState(() => _addressExpanded = !_addressExpanded);

  Widget _recipient(BuildContext context) {
    final recipient = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_addressExpanded) ...[
          FullAddressText(
            address: widget.request.address,
            color: context.colors.text.accent,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _addressAction(context),
          ),
        ] else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xxs,
            children: [
              Text(
                truncatedAddress(widget.request.address),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.codeMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              _addressAction(context),
            ],
          ),
      ],
    );
    return _Detail(
      label: 'To',
      // Match ZEC requests: a compact pill with the recipient block tappable.
      child: widget.isMobile
          ? GestureDetector(
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              onTap: _toggleAddress,
              child: recipient,
            )
          : recipient,
    );
  }

  Widget _addressAction(BuildContext context) {
    final label = _addressExpanded ? 'Hide full address' : 'Show full address';
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final visibleLabel = usesLargeText
        ? (_addressExpanded ? 'Hide' : 'Show')
        : label;
    return Semantics(
      button: true,
      label: label,
      onTap: _toggleAddress,
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.5,
        child: AppButton(
          key: const ValueKey('payment_request_show_address'),
          onPressed: _toggleAddress,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.small,
          iconGap: 0,
          leading: usesLargeText
              ? null
              : AppIcon(
                  _addressExpanded ? AppIcons.eyeClosed : AppIcons.eye,
                  color: context.colors.button.ghost.label,
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              visibleLabel,
              maxLines: 1,
              style: AppTypography.labelSmall,
            ),
          ),
        ),
      ),
    );
  }

  Widget _disclosureButton({
    required Key key,
    required String label,
    required bool expanded,
    required VoidCallback? onPressed,
    AppButtonVariant variant = AppButtonVariant.ghost,
  }) => Semantics(
    expanded: expanded,
    child: AppButton(
      key: key,
      onPressed: onPressed,
      variant: variant,
      size: AppButtonSize.medium,
      height: widget.isMobile ? 44 : null,
      expand: true,
      constrainContent: true,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: AppSpacing.xs),
          RotatedBox(
            quarterTurns: expanded ? 3 : 1,
            child: AppIcon(
              AppIcons.chevronForward,
              size: AppIconSize.medium,
              color: context.colors.icon.regular,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      child,
    ],
  );
}
