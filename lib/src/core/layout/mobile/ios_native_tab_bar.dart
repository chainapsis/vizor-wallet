import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  });

  final List<IosNativeTabBarItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// Keep the native view mounted while a popup or access gate covers the app.
  final bool hidden;
}

typedef IosNativeTabBarIconLoader =
    Future<Uint8List> Function(
      AssetBundle bundle,
      String iconName,
      double pixelRatio,
    );

/// Chooses the original bar until the native capability and icons are ready.
/// The builder keeps the shell and its router mounted when this choice changes.
class IosNativeTabBarHost extends StatefulWidget {
  const IosNativeTabBarHost({
    required this.configuration,
    required this.builder,
    this.enabled = true,
    this.iconLoader = _loadNativeIcon,
    super.key,
  });

  final IosNativeTabBarConfiguration configuration;
  final Widget Function(BuildContext context, Widget? nativeBar) builder;
  final bool enabled;
  final IosNativeTabBarIconLoader iconLoader;

  static const channel = MethodChannel('com.zcash.wallet/native_tab_bar');

  @override
  State<IosNativeTabBarHost> createState() => _IosNativeTabBarHostState();
}

class _IosNativeTabBarHostState extends State<IosNativeTabBarHost> {
  Future<bool>? _capability;
  ({AssetBundle bundle, double scale, String icons})? _request;
  List<_PreparedItem>? _items;
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
    if (oldWidget.iconLoader != widget.iconLoader) _request = null;
    _prepare();
  }

  Future<bool> _readCapability() async {
    try {
      final value = await IosNativeTabBarHost.channel
          .invokeMapMethod<String, dynamic>('getCapabilities');
      return value?['supported'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void _prepare() {
    if (!_eligible) {
      _generation++;
      _request = null;
      _items = null;
      return;
    }
    final request = (
      bundle: DefaultAssetBundle.of(context),
      scale: MediaQuery.devicePixelRatioOf(context),
      icons: widget.configuration.items
          .map((item) => item.iconName)
          .join('\u0000'),
    );
    if (_request == request) return;
    _request = request;
    final generation = ++_generation;
    final destinations = List.of(widget.configuration.items);
    final loader = widget.iconLoader;
    unawaited(() async {
      if (!await (_capability ??= _readCapability())) return;
      try {
        final icons = await Future.wait([
          for (final item in destinations)
            loader(request.bundle, item.iconName, request.scale),
        ]);
        if (!mounted || generation != _generation) return;
        setState(() {
          _items = [
            for (var i = 0; i < destinations.length; i++)
              _PreparedItem(destinations[i], icons[i], request.scale),
          ];
        });
      } catch (error, stack) {
        if (!mounted || generation != _generation) return;
        // The original Flutter bar remains usable if a bundled icon fails.
        setState(() => _items = null);
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'native tab bar',
            context: ErrorDescription('while preparing native tab icons'),
          ),
        );
      }
    }());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _items;
    if (!_eligible || prepared == null || prepared.isEmpty) {
      return widget.builder(context, null);
    }
    // Translated labels/selection do not rerasterize icons. New destinations
    // keep the previous native view alive until their icons have arrived.
    final icons = {for (final item in prepared) item.item.iconName: item};
    final current = widget.configuration.items;
    if (current.isEmpty) return widget.builder(context, null);
    final canUpdate = current.every((item) => icons.containsKey(item.iconName));
    final items = canUpdate
        ? [
            for (final item in current)
              _PreparedItem(
                item,
                icons[item.iconName]!.icon,
                icons[item.iconName]!.scale,
              ),
          ]
        : prepared;
    return widget.builder(
      context,
      IosNativeTabBar._(configuration: widget.configuration, items: items),
    );
  }
}

class _PreparedItem {
  const _PreparedItem(this.item, this.icon, this.scale);
  final IosNativeTabBarItem item;
  final Uint8List icon;
  final double scale;

  Map<String, Object> toMap() => {
    'id': item.id,
    'label': item.label,
    'icon': icon,
    'iconScale': scale,
  };

  bool sameAs(_PreparedItem other) =>
      item.id == other.item.id &&
      item.label == other.item.label &&
      identical(icon, other.icon) &&
      scale == other.scale;
}

/// One persistent UIKit tab bar; all material and interaction styling is native.
class IosNativeTabBar extends StatefulWidget {
  const IosNativeTabBar._({
    required this.configuration,
    required List<_PreparedItem> items,
  }) : _items = items;

