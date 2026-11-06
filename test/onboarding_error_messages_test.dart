import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_error_messages.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'support/test_l10n.dart';

void main() {
  test('preserves Ledger duplicate account copy from Rust', () {
    expect(
      onboardingSubmitErrorMessage(
        testL10n,
        const _FakeAnyhowException(
          'This Ledger account is already in your wallet.',
        ),
      ),
      'This Ledger account is already in your wallet.',
    );
  });
  test('shows wallet creation block height error without technical detail', () {
    const error = WalletCreationCurrentBlockHeightException('network down');

    expect(
      onboardingSubmitErrorMessage(testL10n, error),
      testL10n.onboardingBlockHeightRequired,
    );
  });

  test('puts other errors under a localized headline', () {
    expect(
      onboardingSubmitErrorMessage(testL10n, Exception('bad input')),
      testL10n.commonErrorWithDetails(
        testL10n.onboardingSubmitFailed,
        'bad input',
      ),
    );
    expect(
      onboardingSubmitErrorMessage(
        testL10n,
        const _FakeAnyhowException('database is locked'),
      ),
      testL10n.commonErrorWithDetails(
        testL10n.onboardingSubmitFailed,
        'database is locked',
      ),
    );
  });

  test('strips rust wrapper from duplicate Secret Passphrase import error', () {
    expect(
      onboardingSubmitErrorMessage(
        testL10n,
        _FakeAnyhowException(kDuplicateSecretPassphraseImportErrorMessage),
      ),
      kDuplicateSecretPassphraseImportErrorMessage,
    );
  });

  test('strips flutter rust bridge anyhow wrapper from submit errors', () {
    expect(
      onboardingSubmitErrorMessage(
        testL10n,
        _FakeAnyhowException(kDuplicateKeystoneAccountImportErrorMessage),
      ),
      kDuplicateKeystoneAccountImportErrorMessage,
    );
  });

  test('maps raw account collision errors to generic duplicate account copy', () {
    expect(
      onboardingSubmitErrorMessage(
        testL10n,
        const _FakeAnyhowException(
          'Failed to import account: An account corresponding to the data '
          'provided already exists in the wallet with UUID 00000000-0000-0000-0000-000000000000.',
        ),
      ),
      kDuplicateAccountImportErrorMessage,
    );
  });
}

class _FakeAnyhowException implements Exception {
  const _FakeAnyhowException(this.message);

  final String message;

  @override
  String toString() => 'AnyhowException($message)';
}
