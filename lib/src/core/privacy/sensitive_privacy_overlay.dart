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

bool get _supportsNativePrivacyShield => supportsNativePrivacyShield(
  isWeb: kIsWeb,
  isMacOS: !kIsWeb && Platform.isMacOS,
  isAndroid: !kIsWeb && Platform.isAndroid,
  isIOS: !kIsWeb && Platform.isIOS,
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

/// Whether the platform can natively blank the app in OS screenshots and
/// screen recordings via the `com.zcash.wallet/privacy_shield` channel.
///
/// - macOS suppresses Mission Control capture of the window.
/// - Android sets `FLAG_SECURE`.
/// - iOS re-parents the window layer into a `secureTextEntry` field's canvas
///   (see `SecureScreenshotShield` in `ios/Runner/AppDelegate.swift`); the
///   screenshot warning sheet stays as a secondary post-capture UX because
///   iOS only notifies after the capture completes.
@visibleForTesting
bool supportsNativePrivacyShield({
  required bool isWeb,
  required bool isMacOS,
  required bool isAndroid,
  required bool isIOS,
}) {
  return !isWeb && (isMacOS || isAndroid || isIOS);
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

abstract final class NativeSensitiveContentBridge {
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
    if (!_supportsNativePrivacyShield) return;
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
      // This bridge only controls native window screenshot policy. The Flutter
      // overlay remains the visual privacy layer if the channel fails.
    }
  }
}

@visibleForTesting
typedef MacOSSensitiveContentBridge = NativeSensitiveContentBridge;

class SensitivePrivacyOverlayController extends ChangeNotifier {
  SensitivePrivacyOverlayController({bool initiallySafe = true})
    : _isSafe = initiallySafe;

  bool _isSafe;
  bool _authPromptActive = false;
  bool _screenshotSuppressionActive = false;

  /// Whether sensitive content may be shown unobscured.
  bool get isSafe => _isSafe;

  void markSafe() => _setSafe(true);

  void markUnsafe() => _setSafe(false);

  /// Marks an in-app biometric prompt as active. The environment controller
  /// uses this only to suppress the false `inactive` lifecycle transition that
  /// iOS emits while the prompt is covering the app.
  void beginAuthPrompt() {
    if (_authPromptActive) return;
    _authPromptActive = true;
    notifyListeners();
  }

  /// Releases the [beginAuthPrompt] marker. Subclasses may override to defer
  /// release until the app has returned to foreground.
  void endAuthPrompt() {
    if (!_authPromptActive) return;
    _authPromptActive = false;
    notifyListeners();
  }

  /// Suppresses the shield through the brief `inactive` transition the iOS
  /// screenshot preview/editor causes. The native secure-field blanking already
  /// blacks out the actual capture and the warning sheet already explains it, so
  /// the extra blur flash during the screenshot flow is pure noise. The
  /// environment controller auto-releases this on the next foreground return.
  void beginScreenshotSuppression() {
    if (_screenshotSuppressionActive) return;
    _screenshotSuppressionActive = true;
    notifyListeners();
  }

  /// Releases the [beginScreenshotSuppression] marker.
  void endScreenshotSuppression() {
    if (!_screenshotSuppressionActive) return;
    _screenshotSuppressionActive = false;
    notifyListeners();
  }

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
    if (!kIsWeb) {
      _lifecycleListener = AppLifecycleListener(
        onResume: _setLifecycleForeground,
        onShow: _setLifecycleForeground,
        // iOS snapshots during inactive, before pause. Keep sensitive content
        // covered as soon as the app starts losing foreground interaction.
        onInactive: _setLifecycleInactive,
        onHide: _setLifecycleHidden,
        onPause: _setLifecycleHidden,
      );
    }

