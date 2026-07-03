import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart'
    show AnimatedUrScannerView, ScanResult;
import '../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../about/about_content.dart' show launchAboutUrl;
import '../keystone/keystone_onboarding_flow.dart'
    show
        KeystoneOnboardingStep,
        KeystoneOnboardingStepX,
        keystoneOnboardingProvider;
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_birthday_screen.dart';
import 'mobile_keystone_scan_card.dart';
import 'mobile_onboarding_scaffold.dart';

const _keystoneFirmwareUrl = 'https://keyst.one/firmware';

/// Step 1 — Figma `Keystone 1` (4654:71439): firmware check and the
/// connect preparation steps.
class MobileKeystoneIntroScreen extends StatelessWidget {
  const MobileKeystoneIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.2,
      onBack: () => Navigator.of(context).maybePop(),
      title: AppLocalizations.of(context).navConnectKeystone,
      subtitle: AppLocalizations.of(context).keystonePrepareWallet,
      bottomArea: AppButton(
        key: const ValueKey('mobile_keystone_intro_continue'),
        expand: true,
        onPressed: () =>
            context.push(KeystoneOnboardingStep.scanQrCode.routePath),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: Text(AppLocalizations.of(context).commonContinue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KeystoneIntroCard(
            key: const ValueKey('mobile_keystone_intro_firmware_card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeading(
                  iconName: AppIcons.importWallet,
                  title: AppLocalizations.of(context).keystoneStepCheckFirmware,
                ),
                const SizedBox(height: AppSpacing.sm),
                const _FirmwareBodyWithLink(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _KeystoneIntroCard(
            key: const ValueKey('mobile_keystone_intro_prepare_card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeading(
                  iconName: AppIcons.qr,
                  title: AppLocalizations.of(context).keystoneStepPrepareConnect,
                ),
                const SizedBox(height: AppSpacing.sm),
                _StepGroupHeading(AppLocalizations.of(context).keystoneOnYourKeystone),
                const SizedBox(height: AppSpacing.xxs),
                for (final (i, step) in [
                  AppLocalizations.of(context).keystoneStepTapConnect,
                  AppLocalizations.of(context).keystoneStepSelectVizor,
                ].indexed)
                  _NumberedStep(
                    index: i + 1,
                    text: step,
                    isFirstInGroup: i == 0,
                  ),
                const SizedBox(height: AppSpacing.sm),
                _StepGroupHeading(AppLocalizations.of(context).keystoneOnVizor),
                const SizedBox(height: AppSpacing.xxs),
                _NumberedStep(
                  index: 3,
                  text: AppLocalizations.of(context).keystoneStepScanDynamicQr,
                  isFirstInGroup: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeystoneIntroCard extends StatelessWidget {
  const _KeystoneIntroCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: child,
      ),
    );
  }
}

class _FirmwareBodyWithLink extends StatelessWidget {
  const _FirmwareBodyWithLink();

  @override
  Widget build(BuildContext context) {
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: context.colors.text.primary,
    );
    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          TextSpan(text: AppLocalizations.of(context).keystoneFirmwareNote),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _FirmwareInlineLink(),
          ),
        ],
      ),
    );
  }
}

class _FirmwareInlineLink extends StatelessWidget {
  const _FirmwareInlineLink();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      link: true,
      label: AppLocalizations.of(context).keystoneDownloadFirmware,
      child: AppButton(
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.small,
        height: 24,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        iconGap: AppSpacing.xxs,
        leading: const AppIcon(AppIcons.link),
        onPressed: () => unawaited(launchAboutUrl(_keystoneFirmwareUrl)),
        child: Text(AppLocalizations.of(context).keystoneLink),
      ),
    );
  }
}

