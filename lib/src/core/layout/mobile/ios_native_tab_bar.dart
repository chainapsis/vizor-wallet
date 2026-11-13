import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_form_factor.dart';
import '../../theme/app_theme.dart';

/// A destination's identity is independent of its position or translated title.
class IosNativeTabBarItem {
  const IosNativeTabBarItem({
    required this.id,
    required this.iconName,
    required this.label,
  });

  final String id;
  final String iconName;
  final String label;
}

class IosNativeTabBarConfiguration {
  const IosNativeTabBarConfiguration({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    this.hidden = false,
    this.inputEnabled = true,
    this.hideImmediately = false,
    this.readSelectedId,
  });

  final List<IosNativeTabBarItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// Physically slide the bar away for a privacy gate or keyboard.
  final bool hidden;

  /// Route coverage and popups block input without moving the underlying bar.
  final bool inputEnabled;

  /// Security coverage removes the native surface without an exit animation.
  final bool hideImmediately;

  /// Live authority for app-level hosts whose visual publication is deferred.
  final String Function()? readSelectedId;
}

/// Keeps the native slot transparent until the native catalog is checked.
/// Unsupported hosts or missing catalog images use the original Flutter bar.
/// No Flutter asset decoding occurs while preparing this native lane.
class IosNativeTabBarHost extends StatefulWidget {
  const IosNativeTabBarHost({
    required this.configuration,
    required this.builder,
    this.enabled = true,
    this.onHeightChanged,
    super.key,
  });

  final IosNativeTabBarConfiguration configuration;
  final Widget Function(BuildContext context, Widget? nativeBar) builder;
  final bool enabled;
  final ValueChanged<double>? onHeightChanged;

  static const channel = MethodChannel('com.zcash.wallet/native_tab_bar');

  @override
  State<IosNativeTabBarHost> createState() => _IosNativeTabBarHostState();
}

class _NativeTabBarCapabilities {
  const _NativeTabBarCapabilities({
    required this.supported,
    this.iconNames = const {},
  });
  final bool supported;
  final Set<String> iconNames;
}

class _IosNativeTabBarHostState extends State<IosNativeTabBarHost> {
  Future<_NativeTabBarCapabilities>? _request;
  _NativeTabBarCapabilities? _capabilities;
  bool _reading = false;
  int _generation = 0;

  bool get _eligible =>
      widget.enabled &&
      kAppFormFactor == AppFormFactor.mobile &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant IosNativeTabBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  Future<_NativeTabBarCapabilities> _readCapabilities() async {
    try {
      final value = await IosNativeTabBarHost.channel
          .invokeMapMethod<String, dynamic>('getCapabilities');
      final names = value?['iconNames'];
      return _NativeTabBarCapabilities(
        supported: value?['supported'] == true,
        iconNames: names is List
            ? Set.unmodifiable(names.whereType<String>())
            : const {},
      );
    } on MissingPluginException {
      return const _NativeTabBarCapabilities(supported: false);
    } on PlatformException {
      return const _NativeTabBarCapabilities(supported: false);
    }
  }

  void _prepare() {
    if (!_eligible) {
      _generation++;
      _reading = false;
      return;
    }
    if (_capabilities != null || _reading) return;
    _reading = true;
    final generation = ++_generation;
    unawaited(() async {
      final capabilities = await (_request ??= _readCapabilities());
      if (!mounted || !_eligible || generation != _generation) return;
      setState(() {
        _capabilities = capabilities;
        _reading = false;
      });
    }());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    final items = widget.configuration.items;
    if (!_eligible ||
        items.isEmpty ||
        (capabilities != null &&
            (!capabilities.supported ||
                items.any(
                  (item) => !capabilities.iconNames.contains(item.iconName),
                )))) {
      return widget.builder(context, null);
    }
    if (capabilities == null) {
      return widget.builder(
        context,
        SizedBox(
          key: const ValueKey('ios_native_tab_bar_pending'),
          height: 49 + MediaQuery.viewPaddingOf(context).bottom,
        ),
      );
    }
    return widget.builder(
      context,
      IosNativeTabBar._(
        configuration: widget.configuration,
        items: List.unmodifiable(items),
        onHeightChanged: widget.onHeightChanged,
      ),
    );
  }
}

