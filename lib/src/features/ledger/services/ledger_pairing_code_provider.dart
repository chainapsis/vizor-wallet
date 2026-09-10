import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ledger_capability.dart' show ledgerTargetPlatformProvider;
import 'ledger_mobile_ble_service.dart' show kLedgerMobileMethodChannel;

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

/// Answers the pairing prompt: `accept` is whether the Ledger shows the same
/// code. The host side of the pairing stays on hold until this is called,
/// so a rejected answer never leaves a bond behind.
typedef LedgerPairingAnswer = Future<void> Function({required bool accept});

final ledgerPairingAnswerProvider = Provider<LedgerPairingAnswer>((_) {
  const methods = MethodChannel(kLedgerMobileMethodChannel);
  return ({required accept}) =>
      methods.invokeMethod<void>('confirmPairing', {'accept': accept});
});

/// The Bluetooth pairing code to compare with the Ledger's screen, or null
/// while no pairing waits for confirmation.
///
/// On Linux, Vizor's own BlueZ agent answers the host side of a pairing it
/// started, so this is the only place the user can check that both devices
/// show the same code; the answer goes back through
/// [ledgerPairingAnswerProvider]. Other platforms show their own pairing
/// prompt and never emit a code.
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
