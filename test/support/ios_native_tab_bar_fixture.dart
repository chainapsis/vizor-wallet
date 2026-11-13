import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/ios_native_tab_bar.dart';

class NativeTabBarFixture {
  NativeTabBarFixture() {
    messenger.setMockMethodCallHandler(IosNativeTabBarHost.channel, (
      call,
    ) async {
      capabilityReads++;
      return capabilityResponse ?? {'supported': supported};
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'acceptGesture' || call.method == 'rejectGesture') {
        gestureCalls.add(call.method);
      }
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final id = args['id'] as int;
        final bytes = args['params'] as Uint8List;
        created[id] =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(bytes),
                )
                as Map;
        latest = created[id]!;
        presentations[id] = {
          'visibilityEpoch': latest['visibilityEpoch'],
          'revision': 0,
          'interactive': _readyFor(latest),
          'phase': latest['hidden'] == true
              ? automaticallySettleHidden
                    ? 'hidden'
                    : 'exiting'
              : 'preparing',
          'settledHidden':
              latest['hidden'] == true && automaticallySettleHidden,
        };
        final channel = MethodChannel('com.zcash.wallet/native_tab_bar/$id');
        channels[id] = channel;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'update') {
            latest = call.arguments as Map;
            updates.add(Map.of(latest));
            final previous = presentations[id]!;
            final ready = _readyFor(latest, previous: previous);
            if (previous['visibilityEpoch'] != latest['visibilityEpoch'] ||
                previous['interactive'] != ready) {
              presentations[id] = {
                'visibilityEpoch': latest['visibilityEpoch'],
                'revision': (previous['revision'] as int) + 1,
                'interactive': ready,
                'phase': ready
                    ? 'visible'
                    : latest['hidden'] == true
                    ? automaticallySettleHidden
                          ? 'hidden'
                          : 'exiting'
                    : 'preparing',
                'settledHidden':
                    latest['hidden'] == true && automaticallySettleHidden,
              };
              unawaited(send('presentation', presentations[id]!));
            }
            await updateDelay?.future;
          } else if (call.method == 'getHeight') {
            return heightResponse ?? height;
          } else if (call.method == 'getPresentation') {
            return presentationResponse ?? presentations[id];
          }
          return null;
        });
      }
      return null;
    });
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  bool supported = true;
  Future<Map>? capabilityResponse;
  int capabilityReads = 0;
  double height = 83;
  Future<num>? heightResponse;
  bool automaticallyPresent = true;
  bool automaticallySettleHidden = true;
  Future<Map>? presentationResponse;
  Completer<void>? updateDelay;
  final created = <int, Map>{};
  final presentations = <int, Map>{};
  final updates = <Map>[];
  final gestureCalls = <String>[];
  final channels = <int, MethodChannel>{};
  Map latest = {};

  bool _readyFor(Map snapshot, {Map? previous}) =>
      (automaticallyPresent ||
          (previous?['visibilityEpoch'] == snapshot['visibilityEpoch'] &&
              previous?['interactive'] == true)) &&
      snapshot['hidden'] != true &&
      snapshot['inputEnabled'] == true &&
      snapshot['layoutReady'] == true;

  Future<void> send(String method, Object? arguments) async {
    final channel = channels.values.last;
    if ((method == 'select' || method == 'presentation') && arguments is Map) {
      arguments = {...presentations.values.last, ...arguments};
    }
    final complete = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => complete.complete(),
    );
    await complete.future;
  }

  Future<void> present({
    required bool interactive,
    int? epoch,
    int? revision,
    String? phase,
    bool? settledHidden,
  }) async {
    final id = channels.keys.last;
    final status = {
      'visibilityEpoch': epoch ?? latest['visibilityEpoch'],
      'revision': revision ?? (presentations[id]!['revision'] as int) + 1,
      'interactive': interactive,
      'phase':
          phase ??
          (interactive
              ? 'visible'
              : latest['hidden'] == true
              ? automaticallySettleHidden
                    ? 'hidden'
                    : 'exiting'
              : 'preparing'),
      'settledHidden':
          settledHidden ??
          (latest['hidden'] == true && automaticallySettleHidden),
    };
    presentations[id] = status;
    await send('presentation', status);
  }

  void dispose() {
    messenger.setMockMethodCallHandler(IosNativeTabBarHost.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels.values) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
