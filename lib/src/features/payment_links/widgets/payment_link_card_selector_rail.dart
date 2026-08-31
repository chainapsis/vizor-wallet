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
    this.itemWidth = PaymentLinkCardSelector.width,
    this.itemHeight = PaymentLinkCardSelector.height,
    this.artworkWidth = 60,
    this.artworkHeight = 44,
    this.itemGap = AppSpacing.xxs,
    this.selectionInset = const EdgeInsets.fromLTRB(1, 2, 0, 1),
    this.selectionBorderWidth = 2,
    this.selectionBorderRadius = 10,
    this.selectedCheckSize = 20,
    this.edgeMaskInset = 17,
    this.edgeFadeFraction = 0.2,
    this.inactiveOpacity = 0.5,
    super.key,
  }) : assert(artworks.length > 0),
       assert(
         width >= itemWidth + (AppSpacing.xxs * 2),
         'width must leave room for the selector edge treatment.',
       ),
       assert(itemWidth > 0),
       assert(itemHeight > 0),
       assert(itemGap >= 0),
       assert(selectionBorderWidth > 0),
       assert(selectionBorderRadius >= 0),
       assert(selectedCheckSize > 0),
       assert(edgeMaskInset >= 0 && edgeMaskInset < width / 2),
       assert(edgeFadeFraction >= 0 && edgeFadeFraction < 0.5),
       assert(inactiveOpacity >= 0 && inactiveOpacity <= 1);

  static const double defaultWidth = 396;

  /// Ordered artwork choices shown in the rail.
  ///
  /// Pass [PaymentLinkCardArtwork.values] to expose all exported designs.
  final List<PaymentLinkCardArtwork> artworks;
  final PaymentLinkCardArtwork selected;
  final ValueChanged<PaymentLinkCardArtwork> onSelected;
  final double width;
  final double itemWidth;
  final double itemHeight;
  final double artworkWidth;
  final double artworkHeight;
  final double itemGap;
  final EdgeInsets selectionInset;
  final double selectionBorderWidth;
  final double selectionBorderRadius;
  final double selectedCheckSize;
  final double edgeMaskInset;
  final double edgeFadeFraction;
  final double inactiveOpacity;

  @override
  State<PaymentLinkCardSelectorRail> createState() =>
      _PaymentLinkCardSelectorRailState();
}

class _PaymentLinkCardSelectorRailState
    extends State<PaymentLinkCardSelectorRail> {
  static const _selectionDuration = Duration(milliseconds: 180);

  late final ScrollController _controller;

  double get _itemStride => widget.itemWidth + widget.itemGap;

  double get _sidePadding => (widget.width - widget.itemWidth) / 2;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: _scrollOffsetFor(widget.selected),
    );
  }

  @override
  void didUpdateWidget(covariant PaymentLinkCardSelectorRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected &&
        _sameArtworks(oldWidget.artworks, widget.artworks)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recenterSelection());
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

  double _scrollOffsetFor(PaymentLinkCardArtwork artwork) {
    final index = widget.artworks.indexOf(artwork);
    return index < 0 ? 0 : index * _itemStride;
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
    final maskWidth = widget.width - (widget.edgeMaskInset * 2);
    final fadeWidth = maskWidth * widget.edgeFadeFraction;
    final maskStart = widget.edgeMaskInset / widget.width;
    final opaqueStart = (widget.edgeMaskInset + fadeWidth) / widget.width;
    final opaqueEnd =
        (widget.width - widget.edgeMaskInset - fadeWidth) / widget.width;
    final maskEnd = (widget.width - widget.edgeMaskInset) / widget.width;
    return SizedBox(
      key: const ValueKey('payment_link_card_selector_rail'),
      width: widget.width,
      height: widget.itemHeight,
      child: ClipRect(
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
            stops: [0, maskStart, opaqueStart, opaqueEnd, maskEnd, 1],
          ).createShader(bounds),
          child: ScrollConfiguration(
            behavior: inheritedScrollBehavior.copyWith(
              scrollbars: false,
              dragDevices: {
                ...inheritedScrollBehavior.dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
            child: ListView.builder(
              key: const ValueKey('payment_link_card_selector_scroll'),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              itemExtent: _itemStride,
              padding: EdgeInsets.only(
                left: _sidePadding,
                right: _sidePadding - widget.itemGap,
              ),
              itemCount: widget.artworks.length,
              itemBuilder: (context, index) {
                final artwork = widget.artworks[index];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: PaymentLinkCardSelector(
                    key: ValueKey('payment_link_card_selector_${artwork.name}'),
                    artwork: artwork,
                    selected: artwork == widget.selected,
                    onSelected: () => widget.onSelected(artwork),
                    itemWidth: widget.itemWidth,
                    itemHeight: widget.itemHeight,
                    artworkWidth: widget.artworkWidth,
                    artworkHeight: widget.artworkHeight,
                    selectionInset: widget.selectionInset,
                    selectionBorderWidth: widget.selectionBorderWidth,
                    selectionBorderRadius: widget.selectionBorderRadius,
                    selectedCheckSize: widget.selectedCheckSize,
                    inactiveOpacity: widget.inactiveOpacity,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
