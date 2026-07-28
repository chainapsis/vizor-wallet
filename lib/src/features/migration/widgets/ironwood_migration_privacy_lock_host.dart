import 'dart:async';

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_form_factor.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/app_security_provider.dart';
import '../../onboarding/shared/onboarding_auth_shell.dart';
import '../../onboarding/unlock_screen.dart';
import '../providers/ironwood_migration_privacy_lock_provider.dart';

const ironwoodMigrationVirtualUnlockScreenKey = ValueKey<String>(
  'ironwood_migration_virtual_unlock_screen',
);
const ironwoodMigrationInProgressBadgeKey = ValueKey<String>(
  'ironwood_migration_in_progress_badge',
);

class IronwoodMigrationPrivacyLockHost extends ConsumerStatefulWidget {
  const IronwoodMigrationPrivacyLockHost({
    required this.child,
    this.idleTimeout = kIronwoodMigrationPrivacyIdleTimeout,
    this.now,
    super.key,
  });

  final Widget child;
  final Duration idleTimeout;
  final DateTime Function()? now;

  @override
  ConsumerState<IronwoodMigrationPrivacyLockHost> createState() =>
      _IronwoodMigrationPrivacyLockHostState();
}

class _IronwoodMigrationPrivacyLockHostState
    extends ConsumerState<IronwoodMigrationPrivacyLockHost> {
  Timer? _idleTimer;
  AppLifecycleListener? _lifecycleListener;
  ProviderSubscription<bool>? _featureSubscription;
  late DateTime _lastInteractionAt;
  bool _featureEnabled = false;
  bool _wasEligible = false;

  @override
  void initState() {
    super.initState();
    _lastInteractionAt = _now();
    _featureSubscription = ref.listenManual(
      ironwoodMigrationPrivacyLockFeatureEnabledProvider,
      (_, enabled) => _setFeatureEnabled(enabled),
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_featureEnabled || kAppFormFactor != AppFormFactor.desktop) {
      return widget.child;
    }

    ref.listen(
      appSecurityProvider.select((security) => security.requiresUnlock),
      (_, requiresUnlock) {
        if (!requiresUnlock) return;
        _lastInteractionAt = _now();
        ref.read(ironwoodMigrationPrivacyLockProvider.notifier).clear();
      },
    );
    ref.listen(
      ironwoodMigrationPrivacyLockProvider.select((state) => state.isLocked),
      (wasLocked, isLocked) {
        if (wasLocked == true && !isLocked) {
          _lastInteractionAt = _now();
        }
      },
    );

    final eligible = ref.watch(ironwoodMigrationPrivacyLockEligibleProvider);
    final locked = ref.watch(
      ironwoodMigrationPrivacyLockProvider.select((state) => state.isLocked),
    );
    _syncIdleTimer(eligible: eligible, locked: locked);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markInteraction(),
      onPointerMove: (_) => _markInteraction(),
      onPointerHover: (_) => _markInteraction(),
      onPointerSignal: (_) => _markInteraction(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: locked,
            child: IgnorePointer(ignoring: locked, child: widget.child),
          ),
          if (locked)
            Positioned.fill(
              child: _PrivacyLockOverlay(
                child: IronwoodMigrationVirtualUnlockScreen(
                  key: ironwoodMigrationVirtualUnlockScreenKey,
                  showMigrationInProgress: eligible,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _featureSubscription?.close();
    _idleTimer?.cancel();
    _removePlatformListeners();
    super.dispose();
  }

  void _setFeatureEnabled(bool enabled) {
    final shouldEnable = enabled && kAppFormFactor == AppFormFactor.desktop;
    if (_featureEnabled == shouldEnable) return;
    _featureEnabled = shouldEnable;
    if (shouldEnable) {
      _lastInteractionAt = _now();
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      _lifecycleListener = AppLifecycleListener(
        onResume: _evaluateIdleAfterResume,
      );
    } else {
      _idleTimer?.cancel();
      _idleTimer = null;
      _wasEligible = false;
      _removePlatformListeners();
      ref.read(ironwoodMigrationPrivacyLockProvider.notifier).clear();
    }
    if (mounted) setState(() {});
  }

  void _removePlatformListeners() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  bool _handleKeyEvent(KeyEvent event) {
    _markInteraction();
    return false;
  }

  void _markInteraction() {
    if (!_featureEnabled ||
        !ref.read(ironwoodMigrationPrivacyLockEligibleProvider) ||
        ref.read(ironwoodMigrationPrivacyLockProvider).isLocked) {
      return;
    }
    _lastInteractionAt = _now();
    _armTimer();
  }

  void _syncIdleTimer({required bool eligible, required bool locked}) {
    if (!eligible) {
      _idleTimer?.cancel();
      _idleTimer = null;
      _wasEligible = false;
      return;
    }
    if (!_wasEligible) {
      _wasEligible = true;
      _lastInteractionAt = _now();
    }
    if (locked) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    _armTimer();
  }

  void _armTimer() {
    _idleTimer?.cancel();
    final elapsed = _now().difference(_lastInteractionAt);
    final remaining = widget.idleTimeout - elapsed;
    _idleTimer = Timer(
      remaining <= Duration.zero ? Duration.zero : remaining,
      _lockFromTimer,
    );
  }

  void _evaluateIdleAfterResume() {
    if (!_featureEnabled ||
        !ref.read(ironwoodMigrationPrivacyLockEligibleProvider) ||
        ref.read(ironwoodMigrationPrivacyLockProvider).isLocked) {
      return;
    }
    _lockIfStillIdle();
  }

  void _lockFromTimer() => _lockIfStillIdle(timerExpired: true);

  void _lockIfStillIdle({bool timerExpired = false}) {
    if (!mounted ||
        !_featureEnabled ||
        !ref.read(ironwoodMigrationPrivacyLockEligibleProvider) ||
        ref.read(ironwoodMigrationPrivacyLockProvider).isLocked) {
      return;
    }
    if (!timerExpired &&
        _now().difference(_lastInteractionAt) < widget.idleTimeout) {
      _armTimer();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(ironwoodMigrationPrivacyLockProvider.notifier).lock();
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();
}

class _PrivacyLockOverlay extends StatefulWidget {
  const _PrivacyLockOverlay({required this.child});

  final Widget child;

  @override
  State<_PrivacyLockOverlay> createState() => _PrivacyLockOverlayState();
}

class _PrivacyLockOverlayState extends State<_PrivacyLockOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_PrivacyLockOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entry]);
  }
}

class IronwoodMigrationVirtualUnlockScreen extends ConsumerStatefulWidget {
  const IronwoodMigrationVirtualUnlockScreen({
    this.showMigrationInProgress = true,
    super.key,
  });

  final bool showMigrationInProgress;

  @override
  ConsumerState<IronwoodMigrationVirtualUnlockScreen> createState() =>
      _IronwoodMigrationVirtualUnlockScreenState();
}

class _IronwoodMigrationVirtualUnlockScreenState
    extends ConsumerState<IronwoodMigrationVirtualUnlockScreen> {
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  String? get _passwordPolicyMessage =>
      validateWalletPassword(_passwordController.text);

  bool get _canSubmit =>
      !_isSubmitting && isWalletPasswordValid(_passwordController.text);

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final policyError = _passwordPolicyMessage;
    if (!isWalletPasswordValid(_passwordController.text)) {
      if (policyError == null) return;
      setState(() => _errorText = policyError);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    var confirmed = false;
    try {
      confirmed = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_passwordController.text);
    } catch (error, stackTrace) {
      log(
        'IronwoodMigrationVirtualUnlockScreen._submit: '
        'ERROR: $error\n$stackTrace',
      );
    }
    if (!mounted) return;

    if (confirmed) {
      ref.read(ironwoodMigrationPrivacyLockProvider.notifier).unlock();
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorText = 'Incorrect password. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            OnboardingAuthShell(
              card: OnboardingAuthCard(
                width: DesktopUnlockContent.cardWidth,
                height: DesktopUnlockContent.cardHeight,
                borderRadius: AppSpacing.base,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                child: DesktopUnlockContent(
                  passwordController: _passwordController,
                  canSubmit: _canSubmit,
                  messageText: _errorText ?? _passwordPolicyMessage,
                  autofocus: true,
                  showForgotPassword: false,
                  reserveForgotPasswordSpace: true,
                  onChanged: () => setState(() => _errorText = null),
                  onSubmit: _submit,
                ),
              ),
            ),
            if (widget.showMigrationInProgress)
              const Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(child: _MigrationInProgressBadge()),
              ),
          ],
        ),
      ),
    );
  }
}

class _MigrationInProgressBadge extends StatelessWidget {
  const _MigrationInProgressBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: ironwoodMigrationInProgressBadgeKey,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.full),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.shadow1,
            offset: const Offset(0, 2),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.shadow1,
            offset: const Offset(0, 10),
            blurRadius: 15,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 30,
                child: Center(
                  child: _MigrationLoader(color: colors.text.positiveStrong),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Migration in progress',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.positiveStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MigrationLoader extends StatefulWidget {
  const _MigrationLoader({required this.color});

  final Color color;

  @override
  State<_MigrationLoader> createState() => _MigrationLoaderState();
}

class _MigrationLoaderState extends State<_MigrationLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: AppIcon(
        AppIcons.ironwoodMigrationLoader,
        size: 28,
        color: widget.color,
        semanticLabel: 'Migration in progress',
      ),
    );
  }
}
