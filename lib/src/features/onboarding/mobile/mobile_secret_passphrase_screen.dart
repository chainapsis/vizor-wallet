import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../create/onboarding_split_view.dart'
    show
        clearCreateOnboardingSecretState,
        createOnboardingMnemonicProvider,
        onboardingSecretPassphraseRevealedProvider;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_create_steps.dart';
import 'mobile_onboarding_scaffold.dart';
import 'seed_card.dart';

/// Mobile create-flow passphrase step — Figma `Onboarding 4 Secret
/// Phrase` (4394:81938 hidden / 4394:82007 revealed). Mirrors the
/// desktop screen's logic: the mnemonic survives back navigation via
/// [createOnboardingMnemonicProvider]; continue either pushes the
/// passcode step (first wallet) or creates the account directly when a
/// password is already configured (add-account).
class MobileSecretPassphraseScreen extends ConsumerStatefulWidget {
  const MobileSecretPassphraseScreen({this.args, super.key});

  final CreateSecretPassphraseArgs? args;

  @override
  ConsumerState<MobileSecretPassphraseScreen> createState() =>
      _MobileSecretPassphraseScreenState();
}

class _MobileSecretPassphraseScreenState
    extends ConsumerState<MobileSecretPassphraseScreen> {
  String? _mnemonic;
  bool _revealed = false;
  bool _copied = false;
  bool _submitting = false;
  String? _error;
  Timer? _copyResetTimer;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args != null) {
      _mnemonic = args.mnemonic;
      _revealed = true;
      return;
    }
    final existing = ref.read(createOnboardingMnemonicProvider);
    if (existing != null) {
      _mnemonic = existing;
      _revealed = ref.read(onboardingSecretPassphraseRevealedProvider);
      return;
    }
    try {
      final mnemonic = rust_wallet.generateMnemonic();
      _mnemonic = mnemonic;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(createOnboardingMnemonicProvider.notifier)
            .setMnemonic(mnemonic);
      });
    } catch (e, st) {
      log('MobileSecretPassphrase: ERROR generating mnemonic: $e\n$st');
      _error = onboardingSubmitErrorMessage(e);
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null || !_revealed) return;
    await Clipboard.setData(ClipboardData(text: mnemonic));
    if (!mounted) return;
    _copyResetTimer?.cancel();
    setState(() => _copied = true);
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _continue() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null || _submitting) return;
    if (!_revealed) {
      setState(() => _revealed = true);
      ref
          .read(onboardingSecretPassphraseRevealedProvider.notifier)
          .setRevealed(true);
      return;
    }

    final security = ref.read(appSecurityProvider);
    if (!security.isPasswordConfigured) {
      context.push(
        '/onboarding/set-passcode',
        extra: SetPasswordScreenArgs.create(mnemonic: mnemonic),
      );
      return;
    }

    // Add-account path: a passcode already guards the wallet, so the
    // account is created right here.
    setState(() {
      _submitting = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    final accountNotifier = ref.read(accountProvider.notifier);
    try {
      await runWithSyncPausedForAccountMutation(
        ref,
        () => accountNotifier.createAccountFromMnemonic(mnemonic: mnemonic),
      );
    } catch (e, st) {
      log('MobileSecretPassphrase: ERROR creating account: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = onboardingSubmitErrorMessage(e);
      });
      return;
    }
    if (mounted) {
      clearCreateOnboardingSecretState(ref.read);
    }
    router.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = _mnemonic?.split(' ') ?? const <String>[];

    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(4),
      onBack: _submitting ? null : () => Navigator.of(context).maybePop(),
      title: 'Secret Passphrase',
      subtitle: 'The Master Key to your wallet.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            key: const ValueKey('mobile_secret_passphrase_primary'),
            expand: true,
            onPressed: _error != null || _submitting ? null : _continue,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: Text(
              _submitting
                  ? 'Creating wallet...'
                  : _revealed
                  ? 'Continue'
                  : 'Reveal phrase',
            ),
          ),
        ],
      ),
      child: _revealed
          ? SeedCard(
              words: words,
              onCopy: _copy,
              copied: _copied,
            )
          : const _RevealWarningCard(),
    );
  }
}

/// Pre-reveal warning card — Figma `Onboarding 4 Secret Phrase` hidden
/// variant: the words stay off-screen entirely; a centered key badge,
/// headline, and caution paragraph fill the dark card instead.
class _RevealWarningCard extends StatelessWidget {
  const _RevealWarningCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 440),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.background.brandCrimsonStrong,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Center(
              child: AppIcon(
                AppIcons.key,
                size: 24,
                color: colors.text.homeCard,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'You are about to see your\nSecret Passphrase.',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.homeCard,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              'This phrase is the master key to your funds. Keep it safe, '
              'keep it secret. If you lose it, no one can help you recover '
              'your wallet. Not even us.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.homeCard.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
