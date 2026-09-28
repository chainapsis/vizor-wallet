import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../layout/app_form_factor.dart';

/// Disabled outside the production bootstrap (including Widgetbook/tests).
final appPasswordInputSourceProvider = Provider<AppPasswordInputSource>((ref) {
  return AppPasswordInputSource(enabled: false);
});

abstract interface class PasswordInputSourcePlatform {
  Future<Map<String, Object?>?> capture();
  Future<void> restore(
    Map<String, Object?> target,
    Map<String, Object?> expected,
  );
}

class MethodChannelPasswordInputSource implements PasswordInputSourcePlatform {
  MethodChannelPasswordInputSource({this.windows = false});

  final bool windows;
  static const channel = MethodChannel(
    'com.zcash.wallet/password_input_source',
  );

  @override
  Future<Map<String, Object?>?> capture() async {
    final value = await channel.invokeMapMethod<String, Object?>('capture');
    return value;
  }

  @override
  Future<void> restore(
    Map<String, Object?> target,
    Map<String, Object?> expected,
  ) async {
    final arguments = {'target': target, 'expected': expected};
    if (!windows) {
      await channel.invokeMethod<void>('restore', arguments);
      return;
    }
    final applied = await channel.invokeMethod<bool>(
      'restoreWithResult',
      arguments,
    );
    if (applied != true) {
      debugPrint('Windows password input source: restoration not confirmed.');
    }
  }
}

abstract interface class PasswordInputSourceStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class PreferencesPasswordInputSourceStore implements PasswordInputSourceStore {
  static const key = 'app_password_input_source_v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}

/// A submission snapshot, never a password or a native pointer.
class PasswordInputSourceCandidate {
  PasswordInputSourceCandidate._(this.owner, this.generation, this.value);
  final AppPasswordInputSource owner;
  final int generation;
  final Map<String, Object?> value;
}

class AppPasswordInputSource {
  AppPasswordInputSource({
    required this.enabled,
    this.useWindowsFocus = false,
    PasswordInputSourcePlatform? platform,
    PasswordInputSourceStore? store,
  }) : _platform =
           platform ??
           MethodChannelPasswordInputSource(windows: useWindowsFocus),
       _store = store ?? PreferencesPasswordInputSourceStore();

  factory AppPasswordInputSource.production() => AppPasswordInputSource(
    enabled:
        kAppFormFactor == AppFormFactor.desktop &&
        (Platform.isWindows || Platform.isMacOS),
    useWindowsFocus: Platform.isWindows,
  );

  final bool enabled;
  // Windows may not deliver Flutter lifecycle events during initial startup.
  // Keep the established macOS lifecycle and key handling unchanged.
  final bool useWindowsFocus;
  final PasswordInputSourcePlatform _platform;
  final PasswordInputSourceStore _store;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _writes;
  static const _timeout = Duration(milliseconds: 300);

  Future<PasswordInputSourceCandidate?> capture() async {
    if (!enabled || _disposed) return null;
    final generation = _generation;
    try {
      final value = await _platform.capture().timeout(_timeout);
      if (value == null || _disposed || generation != _generation) return null;
      return PasswordInputSourceCandidate._(
        this,
        generation,
        Map.unmodifiable(value),
      );
    } catch (_) {
      return null; // A convenience must never prevent authentication.
    }
  }

  Future<void> remember(PasswordInputSourceCandidate? candidate) {
    if (!enabled || candidate == null || !identical(candidate.owner, this)) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      if (_disposed || candidate.generation != _generation) return;
      await _store.write(jsonEncode({'version': 1, 'source': candidate.value}));
    });
  }

  Future<void> restore({required bool Function() isCurrent}) async {
    if (!enabled || _disposed || !isCurrent()) return;
    final generation = _generation;
    try {
      // Native code compares this again before writing, so a user switch while
      // preferences load is never overwritten by a late restore.
      final expected = await _platform.capture().timeout(_timeout);
      if (expected == null || !isCurrent()) return;
      final raw = await _store.read().timeout(_timeout);
      if (raw == null ||
          _disposed ||
          generation != _generation ||
          !isCurrent()) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['source'] is! Map) {
        return;
      }
      final target = Map<String, Object?>.from(decoded['source'] as Map);
      if (target['platform'] != expected['platform']) return;
      await _platform.restore(target, expected);
    } catch (_) {
      // Missing plugin, stale settings, unavailable source: keep normal input.
    }
  }

  /// Invalidate in-flight captures synchronously, then delete after older writes.
  Future<void> clear() {
    _generation++;
    if (!enabled) return Future<void>.value();
    return _enqueue(_store.clear);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final write = (_writes ?? Future<void>.value())
        .then((_) => action())
        .catchError((Object _) {});
    _writes = write;
    return write;
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}

