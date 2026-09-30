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
    super.key,
  });

  final GoRouter router;
  final Widget child;
  final Duration timeout;

  @override
  ConsumerState<BackgroundAutoLockHost> createState() =>
      _BackgroundAutoLockHostState();
}

class _BackgroundAutoLockHostState
    extends ConsumerState<BackgroundAutoLockHost> {
  AppLifecycleListener? _listener;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor != AppFormFactor.mobile) return;
    _listener = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: _onShow,
    );
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  void _onShow() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // Wall clock: monotonic clocks stop while the device sleeps.
    if (hiddenAt == null ||
        DateTime.now().difference(hiddenAt) < widget.timeout) {
      return;
    }

    final security = ref.read(appSecurityProvider);
    if (!security.isPasswordConfigured ||
        !security.isUnlocked ||
        !(ref.read(walletProvider).value?.hasWallet ?? false) ||
        // Same guard as sign-out; the next return re-evaluates.
        ref.read(votingSubmissionGuardProvider).isNotEmpty) {
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
