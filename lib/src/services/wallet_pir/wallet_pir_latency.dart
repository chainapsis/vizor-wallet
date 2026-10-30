import 'dart:async';

const kWalletPirPingInterval = Duration(seconds: 10);

enum WalletPirPingStatus { checking, available, unavailable }

class WalletPirPingSample {
  const WalletPirPingSample.checking()
    : status = WalletPirPingStatus.checking,
      latency = null;
  const WalletPirPingSample.available(Duration value)
    : status = WalletPirPingStatus.available,
      latency = value;
  const WalletPirPingSample.unavailable()
    : status = WalletPirPingStatus.unavailable,
      latency = null;

  final WalletPirPingStatus status;
  final Duration? latency;

  String get label => switch (status) {
    WalletPirPingStatus.checking => 'Checking...',
    WalletPirPingStatus.available => '${latency!.inMilliseconds}ms',
    WalletPirPingStatus.unavailable => 'Unavailable',
  };
}

typedef WalletPirServerProbe =
    Future<WalletPirPingSample> Function(
      String baseUrl,
      Future<void> cancelled,
    );

/// Measures one routed HTTPS response, not the health of every private product.
Future<WalletPirPingSample> measureWalletPirPing(
  Future<int> Function() request,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    final status = await request();
    return status == 200
        ? WalletPirPingSample.available(stopwatch.elapsed)
        : const WalletPirPingSample.unavailable();
  } catch (_) {
    return const WalletPirPingSample.unavailable();
  } finally {
    stopwatch.stop();
  }
}

/// Owns pings only while the picker is visible and the app is foregrounded.
/// Cancels obsolete requests, ignores late replies, and never overlaps rounds.
class WalletPirLatencyMonitor {
  WalletPirLatencyMonitor({
    required this.probe,
    required this.onChanged,
    this.interval = kWalletPirPingInterval,
  });

  final WalletPirServerProbe probe;
  final void Function() onChanged;
  final Duration interval;
  final _targets = <String>{};
  final _samples = <String, WalletPirPingSample>{};
  Timer? _timer;
  Completer<void>? _cancel;
  bool _running = false;
  bool _inFlight = false;
  int _generation = 0;

  Map<String, WalletPirPingSample> get samples => Map.unmodifiable(_samples);

  void updateTargets(Iterable<String> urls) {
    final next = urls.toSet();
    if (next.length == _targets.length && next.every(_targets.contains)) return;
    _cancelRound();
    _targets
      ..clear()
      ..addAll(next);
    _samples.removeWhere((url, _) => !next.contains(url));
    if (_running) unawaited(refresh());
  }

  void resume() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void pause() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _cancelRound();
  }

  void dispose() => pause();

  void _cancelRound() {
    _generation++;
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _cancel = null;
    _inFlight = false;
  }

  Future<void> refresh() async {
    if (!_running || _inFlight || _targets.isEmpty) return;
    _inFlight = true;
    final generation = ++_generation;
    final cancel = _cancel = Completer<void>();
    final targets = _targets.toList();
    for (final url in targets) {
      _samples.putIfAbsent(url, () => const WalletPirPingSample.checking());
    }
    onChanged();
    try {
      await Future.wait([
        for (final url in targets) _measure(url, generation, cancel.future),
      ]);
    } finally {
      if (generation == _generation) _inFlight = false;
    }
  }

  Future<void> _measure(String url, int generation, Future<void> cancel) async {
    WalletPirPingSample sample;
    try {
      sample = await probe(url, cancel);
    } catch (_) {
      sample = const WalletPirPingSample.unavailable();
    }
    if (!_running || generation != _generation) return;
    _samples[url] = sample;
    onChanged();
  }
}
