import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

@immutable
class MobileHomeCarouselItem {
  const MobileHomeCarouselItem({required this.id, required this.child});

  final Object id;
  final Widget child;
}

/// A compact Home carousel for a small set of actionable mobile banners.
///
/// It keeps only the active banner in the layout, so translated or scaled text
/// can grow the card naturally. Users change pages by swiping, selecting a page
/// indicator, or using keyboard arrow keys.
class MobileHomeCarousel extends StatefulWidget {
  const MobileHomeCarousel({
    required this.items,
    this.initialPage = 0,
    super.key,
  });

  final List<MobileHomeCarouselItem> items;
  final int initialPage;

  @override
  State<MobileHomeCarousel> createState() => _MobileHomeCarouselState();
}

class _MobileHomeCarouselState extends State<MobileHomeCarousel> {
  static const _transitionDuration = Duration(milliseconds: 150);

  late final FocusNode _focusNode;
  late int _activePage;
  double _dragDelta = 0;

  @override
  void initState() {
    super.initState();
    _activePage = _clampedInitialPage();
    _focusNode = FocusNode(debugLabel: 'MobileHomeCarousel');
  }

  @override
  void didUpdateWidget(covariant MobileHomeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final itemIdsChanged = !_sameItemIds(oldWidget.items, widget.items);
    if (itemIdsChanged || oldWidget.initialPage != widget.initialPage) {
      _activePage = _clampedInitialPage();
    }
  }

  int _clampedInitialPage() {
    if (widget.items.isEmpty) return 0;
    if (widget.initialPage < 0) return 0;
    if (widget.initialPage >= widget.items.length) {
      return widget.items.length - 1;
    }
    return widget.initialPage;
  }

  bool _sameItemIds(
    List<MobileHomeCarouselItem> previous,
    List<MobileHomeCarouselItem> next,
  ) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].id != next[index].id) return false;
    }
    return true;
  }

  void _showNextPage() {
    if (widget.items.length < 2) return;
    _showPage((_activePage + 1) % widget.items.length);
  }

  void _showPreviousPage() {
    if (widget.items.length < 2) return;
    _showPage((_activePage - 1 + widget.items.length) % widget.items.length);
  }

  void _showPage(int page) {
    if (widget.items.isEmpty ||
        page == _activePage ||
        page < 0 ||
        page >= widget.items.length) {
      return;
    }
    setState(() => _activePage = page);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _dragDelta += details.primaryDelta ?? 0;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final rtlMultiplier = Directionality.of(context) == TextDirection.rtl
        ? -1
        : 1;
    final directionalVelocity = (details.primaryVelocity ?? 0) * rtlMultiplier;
    final directionalDelta = _dragDelta * rtlMultiplier;
    if (directionalVelocity < -200 || directionalDelta < -48) {
      _showNextPage();
    } else if (directionalVelocity > 200 || directionalDelta > 48) {
      _showPreviousPage();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      isRtl ? _showNextPage() : _showPreviousPage();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      isRtl ? _showPreviousPage() : _showNextPage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = widget.items[_activePage];
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final duration = reduceMotion ? Duration.zero : _transitionDuration;
    final banner = KeyedSubtree(key: ValueKey(item.id), child: item.child);
    final bannerContent = reduceMotion
        ? banner
        : AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: banner,
            ),
          );
    return Focus(
      key: const ValueKey('mobile_home_carousel_focus'),
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _dragDelta = 0,
            onHorizontalDragUpdate: _handleHorizontalDragUpdate,
            onHorizontalDragCancel: () => _dragDelta = 0,
            onHorizontalDragEnd: _handleHorizontalDragEnd,
            child: bannerContent,
          ),
          if (widget.items.length > 1) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < widget.items.length; index++)
                  Semantics(
                    button: true,
                    selected: index == _activePage,
                    label:
                        'Show wallet setup banner ${index + 1} of '
                        '${widget.items.length}',
                    child: GestureDetector(
                      key: ValueKey('mobile_home_carousel_indicator_$index'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showPage(index),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: AnimatedContainer(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            width: index == _activePage ? 24 : 8,
                            height: 6,
                            decoration: BoxDecoration(
                              color: index == _activePage
                                  ? context.colors.icon.accent
                                  : context.colors.icon.muted,
                              borderRadius: BorderRadius.circular(
                                AppRadii.full,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