class _StepGroupHeading extends StatelessWidget {
  const _StepGroupHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodyMediumStrong.copyWith(
        color: context.colors.text.accent,
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({
    required this.index,
    required this.text,
    required this.isFirstInGroup,
  });

  final int index;
  final String text;
  final bool isFirstInGroup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.bodyMedium.copyWith(color: colors.text.primary);
    return Padding(
      padding: EdgeInsets.only(top: isFirstInGroup ? 0 : AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text('$index.', style: style)),
          Expanded(child: Text(text, style: style)),
        ],
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
  const MobileKeystoneScanScreen({this.scannerController, super.key});

  final MobileScannerController? scannerController;

  @override
  ConsumerState<MobileKeystoneScanScreen> createState() =>
      _MobileKeystoneScanScreenState();
}

class _MobileKeystoneScanScreenState
    extends ConsumerState<MobileKeystoneScanScreen> {
  bool _decoding = false;
  String? _error;
  int _scanProgress = 0;
  int _scanSessionResetToken = 0;

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
      _scanProgress = 100;
    });

    try {
      final accounts = await rust_keystone.decodeAccountsFromCbor(
        cbor: result.data,
      );
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _decoding = false;
          _error = AppLocalizations.of(context).keystoneNoZcashAccounts;
          _scanProgress = 0;
          _scanSessionResetToken++;
        });
        return;
      }

      ref.read(keystoneOnboardingProvider.notifier).setAccounts(accounts);
      if (mounted) setState(() => _decoding = false);
      // push() resolves when select-account pops back to this still-mounted
      // scan screen. Reset the UR session/progress on return so a second
      // Keystone QR can be scanned — otherwise the scanner stays in its
      // completed state and ignores new frames.
      await context.push(KeystoneOnboardingStep.selectAccount.routePath);
      if (!mounted) return;
      setState(() {
        _scanProgress = 0;
        _scanSessionResetToken++;
        _error = null;
      });
    } catch (e, st) {
      log('MobileKeystoneScan: account decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _scanProgress = 0;
        _scanSessionResetToken++;
        _error =
            AppLocalizations.of(context).keystoneAccountQrDecodeError;
      });
    }
  }

  void _handleScanProgress(int progress) {
    final clamped = progress.clamp(0, 100);
    if (!mounted || _scanProgress == clamped) return;
    setState(() {
      _scanProgress = clamped;
      if (clamped > 0) _error = null;
    });
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? AppLocalizations.of(context).keystoneOpenAccountQr
        : AppLocalizations.of(context).keystoneScanHoldSteady;
    if (_error == message) return;
    setState(() => _error = message);
  }

  String? get _scanCaptionOverride {
    if (_decoding) return AppLocalizations.of(context).keystoneReadingAccounts;
    if (_error != null) return _error;
    if (_scanProgress > 0 && _scanProgress < 100) {
      return AppLocalizations.of(context).keystoneScanningProgress(_scanProgress);
    }
    return null;
  }

  double _scanModalHeight(BuildContext context) {
    return MobileAddressScanCardContent.modalCameraHeight(context);
  }

  Widget _buildScanCard(double cameraHeight) {
    return MobileQrScanCard(
      key: const ValueKey('mobile_keystone_scan_card'),
      controller: widget.scannerController,
      cameraHeight: cameraHeight,
      caption: AppLocalizations.of(context).keystoneScanAccountQr,
      permissionTitle: AppLocalizations.of(context).keystoneScanQrTitle,
      error: _scanCaptionOverride,
      unavailableDescription: AppLocalizations.of(context).keystoneImportCameraOnly,
      onClose: () => Navigator.of(context).maybePop(),
      permissionBuilder:
          (context, status, unavailableDescription, onRetry, onClose) =>
              MobileKeystoneScanPermissionCard(
                status: status,
                unavailableDescription: unavailableDescription,
                onRetry: onRetry,
                cameraHeight: cameraHeight,
              ),
      cameraViewBuilder: (context, controller) => AnimatedUrScannerView(
        key: const ValueKey('mobile_keystone_scan_camera'),
        controller: controller,
        expectedUrType: 'zcash-accounts',
        scanSessionResetToken: _scanSessionResetToken,
        errorBuilder: (context, error) => const SizedBox.shrink(),
        onProgress: _handleScanProgress,
        onDecodeError: _handleDecodeError,
        onComplete: (result) => unawaited(_handleScanComplete(result)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cameraHeight = _scanModalHeight(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileOnboardingStepScaffold(
          progress: 0.4,
          onBack: () => Navigator.of(context).maybePop(),
          title: AppLocalizations.of(context).keystoneScanQrTitle,
          subtitle: AppLocalizations.of(context).keystonePrepareWallet,
          scrollable: false,
          child: const SizedBox.shrink(),
        ),
        IgnorePointer(
          child: ModalBarrier(color: colors.background.neutralScrim),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              MobileModalCard(child: _buildScanCard(cameraHeight)),
            ],
          ),
        ),
      ],
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
      title: AppLocalizations.of(context).keystoneSelectAccount,
      subtitle: AppLocalizations.of(context).keystonePrepareWallet,
      bottomArea: AppButton(
        key: const ValueKey('mobile_keystone_select_continue'),
        expand: true,
        onPressed: selected == null
            ? null
            : () => context.push(
                KeystoneOnboardingStep.walletBirthdayHeight.routePath,
              ),
        child: Text(AppLocalizations.of(context).keystoneSelectAccount),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Figma `List Title` (4654:74577): Label M Medium on
          // text/secondary with a 4 px inset.
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              AppLocalizations.of(context).keystoneAccountsFound(accounts.length),
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          for (final account in accounts) ...[
            _AccountCard(
              name: account.name.trim().isEmpty
                  ? AppLocalizations.of(context).keystoneAccountFallback(account.index + 1)
                  : account.name,
              detail: _truncate(account.ufvk),
              selected: account == selected,
              onTap: () => ref
                  .read(keystoneOnboardingProvider.notifier)
                  .selectAccount(account),
            ),
            // 12 px gap between radio cards (Figma `Radi Group` 4654:74579).
            const SizedBox(height: AppSpacing.s),
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
          // Figma `Radio Card` (4654:74580): min-h 64, ground fill, 16 px
          // radius, asymmetric 8/12/4 padding. Only the selected card
          // carries a 2 px strong border; unselected cards are border-less.
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
            top: AppSpacing.xxs,
            bottom: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: selected
                ? Border.all(color: colors.border.strong, width: 2)
                : null,
          ),
          child: Row(
            children: [
              // 32 px icon cell; the user glyph dims to 50 % when the card
              // is not selected (Figma `Card Icon`).
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Opacity(
                    opacity: selected ? 1 : 0.5,
                    child: AppIcon(
                      AppIcons.user,
                      size: 20,
                      color: colors.icon.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label M; SemiBold when selected, Medium otherwise.
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Label M Regular; accent on the selected card, secondary
                    // otherwise.
                    Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: selected
                            ? colors.text.accent
                            : colors.text.secondary,
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
                    color: colors.background.neutralSubtleOpacity,
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
      progress: 0.8,
      onHeightConfirmed: (height) => _confirm(context, ref, height),
    );
  }
}
