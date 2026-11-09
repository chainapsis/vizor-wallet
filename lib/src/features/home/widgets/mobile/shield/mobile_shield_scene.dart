import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../../../../core/formatting/zec_amount.dart';
import '../../../../../core/privacy/privacy_mask.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/app_button.dart';
import 'balance_art.dart';
import 'keystone_shield_morph.dart';
import 'mobile_shield_backdrop.dart';
import 'particles/particle_field.dart';
import 'shield_background.dart';
import 'shield_haptics.dart';
import 'shield_icon.dart';
import 'shield_motion.dart';
import 'shield_hardware_motion.dart';
import 'shield_particle_art.dart';
import 'shield_timeline.dart';
import 'slide_to_shield.dart';

/// The scene draws `ZEC` beside the amount, so the amount stays bare.
String mobileShieldAmountText(
  BigInt zatoshi, {
  required bool privacyModeEnabled,
}) => hideIfPrivacyMode(
  formatZecAmount(zatoshi),
  privacyModeEnabled: privacyModeEnabled,
);

// Transaction owners supply real states. This presentation never starts a
// transaction, guesses its progress, or treats a pending broadcast as success.
enum MobileShieldPhase { review, working, hardware, succeeded, pending, failed }

class MobileShieldScene extends StatefulWidget {
  const MobileShieldScene({
    required this.phase,
    required this.amount,
    required this.title,
    this.resultAmount,
    this.showResultAmount = true,
    this.backdrop,
    this.body,
    this.focusChild,
    this.focusBuilder,
    this.keystoneFocus,
    this.footer,
    this.onCommit,
    this.onClose,
    this.onPrevious,
    this.onComplete,
    this.canLeave = true,
    this.animateHardware = false,
    super.key,
  });
  final MobileShieldPhase phase;
  final String amount;
  final String? resultAmount;
  final bool showResultAmount;
  final MobileShieldBackdrop? backdrop;
  final String title;
  final String? body;
  final Widget? focusChild;
  final Widget Function(BuildContext, BoxConstraints)? focusBuilder;
  final KeystoneShieldFocus? keystoneFocus;
  final Widget? footer;
  final VoidCallback? onCommit;
  final VoidCallback? onClose;

  /// System Back may navigate a nested hardware help step. Close stays separate.
  final VoidCallback? onPrevious;
  final VoidCallback? onComplete;
  final bool canLeave;
  final bool animateHardware;

  @override
  State<MobileShieldScene> createState() => _MobileShieldSceneState();
}

