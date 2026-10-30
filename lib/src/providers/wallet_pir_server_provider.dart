import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';
import '../rust/api/pir_config.dart' as rust;
import '../services/wallet_pir/wallet_pir_config.dart';
import 'account_provider.dart';
import 'sync_provider.dart';

const kWalletPirConfigCacheKeyPrefix = 'zcash_wallet_pir_config_v1_';
const kWalletPirConfigRefreshInterval = Duration(minutes: 5);

/// Plain (non-secret) persistence of the last good snapshot and server choice,
/// scoped to the app's fixed source and network. A future app source/pin change
/// cannot reuse another source's cached config or choice.
abstract interface class WalletPirConfigStore {
  Future<WalletPirCachedConfig?> readCached(String network, String source);
  Future<void> writeCached(
    String network,
    String source,
    WalletPirCachedConfig cached,
  );
}

class WalletPirCachedConfig {
  const WalletPirCachedConfig({
    this.snapshotJson,
    this.selectionJson,
    this.customBaseUrl,
  });

  final String? snapshotJson;
  final String? selectionJson;
  final String? customBaseUrl;

  WalletPirCachedConfig copyWith({
    String? snapshotJson,
    String? selectionJson,
    String? customBaseUrl,
    bool clearCustomServer = false,
  }) => WalletPirCachedConfig(
    snapshotJson: snapshotJson ?? this.snapshotJson,
    selectionJson: selectionJson ?? this.selectionJson,
    customBaseUrl: clearCustomServer
        ? null
        : customBaseUrl ?? this.customBaseUrl,
  );

  Map<String, Object?> toJson() => {
    'snapshot': snapshotJson,
    'selection': selectionJson,
    'customBaseUrl': customBaseUrl,
  };

  static WalletPirCachedConfig fromJson(Object? json) {
    if (json is! Map) return const WalletPirCachedConfig();
    return WalletPirCachedConfig(
      snapshotJson: json['snapshot'] as String?,
      selectionJson: json['selection'] as String?,
      customBaseUrl: json['customBaseUrl'] as String?,
    );
  }
}

class AppSecureStoreWalletPirConfigStore implements WalletPirConfigStore {
  const AppSecureStoreWalletPirConfigStore(this._store);

  final AppSecureStore _store;

  @override
  Future<WalletPirCachedConfig?> readCached(
    String network,
    String source,
  ) async {
    final entries = await _readEntries(network);
    final entry = entries[source];
    return entry == null ? null : WalletPirCachedConfig.fromJson(entry);
  }

  @override
  Future<void> writeCached(
    String network,
    String source,
    WalletPirCachedConfig cached,
  ) async {
    final entries = await _readEntries(network);
    entries[source] = cached.toJson();
    await _store.writePlain(
      '$kWalletPirConfigCacheKeyPrefix$network',
      jsonEncode(entries),
    );
  }

  Future<Map<String, Object?>> _readEntries(String network) async {
    final raw = await _store.readPlain(
      '$kWalletPirConfigCacheKeyPrefix$network',
    );
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      return {};
    }
  }
}

/// Makes `baseUrl` (or no server) the one all four private products use.
typedef WalletPirServerApplier = Future<void> Function(String? baseUrl);

/// An explicit custom choice. Invalid saved input requires another choice
/// instead of silently activating a server from the published list.
@immutable
class WalletPirCustomServer {
  const WalletPirCustomServer(this.baseUrl, {this.error});

  final String baseUrl;
  final String? error;
  bool get isValid => error == null;
}

/// Where the settings screen stands. Labels are display text; the base URL is
/// the identity.
@immutable
class WalletPirServerState {
  const WalletPirServerState({
    required this.source,
    this.config,
    this.customServer,
    this.refreshing = false,
    this.refreshError,
  });

  /// The app's fixed pinned source, or `null` on unsupported networks.
  final String? source;

  /// The last good config for [source]; kept when a refresh fails.
  final WalletPirConfigView? config;
  final WalletPirCustomServer? customServer;
  final bool refreshing;

  /// Why the latest refresh failed, if it did.
  final String? refreshError;