/// Explicit opt-in around an app-password field, not part of PasswordTextField.
class AppPasswordInput extends ConsumerStatefulWidget {
  const AppPasswordInput({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<AppPasswordInput> createState() => _AppPasswordInputState();
}

class _AppPasswordInputState extends ConsumerState<AppPasswordInput>
    with WidgetsBindingObserver, WindowListener {
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  int _revision = 0;
  bool _active = false;
  bool _awaitingActivation = false;
  late final bool _useWindowsFocus;
  int _windowRevision = 0;
  int _viewRevision = 0;
  TextEditingController? _suspendedEditor;
  TextEditingController? _editingController;
  TextEditingValue? _lastEditingValue;

  void _onEditingChanged() {
    final value = _editingController?.value;
    final previous = _lastEditingValue;
    _lastEditingValue = value;
    // Autofocus initializes selection without user input. Only text or IME
    // composition changes invalidate restoration; key events are guarded too.
    if (value?.text != previous?.text ||
        value?.composing != previous?.composing) {
      _cancelRestore();
    }
  }

  void _cancelRestore() {
    _revision++;
    _awaitingActivation = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _useWindowsFocus = ref.read(appPasswordInputSourceProvider).useWindowsFocus;
    if (_useWindowsFocus) {
      windowManager.addListener(this);
      unawaited(_readInitialWindowFocus());
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == AppLifecycleState.resumed;
  }

  Future<void> _readInitialWindowFocus() async {
    final revision = _windowRevision;
    try {
      final focused = await windowManager.isFocused();
      if (mounted && revision == _windowRevision) _setWindowFocus(focused);
    } catch (_) {
      // A later native focus event can still fulfill initial autofocus.
    }
  }

  void _setWindowFocus(bool focused) {
    _windowRevision++;
    if (_active == focused) return;
    _active = focused;
    _revision++;
    if (_active && _awaitingActivation && _focus.hasFocus) _onFocus(true);
  }

  @override
  void onWindowFocus() => _setWindowFocus(true);

  @override
  void onWindowBlur() => _setWindowFocus(false);

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (!_useWindowsFocus || event.viewId != View.of(context).viewId) return;
    final revision = ++_viewRevision;
    if (event.state == ViewFocusState.unfocused) {
      // Flutter parks focus at the root when the native view loses focus.
      // Returning to that same editor is not a new password-field entry.
      if (!_awaitingActivation && _editingController != null) {
        _suspendedEditor = _editingController;
      }
      _revision++;
    } else {
      // The enclosing View has already queued its focus restoration. Keep the
      // marker through that focus notification, then discard it even if a
      // different editor receives focus so later deliberate entry still works.
      scheduleMicrotask(() {
        if (mounted && revision == _viewRevision) _suspendedEditor = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_useWindowsFocus) return;
    _active = state == AppLifecycleState.resumed;
    _revision++;
    // Startup autofocus can precede the runner showing its first frame. Only
    // fulfill that deferred focus; ordinary app reactivation must not re-force.
    if (_active && _awaitingActivation && _focus.hasFocus) _onFocus(true);
  }

  void _onFocus(bool focused) {
    _editingController?.removeListener(_onEditingChanged);
    _editingController = null;
    _lastEditingValue = null;
    final revision = ++_revision;
    _awaitingActivation = false;
    if (!focused) return;
    // Focus attachment contexts differ between Flutter editor versions.
    void findEditor(Element element) {
      final child = element.widget;
      if (child is EditableText && child.focusNode.hasFocus) {
        _editingController = child.controller;
        return;
      }
      element.visitChildElements(findEditor);
    }

    context.visitChildElements(findEditor);
    _lastEditingValue = _editingController?.value;
    _editingController?.addListener(_onEditingChanged);
    if (_useWindowsFocus &&
        _suspendedEditor != null &&
        identical(_editingController, _suspendedEditor)) {
      _suspendedEditor = null;
      return;
    }
    if (!_active) {
      _awaitingActivation = true;
      return;
    }
    unawaited(_restoreForFocus(revision));
  }

  Future<void> _restoreForFocus(int revision) async {
    if (_useWindowsFocus) {
      // Let EditableText attach its native text-input client before capturing
      // IMM state. Password-client setup itself can close the Windows IME.
      await WidgetsBinding.instance.endOfFrame;
    }
    bool isCurrent() =>
        mounted && _active && _focus.hasFocus && revision == _revision;
    if (!isCurrent()) return;
    await ref
        .read(appPasswordInputSourceProvider)
        .restore(isCurrent: isCurrent);
  }

  @override
  void dispose() {
    _revision++;
    if (_useWindowsFocus) {
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _editingController?.removeListener(_onEditingChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onFocusChange: _onFocus,
    onKeyEvent: (_, event) {
      // Traversal moves focus on key-down; the new field receives the release.
      if (_useWindowsFocus &&
          event is KeyUpEvent &&
          (event.logicalKey == LogicalKeyboardKey.tab ||
              event.logicalKey == LogicalKeyboardKey.shiftLeft ||
              event.logicalKey == LogicalKeyboardKey.shiftRight)) {
        return KeyEventResult.ignored;
      }
      _cancelRestore();
      return KeyEventResult.ignored;
    },
    child: widget.child,
  );
}
