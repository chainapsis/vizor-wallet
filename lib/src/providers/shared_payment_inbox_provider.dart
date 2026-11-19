import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation/shared_payment_inbox.dart';
import '../core/navigation/shared_payment_intake.dart';
import '../services/qr_scanner.dart';
import '../services/shared_payment_service.dart';

/// The inbox wired to the runner's share channel, reading images through the
/// plugin the camera scanners use.
final sharedPaymentInboxProvider = Provider<SharedPaymentInbox>((ref) {
  final inbox = SharedPaymentInbox(
    intake: const SharedPaymentIntake(readQrCodes: QrScanner.readImage),
    events: ref.watch(sharedPaymentServiceProvider).stream,
  );
  ref.onDispose(inbox.dispose);
  return inbox;
});
