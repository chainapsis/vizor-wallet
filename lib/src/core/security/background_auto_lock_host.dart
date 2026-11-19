import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/mobile_account_visibility_provider.dart';
import '../theme/app_theme.dart';
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
  bool _coverPrivateView = false;
  bool _protectingSwitcher = false;
  static const _snapshotChannel = MethodChannel(
    'com.zcash.wallet/privacy_shield',
  );

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor != AppFormFactor.mobile) return;
    _listener = AppLifecycleListener(
      onHide: _onHide,
      onShow: _onShow,
      onResume: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncSwitcherProtection();
        });
      },
    );
    ref.listenManual(
      mobileAccountScopeProvider,
      (_, _) => _syncSwitcherProtection(),
    );
    ref.listenManual(
      mobileAccountManagementOpenProvider,
      (_, _) => _syncSwitcherProtection(),
    );
    ref.listenManual(
      mobileAccountRelockProvider,
      (_, _) => _requestPrivateLock(),
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
    if (_protectingSwitcher) unawaited(_setSwitcherProtection(false));
    super.dispose();
  }

  bool get _privateView =>
      ref.read(mobileAccountScopeProvider) != null ||
      ref.read(mobileAccountManagementOpenProvider);

  void _syncSwitcherProtection() {
    final shouldProtect = _coverPrivateView || _privateView;
    if (shouldProtect == _protectingSwitcher) return;
    // The OS can take its snapshot after Dart has already cleared the scope.
    // Hold native protection until a foreground frame can replace it.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!shouldProtect &&
        lifecycle != null &&
        lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _protectingSwitcher = shouldProtect;
    unawaited(_setSwitcherProtection(shouldProtect));
  }

  Future<void> _setSwitcherProtection(bool enabled) async {
    try {
      await _snapshotChannel.invokeMethod<void>(
        'setPrivateAccountViewVisible',
        {'visible': enabled},
      );
    } on MissingPluginException {
      // The same mobile widgets run on desktop in Widgetbook and tests.
    } on PlatformException {
      // The Flutter cover and relock still apply if the OS bridge fails.
    }
  }

  void _onHide() {
    _hiddenAt = _now();
    if (_privateView) {
      _requestPrivateLock();
    }
  }

  void _requestPrivateLock() {
    if (!ref.read(appSecurityProvider).isUnlocked) return;
    if (!_coverPrivateView) {
      setState(() => _coverPrivateView = true);
      _syncSwitcherProtection();
    }
    _lockPending = true;
    _lockIfPending();
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
      if (_coverPrivateView) _removePrivateCover();
      return;
    }

    ref.read(appSecurityProvider.notifier).lock();
    final accounts = ref.read(accountProvider.notifier);
    accounts.clearSensitiveStateForLock();
    if (_coverPrivateView) accounts.selectMobileAccountBeforeUnlock(null);
    widget.router.go('/unlock');
    unawaited(ref.read(syncProvider.notifier).clearSensitiveStateForLock());
    if (_coverPrivateView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_lockPending) _removePrivateCover();
      });
    }
  }

  void _removePrivateCover() {
    setState(() => _coverPrivateView = false);
    // Wait for the next frame without the Flutter cover before releasing the
    // native one. A scene can resume before Flutter paints its lock route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSwitcherProtection();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor != AppFormFactor.mobile) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _coverPrivateView,
          child: ExcludeFocus(
            excluding: _coverPrivateView,
            child: widget.child,
          ),
        ),
        if (_coverPrivateView)
          ColoredBox(color: context.colors.background.window),
      ],
    );
  }
}
