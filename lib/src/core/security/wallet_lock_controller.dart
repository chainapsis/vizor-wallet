import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show log;
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';

const Duration kAutoLockBackgroundTimeout = Duration(minutes: 10);

bool shouldAutoLock({
  required Duration? hiddenAt,
  required Duration now,
  Duration threshold = kAutoLockBackgroundTimeout,
}) {
  if (hiddenAt == null) return false;
  return (now - hiddenAt) >= threshold;
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
  final Stopwatch _clock = Stopwatch()..start();
  Duration? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void dispose() {
    _listener?.dispose();
    _listener = null;
    _clock.stop();
    super.dispose();
  }

  void _onHide() {
    final security = ref.read(appSecurityProvider);
    if (!security.isUnlocked) return;
    _hiddenAt = _clock.elapsed;
  }

  void _onShow() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null) return;
    final security = ref.read(appSecurityProvider);
    if (!security.isUnlocked) return;
    final now = _clock.elapsed;
    if (!shouldAutoLock(hiddenAt: hiddenAt, now: now)) return;
    log('AutoLock: hidden for ${now - hiddenAt}, locking wallet session');
    lockWalletSession(
      securityNotifier: ref.read(appSecurityProvider.notifier),
      accountNotifier: ref.read(accountProvider.notifier),
      syncNotifier: ref.read(syncProvider.notifier),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
