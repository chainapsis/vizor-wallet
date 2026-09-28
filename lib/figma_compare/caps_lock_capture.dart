// ignore_for_file: depend_on_referenced_packages
// Uses real screen widgets and an in-memory Caps Lock state; no native input IO.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/features/swap/providers/swap_activity_store.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart';
import '../src/core/input/caps_lock_monitor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/onboarding/shared/set_password_screen.dart';
import '../widgetbook/screen_use_cases.dart';

Widget buildCapsLockUnlockCapture(BuildContext context) =>
    _CapsLockCapture(builder: buildUnlockLoginUseCase);
Widget buildCapsLockSetPasswordCapture(BuildContext context) =>
    _CapsLockCapture(builder: (_) => const _SetPasswordCapture());
Widget buildCapsLockConfirmPasswordCapture(BuildContext context) =>
    _CapsLockCapture(
      builder: (_) => const _SetPasswordCapture(),
      focusIndex: 1,
    );
Widget buildCapsLockSettingsCapture(BuildContext context) =>
    _CapsLockCapture(builder: buildSettingsChangePasswordGateUseCase);
Widget buildCapsLockRemoveAccountCapture(BuildContext context) =>
    _CapsLockCapture(builder: buildAccountsRemoveUseCase, focusIndex: 0);

class _CapsLockCapture extends StatefulWidget {
  const _CapsLockCapture({required this.builder, this.focusIndex});
  final WidgetBuilder builder;
  final int? focusIndex;

  @override
  State<_CapsLockCapture> createState() => _CapsLockCaptureState();
}

class _CapsLockCaptureState extends State<_CapsLockCapture> {
  final _monitor = CapsLockMonitor(enabled: false)..value = true;

  @override
  void initState() {
    super.initState();
    if (widget.focusIndex != null) _focusField();
  }

  void _focusField([int attempts = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editors = <EditableText>[];
      void collect(Element element) {
        if (element.widget is EditableText) {
          editors.add(element.widget as EditableText);
        }
        element.visitChildren(collect);
      }

      context.visitChildElements(collect);
      final index = widget.focusIndex!;
      if (editors.length > index && editors[index].focusNode.canRequestFocus) {
        editors[index].focusNode.requestFocus();
      } else if (attempts < 4) {
        // Account fixtures resolve their in-memory account/check state first.
        _focusField(attempts + 1);
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    });
  }

  @override
  void dispose() {
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(_CaptureAccount.new),
      syncProvider.overrideWith(_CaptureSync.new),
      swapPendingIntentCountProvider.overrideWith((ref, _) async => 0),
      paymentLinkReceivingCountProvider.overrideWith((ref, _) async => 0),
      capsLockMonitorProvider.overrideWithValue(_monitor),
    ],
    child: Builder(builder: widget.builder),
  );
}

class _SetPasswordCapture extends StatefulWidget {
  const _SetPasswordCapture();

  @override
  State<_SetPasswordCapture> createState() => _SetPasswordCaptureState();
}

class _SetPasswordCaptureState extends State<_SetPasswordCapture> {
  late final _router = GoRouter(
    initialLocation: OnboardingStep.setPassword.routePath,
    routes: [
      GoRoute(
        path: OnboardingStep.setPassword.routePath,
        builder: (_, _) => const OnboardingSplitViewShell(
          activeStep: OnboardingStep.setPassword,
          showPasswordStep: true,
          child: SetPasswordScreen(
            args: SetPasswordScreenArgs.create(
              mnemonic:
                  'abandon abandon abandon abandon abandon abandon '
                  'abandon abandon abandon abandon abandon about',
            ),
          ),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.macosUtility.window,
    child: Router.withConfig(config: _router),
  );
}

// Providers without declared scoping dependencies can resolve at the outer
// capture scope; keep those reads isolated too, not just the inner fixtures.
class _CaptureAccount extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState();
}

class _CaptureSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
}
