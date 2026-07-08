import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../features/address_book/models/address_book_contact.dart';
import '../../../features/address_book/providers/address_book_provider.dart';
import '../../../providers/account_provider.dart';
import '../models/wallet_link_models.dart';
import '../services/wallet_link_api_client.dart';

final mobileWalletLinkControllerProvider =
    NotifierProvider.autoDispose<
      MobileWalletLinkController,
      MobileWalletLinkState
    >(MobileWalletLinkController.new);

enum MobileWalletLinkScanError { invalid, expired, failed }

class MobileWalletLinkState {
  const MobileWalletLinkState({
    this.payload,
    this.packageId,
    this.completionToken,
    this.keyBytes,
    this.selectedAccountUuids = const <String>{},
    this.selectedContactIds = const <String>{},
    this.alreadyImportedAccountUuids = const <String>{},
    this.alreadyImportedContactIds = const <String>{},
    this.scanError,
    this.loading = false,
    this.submitting = false,
    this.scanResetToken = 0,
  });

  const MobileWalletLinkState.initial() : this();

  final WalletLinkTransferPayload? payload;
  final String? packageId;
  final String? completionToken;
  final List<int>? keyBytes;
  final Set<String> selectedAccountUuids;
  final Set<String> selectedContactIds;
  final Set<String> alreadyImportedAccountUuids;
  final Set<String> alreadyImportedContactIds;
  final MobileWalletLinkScanError? scanError;
  final bool loading;
  final bool submitting;
  final int scanResetToken;

