import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/migration/services/ironwood_migration_background_credential_store.dart';
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
  bool quiesceMigrationWork = true,
  IronwoodMigrationBackgroundLifecycle? migrationLifecycle,
}) async {
  final hasExistingAccounts =
      (ref.read(accountProvider).value?.accounts ?? const <AccountInfo>[])
          .isNotEmpty;
  final syncNotifier = ref.read(syncProvider.notifier);
  final shouldQuiesceMigrationWork =
      quiesceMigrationWork && hasExistingAccounts;
  final lifecycle =
      migrationLifecycle ?? IronwoodMigrationBackgroundLifecycle.instance;
  var migrationWorkQuiesced = false;
  var migrationQuiesceAttempted = false;

  try {
    // Migration preparation has its own native sync/advance loop. Stop that
    // owner before inspecting or cancelling foreground sync so a native pass
    // cannot be mistaken for foreground work. Treat an attempted quiesce as a
    // lease even when its MethodChannel response is ambiguous: the native side
    // may already have stopped and must be resumed in the outer finally.
    if (shouldQuiesceMigrationWork) {
      migrationQuiesceAttempted = true;
      await lifecycle.quiesce();
      migrationWorkQuiesced = true;
    }

    if (!hasExistingAccounts && !syncNotifier.needsPauseForWalletMutation()) {
      return await action();
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
      final result = migrationWorkQuiesced
          ? await lifecycle.runWithCallerManagedQuiescence(action)
          : await action();
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
  } finally {
    if (migrationQuiesceAttempted) {
      try {
        await lifecycle.resumeAfterMutation();
      } catch (error, stackTrace) {
        // The DB mutation may already have committed. A best-effort recovery
        // failure must not turn that durable success into an import error (or
        // mask the mutation's original exception and invite a duplicate retry).
        log(
          'Failed to resume Ironwood migration after account mutation: '
          '$error\n$stackTrace',
        );
      }
    }
  }
}

Future<void> runWithSyncPausedForWalletReset(
  WidgetRef ref,
  Future<void> Function() resetWallet, {
  FutureOr<void> Function()? onStoppingSync,
  FutureOr<void> Function()? onSyncPaused,
  FutureOr<void> Function()? onResetting,
  IronwoodMigrationBackgroundLifecycle? migrationLifecycle,
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
    migrationLifecycle: migrationLifecycle,
  );
}
