import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/private_transparent_recovery_config.dart';

void main() {
  test('private transparent recovery is opt-in by default', () {
    expect(kZcashPrivateTransparentRecovery, isFalse);
  });

  test('only a build with the flag describes transparent recovery', () {
    const base = 'Experimental. Looks up supported transactions.';
    expect(privateQueriesDescription(base), base);
    expect(
      privateQueriesDescription(base, privateTransparentRecovery: false),
      base,
    );
    final flagged = privateQueriesDescription(
      base,
      privateTransparentRecovery: true,
    );
    expect(flagged, startsWith(base));
    expect(
      flagged,
      contains(
        'Transparent funds stay unavailable until private recovery '
        'completes; Ledger transparent funds are not recovered privately.',
      ),
    );
  });
}
