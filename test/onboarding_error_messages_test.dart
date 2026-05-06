import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_error_messages.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  test('shows wallet creation block height error without technical detail', () {
    const error = WalletCreationCurrentBlockHeightException('network down');

    expect(
      onboardingSubmitErrorMessage(error),
      kWalletCreationCurrentBlockHeightErrorMessage,
    );
  });

  test('strips default Exception prefix from onboarding submit errors', () {
    expect(onboardingSubmitErrorMessage(Exception('bad input')), 'bad input');
  });
}
