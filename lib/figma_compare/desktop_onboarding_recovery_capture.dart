import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/features/onboarding/create/customise_account_screen.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';

Widget buildDesktopSetupInterruptedCapture(BuildContext context) =>
    const _RecoveryCapture();
Widget buildDesktopSetupUncertainCapture(BuildContext context) =>
    const _RecoveryCapture(uncertain: true);
Widget buildDesktopSetupRetryErrorCapture(BuildContext context) =>
    const _RecoveryCapture(retry: true, reloadFails: true);
Widget buildDesktopSetupPendingCapture(BuildContext context) =>
    const _RecoveryCapture(retry: true);
Widget buildDesktopLedgerSetupInterruptedCapture(BuildContext context) =>
    const _RecoveryCapture(ledger: true);
Widget buildDesktopSetupOrdinaryErrorCapture(BuildContext context) =>
    const _RecoveryCapture(ordinaryError: true);

/// Drives the production submit callback with only local, scripted failures.
class _RecoveryCapture extends StatefulWidget {
  const _RecoveryCapture({
    this.uncertain = false,
    this.retry = false,
    this.reloadFails = false,
    this.ledger = false,
    this.ordinaryError = false,
  });

  final bool uncertain;
  final bool retry;
  final bool reloadFails;
  final bool ledger;
  final bool ordinaryError;

  @override
  State<_RecoveryCapture> createState() => _RecoveryCaptureState();
}

class _RecoveryCaptureState extends State<_RecoveryCapture> {
  final _reload = Completer<void>();
  late final _router = GoRouter(
    initialLocation: '/capture',
    routes: [GoRoute(path: '/capture', builder: (_, _) => _screen())],
  );

  @override
  void initState() {
    super.initState();
    _pressFinish(thenRetry: widget.retry);
  }

  void _pressFinish({bool thenRetry = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppButton? finish;
      void collect(Element element) {
        if (element.widget case final AppButton button
            when button.key ==
                const ValueKey('customise_account_finish_button')) {
          finish = button;
        }
        element.visitChildren(collect);
      }

      context.visitChildElements(collect);
      final action = finish?.onPressed;
      assert(action != null, 'The capture must drive the real finish button.');
      action?.call();
      if (thenRetry) _pressFinish();
    });
  }

  Future<void> _failSubmit(String _, String _) async {
    if (widget.ordinaryError) {
      throw Exception('Could not connect. Please try again.');
    }
    if (widget.uncertain) {
      throw WalletAccountStateUncertainException(StateError('Capture DB read'));
    }
    throw WalletAccountSetupInterruptedException(
      null,
      StateError('Capture storage write'),
    );
  }

  Widget _screen() {
    if (widget.ledger) {
      return CustomiseAccountScreen.ledger(
        random: Random(1234),
        onFinish: _failSubmit,
        ledgerBackTarget: const OnboardingBackTarget.route(
          label: 'Set Password',
          routePath: '/capture-back',
        ),
      );
    }
    return OnboardingSplitViewShell(
      activeStep: OnboardingStep.customiseAccount,
      showPasswordStep: true,
      child: CustomiseAccountScreen(
        random: Random(1234),
        args: const CustomiseAccountArgs(
          setupArgs: SetPasswordScreenArgs.create(mnemonic: 'capture-only'),
          pendingPassword: 'PreviewPassword1!',
        ),
        onFinish: _failSubmit,
      ),
    );
  }

  @override
  void dispose() {
    if (!_reload.isCompleted) _reload.complete();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.macosUtility.window,
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        appSecurityProvider.overrideWith(_CaptureSecurity.new),
        appBootstrapRetryProvider.overrideWithValue(() {
          if (widget.reloadFails) throw StateError('Capture bootstrap failure');
          return _reload.future;
        }),
      ],
      child: Router.withConfig(config: _router),
    ),
  );
}

class _CaptureSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  void lock() => state = state.copyWith(isUnlocked: false);
}
