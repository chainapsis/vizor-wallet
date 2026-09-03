import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpException, HttpHeaders, Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../main.dart' show log;
import '../../app_bootstrap.dart';
import '../../providers/network_privacy_provider.dart';
import '../layout/app_form_factor.dart';
import '../layout/app_process_work_policy.dart';
import '../network/network_http_client.dart';
import 'app_version_config.dart';
import 'network_config.dart';
import 'swap_remote_enable_config.dart';

final swapFeatureEnabledProvider = Provider<bool>((ref) {
  final networkName = ref.watch(appBootstrapProvider).network;
  final networkEnabled = isSwapFeatureEnabledForNetwork(networkName);
  if (!networkEnabled) return false;
  if (!ref.watch(swapForceDisabledForCurrentBuildProvider)) return true;
  return ref.watch(swapEnabledRemoteOverrideProvider);
});

bool isSwapFeatureEnabledForNetwork(String networkName) {
  return zcashNetworkFromName(networkName) == ZcashNetwork.mainnet;
}

final swapFeatureIsIosProvider = Provider<bool>((_) => Platform.isIOS);

final swapForceDisabledForCurrentBuildProvider = Provider<bool>((ref) {
  return shouldForceDisableSwapForCurrentBuild(
    forceDisableDefine: kVizorForceDisableIosMobileSwap,
    formFactor: kAppFormFactor,
    isIOS: ref.watch(swapFeatureIsIosProvider),
  );
});

@visibleForTesting
bool shouldForceDisableSwapForCurrentBuild({
  required bool forceDisableDefine,
  required AppFormFactor formFactor,
  required bool isIOS,
}) {
  return forceDisableDefine && formFactor == AppFormFactor.mobile && isIOS;
}

abstract interface class SwapEnabledOverrideSource {
  /// Whether the remote override enables swap for [version]. `false` is a
  /// definitive answer from the document; an unknown answer (transport
  /// failure, non-2xx) throws so the caller can ask again.
  Future<bool> isEnabledForVersion(String version);
}

class HttpSwapEnabledOverrideSource implements SwapEnabledOverrideSource {
  HttpSwapEnabledOverrideSource({
    HttpClient? client,
    NetworkHttpClient? networkClient,
    Uri? endpoint,
    // Each Tor request builds a fresh circuit; 8s measured too tight.
    this.timeout = const Duration(seconds: 20),
  }) : _client = networkClient ?? NetworkHttpClient(directClient: client),
       _endpoint = endpoint ?? Uri.parse(kSwapEnabledOverrideUrl);

  final NetworkHttpClient _client;
  final Uri _endpoint;
  final Duration timeout;

  @override
  Future<bool> isEnabledForVersion(String version) async {
    final NetworkHttpResponse response;
    try {
      response = await _client.request(
        'GET',
        _endpoint,
        headers: const {HttpHeaders.acceptHeader: 'application/json'},
        timeout: timeout,
      );
    } catch (e) {
      log('swapFeature: override fetch failed: $e');
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      log('swapFeature: override returned ${response.statusCode}');
      throw HttpException(
        'Swap override returned ${response.statusCode}',
        uri: _endpoint,
      );
    }
    return parseSwapEnabledOverrideForVersion(
      utf8.decode(response.bodyBytes),
      version,
    );
  }

  void close({bool force = false}) {
    _client.close(force: force);
  }
}

abstract interface class SwapEnabledOverrideStore {
  Future<void> cacheEnabledForVersion(String version);
}

class SharedPreferencesSwapEnabledOverrideStore
    implements SwapEnabledOverrideStore {
  const SharedPreferencesSwapEnabledOverrideStore();

  @override
  Future<void> cacheEnabledForVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(swapEnabledOverrideStorageKey(version), true);
  }
}

final swapEnabledOverrideSourceProvider = Provider<SwapEnabledOverrideSource>((
  ref,
) {
  final source = HttpSwapEnabledOverrideSource();
  ref.onDispose(() => source.close());
  return source;
});

final swapEnabledOverrideStoreProvider = Provider<SwapEnabledOverrideStore>((
  ref,
) {
  return const SharedPreferencesSwapEnabledOverrideStore();
});

/// Delays before re-asking after an unknown answer; the last entry repeats.
/// Unbounded on purpose: one small GET every five minutes, on a fresh Tor
/// circuit each time.
const _kSwapOverrideRetryDelays = <Duration>[
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 120),
  Duration(seconds: 300),
];

/// Whether an override retry may run in the current lifecycle (mobile is
/// foreground-only; the Tor client sleeps on hide).
final swapOverrideProcessWorkPolicyProvider =
    Provider<bool Function({required bool isInForeground})>(
      (_) => canRunAppProcessWork,
    );

