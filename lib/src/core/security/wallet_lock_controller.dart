import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show log;
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';

const Duration kAutoLockBackgroundTimeout = Duration(minutes: 10);

bool shouldAutoLock({
  required DateTime? hiddenAt,
  required DateTime now,
  Duration threshold = kAutoLockBackgroundTimeout,
}) {
  if (hiddenAt == null) return false;
  return now.difference(hiddenAt) >= threshold;
}

Future<void> lockWalletSession({
  required AppSecurityNotifier securityNotifier,
  required AccountNotifier accountNotifier,
  required SyncNotifier syncNotifier,
  bool awaitSync = false,
}) async {
  securityNotifier.lock();
  accountNotifier.clearSensitiveStateForLock();
  final syncFuture = syncNotifier.clearSensitiveStateForLock();
  if (awaitSync) {
    await syncFuture;
  } else {
    unawaited(syncFuture);
  }
}

class AutoLockObserver extends ConsumerStatefulWidget {
  const AutoLockObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoLockObserver> createState() => _AutoLockObserverState();
}

class _AutoLockObserverState extends ConsumerState<AutoLockObserver> {
  AppLifecycleListener? _listener;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void dispose() {
    _listener?.dispose();
    _listener = null;
    super.dispose();
  }

  void _onHide() {
    final security = ref.read(appSecurityProvider);
    if (!security.isUnlocked) return;
    _hiddenAt = DateTime.now();
  }

  void _onShow() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null) return;
    final security = ref.read(appSecurityProvider);
    if (!security.isUnlocked) return;
    final now = DateTime.now();
    if (!shouldAutoLock(hiddenAt: hiddenAt, now: now)) return;
    log(
      'AutoLock: hidden for ${now.difference(hiddenAt)}, '
      'locking wallet session',
    );
    lockWalletSession(
      securityNotifier: ref.read(appSecurityProvider.notifier),
      accountNotifier: ref.read(accountProvider.notifier),
      syncNotifier: ref.read(syncProvider.notifier),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
