import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart';

void main() {
  test('effective selected account defaults to the only scanned account', () {
    final account = _account(0);
    final state = KeystoneOnboardingState(accounts: [account]);

    expect(state.effectiveSelectedAccount, same(account));
  });

  test(
    'effective selected account stays null when multiple accounts exist',
    () {
      final state = KeystoneOnboardingState(
        accounts: [_account(0), _account(1)],
      );

      expect(state.effectiveSelectedAccount, isNull);
    },
  );

  test('effective selected account keeps the explicit selection', () {
    final first = _account(0);
    final second = _account(1);
    final state = KeystoneOnboardingState(
      accounts: [first, second],
      selectedAccount: second,
    );

    expect(state.effectiveSelectedAccount, same(second));
  });
}

KeystoneAccountInfo _account(int index) {
  return KeystoneAccountInfo(
    name: 'Account ${index + 1}',
    ufvk: 'uview$index',
    index: index,
    seedFingerprint: Uint8List.fromList([index]),
  );
}
