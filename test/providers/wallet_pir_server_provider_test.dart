import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/settings/widgets/enhance_pir_privacy_control.dart';
import 'package:zcash_wallet/src/features/settings/widgets/mobile/mobile_private_queries_control.dart';
import 'package:zcash_wallet/src/features/settings/widgets/wallet_pir_server_popup.dart';
import 'package:zcash_wallet/src/features/settings/widgets/wallet_pir_server_settings.dart';
import 'package:zcash_wallet/src/providers/wallet_pir_server_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_pir_latency_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/services/wallet_pir/wallet_pir_config.dart';
import 'package:zcash_wallet/src/services/wallet_pir/wallet_pir_latency.dart';

const _sourceA = 'https://config.example/a/static.json?checksum=sha256:aaaa';
const _sourceB = 'https://config.example/b/static.json?checksum=sha256:bbbb';
const _mirror = 'https://config.example/dynamic.json';

class _MemoryStore implements WalletPirConfigStore {
  final cached = <String, WalletPirCachedConfig>{};

  /// Holds open the next write whose selection names a key's base.
  final writeGates = <String, Completer<void>>{};

  @override
  Future<WalletPirCachedConfig?> readCached(String network, String src) async =>
      cached['$network|$src'];

  @override
  Future<void> writeCached(
    String network,
    String src,
    WalletPirCachedConfig value,
  ) async {
    final selection =
        '${value.selectionJson ?? ''}|${value.customBaseUrl ?? ''}';
    for (final base in [...writeGates.keys]) {
      if (selection.contains(base)) await writeGates.remove(base)!.future;
    }
    cached['$network|$src'] = value;
  }
}

/// Serves the static document (whose body names its source) and a dynamic
/// document per source. A gate holds a source's fetch open for race tests.
class _Fetcher implements WalletPirConfigFetcher {
  int requests = 0;
  final servers = <String, List<List<String>>>{};
  final failing = <String>{};
  final gates = <String, Completer<void>>{};
  String _lastStatic = '';

  @override
  Future<Uint8List> fetch(Uri uri) async {
    requests++;
    final url = uri.toString();
    if (url != _mirror) {
      final source = [
        _sourceA,
        _sourceB,
      ].firstWhere((s) => walletPirConfigTransportUri(s).toString() == url);
      await gates[source]?.future;
      if (failing.contains(source)) throw Exception('offline');
      _lastStatic = source;
      return Uint8List.fromList(utf8.encode(source));
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode(servers[_lastStatic] ?? const [])),
    );
  }
}

