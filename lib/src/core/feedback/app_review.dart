import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/google_play_config.dart';
import '../layout/app_form_factor.dart';

bool isNativeAppReviewEnabled({required bool isIOS, required bool isAndroid}) =>
    kAppFormFactor == AppFormFactor.mobile &&
    (isIOS || (isAndroid && !kVizorDegoogled));

/// Installation-wide history. A request is an API attempt, never a confirmed
/// impression or review: neither store exposes those outcomes.
class AppReviewHistory {
  const AppReviewHistory({
    this.launches = 0,
    this.requests = 0,
    this.lastRequest,
    this.existingUser,
  });

  final int launches;
  final int requests;
  final DateTime? lastRequest;
  // Null denotes an unclassified installation, including legacy v1 history.
  // Once persisted, wallet creation/deletion never changes this decision.
  final bool? existingUser;

  bool isDue(DateTime now) =>
      (existingUser == true || launches >= 3) &&
      (requests == 0 ||
          (requests == 1 &&
              lastRequest != null &&
              now.difference(lastRequest!) >= const Duration(days: 7)));

  String encode() => jsonEncode({
    'launches': launches,
    'requests': requests,
    'lastRequest': lastRequest?.toUtc().toIso8601String(),
    'existingUser': existingUser,
  });

  static AppReviewHistory decode(String? value) {
    if (value == null) return const AppReviewHistory();
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final launches = data['launches'] as int;
      final requests = data['requests'] as int;
      final last = data['lastRequest'] as String?;
      final existingUser = data['existingUser'] as bool?;
      if (launches < 0 ||
          requests < 0 ||
          requests > 2 ||
          (requests > 0 && last == null)) {
        throw const FormatException('Invalid review history');
      }
      return AppReviewHistory(
        launches: launches,
        requests: requests,
        lastRequest: last == null ? null : DateTime.parse(last),
        existingUser: existingUser,
      );
    } catch (_) {
      // Damaged history must not start a fresh request budget.
      return const AppReviewHistory(requests: 2);
    }
  }
}

abstract interface class AppReviewStore {
  Future<AppReviewHistory> load();
  Future<void> save(AppReviewHistory history);
}

class PreferencesAppReviewStore implements AppReviewStore {
  static const key = 'vizor_app_review_history_v1';
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<AppReviewHistory> load() async =>
      AppReviewHistory.decode(await _preferences.getString(key));

  @override
  Future<void> save(AppReviewHistory history) =>
      _preferences.setString(key, history.encode());
}

abstract interface class AppReviewNative {
  Future<bool> prepare();
  Future<bool> request();
  Future<void> cancel();
}

class MethodChannelAppReviewNative implements AppReviewNative {
  static const channel = MethodChannel('com.zcash.wallet/app_review');

  @override
  Future<bool> prepare() async =>
      await channel.invokeMethod<bool>('prepare') ?? false;

  @override
  Future<bool> request() async =>
      await channel.invokeMethod<bool>('request') ?? false;

  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}

