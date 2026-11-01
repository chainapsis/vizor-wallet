import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import 'enhance_pir_provider.dart';
import 'sync_provider.dart';

/// Whether the wallet's automatic lookup of past one-time swap payments is
/// still running, as after NEAR swap privacy is turned on or a restore. A
/// history check the user started doesn't count. The wallet reports one state
/// for all its accounts.
final swapPastSwapsCheckProvider = NotifierProvider<SwapPastSwapsCheck, bool>(
  SwapPastSwapsCheck.new,
);

/// See [swapPastSwapsCheckProvider]. Reads the wallet's saved state again
/// after every recovery round and NEAR swap privacy change; a read the wallet
/// refuses keeps the last answer.
class SwapPastSwapsCheck extends Notifier<bool> {
  var _reads = 0;

  @override
  bool build() {
    _reads = 0;
    ref.listen(swapRecoveryRoundsProvider, (_, _) => unawaited(_read()));
    ref.listen(nearSwapPrivacyProvider, (_, _) => unawaited(_read()));
    unawaited(Future<void>.microtask(_read));
    return false;
  }

  Future<void> _read() async {
    final read = ++_reads;
    try {
      final status = await ref.read(swapRecoveryStatusReaderProvider)();
      if (!ref.mounted || read != _reads) return;
      state =
          status != null && status.checkingHistory && !status.manualCheckActive;
    } catch (error) {
      // A wallet change holds admission; keep the last answer.
      log('Swap history state not read: $error');
    }
  }
}