/// Stands in for the Rust profile with its selection rules: keep an
/// advertised choice, require a new one when it is removed, default to the
/// first server only without an earlier choice in the scope.
class _Resolver implements WalletPirConfigResolver {
  @override
  String normalizeCustomServer(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const WalletPirConfigException('invalid custom server');
    }
    return uri
        .replace(scheme: 'https', host: uri.host.toLowerCase())
        .toString()
        .replaceFirst(RegExp(r'/+$'), '');
  }

  @override
  List<String> resolveStatic({
    required String source,
    required String network,
    required Uint8List staticBytes,
  }) {
    if (utf8.decode(staticBytes) != source) {
      throw const WalletPirConfigException('hash-pin mismatch');
    }
    return const [_mirror];
  }

  @override
  WalletPirConfigView resolve({
    required String source,
    required String network,
    required Uint8List staticBytes,
    required List<WalletPirMirrorAttempt> attempts,
    String? savedSelectionJson,
  }) {
    final bytes = attempts.last.bytes;
    if (bytes == null) throw WalletPirConfigException(attempts.last.error!);
    final snapshot = jsonEncode({
      'source': source,
      'servers': jsonDecode(utf8.decode(bytes)),
    });
    return revalidate(
      source: source,
      network: network,
      snapshotJson: snapshot,
      savedSelectionJson: savedSelectionJson,
    );
  }

  @override
  WalletPirConfigView revalidate({
    required String source,
    required String network,
    required String snapshotJson,
    String? savedSelectionJson,
  }) {
    final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
    if (snapshot['source'] != source) {
      throw const WalletPirConfigException('snapshot from another source');
    }
    final servers = [
      for (final s in snapshot['servers'] as List)
        WalletPirServerOption(label: s[0] as String, baseUrl: s[1] as String),
    ];
    final saved = savedSelectionJson == null
        ? null
        : jsonDecode(savedSelectionJson) as Map<String, dynamic>;
    final inScope = saved != null && saved['scope'] == source ? saved : null;
    String selection(String base) =>
        jsonEncode({'scope': source, 'base': base});
    final base = inScope?['base'] as String?;
    if (base != null) {
      final kept = servers.any((s) => s.baseUrl == base);
      return WalletPirConfigView(
        scope: source,
        snapshotJson: snapshotJson,
        servers: servers,
        selectionState: kept
            ? WalletPirSelectionState.kept
            : WalletPirSelectionState.selectionRequired,
        selectedBaseUrl: kept ? base : null,
        selectionJson: kept ? selection(base) : null,
        removedBaseUrl: kept ? null : base,
      );
    }
    if (servers.isEmpty) {
      return WalletPirConfigView(
        scope: source,
        snapshotJson: snapshotJson,
        servers: servers,
        selectionState: WalletPirSelectionState.noServers,
      );
    }
    return WalletPirConfigView(
      scope: source,
      snapshotJson: snapshotJson,
      servers: servers,
      selectionState: WalletPirSelectionState.defaulted,
      selectedBaseUrl: servers.first.baseUrl,
      selectionJson: selection(servers.first.baseUrl),
    );
  }

  @override
  String select({
    required String source,
    required String network,
    required String snapshotJson,
    required String baseUrl,
  }) {
    final view = revalidate(
      source: source,
      network: network,
      snapshotJson: snapshotJson,
    );
    if (!view.servers.any((s) => s.baseUrl == baseUrl)) {
      throw const WalletPirConfigException('not advertised');
    }
    return jsonEncode({'scope': source, 'base': baseUrl});
  }
}

class _Harness {
  _Harness({String? source = _sourceA, bool privateQueriesOn = true}) {
    container = ProviderContainer(
      overrides: [
        walletPirConfigStoreProvider.overrideWithValue(store),
        walletPirConfigResolverProvider.overrideWithValue(_Resolver()),
        walletPirConfigFetcherProvider.overrideWithValue(fetcher),
        walletPirConfigSourceProvider.overrideWithValue(source),
        walletPirNetworkProvider.overrideWithValue('mainnet'),
        walletPirServerProbeProvider.overrideWithValue(
          (_, _) async =>
              const WalletPirPingSample.available(Duration(milliseconds: 42)),
        ),
        walletPirConfigRepositoryLauncherProvider.overrideWithValue((
          uri,
        ) async {
          openedRepositories.add(uri);
          return true;
        }),
        enhancePirAvailableProvider.overrideWithValue(true),
        privateQueriesControlEnabledProvider.overrideWithValue(
          privateQueriesOn,
        ),
        walletPirServerApplierProvider.overrideWithValue((base) async {
          applying++;
          if (applying > maxApplying) maxApplying = applying;
          try {
            await applyGates.remove(base)?.future;
            applied.add(base);
          } finally {
            applying--;
          }
        }),
      ],
    );
    addTearDown(dispose);
  }

  final store = _MemoryStore();
  final fetcher = _Fetcher();

  /// Servers in the order their apply finished.
  final applied = <String?>[];
  final openedRepositories = <Uri>[];
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  /// Holds open the next apply of a base.
  final applyGates = <String?, Completer<void>>{};
  var applying = 0;
  var maxApplying = 0;
  late ProviderContainer container;

  WalletPirServerNotifier get notifier =>
      container.read(walletPirServerProvider.notifier);

  WalletPirServerState get state =>
      container.read(walletPirServerProvider).requireValue;

  Future<void> start() async {
    await container.read(walletPirServerProvider.future);
    await pumpEventQueue();
  }

  /// A fresh app start over the same storage.
  _Harness restart() {
    final next = _Harness();
    next.store.cached.addAll(store.cached);
    next.fetcher.servers.addAll(fetcher.servers);
    next.fetcher.failing.addAll(fetcher.failing);
    dispose();
    return next;
  }
}

