import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_security_provider.dart';
import '../../providers/flip_to_hide_balance_provider.dart';
import '../../providers/privacy_mode_provider.dart';
import '../../providers/wallet_provider.dart';
import '../feedback/app_haptics.dart';
import '../l10n/l10n.dart';
import '../layout/app_form_factor.dart';
import '../platform/screen_facing.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_toast.dart';
import 'flip_to_hide_detector.dart';

/// Flip to hide (mobile): turning the phone screen-down hides amounts on any
/// screen, and a quick flip down and back up shows them again
/// ([FlipToHideDetector]). It switches privacy mode, as the Home eye button
/// does. The motion sensor runs only while the app is visible, a wallet is
/// unlocked, and the Settings switch is on.
///
/// Mounted in the wallet's root shell route (`buildMobileRoutes`), so it
/// covers every wallet page and its toast shows in the root overlay, above
/// pushed pages and sheets.
class FlipToHideBalanceHost extends ConsumerStatefulWidget {
  const FlipToHideBalanceHost({
    required this.child,
    this.facingEvents = screenFacingEvents,
    super.key,
  });

  final Widget child;

  /// The sensor readings; tests pass their own.
  final Stream<double> Function() facingEvents;

  @override
  ConsumerState<FlipToHideBalanceHost> createState() =>
      _FlipToHideBalanceHostState();
}

class _FlipToHideBalanceHostState extends ConsumerState<FlipToHideBalanceHost> {
  AppLifecycleListener? _listener;
  StreamSubscription<double>? _subscription;
  final _clock = Stopwatch();
  bool _visible = true;
  int _sensorSession = 0;

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor != AppFormFactor.mobile) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _visible =
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.detached;
    _listener = AppLifecycleListener(
      onShow: () {
        _visible = true;
        _update();
      },
      onHide: () {
        _visible = false;
        _update();
      },
    );
    ref.listenManual(flipToHideBalanceProvider, (_, _) => _update());
    ref.listenManual(appSecurityProvider, (_, _) => _update());
    ref.listenManual(walletProvider, (_, _) => _update());
    _update();
  }

  @override
  void dispose() {
    ++_sensorSession;
    _listener?.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  bool get _shouldListen {
    if (!_visible || !ref.read(flipToHideBalanceProvider)) return false;
    final security = ref.read(appSecurityProvider);
    return security.isPasswordConfigured &&
        security.isUnlocked &&
        (ref.read(walletProvider).value?.hasWallet ?? false);
  }

  void _update() {
    if (!_shouldListen) {
      ++_sensorSession;
      unawaited(_subscription?.cancel());
      _subscription = null;
      _clock.stop();
      return;
    }
    if (_subscription != null) return;
    final session = ++_sensorSession;
    // A fresh detector each time: a phone already screen-down when listening
    // starts is not a flip.
    final detector = FlipToHideDetector();
    _clock
      ..reset()
      ..start();
    _subscription = widget.facingEvents().listen((facing) {
      if (session != _sensorSession || !_shouldListen) return;
      final action = detector.add(
        facing,
        at: _clock.elapsed,
        hidden: ref.read(privacyModeProvider.notifier).requestedHidden,
      );
      if (action != null) unawaited(_apply(action, session));
    });
  }

  Future<void> _apply(FlipToHideAction action, int session) async {
    final hide = action == FlipToHideAction.hide;
    final privacy = ref.read(privacyModeProvider.notifier);
    bool isActive() => mounted && session == _sensorSession && _shouldListen;
    final change = privacy.setFromFlip(hide, isActive: isActive);
    bool isCurrent() => isActive() && change.isCurrent;
    try {
      final applied = await change.completed;
      if (!applied || !isCurrent()) return;
    } catch (_) {
      if (!mounted || !isCurrent()) return;
      showAppToast(
        context,
        hide
            ? context.l10n.privacyBalanceHiddenSaveFailed
            : context.l10n.privacyBalanceShowFailed,
        iconName: AppIcons.warning,
        tone: AppToastTone.destructive,
      );
      return;
    }
    if (!mounted) return;
    unawaited(AppHaptics.privacyToggle());
    showAppToast(
      context,
      hide ? context.l10n.commonBalanceHidden : context.l10n.commonBalanceShown,
      iconName: hide ? AppIcons.eyeClosed : AppIcons.eye,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
