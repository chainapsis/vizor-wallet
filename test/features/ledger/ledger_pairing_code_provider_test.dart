import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_pairing_code_provider.dart';

void main() {
  test('surfaces a Linux pairing code until the prompt ends', () async {
    final events = StreamController<Object?>();
    addTearDown(events.close);
    final container = ProviderContainer(
      overrides: [
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ledgerConnectionEventSourceProvider.overrideWithValue(
          () => events.stream,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(ledgerPairingCodeProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(ledgerPairingCodeProvider).value, isNull);

    events.add({'type': 'pairing', 'code': '123456'});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(ledgerPairingCodeProvider).value, '123456');

    events.add({'type': 'pairing_ended'});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(ledgerPairingCodeProvider).value, isNull);
  });

  test('other platforms never listen to the connection channel', () async {
    var subscribed = false;
    final container = ProviderContainer(
      overrides: [
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ledgerConnectionEventSourceProvider.overrideWithValue(() {
          subscribed = true;
          return const Stream.empty();
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(ledgerPairingCodeProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(subscribed, isFalse);
    expect(container.read(ledgerPairingCodeProvider).value, isNull);
  });

  test('decodes only a well-formed pairing event', () {
    expect(
      ledgerPairingCodeFromEvent({'type': 'pairing', 'code': '000042'}),
      '000042',
    );
    expect(ledgerPairingCodeFromEvent({'type': 'pairing', 'code': ''}), isNull);
    expect(ledgerPairingCodeFromEvent({'type': 'pairing'}), isNull);
    expect(ledgerPairingCodeFromEvent({'type': 'pairing_ended'}), isNull);
    expect(ledgerPairingCodeFromEvent('pairing'), isNull);
    expect(ledgerPairingCodeFromEvent(null), isNull);
  });
}
