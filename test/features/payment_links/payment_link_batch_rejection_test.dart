import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';

/// The English Rust writes for each code (`validate_payment_link_batch_proposal`
/// in `rust/src/wallet/sync/send.rs`, pinned by its tests).
const _rustMessages = {
  ApiWalletErrorCode.paymentLinkBatchNotOneTransaction:
      'This group can’t be funded in one transaction. '
      'Try fewer cards or a smaller amount per card.',
  ApiWalletErrorCode.paymentLinkBatchKeystoneSapling:
      'This group would spend older Sapling funds, which your Keystone '
      'can’t sign. Try fewer cards or a smaller amount per card.',
  ApiWalletErrorCode.paymentLinkBatchKeystoneSignatureLimit:
      'This group needs more inputs than your Keystone can sign at once. '
      'Try fewer cards or a smaller amount per card.',
  ApiWalletErrorCode.paymentLinkBatchLedgerRecipientLimit:
      'This group has more shielded recipients than your Ledger can display '
      '(maximum 4). Try fewer cards or a smaller amount per card.',
  ApiWalletErrorCode.paymentLinkBatchLedgerSapling:
      'This group would spend older Sapling funds, which your Ledger can’t '
      'sign. Try fewer cards or a smaller amount per card.',
  ApiWalletErrorCode.paymentLinkBatchLedgerTooLarge:
      'This group is too large for your Ledger to sign. '
      'Try fewer cards or a smaller amount per card.',
};

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ko = lookupAppLocalizations(const Locale('ko'));
  final zh = lookupAppLocalizations(const Locale('zh'));

  test('English is the message Rust writes for each code', () {
    for (final MapEntry(key: code, value: message) in _rustMessages.entries) {
      final rejected = PaymentLinkBatchRejected.from(
        ApiWalletError(code: code, message: message),
      );
      expect(rejected, isNotNull, reason: code.name);
      expect(rejected!.text(en), message);
      expect(rejected.text(ko), isNot(message));
      expect(rejected.text(zh), isNot(message));
    }
  });

  test('other failures are not group rejections', () {
    expect(
      PaymentLinkBatchRejected.from(
        const ApiWalletError(
          code: ApiWalletErrorCode.other,
          message: 'This group can’t be funded in one transaction.',
        ),
      ),
      isNull,
    );
    expect(PaymentLinkBatchRejected.from('This group is too large'), isNull);
  });
}
