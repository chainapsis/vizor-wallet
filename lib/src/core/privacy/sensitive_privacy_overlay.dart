import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';

bool get _supportsPlatformPrivacySignals => supportsPlatformPrivacySignals(
  isWeb: kIsWeb,
  isMacOS: !kIsWeb && Platform.isMacOS,
);

@visibleForTesting
bool supportsPlatformPrivacySignals({
  required bool isWeb,
  required bool isMacOS,
}) {
  // TODO(privacy-layer): Add a Windows implementation before enabling this on
  // desktop platforms other than macOS.
  return !isWeb && isMacOS;
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
  static final Stream<MacOSPrivacyExposureEvent> _stream =
      kIsWeb || !Platform.isMacOS
      ? const Stream.empty()
      : _channel.receiveBroadcastStream().map(
          MacOSPrivacyExposureEvent.fromPlatformEvent,
        );

  static Stream<MacOSPrivacyExposureEvent> get stream => _stream;
}

abstract final class MacOSSensitiveContentBridge {
  static const _channel = MethodChannel('com.zcash.wallet/privacy_shield');

  static final Set<int> _visibleTokens = <int>{};
  static int _nextToken = 0;
  static bool _lastVisible = false;

  static int createToken() => _nextToken++;

  static void updateToken(int token, bool visible) {
    if (visible) {
      _visibleTokens.add(token);
    } else {
      _visibleTokens.remove(token);
    }
    _syncIfNeeded();
  }

  static void clearToken(int token) {
    _visibleTokens.remove(token);
    _syncIfNeeded();
  }

  @visibleForTesting
  static void resetForTesting() {
    _visibleTokens.clear();
    _nextToken = 0;
    _lastVisible = false;
  }

  static void _syncIfNeeded() {
    if (kIsWeb || !Platform.isMacOS) return;
    final visible = _visibleTokens.isNotEmpty;
    if (_lastVisible == visible) return;
    _lastVisible = visible;
    unawaited(_setSensitiveContentVisible(visible));
  }

  static Future<void> _setSensitiveContentVisible(bool visible) async {
    final arguments = <String, Object?>{'visible': visible};

    try {
      await _channel.invokeMethod<void>(
        'setSensitiveContentVisible',
        arguments,
      );
    } catch (_) {
      // This bridge only controls macOS window policy/exposure events. The
      // Flutter overlay remains the visual privacy layer if the channel fails.
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
    if (_supportsPlatformPrivacySignals) {
      _lifecycleListener = AppLifecycleListener(
        onResume: () => _setLifecycleSafe(true),
        onShow: () => _setLifecycleSafe(true),
        // iOS snapshots during inactive, before pause. Keep sensitive content
        // covered as soon as the app starts losing foreground interaction.
        onInactive: () => _setLifecycleSafe(false),
        onHide: () => _setLifecycleSafe(false),
        onPause: () => _setLifecycleSafe(false),
      );
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
    if (_supportsPlatformPrivacySignals) {
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

class _SensitivePrivacyOverlayState extends State<SensitivePrivacyOverlay> {
  late final int _nativeVisibilityToken =
      MacOSSensitiveContentBridge.createToken();
  late SensitivePrivacyOverlayController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _setController(widget.controller);
    _syncNativeVisibility();
  }

  @override
  void didUpdateWidget(covariant SensitivePrivacyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller.dispose();
      _setController(widget.controller);
    }
    if (oldWidget.sensitiveContentVisible != widget.sensitiveContentVisible) {
      _syncNativeVisibility();
    }
  }

  void _setController(SensitivePrivacyOverlayController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? SensitivePrivacyEnvironmentController();
  }

  @override
  void dispose() {
    MacOSSensitiveContentBridge.clearToken(_nativeVisibilityToken);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _syncNativeVisibility() {
    MacOSSensitiveContentBridge.updateToken(
      _nativeVisibilityToken,
      widget.sensitiveContentVisible,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final showShield =
            widget.sensitiveContentVisible && !_controller.isSafe;
        return Stack(
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
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
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
