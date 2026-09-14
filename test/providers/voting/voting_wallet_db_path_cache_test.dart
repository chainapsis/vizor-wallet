import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

void main() {
  test('resolves once and reuses the cached path', () async {
    var calls = 0;
    final cache = VotingWalletDbPathCache(
      resolver: () async {
        calls++;
        return '/wallet/zcash_wallet.db';
      },
    );

    expect(await cache.resolve(), '/wallet/zcash_wallet.db');
    expect(await cache.resolve(), '/wallet/zcash_wallet.db');
    expect(calls, 1);
  });

  test('concurrent resolves share one in-flight lookup', () async {
    var calls = 0;
    final gate = Completer<String>();
    final cache = VotingWalletDbPathCache(
      resolver: () {
        calls++;
        return gate.future;
      },
    );

    final first = cache.resolve();
    final second = cache.resolve();
    gate.complete('/wallet/zcash_wallet.db');

    expect(await first, '/wallet/zcash_wallet.db');
    expect(await second, '/wallet/zcash_wallet.db');
    expect(calls, 1);
  });

  test('a failed resolve is not cached', () async {
    var calls = 0;
    final cache = VotingWalletDbPathCache(
      resolver: () async {
        calls++;
        if (calls == 1) throw StateError('no wallet');
        return '/wallet/zcash_wallet.db';
      },
    );

    await expectLater(cache.resolve(), throwsStateError);
    expect(await cache.resolve(), '/wallet/zcash_wallet.db');
    expect(calls, 2);
  });

  test('clear forces the next resolve to re-read the DB name', () async {
    var calls = 0;
    final cache = VotingWalletDbPathCache(
      resolver: () async {
        calls++;
        return '/wallet/db-$calls.db';
      },
    );

    expect(await cache.resolve(), '/wallet/db-1.db');
    cache.clear();
    // A reset mints a new DB name; the stale path would point at a deleted DB.
    expect(await cache.resolve(), '/wallet/db-2.db');
    expect(calls, 2);
  });
}
