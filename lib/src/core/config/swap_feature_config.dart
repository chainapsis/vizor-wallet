import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpException, HttpHeaders, Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../main.dart' show log;
import '../../app_bootstrap.dart';
import '../../providers/network_privacy_provider.dart';
import '../layout/app_form_factor.dart';
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
  /// Whether the remote override enables swap for [version].
  ///
  /// `false` is a definitive answer: the document was read and this version is
  /// not enabled in it. Anything that leaves the answer unknown — a transport
  /// failure, a non-2xx response — throws instead, so a caller can ask again
  /// rather than treat a request it never got an answer to as a "no".
  Future<bool> isEnabledForVersion(String version);
}

class HttpSwapEnabledOverrideSource implements SwapEnabledOverrideSource {
  HttpSwapEnabledOverrideSource({
    HttpClient? client,
    NetworkHttpClient? networkClient,
    Uri? endpoint,
    // Tor builds a fresh circuit for this request, and 8s measured too tight
    // on a slow exit.
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

/// Delays before re-asking after a fetch that left the answer unknown.
///
/// The last entry repeats for as long as the answer stays unknown. Attempts
/// are unbounded on purpose: one small GET every five minutes costs nothing,
/// and every Tor request is built on a fresh circuit, so a later attempt is a
/// genuinely new draw rather than a repeat of the same failure.
const _kSwapOverrideRetryDelays = <Duration>[
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 120),
  Duration(seconds: 300),
];

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

  @override
  bool build() {
    ref.onDispose(() {
      _disposed = true;
      _cancelRetry();
    });
    final bootstrap = ref.watch(appBootstrapProvider);
    if (bootstrap.swapEnabledOverrideCachedForRelease) return true;
    if (!ref.watch(swapForceDisabledForCurrentBuildProvider)) return false;
    if (!isSwapFeatureEnabledForNetwork(bootstrap.network)) return false;

    // The first fetch runs during launch, which on a Tor wallet is while the
    // route is fail-closed and still bootstrapping: the request is refused in
    // milliseconds and nothing else ever asks again, so swap stays off for the
    // whole session. Ask once more when the route reaches a settled state.
    ref.listen(networkPrivacyProvider, (previous, next) {
      if (next.status == previous?.status) return;
      if (next.status != NetworkPrivacyConnectionStatus.off &&
          next.status != NetworkPrivacyConnectionStatus.connected) {
        return;
      }
      if (!_retryOnRouteChange || _fetchInFlight) return;
      // A settled route is better evidence than the clock, so it takes over
      // the pending attempt instead of racing it.
      _cancelRetry();
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
      // Unknown, not disabled. Keep the answer pending so a settled route can
      // resolve it; a definitive `false` deliberately does not come back here.
      log('swapFeature: override fetch unresolved: $e');
      _retryOnRouteChange = true;
      // A route transition may never come — the route can already be settled
      // when the request fails, as a slow Tor exit does. Keep asking on a
      // timer so the session is not written off after one attempt.
      _scheduleRetry();
      return;
    } finally {
      _fetchInFlight = false;
    }
    // Answered, either way. Nothing is owed another attempt.
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
    _retryTimer = Timer(_kSwapOverrideRetryDelays[index], () {
      _retryTimer = null;
      // A fetch already running will schedule the next attempt itself.
      if (_disposed || _fetchInFlight) return;
      unawaited(_fetchOverride());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