/// One persistent UIKit tab bar; all material and interaction styling is native.
class IosNativeTabBar extends StatefulWidget {
  const IosNativeTabBar._({
    required this.configuration,
    required List<IosNativeTabBarItem> items,
    this.onHeightChanged,
  }) : _items = items;

  final IosNativeTabBarConfiguration configuration;
  final List<IosNativeTabBarItem> _items;
  final ValueChanged<double>? onHeightChanged;

  @override
  State<IosNativeTabBar> createState() => _IosNativeTabBarState();
}

class _IosNativeTabBarState extends State<IosNativeTabBar> {
  MethodChannel? _channel;
  _Snapshot? _snapshot;
  double? _height;
  int _revision = 0;
  int _sentRevision = -1;
  int _visibilityEpoch = 0;
  int _presentationRevision = -1;
  bool _interactive = false;
  bool _sending = false;
  bool _layoutReady = false;
  BoxConstraints? _slotConstraints;
  final _slotKey = GlobalKey();
  int _layoutGeneration = 0;
  bool _layoutAcknowledgementScheduled = false;
  int _showRequestId = 0;
  int? _settledHiddenEpoch;

  _Snapshot get _currentSnapshot {
    final hidden =
        widget.configuration.hidden ||
        MediaQuery.viewInsetsOf(context).bottom > 0;
    final selectedId =
        widget.configuration.readSelectedId?.call() ??
        widget.configuration.selectedId;
    final selected = widget._items.any((item) => item.id == selectedId)
        ? selectedId
        : widget._items.first.id;
    return _Snapshot(
      items: widget._items,
      selectedId: selected,
      brightness: Theme.of(context).brightness,
      selectedTintColor: context.colors.navPanel.activeIcon.toARGB32(),
      direction: Directionality.of(context),
      hidden: hidden,
      hideImmediately: hidden && widget.configuration.hideImmediately,
      showRequestId: _showRequestId,
      inputEnabled:
          !hidden &&
          widget.configuration.inputEnabled &&
          ModalRoute.isCurrentOf(context) != false &&
          TickerMode.valuesOf(context).enabled,
      layoutReady: _layoutReady,
      visibilityEpoch: _visibilityEpoch,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSnapshot();
  }

  @override
  void didUpdateWidget(covariant IosNativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSnapshot();
  }

  void _updateSnapshot({bool force = false}) {
    var snapshot = _currentSnapshot;
    if (_snapshot?.hidden == true && !snapshot.hidden) {
      _showRequestId++;
      snapshot = _currentSnapshot;
    }
    if (_snapshot != null &&
        (_snapshot!.hidden != snapshot.hidden ||
            _snapshot!.inputEnabled != snapshot.inputEnabled ||
            _snapshot!.layoutReady != snapshot.layoutReady ||
            _snapshot!.hideImmediately != snapshot.hideImmediately)) {
      // Keep every readiness transition even when an in-flight update causes
      // intermediate snapshots to coalesce. The final ready snapshot must
      // receive a new native acknowledgement after hide/show, cover/uncover
      // or layout invalidation, even if its booleans match the previous one.
      _visibilityEpoch++;
      _interactive = false;
      snapshot = _currentSnapshot;
    }
    if (!force && _snapshot?.sameAs(snapshot) == true) return;
    _snapshot = snapshot;
    _revision++;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    final channel = _channel;
    if (_sending || channel == null) return;
    _sending = true;
    try {
      while (mounted &&
          identical(channel, _channel) &&
          _sentRevision != _revision) {
        final revision = _revision;
        await channel.invokeMethod<void>('update', _snapshot!.toMap());
        if (mounted && identical(channel, _channel)) _sentRevision = revision;
      }
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    } on MissingPluginException {
      // Disposal can race the final native channel call.
    } finally {
      _sending = false;
      if (mounted && _channel != null && !identical(channel, _channel)) {
        unawaited(_flush());
      }
    }
  }

  void _created(int id) {
    final channel = MethodChannel('com.zcash.wallet/native_tab_bar/$id');
    _channel?.setMethodCallHandler(null);
    _channel = channel;
    _sentRevision = -1;
    _presentationRevision = -1;
    _settledHiddenEpoch = null;
    _layoutReady = false;
    _layoutGeneration++;
    _updateSnapshot();
    if (_interactive) setState(() => _interactive = false);
    channel.setMethodCallHandler((call) async {
      if (!mounted || !identical(_channel, channel)) return;
      if (call.method == 'select') {
        final arguments = call.arguments;
        final values = arguments is Map ? arguments : const {};
        final id = values['id'];
        if (id is String &&
            _interactive &&
            values['visibilityEpoch'] is int &&
            values['revision'] is int &&
            values['visibilityEpoch'] == _visibilityEpoch &&
            values['revision'] == _presentationRevision &&
            _currentSnapshot.inputEnabled &&
            _layoutReady &&
            widget.configuration.items.any((item) => item.id == id)) {
          widget.configuration.onSelect(id);
        }
        // If navigation was rejected, restore its authoritative selection.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_channel, channel)) {
            _updateSnapshot(force: true);
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      } else if (call.method == 'layout') {
        _acceptHeight((call.arguments as Map?)?['height']);
      } else if (call.method == 'presentation') {
        _acceptPresentation(call.arguments);
      }
    });
    unawaited(_flush());
    unawaited(() async {
      try {
        // UIKit can finish the initial entrance before this handler attaches.
        // Reconcile with the current state, without trusting an older reply
        // over a presentation callback received while this query was pending.
        final presentation = await channel.invokeMapMethod<String, dynamic>(
          'getPresentation',
        );
        if (mounted && identical(_channel, channel)) {
          _acceptPresentation(presentation);
        }
      } on PlatformException {
        // Keep input blocked until a later native acknowledgement arrives.
      } on MissingPluginException {
        // The view may already have been removed by navigation.
      }
    }());
    unawaited(() async {
      try {
        final height = await channel.invokeMethod<num>('getHeight');
        if (mounted && identical(_channel, channel)) _acceptHeight(height);
      } on PlatformException {
        // A later layout callback still supplies the native size.
      } on MissingPluginException {
        // The view may already have been removed by navigation.
      }
    }());
  }

  void _acceptPresentation(Object? arguments) {
    if (arguments is! Map) return;
    final epoch = arguments['visibilityEpoch'];
    final revision = arguments['revision'];
    final interactive = arguments['interactive'];
    final settledHidden = arguments['settledHidden'];
    final phase = arguments['phase'];
    if (epoch is! int ||
        epoch != _visibilityEpoch ||
        revision is! int ||
        revision < 0 ||
        revision <= _presentationRevision ||
        interactive is! bool ||
        settledHidden is! bool ||
        phase is! String) {
      return;
    }
    _presentationRevision = revision;
    final ready = interactive && _currentSnapshot.inputEnabled && _layoutReady;
    final hiddenEpoch = settledHidden && phase == 'hidden' ? epoch : null;
    if (_interactive != ready || _settledHiddenEpoch != hiddenEpoch) {
      setState(() {
        _interactive = ready;
        _settledHiddenEpoch = hiddenEpoch;
      });
    }
  }

  void _acceptHeight(Object? value) {
    if (value is! num) return;
    final height = value.toDouble();
    if (!height.isFinite || height <= 0) return;
    if (_height == null || (height - _height!).abs() >= 0.5) {
      setState(() {
        _height = height;
        _layoutReady = false;
        _interactive = false;
        _layoutGeneration++;
      });
      _updateSnapshot();
      widget.onHeightChanged?.call(height);
    }
    _acknowledgeSlotLayout();
  }

  void _acknowledgeSlotLayout() {
    if (_layoutAcknowledgementScheduled || _height == null || _layoutReady) {
      return;
    }
    _layoutAcknowledgementScheduled = true;
    final generation = _layoutGeneration;
    final channel = _channel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutAcknowledgementScheduled = false;
      if (!mounted || !identical(channel, _channel)) return;
      if (generation != _layoutGeneration) {
        _acknowledgeSlotLayout();
        return;
      }
      final slot = _slotKey.currentContext?.findRenderObject();
      if (slot is! RenderBox ||
          !slot.hasSize ||
          slot.size.width <= 0 ||
          (slot.size.height - _height!).abs() >= 0.5) {
        return;
      }
      setState(() => _layoutReady = true);
      _updateSnapshot();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _interactive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only a bootstrap estimate. UIKit reports its actual fitting height,
    // including the safe area, after attachment and on subsequent changes.
    final height = _height ?? 49 + MediaQuery.viewPaddingOf(context).bottom;
    final offstage =
        _snapshot!.hideImmediately ||
        (_snapshot!.hidden && _settledHiddenEpoch == _visibilityEpoch);
    return SizedBox(
      height: height,
      child: Offstage(
        offstage: offstage,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_slotConstraints != constraints) {
              _slotConstraints = constraints;
              _layoutGeneration++;
              _layoutReady = false;
              _interactive = false;
              _updateSnapshot();
              _acknowledgeSlotLayout();
            }
            final ready =
                _interactive && _snapshot!.inputEnabled && _layoutReady;
            return SizedBox(
              key: _slotKey,
              height: height,
              child: IgnorePointer(
                ignoring: !ready,
                child: ExcludeSemantics(
                  excluding: !ready,
                  child: UiKitView(
                    viewType: 'com.zcash.wallet/native_tab_bar',
                    layoutDirection: Directionality.of(context),
                    creationParams: _snapshot!.toMap(),
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: _created,
                    // The app's global tap-to-unfocus recognizer must not hold UIKit's
                    // press interaction until a drag cancels that ancestor's tap.
                    gestureRecognizers: ready
                        ? <Factory<OneSequenceGestureRecognizer>>{
                            Factory<OneSequenceGestureRecognizer>(
                              EagerGestureRecognizer.new,
                            ),
                          }
                        : const <Factory<OneSequenceGestureRecognizer>>{},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Snapshot {
  const _Snapshot({
    required this.items,
    required this.selectedId,
    required this.brightness,
    required this.selectedTintColor,
    required this.direction,
    required this.hidden,
    required this.hideImmediately,
    required this.showRequestId,
    required this.inputEnabled,
    required this.layoutReady,
    required this.visibilityEpoch,
  });
  final List<IosNativeTabBarItem> items;
  final String selectedId;
  final Brightness brightness;
  final int selectedTintColor;
  final TextDirection direction;
  final bool hidden;
  final bool hideImmediately;
  final int showRequestId;
  final bool inputEnabled;
  final bool layoutReady;
  final int visibilityEpoch;

  Map<String, Object> toMap() => {
    'items': [
      for (final item in items)
        {'id': item.id, 'label': item.label, 'iconName': item.iconName},
    ],
    'selectedId': selectedId,
    'brightness': brightness.name,
    'selectedTintColor': selectedTintColor,
    'direction': direction.name,
    'hidden': hidden,
    'hideImmediately': hideImmediately,
    'showRequestId': showRequestId,
    'inputEnabled': inputEnabled,
    'layoutReady': layoutReady,
    'visibilityEpoch': visibilityEpoch,
  };

  bool sameAs(_Snapshot other) =>
      selectedId == other.selectedId &&
      brightness == other.brightness &&
      selectedTintColor == other.selectedTintColor &&
      direction == other.direction &&
      hidden == other.hidden &&
      hideImmediately == other.hideImmediately &&
      showRequestId == other.showRequestId &&
      inputEnabled == other.inputEnabled &&
      layoutReady == other.layoutReady &&
      visibilityEpoch == other.visibilityEpoch &&
      items.length == other.items.length &&
      Iterable.generate(items.length).every(
        (i) =>
            (items[i].id == other.items[i].id &&
            items[i].label == other.items[i].label &&
            items[i].iconName == other.items[i].iconName),
      );
}
