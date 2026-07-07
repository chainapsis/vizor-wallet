import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations_en.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_error_messages.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('shows wallet creation block height error without technical detail', () {
    const error = WalletCreationCurrentBlockHeightException('network down');

    expect(
      onboardingSubmitErrorMessage(error, l10n),
      kWalletCreationCurrentBlockHeightErrorMessage,
    );
  });

  test('strips default Exception prefix from onboarding submit errors', () {
    expect(onboardingSubmitErrorMessage(Exception('bad input'), l10n), 'bad input');
  });

  test('strips rust wrapper from duplicate Secret Passphrase import error', () {
    expect(
      onboardingSubmitErrorMessage(
        _FakeAnyhowException(kDuplicateSecretPassphraseImportErrorMessage),
        l10n,
      ),
      kDuplicateSecretPassphraseImportErrorMessage,
    );
  });

  test('strips flutter rust bridge anyhow wrapper from submit errors', () {
    expect(
      onboardingSubmitErrorMessage(
        _FakeAnyhowException(kDuplicateKeystoneAccountImportErrorMessage),
        l10n,
      ),
      kDuplicateKeystoneAccountImportErrorMessage,
    );
  });

  test('maps raw account collision errors to generic duplicate account copy', () {
    expect(
      onboardingSubmitErrorMessage(
        const _FakeAnyhowException(
          'Failed to import account: An account corresponding to the data '
          'provided already exists in the wallet with UUID 00000000-0000-0000-0000-000000000000.',
        ),
        l10n,
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
