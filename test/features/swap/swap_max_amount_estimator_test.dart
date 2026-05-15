import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_max_amount_estimator.dart';

void main() {
  test(
    'findMaxZecAmountByFeeProbe returns the highest sendable amount',
    () async {
      final probes = <BigInt>[];

      final max = await findMaxZecAmountByFeeProbe(
        spendableZatoshi: BigInt.from(100),
        canSend: (amount) async {
          probes.add(amount);
          return amount <= BigInt.from(93);
        },
      );

      expect(max, BigInt.from(93));
      expect(probes, isNotEmpty);
    },
  );

  test(
    'findMaxZecAmountByFeeProbe returns zero without probing empty balance',
    () async {
      var probed = false;

      final max = await findMaxZecAmountByFeeProbe(
        spendableZatoshi: BigInt.zero,
        canSend: (_) async {
          probed = true;
          return true;
        },
      );

      expect(max, BigInt.zero);
      expect(probed, isFalse);
    },
  );
}
