import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/providers/mobile_wallet_link_provider.dart';
import 'package:zcash_wallet/src/features/wallet_link/services/wallet_link_completion_crypto.dart';

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

void main() {
  test(
    'wallet link QR parses id and key without accepting endpoint authority',
    () {
      final key = _base64UrlNoPadding(List<int>.generate(32, (index) => index));
      final completionToken = _base64UrlNoPadding(
        List<int>.generate(32, (index) => 255 - index),
      );
      final payload = WalletLinkQrPayload.parse(
        'vizor://wallet-link/v1'
        '?id=550e8400-e29b-41d4-a716-446655440000'
        '&key=$key'
        '&completion=$completionToken'
        '&endpoint=https%3A%2F%2Fevil.example',
      );

      expect(payload.packageId, '550e8400-e29b-41d4-a716-446655440000');
      expect(payload.keyBytes, List<int>.generate(32, (index) => index));
      expect(payload.completionToken, completionToken);
    },
  );

  test(
    'wallet link completion summary round-trips with fixed ciphertext size',
    () async {
      final keyBytes = List<int>.generate(32, (index) => index);
      final first = await encryptWalletLinkImportSummary(
        summary: const WalletLinkImportSummary(
          importedAccountCount: 1,
          importedContactCount: 1,
        ),
        keyBytes: keyBytes,
      );
      final second = await encryptWalletLinkImportSummary(
        summary: const WalletLinkImportSummary(
          importedAccountCount: 22,
          importedContactCount: 333,
        ),
        keyBytes: keyBytes,
      );

      expect(first.ciphertext.length, 342);
      expect(second.ciphertext.length, first.ciphertext.length);

      final decoded = await decryptWalletLinkImportSummary(
        envelope: first,
        keyBytes: keyBytes,
      );
      expect(decoded.importedAccountCount, 1);
      expect(decoded.importedContactCount, 1);
    },
  );

  test(
    'wallet link display lifetime keeps the local QR timeout as the cap',
    () {
      expect(
        walletLinkDisplayLifetime(
          localLifetime: const Duration(minutes: 1),
          relayTtlSeconds: 15 * 60,
        ),
        const Duration(minutes: 1),
      );
    },
  );

  test('wallet link display lifetime does not outlive the relay ttl', () {
    expect(
      walletLinkDisplayLifetime(
        localLifetime: const Duration(minutes: 1),
        relayTtlSeconds: 30,
      ),
      const Duration(seconds: 30),
    );
    expect(
      walletLinkDisplayLifetime(
        localLifetime: const Duration(minutes: 1),
        relayTtlSeconds: 0,
      ),
      Duration.zero,
    );
  });

  test('wallet link transfer filters hardware accounts by kind', () {
    final payload = WalletLinkTransferPayload.fromJson({
      'version': 1,
      'exportedAt': '2026-07-07T00:00:00Z',
      'network': 'main',
      'activeAccountUuid': 'software',
      'contacts': [],
      'accounts': [
        {
          'uuid': 'software',
          'name': 'Software',
          'order': 0,
          'isHardware': false,
          'isSeedAnchor': true,
          'birthdayHeight': 100,
          'zip32AccountIndex': 0,
          'mnemonic': 'abandon abandon abandon abandon abandon abandon',
        },
        {
          'uuid': 'keystone',
          'name': 'Keystone',
          'order': 1,
          'isHardware': true,
          'isSeedAnchor': false,
          'hardwareKind': 'KEYSTONE',
          'birthdayHeight': 100,
          'zip32AccountIndex': 1,
          'ufvk': 'uview1keystone',
          'seedFingerprint': List<int>.filled(32, 7),
        },
        {
          'uuid': 'legacy-keystone',
          'name': 'Legacy Keystone',
          'order': 2,
          'isHardware': true,
          'isSeedAnchor': false,
          'birthdayHeight': 100,
          'zip32AccountIndex': 2,
          'ufvk': 'uview1legacy',
          'seedFingerprint': List<int>.filled(32, 8),
        },
        {
          'uuid': 'ledger',
          'name': 'Ledger',
          'order': 3,
          'isHardware': true,
          'isSeedAnchor': false,
          'hardwareKind': 'ledger',
          'birthdayHeight': 100,
          'zip32AccountIndex': 3,
          'ufvk': 'uview1ledger',
          'seedFingerprint': List<int>.filled(32, 9),
        },
      ],
    });

    expect(payload.accounts, hasLength(4));
    expect(payload.supportedAccounts.map((account) => account.uuid), [
      'software',
      'keystone',
      'legacy-keystone',
    ]);
    expect(payload.importableAccounts.map((account) => account.uuid), [
      'software',
      'keystone',
      'legacy-keystone',
    ]);

    final keystone = payload.accounts.singleWhere(
      (account) => account.uuid == 'keystone',
    );
    expect(keystone.hardwareKind, kWalletLinkHardwareKindKeystone);
    expect(keystone.effectiveHardwareKind, kWalletLinkHardwareKindKeystone);

    final legacyKeystone = payload.accounts.singleWhere(
      (account) => account.uuid == 'legacy-keystone',
    );
    expect(legacyKeystone.hardwareKind, isNull);
    expect(
      legacyKeystone.effectiveHardwareKind,
      kWalletLinkHardwareKindKeystone,
    );

    final ledger = payload.accounts.singleWhere(
      (account) => account.uuid == 'ledger',
    );
    expect(ledger.isSupportedByMobile, isFalse);
    expect(ledger.isImportable, isFalse);

    final state = MobileWalletLinkState(
      payload: payload,
      selectedAccountUuids: {
        for (final account in payload.accounts) account.uuid,
      },
    );
    expect(state.accounts.map((account) => account.uuid), [
      'software',
      'keystone',
      'legacy-keystone',
    ]);
    expect(state.importableAccountCount, 3);
    expect(state.selectedAccounts.map((account) => account.uuid), [
      'software',
      'keystone',
      'legacy-keystone',
    ]);

    final linkedImport = keystone.toAccountImport();
    expect(linkedImport.sourceAccountUuid, 'keystone');
  });

  test('mobile wallet link state excludes already imported accounts', () {
    const account1 = WalletLinkTransferAccount(
      uuid: 'desktop-account-1',
      name: 'Account 1',
      order: 0,
      isHardware: false,
      isSeedAnchor: true,
      hardwareKind: null,
      profilePictureId: null,
      birthdayHeight: 100,
      zip32AccountIndex: 0,
      ufvk: null,
      seedFingerprint: null,
      mnemonic: 'abandon abandon abandon abandon abandon abandon',
    );
    const account2 = WalletLinkTransferAccount(
      uuid: 'desktop-account-2',
      name: 'Account 2',
      order: 1,
      isHardware: false,
      isSeedAnchor: false,
      hardwareKind: null,
      profilePictureId: null,
      birthdayHeight: 100,
      zip32AccountIndex: 1,
      ufvk: null,
      seedFingerprint: null,
      mnemonic: 'abandon abandon abandon abandon abandon abandon',
    );
    final payload = WalletLinkTransferPayload(
      version: 1,
      exportedAt: DateTime.utc(2026, 7, 8),
      network: 'main',
      activeAccountUuid: account1.uuid,
      accounts: const [account1, account2],
      contacts: const [],
    );

    final state = MobileWalletLinkState(
      payload: payload,
      selectedAccountUuids: const {'desktop-account-1', 'desktop-account-2'},
      alreadyImportedAccountUuids: const {'desktop-account-1'},
    );

    expect(state.importableAccountCount, 1);
    expect(state.selectedAccounts.map((account) => account.uuid), [
      'desktop-account-2',
    ]);
    expect(state.sortedAccounts.map((account) => account.uuid), [
      'desktop-account-2',
      'desktop-account-1',
    ]);
  });
}