final swapEnabledRemoteOverrideProvider =
    NotifierProvider<SwapEnabledRemoteOverrideNotifier, bool>(
      SwapEnabledRemoteOverrideNotifier.new,
    );

class SwapEnabledRemoteOverrideNotifier extends Notifier<bool> {
  var _fetchStarted = false;
  var _fetchInFlight = false;
  var _retryOnRouteChange = false;
  var _disposed = false;
  Timer? _retryTimer;
  var _retryAttempt = 0;
  AppLifecycleListener? _lifecycle;
  var _isInForeground = true;

  /// A retry that fell due while backgrounded, owed on the next resume.
  var _retryDeferredToForeground = false;

  bool get _mayRunNow => ref.read(swapOverrideProcessWorkPolicyProvider)(
    isInForeground: _isInForeground,
  );

  @override
  bool build() {
    // A retry that runs after `onHide` would build a Tor circuit on a client
    // the lifecycle just put to sleep, so mobile parks it until resume.
    _lifecycle ??= AppLifecycleListener(
      onHide: () {
        _isInForeground = false;
        if (_mayRunNow || _retryTimer == null) return;
        _cancelRetry();
        _retryDeferredToForeground = true;
      },
      onResume: () {
        _isInForeground = true;
        if (!_retryDeferredToForeground) return;
        _retryDeferredToForeground = false;
        if (_disposed || _fetchInFlight) return;
        unawaited(_fetchOverride());
      },
    );
    ref.onDispose(() {
      _disposed = true;
      _cancelRetry();
      _lifecycle?.dispose();
      _lifecycle = null;
    });
    final bootstrap = ref.watch(appBootstrapProvider);
    if (bootstrap.swapEnabledOverrideCachedForRelease) return true;
    if (!ref.watch(swapForceDisabledForCurrentBuildProvider)) return false;
    if (!isSwapFeatureEnabledForNetwork(bootstrap.network)) return false;

    // An unknown answer is asked again once the route settles (off or
    // connected); a settled route is better evidence than the timer.
    ref.listen(networkPrivacyProvider, (previous, next) {
      if (next.status == previous?.status) return;
      if (next.status != NetworkPrivacyConnectionStatus.off &&
          next.status != NetworkPrivacyConnectionStatus.connected) {
        return;
      }
      if (!_retryOnRouteChange || _fetchInFlight) return;
      _cancelRetry();
      if (!_mayRunNow) {
        _retryDeferredToForeground = true;
        return;
      }
      unawaited(_fetchOverride());
    });

    if (!_fetchStarted) {
      _fetchStarted = true;
      scheduleMicrotask(() => unawaited(_fetchOverride()));
    }
    return false;
  }

  Future<void> _fetchOverride() async {
    final source = ref.read(swapEnabledOverrideSourceProvider);
    final bool enabled;
    _fetchInFlight = true;
    try {
      enabled = await source.isEnabledForVersion(kVizorReleaseVersion);
    } catch (e) {
      // Unknown, not disabled: ask again on a route change or on the timer
      // (the route can already be settled when a slow Tor exit times out).
      log('swapFeature: override fetch unresolved: $e');
      _retryOnRouteChange = true;
      _scheduleRetry();
      return;
    } finally {
      _fetchInFlight = false;
    }
    _retryOnRouteChange = false;
    _cancelRetry();
    _retryAttempt = 0;
    if (_disposed) return;
    if (!enabled) return;
    try {
      await ref
          .read(swapEnabledOverrideStoreProvider)
          .cacheEnabledForVersion(kVizorReleaseVersion);
    } catch (e) {
      log('swapFeature: failed to cache override: $e');
    }
    if (_disposed) return;
    state = true;
  }

  void _scheduleRetry() {
    if (_disposed) return;
    final index = _retryAttempt < _kSwapOverrideRetryDelays.length
        ? _retryAttempt
        : _kSwapOverrideRetryDelays.length - 1;
    _retryAttempt++;
    _retryTimer?.cancel();
    if (!_mayRunNow) {
      _retryDeferredToForeground = true;
      return;
    }
    _retryTimer = Timer(_kSwapOverrideRetryDelays[index], () {
      _retryTimer = null;
      // A running fetch schedules the next attempt itself; a hide that raced
      // this timer hands it to the next resume.
      if (_disposed || _fetchInFlight) return;
      if (!_mayRunNow) {
        _retryDeferredToForeground = true;
        return;
      }
      unawaited(_fetchOverride());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
