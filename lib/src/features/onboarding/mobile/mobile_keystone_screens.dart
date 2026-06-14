import 'dart:async';
import 'dart:math' as math;

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
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart' show ScanResult;
import '../../about/about_content.dart' show launchAboutUrl;
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../keystone/keystone_onboarding_flow.dart'
    show
        KeystoneOnboardingStep,
        KeystoneOnboardingStepX,
        keystoneOnboardingProvider;
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_birthday_screen.dart';
import 'mobile_onboarding_scaffold.dart';

const _keystoneFirmwareUrl = 'https://keyst.one/firmware';

/// Step 1 — Figma `Keystone 1` (4654:71439): firmware check and the
/// connect preparation steps.
class MobileKeystoneIntroScreen extends StatelessWidget {
  const MobileKeystoneIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: 0.2,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Connect Keystone',
      subtitle: 'Prepare your Keystone wallet',
      bottomArea: AppButton(
        key: const ValueKey('mobile_keystone_intro_continue'),
        expand: true,
        onPressed: () =>
            context.push(KeystoneOnboardingStep.scanQrCode.routePath),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: const Text('Continue'),
      ),
      child: Container(
        width: double.infinity,
        // Same surface-card rhythm as the onboarding info cards: 20 px
        // sides, 44 px vertical, 16 below a heading, 36 around the
        // divider.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(
              iconName: AppIcons.importWallet,
              title: '1. Check Keystone firmware',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Check if your Keystone device has the latest version of the '
              'Cypherpunk firmware, update or install if needed.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Semantics(
              button: true,
              link: true,
              label: 'Keystone firmware link',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(launchAboutUrl(_keystoneFirmwareUrl)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.link,
                      size: AppIconSize.medium,
                      color: colors.icon.accent,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Keystone firmware',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Container(height: 1, color: colors.border.subtle),
            ),
            _SectionHeading(
              iconName: AppIcons.qr,
              title: '2. Prepare to connect',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, step) in const [
              'Unlock your Keystone.',
              'Tap the ... menu, then go to Sync.',
              'Open the Zcash QR code in order to connect.',
              'Allow camera access when prompted and scan the QR code '
                  'with your phone.',
            ].indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xxs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${i + 1}.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      step,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.iconName, required this.title});

  final String iconName;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        AppIcon(iconName, size: 24, color: colors.icon.accent),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            title,
            style: AppTypography.bodyLarge.copyWith(color: colors.text.accent),
          ),
        ),
      ],
    );
  }
}

/// Step 2 — Figma `Keystone Scan 1-3` / `Scan Widget` / `Scan Error`:
/// the shared scanner card handles camera permission states and the
/// animated-UR progress; this screen decodes the completed payload.
class MobileKeystoneScanScreen extends ConsumerStatefulWidget {
  const MobileKeystoneScanScreen({super.key});

  @override
  ConsumerState<MobileKeystoneScanScreen> createState() =>
      _MobileKeystoneScanScreenState();
}

class _MobileKeystoneScanScreenState
    extends ConsumerState<MobileKeystoneScanScreen> {
  static const _cameraMaxHeight = 464.0;

  bool _decoding = false;
  String? _error;

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
    });

    try {
      final accounts = await rust_keystone.decodeAccountsFromCbor(
        cbor: result.data,
      );
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _decoding = false;
          _error = 'No Zcash accounts were found on this Keystone QR.';
        });
        return;
      }

      ref.read(keystoneOnboardingProvider.notifier).setAccounts(accounts);
      context.push(KeystoneOnboardingStep.selectAccount.routePath);
      if (mounted) setState(() => _decoding = false);
    } catch (e, st) {
      log('MobileKeystoneScan: account decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error =
            'This QR code could not be decoded as a Keystone Zcash account.';
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the Zcash account QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.4,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Scan QR Code',
      subtitle: 'Prepare your Keystone wallet',
      scrollable: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? math.max(0.0, constraints.maxHeight)
              : _cameraMaxHeight;
          final cameraHeight = math.min(_cameraMaxHeight, availableHeight);
          return Align(
            alignment: Alignment.topCenter,
            child: KeystoneQrScannerCard(
              key: const ValueKey('mobile_keystone_scan_card'),
              expectedUrType: 'zcash-accounts',
              decoding: _decoding,
              error: _error,
              // The Keystone Scan frames run the card edge-to-edge inside the
              // 16 px content inset, as a single 464 px rounded camera card
              // (Figma `Camera` 4654:72631 — no inner frame on mobile). Shorter
              // phones keep the page fixed and shrink only this viewport.
              cardWidth: double.infinity,
              cameraHeight: cameraHeight,
              onProgress: (progress) {
                if (!mounted) return;
                setState(() {
                  if (progress > 0) _error = null;
                });
              },
              onDecodeError: _handleDecodeError,
              onComplete: _handleScanComplete,
              decodingLabel: 'Reading accounts...',
              unavailableMessage:
                  'A camera is required to connect Keystone. You can revert '
                  'this in settings anytime later.',
            ),
          );
        },
      ),
    );
  }
}

