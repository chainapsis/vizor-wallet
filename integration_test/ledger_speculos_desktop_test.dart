import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'drives Ledger import and signing surfaces through Speculos',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixture = _Fixture.load();
      final sandboxDirectory = await Directory.systemTemp.createTemp(
        'vizor-ledger-speculos-e2e.',
      );
      final dbPath = '${sandboxDirectory.path}/wallet.db';
      await File(
        dbPath,
      ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
      LedgerBirthdayArgs? birthdayArgs;
      final router = GoRouter(
        initialLocation: '/onboarding/ledger',
        routes: [
          GoRoute(
            path: '/onboarding/ledger',
            builder: (_, _) => const LedgerConnectScreen(),
          ),
          GoRoute(
            path: '/onboarding/ledger/birthday',
            builder: (_, state) {
              birthdayArgs = state.extra! as LedgerBirthdayArgs;
              return const Center(
                child: Text(
                  'Ledger account approved',
                  key: ValueKey('ledger_speculos_account_approved'),
                ),
              );
            },
          ),
          GoRoute(path: '/add-account', builder: (_, _) => const SizedBox()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('ledger_speculos_import_scope'),
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            syncProvider.overrideWith(_FakeSyncNotifier.new),
            ledgerTargetPlatformProvider.overrideWithValue(
              TargetPlatform.macOS,
            ),
            ledgerOperationCancellerProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect Ledger'), findsWidgets);
      expect(
        find.byKey(const ValueKey('ledger_connect_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pump();
      final connectSpinner = find.byKey(
        const ValueKey('ledger_connect_spinner'),
      );
      expect(connectSpinner, findsOneWidget);
      expect(
        tester.getCenter(connectSpinner).dx,
        greaterThan(
          tester
              .getCenter(find.byKey(const ValueKey('ledger_connect_button')))
              .dx,
        ),
      );
      final importApproval = _approveNextReview(fixture.ufvkApiUrl);
      await _pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ledger_speculos_account_approved')),
        ),
        description: 'Ledger account approval route',
        timeout: const Duration(minutes: 2),
      );
      expect(await importApproval, isTrue);

      final exported = birthdayArgs?.account;
      expect(exported, isNotNull);
      expect(exported!.ufvk, fixture.ufvk);
      expect(exported.seedFingerprint, fixture.seedFingerprint);
      expect(exported.accountIndex, fixture.accountIndex);
      expect(exported.appVersion, '3.9.2');

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('ledger_speculos_signing_scope'),
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: const Center(
                child: LedgerSigningModal(
                  phase: LedgerSigningModalPhase.awaitingDevice,
                  failure: null,
                  onCancel: null,
                  onFailureAction: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Review on your Ledger'), findsOneWidget);
      expect(find.text('Waiting for approval'), findsOneWidget);

      final pczt = fixture.pcztBytes;
      final signingApproval = _approveNextReview(fixture.signingApiUrl);
      Uint8List? signedPczt;
      Object? signingError;
      var signingFinished = false;
      unawaited(
        rust_ledger
            .ledgerSignPcztFull(
              dbPath: dbPath,
              accountUuid: fixture.accountUuid,
              pcztBytes: pczt,
              network: 'main',
            )
            .then(
              (value) => signedPczt = value,
              onError: (Object error, StackTrace _) => signingError = error,
            )
            .whenComplete(() => signingFinished = true),
      );
      await _pumpUntil(
        tester,
        () => signingFinished,
        description: 'Ledger signing completion',
        timeout: const Duration(minutes: 2),
      );
      expect(await signingApproval, isTrue);
      if (signingError case final error?) throw error;
      expect(signedPczt, isNotNull);
      expect(signedPczt, isNot(equals(pczt)));

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('ledger_speculos_saving_scope'),
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: const Center(
                child: LedgerSigningModal(
                  phase: LedgerSigningModalPhase.saving,
                  failure: null,
                  onCancel: null,
                  onFailureAction: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Saving signed transaction'), findsOneWidget);
      expect(find.text('Securing transaction'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _Fixture {
  const _Fixture({
    required this.ufvkApiUrl,
    required this.signingApiUrl,
    required this.ufvk,
    required this.seedFingerprint,
    required this.accountUuid,
    required this.accountIndex,
    required this.pcztBytes,
    required this.dbGzipBytes,
  });

  final String ufvkApiUrl;
  final String signingApiUrl;
  final String ufvk;
  final List<int> seedFingerprint;
  final String accountUuid;
  final int accountIndex;
  final List<int> pcztBytes;
  final List<int> dbGzipBytes;

  static _Fixture load() {
    const ufvk = String.fromEnvironment('VIZOR_LEDGER_E2E_UFVK');
    const seedFingerprint = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_SEED_FINGERPRINT',
    );
    const accountUuid = String.fromEnvironment('VIZOR_LEDGER_E2E_ACCOUNT_UUID');
    const pcztBase64 = String.fromEnvironment('VIZOR_LEDGER_E2E_PCZT_BASE64');
    const dbGzipBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_DB_GZIP_BASE64',
    );
    if (ufvk.isEmpty ||
        seedFingerprint.isEmpty ||
        accountUuid.isEmpty ||
        pcztBase64.isEmpty ||
        dbGzipBase64.isEmpty) {
      throw StateError(
        'Ledger fixture dart-defines are missing. Run the Speculos E2E script.',
      );
    }
    return _Fixture(
      ufvkApiUrl: _requiredEnvironment('VIZOR_LEDGER_SPECULOS_UFVK_API_URL'),
      signingApiUrl: _requiredEnvironment(
        'VIZOR_LEDGER_SPECULOS_SIGNING_API_URL',
      ),
      ufvk: ufvk,
      seedFingerprint: _decodeHex(seedFingerprint),
      accountUuid: accountUuid,
      accountIndex: 0,
      pcztBytes: base64Decode(pcztBase64),
      dbGzipBytes: base64Decode(dbGzipBase64),
    );
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name must be set for the Ledger Speculos E2E.');
  }
  return value;
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd) {
    throw StateError('Ledger fixture fingerprint has invalid hex.');
  }
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

Future<bool> _approveNextReview(String apiUrl) async {
  final client = HttpClient();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var reviewStarted = false;
  try {
    while (DateTime.now().isBefore(deadline)) {
      final screen = await _currentScreenText(client, apiUrl);
      final normalized = screen.toLowerCase();
      if (normalized.contains('review') ||
          normalized.contains('export') ||
          normalized.contains('viewing key')) {
        reviewStarted = true;
      }
      if (reviewStarted) {
        if (normalized.contains('approve') ||
            normalized.contains('accept') ||
            normalized.contains('confirm') ||
            normalized.contains('sign transaction')) {
          await _pressButton(client, apiUrl, 'both');
          return true;
        }
        await _pressButton(
          client,
          apiUrl,
          normalized.contains('cancel') ? 'left' : 'right',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('Speculos review did not become approvable.');
  } finally {
    client.close();
  }
}

Future<String> _currentScreenText(HttpClient client, String apiUrl) async {
  final request = await client.getUrl(
    Uri.parse('$apiUrl/events?currentscreenonly=true'),
  );
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Speculos events returned HTTP ${response.statusCode}.',
    );
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final events = decoded['events']! as List<dynamic>;
  return events
      .cast<Map<String, dynamic>>()
      .map((event) => event['text'])
      .whereType<String>()
      .join(' ');
}

Future<void> _pressButton(
  HttpClient client,
  String apiUrl,
  String button,
) async {
  final request = await client.postUrl(Uri.parse('$apiUrl/button/$button'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'action': 'press-and-release'}));
  final response = await request.close();
  await response.drain<void>();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Speculos button returned HTTP ${response.statusCode}.',
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Timed out waiting for $description.');
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(chainTipHeight: 4000000);
}
