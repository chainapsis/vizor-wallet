import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'payment_link_gift_card.dart';

/// A stack of cards whose depth follows the count. On reveal the cards drop
/// onto the stack one by one, back to front, and then the `×N` badge appears.
///
/// The deck scales down to fit its constraints; the `×N` badge stays at its
/// text size so it remains legible in small previews.
class PaymentLinkBatchDeck extends StatefulWidget {
  const PaymentLinkBatchDeck({
    required this.card,
    required this.count,
    required this.playReveal,
    this.animateCount = false,
    this.backArtworks = const [],
    super.key,
  });

  final Widget card;
  final int count;
  final bool playReveal;
  final bool animateCount;

  /// Designs for the cards behind the front one, nearest first. Empty draws
  /// plain backs, as for a group that shares one design.
  final List<PaymentLinkCardArtwork> backArtworks;

  static const double width = 392;
  static const double height = 253;

  @override
  State<PaymentLinkBatchDeck> createState() => _PaymentLinkBatchDeckState();
}

class _PaymentLinkBatchDeckState extends State<PaymentLinkBatchDeck>
    with SingleTickerProviderStateMixin {
  static const _maxLayers = 6;
  static const _stagger = 90.0;
  static const _drop = 320.0;
  static const _badgeMs = 160.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.playReveal ? 0 : 1,
  );

  bool get _motionDisabled =>
      MediaQuery.disableAnimationsOf(context) ||
      !TickerMode.valuesOf(context).enabled;

  /// Layers behind the front card that are at least partly visible.
  int get _layerCount =>
      (1 + (_maxLayers - 1) * _growth(widget.count.toDouble())).ceil();

  double get _revealMs => _layerCount * _stagger + _drop + _badgeMs;

  void _startReveal() {
    if (_motionDisabled) {
      _controller.value = 1;
      return;
    }
    _controller.duration = Duration(milliseconds: _revealMs.round());
    _controller.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionDisabled) {
      _controller.value = 1;
    } else if (widget.playReveal && _controller.value == 0) {
      _startReveal();
    }
  }

  @override
  void didUpdateWidget(covariant PaymentLinkBatchDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.playReveal && widget.playReveal) _startReveal();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Drop progress of the card at [order], counting from the back of the stack.
  double _dropProgress(int order) {
    final elapsed = _controller.value * _revealMs - order * _stagger;
    return (elapsed / _drop).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final motionDisabled = _motionDisabled;
    // Decorative: the title or the count control beside it says how many.
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = [
            1.0,
            if (constraints.hasBoundedWidth)
              constraints.maxWidth / PaymentLinkBatchDeck.width,
            if (constraints.hasBoundedHeight)
              constraints.maxHeight / PaymentLinkBatchDeck.height,
          ].reduce(math.min);
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.count.toDouble()),
            duration: motionDisabled || !widget.animateCount
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            builder: (context, animatedCount, _) => AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final badge =
                    ((_controller.value * _revealMs - (_revealMs - _badgeMs)) /
                            _badgeMs)
                        .clamp(0.0, 1.0);
                return SizedBox(
                  width: PaymentLinkBatchDeck.width * scale,
                  height: PaymentLinkBatchDeck.height * scale,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: _deck(context, animatedCount),
                        ),
                      ),
                      Positioned(
                        top: _frontCardCorner.dy * scale,
                        right:
                            (PaymentLinkBatchDeck.width - _frontCardCorner.dx) *
                            scale,
                        child: FractionalTranslation(
                          // Center the badge on the front card's corner.
                          translation: const Offset(0.5, -0.5),
                          child: Opacity(
                            opacity: badge,
                            child: Transform.scale(
                              scale: 0.96 + 0.04 * badge,
                              child: _badge(context, motionDisabled),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Top-right corner of the front card inside the unscaled deck box:
  /// 360x225 scaled by .92, centered, then shifted by (-16, 6).
  static const _frontCardCorner = Offset(
    PaymentLinkBatchDeck.width / 2 - 16 + 360 * .92 / 2,
    PaymentLinkBatchDeck.height / 2 + 6 - 225 * .92 / 2,
  );

  Widget _deck(BuildContext context, double animatedCount) {
    final layers = _layerCount;
    return SizedBox(
      width: PaymentLinkBatchDeck.width,
      height: PaymentLinkBatchDeck.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var layer = _maxLayers; layer >= 1; layer--)
            _dropping(
              order: layers - layer,
              child: _countLayer(context, layer, animatedCount),
            ),
          _dropping(
            key: const ValueKey('payment_link_batch_front'),
            order: layers,
            child: Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(-16, 6),
                child: Transform.scale(
                  scale: .92,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.large),
                      boxShadow: appSurfaceShadow(context.colors),
                    ),
                    child: widget.card,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropping({required int order, required Widget child, Key? key}) {
    final progress = _dropProgress(order.clamp(0, _maxLayers));
    if (progress >= 1) return KeyedSubtree(key: key, child: child);
    final eased = Curves.easeOutCubic.transform(progress);
    return Opacity(
      key: key,
      opacity: (progress * 2).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -36 * (1 - eased)),
        child: Transform.scale(scale: 1.03 - 0.03 * eased, child: child),
      ),
    );
  }

  Widget _badge(BuildContext context, bool motionDisabled) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.background.raised,
      borderRadius: BorderRadius.circular(AppRadii.full),
      border: Border.all(color: context.colors.border.regular),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: AnimatedSwitcher(
        duration: motionDisabled || !widget.animateCount
            ? Duration.zero
            : const Duration(milliseconds: 140),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          '×${widget.count}',
          key: ValueKey(widget.count),
          style: AppTypography.labelMedium.copyWith(
            color: context.colors.text.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );

  /// 0 for two cards, 1 at fifty; logarithmic so small counts stay distinct.
  static double _growth(double count) =>
      (math.log(math.max(count - 1, 1)) / math.log(49)).clamp(0.0, 1.0);

  Widget _countLayer(BuildContext context, int layer, double animatedCount) {
    final growth = _growth(animatedCount);
    final visibleLayers = 1 + (_maxLayers - 1) * growth;
    final opacity = (visibleLayers - layer + 1).clamp(0.0, 1.0);
    // A mixed group fans its cards further so each design shows.
    final spread = widget.backArtworks.isEmpty
        ? 3 + 4 * growth
        : 6 + 4 * growth;
    return Opacity(
      opacity: opacity,
      child: Align(
        alignment: Alignment.center,
        child: Transform.translate(
          key: ValueKey('payment_link_batch_layer_$layer'),
          offset: Offset(-16 + layer * spread, 6 - layer * spread * .55),
          child: Transform.rotate(
            angle: layer * growth * .005,
            child: Transform.scale(
              scale: .92,
              child: _cardBack(context, layer),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBack(BuildContext context, int layer) {
    final artworks = widget.backArtworks;
    if (artworks.isNotEmpty) {
      // A mixed group shows a different design peeking from each layer.
      return Container(
        key: ValueKey('payment_link_batch_back_artwork_$layer'),
        width: 360,
        height: 225,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.large),
          border: Border.all(color: context.colors.border.medium),
        ),
        child: Image.asset(
          artworks[(layer - 1) % artworks.length].assetPath,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      );
    }
    return _plainBack(context);
  }

  Widget _plainBack(BuildContext context) => Container(
    width: 360,
    height: 225,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          context.colors.background.raised,
          context.colors.background.brandCrimsonSubtle,
        ],
      ),
      borderRadius: BorderRadius.circular(AppRadii.large),
      border: Border.all(color: context.colors.border.medium),
    ),
  );
}
