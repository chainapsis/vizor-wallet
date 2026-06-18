import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders, Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../main.dart' show log;
import '../../app_bootstrap.dart';
import '../layout/app_form_factor.dart';
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
  Future<bool> isEnabledForVersion(String version);
}

class HttpSwapEnabledOverrideSource implements SwapEnabledOverrideSource {
  HttpSwapEnabledOverrideSource({
    HttpClient? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? HttpClient(),
       _endpoint = endpoint ?? Uri.parse(kSwapEnabledOverrideUrl);

  final HttpClient _client;
  final Uri _endpoint;
  final Duration timeout;

  @override
  Future<bool> isEnabledForVersion(String version) async {
    try {
      final request = await _client.getUrl(_endpoint).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        log('swapFeature: override returned ${response.statusCode}');
        return false;
      }
      return parseSwapEnabledOverrideForVersion(body, version);
    } catch (e) {
      log('swapFeature: override fetch failed: $e');
      return false;
    }
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

final swapEnabledRemoteOverrideProvider =
    NotifierProvider<SwapEnabledRemoteOverrideNotifier, bool>(
      SwapEnabledRemoteOverrideNotifier.new,
    );

class SwapEnabledRemoteOverrideNotifier extends Notifier<bool> {
  var _fetchStarted = false;
  var _disposed = false;

  @override
  bool build() {
    ref.onDispose(() {
      _disposed = true;
    });
    final bootstrap = ref.watch(appBootstrapProvider);
    if (bootstrap.swapEnabledOverrideCachedForRelease) return true;
    if (!ref.watch(swapForceDisabledForCurrentBuildProvider)) return false;
    if (!isSwapFeatureEnabledForNetwork(bootstrap.network)) return false;

    if (!_fetchStarted) {
      _fetchStarted = true;
      scheduleMicrotask(() => unawaited(_fetchOverride()));
    }
    return false;
  }

  Future<void> _fetchOverride() async {
    final source = ref.read(swapEnabledOverrideSourceProvider);
    final enabled = await source.isEnabledForVersion(kVizorReleaseVersion);
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
}