class _MobileShieldSceneState extends State<MobileShieldScene>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  final _clock = ValueNotifier<double>(0);
  final _drag = ValueNotifier<double>(0);
  ShieldParticleArt? _art;
  ParticleField? _field;
  Duration _elapsed = Duration.zero;
  double? _assemblyAt;
  bool _successHaptic = false;
  bool _landHaptic = false;
  bool _reduce = false;
  bool _focusRevealed = false;
  int _preparation = 0;
  late double _beforeFontSize;
  late double _afterFontSize;
  _ShieldLayout? _layout;
  ui.Image? _backdropImage;
  KeystoneShieldMorph? _keystone;
  String? _keystoneFocusTitle;
  Widget? _keystoneFooter;
  bool _retargeting = false;
  final _hardware = ShieldHardwareMotion();
  Widget? _hardwareChild;

  bool get _review => widget.phase == MobileShieldPhase.review;
  double? get _a => _assemblyAt == null ? null : _clock.value - _assemblyAt!;
  String get _result => widget.resultAmount ?? widget.amount;

  @override
  void initState() {
    super.initState();
    _backdropImage = widget.backdrop?.image.clone();
    _hardwareChild = widget.focusChild;
    if (widget.keystoneFocus != null) {
      _keystone = KeystoneShieldMorph()..configure(widget.keystoneFocus!);
      _keystoneFocusTitle = widget.title;
      _keystoneFooter = widget.footer;
      unawaited(_keystone!.prepare());
    }
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduce) {
      _reduce = reduce;
      _field?.reduceMotion = reduce;
    }
    if (!_ticker.isActive && !_review) _ticker.start();
  }

  @override
  void didUpdateWidget(MobileShieldScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusChild != null) _hardwareChild = widget.focusChild;
    if (widget.keystoneFocus != null) {
      if (widget.keystoneFocus!.stage != KeystoneShieldFocusStage.cloud) {
        _keystoneFocusTitle = widget.title;
      }
      _keystone?.configure(widget.keystoneFocus!);
      if (widget.footer != null &&
          widget.phase != MobileShieldPhase.failed &&
          widget.phase != MobileShieldPhase.pending) {
        _keystoneFooter = widget.footer;
      }
    }
    if (oldWidget.backdrop != widget.backdrop) {
      final next = widget.backdrop?.image.clone();
      _backdropImage?.dispose();
      _backdropImage = next;
    }
    if (oldWidget.amount != widget.amount ||
        oldWidget.resultAmount != widget.resultAmount ||
        oldWidget.showResultAmount != widget.showResultAmount) {
      _retargeting = _art != null;
      _prepare();
    }
    if (oldWidget.phase == MobileShieldPhase.review && !_review) {
      if (!_ticker.isActive) _ticker.start();
    }
    if (oldWidget.phase != widget.phase &&
        widget.phase == MobileShieldPhase.succeeded) {
      _assemblyAt = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _elapsed = Duration.zero;
      if (!_review && !_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  double _fitFont(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: VText.display.copyWith(
          fontSize: 84,
          fontWeight: FontWeight.w700,
          height: 1,
          letterSpacing: -3.36,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = math.min(84.0, 84 * 345 / math.max(1, painter.width));
    painter.dispose();
    return size;
  }

  Future<void> _prepare() async {
    final generation = ++_preparation;
    _beforeFontSize = _fitFont(widget.amount);
    _afterFontSize = _fitFont(_result);
    try {
      final art = await ShieldParticleArt.load(
        widget.amount,
        resultAmount: _result,
        showResultAmount: widget.showResultAmount,
        count: shieldCloudDots.length,
        random: math.Random(7),
        fontSize: _beforeFontSize,
        resultFontSize: _afterFontSize,
      );
      if (!mounted || generation != _preparation) {
        art.dispose();
        return;
      }
      if (_layout != null) {
        _field?.updateTargets(_geometry(art, _layout!), art.atlas);
      }
      final old = _art;
      setState(() {
        _art = art;
        _retargeting = false;
      });
      old?.dispose();
    } catch (error, stack) {
      if (mounted && generation == _preparation) _retargeting = false;
      debugPrint('Shield artwork preparation failed: $error\n$stack');
      // Keep the readable amounts and real operation controls usable even if
      // decorative assets cannot be prepared.
    }
  }

  FieldGeometry _geometry(ShieldParticleArt art, _ShieldLayout layout) {
    final before = _balance(widget.amount, false);
    final after = _balance(_result, true);
    final scale = layout.artScale;
    final center = layout.cloudCenter;
    final textRect = Rect.fromLTWH(
      layout.centerX - before.size.width * scale / 2,
      layout.amountTop,
      before.size.width * scale,
      before.size.height * scale,
    );
    final resultRect = Rect.fromLTWH(
      layout.centerX - after.size.width * scale / 2,
      layout.amountTop,
      after.size.width * scale,
      after.size.height * scale,
    );
    final shieldRect = Rect.fromCenter(
      center: center,
      width: art.shieldSize.width * scale,
      height: art.shieldSize.height * scale,
    );
    return FieldGeometry(
      cloudCenter: center,
      cloudSlots: [
        for (final dot in shieldCloudDots)
          center + (dot.p - const Offset(196, 386.7)) * scale,
      ],
      cloudSizes: [for (final dot in shieldCloudDots) dot.size * scale],
      cloudAlphas: [for (final dot in shieldCloudDots) dot.alpha],
      textRect: textRect,
      textPoints: [for (final point in art.textPoints) point * scale],
      shieldRect: shieldRect,
      shieldSlots: [
        for (final point in art.shieldCells) shieldRect.topLeft + point * scale,
      ],
      balancePoints: [
        for (final point in art.balancePoints)
          resultRect.topLeft + point * scale,
      ],
      iconPoints: [
        for (final point in art.iconPoints)
          layout.iconCenter +
              (point -
                      Offset(
                        ShieldParticleArt.iconWidth / 2,
                        ShieldParticleArt.iconHeight / 2,
                      )) *
                  scale,
      ],
      textDimFrom: before.unitFrom * scale,
      balanceDimFrom: resultRect.top + after.unitFrom * scale,
      screen: layout.contentSize,
      emitter: center,
    );
  }

  BalanceArt _balance(String amount, bool shielded) => BalanceArt(
    amount,
    look: shielded ? BalanceLook.shielded : BalanceLook.transparent,
    unitTop: BalanceArt.unitOffset,
    fontSize: shielded ? _afterFontSize : _beforeFontSize,
  );

  void _tick(Duration elapsed) {
    // Ticker.start resets its elapsed time; retain scene time across resume.
    final step = (elapsed - _elapsed).inMicroseconds / 1e6;
    _elapsed = elapsed;
    final t = _clock.value + math.max(0.0, step);
    if (widget.animateHardware) {
      _hardware.reduceMotion = _reduce;
      _hardware.configure(
        widget.focusChild != null && t >= ShieldTimeline.fall.end,
        _clock.value,
      );
      _hardware.update(t);
    }
    if (_art != null && _field == null && _layout != null) {
      _field = ParticleField(
        geometry: _geometry(_art!, _layout!),
        atlas: _art!.atlas,
        reduceMotion: _reduce,
      );
    }
    if (widget.phase == MobileShieldPhase.succeeded &&
        _assemblyAt == null &&
        !_retargeting &&
        (!widget.animateHardware || !_hardware.active) &&
        (_keystone?.cloudReady ?? true) &&
        t >= 3) {
      _assemblyAt = t;
    }
    final a = _assemblyAt == null ? null : t - _assemblyAt!;
    _field?.hapticsEnabled =
        widget.phase == MobileShieldPhase.working ||
        widget.phase == MobileShieldPhase.succeeded;
    _field?.captureProjectedParticles = _keystone != null;
    _field?.update(t, a);
    final morph = _keystone;
    if (morph != null && t >= ShieldTimeline.fall.end) {
      morph.reduceMotion = _reduce;
      morph.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      morph.update(t, _field?.projectedParticles ?? const []);
    }
    if (a != null && a >= ShieldTimeline.lock && !_successHaptic) {
      _successHaptic = true;
      Haptics.success();
    }
    if (a != null && a >= ShieldTimeline.land && !_landHaptic) {
      _landHaptic = true;
      Haptics.impact(ImpactStyle.soft);
    }
    _clock.value = t;
    if (!_focusRevealed && t >= ShieldTimeline.fall.end) {
      setState(() => _focusRevealed = true);
    }
    if (_reduce && a != null && a >= ShieldTimeline.done) _ticker.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _clock.dispose();
    _drag.dispose();
    _field?.dispose();
    _keystone?.dispose();
    _art?.dispose();
    _backdropImage?.dispose();
    super.dispose();
  }

  double _headingHeight(double width) {
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: AppTypography.bodyMedium),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: math.max(1, width - 48));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return math.max(
      measure('Transparent Balance'),
      measure('Shielded successfully'),
    );
  }

  bool get _ready =>
      widget.phase == MobileShieldPhase.succeeded &&
      (_a ?? 0) >= ShieldTimeline.completeIn.end;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Color(0xFF000000),
    ),
    child: AppTheme(
      data: AppThemeData.dark,
      child: PopScope(
        canPop: widget.onClose == null && widget.canLeave,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.canLeave) {
            (widget.onPrevious ?? widget.onClose)?.call();
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0x00000000),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0xFF000000),
                    child: _backdropImage == null
                        ? null
                        : ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: 7.5,
                              sigmaY: 7.5,
                              tileMode: ui.TileMode.clamp,
                            ),
                            child: RawImage(
                              image: _backdropImage,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _clock,
                builder: (_, _) => CustomPaint(
                  painter: ShieldScrimPainter(
                    _a == null
                        ? 0
                        : ShieldTimeline.backgroundShift.eased(
                            _a!,
                            VMotion.ease,
                          ),
                  ),
                ),
              ),
              if (_keystone != null)
                AnimatedBuilder(
                  animation: _clock,
                  builder: (_, _) => IgnorePointer(
                    child: ColoredBox(
                      key: const ValueKey('mobile_keystone_black_background'),
                      color: Color.fromRGBO(0, 0, 0, _keystone!.blackMix),
                    ),
                  ),
                ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final layout = _ShieldLayout(
                      constraints.biggest,
                      headingHeight: _headingHeight(constraints.maxWidth),
                      amountHeight: math.max(
                        _balance(widget.amount, false).size.height,
                        _balance(_result, true).size.height,
                      ),
                    );
                    if (_layout?.size != layout.size ||
                        _layout?.headingHeight != layout.headingHeight ||
                        _layout?.amountHeight != layout.amountHeight) {
                      _layout = layout;
                      if (_art != null) {
                        _field?.updateTargets(
                          _geometry(_art!, layout),
                          _art!.atlas,
                        );
                      }
                    }
                    return AnimatedBuilder(
                      animation: _clock,
                      builder: (_, _) {
                        final auxiliary =
                            (widget.animateHardware && _hardware.active) ||
                            (_keystone?.active ?? false) ||
                            widget.focusChild != null ||
                            widget.focusBuilder != null ||
                            widget.phase == MobileShieldPhase.failed ||
                            widget.phase == MobileShieldPhase.pending;
                        final content = Stack(
                          key: _keystone?.spaceKey,
                          fit: StackFit.expand,
                          children: [
                            _visual(layout, auxiliary && _focusRevealed),
                            if (auxiliary)
                              _functionalContent(constraints)
                            else
                              _normalControls(layout),
                            if (_keystone != null && _focusRevealed)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _KeystoneMorphPainter(
                                      _keystone!,
                                      _clock,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                        if (!auxiliary &&
                            layout.contentHeight > constraints.maxHeight) {
                          return SingleChildScrollView(
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: layout.contentHeight,
                              child: content,
                            ),
                          );
                        }
                        return content;
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _normalControls(_ShieldLayout layout) {
    final a = _a;
    final t = _clock.value;
    final sliderOut = _review ? 0.0 : ShieldTimeline.sliderOut.eased(t);
    final statusIn = !_review ? ShieldTimeline.statusIn.eased(t) : 0.0;
    final statusOut = a == null ? 0.0 : ShieldTimeline.statusOut.eased(a);
    final completeIn = a == null
        ? 0.0
        : ShieldTimeline.completeIn.eased(a, VMotion.ease);
    return Stack(
      children: [
        if (sliderOut < 1)
          Positioned(
            left: layout.centerX - layout.sliderWidth / 2,
            top: layout.actionTop,
            child: Opacity(
              opacity: 1 - sliderOut,
              child: IgnorePointer(
                ignoring: !_review,
                child: SlideToShield(
                  key: const ValueKey('mobile_shield_slide'),
                  width: layout.sliderWidth,
                  progress: _drag,
                  onCommitted: () => widget.onCommit?.call(),
                ),
              ),
            ),
          ),
        if (!_review && statusIn > 0 && statusOut < 1)
          Positioned(
            left: 24,
            right: 24,
            top: layout.actionTop,
            child: SizedBox(
              height: SlideToShield.height,
              child: Center(
                child: Opacity(
                  opacity: statusIn * (1 - statusOut),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.phase == MobileShieldPhase.succeeded
                          ? 'Shielding your balance…'
                          : widget.title,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: const Color(0xB3FFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (completeIn > 0)
          Positioned(
            left: layout.centerX - 176.5 / 2,
            top: layout.actionTop,
            child: Opacity(
              key: const ValueKey('mobile_shield_complete_fade'),
              opacity: completeIn,
              child: ExcludeSemantics(
                excluding: !_ready,
                child: SizedBox(
                  width: 176.5,
                  height: 50,
                  child: AppButton(
                    key: const ValueKey('mobile_shield_complete'),
                    onPressed: _ready ? widget.onComplete : null,
                    expand: true,
                    constrainContent: true,
                    variant: AppButtonVariant.secondary,
                    disabledBackgroundColor: const Color(0xFFFFFFFF),
                    enabledBackgroundColor: const Color(0xFFFFFFFF),
                    enabledLabelColor: const Color(0xFF141818),
                    child: Text(
                      'Complete',
                      style: AppTypography.bodyMedium.copyWith(
                        color: const Color(0xFF141818),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.onClose != null &&
            (_review ? widget.canLeave : sliderOut < 1))
          Positioned(
            left: 24,
            right: 24,
            top: layout.cancelCenter - 24,
            child: Opacity(
              opacity: 1 - sliderOut,
              child: ExcludeSemantics(
                excluding: !_review,
                child: IgnorePointer(
                  ignoring: !_review,
                  child: Center(child: _cancel()),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cancel() => Semantics(
    button: true,
    label: 'Cancel',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.canLeave ? widget.onClose : null,
      child: SizedBox(
        width: 100,
        height: 48,
        child: Center(
          child: Text(
            'Cancel',
            style: AppTypography.bodyMedium.copyWith(
              color: const Color(0x99FFFFFF),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _functionalContent(BoxConstraints constraints) {
    if (widget.animateHardware) {
      final interactive = _hardware.interactive && widget.focusChild != null;
      final horizontal = constraints.maxWidth < 360 ? 28.0 : 32.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 20),
        child: ShieldHardwarePresentation(
          mix: _hardware.mix,
          footerOpacity: _hardware.footer,
          footerDy: _hardware.footerDy,
          interactive: interactive,
          child: ExcludeSemantics(
            excluding: !interactive,
            child: ExcludeFocus(
              excluding: !interactive,
              child: IgnorePointer(
                ignoring: !interactive,
                child: Center(
                  child: SizedBox(
                    width: math.min(
                      360,
                      math.max(0, constraints.maxWidth - horizontal * 2),
                    ),
                    height: double.infinity,
                    child: widget.focusChild ?? _hardwareChild,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final morph = _keystone;
    final footer =
        widget.footer ?? (morph?.active == true ? _keystoneFooter : null);
    final animateFooter =
        morph != null &&
        widget.phase != MobileShieldPhase.failed &&
        widget.phase != MobileShieldPhase.pending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, available) {
                final morph = _keystone;
                final focus = widget.keystoneFocus;
                final child = morph != null && focus != null
                    ? SizedBox(
                        width: math.min(360, available.maxWidth),
                        height: available.maxHeight,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (morph.stage == KeystoneShieldFocusStage.qr)
                              KeystoneShieldAnchor(
                                key: const ValueKey(
                                  'mobile_shield_keystone_qr',
                                ),
                                morph: morph,
                                kind: KeystoneShieldAnchorKind.qr,
                                child: SizedBox.square(
                                  dimension: math.max(
                                    1,
                                    math.min(
                                      312,
                                      math.min(
                                        available.maxWidth,
                                        available.maxHeight,
                                      ),
                                    ),
                                  ),
                                  child: Semantics(
                                    label: 'Keystone transaction QR',
                                  ),
                                ),
                              ),
                            if (morph.scannerVisible)
                              focus.scannerBuilder(available, morph),
                          ],
                        ),
                      )
                    : widget.focusBuilder?.call(
                            context,
                            BoxConstraints(
                              maxWidth: math.min(360, available.maxWidth),
                              maxHeight: available.maxHeight,
                            ),
                          ) ??
                          widget.focusChild;
                if (!_focusRevealed) return const SizedBox.shrink();
                return Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 360),
                      child: child,
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.focusChild == null)
            Opacity(
              opacity: _keystone?.leavingOpacity ?? 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.26,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        widget.phase == MobileShieldPhase.succeeded &&
                                (_keystone?.active ?? false)
                            ? _keystoneFocusTitle ?? 'Shielding your balance…'
                            : widget.title,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                      if (widget.body != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            widget.body!,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: const Color(0xCCFFFFFF),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (footer != null)
            if (animateFooter)
              ExcludeSemantics(
                excluding: !morph.footerInteractive,
                child: ExcludeFocus(
                  excluding: !morph.footerInteractive,
                  child: IgnorePointer(
                    ignoring: !morph.footerInteractive,
                    child: Opacity(
                      key: const ValueKey('mobile_keystone_footer_visibility'),
                      opacity: morph.footerOpacity,
                      child: Transform.translate(
                        offset: Offset(0, morph.footerDy),
                        child: footer,
                      ),
                    ),
                  ),
                ),
              )
            else
              footer
          else if (widget.focusChild == null &&
              widget.canLeave &&
              widget.onClose != null)
            _cancel(),
        ],
      ),
    );
  }

  Widget _visual(_ShieldLayout layout, bool auxiliary) {
    final a = _a;
    final t = _clock.value;
    final before = _balance(widget.amount, false);
    final after = _balance(_result, true);
    final header = _review ? 1.0 : 1 - ShieldTimeline.headerOut.eased(t);
    Widget icon(String asset, double opacity) => Positioned(
      left: layout.iconCenter.dx - 20 * layout.artScale,
      top: layout.iconCenter.dy - 20 * layout.artScale,
      child: Opacity(
        opacity: opacity,
        child: ShieldIcon(
          asset,
          box: Size.square(40 * layout.artScale),
          width:
              (asset == 'overlay_transparent' ? 36.6667 : 32) * layout.artScale,
          height: 37 * layout.artScale,
        ),
      ),
    );
    Widget title(String text, double opacity) => Positioned(
      left: 24,
      right: 24,
      top: layout.titleTop,
      child: SizedBox(
        height: layout.headingHeight,
        child: Center(
          child: Opacity(
            opacity: opacity,
            child: Text(
              text,
              key: const ValueKey('mobile_shield_heading'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
        ),
      ),
    );
    Widget balance(BalanceArt art, {required bool result}) {
      final textIn = result
          ? ShieldTimeline.textIn.eased(a!, VMotion.ease)
          : 1.0;
      final paint = CustomPaint(
        key: ValueKey(
          result ? 'mobile_shield_result_amount' : 'mobile_shield_amount',
        ),
        size: art.size,
        painter: _BalancePainter(art),
      );
      final dy = result || _review || _reduce
          ? 0.0
          : ShieldTimeline.fallDy(t) * layout.artScale;
      return Positioned(
        left: layout.centerX - art.size.width * layout.artScale / 2,
        top: layout.amountTop + dy,
        child: Semantics(
          label: '${result ? _result : widget.amount} ZEC',
          child: ExcludeSemantics(
            child: Transform.scale(
              alignment: Alignment.topLeft,
              scale:
                  layout.artScale *
                  (result || _review || _reduce
                      ? 1
                      : ShieldTimeline.fallScale(t)),
              child: Opacity(
                opacity: result
                    ? textIn
                    : _review || !_reduce
                    ? 1
                    : 1 - ShieldTimeline.dissolve(t),
                child: _AmountDissolve(
                  progress: result || _review || _reduce
                      ? 0
                      : ShieldTimeline.dissolve(t),
                  child: result && !_reduce
                      ? ImageFiltered(
                          enabled: textIn < 0.995,
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 8 * (1 - textIn),
                            sigmaY: 8 * (1 - textIn),
                          ),
                          child: paint,
                        )
                      : paint,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_art != null &&
              !_review &&
              (!auxiliary || widget.animateHardware))
            Positioned.fill(
              child: CustomPaint(
                painter: _CloudGlow(
                  _art!,
                  layout.cloudCenter,
                  layout.artScale,
                  (widget.animateHardware ? 1 - _hardware.mix : 1) *
                      ShieldTimeline.glowTextIn.eased(t) *
                      (1 -
                          (a == null
                              ? 0.0
                              : ShieldTimeline.glowTextOut.eased(a))),
                ),
              ),
            ),
          if (_field != null &&
              !(_focusRevealed &&
                  (_keystone?.active ?? false) &&
                  _keystone!.particles.isNotEmpty))
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter:
                      widget.animateHardware ||
                          (auxiliary && !(_keystone?.active ?? false))
                      ? _FocusParticles(
                          _field!,
                          layout.cloudCenter,
                          mix: widget.animateHardware ? _hardware.mix : 1,
                        )
                      : ParticlePainter(_field!),
                ),
              ),
            ),
          if (!auxiliary && (_review || t < ShieldTimeline.fall.end)) ...[
            icon('overlay_transparent', header * 0.6),
            title(_review ? widget.title : 'Transparent Balance', header),
            balance(before, result: false),
          ],
          if (!auxiliary && a != null && a >= ShieldTimeline.textIn.start) ...[
            icon('success_shield_fill', ShieldTimeline.iconIn.eased(a)),
            title(widget.title, ShieldTimeline.successLabelIn.eased(a)),
            if (widget.showResultAmount) balance(after, result: true),
          ],
        ],
      ),
    );
  }
}

/// One vertical composition, using the original video's relative anchors.
/// Only artwork shrinks on narrow screens; controls retain usable hit targets.
class _ShieldLayout {
  _ShieldLayout(
    this.size, {
    required this.headingHeight,
    required this.amountHeight,
  });
  final Size size;
  final double headingHeight;
  final double amountHeight;
  double get centerX => size.width / 2;
  double get artScale => math.min(1.0, math.max(0.1, (size.width - 48) / 345));
  Offset get iconCenter => Offset(centerX, size.height * 0.215);
  double get titleTop => math.max(
    size.height * 0.332 - headingHeight / 2,
    iconCenter.dy + 20 * artScale + 24,
  );
  double get amountTop =>
      math.max(size.height * 0.405, titleTop + headingHeight + 12);
  Offset get cloudCenter => Offset(centerX, size.height * 0.43);
  double get actionTop =>
      math.max(size.height * 0.666, amountTop + amountHeight * artScale + 32);
  double get cancelCenter =>
      math.max(size.height * 0.906, actionTop + SlideToShield.height + 56);
  double get contentHeight => math.max(size.height, cancelCenter + 40);
  Size get contentSize => Size(size.width, contentHeight);
  double get sliderWidth => math.min(284, math.max(61, size.width - 48));
}

class _BalancePainter extends CustomPainter {
  _BalancePainter(this.art);
  final BalanceArt art;
  @override
  void paint(Canvas canvas, Size size) => art.paint(canvas);
  @override
  bool shouldRepaint(_BalancePainter old) => true;
}

class _CloudGlow extends CustomPainter {
  const _CloudGlow(this.art, this.center, this.scale, this.opacity);
  final ShieldParticleArt art;
  final Offset center;
  final double scale;
  final double opacity;
  @override
  void paint(Canvas canvas, Size size) {
    final baked = art.glowText;
    final origin =
        center - Offset(art.glowSize.width, art.glowSize.height) * scale / 2;
    canvas.drawImageRect(
      baked.image,
      Rect.fromLTWH(
        0,
        0,
        baked.image.width.toDouble(),
        baked.image.height.toDouble(),
      ),
      (origin + baked.rect.topLeft * scale) & (baked.rect.size * scale),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity * 0.7),
    );
  }

  @override
  bool shouldRepaint(_CloudGlow old) =>
      old.art != art ||
      old.center != center ||
      old.scale != scale ||
      old.opacity != opacity;
}

/// Fade particles out behind readable hardware content without carving a
/// rectangular frame into the cloud. The QR itself keeps its white quiet zone.
class _FocusParticles extends CustomPainter {
  _FocusParticles(this.field, this.center, {this.mix = 1})
    : super(repaint: field);
  final double mix;
  final ParticleField field;
  final Offset center;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1 + 0.35 * mix);
    canvas.translate(-center.dx, -center.dy);
    field.paint(canvas);
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = ui.BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          center,
          math.min(size.width * 0.7, 260),
          [
            Color.fromRGBO(255, 255, 255, 1 - mix),
            Color.fromRGBO(255, 255, 255, 1 - 0.8 * mix),
            Color.fromRGBO(255, 255, 255, 1 - (1 - 0x88 / 255) * mix),
          ],
          const [0, 0.5, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FocusParticles old) =>
      old.field != field || old.center != center || old.mix != mix;
}

class _AmountDissolve extends StatelessWidget {
  const _AmountDissolve({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0) return child;
    if (progress >= 1) return const SizedBox.shrink();
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final edge = bounds.height * 0.08;
        final front =
            bounds.height + edge - (bounds.height + 2 * edge) * progress;
        return ui.Gradient.linear(
          Offset(0, front - edge),
          Offset(0, front + edge),
          const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        );
      },
      child: child,
    );
  }
}

class _KeystoneMorphPainter extends CustomPainter {
  _KeystoneMorphPainter(this.morph, Listenable clock) : super(repaint: clock);
  final KeystoneShieldMorph morph;
  @override
  void paint(Canvas canvas, Size size) => morph.paint(canvas);
  @override
  bool shouldRepaint(_KeystoneMorphPainter old) => old.morph != morph;
}
