import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_funding_balance_provider.dart';
import '../../support/test_l10n.dart';

void main() {
  group('swapIronwoodOnlyShortfallMessage', () {
    final balance = (
      spendable: BigInt.from(820000000),
      ordinary: BigInt.from(1000000000),
    );
    bool Function(BigInt) needs(int zatoshi) =>
        (available) => BigInt.from(zatoshi) >= available;

    test('explains a shortfall only Ironwood-only funding causes', () {
      expect(
        swapIronwoodOnlyShortfallMessage(
          testL10n,
          balance,
          needs(900000000),
          payment: false,
          privacyModeEnabled: false,
        ),
        'Private swaps use Ironwood ZEC only. You have 8.2 ZEC there.',
      );
      expect(
        swapIronwoodOnlyShortfallMessage(
          testL10n,
          balance,
          needs(900000000),
          payment: true,
          privacyModeEnabled: false,
        ),
        'Private payments use Ironwood ZEC only. You have 8.2 ZEC there.',
      );
    });

    test('leaves enough ZEC, and too little ZEC overall, to the button', () {
      expect(
        swapIronwoodOnlyShortfallMessage(
          testL10n,
          balance,
          needs(500000000),
          payment: false,
          privacyModeEnabled: false,
        ),
        isNull,
      );
      expect(
        swapIronwoodOnlyShortfallMessage(
          testL10n,
          balance,
          needs(1200000000),
          payment: false,
          privacyModeEnabled: false,
        ),
        isNull,
      );
    });

    test('masks the balance in privacy mode', () {
      expect(
        swapIronwoodOnlyShortfallMessage(
          testL10n,
          balance,
          needs(900000000),
          payment: false,
          privacyModeEnabled: true,
        ),
        'Private swaps use Ironwood ZEC only. You have ******\u00A0ZEC there.',
      );
    });
  });
}
