import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ) => channel.invokeMethod<void>('restore', {
    'target': target,
    'expected': expected,
  });
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
    PasswordInputSourcePlatform? platform,
    PasswordInputSourceStore? store,
  }) : _platform = platform ?? MethodChannelPasswordInputSource(),
       _store = store ?? PreferencesPasswordInputSourceStore();

  factory AppPasswordInputSource.production() => AppPasswordInputSource(
    enabled:
        kAppFormFactor == AppFormFactor.desktop &&
        (Platform.isWindows || Platform.isMacOS),
  );

  final bool enabled;
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
    with WidgetsBindingObserver {
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  int _revision = 0;
  bool _active = false;
  bool _awaitingActivation = false;
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
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    if (!_active) {
      _awaitingActivation = true;
      return;
    }
    unawaited(
      ref
          .read(appPasswordInputSourceProvider)
          .restore(
            isCurrent: () =>
                mounted && _active && _focus.hasFocus && revision == _revision,
          ),
    );
  }

  @override
  void dispose() {
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    _editingController?.removeListener(_onEditingChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onFocusChange: _onFocus,
    onKeyEvent: (_, _) {
      _cancelRestore();
      return KeyEventResult.ignored;
    },
    child: widget.child,
  );
}
