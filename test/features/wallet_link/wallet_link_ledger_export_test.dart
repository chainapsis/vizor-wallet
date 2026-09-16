import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/providers/wallet_link_provider.dart';
import 'package:zcash_wallet/src/features/wallet_link/services/wallet_link_api_client.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _ExportRustApi()));
  tearDownAll(RustLib.dispose);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Ledger export keeps its signer kind so mobile rejects it', () async {
    final directory = Directory.systemTemp.createTempSync(
      'vizor-ledger-link-export',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null),
    );

    final relay = _CapturingRelay();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Accounts.new),
        addressBookProvider.overrideWith(_Contacts.new),
        walletLinkApiClientProvider.overrideWithValue(relay),
      ],
    );
    addTearDown(container.dispose);
    container.listen(walletLinkControllerProvider, (_, _) {});

    await container.read(walletLinkControllerProvider.notifier).start();

    final state = container.read(walletLinkControllerProvider);
    expect(state.phase, WalletLinkPhase.ready, reason: state.errorMessage);
    final qr = WalletLinkQrPayload.parse(state.qrPayload!);
    final envelope = relay.request!.envelope;
    final plaintext = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Url.decode(base64Url.normalize(envelope.ciphertext)),
        nonce: base64Url.decode(base64Url.normalize(envelope.nonce)),
        mac: Mac(base64Url.decode(base64Url.normalize(envelope.tag))),
      ),
      secretKey: SecretKey(qr.keyBytes),
    );
    final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    final transfer = WalletLinkTransferPayload.fromJson(json);
    final linked = transfer.accounts.single;

    expect(linked.hardwareKind, HardwareSignerKind.ledger.name);
    expect(linked.isSupportedByMobile, isFalse);
    expect(linked.isImportable, isFalse);
    expect(transfer.importableAccounts, isEmpty);
  });
}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'desktop-ledger',
        name: 'Ledger',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      ),
    ],
  );
}

class _Contacts extends AddressBookNotifier {
  @override
  Future<AddressBookState> build() async => const AddressBookState();
}

class _CapturingRelay implements WalletLinkApiClient {
  WalletLinkCreatePackageRequest? request;

  @override
  Future<WalletLinkCreatePackageResponse> createPackage(
    WalletLinkCreatePackageRequest input,
  ) async {
    request = input;
    return WalletLinkCreatePackageResponse(
      id: input.id,
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
      ttlSeconds: 60,
    );
  }

  @override
  Future<WalletLinkPackageStatus> getPackageStatus(String packageId) async =>
      WalletLinkPackageStatus(
        id: packageId,
        status: WalletLinkPackageCompletionStatus.pending,
        expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
      );

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExportRustApi implements RustLibApi {
  @override
  Future<BigInt> crateApiSyncGetExportBirthdayHeight({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => BigInt.from(3000000);

  @override
  Future<rust_wallet.AccountExportMetadata>
  crateApiWalletGetAccountExportMetadata({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => rust_wallet.AccountExportMetadata(
    zip32AccountIndex: 7,
    hardwareUfvk: 'uview1ledger',
    seedFingerprint: Uint8List.fromList(List.filled(32, 7)),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