/// Step 3 — Figma `Leystone Select Account` (4654:73917): the accounts
/// decoded from the QR with radio selection.
class MobileKeystoneSelectAccountScreen extends ConsumerWidget {
  const MobileKeystoneSelectAccountScreen({super.key});

  String _truncate(String value) {
    if (value.length <= 26) return value;
    return '${value.substring(0, 12)} ... ${value.substring(value.length - 10)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(keystoneOnboardingProvider);
    final accounts = state.accounts;
    final selected = state.selectedAccount;

    if (accounts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        GoRouter.maybeOf(
          context,
        )?.go(KeystoneOnboardingStep.scanQrCode.routePath);
      });
    }

    return MobileOnboardingStepScaffold(
      progress: 0.6,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Select account',
      subtitle: 'Prepare your Keystone wallet',
      bottomArea: AppButton(
        key: const ValueKey('mobile_keystone_select_continue'),
        expand: true,
        onPressed: selected == null
            ? null
            : () => context.push(
                KeystoneOnboardingStep.walletBirthdayHeight.routePath,
              ),
        child: const Text('Select account'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${accounts.length} account${accounts.length == 1 ? '' : 's'} '
            'found',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          for (final account in accounts) ...[
            _AccountCard(
              name: account.name,
              detail: _truncate(account.ufvk),
              selected: account == selected,
              onTap: () => ref
                  .read(keystoneOnboardingProvider.notifier)
                  .selectAccount(account),
            ),
            // 10 px card gap measured from the Select Account frame
            // (76 px row pitch with the 66 px card).
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.subtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              AppIcon(AppIcons.user, size: 20, color: colors.icon.muted),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (selected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.background.inverse,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.check,
                      size: 14,
                      color: colors.text.inverse,
                    ),
                  ),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.raised,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 4 — Figma `Keystone 2` / `Keystone 2 Calendar`: the shared
/// birthday screen confirming into the Keystone import instead of the
/// software-mnemonic path.
class MobileKeystoneBirthdayScreen extends ConsumerWidget {
  const MobileKeystoneBirthdayScreen({super.key});

  Future<void> _confirm(BuildContext context, WidgetRef ref, int height) async {
    final account = ref.read(keystoneOnboardingProvider).selectedAccount;
    if (account == null) {
      if (context.mounted) {
        context.go(KeystoneOnboardingStep.selectAccount.routePath);
      }
      return;
    }

    final security = ref.read(appSecurityProvider);
    if (!security.isPasswordConfigured) {
      if (!context.mounted) return;
      context.push(
        '/onboarding/set-passcode',
        extra: SetPasswordScreenArgs.importKeystone(
          name: account.name,
          ufvk: account.ufvk,
          seedFingerprint: account.seedFingerprint.toList(),
          zip32Index: account.index,
          birthdayHeight: height,
        ),
      );
      return;
    }

    // Add-account path: a passcode already guards the wallet, so the
    // hardware account imports right here (same as desktop).
    final router = GoRouter.of(context);
    final accountNotifier = ref.read(accountProvider.notifier);
    await runWithSyncPausedForAccountMutation(
      ref,
      () => accountNotifier.importKeystoneAccount(
        name: account.name,
        ufvk: account.ufvk,
        seedFingerprint: account.seedFingerprint.toList(),
        zip32Index: account.index,
        birthdayHeight: height,
      ),
    );
    ref.read(keystoneOnboardingProvider.notifier).resetScan();
    router.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MobileImportBirthdayScreen(
      args: const ImportBirthdayArgs(mnemonic: ''),
      onHeightConfirmed: (height) => _confirm(context, ref, height),
    );
  }
}