/// One controller per production process, including bootstrap retries. A
/// foreground resume or an unlock never increments the cold-launch count.
class AppReviewController extends ChangeNotifier {
  AppReviewController({
    required this.store,
    required this.native,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final AppReviewStore store;
  final AppReviewNative native;
  final DateTime Function() now;
  AppReviewHistory history = const AppReviewHistory();
  Future<void>? _launch;
  bool _ready = false;
  bool _requesting = false;
  bool _used = false;
  String? _visitIntent;
  bool _visited = false;
  int _busy = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get isDue =>
      !_disposed && _ready && _used && !_requesting && history.isDue(now());
  bool get isBusy => _busy > 0;

  Future<void> recordLaunch({bool hadWalletAtStartup = false}) =>
      _launch ??= _recordLaunch(hadWalletAtStartup);

  Future<void> _recordLaunch(bool hadWalletAtStartup) async {
    try {
      final previous = await store.load();
      final next = AppReviewHistory(
        launches: previous.launches < 3 ? previous.launches + 1 : 3,
        requests: previous.requests,
        lastRequest: previous.lastRequest,
        existingUser: previous.existingUser ?? hadWalletAtStartup,
      );
      await store.save(next);
      history = next;
      _ready = true;
      _notify();
    } catch (_) {
      // Storage failure disables requests for this process; no fresh budget.
    }
  }

  void recordUse() {
    _used = true;
    _notify();
  }

  /// Only explicit user navigation calls this. Observing routes alone would
  /// mistake deep links, redirects and account management for usage.
  void expectVisit(String path) => _visitIntent = Uri.parse(path).path;

  void observePath(String path) {
    final intent = _visitIntent;
    if (intent != null && path != '/home') {
      // A tab's indexed stack can restore a detail below its root path.
      if (path == intent || path.startsWith('$intent/')) _visited = true;
      _visitIntent = null;
    }
    if (path == '/home') {
      _visitIntent = null;
      if (_visited) {
        _visited = false;
        recordUse();
      }
    }
  }

  Future<T> duringBusy<T>(Future<T> Function() action) async {
    _busy++;
    _notify();
    try {
      return await action();
    } finally {
      _busy--;
      _notify();
    }
  }

  /// Recheck the live surface after Play's asynchronous preparation and after
  /// persistence. Reserve before invoking native so process death cannot replay
  /// the same request. A definite cancellation restores the unused budget.
  Future<void> requestIfDue(bool Function() canPresent) async {
    if (!isDue || !canPresent()) return;
    _requesting = true;
    final previous = history;
    var reserved = false;
    var dispatched = false;
    var rearm = false;
    try {
      if (!await native.prepare()) return;
      if (!canPresent()) {
        rearm = true;
        return;
      }
      final next = AppReviewHistory(
        launches: previous.launches,
        requests: previous.requests + 1,
        lastRequest: now(),
        existingUser: previous.existingUser,
      );
      await store.save(next);
      history = next;
      reserved = true;
      if (!canPresent()) {
        rearm = true;
        return;
      }
      // Treat a lost native response conservatively: it may already have
      // requested a prompt. false explicitly means the API was not invoked.
      dispatched = true;
      dispatched = await native.request();
      rearm = !dispatched;
      if (dispatched) _used = false;
    } catch (_) {
      // Best effort: reviews must never interrupt wallet use.
      if (dispatched) _used = false;
    } finally {
      if (reserved && !dispatched) {
        try {
          await store.save(previous);
          history = previous;
        } catch (_) {
          // Keep the reservation when rollback fails, preserving the cap.
        }
      }
      try {
        await native.cancel();
      } catch (_) {}
      _requesting = false;
      // A surface may have become safe while preparation was still pending.
      // Preparation/storage errors do not auto-retry and spin indefinitely.
      if (rearm) _notify();
    }
  }
}

// Preview and test app builders opt in explicitly; production supplies the
// same process-owned controller across ProviderScope bootstrap retries.
final appReviewEnabledProvider = Provider<bool>((ref) => false);
// Production supplies the immutable bootstrap snapshot. Null means startup
// failed, so review history must wait for a successful bootstrap retry.
final appReviewStartupWalletProvider = Provider<bool?>((ref) => false);
final appReviewControllerProvider = Provider<AppReviewController>((ref) {
  final controller = AppReviewController(
    store: PreferencesAppReviewStore(),
    native: MethodChannelAppReviewNative(),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

void expectAppReviewVisit(WidgetRef ref, String path) {
  if (ref.read(appReviewEnabledProvider)) {
    ref.read(appReviewControllerProvider).expectVisit(path);
  }
}

Future<T> duringAppReviewBusy<T>(
  WidgetRef ref,
  Future<T> Function() action,
) async {
  if (!ref.read(appReviewEnabledProvider)) return action();
  return ref.read(appReviewControllerProvider).duringBusy(action);
}
