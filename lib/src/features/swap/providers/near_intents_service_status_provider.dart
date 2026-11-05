import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/near_intents_service_status.dart';
import '../integrations/near_intents/near_intents_service_status_client.dart';

final nearIntentsServiceStatusSourceProvider =
    Provider.autoDispose<NearIntentsServiceStatusSource>((ref) {
      final client = NearIntentsServiceStatusClient();
      ref.onDispose(client.close);
      return client;
    });

final nearIntentsServiceElapsedProvider = Provider<Duration Function()>((ref) {
  final clock = Stopwatch()..start();
  ref.onDispose(clock.stop);
  return () => clock.elapsed;
});

final nearIntentsServiceStatusProvider =
    NotifierProvider.autoDispose<
      NearIntentsServiceStatusNotifier,
      NearIntentsServiceStatus
    >(NearIntentsServiceStatusNotifier.new);

class NearIntentsServiceStatusNotifier
    extends Notifier<NearIntentsServiceStatus> {
  Timer? _poll;
  Timer? _boundary;
  Completer<void>? _cancel;
  var _generation = 0;
  var _disposed = false;
  var _foreground = true;
  var _loading = false;
  late Duration Function() _elapsed;
  late NearIntentsServiceStatusSource _source;

  @override
  NearIntentsServiceStatus build() {
    _disposed = false;
    _stop();
    _elapsed = ref.watch(nearIntentsServiceElapsedProvider);
    _source = ref.watch(nearIntentsServiceStatusSourceProvider);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final lifecycle = AppLifecycleListener(
      onStateChange: (value) {
        _foreground = value == AppLifecycleState.resumed;
        if (_foreground) {
          _startPolling();
          unawaited(refresh());
        } else {
          _stop();
          state = NearIntentsServiceStatus(elapsed: _elapsed());
        }
      },
    );
    ref.onDispose(() {
      _disposed = true;
      _stop();
      lifecycle.dispose();
    });
    if (_foreground) {
      _startPolling();
      unawaited(Future<void>.microtask(refresh));
    }
    return NearIntentsServiceStatus(elapsed: _elapsed());
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  void _stop() {
    _generation++;
    _loading = false;
    _poll?.cancel();
    _boundary?.cancel();
    if (_cancel?.isCompleted == false) _cancel!.complete();
    _cancel = null;
  }

  Future<void> refresh() async {
    if (_disposed || !_foreground || _loading) return;
    _loading = true;
    final generation = ++_generation;
    final cancel = _cancel = Completer<void>();
    final source = _source;
    Future<void> load(bool maintenance) async {
      NearIntentsServiceObservation? observation;
      try {
        final feed = await (maintenance
            ? source.loadMaintenance(cancelSignal: cancel.future)
            : source.loadIncidents(cancelSignal: cancel.future));
        observation = NearIntentsServiceObservation(
          feed: feed,
          receivedAt: _elapsed(),
        );
      } catch (_) {
        // Fail silently and discard this feed's previous alerts, not the other
        // independent feed's successfully validated records.
        observation = null;
      }
      if (_disposed || generation != _generation) return;
      _publish(
        NearIntentsServiceStatus(
          elapsed: _elapsed(),
          incidentFeed: maintenance ? state.incidentFeed : observation,
          maintenanceFeed: maintenance ? observation : state.maintenanceFeed,
        ),
      );
    }

    await Future.wait([load(false), load(true)]);
    if (!_disposed && generation == _generation) _loading = false;
  }

  void _publish(NearIntentsServiceStatus next) {
    _boundary?.cancel();
    state = next;
    final delay = next.nextUpdateIn;
    if (delay == null) return;
    _boundary = Timer(delay, () {
      if (_disposed || !_foreground) return;
      _publish(
        NearIntentsServiceStatus(
          elapsed: _elapsed(),
          incidentFeed: state.incidentFeed,
          maintenanceFeed: state.maintenanceFeed,
        ),
      );
    });
  }
}
