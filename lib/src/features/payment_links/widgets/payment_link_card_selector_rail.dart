import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import 'payment_link_card_selector.dart';
import 'payment_link_gift_card.dart';

/// Controlled, horizontally scrollable gift-card artwork selector.
///
/// The parent owns [selected] and updates it from [onSelected]. When the
/// selection changes externally, the rail recenters that artwork. Each
/// [PaymentLinkCardSelector] remains an independent semantic control.
class PaymentLinkCardSelectorRail extends StatefulWidget {
  const PaymentLinkCardSelectorRail({
    required this.artworks,
    required this.selected,
    required this.onSelected,
    this.width = defaultWidth,
    this.height = defaultHeight,
    this.itemWidth = PaymentLinkCardSelector.width,
    this.itemHeight = PaymentLinkCardSelector.height,
    this.artworkWidth = 60,
    this.artworkHeight = 44,
    this.edgeMaskInset = 17,
    this.edgeFadeFraction = 0.15,
    this.inactiveOpacity = 0.5,
    this.loop = false,
    super.key,
  }) : assert(artworks.length > 0),
       assert(
         width >= itemWidth + (itemGap * 2),
         'width must leave room for the selector edge treatment.',
       ),
       assert(itemWidth > 0),
       assert(itemHeight > 0),
       assert(height > 0),
       assert(edgeMaskInset >= 0 && edgeMaskInset < width / 2),
       assert(edgeFadeFraction >= 0 && edgeFadeFraction < 0.5),
       assert(inactiveOpacity >= 0 && inactiveOpacity <= 1);

  static const double defaultWidth = 396;
  static const double defaultHeight = 50;

  /// Gap between two adjacent selector items.
  static const double itemGap = AppSpacing.xs;

  /// Ordered artwork choices shown in the rail.
  ///
  /// Pass [PaymentLinkCardArtwork.values] to expose all exported designs.
  final List<PaymentLinkCardArtwork> artworks;
  final PaymentLinkCardArtwork selected;
  final ValueChanged<PaymentLinkCardArtwork> onSelected;
  final double width;
  final double height;
  final double itemWidth;
  final double itemHeight;
  final double artworkWidth;
  final double artworkHeight;
  final double edgeMaskInset;
  final double edgeFadeFraction;
  final double inactiveOpacity;

  /// Mobile artwork selection loops; desktop keeps its bounded rail.
  final bool loop;

  @override
  State<PaymentLinkCardSelectorRail> createState() =>
      _PaymentLinkCardSelectorRailState();
}

