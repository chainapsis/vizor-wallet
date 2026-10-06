import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';

final backupReminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Snoozing hides the Home entry, while the account still needs a backup.
bool shouldShowBackupReminder(AccountInfo account, DateTime now) =>
    account.setupPending &&
    (account.backupReminderSnoozedUntilUtc == null ||
        !now.toUtc().isBefore(account.backupReminderSnoozedUntilUtc!));

final showBackupReminderProvider = Provider.autoDispose<bool>((ref) {
  final account = ref.watch(
    accountProvider.select((state) => state.value?.activeAccount),
  );
  if (account == null) return false;
  final now = ref.watch(backupReminderClockProvider)().toUtc();
  final deadline = account.backupReminderSnoozedUntilUtc;
  if (account.setupPending && deadline != null && now.isBefore(deadline)) {
    final timer = Timer(deadline.difference(now), ref.invalidateSelf);
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
    });
  }
  return shouldShowBackupReminder(account, now);
}, dependencies: [accountProvider, backupReminderClockProvider]);
