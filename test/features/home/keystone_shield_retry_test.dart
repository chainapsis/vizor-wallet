// Fakes the path provider platform, as other storage tests do.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/zcash/network_upgrade_hold.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/features/home/widgets/keystone_shield_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_sync_notifier.dart';

/// A Keystone shield refused only because private recovery has not yet
/// covered the wallet's latest block keeps the user's signature: the overlay
/// offers to send the same signed transaction again instead of asking the
/// user to sign on the device once more.
void main() {
  final api = _ShieldApi();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);

  late Directory support;
  late PathProviderPlatform paths;
  setUp(() async {
    api.reset();
    FlutterSecureStorage.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp('keystone-shield-retry-');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await support.delete(recursive: true);
  });

  test('only the Rust retry code is retryable', () {
    expect(isHardwareBroadcastRetryable(_retryable), isTrue);
    // The message alone decides nothing, whatever it says.
    expect(
      isHardwareBroadcastRetryable(
        'hardware_recovery_retryable: Transparent broadcast authority '
        'unavailable',
      ),
      isFalse,
    );
    expect(
      isHardwareBroadcastRetryable(
        const ApiWalletError(
          code: ApiWalletErrorCode.authorityRefused,
          message: _refusal,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('a refusal while private recovery catches up sends the same '
      'signature again', (tester) async {
    api.refusals = [_retryable];
    var completed = 0;
    await tester.pumpWidget(_app(onComplete: () => completed++));
    await _getSignature(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(KeystoneShieldSigningOverlay)),
    );
    expect(container.read(pendingActivityEvidenceProvider).observedAt, isEmpty);

    expect(api.broadcasts, [_signature]);
    expect(find.text(kShieldWaitingForPrivateRecoveryMessage), findsOneWidget);
    final retry = find.text('Try again');
    expect(retry, findsOneWidget);
    expect(completed, 0);

    await tester.tap(retry);
    await _settle(tester);

    // Sent again with the kept signature, without another scan.
    expect(api.broadcasts, [_signature, _signature]);
    expect(api.scans, 1);
    expect(completed, 1);
    expect(
      container.read(pendingActivityEvidenceProvider).observedAt.keys,
      contains(('account-1', 'ab')),
    );
  });

  testWidgets('an upgrade hold before signing shows the upgrade copy', (
    tester,
  ) async {
    api.createError = StateError(
      "Transactions can't be sent this close to the network upgrade. "
      'Try again after it activates.',
    );
    await tester.pumpWidget(_app(onComplete: () {}));
    await _settle(tester);

    expect(find.text(kNetworkUpgradeHoldMessage), findsOneWidget);
    expect(find.text('Shield balance failed. Please try again.'), findsNothing);
    expect(find.text('Get Signature'), findsNothing);
    expect(api.broadcasts, isEmpty);
  });

  testWidgets('a final refusal offers no retry', (tester) async {
    api.refusals = [
      const ApiWalletError(
        code: ApiWalletErrorCode.authorityRefused,
        message: _refusal,
      ),
    ];
    await tester.pumpWidget(_app(onComplete: () {}));
    await _getSignature(tester);

    expect(api.broadcasts, [_signature]);
    expect(find.text('Try again'), findsNothing);
    expect(find.text(kShieldWaitingForPrivateRecoveryMessage), findsNothing);
    expect(find.text('Back to Wallet'), findsOneWidget);
  });
}

const _refusal = 'Transparent broadcast authority unavailable';
const _retryable = ApiWalletError(
  code: ApiWalletErrorCode.retryAfterRecovery,
  message: _refusal,
);
final _signature = [9, 8, 7];

Future<void> _settle(WidgetTester tester) async {
  // The signing QR animates, so the tree never settles. Real file and
  // secure-storage work completes only outside the fake clock, so alternate
  // real waits with frames until the mocked calls have run.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _getSignature(WidgetTester tester) async {
  await _settle(tester);
  final getSignature = find.text('Get Signature');
  expect(getSignature, findsOneWidget);
  await tester.tap(getSignature);
  await _settle(tester);
}

Widget _app({required VoidCallback onComplete}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: KeystoneShieldSigningOverlay(
            onCancel: () {},
            onComplete: onComplete,
          ),
        ),
      ),
      GoRoute(
        path: '/send/keystone/scan',
        builder: (context, _) => const _SignedScan(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
    child: AppTheme(
      data: AppThemeData.dark,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

/// Stands in for the scanner: returns the device's signature at once.
class _SignedScan extends StatefulWidget {
  const _SignedScan();

  @override
  State<_SignedScan> createState() => _SignedScanState();
}

class _SignedScanState extends State<_SignedScan> {
  @override
  void initState() {
    super.initState();
    _ShieldApi.current?.scans++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop(_signature);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ShieldApi extends RustLibApi {
  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {}

  _ShieldApi() {
    current = this;
  }

  static _ShieldApi? current;

  final broadcasts = <List<int>>[];
  List<ApiWalletError> refusals = [];
  Object? createError;
  int scans = 0;

  void reset() {
    broadcasts.clear();
    refusals = [];
    createError = null;
    scans = 0;
  }

  @override
  Future<ShieldTransparentPcztResult> crateApiSyncCreateShieldTransparentPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String sendFlowId,
  }) async {
    if (createError case final error?) throw error;
    return ShieldTransparentPcztResult(
      proposalId: BigInt.from(77),
      pcztBytes: Uint8List.fromList([1]),
      feeZatoshi: BigInt.from(10000),
      shieldedZatoshi: BigInt.from(90000),
      needsSaplingParams: false,
    );
  }

  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => Uint8List.fromList([2]);

  @override
  Future<Uint8List> crateApiSyncRedactPcztForSigner({
    required List<int> pcztBytes,
  }) async => Uint8List.fromList([3]);

  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async => [
    'ur:zcash-pczt/oyadhdcxlkahssqzwfvslofzoxwkrewngotktbmwjkwdcmnefsaaehrlolkskncnktlbaypkvoonhknt',
  ];

  @override
  Future<StoreAndBroadcastPcztsResult>
  crateApiSyncStoreAndBroadcastSignedPcztsForProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required List<Uint8List> pcztWithProofs,
    required List<Uint8List> pcztWithSignatures,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(List.of(pcztWithSignatures.single));
    if (refusals.isNotEmpty) throw refusals.removeAt(0);
    return const StoreAndBroadcastPcztsResult(
      broadcastedCount: 1,
      totalCount: 1,
      txids: 'ab',
      status: 'broadcasted',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1shieldretry',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
