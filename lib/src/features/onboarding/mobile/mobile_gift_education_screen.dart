import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import 'mobile_create_steps.dart';

enum GiftEducationPage { intro, addressTypes, thingsToKnow }

/// The existing Zcash education, offered after a Gift Card wallet reaches
/// Home. Leaving a page keeps the Home entry; only Skip or the final Continue
/// marks the account's education complete.
class MobileGiftEducationScreen extends ConsumerStatefulWidget {
  const MobileGiftEducationScreen({
    required this.page,
    this.accountUuid,
    super.key,
  });

  final GiftEducationPage page;
  final String? accountUuid;

  @override
  ConsumerState<MobileGiftEducationScreen> createState() =>
      _MobileGiftEducationScreenState();
}

class _MobileGiftEducationScreenState
    extends ConsumerState<MobileGiftEducationScreen> {
  bool _finishing = false;
  String? _accountUuid;
  @override
  void initState() {
    super.initState();
    _accountUuid =
        widget.accountUuid ??
        ref.read(accountProvider).value?.activeAccountUuid;
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final account = ref
        .read(accountProvider)
        .value
        ?.accounts
        .where((a) => a.uuid == _accountUuid)
        .firstOrNull;
    if (account == null || !account.giftEducationPending) {
      context.go('/home');
      return;
    }
    setState(() => _finishing = true);
    try {
      await ref
          .read(accountProvider.notifier)
          .markGiftEducationComplete(account.uuid);
      if (mounted &&
          GoRouter.of(
            context,
          ).state.matchedLocation.startsWith('/setup/education/')) {
        context.go('/home');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _finishing = false);
      showAppToast(
        context,
        'Unable to save your progress. Try again.',
        iconName: AppIcons.warning,
        tone: AppToastTone.destructive,
      );
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.page) {
    GiftEducationPage.intro => MobileOnboardingIntroScreen(
      showProgress: false,
      onBack: _back,
      actionsEnabled: !_finishing,
      onContinue: () =>
          context.push('/setup/education/address-types', extra: _accountUuid),
      closingText:
          'Your wallet is ready. Learn how Zcash protects your privacy and '
          'which address to use.',
      onSkip: _finish,
    ),
    GiftEducationPage.addressTypes => MobileAddressTypesScreen(
      showProgress: false,
      onBack: _back,
      actionsEnabled: !_finishing,
      onContinue: () =>
          context.push('/setup/education/things-to-know', extra: _accountUuid),
    ),
    GiftEducationPage.thingsToKnow => MobileThingsToKnowScreen(
      showProgress: false,
      onBack: _back,
      actionsEnabled: !_finishing,
      onContinue: _finish,
    ),
  };
}
