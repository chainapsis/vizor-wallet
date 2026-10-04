import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/app_security_provider.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';

/// Mobile-only route metadata. The existing setup payload remains unchanged.
class MobileOnboardingRouteArgs {
  const MobileOnboardingRouteArgs({required this.setupMode, this.payload});
  final OnboardingSetupMode setupMode;
  final Object? payload;
}

Object? mobileOnboardingPayload(Object? extra) =>
    extra is MobileOnboardingRouteArgs ? extra.payload : extra;

/// Each route owns its immutable setup condition, including direct entries.
class MobileOnboardingProgressFrame extends ConsumerStatefulWidget {
  const MobileOnboardingProgressFrame({
    required this.child,
    this.setupMode,
    super.key,
  });
  final OnboardingSetupMode? setupMode;
  final Widget child;

  @override
  ConsumerState<MobileOnboardingProgressFrame> createState() =>
      _MobileOnboardingProgressFrameState();
}

class _MobileOnboardingProgressFrameState
    extends ConsumerState<MobileOnboardingProgressFrame> {
  late final _initialMode =
      widget.setupMode ??
      (ref.read(appSecurityProvider).isPasswordConfigured
          ? OnboardingSetupMode.reusePasscode
          : OnboardingSetupMode.createPasscode);

  @override
  Widget build(BuildContext context) => MobileOnboardingProgressScope(
    setupMode: widget.setupMode ?? _initialMode,
    child: widget.child,
  );
}

/// Also used by deterministic standalone previews and component tests.
class MobileOnboardingProgressScope extends InheritedWidget {
  const MobileOnboardingProgressScope({
    required this.setupMode,
    required super.child,
    super.key,
  });
  final OnboardingSetupMode setupMode;

  static MobileOnboardingProgressScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MobileOnboardingProgressScope>();
    if (scope == null) {
      throw StateError('Mobile onboarding requires a progress scope.');
    }
    return scope;
  }

  OnboardingProgressPosition at(OnboardingFlow flow, OnboardingStage stage) =>
      OnboardingProgressPlan.forFlow(flow, setupMode: setupMode).at(stage);

  @override
  bool updateShouldNotify(MobileOnboardingProgressScope oldWidget) =>
      setupMode != oldWidget.setupMode;
}

OnboardingFlow onboardingFlowForSetup(SetPasswordFlow flow) => switch (flow) {
  SetPasswordFlow.create => OnboardingFlow.create,
  SetPasswordFlow.importWallet => OnboardingFlow.importWallet,
  SetPasswordFlow.importKeystone => OnboardingFlow.keystone,
  SetPasswordFlow.importLedger => OnboardingFlow.ledger,
  SetPasswordFlow.importWalletLink => OnboardingFlow.walletLink,
};

/// Preserve the setup snapshot and the existing push result/route history.
extension MobileOnboardingNavigation on BuildContext {
  Future<T?> startOnboarding<T extends Object?>(String location) {
    final security = ProviderScope.containerOf(
      this,
      listen: false,
    ).read(appSecurityProvider);
    return push<T>(
      location,
      extra: MobileOnboardingRouteArgs(
        setupMode: security.isPasswordConfigured
            ? OnboardingSetupMode.reusePasscode
            : OnboardingSetupMode.createPasscode,
      ),
    );
  }

  Future<T?> pushOnboarding<T extends Object?>(
    String location, {
    Object? extra,
  }) => push<T>(location, extra: _onboardingArgs(extra));

  void goOnboarding(String location, {Object? extra}) =>
      go(location, extra: _onboardingArgs(extra));

  MobileOnboardingRouteArgs _onboardingArgs(Object? payload) =>
      MobileOnboardingRouteArgs(
        setupMode: MobileOnboardingProgressScope.of(this).setupMode,
        payload: payload,
      );
}