const _a = ['Server A', 'https://a.example'];
const _b = ['Server B', 'https://b.example'];
const _c = ['Server C', 'https://c.example'];

String? _savedBase(_Harness h, [String source = _sourceA]) {
  final json = h.store.cached['mainnet|$source']?.selectionJson;
  return json == null ? null : (jsonDecode(json) as Map)['base'] as String?;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the list refreshes every five minutes and pauses in the background',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = _Harness();
      h.fetcher.servers[_sourceA] = [_a];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: Consumer(
            builder: (_, ref, _) {
              ref.watch(walletPirServerProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.fetcher.requests, 2);
      await tester.pump(kWalletPirConfigRefreshInterval);
      await tester.pumpAndSettle();
      expect(h.fetcher.requests, 4);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 10));
      expect(h.fetcher.requests, 4);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.fetcher.requests, 6);
      h.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 5));
      expect(h.fetcher.requests, 6);
    },
  );

  test('automatic triggers do not replace an in-flight config fetch', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a];
    await h.start();
    final gate = h.fetcher.gates[_sourceA] = Completer<void>();
    final first = h.notifier.refreshAutomatically();
    await pumpEventQueue();
    final inFlightRequests = h.fetcher.requests;
    await h.notifier.refreshAutomatically();
    expect(h.fetcher.requests, inFlightRequests);
    gate.complete();
    await first;
  });

  testWidgets('the settings popup offers both servers and saves the choice', (
    tester,
  ) async {
    const primary = 'https://wallet-pir.valargroup.dev';
    const secondary = 'https://wallet-pir-secondary.valargroup.dev';
    final h = _Harness();
    var toggles = 0;
    h.fetcher.servers[_sourceA] = [
      ['Valargroup Wallet PIR', primary],
      ['Valargroup Wallet PIR Secondary', secondary],
    ];
    await tester.runAsync(h.start);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Scaffold(
              body: kAppFormFactor == AppFormFactor.mobile
                  ? MobilePrivateQueriesControl(
                      onRequest: () async => toggles++,
                    )
                  : EnhancePirPrivacyControl(
                      enabled: true,
                      onToggle: () => toggles++,
                      transition: null,
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WalletPirServerSettingsButton), findsOneWidget);
    expect(find.text('Valargroup Wallet PIR'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('wallet_pir_server_settings_button')),
    );
    await tester.pumpAndSettle();
    expect(
      toggles,
      0,
      reason: 'opening settings does not toggle private queries',
    );
    expect(find.text('Valargroup Wallet PIR'), findsOneWidget);
    expect(find.text('Valargroup Wallet PIR Secondary'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
    expect(find.text('42ms'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('wallet_pir_share_server')));
    await tester.pumpAndSettle();
    expect(h.openedRepositories, [
      Uri.parse('https://github.com/valargroup/wallet-pir-config'),
    ]);
    expect(h.state.selectedBaseUrl, primary);
    expect(find.text('Change server list'), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('wallet_pir_server_option_$secondary')),
    );
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(h.applied.last, secondary);
    expect(h.state.selectedBaseUrl, secondary);
    expect(_savedBase(h), secondary);
    expect(
      find.text('Choose a server'),
      findsNothing,
      reason: 'selection closes the popup',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    final restarted = h.restart();
    await tester.runAsync(restarted.start);
    expect(restarted.state.selectedBaseUrl, secondary);
    expect(restarted.applied.last, secondary);
    restarted.dispose();
  });

  testWidgets('the settings icon is disabled when private queries are off', (
    tester,
  ) async {
    final h = _Harness(privateQueriesOn: false);
    var toggles = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Scaffold(
              body: kAppFormFactor == AppFormFactor.mobile
                  ? MobilePrivateQueriesControl(
                      onRequest: () async => toggles++,
                    )
                  : EnhancePirPrivacyControl(
                      enabled: false,
                      onToggle: () => toggles++,
                      transition: null,
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(
      const ValueKey('wallet_pir_server_settings_button'),
    );
    expect(tester.widget<AppButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Choose a server'), findsNothing);
    expect(
      toggles,
      0,
      reason: 'the disabled icon does not turn private queries on',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  });

  testWidgets('a failed server change stays open and can be retried', (
    tester,
  ) async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    // Keep the provider and failing future in the widget test's error zone.
    final started = h.container.read(walletPirServerProvider.future);
    await tester.pump();
    await started;
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: const Scaffold(
              body: WalletPirServerSettingsButton(enabled: true),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('wallet_pir_server_settings_button')),
    );
    await tester.pumpAndSettle();
    final failing = h.applyGates[_b[1]] = Completer<void>();
    final second = find.byKey(ValueKey('wallet_pir_server_option_${_b[1]}'));
    await tester.tap(second);
    await tester.pump();
    failing.completeError(StateError('db busy'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text("Couldn't change server. Try again."), findsOneWidget);
    expect(find.text('Choose a server'), findsOneWidget);
    expect(h.state.selectedBaseUrl, _a[1]);

    await tester.tap(second);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(h.state.selectedBaseUrl, _b[1]);
    expect(find.text('Choose a server'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  });

  testWidgets(
    'the custom editor validates, cancels and saves without changing the source',
    (tester) async {
      final h = _Harness();
      h.fetcher.servers[_sourceA] = [_a, _b];
      await tester.runAsync(h.start);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: const Scaffold(
                body: WalletPirServerSettingsButton(enabled: true),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('wallet_pir_server_settings_button')),
      );
      await tester.pumpAndSettle();
      final customOption = find.byKey(
        const ValueKey('wallet_pir_custom_server_option'),
      );
      await tester.tap(customOption);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('wallet_pir_custom_server_save'));
      await tester.enterText(
        find.byType(EditableText),
        'http://custom.example',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(save).onPressed, isNull);
      expect(find.textContaining('Enter an HTTPS base URL'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.state.selectedBaseUrl, _a[1]);

      await tester.tap(customOption);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText),
        'https://custom.example/pir/',
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(h.state.source, _sourceA);
      expect(h.state.selectedBaseUrl, 'https://custom.example/pir');
      expect(
        h.store.cached['mainnet|$_sourceA']?.customBaseUrl,
        'https://custom.example/pir',
      );
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('wallet_pir_server_settings_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom server'), findsOneWidget);
      expect(find.text('custom.example/pir'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    },
  );

  test('first load picks the first server and keeps it', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.start();

    expect(h.state.selectedBaseUrl, 'https://a.example');
    expect(h.applied.last, 'https://a.example');
    expect(
      h.store.cached['mainnet|$_sourceA']!.selectionJson,
      contains('a.example'),
    );
  });

  test(
    'a custom choice survives refresh and restart until a listed server is chosen',
    () async {
      var h = _Harness();
      h.fetcher.servers[_sourceA] = [_a, _b];
      await h.start();
      await h.notifier.selectCustomServer('https://custom.example/pir/');
      expect(h.state.selectedBaseUrl, 'https://custom.example/pir');
      expect(h.state.customServer?.isValid, isTrue);
      expect(
        h.state.servers.map((server) => server.baseUrl),
        isNot(contains('https://custom.example/pir')),
      );

      h.fetcher.servers[_sourceA] = [_b];
      await h.notifier.refresh();
      expect(h.state.selectedBaseUrl, 'https://custom.example/pir');
      expect(h.state.needsSelection, isFalse);
      h = h.restart();
      await h.start();
      expect(h.applied.last, 'https://custom.example/pir');
      expect(h.state.selectedServer?.label, 'Custom server');

      await h.notifier.selectServer(_b[1]);
      expect(h.state.customServer, isNull);
      expect(h.store.cached['mainnet|$_sourceA']?.customBaseUrl, isNull);
      h = h.restart();
      await h.start();
      expect(h.applied.last, _b[1]);
      expect(h.state.customServer, isNull);
      h.dispose();
    },
  );

  test(
    'invalid custom input changes neither the server nor saved preference',
    () async {
      final h = _Harness();
      h.fetcher.servers[_sourceA] = [_a];
      await h.start();
      await expectLater(
        h.notifier.selectCustomServer('http://custom.example'),
        throwsA(isA<WalletPirConfigException>()),
      );
      expect(h.applied.last, _a[1]);
      expect(h.state.customServer, isNull);
      expect(h.store.cached['mainnet|$_sourceA']?.customBaseUrl, isNull);
      h.dispose();
    },
  );

  test(
    'an invalid saved custom server never falls back to a listed server',
    () async {
      final h = _Harness();
      h.fetcher.servers[_sourceA] = [_a];
      h.store.cached['mainnet|$_sourceA'] = const WalletPirCachedConfig(
        customBaseUrl: 'http://custom.example',
      );
      await h.start();
      expect(h.state.selectedBaseUrl, isNull);
      expect(h.state.needsSelection, isTrue);
      expect(h.applied.whereType<String>(), isEmpty);
      await h.notifier.selectServer(_a[1]);
      expect(h.state.customServer, isNull);
      expect(h.applied.last, _a[1]);
      h.dispose();
    },
  );

  test(
    'a custom server can be used while the published list is unavailable',
    () async {
      var h = _Harness();
      h.fetcher.failing.add(_sourceA);
      await h.start();
      await h.notifier.selectCustomServer('https://custom.example');
      h = h.restart();
      await h.start();
      expect(h.state.config, isNull);
      expect(h.applied.last, 'https://custom.example');
      expect(
        walletPirServerStatusText(h.state)?.text,
        contains('custom server is still selected'),
      );
      h.dispose();
    },
  );

  test(
    'a custom choice made during a refresh survives its completion',
    () async {
      final h = _Harness();
      h.fetcher.servers[_sourceA] = [_a, _b];
      await h.start();
      final gate = h.fetcher.gates[_sourceA] = Completer<void>();
      final refresh = h.notifier.refresh();
      await pumpEventQueue();
      await h.notifier.selectCustomServer('https://custom.example');
      gate.complete();
      await refresh;
      expect(h.applied.last, 'https://custom.example');
      expect(h.state.selectedBaseUrl, 'https://custom.example');
      h.dispose();
    },
  );

  test('an empty list selects nothing and sends no traffic', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [];
    await h.start();

    expect(h.state.hasNoServers, isTrue);
    expect(h.applied.whereType<String>(), isEmpty);
    expect(
      walletPirServerStatusText(h.state)!.text,
      contains('No servers are offered'),
    );
  });

  test('reorder and relabel keep the explicit choice', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.start();
    await h.notifier.selectServer('https://b.example');
    expect(h.applied.last, 'https://b.example');

    h.fetcher.servers[_sourceA] = [
      ['Renamed B', 'https://b.example'],
      _a,
    ];
    await h.notifier.refresh();
    expect(h.state.selectedBaseUrl, 'https://b.example');
    expect(h.state.selectedServer!.label, 'Renamed B');
  });

  test('a removed choice needs a new one, across restarts', () async {
    var h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.start();
    await h.notifier.selectServer('https://b.example');

    h.fetcher.servers[_sourceA] = [_a];
    await h.notifier.refresh();
    expect(h.state.needsSelection, isTrue);
    expect(h.applied.last, isNull, reason: 'never falls back to server A');

    h = h.restart();
    await h.start();
    expect(h.state.needsSelection, isTrue);
    expect(h.applied, isNot(contains('https://a.example')));

    await h.notifier.selectServer('https://a.example');
    expect(h.state.needsSelection, isFalse);
    expect(h.applied.last, 'https://a.example');
  });

  test('an outage keeps the last good list and says so', () async {
    var h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.start();

    h = h.restart();
    h.fetcher.failing.add(_sourceA);
    await h.start();
    expect(h.state.selectedBaseUrl, 'https://a.example');
    expect(h.state.refreshError, isNotNull);
    expect(h.applied, isNot(contains(null)));
    expect(
      walletPirServerStatusText(h.state)!.text,
      contains('Using the last list loaded'),
    );
  });

  test('an older refresh cannot replace a newer server list', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a];
    await h.start();

    final gate = h.fetcher.gates[_sourceA] = Completer<void>();
    final older = h.notifier.refresh();
    await pumpEventQueue();
    h.fetcher.gates.remove(_sourceA);
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.notifier.refresh();
    await h.notifier.selectServer('https://b.example');
    gate.complete();
    await older;

    expect(h.state.servers, hasLength(2));
    expect(h.state.selectedBaseUrl, 'https://b.example');
    expect(h.applied.last, 'https://b.example');
  });

  test('a delayed older apply cannot outlast a newer choice', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b, _c];
    await h.start();
    expect(h.applied.last, 'https://a.example');

    final slow = h.applyGates['https://b.example'] = Completer<void>();
    final older = h.notifier.selectServer('https://b.example');
    await pumpEventQueue();
    final newer = h.notifier.selectServer('https://c.example');
    await pumpEventQueue();
    slow.complete();
    await Future.wait([older, newer]);

    expect(h.applied.last, 'https://c.example');
    expect(h.state.selectedBaseUrl, 'https://c.example');
    expect(_savedBase(h), 'https://c.example');
    expect(h.maxApplying, 1, reason: 'applies never overlap');
  });

  test('a delayed older write cannot outlast a newer choice', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b, _c];
    await h.start();

    final slow = h.store.writeGates['https://b.example'] = Completer<void>();
    final older = h.notifier.selectServer('https://b.example');
    await pumpEventQueue();
    final newer = h.notifier.selectServer('https://c.example');
    await pumpEventQueue();
    slow.complete();
    await Future.wait([older, newer]);

    expect(_savedBase(h), 'https://c.example');
    expect(h.applied.last, 'https://c.example');
    expect(h.state.selectedBaseUrl, 'https://c.example');
  });

  test('a choice made during a refresh survives the refresh', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.start();

    final gate = h.fetcher.gates[_sourceA] = Completer<void>();
    final refreshing = h.notifier.refresh();
    await pumpEventQueue();
    await h.notifier.selectServer('https://b.example');
    gate.complete();
    await refreshing;

    expect(h.state.selectedBaseUrl, 'https://b.example');
    expect(h.applied.last, 'https://b.example');
    expect(_savedBase(h), 'https://b.example');
  });

  test('commits keep running after a failed apply', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    await h.start();

    final failing = h.applyGates['https://b.example'] = Completer<void>();
    final failed = expectLater(
      h.notifier.selectServer('https://b.example'),
      throwsStateError,
    );
    await pumpEventQueue();
    failing.completeError(StateError('db busy'));
    await failed;
    // The queue keeps going after a failure.
    await h.notifier.selectServer('https://b.example');
    expect(h.applied.last, 'https://b.example');
    expect(h.state.selectedBaseUrl, 'https://b.example');
  });

  test('another source cache cannot replace the fixed source', () async {
    final h = _Harness();
    h.fetcher.servers[_sourceA] = [_a, _b];
    h.store.cached['mainnet|$_sourceB'] = WalletPirCachedConfig(
      snapshotJson: jsonEncode({
        'source': _sourceB,
        'servers': [_c],
      }),
      selectionJson: jsonEncode({'scope': _sourceB, 'base': _c[1]}),
    );
    await h.start();
    await h.notifier.selectServer('https://b.example');

    final restarted = h.restart();
    await restarted.start();
    expect(restarted.state.source, _sourceA);
    expect(restarted.state.selectedBaseUrl, 'https://b.example');
    expect(restarted.applied, isNot(contains('https://c.example')));
  });

  test('with no source there is no server', () async {
    final h = _Harness(source: null);
    await h.start();
    expect(h.state.source, isNull);
    expect(h.applied, [null]);
    expect(walletPirServerStatusText(h.state)!.warning, isTrue);
  });

  test('the transport URL drops only the pin', () {
    expect(
      walletPirConfigTransportUri(
        'https://h.example/s.json?v=1&checksum=sha256:ab',
      ).toString(),
      'https://h.example/s.json?v=1',
    );
    expect(
      walletPirConfigTransportUri(_sourceA).toString(),
      'https://config.example/a/static.json',
    );
  });
}