  List<WalletPirServerOption> get servers => config?.servers ?? const [];
  String? get selectedBaseUrl => customServer == null
      ? config?.selectedBaseUrl
      : customServer!.isValid
      ? customServer!.baseUrl
      : null;
  bool get needsSelection => customServer == null
      ? config?.selectionState == WalletPirSelectionState.selectionRequired
      : !customServer!.isValid;
  bool get hasNoServers =>
      customServer == null &&
      config?.selectionState == WalletPirSelectionState.noServers;

  WalletPirServerOption? get selectedServer {
    final base = selectedBaseUrl;
    if (base == null) return null;
    if (customServer != null) {
      return WalletPirServerOption(label: 'Custom server', baseUrl: base);
    }
    for (final server in servers) {
      if (server.baseUrl == base) return server;
    }
    return null;
  }

  WalletPirServerState copyWith({
    WalletPirConfigView? config,
    WalletPirCustomServer? customServer,
    bool clearCustomServer = false,
    bool? refreshing,
    String? refreshError,
    bool clearRefreshError = false,
  }) => WalletPirServerState(
    source: source,
    config: config ?? this.config,
    customServer: clearCustomServer ? null : customServer ?? this.customServer,
    refreshing: refreshing ?? this.refreshing,
    refreshError: clearRefreshError ? null : refreshError ?? this.refreshError,
  );
}

final walletPirConfigStoreProvider = Provider<WalletPirConfigStore>(
  (ref) => AppSecureStoreWalletPirConfigStore(AppSecureStore.instance),
);

final walletPirConfigResolverProvider = Provider<WalletPirConfigResolver>(
  (ref) => const RustWalletPirConfigResolver(),
);

final walletPirConfigFetcherProvider = Provider<WalletPirConfigFetcher>(
  (ref) => RoutedWalletPirConfigFetcher(),
);

final walletPirConfigSourceProvider = Provider<String?>(
  (ref) => defaultWalletPirConfigSource(),
);

final walletPirNetworkProvider = Provider<String>(
  (ref) => walletPirConfigNetworkName(),
);

/// Pauses sync, applies the server in Rust (which forgets caches tied
/// to the old server), then resumes sync so every
/// product session is rebuilt against the new base.
///
/// A failed Rust apply leaves no server selected with its cleanup still owed,
/// so the next call goes to Rust even for the base Rust now reports.
final walletPirServerApplierProvider = Provider<WalletPirServerApplier>((ref) {
  var cleanupOwed = false;
  return (baseUrl) async {
    if (!cleanupOwed && rust.selectedWalletPirServer() == baseUrl) return;
    try {
      await _applyWalletPirServer(ref, baseUrl);
      cleanupOwed = false;
    } catch (_) {
      cleanupOwed = true;
      rethrow;
    }
  };
});

Future<void> _applyWalletPirServer(Ref ref, String? baseUrl) async {
  final hasWallet =
      (ref.read(accountProvider).value?.accounts ?? const []).isNotEmpty;
  if (!hasWallet) {
    await rust.applyWalletPirServer(baseUrl: baseUrl);
    return;
  }
  final sync = ref.read(syncProvider.notifier);
  final pause = await sync.pauseForWalletMutation();
  try {
    await rust.applyWalletPirServer(baseUrl: baseUrl);
  } finally {
    sync.resumeAfterWalletMutation(pause, forceRestart: true);
  }
}

class WalletPirServerNotifier extends AsyncNotifier<WalletPirServerState> {
  /// A commit from a disposed or rebuilt provider does nothing.
  int _lifecycleGeneration = 0;

  /// Bumped by every refresh and rebuild, so only the latest refresh
  /// commits what it fetched.
  int _refreshGeneration = 0;

  /// The tail of the commit queue. Every durable write and every server
  /// apply runs inside [_commit], one at a time in call order, and checks
  /// that its intent is still current when it starts. The last commit to run
  /// is therefore the newest, and its server is the one Rust ends up using,
  /// however long an earlier apply or write took.
  Future<void> _commits = Future.value();
  AppLifecycleListener? _lifecycle;
  Timer? _refreshTimer;

