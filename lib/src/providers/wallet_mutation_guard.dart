import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_provider.dart';
import 'sync_provider.dart';

Future<T> runWithSyncPausedForAccountMutation<T>(
  WidgetRef ref,
  Future<T> Function() action, {
  FutureOr<void> Function()? onStoppingSync,
  FutureOr<void> Function()? onSyncPaused,
  bool resumeAfterMutation = true,
}) async {
  final hasExistingAccounts =
      (ref.read(accountProvider).value?.accounts ?? const <AccountInfo>[])
          .isNotEmpty;
  final syncNotifier = ref.read(syncProvider.notifier);
  if (!hasExistingAccounts && !syncNotifier.needsPauseForWalletMutation()) {
    return action();
  }

  final pause = await syncNotifier.pauseForWalletMutation(
    onStoppingSync: onStoppingSync,
  );
  // `resumeAfterMutation: false` means "don't resume after a SUCCESSFUL
  // mutation" (e.g. a full wallet reset that ends with no wallet to sync).
  // When the action throws, the wallet still exists, so sync must resume
  // either way or the app is left with polling silently stopped.
  var succeeded = false;
  try {
    if (pause.hadWorkToPause) {
      await onSyncPaused?.call();
    }
    final result = await action();
    succeeded = true;
    return result;
  } finally {
    if (resumeAfterMutation || !succeeded) {
      syncNotifier.resumeAfterWalletMutation(pause);
    }
  }
}
