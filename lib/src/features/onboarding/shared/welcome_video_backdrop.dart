import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// The Welcome background, decoded by the native video player.
/// Both mobile and desktop clips include a brief loop crossfade.
class WelcomeVideoBackdrop extends StatefulWidget {
  const WelcomeVideoBackdrop({
    required this.videoAsset,
    required this.posterAsset,
    this.animatedImageAsset,
    this.animate = true,
    super.key,
  });

  final String videoAsset;
  final String posterAsset;

  /// Multiframe image used where the native video plugin is unavailable.
  final String? animatedImageAsset;

  /// Deterministic previews use the source poster instead of a native texture.
  final bool animate;

  @override
  State<WelcomeVideoBackdrop> createState() => _WelcomeVideoBackdropState();
}

class _WelcomeVideoBackdropState extends State<WelcomeVideoBackdrop>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _initializationStarted = false;
  bool _visible = false;
  bool _foreground = true;
  bool _updatingPlayback = false;

  bool get _usesAnimatedImageBackend {
    if (kIsWeb || widget.animatedImageAsset == null) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateVisibility();
  }

  @override
  void didUpdateWidget(WelcomeVideoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateVisibility();
  }

  void _updateVisibility() {
    _visible =
        widget.animate &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (_usesAnimatedImageBackend) return;
    if (_visible && _foreground && !_initializationStarted) {
      _initializationStarted = true;
      unawaited(_initialize());
    } else {
      unawaited(_updatePlayback());
    }
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.asset(
      widget.videoAsset,
      // This widget owns lifecycle and route visibility together. Disable
      // the controller's separate lifecycle observer so native commands
      // cannot race with that observer's automatic pause/resume.
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: true,
        preventsDisplaySleepDuringVideoPlayback: false,
      ),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() {});
      await _updatePlayback();
    } catch (error) {
      // A failed native decoder keeps the original poster visible.
      if (mounted) debugPrint('Welcome video could not initialize: $error');
    }
  }

  Future<void> _updatePlayback() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _updatingPlayback) {
      return;
    }
    _updatingPlayback = true;
    try {
      // Serialize native commands and apply the latest visibility after an
      // in-flight command finishes (e.g. quick push/pop or pause/resume).
      while (mounted) {
        final shouldPlay = _visible && _foreground;
        if (shouldPlay) {
          await controller.play();
        } else {
          await controller.pause();
        }
        if (shouldPlay == (_visible && _foreground)) break;
      }
    } catch (error) {
      if (mounted) debugPrint('Welcome video playback failed: $error');
    } finally {
      _updatingPlayback = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_usesAnimatedImageBackend) {
      if (_foreground != foreground && mounted) {
        setState(() => _foreground = foreground);
      }
      return;
    }
    _foreground = foreground;
    if (_visible && _foreground && !_initializationStarted) {
      _initializationStarted = true;
      unawaited(_initialize());
      return;
    }
    unawaited(_updatePlayback());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final motionEnabled =
        widget.animate && !MediaQuery.disableAnimationsOf(context);
    final animatedImageAsset = widget.animatedImageAsset;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              widget.posterAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
            if (_usesAnimatedImageBackend &&
                motionEnabled &&
                animatedImageAsset != null)
              TickerMode(
                enabled: _visible && _foreground,
                child: Image.asset(
                  animatedImageAsset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            // Keep the paused frame during a route transition; replacing it
            // with the poster would visibly jump back to the first frame.
            if (!_usesAnimatedImageBackend &&
                motionEnabled &&
                controller != null &&
                controller.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
