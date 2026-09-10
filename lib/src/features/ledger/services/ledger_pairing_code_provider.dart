import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ledger_capability.dart' show ledgerTargetPlatformProvider;

/// Connection progress the Linux runner pushes while a Ledger connects.
const kLedgerConnectionEventChannel =
    'com.zcash.wallet/ledger_mobile/connection';

typedef LedgerConnectionEventSource = Stream<Object?> Function();

final ledgerConnectionEventSourceProvider =
    Provider<LedgerConnectionEventSource>(
      (_) => const EventChannel(
        kLedgerConnectionEventChannel,
      ).receiveBroadcastStream,
    );

/// The Bluetooth pairing code to compare with the Ledger's screen, or null
/// while no pairing waits for confirmation.
///
/// On Linux, Vizor's own BlueZ agent confirms the host side of a pairing it
/// started, so this is the only place the user can check that both devices
/// show the same code before approving on the Ledger. Other platforms show
/// their own pairing prompt and never emit a code.
final ledgerPairingCodeProvider = StreamProvider<String?>((ref) {
  if (ref.watch(ledgerTargetPlatformProvider) != TargetPlatform.linux) {
    return Stream.value(null);
  }
  return ref
      .watch(ledgerConnectionEventSourceProvider)()
      .map(ledgerPairingCodeFromEvent);
});

/// `{type: 'pairing', code}` carries a code; any other event ends the prompt.
String? ledgerPairingCodeFromEvent(Object? event) {
  if (event is! Map || event['type'] != 'pairing') return null;
  final code = event['code'];
  return code is String && code.isNotEmpty ? code : null;
}
