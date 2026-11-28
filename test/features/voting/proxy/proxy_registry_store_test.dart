import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_store.dart';
import 'package:zcash_wallet/src/services/voting/voting_file_cache.dart';

void main() {
  late Directory root;
  late ProxyRegistryStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('proxy-registry-store-');
    store = ProxyRegistryStore(VotingFileCache(directory: () async => root));
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('state round-trips per network', () async {
    await store.writeRegistryCache('main', '{"entries":[]}');
    final list = Uint8List.fromList(List.generate(300, (i) => i % 256));
    await store.writeWalletList('main', list);

    expect(await store.readRegistryCache('main'), '{"entries":[]}');
    expect(await store.readRegistryCache('test'), isNull);
    expect(await store.readWalletList('main'), list);
    expect(await store.readWalletList('test'), isNull);
    expect(
      File(
        '${root.path}/$kProxyRegistryCacheFolder/main/wallet-list.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('clear deletes every network and leaves other voting data', () async {
    await store.writeRegistryCache('main', '{}');
    await store.writeWalletList('test', [1, 2, 3]);
    final notes = File('${root.path}/${VotingFileCache.digest('a')}/n.json');
    await notes.parent.create(recursive: true);
    await notes.writeAsString('{}');

    await store.clear();

    expect(
      Directory('${root.path}/$kProxyRegistryCacheFolder').existsSync(),
      isFalse,
    );
    expect(notes.existsSync(), isTrue);
    await store.clear();
  });
}
