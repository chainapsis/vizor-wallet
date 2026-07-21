import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_operation_registry.dart';

void main() {
  const network = 'test';
  const accountUuid = 'account-1';

  test('revocation waits for active work and rejects queued work', () async {
    final registry = IronwoodMigrationOperationRegistry();
    final started = Completer<void>();
    final finish = Completer<void>();

    final active = registry.run<void>(
      network: network,
      accountUuid: accountUuid,
      operation: () async {
        started.complete();
        await finish.future;
      },
    );
    await started.future;

    var queuedRan = false;
    final queued = registry.run<void>(
      network: network,
      accountUuid: accountUuid,
      operation: () async => queuedRan = true,
    );

    var revocationCompleted = false;
    final revocationFuture = registry
        .revokeAndWait(network: network, accountUuid: accountUuid)
        .then((value) {
          revocationCompleted = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);

    expect(revocationCompleted, isFalse);
    await expectLater(
      registry.run<void>(
        network: network,
        accountUuid: accountUuid,
        operation: () async {},
      ),
      throwsA(isA<IronwoodMigrationAccountRevokedException>()),
    );

    finish.complete();
    await active;
    await expectLater(
      queued,
      throwsA(isA<IronwoodMigrationAccountRevokedException>()),
    );
    expect(queuedRan, isFalse);
    final revocation = await revocationFuture;
    revocation.commit();

    await expectLater(
      registry.run<void>(
        network: network,
        accountUuid: accountUuid,
        operation: () async {},
      ),
      throwsA(isA<IronwoodMigrationAccountRevokedException>()),
    );
  });

  test('rollback permits work after account deletion fails', () async {
    final registry = IronwoodMigrationOperationRegistry();

    final revocation = await registry.revokeAndWait(
      network: network,
      accountUuid: accountUuid,
    );
    revocation.rollback();

    var ran = false;
    await registry.run<void>(
      network: network,
      accountUuid: accountUuid,
      operation: () async => ran = true,
    );

    expect(ran, isTrue);
  });

  test('committed revocation permits an idempotent deletion retry', () async {
    final registry = IronwoodMigrationOperationRegistry();
    final first = await registry.revokeAndWait(
      network: network,
      accountUuid: accountUuid,
    );
    first.commit();

    final retry = await registry.revokeAndWait(
      network: network,
      accountUuid: accountUuid,
    );
    retry.rollback();

    await expectLater(
      registry.run<void>(
        network: network,
        accountUuid: accountUuid,
        operation: () async {},
      ),
      throwsA(isA<IronwoodMigrationAccountRevokedException>()),
    );
  });

  test('revoking one account does not block another account', () async {
    final registry = IronwoodMigrationOperationRegistry();
    final revocation = await registry.revokeAndWait(
      network: network,
      accountUuid: accountUuid,
    );
    revocation.commit();

    var ran = false;
    await registry.run<void>(
      network: network,
      accountUuid: 'account-2',
      operation: () async => ran = true,
    );

    expect(ran, isTrue);
  });
}
