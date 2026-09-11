import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/services/voting/voting_file_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late VotingFileCache cache;
  final key = '0100${'a' * 128}';
  final other = '0100${'b' * 128}';
  final scope = jsonEncode(['main', 'round', '100', 'governance-v1']);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('voting-note-cache-');
    cache = VotingFileCache(directory: () async => root);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'reset retries orphaned caches after secure storage loses the DB name',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = AppSecureStore.instance;
      final oldName = await storage.ensureWalletDbName();
      final oldCache = Directory('${root.path}/$oldName.voting-cache');
      final sibling = Directory(
        '${root.path}/zcash_wallet_${'a' * 24}.db.voting-cache',
      );
      for (final directory in [oldCache, sibling]) {
        await directory.create();
        await File('${directory.path}/home-v2.json').writeAsString('{}');
      }
      await expectLater(
        clearVotingCachesForReset(
          resolveSupportDirectory: () async => root,
          deleteDirectory: (directory) async {
            if (directory.path == oldCache.path) {
              throw FileSystemException('locked');
            }
            await directory.delete(recursive: true);
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sibling.exists(), false);
      expect(await oldCache.exists(), true);
      // Matches resetWallet: secrets are wiped even if cache cleanup failed.
      await storage.deleteAll();
      expect(await storage.ensureWalletDbName(), isNot(oldName));
      await clearVotingCachesForReset(
        resolveSupportDirectory: () async => root,
      );
      expect(await oldCache.exists(), false);
      await storage.deleteAll();
    },
  );

  test(
    'reset sweep only deletes wallet cache directories and never follows links',
    () async {
      final legacy = Directory('${root.path}/zcash_wallet.db.voting-cache');
      await legacy.create();
      final unrelated = Directory('${root.path}/other.db.voting-cache');
      await unrelated.create();
      final db = File('${root.path}/zcash_wallet_${'b' * 24}.db');
      await db.writeAsString('wallet');
      final link = Link(
        '${root.path}/zcash_wallet_${'c' * 24}.db.voting-cache',
      );
      await link.create(unrelated.path);
      await clearVotingCachesForReset(
        resolveSupportDirectory: () async => root,
      );
      expect(await legacy.exists(), false);
      expect(await unrelated.exists(), true);
      expect(await db.exists(), true);
      expect(await link.exists(), true);
      await link.delete();
      await clearVotingCachesForReset(
        resolveSupportDirectory: () async => Directory('${root.path}/absent'),
      );
    },
  );

  test(
    'restart preserves used and unused and isolates accounts and rounds',
    () async {
      await cache.writeNotes('a', scope, {
        key: {'used': true, 'height': 10},
        other: {'used': false, 'height': 10},
      });
      final reopened = VotingFileCache(directory: () async => root);
      expect(await reopened.readNotes('a', scope), hasLength(2));
      expect(await reopened.readNotes('b', scope), isEmpty);
      expect(
        await reopened.readNotes(
          'a',
          jsonEncode(['test', 'round', '100', 'governance-v1']),
        ),
        isEmpty,
      );
    },
  );

  test(
    'concurrent stale observations never revert a locally confirmed note',
    () async {
      await Future.wait([
        cache.writeNotes('a', scope, {
          key: {'used': true, 'height': 0},
        }),
        VotingFileCache(directory: () async => root).writeNotes('a', scope, {
          key: {'used': false, 'height': 99},
          other: {'used': false, 'height': 99},
        }),
      ]);
      expect((await cache.readNotes('a', scope))[key]['used'], true);
      expect(await cache.readNotes('a', scope), hasLength(2));
    },
  );

  test('malformed entries are unknown without losing valid siblings', () async {
    await cache.write(
      cache.notePath('a', scope),
      jsonEncode({
        'version': 1,
        'scope': scope,
        'notes': {
          key: {'used': false, 'height': 10},
          other: {'used': 'false', 'height': 10},
          'not-a-key': {'used': true, 'height': 10},
        },
      }),
    );
    expect((await cache.readNotes('a', scope)).keys, [key]);
  });

  test(
    'ended round cleanup prevents late writes but retains other scopes',
    () async {
      final next = jsonEncode(['main', 'next', '100', 'governance-v1']);
      for (final account in ['a', 'b']) {
        await cache.writeNotes(account, scope, {
          key: {'used': true, 'height': 1},
        });
        await cache.writeNotes(account, next, {
          key: {'used': false, 'height': 1},
        });
      }
      await cache.removeRound('main', 'round');
      await cache.writeNotes('a', scope, {
        key: {'used': false, 'height': 2},
      });
      expect(await cache.readNotes('a', scope), isEmpty);
      expect(await cache.readNotes('b', scope), isEmpty);
      expect(await cache.readNotes('b', next), hasLength(1));
      await cache.removeAccount('a');
      expect(await cache.readNotes('a', next), isEmpty);
      expect(await cache.readNotes('b', next), hasLength(1));
      await cache.clear();
      expect(await root.exists(), false);
    },
  );

  test(
    'snapshot registration preserves tokens across client instances',
    () async {
      expect(await cache.snapshotRevision(100), '0');
      await File('${root.path}/snapshots/100').writeAsString('scan-generation');
      final reopened = VotingFileCache(directory: () async => root);
      expect(await reopened.snapshotRevision(100), 'scan-generation');
      expect(await reopened.snapshotRevision(200), '0');
    },
  );
}