    if (_supportsPlatformPrivacySignals) {
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
  bool _lifecycleInactive = false;
  bool _windowSafe = true;
  bool _macOSNativeSafe = true;
  bool _disposed = false;
  bool _deferAuthClear = false;
  Timer? _screenshotSuppressionTimer;

  @override
  void beginAuthPrompt() {
    if (_authPromptActive) return;
    super.beginAuthPrompt();
    _syncSafety();
  }

  @override
  void endAuthPrompt() {
    if (!_authPromptActive) return;
    // The biometric sheet pushes the app to `inactive`; dropping suppression
    // now would flash the shield for the frames before `onResume`/`onShow`
    // arrives. Defer the release to the next foreground transition so
    // suppression and lifecycle-safe flip together. Other unsafe states
    // (pause/hide/window blur/native exposure) are not suppressed.
    if (_lifecycleInactive) {
      _deferAuthClear = true;
    } else {
      super.endAuthPrompt();
      _syncSafety();
    }
  }

  @override
  void beginScreenshotSuppression() {
    final wasActive = _screenshotSuppressionActive;
    _screenshotSuppressionActive = true;
    // Backstop: if the app never goes inactive (the user ignores the preview),
    // release after a short window so a genuine later backgrounding still
    // blurs. It only clears while already foreground; if the editor is still
    // up (inactive), the foreground transition clears it instead, so the
    // shield never flashes during the editor dismiss animation.
    _screenshotSuppressionTimer?.cancel();
    _screenshotSuppressionTimer = Timer(const Duration(seconds: 8), () {
      if (!_lifecycleInactive) endScreenshotSuppression();
    });
    if (!wasActive) _syncSafety();
  }

  @override
  void endScreenshotSuppression() {
    _screenshotSuppressionTimer?.cancel();
    _screenshotSuppressionTimer = null;
    if (!_screenshotSuppressionActive) return;
    _screenshotSuppressionActive = false;
    _syncSafety();
  }

  @override
  void onWindowFocus() => _setWindowSafe(true);

  @override
  void onWindowRestore() => _setWindowSafe(true);

  @override
  void onWindowBlur() => _setWindowSafe(false);

  @override
  void onWindowMinimize() => _setWindowSafe(false);

  @visibleForTesting
  void setLifecycleForegroundForTesting() => _setLifecycleForeground();

  @visibleForTesting
  void setLifecycleInactiveForTesting() => _setLifecycleInactive();

  @visibleForTesting
  void setLifecycleHiddenForTesting() => _setLifecycleHidden();

  void _setLifecycleForeground() {
    _lifecycleInactive = false;
    _lifecycleSafe = true;
    if (_deferAuthClear) {
      // The prompt that suppressed the shield handed foreground back. Clearing
      // here keeps suppression and lifecycle-safe in lockstep, so there is no
      // frame where content is visible, unsuppressed, and unsafe.
      _deferAuthClear = false;
      _authPromptActive = false;
    }
    if (_screenshotSuppressionActive) {
      // The iOS screenshot preview/editor handed foreground back; drop the
      // suppression so a genuine later backgrounding blurs normally.
      _screenshotSuppressionTimer?.cancel();
      _screenshotSuppressionTimer = null;
      _screenshotSuppressionActive = false;
    }
    _syncSafety();
  }

  void _setLifecycleInactive() {
    _lifecycleInactive = true;
    _lifecycleSafe = false;
    _syncSafety();
  }

  void _setLifecycleHidden() {
    _lifecycleInactive = false;
    _lifecycleSafe = false;
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
    final suppressedInactive =
        _lifecycleInactive &&
        (_authPromptActive || _screenshotSuppressionActive);
    final lifecycleSafe = _lifecycleSafe || suppressedInactive;
    _setSafe(lifecycleSafe && _windowSafe && _macOSNativeSafe);
  }

  @override
  void dispose() {
    _disposed = true;
    _screenshotSuppressionTimer?.cancel();
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
    this.borderRadius = BorderRadius.zero,
    super.key,
  });

  static const shieldKey = ValueKey('sensitive_privacy_overlay.shield');

  final bool sensitiveContentVisible;
  final Widget child;
  final SensitivePrivacyOverlayController? controller;
  final BorderRadiusGeometry borderRadius;

  @override
  State<SensitivePrivacyOverlay> createState() =>
      _SensitivePrivacyOverlayState();
}

class _SensitivePrivacyOverlayState extends State<SensitivePrivacyOverlay> {
  late final int _nativeVisibilityToken =
      NativeSensitiveContentBridge.createToken();
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
    NativeSensitiveContentBridge.clearToken(_nativeVisibilityToken);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _syncNativeVisibility() {
    NativeSensitiveContentBridge.updateToken(
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
              Positioned.fill(
                child: _SensitivePrivacyShield(
                  key: SensitivePrivacyOverlay.shieldKey,
                  borderRadius: widget.borderRadius,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SensitivePrivacyShield extends StatelessWidget {
  const _SensitivePrivacyShield({required this.borderRadius, super.key});

  final BorderRadiusGeometry borderRadius;

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
      child: ClipRRect(
        borderRadius: borderRadius,
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
