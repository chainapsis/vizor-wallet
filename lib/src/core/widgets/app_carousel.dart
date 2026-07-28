import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../layout/app_form_factor.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

/// A single informational card rendered by [AppCarousel].
///
/// The two constructors keep decorative vector and raster treatments explicit
/// while the carousel owns their shared surface, typography, and geometry.
@immutable
class AppCarouselItem {
  const AppCarouselItem.icon({
    required this.message,
    required this.tileColor,
    required this.icon,
    this.iconSize = 20,
  }) : imageAsset = null;

  const AppCarouselItem.image({
    required this.message,
    required this.tileColor,
    required this.imageAsset,
  }) : icon = null,
       iconSize = 0;

  final String message;
  final Color tileColor;
  final String? icon;
  final double iconSize;
  final String? imageAsset;
}

/// Desktop information carousel from the Vizor design system.
///
/// The component owns the fixed Figma geometry, edge mask, page indicator,
/// autoplay, looping, pointer drag, keyboard navigation, and accessibility.
/// Feature code supplies only [items].
class AppCarousel extends StatefulWidget {
  const AppCarousel({
    required this.items,
    this.initialPage = 0,
    this.autoplay = true,
    this.autoplayInterval = const Duration(seconds: 5),
    this.transitionDuration = const Duration(milliseconds: 400),
    this.semanticLabel = 'Information',
    this.onPageChanged,
    super.key,
  }) : assert(items.length > 0, 'AppCarousel requires at least one item.'),
       assert(
         initialPage >= 0 && initialPage < items.length,
         'initialPage must identify an item.',
       );

  final List<AppCarouselItem> items;
  final int initialPage;
  final bool autoplay;
  final Duration autoplayInterval;
  final Duration transitionDuration;
  final String semanticLabel;
  final ValueChanged<int>? onPageChanged;

  @override
  State<AppCarousel> createState() => _AppCarouselState();
}

class _AppCarouselState extends State<AppCarousel> with WidgetsBindingObserver {
  static const _width = 560.0;
  static const _height = 116.0;
  static const _viewportHeight = 100.0;
  static const _cardWidth = 396.0;
  static const _cardHeight = 74.0;
  static const _pageExtent = 415.0;
  static const _pageInset = (_pageExtent - _cardWidth) / 2;
  static const _viewportFraction = _pageExtent / _width;
  static const _indicatorGap = 10.0;
  static const _indicatorHeight = 6.0;
  static const _indicatorItemGap = 4.0;
  static const _activeIndicatorWidth = 40.0;
  static const _inactiveIndicatorWidth = 20.0;
  static const _indicatorDuration = Duration(milliseconds: 240);
  static const _iconTileRadius = 8.875;
  static const _iconColor = Color(0xFFF7F7F7);
  static const _inactiveIndicatorColor = Color(0xFF393E3E);
  static const _loopSeedMultiplier = 1000;

