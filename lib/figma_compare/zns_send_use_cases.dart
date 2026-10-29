// ignore_for_file: depend_on_referenced_packages
// Deterministic captures of the send flow with a Zcash name (ZNS) as the
// recipient. A fixed in-memory resolver stands in for the ZNS resolver, so
// nothing here touches the network, production storage, or Rust state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/naming/zns_name_resolver.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/address_book/screens/address_book_screen.dart';
import '../src/features/address_book/screens/mobile/mobile_address_book_screen.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/send/models/send_prefill_args.dart';
import '../src/features/send/screens/mobile/mobile_send_screen.dart';
import '../src/features/send/screens/send_screen.dart';
import '../src/features/send/services/send_proving_key_warmup.dart';
import '../src/features/send/widgets/send_recipient_resolver.dart';
import '../src/providers/account_models.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/rust/frb_generated.dart';

const _znsAddress =
    'u14lms6q2sg984hhng068lqesatnak86mlg297x0qkqsvkqgk2m7dyj5x2grlku3adg2tq6t'
    'rl5ue3vce7c3jnu5808kw9lsr890kfetrg524q4pgcn4zcnp84na85453pz67cjfy4sx7y6z'
    '6zc9t7666utasw5mehe9r2dwwcrgzp94ah';

Widget buildZnsDesktopSendResolvedUseCase(BuildContext context) =>
    const _DesktopZnsSendHarness(recipient: 'alice.zcash');

Widget buildZnsDesktopSendResolvingUseCase(BuildContext context) =>
    const _DesktopZnsSendHarness(
      recipient: 'alice.zcash',
      resolver: _PendingZnsResolver(),
    );

Widget buildZnsDesktopSendNotRegisteredUseCase(BuildContext context) =>
    const _DesktopZnsSendHarness(recipient: 'nobody.zcash');

Widget buildZnsMobileSendResolvedUseCase(BuildContext context) =>
    const _MobileZnsSendHarness(recipient: 'alice.zcash');

Widget buildZnsMobileSendNotRegisteredUseCase(BuildContext context) =>
    const _MobileZnsSendHarness(recipient: 'nobody.zcash');

Widget buildZnsMobileSendAmountUseCase(BuildContext context) =>
    const _MobileZnsSendHarness(recipient: _znsAddress, step: _Step.amount);

Widget buildZnsMobileSendReviewUseCase(BuildContext context) =>
    const _MobileZnsSendHarness(recipient: _znsAddress, step: _Step.review);

/// The contacts screen with no contacts. The ZNS contact capture test opens
/// its add form and types a name.
Widget buildZnsDesktopContactsUseCase(BuildContext context) =>
    const _ContactsHarness(mobile: false);

Widget buildZnsMobileContactsUseCase(BuildContext context) =>
    const _ContactsHarness(mobile: true);

enum _Step { recipient, amount, review }

/// Knows one name, `alice`, and nothing else.
class _CaptureZnsResolver implements ZnsNameResolver {
  const _CaptureZnsResolver();

  @override
  Future<ZnsResolution?> resolve(String name) async =>
      name == 'alice' ? ZnsResolution(name: name, address: _znsAddress) : null;
}

/// Never answers, which holds the field in its lookup state.
class _PendingZnsResolver implements ZnsNameResolver {
  const _PendingZnsResolver();

  @override
  Future<ZnsResolution?> resolve(String name) =>
      Completer<ZnsResolution?>().future;
}

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

Widget _captureScope({
  required Widget child,
  ZnsNameResolver resolver = const _CaptureZnsResolver(),
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap),
    sendWalletDbPathProvider.overrideWithValue(() async => '/tmp/capture.db'),
    sendProvingKeyWarmupProvider.overrideWithValue(() {}),
    ironwoodHomeMigrationCtaProvider.overrideWithValue(
      const AsyncValue.data(IronwoodHomeMigrationCtaState.hidden()),
    ),
    zecLiveUsdUnitPriceProvider.overrideWithValue(70),
    zecHomeUsdUnitPriceProvider.overrideWithValue(70),
    syncProvider.overrideWith(_CaptureSyncNotifier.new),
    addressBookRepositoryProvider.overrideWithValue(
      const _CaptureAddressBookRepository(),
    ),
    ownAccountAddressesProvider.overrideWith((ref) async => const {}),
    znsNameResolverProvider.overrideWithValue(resolver),
  ],
  child: child,
);

/// Desktop `SendScreen` validates through Rust directly, so the capture
/// installs an FRB mock that accepts every address as unified.
class _DesktopZnsSendHarness extends StatefulWidget {
  const _DesktopZnsSendHarness({
    required this.recipient,
    this.resolver = const _CaptureZnsResolver(),
  });

  final String recipient;
  final ZnsNameResolver resolver;

  @override
  State<_DesktopZnsSendHarness> createState() => _DesktopZnsSendHarnessState();
}

class _DesktopZnsSendHarnessState extends State<_DesktopZnsSendHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    if (!RustLib.instance.initialized) {
      RustLib.initMock(api: _CaptureRustApi());
    }
    final prefill = SendPrefillArgs(
      id: 'zns-capture-${widget.recipient}',
      source: 'capture',
      address: widget.recipient,
      amountText: '0.5',
    );
    _router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/send',
          builder: (_, _) => SendScreen(prefill: prefill),
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
    return _captureScope(
      resolver: widget.resolver,
      child: Router.withConfig(config: _router),
    );
  }
}

class _ContactsHarness extends StatefulWidget {
  const _ContactsHarness({required this.mobile});

  final bool mobile;

  @override
  State<_ContactsHarness> createState() => _ContactsHarnessState();
}

class _ContactsHarnessState extends State<_ContactsHarness> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/contacts',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/contacts',
        builder: (_, _) => widget.mobile
            ? const MobileAddressBookScreen()
            : const AddressBookScreen(),
      ),
    ],
  );

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

class _MobileZnsSendHarness extends StatelessWidget {
  const _MobileZnsSendHarness({
    required this.recipient,
    this.step = _Step.recipient,
  });

  final String recipient;
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final carriesName = step != _Step.recipient;
    return _captureScope(
      child: SizedBox(
        width: 393,
        height: 852,
        child: MobileSendScreen(
          initialRecipient: recipient,
          initialAddressType: carriesName ? 'unified' : null,
          initialZnsName: carriesName ? 'alice.zcash' : null,
          initialAmountStep: step == _Step.amount,
          initialReview: step == _Step.review,
          initialAmount: carriesName ? '0.5' : null,
          initialAmountReady: carriesName,
          initialFeeZatoshi: carriesName ? BigInt.from(10000) : null,
          loadWalletDbPath: () async => '/tmp/capture.db',
          validateAddress: _captureValidateAddress,
          estimateFee: _captureEstimateFee,
        ),
      ),
    );
  }
}

Future<rust_sync.AddressValidationResult> _captureValidateAddress({
  required String address,
  required String network,
}) async => const rust_sync.AddressValidationResult(
  isValid: true,
  addressType: 'unified',
  wrongNetwork: false,
);

Future<BigInt> _captureEstimateFee({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  required BigInt amountZatoshi,
  String? memo,
}) async => BigInt.from(10000);

class _CaptureRustApi implements RustLibApi {
  @override
  Future<rust_sync.AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) => _captureValidateAddress(address: address, network: network);

  @override
  Future<BigInt> crateApiSyncEstimateFee({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async => BigInt.from(10000);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
