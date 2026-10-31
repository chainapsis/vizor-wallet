import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_funding_balance_provider.dart';

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
          balance,
          needs(900000000),
          payment: false,
        ),
        'Private swaps use Ironwood ZEC only. You have 8.2 ZEC there.',
      );
      expect(
        swapIronwoodOnlyShortfallMessage(
          balance,
          needs(900000000),
          payment: true,
        ),
        'Private payments use Ironwood ZEC only. You have 8.2 ZEC there.',
      );
    });

    test('leaves enough ZEC, and too little ZEC overall, to the button', () {
      expect(
        swapIronwoodOnlyShortfallMessage(
          balance,
          needs(500000000),
          payment: false,
        ),
        isNull,
      );
      expect(
        swapIronwoodOnlyShortfallMessage(
          balance,
          needs(1200000000),
          payment: false,
        ),
        isNull,
      );
    });

    test('masks the balance when asked', () {
      expect(
        swapIronwoodOnlyShortfallMessage(
          balance,
          needs(900000000),
          payment: false,
          maskAmount: (_) => '••• ZEC',
        ),
        'Private swaps use Ironwood ZEC only. You have ••• ZEC there.',
      );
    });
  });
}
