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

final nearIntentsServiceStatusClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

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
  late DateTime Function() _now;
  late NearIntentsServiceStatusSource _source;

  @override
  NearIntentsServiceStatus build() {
    _disposed = false;
    _stop();
    _now = ref.watch(nearIntentsServiceStatusClockProvider);
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
          state = NearIntentsServiceStatus(now: _now());
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
    return NearIntentsServiceStatus(now: _now());
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
      List<NearIntentsServiceIssue> issues;
      DateTime? fetchedAt;
      try {
        issues = await (maintenance
            ? source.loadMaintenance(cancelSignal: cancel.future)
            : source.loadIncidents(cancelSignal: cancel.future));
        fetchedAt = _now();
      } catch (_) {
        // Fail silently and discard this feed's previous alerts, not the other
        // independent feed's successfully validated records.
        issues = const [];
      }
      if (_disposed || generation != _generation) return;
      _publish(
        NearIntentsServiceStatus(
          now: _now(),
          incidents: maintenance ? state.incidents : issues,
          maintenance: maintenance ? issues : state.maintenance,
          incidentsFetchedAt: maintenance
              ? state.incidentsFetchedAt
              : fetchedAt,
          maintenanceFetchedAt: maintenance
              ? fetchedAt
              : state.maintenanceFetchedAt,
        ),
      );
    }

    await Future.wait([load(false), load(true)]);
    if (!_disposed && generation == _generation) _loading = false;
  }

  void _publish(NearIntentsServiceStatus next) {
    _boundary?.cancel();
    state = next;
    final boundaries = <DateTime>[
      if (next.incidentsFetchedAt != null)
        next.incidentsFetchedAt!.add(nearIntentsStatusFreshness),
      if (next.maintenanceFetchedAt != null)
        next.maintenanceFetchedAt!.add(nearIntentsStatusFreshness),
      for (final issue in next.maintenance) ...[
        issue.startsAt!.subtract(nearIntentsMaintenanceLeadTime),
        issue.startsAt!,
        issue.finishesAt!,
      ],
    ].where((time) => time.isAfter(next.now)).toList()..sort();
    if (boundaries.isEmpty) return;
    _boundary = Timer(boundaries.first.difference(next.now), () {
      if (_disposed || !_foreground) return;
      _publish(
        NearIntentsServiceStatus(
          now: _now(),
          incidents: state.incidents,
          maintenance: state.maintenance,
          incidentsFetchedAt: state.incidentsFetchedAt,
          maintenanceFetchedAt: state.maintenanceFetchedAt,
        ),
      );
    });
  }
}
