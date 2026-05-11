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
  try {
    if (pause.hadWorkToPause) {
      await onSyncPaused?.call();
    }
    return await action();
  } finally {
    if (resumeAfterMutation) {
      syncNotifier.resumeAfterWalletMutation(pause);
    }
  }
}
