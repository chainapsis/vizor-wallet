import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/layout/content_overlay_inset.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/features/onboarding/create/customise_account_screen.dart';
import '../src/features/onboarding/import/import_split_view.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_claim_account_sheet.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';

Widget buildDesktopGiftReceivingAccountUseCase(BuildContext context) =>
    const _RecipientCapture();
Widget buildDesktopGiftReceivingManyAccountsUseCase(BuildContext context) =>
    const _RecipientCapture(count: 8);
Widget buildDesktopGiftReceivingPendingUseCase(BuildContext context) =>
    const _RecipientCapture(pending: true);
Widget buildDesktopGiftReceivingErrorUseCase(BuildContext context) =>
    const _RecipientCapture(failed: true);

/// Drives production modal content and confirmation with local adapters.
class _RecipientCapture extends StatefulWidget {
  const _RecipientCapture({
    this.count = 2,
    this.pending = false,
    this.failed = false,
  });
  final int count;
  final bool pending;
  final bool failed;

  @override
  State<_RecipientCapture> createState() => _RecipientCaptureState();
}

class _RecipientCaptureState extends State<_RecipientCapture> {
  final _pending = Completer<void>();
  late final _router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, _) => _screen(context))],
  );

  @override
  void initState() {
    super.initState();
    _pressButton('customise_account_finish_button');
    if (widget.pending || widget.failed) {
      _pressButton('payment_link_claim_account_confirm');
    }
  }

  void _pressButton(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppButton? target;
      void collect(Element element) {
        if (element.widget case final AppButton button
            when button.key == ValueKey(key)) {
          target = button;
        }
        element.visitChildren(collect);
      }

      context.visitChildElements(collect);
      assert(target?.onPressed != null, 'Capture must drive the real $key.');
      target?.onPressed?.call();
    });
  }

  Widget _choice() => PaymentLinkClaimAccountSheet(
    amountZatoshi: BigInt.from(10000000),
    accounts: [
      for (var i = 0; i < widget.count; i++)
        AccountInfo(
          uuid: 'imported-$i',
          name: i == 0 ? 'Main account' : 'Imported account ${i + 1}',
          order: i,
        ),
    ],
    activeAccountUuid: 'imported-0',
    onConfirm: (_) async {
      if (widget.failed) throw StateError('Capture recipient unavailable');
      if (widget.pending) await _pending.future;
    },
    onConfirmed: () {},
    onClose: () {},
  );

  // Keep the real dialog content inside the capture boundary. A root Navigator
  // dialog is painted outside that boundary by the comparison app.
  Widget _screen(BuildContext context) => Stack(
    children: [
      ImportOnboardingShell(
        activeStep: ImportOnboardingStep.customiseAccount,
        showPasswordStep: true,
        child: CustomiseAccountScreen(
          random: Random(1234),
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.importWallet(
              mnemonic: 'capture-only',
              birthdayHeight: 3000000,
            ),
            pendingPassword: 'PreviewPassword1!',
          ),
          onFinish: (_, _) => _pending.future,
        ),
      ),
      const Positioned.fill(child: ColoredBox(color: Color(0x8A000000))),
      ContentPaneCenteringPadding(child: Center(child: _choice())),
    ],
  );

  @override
  void dispose() {
    // The fake pending confirmation deliberately lasts until the fixture ends.
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.macosUtility.window,
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_CaptureAccounts.new),
        appSecurityProvider.overrideWith(_CaptureSecurity.new),
      ],
      child: Router(
        routerDelegate: _router.routerDelegate,
        routeInformationParser: _router.routeInformationParser,
        routeInformationProvider: _router.routeInformationProvider,
      ),
    ),
  );
}

class _CaptureAccounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState();
}

class _CaptureSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}
