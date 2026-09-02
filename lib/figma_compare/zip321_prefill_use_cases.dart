// ignore_for_file: depend_on_referenced_packages
// DEV-ONLY, UNCOMMITTED. Deterministic captures of what a user actually sees
// after opening a ZIP-321 `zcash:` payment link. Mirrors the provider/Rust
// fakes already used by test/features/send/send_screen_test.dart and the
// Widgetbook mobile send harness, so nothing here touches production storage,
// network, wallet, or Rust state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/send/models/send_prefill_args.dart';
import '../src/features/send/screens/mobile/mobile_send_screen.dart';
import '../src/features/send/screens/send_screen.dart';
import '../src/features/send/services/send_proving_key_warmup.dart';
import '../src/providers/account_models.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/rust/frb_generated.dart';

/// The exact payment link used for the OS-level runtime evidence.
const zip321UnifiedAddress =
    'u1l8xunezsvhq8fgzfl7404m450nwnd76zshscn6nfys7vyz2ywyh4cc5daaq0c7q2su5l'
    'qfh23sp7fkf3kt27ve5948mzpfutvdxs8yzc5r8c2t6p6al2ucw2t8xjzyt7j4mhv3hd0g'
    '4v3v99ggxzxnzk7v0k3ghpt8tqxa8ge87j9xmpva6wafxffgws5l6ts3plhjmnl4lsg3d3'
    'drl2vxs3ah8p99d0sg50s8kvg38w2wr9n6qe';

/// `memo=` decoded from the link, whitespace-preserving (`preserveMemoText`).
const zip321MemoText = '  Invoice #42\nThanks  ';

const _zip321Prefill = SendPrefillArgs(
  id: 'zip321-capture',
  source: 'zcash-uri',
  address: zip321UnifiedAddress,
  amountText: '0.5',
  memoText: zip321MemoText,
  preserveMemoText: true,
  label: 'Coffee shop',
  message: 'Thank you',
);

/// The same link without `memo=`, which is the only way the desktop compose
/// screen lands with the message card collapsed (`_applyPrefill` sets
/// `_messageExpanded = true` whenever the memo is non-empty).
const _zip321PrefillNoMemo = SendPrefillArgs(
  id: 'zip321-capture-no-memo',
  source: 'zcash-uri',
  address: zip321UnifiedAddress,
  amountText: '0.5',
  label: 'Coffee shop',
  message: 'Thank you',
);

// --- (a) desktop /send prefilled from a ZIP-321 link ------------------------

Widget buildZip321DesktopSendPrefillUseCase(BuildContext context) {
  return const _DesktopSendPrefillHarness(prefill: _zip321Prefill);
}

// --- (b) desktop /send, memo card collapsed (link carried no memo) ----------

Widget buildZip321DesktopSendPrefillNoMemoUseCase(BuildContext context) {
  return const _DesktopSendPrefillHarness(prefill: _zip321PrefillNoMemo);
}

// --- (c) mobile /send, route-step mode, jumped to the amount step -----------

Widget buildZip321MobileSendAmountStepUseCase(BuildContext context) {
  return const _MobileSendPrefillHarness();
}

// --- (d) mobile recipient step after the in-place fallback ------------------

Widget buildZip321MobileSendRecipientFallbackUseCase(BuildContext context) {
  return const _MobileSendPrefillHarness(addressValidates: false);
}

// --- harnesses --------------------------------------------------------------

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'capture-account',
      name: 'Account 1',
      order: 0,
      profilePictureId: 'pfp-01',
    ),
  ],
  activeAccountUuid: 'capture-account',
  activeAddress: 'u1activeaddress',
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _CaptureSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'capture-account',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000),
    totalBalance: BigInt.from(500000000),
    percentage: 1,
  );
}

class _CaptureAddressBookRepository implements AddressBookRepository {
  const _CaptureAddressBookRepository();

  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

Widget _captureScope({required Widget child}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap),
    sendWalletDbPathProvider.overrideWithValue(() async => '/tmp/capture.db'),
    sendProvingKeyWarmupProvider.overrideWithValue(() {}),
    ironwoodHomeMigrationCtaProvider.overrideWithValue(
      const AsyncValue.data(IronwoodHomeMigrationCtaState.hidden()),
    ),
    zecLiveUsdUnitPriceProvider.overrideWithValue(70),
    syncProvider.overrideWith(_CaptureSyncNotifier.new),
    addressBookRepositoryProvider.overrideWithValue(
      const _CaptureAddressBookRepository(),
    ),
  ],
  child: child,
);

/// Desktop `SendScreen` calls `rust_sync.validateAddress` directly (no
/// injection seam), so the capture installs the same FRB mock the desktop send
/// widget tests use.
class _DesktopSendPrefillHarness extends StatefulWidget {
  const _DesktopSendPrefillHarness({required this.prefill});

  final SendPrefillArgs prefill;

  @override
  State<_DesktopSendPrefillHarness> createState() =>
      _DesktopSendPrefillHarnessState();
}

class _DesktopSendPrefillHarnessState
    extends State<_DesktopSendPrefillHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _ensureRustMock();
    _router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/send',
          builder: (_, _) => SendScreen(prefill: widget.prefill),
        ),
        GoRoute(
          path: '/send/review',
          builder: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _captureScope(child: Router.withConfig(config: _router));
  }
}

class _MobileSendPrefillHarness extends StatelessWidget {
  const _MobileSendPrefillHarness({this.addressValidates = true});

  final bool addressValidates;

  @override
  Widget build(BuildContext context) {
    return _captureScope(
      child: SizedBox(
        width: 393,
        height: 852,
        child: MobileSendScreen(
          // Exactly what lib/src/core/navigation/mobile_routes.dart:152-159
          // hands MobileSendScreen for a SendPrefillArgs on /send.
          useRouteSteps: true,
          initialRecipient: _zip321Prefill.address,
          initialAmount: _zip321Prefill.amountText,
          initialMemo: _zip321Prefill.memoText,
          preserveInitialMemoWhitespace: _zip321Prefill.preserveMemoText,
          loadWalletDbPath: () async => '/tmp/capture.db',
          validateAddress: addressValidates
              ? _captureValidateAddress
              : _captureRejectAddress,
          estimateFee: _captureEstimateFee,
        ),
      ),
    );
  }
}

Future<rust_sync.AddressValidationResult> _captureValidateAddress({
  required String address,
}) async {
  return const rust_sync.AddressValidationResult(
    isValid: true,
    addressType: 'unified',
  );
}

Future<rust_sync.AddressValidationResult> _captureRejectAddress({
  required String address,
}) async {
  return const rust_sync.AddressValidationResult(
    isValid: false,
    addressType: '',
  );
}

Future<BigInt> _captureEstimateFee({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  required BigInt amountZatoshi,
  String? memo,
}) async {
  return BigInt.from(10000);
}

bool _rustMockInstalled = false;

void _ensureRustMock() {
  if (_rustMockInstalled) return;
  _rustMockInstalled = true;
  RustLib.initMock(api: _CaptureRustApi());
}

class _CaptureRustApi implements RustLibApi {
  @override
  Future<rust_sync.AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
    return const rust_sync.AddressValidationResult(
      isValid: true,
      addressType: 'unified',
    );
  }

  @override
  Future<BigInt> crateApiSyncEstimateFee({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    return BigInt.from(10000);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
