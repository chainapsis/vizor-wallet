import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../features/address_book/models/address_book_contact.dart';
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
  final MobileWalletLinkScanError? scanError;
  final bool loading;
  final bool submitting;
  final int scanResetToken;

  List<WalletLinkTransferAccount> get accounts =>
      payload?.supportedAccounts ?? const [];
  List<AddressBookContact> get contacts => payload?.contacts ?? const [];

  List<WalletLinkTransferAccount> get selectedAccounts => [
    for (final account in accounts)
      if (selectedAccountUuids.contains(account.uuid) && account.isImportable)
        account,
  ];

  List<AddressBookContact> get selectedContacts => [
    for (final contact in contacts)
      if (selectedContactIds.contains(contact.id)) contact,
  ];

  int get importableAccountCount =>
      accounts.where((account) => account.isImportable).length;
  int get selectedAccountCount => selectedAccounts.length;
  int get selectedContactCount => selectedContacts.length;
  bool get hasPayload => payload != null;

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
        final selectedAccounts = {
          for (final account in payload.importableAccounts) account.uuid,
        };
        final selectedContacts = {
          for (final contact in payload.contacts) contact.id,
        };
        state = MobileWalletLinkState(
          payload: payload,
          packageId: qr.packageId,
          completionToken: qr.completionToken,
          keyBytes: Uint8List.fromList(qr.keyBytes),
          selectedAccountUuids: selectedAccounts,
          selectedContactIds: selectedContacts,
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
    if (account == null || !account.isImportable) return;

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
          if (account.isImportable) account.uuid,
      },
    );
  }

  void deselectAllAccounts() {
    state = state.copyWith(selectedAccountUuids: const <String>{});
  }

  void toggleContact(String id) {
    final selected = {...state.selectedContactIds};
    if (!selected.remove(id)) {
      selected.add(id);
    }
    state = state.copyWith(selectedContactIds: selected);
  }

  void selectAllContacts() {
    state = state.copyWith(
      selectedContactIds: {for (final contact in state.contacts) contact.id},
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
}

class WalletLinkExpiredException implements Exception {
  const WalletLinkExpiredException();
}

List<int> _base64UrlNoPaddingDecode(String value) {
  return base64Url.decode(base64Url.normalize(value));
}
