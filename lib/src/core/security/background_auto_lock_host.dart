import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/voting/voting_submission_guard_provider.dart';
import '../../providers/wallet_provider.dart';
import '../layout/app_form_factor.dart';

const kBackgroundAutoLockTimeout = Duration(minutes: 15);

/// Locks the mobile wallet when it returns after [timeout] in the background.
///
/// Uses the desktop sign-out sequence, so the existing unlock screen handles
/// biometrics, parked links, and passcode reset. After this long in the
/// background the OS has already suspended in-flight Dart work, so a session
/// lock costs no more than the cold start the app must survive anyway.
class BackgroundAutoLockHost extends ConsumerStatefulWidget {
  const BackgroundAutoLockHost({
    required this.router,
    required this.child,
    this.timeout = kBackgroundAutoLockTimeout,
    this.now,
    super.key,
  });

  final GoRouter router;
  final Widget child;
  final Duration timeout;
  final DateTime Function()? now;

  @override
  ConsumerState<BackgroundAutoLockHost> createState() =>
      _BackgroundAutoLockHostState();
}

class _BackgroundAutoLockHostState
    extends ConsumerState<BackgroundAutoLockHost> {
  AppLifecycleListener? _listener;
  DateTime? _hiddenAt;
  bool _lockPending = false;

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor != AppFormFactor.mobile) return;
    _listener = AppLifecycleListener(
      onHide: () => _hiddenAt = _now(),
      onShow: _onShow,
    );
    // A lock deferred for a voting submission applies once it finishes.
    ref.listenManual(votingSubmissionGuardProvider, (_, guards) {
      if (guards.isEmpty) _lockIfPending();
    });
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  void _onShow() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null) return;
    // Wall clock: monotonic clocks stop while the device sleeps. A clock moved
    // backwards cannot prove a short absence, so it locks.
    final away = _now().difference(hiddenAt);
    if (!away.isNegative && away < widget.timeout) return;
    _lockPending = true;
    _lockIfPending();
  }

  void _lockIfPending() {
    // Same guard as sign-out: the lock waits for the submission to finish.
    if (!_lockPending || ref.read(votingSubmissionGuardProvider).isNotEmpty) {
      return;
    }
    _lockPending = false;
    final security = ref.read(appSecurityProvider);
    if (!security.isPasswordConfigured ||
        !security.isUnlocked ||
        !(ref.read(walletProvider).value?.hasWallet ?? false)) {
      return;
    }

    ref.read(appSecurityProvider.notifier).lock();
    ref.read(accountProvider.notifier).clearSensitiveStateForLock();
    widget.router.go('/unlock');
    unawaited(ref.read(syncProvider.notifier).clearSensitiveStateForLock());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
