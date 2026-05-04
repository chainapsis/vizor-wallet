import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';

bool get _supportsWindowFocusEvents {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

class MacOSPrivacyExposureEvent {
  const MacOSPrivacyExposureEvent({
    required this.isSafe,
    required this.reason,
    this.details = const {},
  });

  final bool isSafe;
  final String reason;
  final Map<String, bool> details;

  static MacOSPrivacyExposureEvent fromPlatformEvent(Object? event) {
    final map = event as Map<Object?, Object?>? ?? const {};
    final rawDetails = map['details'] as Map<Object?, Object?>? ?? const {};
    return MacOSPrivacyExposureEvent(
      isSafe: map['isSafe'] as bool? ?? true,
      reason: map['reason'] as String? ?? 'unknown',
      details: rawDetails.map(
        (key, value) => MapEntry(key.toString(), value as bool? ?? false),
      ),
    );
  }
}

abstract final class MacOSPrivacyExposureEvents {
  static const _channel = EventChannel('com.zcash.wallet/privacy_exposure');

  static Stream<MacOSPrivacyExposureEvent> get stream {
    if (kIsWeb || !Platform.isMacOS) return const Stream.empty();
    return _channel.receiveBroadcastStream().map(
      MacOSPrivacyExposureEvent.fromPlatformEvent,
    );
  }
}

abstract final class MacOSNativePrivacyShield {
  static const _channel = MethodChannel('com.zcash.wallet/privacy_shield');

  static final Set<int> _visibleTokens = <int>{};
  static final Map<int, ui.Rect> _tokenRects = <int, ui.Rect>{};
  static int _nextToken = 0;
  static bool _lastVisible = false;
  static ui.Rect? _lastRect;

  static int createToken() => _nextToken++;

  static void updateToken(int token, bool visible, {ui.Rect? globalRect}) {
    if (visible) {
      _visibleTokens.add(token);
      if (globalRect != null && !globalRect.isEmpty) {
        _tokenRects[token] = globalRect;
      }
    } else {
      _visibleTokens.remove(token);
      _tokenRects.remove(token);
    }
    _syncIfNeeded();
  }

  static void clearToken(int token) {
    _visibleTokens.remove(token);
    _tokenRects.remove(token);
    _syncIfNeeded();
  }

  @visibleForTesting
  static void resetForTesting() {
    _visibleTokens.clear();
    _tokenRects.clear();
    _nextToken = 0;
    _lastVisible = false;
    _lastRect = null;
  }

  static void _syncIfNeeded() {
    if (kIsWeb || !Platform.isMacOS) return;
    final visible = _visibleTokens.isNotEmpty;
    final rect = _combinedVisibleRect();
    if (_lastVisible == visible && _lastRect == rect) return;
    _lastVisible = visible;
    _lastRect = rect;
    unawaited(_setSensitiveContentVisible(visible, rect));
  }

  static ui.Rect? _combinedVisibleRect() {
    ui.Rect? combined;
    for (final token in _visibleTokens) {
      final rect = _tokenRects[token];
      if (rect == null) continue;
      combined = combined?.expandToInclude(rect) ?? rect;
    }
    return combined;
  }

  static Future<void> _setSensitiveContentVisible(
    bool visible,
    ui.Rect? rect,
  ) async {
    final arguments = <String, Object?>{'visible': visible};
    if (rect != null) {
      arguments['rect'] = <String, double>{
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }

    try {
      await _channel.invokeMethod<void>(
        'setSensitiveContentVisible',
        arguments,
      );
    } catch (_) {
      // The native shield is a macOS-only fast path. The Flutter overlay still
      // handles privacy if the native channel is unavailable.
    }
  }
}

class SensitivePrivacyOverlayController extends ChangeNotifier {
  SensitivePrivacyOverlayController({bool initiallySafe = true})
    : _isSafe = initiallySafe;

  bool _isSafe;

  bool get isSafe => _isSafe;

  void markSafe() => _setSafe(true);

  void markUnsafe() => _setSafe(false);

  @protected
  void _setSafe(bool value) {
    if (_isSafe == value) return;
    _isSafe = value;
    notifyListeners();
  }
}

class SensitivePrivacyEnvironmentController
    extends SensitivePrivacyOverlayController
    with WindowListener {
  SensitivePrivacyEnvironmentController({
    Stream<MacOSPrivacyExposureEvent>? macOSExposureEvents,
  }) {
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _setLifecycleSafe(true),
      onShow: () => _setLifecycleSafe(true),
      onInactive: () => _setLifecycleSafe(false),
      onHide: () => _setLifecycleSafe(false),
      onPause: () => _setLifecycleSafe(false),
    );

    if (_supportsWindowFocusEvents) {
      windowManager.addListener(this);
      windowManager
          .isFocused()
          .then((focused) {
            if (_disposed) return;
            _setWindowSafe(focused);
          })
          .catchError((_) {
            if (!_disposed) _setWindowSafe(false);
          });
    }

    _macOSExposureSub =
        (macOSExposureEvents ?? MacOSPrivacyExposureEvents.stream).listen(
          (event) {
            _setMacOSNativeSafe(event.isSafe);
            assert(() {
              final details = event.details.entries
                  .map((entry) => '${entry.key}=${entry.value}')
                  .join(', ');
              debugPrint(
                'MacOSPrivacyExposure: ${event.isSafe ? 'safe' : 'unsafe'} '
                '(${event.reason})${details.isEmpty ? '' : ' {$details}'}',
              );
              return true;
            }());
          },
          onError: (Object error) {
            assert(() {
              debugPrint('MacOSPrivacyExposure: stream error: $error');
              return true;
            }());
          },
        );
  }

  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<MacOSPrivacyExposureEvent>? _macOSExposureSub;
  bool _lifecycleSafe = true;
  bool _windowSafe = true;
  bool _macOSNativeSafe = true;
  bool _disposed = false;

  @override
  void onWindowFocus() => _setWindowSafe(true);

  @override
  void onWindowRestore() => _setWindowSafe(true);

  @override
  void onWindowBlur() => _setWindowSafe(false);

  @override
  void onWindowMinimize() => _setWindowSafe(false);

  void _setLifecycleSafe(bool value) {
    _lifecycleSafe = value;
    _syncSafety();
  }

  void _setWindowSafe(bool value) {
    _windowSafe = value;
    _syncSafety();
  }

  void _setMacOSNativeSafe(bool value) {
    _macOSNativeSafe = value;
    _syncSafety();
  }

  void _syncSafety() {
    _setSafe(_lifecycleSafe && _windowSafe && _macOSNativeSafe);
  }

  @override
  void dispose() {
    _disposed = true;
    _macOSExposureSub?.cancel();
    _lifecycleListener?.dispose();
    if (_supportsWindowFocusEvents) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }
}

class SensitivePrivacyOverlay extends StatefulWidget {
  const SensitivePrivacyOverlay({
    required this.sensitiveContentVisible,
    required this.child,
    this.controller,
    super.key,
  });

  static const shieldKey = ValueKey('sensitive_privacy_overlay.shield');

  final bool sensitiveContentVisible;
  final Widget child;
  final SensitivePrivacyOverlayController? controller;

  @override
  State<SensitivePrivacyOverlay> createState() =>
      _SensitivePrivacyOverlayState();
}

class _SensitivePrivacyOverlayState extends State<SensitivePrivacyOverlay>
    with WidgetsBindingObserver {
  final _overlayKey = GlobalKey();
  late final int _nativeShieldToken = MacOSNativePrivacyShield.createToken();
  late SensitivePrivacyOverlayController _controller;
  late bool _ownsController;
  bool _nativeShieldSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setController(widget.controller);
    _scheduleNativeShieldSync();
  }

  @override
  void didUpdateWidget(covariant SensitivePrivacyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller.dispose();
      _setController(widget.controller);
    }
    if (oldWidget.sensitiveContentVisible != widget.sensitiveContentVisible) {
      _scheduleNativeShieldSync();
    }
  }

  void _setController(SensitivePrivacyOverlayController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? SensitivePrivacyEnvironmentController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MacOSNativePrivacyShield.clearToken(_nativeShieldToken);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleNativeShieldSync();
  }

  void _scheduleNativeShieldSync() {
    if (!widget.sensitiveContentVisible) {
      _syncNativeShield();
      return;
    }
    if (_nativeShieldSyncScheduled) return;
    _nativeShieldSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nativeShieldSyncScheduled = false;
      if (!mounted) return;
      _syncNativeShield();
    });
  }

  void _syncNativeShield() {
    MacOSNativePrivacyShield.updateToken(
      _nativeShieldToken,
      widget.sensitiveContentVisible,
      globalRect: _overlayGlobalRect(),
    );
  }

  ui.Rect? _overlayGlobalRect() {
    final renderObject = _overlayKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final size = renderObject.size;
    if (size.isEmpty) return null;
    return renderObject.localToGlobal(Offset.zero) & size;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleNativeShieldSync();
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final showShield =
            widget.sensitiveContentVisible && !_controller.isSafe;
        return Stack(
          key: _overlayKey,
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (showShield)
              const Positioned.fill(
                child: _SensitivePrivacyShield(
                  key: SensitivePrivacyOverlay.shieldKey,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SensitivePrivacyShield extends StatelessWidget {
  const _SensitivePrivacyShield({super.key});

  static const _lightScrim = Color(0x33141818);
  static const _darkScrim = Color(0x33626767);
  static const _darkSurface = Color(0xFF141818);
  static const _darkIcon = Color(0xFFE1E1E1);

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final badgeColor = isDark ? _darkSurface : const Color(0xFFFFFFFF);
    final iconColor = isDark ? _darkIcon : _darkSurface;

    return IgnorePointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: DecoratedBox(
            decoration: BoxDecoration(color: isDark ? _darkScrim : _lightScrim),
            child: Center(
              child: Container(
                width: 98,
                height: 98,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.lock,
                  size: 50,
                  color: iconColor,
                  semanticLabel: 'Sensitive content hidden',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