class _PaymentLinkCardSelectorRailState
    extends State<PaymentLinkCardSelectorRail> {
  static const _selectionDuration = Duration(milliseconds: 350);

  late final ScrollController _controller;

  // Rebase to this equivalent cycle after scrolling so both directions keep
  // ample room without building the off-screen copies.
  int get _loopOrigin => widget.artworks.length * 1000;

  double get _itemStride =>
      widget.itemWidth + PaymentLinkCardSelectorRail.itemGap;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset:
          (_loopOriginForMode + widget.artworks.indexOf(widget.selected)) *
          _itemStride,
    );
  }

  @override
  void didUpdateWidget(covariant PaymentLinkCardSelectorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final artworksChanged = !_sameArtworks(oldWidget.artworks, widget.artworks);
    final itemWidthChanged =
        oldWidget.itemWidth != widget.itemWidth ||
        oldWidget.loop != widget.loop;
    if (!artworksChanged &&
        !itemWidthChanged &&
        oldWidget.selected == widget.selected) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (artworksChanged || itemWidthChanged) {
        _jumpToSelection();
      } else {
        _recenterSelection();
      }
    });
  }

  bool _sameArtworks(
    List<PaymentLinkCardArtwork> before,
    List<PaymentLinkCardArtwork> after,
  ) {
    if (identical(before, after)) return true;
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index] != after[index]) return false;
    }
    return true;
  }

  int get _loopOriginForMode => widget.loop ? _loopOrigin : 0;

  void _normalizeLoopOffset() {
    if (!widget.loop ||
        !mounted ||
        !_controller.hasClients ||
        _controller.position.isScrollingNotifier.value) {
      return;
    }
    final cycle = widget.artworks.length * _itemStride;
    final target = _loopOrigin * _itemStride + _controller.offset % cycle;
    if ((_controller.offset - target).abs() > 0.01) {
      _controller.jumpTo(target);
    }
  }

  double _scrollOffsetFor(PaymentLinkCardArtwork artwork) {
    final index = widget.artworks.indexOf(artwork);
    if (index < 0) return 0;
    if (!widget.loop) return _scrollOffsetForIndex(index);
    final current = _controller.hasClients
        ? _controller.offset / _itemStride
        : _loopOrigin.toDouble();
    final cycle = ((current - index) / widget.artworks.length).round();
    return _scrollOffsetForIndex(cycle * widget.artworks.length + index);
  }

  double _scrollOffsetForIndex(int index) {
    return index * _itemStride;
  }

  void _jumpToSelection() {
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpTo(_scrollOffsetFor(widget.selected));
  }

  void _recenterSelection() {
    if (!mounted || !_controller.hasClients) return;
    final offset = _scrollOffsetFor(widget.selected).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _controller.jumpTo(offset);
      return;
    }
    _controller.animateTo(
      offset,
      duration: _selectionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.artworks.contains(widget.selected),
      'selected must be included in artworks.',
    );
    assert(
      widget.artworks.toSet().length == widget.artworks.length,
      'artworks must not contain duplicates.',
    );
    final inheritedScrollBehavior = ScrollConfiguration.of(context);
    final railHeight = widget.height < widget.itemHeight
        ? widget.itemHeight
        : widget.height;
    return SizedBox(
      key: const ValueKey('payment_link_card_selector_rail'),
      width: widget.width,
      height: railHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final edgeInset = widget.edgeMaskInset.clamp(0.0, viewportWidth / 2);
          final fadeWidth =
              (viewportWidth - edgeInset * 2) * widget.edgeFadeFraction;
          // End padding lets the first and last designs stay centered without
          // repeating any artwork. Use the laid-out width on narrower phones.
          final endPadding = ((viewportWidth - _itemStride) / 2).clamp(
            0.0,
            double.infinity,
          );
          return ClipRect(
            clipper: _CardSelectorEdgeClipper(edgeInset),
            child: ShaderMask(
              key: const ValueKey('payment_link_card_selector_edge_fade'),
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  const Color(0x00FFFFFF),
                  const Color(0x00FFFFFF),
                  const Color(0xFFFFFFFF),
                  const Color(0xFFFFFFFF),
                  const Color(0x00FFFFFF),
                  const Color(0x00FFFFFF),
                ],
                stops: [
                  0,
                  edgeInset / viewportWidth,
                  (edgeInset + fadeWidth) / viewportWidth,
                  (viewportWidth - edgeInset - fadeWidth) / viewportWidth,
                  (viewportWidth - edgeInset) / viewportWidth,
                  1,
                ],
              ).createShader(bounds),
              child: ScrollConfiguration(
                behavior: inheritedScrollBehavior.copyWith(
                  scrollbars: false,
                  dragDevices: {
                    ...inheritedScrollBehavior.dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _normalizeLoopOffset(),
                    );
                    return false;
                  },
                  child: ListView.builder(
                    key: const ValueKey('payment_link_card_selector_scroll'),
                    controller: _controller,
                    padding: EdgeInsets.symmetric(horizontal: endPadding),
                    physics: const ClampingScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    itemExtent: _itemStride,
                    itemCount: widget.loop ? null : widget.artworks.length,
                    semanticChildCount: widget.loop
                        ? null
                        : widget.artworks.length,
                    addSemanticIndexes: !widget.loop,
                    itemBuilder: (context, index) {
                      final artwork =
                          widget.artworks[index % widget.artworks.length];
                      return Center(
                        child: PaymentLinkCardSelector(
                          key: ValueKey(
                            'payment_link_card_selector_${artwork.name}',
                          ),
                          artwork: artwork,
                          selected: artwork == widget.selected,
                          onSelected: () {
                            widget.onSelected(artwork);
                            final target = _scrollOffsetForIndex(index).clamp(
                              _controller.position.minScrollExtent,
                              _controller.position.maxScrollExtent,
                            );
                            final disableAnimations =
                                MediaQuery.maybeOf(
                                  context,
                                )?.disableAnimations ??
                                false;
                            if (disableAnimations) {
                              _controller.jumpTo(target);
                            } else {
                              _controller.animateTo(
                                target,
                                duration: _selectionDuration,
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          itemWidth: widget.itemWidth,
                          itemHeight: widget.itemHeight,
                          artworkWidth: widget.artworkWidth,
                          artworkHeight: widget.artworkHeight,
                          inactiveOpacity: widget.inactiveOpacity,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The fully transparent gutters are clipped as well as faded, so a card
/// cannot paint past the edge of the mask while the list is moving.
class _CardSelectorEdgeClipper extends CustomClipper<Rect> {
  const _CardSelectorEdgeClipper(this.inset);

  final double inset;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(inset, 0, size.width - inset, size.height);

  @override
  bool shouldReclip(_CardSelectorEdgeClipper oldClipper) =>
      oldClipper.inset != inset;
}