  WalletPirConfigStore get _store => ref.read(walletPirConfigStoreProvider);
  WalletPirConfigResolver get _resolver =>
      ref.read(walletPirConfigResolverProvider);
  String get _network => ref.read(walletPirNetworkProvider);
  WalletPirServerApplier get _applier =>
      ref.read(walletPirServerApplierProvider);

  @override
  Future<WalletPirServerState> build() async {
    _lifecycle?.dispose();
    _refreshTimer?.cancel();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _startAutomaticRefresh();
          unawaited(refreshAutomatically());
        } else {
          _refreshTimer?.cancel();
          _refreshTimer = null;
        }
      },
    );
    ref.onDispose(() {
      _lifecycleGeneration++;
      _refreshGeneration++;
      _lifecycle?.dispose();
      _lifecycle = null;
      _refreshTimer?.cancel();
      _refreshTimer = null;
    });
    final generation = ++_lifecycleGeneration;
    _refreshGeneration++;
    final initial = await _loadCached();
    await _commit(() async {
      if (generation != _lifecycleGeneration) return;
      await _applier(initial.selectedBaseUrl);
    });
    if (generation == _lifecycleGeneration && initial.source != null) {
      _startAutomaticRefresh();
      scheduleMicrotask(() => unawaited(refreshAutomatically()));
    }
    return initial;
  }

  void _startAutomaticRefresh() {
    if (ref.read(walletPirConfigSourceProvider) == null) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      kWalletPirConfigRefreshInterval,
      (_) => unawaited(refreshAutomatically()),
    );
  }

  /// Automatic triggers keep the active fetch running instead of repeatedly
  /// superseding it while a slow mirror is still responding.
  Future<void> refreshAutomatically() async {
    if (state.value?.refreshing ?? true) return;
    await refresh();
  }

  /// Fetches the source's documents again. A failure keeps the last good
  /// config and shows why.
  Future<void> refresh() async {
    final current = state.value;
    final source = current?.source;
    if (current == null || source == null) return;
    final lifecycleGeneration = _lifecycleGeneration;
    final refreshGeneration = ++_refreshGeneration;
    bool live() =>
        lifecycleGeneration == _lifecycleGeneration &&
        refreshGeneration == _refreshGeneration;
    state = AsyncData(current.copyWith(refreshing: true));
    try {
      final fetchedWith = await _store.readCached(_network, source);
      final fetched = await fetchWalletPirConfig(
        fetcher: ref.read(walletPirConfigFetcherProvider),
        resolver: _resolver,
        source: source,
        network: _network,
        savedSelectionJson: fetchedWith?.selectionJson,
      );
      await _commit(() async {
        if (!live()) return;
        final cached = await _store.readCached(_network, source);
        if (!live()) return;
        // A choice the user made while this fetch ran wins over the one the
        // fetch was resolved with.
        final view = cached?.selectionJson == fetchedWith?.selectionJson
            ? fetched
            : _resolver.revalidate(
                source: source,
                network: _network,
                snapshotJson: fetched.snapshotJson,
                savedSelectionJson: cached?.selectionJson,
              );
        // From here the commit completes: the write, the apply and the state
        // stay consistent, and any newer commit runs after this one.
        await _store.writeCached(
          _network,
          source,
          (cached ?? const WalletPirCachedConfig()).copyWith(
            snapshotJson: view.snapshotJson,
            // A removed selection stays saved, so a restart asks again.
            selectionJson: view.selectionJson,
          ),
        );
        final next = (state.value ?? current).copyWith(
          config: view,
          customServer: _validateSavedCustomServer(cached?.customBaseUrl),
          clearCustomServer: cached?.customBaseUrl == null,
          refreshing: false,
          clearRefreshError: true,
        );
        await _applier(next.selectedBaseUrl);
        state = AsyncData(next);
      });
    } catch (error) {
      if (!live()) return;
      state = AsyncData(
        (state.value ?? current).copyWith(
          refreshing: false,
          refreshError: '$error',
        ),
      );
    }
  }

  /// The user's explicit choice of an offered server.
  Future<void> selectServer(String baseUrl) {
    final generation = _lifecycleGeneration;
    return _commit(() async {
      if (generation != _lifecycleGeneration) return;
      // Read at commit time, so a choice is made against the latest accepted
      // config, never one a refresh has since replaced.
      final current = state.value;
      final source = current?.source;
      final config = current?.config;
      if (current == null || source == null || config == null) return;
      final selectionJson = _resolver.select(
        source: source,
        network: _network,
        snapshotJson: config.snapshotJson,
        baseUrl: baseUrl,
      );
      final view = _resolver.revalidate(
        source: source,
        network: _network,
        snapshotJson: config.snapshotJson,
        savedSelectionJson: selectionJson,
      );
      final cached = await _store.readCached(_network, source);
      if (generation != _lifecycleGeneration) return;
      await _store.writeCached(
        _network,
        source,
        (cached ?? const WalletPirCachedConfig()).copyWith(
          snapshotJson: config.snapshotJson,
          selectionJson: selectionJson,
          clearCustomServer: true,
        ),
      );
      if (generation != _lifecycleGeneration) return;
      await _applier(view.selectedBaseUrl);
      if (generation != _lifecycleGeneration) return;
      state = AsyncData(
        (state.value ?? current).copyWith(
          config: view,
          clearCustomServer: true,
        ),
      );
    });
  }

  /// Uses an explicit custom base, separate from the published list. The
  /// serialized commit queue also orders this choice against refreshes.
  Future<void> selectCustomServer(String input) {
    final generation = _lifecycleGeneration;
    return _commit(() async {
      if (generation != _lifecycleGeneration) return;
      final current = state.value;
      final source = current?.source;
      if (current == null || source == null) {
        throw const WalletPirConfigException(
          'Private queries are unavailable on this network.',
        );
      }
      final baseUrl = _resolver.normalizeCustomServer(input);
      final cached = await _store.readCached(_network, source);
      if (generation != _lifecycleGeneration) return;
      await _store.writeCached(
        _network,
        source,
        (cached ?? const WalletPirCachedConfig()).copyWith(
          customBaseUrl: baseUrl,
        ),
      );
      if (generation != _lifecycleGeneration) return;
      await _applier(baseUrl);
      if (generation != _lifecycleGeneration) return;
      state = AsyncData(
        (state.value ?? current).copyWith(
          customServer: WalletPirCustomServer(baseUrl),
        ),
      );
    });
  }

  WalletPirCustomServer? _validateSavedCustomServer(String? baseUrl) {
    if (baseUrl == null) return null;
    try {
      return WalletPirCustomServer(_resolver.normalizeCustomServer(baseUrl));
    } catch (_) {
      return WalletPirCustomServer(
        baseUrl,
        error: 'Choose a valid HTTPS server.',
      );
    }
  }

  Future<WalletPirServerState> _loadCached() async {
    final source = ref.read(walletPirConfigSourceProvider);
    final base = WalletPirServerState(source: source);
    if (source == null) return base;
    final cached = await _store.readCached(_network, source);
    final withCustom = base.copyWith(
      customServer: _validateSavedCustomServer(cached?.customBaseUrl),
    );
    final snapshot = cached?.snapshotJson;
    if (snapshot == null) return withCustom;
    try {
      return withCustom.copyWith(
        config: _resolver.revalidate(
          source: source,
          network: _network,
          snapshotJson: snapshot,
          savedSelectionJson: cached?.selectionJson,
        ),
      );
    } catch (error) {
      // A cached config that no longer passes is not used.
      return withCustom;
    }
  }

  /// Runs `body` after every earlier commit has finished, whether or not it
  /// succeeded.
  Future<void> _commit(Future<void> Function() body) {
    final run = _commits.then((_) => body());
    _commits = run.catchError((Object _) {});
    return run;
  }
}

final walletPirServerProvider =
    AsyncNotifierProvider<WalletPirServerNotifier, WalletPirServerState>(
      WalletPirServerNotifier.new,
    );

/// Keeps [walletPirServerProvider] alive from app start, so the saved server
/// is applied and refreshed without the app root rebuilding on its changes.
final walletPirServerActivatorProvider = Provider<void>((ref) {
  ref.listen(walletPirServerProvider, (_, _) {});
});