  List<WalletLinkTransferAccount> get accounts =>
      payload?.supportedAccounts ?? const [];
  List<AddressBookContact> get contacts => payload?.contacts ?? const [];
  List<WalletLinkTransferAccount> get sortedAccounts {
    final indexed = accounts.indexed.toList();
    indexed.sort((a, b) {
      final rank = _accountDisplayRank(
        a.$2,
      ).compareTo(_accountDisplayRank(b.$2));
      if (rank != 0) return rank;
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  List<AddressBookContact> get sortedContacts {
    final indexed = contacts.indexed.toList();
    indexed.sort((a, b) {
      final rank = _contactDisplayRank(
        a.$2,
      ).compareTo(_contactDisplayRank(b.$2));
      if (rank != 0) return rank;
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  List<WalletLinkTransferAccount> get selectedAccounts => [
    for (final account in accounts)
      if (selectedAccountUuids.contains(account.uuid) &&
          isAccountSelectable(account))
        account,
  ];

  List<AddressBookContact> get selectedContacts => [
    for (final contact in contacts)
      if (selectedContactIds.contains(contact.id) &&
          isContactSelectable(contact))
        contact,
  ];

  int get importableAccountCount => accounts.where(isAccountSelectable).length;
  int get importableContactCount => contacts.where(isContactSelectable).length;
  int get selectedAccountCount => selectedAccounts.length;
  int get selectedContactCount => selectedContacts.length;
  bool get hasPayload => payload != null;

  bool isAccountAlreadyImported(String uuid) {
    return alreadyImportedAccountUuids.contains(uuid);
  }

  bool isAccountSelectable(WalletLinkTransferAccount account) {
    return account.isImportable && !isAccountAlreadyImported(account.uuid);
  }

  bool isContactAlreadyImported(String id) {
    return alreadyImportedContactIds.contains(id);
  }

  bool isContactSelectable(AddressBookContact contact) {
    return !isContactAlreadyImported(contact.id);
  }

  int _accountDisplayRank(WalletLinkTransferAccount account) {
    if (isAccountAlreadyImported(account.uuid)) return 2;
    if (!account.isImportable) return 1;
    return 0;
  }

  int _contactDisplayRank(AddressBookContact contact) {
    return isContactAlreadyImported(contact.id) ? 1 : 0;
  }

  MobileWalletLinkState copyWith({
    WalletLinkTransferPayload? payload,
    bool clearPayload = false,
    String? packageId,
    bool clearPackageId = false,
    String? completionToken,
    bool clearCompletionToken = false,
    List<int>? keyBytes,
    bool clearKeyBytes = false,
    Set<String>? selectedAccountUuids,
    Set<String>? selectedContactIds,
    Set<String>? alreadyImportedAccountUuids,
    Set<String>? alreadyImportedContactIds,
    MobileWalletLinkScanError? scanError,
    bool clearScanError = false,
    bool? loading,
    bool? submitting,
    int? scanResetToken,
  }) {
    return MobileWalletLinkState(
      payload: clearPayload ? null : payload ?? this.payload,
      packageId: clearPackageId ? null : packageId ?? this.packageId,
      completionToken: clearCompletionToken
          ? null
          : completionToken ?? this.completionToken,
      keyBytes: clearKeyBytes ? null : keyBytes ?? this.keyBytes,
      selectedAccountUuids: selectedAccountUuids ?? this.selectedAccountUuids,
      selectedContactIds: selectedContactIds ?? this.selectedContactIds,
      alreadyImportedAccountUuids:
          alreadyImportedAccountUuids ?? this.alreadyImportedAccountUuids,
      alreadyImportedContactIds:
          alreadyImportedContactIds ?? this.alreadyImportedContactIds,
      scanError: clearScanError ? null : scanError ?? this.scanError,
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      scanResetToken: scanResetToken ?? this.scanResetToken,
    );
  }
}

class MobileWalletLinkController extends Notifier<MobileWalletLinkState> {
  @override
  MobileWalletLinkState build() => const MobileWalletLinkState.initial();

  Future<bool> handleQrCode(String raw) async {
    if (state.loading) return false;
    state = state.copyWith(loading: true, clearScanError: true);

    try {
      final qr = WalletLinkQrPayload.parse(raw);
      final client = WalletLinkApiClient();
      try {
        final package = await client.getPackage(qr.packageId);
        if (package.version != 1) {
          throw const FormatException('Unsupported wallet link package.');
        }
        if (package.expiresAt <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000) {
          throw const WalletLinkExpiredException();
        }

        final payload = await _decryptPayload(
          package.envelope,
          keyBytes: qr.keyBytes,
        );
        final alreadyImportedAccounts = await _alreadyImportedAccountUuids(
          payload,
        );
        final alreadyImportedContacts = await _alreadyImportedContactIds(
          payload,
        );
        final selectedAccounts = {
          for (final account in payload.importableAccounts)
            if (!alreadyImportedAccounts.contains(account.uuid)) account.uuid,
        };
        final selectedContacts = {
          for (final contact in payload.contacts)
            if (!alreadyImportedContacts.contains(contact.id)) contact.id,
        };
        state = MobileWalletLinkState(
          payload: payload,
          packageId: qr.packageId,
          completionToken: qr.completionToken,
          keyBytes: Uint8List.fromList(qr.keyBytes),
          selectedAccountUuids: selectedAccounts,
          selectedContactIds: selectedContacts,
          alreadyImportedAccountUuids: alreadyImportedAccounts,
          alreadyImportedContactIds: alreadyImportedContacts,
          scanResetToken: state.scanResetToken,
        );
        return true;
      } finally {
        client.close(force: true);
      }
    } on WalletLinkApiException catch (error) {
      log('MobileWalletLink.handleQrCode: API error: $error');
      final scanError = error.statusCode == 410
          ? MobileWalletLinkScanError.expired
          : MobileWalletLinkScanError.failed;
      _markScanFailed(scanError);
      return false;
    } on WalletLinkExpiredException {
      _markScanFailed(MobileWalletLinkScanError.expired);
      return false;
    } on FormatException catch (error, stackTrace) {
      log(
        'MobileWalletLink.handleQrCode: invalid payload: $error\n$stackTrace',
      );
      _markScanFailed(MobileWalletLinkScanError.invalid);
      return false;
    } catch (error, stackTrace) {
      log('MobileWalletLink.handleQrCode: ERROR: $error\n$stackTrace');
      _markScanFailed(MobileWalletLinkScanError.failed);
      return false;
    }
  }

  void clearScanError() {
    state = state.copyWith(
      clearScanError: true,
      loading: false,
      scanResetToken: state.scanResetToken + 1,
    );
  }

  void reset() {
    state = MobileWalletLinkState(scanResetToken: state.scanResetToken + 1);
  }

  void beginSubmit() {
    if (state.submitting) return;
    state = state.copyWith(submitting: true);
  }

  void endSubmit() {
    if (!state.submitting) return;
    state = state.copyWith(submitting: false);
  }

  void toggleAccount(String uuid) {
    final account = state.accounts
        .where((item) => item.uuid == uuid)
        .firstOrNull;
    if (account == null || !state.isAccountSelectable(account)) return;

    final selected = {...state.selectedAccountUuids};
    if (!selected.remove(uuid)) {
      selected.add(uuid);
    }
    state = state.copyWith(selectedAccountUuids: selected);
  }

  void selectAllImportableAccounts() {
    state = state.copyWith(
      selectedAccountUuids: {
        for (final account in state.accounts)
          if (state.isAccountSelectable(account)) account.uuid,
      },
    );
  }

  void deselectAllAccounts() {
    state = state.copyWith(selectedAccountUuids: const <String>{});
  }

  void toggleContact(String id) {
    final contact = state.contacts.where((item) => item.id == id).firstOrNull;
    if (contact == null || !state.isContactSelectable(contact)) return;

    final selected = {...state.selectedContactIds};
    if (!selected.remove(id)) {
      selected.add(id);
    }
    state = state.copyWith(selectedContactIds: selected);
  }

  void selectAllContacts() {
    state = state.copyWith(
      selectedContactIds: {
        for (final contact in state.contacts)
          if (state.isContactSelectable(contact)) contact.id,
      },
    );
  }

  void deselectAllContacts() {
    state = state.copyWith(selectedContactIds: const <String>{});
  }

  void _markScanFailed(MobileWalletLinkScanError error) {
    state = state.copyWith(
      scanError: error,
      loading: false,
      scanResetToken: state.scanResetToken + 1,
    );
  }

  Future<WalletLinkTransferPayload> _decryptPayload(
    WalletLinkEnvelope envelope, {
    required List<int> keyBytes,
  }) async {
    if (envelope.algorithm != 'aes-256-gcm') {
      throw const FormatException('Unsupported wallet link encryption.');
    }
    final algorithm = AesGcm.with256bits();
    final clearText = await algorithm.decrypt(
      SecretBox(
        _base64UrlNoPaddingDecode(envelope.ciphertext),
        nonce: _base64UrlNoPaddingDecode(envelope.nonce),
        mac: Mac(_base64UrlNoPaddingDecode(envelope.tag)),
      ),
      secretKey: SecretKey(keyBytes),
    );
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Wallet link payload must be an object.');
    }
    final payload = WalletLinkTransferPayload.fromJson(decoded);
    if (payload.version != 1 ||
        payload.network.isEmpty ||
        payload.accounts.isEmpty) {
      throw const FormatException('Wallet link payload is invalid.');
    }
    return payload;
  }

  Future<Set<String>> _alreadyImportedAccountUuids(
    WalletLinkTransferPayload payload,
  ) async {
    final accountsToCheck = <LinkedWalletAccountImport>[];
    for (final account in payload.importableAccounts) {
      try {
        accountsToCheck.add(account.toAccountImport());
      } catch (error, stackTrace) {
        log(
          'MobileWalletLink.handleQrCode: account preflight skipped '
          '"${account.displayName}": $error\n$stackTrace',
        );
      }
    }
    try {
      return await ref
          .read(accountProvider.notifier)
          .alreadyImportedWalletLinkSourceAccountUuids(
            network: payload.network,
            accountsToCheck: accountsToCheck,
          );
    } catch (error, stackTrace) {
      log(
        'MobileWalletLink.handleQrCode: account preflight failed: '
        '$error\n$stackTrace',
      );
      return const <String>{};
    }
  }

  Future<Set<String>> _alreadyImportedContactIds(
    WalletLinkTransferPayload payload,
  ) async {
    try {
      return await ref
          .read(addressBookProvider.notifier)
          .alreadyImportedContactIds(payload.contacts);
    } catch (error, stackTrace) {
      log(
        'MobileWalletLink.handleQrCode: contact preflight failed: '
        '$error\n$stackTrace',
      );
      return const <String>{};
    }
  }
}

class WalletLinkExpiredException implements Exception {
  const WalletLinkExpiredException();
}

List<int> _base64UrlNoPaddingDecode(String value) {
  return base64Url.decode(base64Url.normalize(value));
}
