import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';

void main() {
  const sourceA =
      'https://voting.example/static-a.json?checksum=sha256:'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const sourceB =
      'https://voting.example/static-b.json?checksum=sha256:'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const sourceWithoutChecksum = 'https://voting.example/static.json';

  test('loads stored source and filters invalid saved sources', () async {
    final store = FakeVotingConfigSourceStore(
      sourceUrl: sourceA,
      savedSourcesJson:
          '''
        [
          {"id":"a","name":" Alpha ","sourceUrl":"$sourceA"},
          {"id":42,"name":"Wrong type","sourceUrl":"$sourceB"},
          {"id":"","name":"Missing id","sourceUrl":"$sourceB"},
          {"id":"bad","name":"Bad","sourceUrl":"http://voting.example/static.json"}
        ]
      ''',
    );
    final container = _container(store);
    addTearDown(container.dispose);

    final state = await container.read(votingConfigSourceProvider.future);

    expect(state.sourceUrl, sourceA);
    expect(state.isDefault, isFalse);
    expect(state.savedSources, hasLength(1));
    expect(state.savedSources.single.name, 'Alpha');
  });

  test(
    'invalid stored source falls back to default and clears override',
    () async {
      final store = FakeVotingConfigSourceStore(
        sourceUrl: 'http://voting.example/static.json',
        savedSourcesJson:
            '''
        [
          {"id":"a","name":"Alpha","sourceUrl":"$sourceA"}
        ]
      ''',
      );
      final container = _container(store);
      addTearDown(container.dispose);

      final state = await container.read(votingConfigSourceProvider.future);

      expect(state.sourceUrl, kDefaultStaticVotingConfigSource);
      expect(state.isDefault, isTrue);
      expect(state.savedSources.single.id, 'a');
      expect(store.sourceUrl, isNull);
    },
  );

  test('save source persists the source and makes it active', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(votingConfigSourceProvider.future);

    await container
        .read(votingConfigSourceProvider.notifier)
        .saveSource(name: ' Demo ', sourceUrl: sourceA);

    final state = container.read(votingConfigSourceProvider).value!;
    expect(state.sourceUrl, sourceA);
    expect(state.isDefault, isFalse);
    expect(state.savedSources.single.name, 'Demo');
    expect(store.sourceUrl, sourceA);
    expect(store.savedSourcesJson, contains(sourceA));
  });

  test('set custom accepts source without checksum pin', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(votingConfigSourceProvider.future);

    await container
        .read(votingConfigSourceProvider.notifier)
        .setCustom(sourceWithoutChecksum);

    final state = container.read(votingConfigSourceProvider).value!;
    expect(state.sourceUrl, sourceWithoutChecksum);
    expect(state.isDefault, isFalse);
    expect(store.sourceUrl, sourceWithoutChecksum);
  });

  test('stored custom source without checksum stays active', () async {
    final store = FakeVotingConfigSourceStore(
      sourceUrl: sourceWithoutChecksum,
      savedSourcesJson:
          '''
        [
          {"id":"a","name":"Alpha","sourceUrl":"$sourceA"}
        ]
      ''',
    );
    final container = _container(store);
    addTearDown(container.dispose);

    final state = await container.read(votingConfigSourceProvider.future);
    expect(state.sourceUrl, sourceWithoutChecksum);
    expect(state.isDefault, isFalse);
    expect(store.sourceUrl, sourceWithoutChecksum);
  });

  test('set custom still rejects malformed checksum when provided', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(votingConfigSourceProvider.future);

    await expectLater(
      () => container
          .read(votingConfigSourceProvider.notifier)
          .setCustom(
            'https://voting.example/static.json?checksum=sha256:INVALID',
          ),
      throwsA(isA<StaticVotingConfigSourceMalformed>()),
    );
  });

  test('save source rejects same URL with different checksum', () async {
    const sourceAAltChecksum =
        'https://voting.example/static-a.json?checksum=sha256:'
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final store = FakeVotingConfigSourceStore();
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(votingConfigSourceProvider.future);
    await container
        .read(votingConfigSourceProvider.notifier)
        .saveSource(name: 'Alpha', sourceUrl: sourceA);

    await expectLater(
      () => container
          .read(votingConfigSourceProvider.notifier)
          .saveSource(name: 'Alpha alt', sourceUrl: sourceAAltChecksum),
      throwsA(isA<DuplicateVotingConfigSource>()),
    );

    final state = container.read(votingConfigSourceProvider).value!;
    expect(state.savedSources, hasLength(1));
    expect(state.savedSources.single.sourceUrl, sourceA);
  });

  test('deleting the active saved source falls back to default', () async {
    final store = FakeVotingConfigSourceStore(
      sourceUrl: sourceA,
      savedSourcesJson:
          '''
        [
          {"id":"a","name":"Alpha","sourceUrl":"$sourceA"},
          {"id":"b","name":"Beta","sourceUrl":"$sourceB"}
        ]
      ''',
    );
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(votingConfigSourceProvider.future);

    await container
        .read(votingConfigSourceProvider.notifier)
        .deleteSavedSource('a');

    final state = container.read(votingConfigSourceProvider).value!;
    expect(state.sourceUrl, kDefaultStaticVotingConfigSource);
    expect(state.isDefault, isTrue);
    expect(state.savedSources.map((source) => source.id), ['b']);
    expect(store.sourceUrl, isNull);
  });
}

ProviderContainer _container(FakeVotingConfigSourceStore store) {
  return ProviderContainer(
    overrides: [votingConfigSourceStoreProvider.overrideWithValue(store)],
  );
}

class FakeVotingConfigSourceStore implements VotingConfigSourceStore {
  FakeVotingConfigSourceStore({this.sourceUrl, this.savedSourcesJson});

  String? sourceUrl;
  String? savedSourcesJson;

  @override
  Future<String?> readSourceUrl() async => sourceUrl;

  @override
  Future<void> writeSourceUrl(String sourceUrl) async {
    this.sourceUrl = sourceUrl;
  }

  @override
  Future<void> resetSourceUrl() async {
    sourceUrl = null;
  }

  @override
  Future<String?> readSavedSourcesJson() async => savedSourcesJson;

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) async {
    this.savedSourcesJson = savedSourcesJson;
  }
}