  final IosNativeTabBarConfiguration configuration;
  final List<_PreparedItem> _items;

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

  _Snapshot get _currentSnapshot {
    final selected =
        widget._items.any(
          (item) => item.item.id == widget.configuration.selectedId,
        )
        ? widget.configuration.selectedId
        : widget._items.first.item.id;
    return _Snapshot(
      items: widget._items,
      selectedId: selected,
      brightness: Theme.of(context).brightness,
      selectedTintColor: context.colors.navPanel.activeIcon.toARGB32(),
      direction: Directionality.of(context),
      hidden:
          widget.configuration.hidden ||
          MediaQuery.viewInsetsOf(context).bottom > 0 ||
          ModalRoute.isCurrentOf(context) == false ||
          !TickerMode.valuesOf(context).enabled,
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
    if (_snapshot != null && _snapshot!.hidden != snapshot.hidden) {
      // Keep every visibility transition even when an in-flight update causes
      // intermediate snapshots to coalesce. An old visible acknowledgement
      // must not re-enable a newer hide -> show cycle.
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
            !_currentSnapshot.hidden &&
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
    if (epoch is! int ||
        epoch != _visibilityEpoch ||
        revision is! int ||
        revision < 0 ||
        revision <= _presentationRevision ||
        interactive is! bool) {
      return;
    }
    _presentationRevision = revision;
    final ready = interactive && !_currentSnapshot.hidden;
    if (_interactive != ready) setState(() => _interactive = ready);
  }

  void _acceptHeight(Object? value) {
    if (value is! num) return;
    final height = value.toDouble();
    if (!height.isFinite ||
        height <= 0 ||
        (_height != null && (height - _height!).abs() < 0.5)) {
      return;
    }
    setState(() => _height = height);
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
    final ready = _interactive && !_snapshot!.hidden;
    return SizedBox(
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
    required this.visibilityEpoch,
  });
  final List<_PreparedItem> items;
  final String selectedId;
  final Brightness brightness;
  final int selectedTintColor;
  final TextDirection direction;
  final bool hidden;
  final int visibilityEpoch;

  Map<String, Object> toMap() => {
    'items': [for (final item in items) item.toMap()],
    'selectedId': selectedId,
    'brightness': brightness.name,
    'selectedTintColor': selectedTintColor,
    'direction': direction.name,
    'hidden': hidden,
    'visibilityEpoch': visibilityEpoch,
  };

  bool sameAs(_Snapshot other) =>
      selectedId == other.selectedId &&
      brightness == other.brightness &&
      selectedTintColor == other.selectedTintColor &&
      direction == other.direction &&
      hidden == other.hidden &&
      visibilityEpoch == other.visibilityEpoch &&
      items.length == other.items.length &&
      Iterable.generate(
        items.length,
      ).every((i) => items[i].sameAs(other.items[i]));
}

final _iconCache =
    <({AssetBundle bundle, String name, double scale}), Future<Uint8List>>{};

Future<Uint8List> _loadNativeIcon(
  AssetBundle bundle,
  String name,
  double scale,
) async {
  final key = (bundle: bundle, name: name, scale: scale);
  final existing = _iconCache[key];
  if (existing != null) return existing;
  final future = _rasterizeNativeIcon(bundle, name, scale);
  _iconCache[key] = future;
  // There are currently four tab icons. Bound cached copies across bundles
  // and DPR changes without retaining decoded ui.Image/picture resources.
  if (_iconCache.length > 32) _iconCache.remove(_iconCache.keys.first);
  try {
    return await future;
  } catch (_) {
    if (identical(_iconCache[key], future)) _iconCache.remove(key);
    rethrow;
  }
}

Future<Uint8List> _rasterizeNativeIcon(
  AssetBundle bundle,
  String name,
  double scale,
) async {
  final info = await vg.loadPicture(
    SvgAssetLoader('assets/icons/$name.svg', assetBundle: bundle),
    null,
  );
  ui.Image? image;
  ui.Picture? picture;
  try {
    const side = 25.0;
    final pixels = (side * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixels / info.size.width, pixels / info.size.height);
    canvas.drawPicture(info.picture);
    picture = recorder.endRecording();
    image = await picture.toImage(pixels, pixels);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Native icon PNG encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture?.dispose();
    info.picture.dispose();
  }
}
