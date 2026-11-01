import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/zns_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/zns_recipient_lookup.dart';

import '../../fakes/fake_zns_name_resolver.dart';

const _address = 'u1aliceaddress';
const _alice = ZnsResolution(name: 'alice', address: _address);

void main() {
  group('lookUpZnsRecipient', () {
    test('finds a registered name', () async {
      final lookup = await lookUpZnsRecipient(
        FakeZnsNameResolver({'alice': _address}),
        'alice',
      );
      expect(
        lookup,
        isA<ZnsRecipientFound>().having(
          (l) => l.resolution,
          'resolution',
          _alice,
        ),
      );
    });

    test('maps every way to have no address to a status', () async {
      Future<ZnsLookupStatus> statusOf(ZnsNameResolver? resolver) async =>
          (await lookUpZnsRecipient(resolver, 'alice') as ZnsRecipientMissing)
              .status;

      expect(await statusOf(null), ZnsLookupStatus.unsupportedNetwork);
      expect(
        await statusOf(FakeZnsNameResolver()),
        ZnsLookupStatus.notRegistered,
      );
      expect(
        await statusOf(
          FakeZnsNameResolver(const {}, const ZnsLookupException('offline')),
        ),
        ZnsLookupStatus.failed,
      );
      expect(
        await statusOf(FakeZnsNameResolver(const {}, StateError('bug'))),
        ZnsLookupStatus.failed,
        reason: 'the field must never see an exception',
      );
    });
  });

  test('a lookup failure is an error; a missing name is invalid', () {
    expect(ZnsLookupStatus.resolving.addressType, '');
    expect(ZnsLookupStatus.failed.addressType, 'error');
    for (final status in [
      ZnsLookupStatus.notRegistered,
      ZnsLookupStatus.unsupportedNetwork,
      ZnsLookupStatus.unusableAddress,
    ]) {
      expect(status.addressType, 'invalid', reason: '$status');
    }
    expect(ZnsLookupStatus.resolving.isError, isFalse);
  });

  group('ZnsRecipientState', () {
    test('pays the resolved address only while the field is unchanged', () {
      final state = ZnsRecipientState()
        ..settle('alice.zcash', _alice, addressValid: true);

      expect(state.status, isNull);
      expect(state.paymentAddress(' alice.zcash '), _address);
      expect(state.displayName('alice.zcash'), 'alice.zcash');
      expect(state.paymentAddress('alice.zcas'), 'alice.zcas');
      expect(state.resolutionFor('alice.zcas'), isNull);
    });

    test('a name with an unusable address keeps no resolution', () {
      final state = ZnsRecipientState()
        ..settle('bob.zcash', _alice, addressValid: false);

      expect(state.status, ZnsLookupStatus.unusableAddress);
      expect(state.resolutionFor('bob.zcash'), isNull);
      expect(state.paymentAddress('bob.zcash'), 'bob.zcash');
    });

    test('a plain address settles with no name state', () {
      final state = ZnsRecipientState()
        ..begin()
        ..settle(_address, null, addressValid: true);

      expect(state.status, isNull);
      expect(state.paymentAddress(_address), _address);
      expect(state.displayName(_address), isNull);
    });

    test('a carried name survives a lookup reset but not a field reset', () {
      final state = ZnsRecipientState(carriedName: 'alice.zcash');
      expect(state.displayName(_address), 'alice.zcash');

      state.clearLookup();
      expect(state.displayName(_address), 'alice.zcash');

      state.reset();
      expect(state.displayName(_address), isNull);
    });

    test('begin and fail replace an earlier resolution', () {
      final state = ZnsRecipientState()
        ..settle('alice.zcash', _alice, addressValid: true)
        ..begin();
      expect(state.status, ZnsLookupStatus.resolving);
      expect(state.resolutionFor('alice.zcash'), isNull);

      state
        ..settle('alice.zcash', _alice, addressValid: true)
        ..fail(ZnsLookupStatus.failed);
      expect(state.status, ZnsLookupStatus.failed);
      expect(state.resolutionFor('alice.zcash'), isNull);
    });
  });
}
