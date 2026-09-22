import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_layout.dart';

import '../fixtures/orchard_receive_address.dart';

// Orchard-only mainnet Unified Address from the repository's independent
// BIP39 derivation vector.
const _reservedOrchardAddress =
    'u16yrmgarlnpx3ktaxq4l8mmc8wwnw3nmml02nujwghr2enf3jggmfjqax44yqts3csnxrtq8pyshk9ryew2zlrp3x5lyc64usqsnwnu0v';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _ReceiveAddressApi();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;

  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.requests.clear();
    api.unifiedAddressLookups = 0;
    api.failRenewal = false;
    FlutterSecureStorage.setMockInitialValues({
      kWalletDbNameKey: 'receive-test.db',
    });
    support = Directory.systemTemp.createTempSync('vizor-receive-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return support.path;
          }
          throw MissingPluginException('Unexpected path provider call.');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    support.deleteSync(recursive: true);
  });

  test(
    'own-account lookup labels exact legacy aliases and rejects other addresses',
    () async {
      final container = _container(null);
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      final ownAccounts = await container.read(
        ownAccountAddressesProvider.future,
      );
      for (final address in [orchardReceiveAddress, 'legacy-sapling-orchard']) {
        final recipient = sendReviewRecipientFor(
          contacts: const [],
          address: address,
          ownAccounts: ownAccounts,
        );
        expect(recipient, isA<SendReviewContactRecipient>());
        expect(
          (recipient as SendReviewContactRecipient).name,
          ownAccounts[address]!.name,
        );
        expect(
          paymentRequestRecipientIdentityFor(
            contacts: const [],
            address: address,
            ownAccounts: ownAccounts,
          )?.isOwnAccount,
          isTrue,
        );
      }
      expect(
        sendReviewRecipientFor(
          contacts: const [],
          address: 'unrecognized-ua',
          ownAccounts: ownAccounts,
        ),
        isA<SendReviewAddressRecipient>(),
      );
    },
  );

  for (final signer in [null, ...HardwareSignerKind.values]) {
    test(
      '${signer?.name ?? "software"} renewal updates receive state while reservation stays separate',
      () async {
        final container = _container(signer);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        final service = container.read(receiveAddressServiceProvider);

        final renewed = await service.renewShieldedAddress(
          accountUuid: 'account-1',
        );
        expect(renewed, orchardReceiveAddress);
        expect(api.requests, [('account-1', 'shielded')]);
        expect(container.read(accountProvider).value!.activeAddress, renewed);

        final reserved = await service.reserveOrchardAddress(
          accountUuid: 'account-1',
        );
        expect(reserved, _reservedOrchardAddress);
        expect(api.requests.last, ('account-1', 'orchard'));
        expect(container.read(accountProvider).value!.activeAddress, renewed);
      },
    );
  }

  test(
    'failed current-address renewal preserves the displayed address',
    () async {
      final container = _container(null);
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      api.failRenewal = true;

      await expectLater(
        container
            .read(receiveAddressServiceProvider)
            .renewShieldedAddress(accountUuid: 'account-1'),
        throwsStateError,
      );
      expect(container.read(accountProvider).value!.activeAddress, 'u1initial');
    },
  );

  test('cached Orchard-only receive address bypasses a Rust lookup', () async {
    final container = _container(null);
    addTearDown(container.dispose);
    final service = container.read(receiveAddressServiceProvider);

    final loaded = await service.loadShieldedAddress(
      accountUuid: 'account-1',
      currentShieldedAddress: orchardReceiveAddress,
    );

    expect(loaded, orchardReceiveAddress);
    expect(api.unifiedAddressLookups, 0);
  });
}

ProviderContainer _container(HardwareSignerKind? signer) => ProviderContainer(
  overrides: [
    appBootstrapProvider.overrideWithValue(
      AppBootstrapState(
        initialLocation: '/home',
        initialAccountState: AccountState(
          accounts: [
            AccountInfo(
              uuid: 'account-1',
              name: 'Primary',
              order: 0,
              isHardware: signer != null,
              hardwareSignerKind: signer,
            ),
          ],
          activeAccountUuid: 'account-1',
          activeAddress: 'u1initial',
        ),
        initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('account-1'),
        network: 'main',
        rpcEndpointConfig: defaultRpcEndpointConfig('main'),
        themeMode: ThemeMode.system,
        privacyModeEnabled: false,
        isPasswordConfigured: true,
        isUnlocked: true,
        passwordRotationRecoveryFailed: false,
      ),
    ),
  ],
);

class _ReceiveAddressApi implements RustLibApi {
  final requests = <(String, String)>[];
  bool failRenewal = false;
  int unifiedAddressLookups = 0;

  @override
  Future<List<String>> crateApiWalletGetReceiveAddressAliases({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => [orchardReceiveAddress, 'legacy-sapling-orchard'];

  @override
  Future<List<String>> crateApiWalletGetRecentTransparentReceiveAddresses({
    required String dbPath,
    required String network,
    String? accountUuid,
    int? limit,
  }) async => [];

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    unifiedAddressLookups++;
    return orchardReceiveAddress;
  }

  @override
  Future<String> crateApiSyncGetNextAvailableAddress({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String addressRequest,
  }) async {
    requests.add((accountUuid, addressRequest));
    if (addressRequest == 'shielded') {
      if (failRenewal) throw StateError('Could not commit receive address');
      return orchardReceiveAddress;
    }
    if (failRenewal) throw StateError('Could not commit receive address');
    return requests.length == 1
        ? orchardReceiveAddress
        : _reservedOrchardAddress;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
