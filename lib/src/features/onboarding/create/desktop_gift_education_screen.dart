import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../shared/onboarding_chrome.dart';
import 'address_types_screen.dart';
import 'intro_zcash_screen.dart';
import 'onboarding_split_view.dart';
import 'things_to_know_screen.dart';

enum DesktopGiftEducationPage { intro, addressTypes, thingsToKnow }

/// Offers the existing education after setup, with progress pinned to its account.
class DesktopGiftEducationScreen extends ConsumerStatefulWidget {
  const DesktopGiftEducationScreen({
    required this.page,
    required this.accountUuid,
    super.key,
  });

  final DesktopGiftEducationPage page;
  final String? accountUuid;

  @override
  ConsumerState<DesktopGiftEducationScreen> createState() =>
      _DesktopGiftEducationScreenState();
}

class _DesktopGiftEducationScreenState
    extends ConsumerState<DesktopGiftEducationScreen> {
  late final String? _accountUuid;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accountUuid =
        widget.accountUuid ??
        ref.read(accountProvider).value?.activeAccountUuid;
  }

  Future<void> _finish() async {
    if (_saving) return;
    final account = ref
        .read(accountProvider)
        .value
        ?.accounts
        .where((account) => account.uuid == _accountUuid)
        .firstOrNull;
    if (account == null || !account.giftEducationPending) {
      context.go('/home');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(accountProvider.notifier)
          .markGiftEducationComplete(account.uuid);
      if (mounted &&
          GoRouter.of(context).state.uri.path.startsWith('/setup/education/')) {
        context.go('/home');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(
        context,
        'Unable to save your progress. Try again.',
        iconName: AppIcons.warning,
        tone: AppToastTone.destructive,
      );
    }
  }

  void _open(String path) => context.push(path, extra: _accountUuid);

  @override
  Widget build(BuildContext context) {
    final step = switch (widget.page) {
      DesktopGiftEducationPage.intro => OnboardingStep.intro,
      DesktopGiftEducationPage.addressTypes => OnboardingStep.addressTypes,
      DesktopGiftEducationPage.thingsToKnow => OnboardingStep.thingsToKnow,
    };
    final backTarget = OnboardingBackTarget.route(
      label: 'Home',
      routePath: '/home',
    );
    final content = switch (widget.page) {
      DesktopGiftEducationPage.intro => IntroZcashScreen(
        resetCreateDraft: false,
        backTarget: backTarget,
        actionsEnabled: !_saving,
        closingText:
            'Your wallet is ready. Learn how Zcash protects your '
            'privacy and which address to use.',
        onContinue: () => _open('/setup/education/address-types'),
        onSkip: _finish,
      ),
      DesktopGiftEducationPage.addressTypes => AddressTypesScreen(
        backTarget: backTarget,
        actionsEnabled: !_saving,
        onContinue: () => _open('/setup/education/things-to-know'),
      ),
      DesktopGiftEducationPage.thingsToKnow => ThingsToKnowScreen(
        backTarget: backTarget,
        actionsEnabled: !_saving,
        onContinue: _finish,
      ),
    };
    final theme = context.appTheme == AppThemeData.dark ? 'dark' : 'light';
    final illustration = switch (widget.page) {
      DesktopGiftEducationPage.intro => 'intro',
      DesktopGiftEducationPage.addressTypes => 'wallet_details',
      DesktopGiftEducationPage.thingsToKnow => 'things_to_know',
    };
    return AppDesktopShell(
      backgroundColor: context.colors.background.window,
      sidebar: OnboardingSidebarChrome(
        steps: [
          for (final item in [
            OnboardingStep.intro,
            OnboardingStep.addressTypes,
            OnboardingStep.thingsToKnow,
          ])
            OnboardingSidebarStepData(
              label: item.label,
              iconName: item.iconName,
              active: item == step,
            ),
        ],
        illustration: Align(
          alignment: Alignment.bottomCenter,
          child: Image.asset(
            'assets/illustrations/desktop/onboarding_${illustration}_sidebar_$theme.webp',
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
      pane: content,
    );
  }
}