  late PageController _pageController;
  late final FocusNode _focusNode;
  Timer? _autoplayTimer;
  late int _absolutePage;
  late int _pendingLogicalPage;
  late int _activeLogicalPage;
  late AppLifecycleState _lifecycleState;
  bool _disableAnimations = false;
  bool _tickerEnabled = true;
  bool _hovered = false;
  bool _focused = false;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _focusNode = FocusNode(debugLabel: 'AppCarousel');
    _resetController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoplay());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_disableAnimations == disableAnimations &&
        _tickerEnabled == tickerEnabled) {
      return;
    }
    _disableAnimations = disableAnimations;
    _tickerEnabled = tickerEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoplay());
  }

  @override
  void didUpdateWidget(covariant AppCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerMustReset =
        oldWidget.items.length != widget.items.length ||
        oldWidget.initialPage != widget.initialPage;
    if (controllerMustReset) {
      _autoplayTimer?.cancel();
      _pageController.dispose();
      _resetController();
    }
    if (controllerMustReset ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.autoplayInterval != widget.autoplayInterval) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoplay());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _scheduleAutoplay();
    } else {
      _autoplayTimer?.cancel();
    }
  }

  void _resetController() {
    _absolutePage = widget.items.length == 1
        ? 0
        : widget.items.length * _loopSeedMultiplier + widget.initialPage;
    _activeLogicalPage = widget.initialPage;
    _pendingLogicalPage = widget.initialPage;
    _pageController = PageController(
      initialPage: _absolutePage,
      viewportFraction: _viewportFraction,
    );
  }

  int _logicalPage(int page) {
    final remainder = page % widget.items.length;
    return remainder < 0 ? remainder + widget.items.length : remainder;
  }

  bool get _canAutoplay =>
      mounted &&
      widget.autoplay &&
      widget.items.length > 1 &&
      !_disableAnimations &&
      _tickerEnabled &&
      _lifecycleState == AppLifecycleState.resumed &&
      !_hovered &&
      !_focused &&
      !_scrolling;

  void _scheduleAutoplay() {
    _autoplayTimer?.cancel();
    if (!_canAutoplay) return;
    _autoplayTimer = Timer(widget.autoplayInterval, _showNextPage);
  }

  void _showNextPage() => _animateToPage(_absolutePage + 1);

  void _showPreviousPage() => _animateToPage(_absolutePage - 1);

  void _animateToPage(int page) {
    _autoplayTimer?.cancel();
    if (!_pageController.hasClients) return;
    _pageController
        .animateToPage(
          page,
          duration: widget.transitionDuration,
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          _commitSettledPage();
          _scheduleAutoplay();
        });
  }

  void _commitSettledPage() {
    if (_activeLogicalPage == _pendingLogicalPage) return;
    setState(() => _activeLogicalPage = _pendingLogicalPage);
    widget.onPageChanged?.call(_activeLogicalPage);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _autoplayTimer?.cancel();
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _commitSettledPage();
      _scheduleAutoplay();
    }
    return false;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _showPreviousPage();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _showNextPage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleHover(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (hovered) {
      _autoplayTimer?.cancel();
    } else {
      _scheduleAutoplay();
    }
  }

  void _handleFocus(bool focused) {
    if (_focused == focused) return;
    _focused = focused;
    if (focused) {
      _autoplayTimer?.cancel();
    } else {
      _scheduleAutoplay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoplayTimer?.cancel();
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      kAppFormFactor == AppFormFactor.desktop,
      'AppCarousel implements the desktop Figma component.',
    );
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('app_carousel'),
      width: _width,
      height: _height,
      child: MouseRegion(
        onEnter: (_) => _handleHover(true),
        onExit: (_) => _handleHover(false),
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: _handleFocus,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            children: [
              SizedBox(
                key: const ValueKey('app_carousel_viewport'),
                width: _width,
                height: _viewportHeight,
                child: ClipRect(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0xFFFFFFFF),
                        Color(0xFFFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: [0, 0.15, 0.85, 1],
                    ).createShader(bounds),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: PageView.builder(
                        key: const ValueKey('app_carousel_page_view'),
                        controller: _pageController,
                        physics: const PageScrollPhysics(),
                        onPageChanged: (page) {
                          _absolutePage = page;
                          _pendingLogicalPage = _logicalPage(page);
                        },
                        itemBuilder: (context, page) {
                          final logicalPage = _logicalPage(page);
                          final item = widget.items[logicalPage];
                          final card = Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _pageInset,
                            ),
                            child: Center(
                              child: _AppCarouselCard(
                                key: ValueKey('app_carousel_card_$logicalPage'),
                                item: item,
                              ),
                            ),
                          );
                          if (logicalPage != _activeLogicalPage) {
                            return ExcludeSemantics(child: card);
                          }
                          return Semantics(
                            container: true,
                            label:
                                '${widget.semanticLabel} '
                                '${logicalPage + 1} of ${widget.items.length}. '
                                '${item.message}',
                            child: ExcludeSemantics(child: card),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _indicatorGap),
              SizedBox(
                height: _indicatorHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (
                      var index = 0;
                      index < widget.items.length;
                      index++
                    ) ...[
                      AnimatedContainer(
                        key: ValueKey('app_carousel_indicator_$index'),
                        duration: _disableAnimations
                            ? Duration.zero
                            : _indicatorDuration,
                        curve: Curves.easeOutCubic,
                        width: index == _activeLogicalPage
                            ? _activeIndicatorWidth
                            : _inactiveIndicatorWidth,
                        height: _indicatorHeight,
                        decoration: BoxDecoration(
                          color: index == _activeLogicalPage
                              ? colors.icon.accent
                              : _inactiveIndicatorColor,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                        ),
                      ),
                      if (index < widget.items.length - 1)
                        const SizedBox(width: _indicatorItemGap),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppCarouselCard extends StatelessWidget {
  const _AppCarouselCard({required this.item, super.key});

  final AppCarouselItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _AppCarouselState._cardWidth,
      height: _AppCarouselState._cardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: ColoredBox(
          color: context.colors.background.ground,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    _AppCarouselState._iconTileRadius,
                  ),
                  child: ColoredBox(
                    color: item.tileColor,
                    child: SizedBox.square(
                      dimension: 32,
                      child: ExcludeSemantics(
                        child: item.imageAsset != null
                            ? Image.asset(
                                item.imageAsset!,
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                              )
                            : Center(
                                child: AppIcon(
                                  item.icon!,
                                  size: item.iconSize,
                                  color: _AppCarouselState._iconColor,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    item.message,
                    maxLines: 2,
                    overflow: TextOverflow.clip,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
