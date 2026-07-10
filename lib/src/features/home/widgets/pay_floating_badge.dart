import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../services/pay_introduction_badge_store.dart';

/// Wraps the desktop Pay button with its persistent floating callout.
///
/// Coin, label, and glow remain visible. Only the `NEW` marker is persisted as
/// seen and dismissed after navigation/app backgrounding.
class PayIntroductionBadgeTarget extends ConsumerStatefulWidget {
  const PayIntroductionBadgeTarget({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  ConsumerState<PayIntroductionBadgeTarget> createState() =>
      _PayIntroductionBadgeTargetState();
}

class _PayIntroductionBadgeTargetState
    extends ConsumerState<PayIntroductionBadgeTarget>
    with WidgetsBindingObserver {
  bool _checkStarted = false;
  bool _showNew = false;
  bool? _tickerWasEnabled;
  bool? _routeWasCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCheckIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PayIntroductionBadgeTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _showNew = false;
      return;
    }
    _startCheckIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if ((_tickerWasEnabled == true && !tickerEnabled) ||
        (_routeWasCurrent == true && !routeIsCurrent)) {
      _showNew = false;
    }
    _tickerWasEnabled = tickerEnabled;
    _routeWasCurrent = routeIsCurrent;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hide();
    }
  }

  void _startCheckIfNeeded() {
    if (!widget.enabled || _checkStarted) return;
    _checkStarted = true;
    Future<void>(() async {
      if (ref.read(payIntroductionBadgePersistenceEnabledProvider)) {
        final store = ref.read(payIntroductionBadgeStoreProvider);
        try {
          if (await store.hasSeen()) return;
          // Persist first: once the user has seen this introduction, a process
          // exit must not make it appear again on the next launch.
          await store.markSeen();
        } catch (error) {
          debugPrint('Pay introduction badge persistence failed: $error');
          return;
        }
      }
      if (!mounted || !widget.enabled) return;
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState != null &&
          lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      if (!TickerMode.valuesOf(context).enabled) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      setState(() => _showNew = true);
    });
  }

  void _hide() {
    if (!_showNew || !mounted) return;
    setState(() => _showNew = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('pay_introduction_badge_target'),
      clipBehavior: Clip.none,
      children: [
        if (widget.enabled)
          const Positioned(
            left: 0,
            top: 0,
            width: 60,
            height: 44,
            child: IgnorePointer(child: _PayFloatingGlow()),
          ),
        widget.child,
        if (widget.enabled)
          Positioned(
            // In the Home frame (5407:152492), the 169px badge frame starts
            // at the Pay button's left edge and overflows to its right.
            left: 0,
            top: -65,
            child: IgnorePointer(
              child: PayFloatingBadge(
                animate: _showNew,
                showGlow: false,
                showNew: _showNew,
              ),
            ),
          ),
      ],
    );
  }
}

/// Figma `PAY Floating Badge` (6251:92829 light / 6251:92807 dark).
class PayFloatingBadge extends StatefulWidget {
  const PayFloatingBadge({
    super.key,
    this.animate = true,
    this.showGlow = true,
    this.showNew = true,
  });

  static const size = Size(169, 137);

  final bool animate;
  final bool showGlow;
  final bool showNew;

  @override
  State<PayFloatingBadge> createState() => _PayFloatingBadgeState();
}

class _PayFloatingBadgeState extends State<PayFloatingBadge>
    with SingleTickerProviderStateMixin {
  static const _motionDuration = Duration(milliseconds: 1800);
  static const _floatDistance = 6.0;

  AnimationController? _controller;
  Animation<double>? _coinOffset;

  bool get _shouldAnimate {
    if (!widget.animate) return false;
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  AnimationController get _activeController {
    final existing = _controller;
    if (existing != null) return existing;
    final controller = AnimationController(
      vsync: this,
      duration: _motionDuration,
    );
    _controller = controller;
    _coinOffset = Tween<double>(
      begin: 0,
      end: -_floatDistance,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    return controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PayFloatingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) {
        _activeController.repeat(reverse: true);
      }
      return;
    }
    final controller = _controller;
    if (controller != null) {
      controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.appTheme == AppThemeData.dark;
    final textColor = context.colors.text.inverse;

    return Semantics(
      label: widget.showNew ? 'New: Pay in USDC' : 'Pay in USDC',
      container: true,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          key: const ValueKey('pay_floating_badge'),
          size: PayFloatingBadge.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.showGlow)
                const Positioned(
                  left: 60,
                  top: 65,
                  width: 60,
                  height: 44,
                  child: _PayFloatingGlow(),
                ),
              Positioned(
                left: 39,
                top: 0,
                width: 68,
                height: 68,
                child: _AnimatedPayCoin(
                  controller: _controller,
                  offset: _coinOffset,
                ),
              ),
              Positioned(
                left: 66,
                top: 72,
                width: 103,
                height: 32,
                child: SvgPicture.asset(
                  isDark
                      ? 'assets/illustrations/pay_floating_label_dark.svg'
                      : 'assets/illustrations/pay_floating_label_light.svg',
                  key: const ValueKey('pay_floating_badge_label_shape'),
                ),
              ),
              Positioned(
                left: 81,
                top: 80,
                child: Text(
                  'Pay in USDC',
                  style: AppTypography.labelLarge.copyWith(color: textColor),
                ),
              ),
              if (widget.showNew) ...[
                Positioned(
                  left: 83,
                  top: 108,
                  width: 55,
                  height: 29,
                  child: SvgPicture.asset(
                    'assets/illustrations/pay_floating_new.svg',
                  ),
                ),
                Positioned(
                  left: 96,
                  top: 114,
                  child: Text(
                    'NEW',
                    style: AppTypography.labelLarge.copyWith(
                      color: const Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PayFloatingGlow extends StatelessWidget {
  const _PayFloatingGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      key: ValueKey('pay_floating_badge_glow'),
      decoration: BoxDecoration(
        color: Color(0x03FFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(999)),
        boxShadow: [
          BoxShadow(color: Color(0xFF1C7ADE), blurRadius: 60, spreadRadius: 20),
          BoxShadow(color: Color(0xFF1C7ADE), blurRadius: 100),
        ],
      ),
    );
  }
}

class _AnimatedPayCoin extends StatelessWidget {
  const _AnimatedPayCoin({required this.controller, required this.offset});

  final AnimationController? controller;
  final Animation<double>? offset;

  @override
  Widget build(BuildContext context) {
    final animation = offset;
    if (animation == null || controller?.isAnimating != true) {
      return Transform.translate(
        key: const ValueKey('pay_floating_badge_coin_motion'),
        offset: Offset.zero,
        child: const _PayCoinImage(),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.translate(
        key: const ValueKey('pay_floating_badge_coin_motion'),
        offset: Offset(0, animation.value),
        child: child,
      ),
      child: const _PayCoinImage(),
    );
  }
}

class _PayCoinImage extends StatelessWidget {
  const _PayCoinImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/illustrations/pay_floating_coin.png',
      key: const ValueKey('pay_floating_badge_coin'),
      width: 68,
      height: 68,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
