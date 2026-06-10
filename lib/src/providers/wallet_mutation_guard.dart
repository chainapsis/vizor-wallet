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
  bool resumeAfterFailure = true,
  bool Function(Object error, StackTrace stackTrace)? shouldResumeAfterFailure,
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
  // Non-destructive failures still resume by default, but destructive reset
  // callers can opt out once the action may have already deleted the wallet DB.
  var succeeded = false;
  Object? failure;
  StackTrace? failureStackTrace;
  try {
    if (pause.hadWorkToPause) {
      await onSyncPaused?.call();
    }
    final result = await action();
    succeeded = true;
    return result;
  } catch (e, st) {
    failure = e;
    failureStackTrace = st;
    rethrow;
  } finally {
    final shouldResume = succeeded
        ? resumeAfterMutation
        : shouldResumeAfterFailure?.call(
                failure as Object,
                failureStackTrace ?? StackTrace.current,
              ) ??
              resumeAfterFailure;
    if (shouldResume) {
      syncNotifier.resumeAfterWalletMutation(pause);
    }
  }
}

Future<void> runWithSyncPausedForWalletReset(
  WidgetRef ref,
  Future<void> Function() resetWallet, {
  FutureOr<void> Function()? onStoppingSync,
  FutureOr<void> Function()? onSyncPaused,
  FutureOr<void> Function()? onResetting,
}) {
  final syncNotifier = ref.read(syncProvider.notifier);
  return runWithSyncPausedForAccountMutation<void>(
    ref,
    () async {
      await onResetting?.call();
      try {
        await resetWallet();
      } finally {
        syncNotifier.clearCachedWalletDbPath();
      }
    },
    onStoppingSync: onStoppingSync,
    onSyncPaused: onSyncPaused,
    resumeAfterMutation: false,
    shouldResumeAfterFailure: (error, stackTrace) =>
        error is! WalletResetException || !error.dbDeleted,
  );
}
