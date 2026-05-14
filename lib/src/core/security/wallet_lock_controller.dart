import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show log;
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/wallet_provider.dart';

const Duration kAutoLockBackgroundTimeout = Duration(minutes: 10);

bool shouldAutoLock({
  required Duration elapsed,
  Duration threshold = kAutoLockBackgroundTimeout,
}) {
  return elapsed >= threshold;
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
  Duration? _monoHiddenAt;
  DateTime? _wallHiddenAt;

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

  bool _isLockable() {
    final security = ref.read(appSecurityProvider);
    if (!security.isUnlocked) return false;
    final wallet = ref.read(walletProvider).value;
    return wallet?.hasWallet ?? false;
  }

  void _onHide() {
    if (!_isLockable()) return;
    _monoHiddenAt = _clock.elapsed;
    _wallHiddenAt = DateTime.now();
  }

  void _onShow() {
    final monoHiddenAt = _monoHiddenAt;
    final wallHiddenAt = _wallHiddenAt;
    _monoHiddenAt = null;
    _wallHiddenAt = null;
    if (monoHiddenAt == null || wallHiddenAt == null) return;
    if (!_isLockable()) return;
    final monoElapsed = _clock.elapsed - monoHiddenAt;
    final wallElapsed = DateTime.now().difference(wallHiddenAt);
    if (!shouldAutoLock(elapsed: monoElapsed) &&
        !shouldAutoLock(elapsed: wallElapsed)) {
      return;
    }
    log(
      'AutoLock: monoElapsed=$monoElapsed wallElapsed=$wallElapsed, '
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
