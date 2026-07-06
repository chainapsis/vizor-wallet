import 'dart:async';

import 'package:flutter/material.dart'
    show Scaffold, ScaffoldMessenger, SnackBar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../services/qr_scanner.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../address_book/widgets/address_book_network_icon.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart';
import '../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../wallet_link/models/wallet_link_models.dart';
import '../../wallet_link/providers/mobile_wallet_link_provider.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_keystone_scan_card.dart';
import 'mobile_onboarding_scaffold.dart';

const _walletLinkIntroProgress = 0.2;
const _walletLinkScanProgress = 0.4;
const _walletLinkAccountsProgress = 0.6;
const _walletLinkContactsProgress = 0.8;

class MobileWalletLinkIntroScreen extends StatelessWidget {
  const MobileWalletLinkIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: _walletLinkIntroProgress,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Link with Desktop',
      subtitle: 'Prepare your desktop app',
      bottomArea: AppButton(
        key: const ValueKey('mobile_wallet_link_intro_scan'),
        expand: true,
        onPressed: () => context.push('/onboarding/link-desktop/scan'),
        child: const Text("I'm ready to scan"),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _DesktopLinkNoticeCard(),
          SizedBox(height: AppSpacing.md),
          _DesktopLinkSteps(),
        ],
      ),
    );
  }
}

class _DesktopLinkNoticeCard extends StatelessWidget {
  const _DesktopLinkNoticeCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.background.raised,
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Center(
              child: AppIcon(
                AppIcons.monitor,
                size: 24,
                color: colors.icon.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This copies selected accounts onto the phone. Nothing on the computer changes.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopLinkSteps extends StatelessWidget {
  const _DesktopLinkSteps();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const steps = [
      'Open & unlock your Vizor desktop app',
      'Go to Settings -> Link Vizor Mobile',
      'A moving QR code appears. Keep it on screen.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, step) in steps.indexed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}.',
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
          if (index != steps.length - 1) const SizedBox(height: AppSpacing.s),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(AppIcons.lock, size: 18, color: colors.icon.accent),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'The code is encrypted. Your recovery phrase is never shown.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MobileWalletLinkScanScreen extends ConsumerWidget {
  const MobileWalletLinkScanScreen({
    this.previewCameraStatus,
    this.previewError,
    super.key,
  });

  final AddressQrCameraStatus? previewCameraStatus;
  final MobileWalletLinkScanError? previewError;

  double _scanModalHeight(BuildContext context) {
    return MobileAddressScanCardContent.modalCameraHeight(context);
  }

  Future<void> _handleScan(
    BuildContext context,
    WidgetRef ref,
    String raw,
  ) async {
    final ok = await ref
        .read(mobileWalletLinkControllerProvider.notifier)
        .handleQrCode(raw);
    if (!context.mounted || !ok) return;
    context.push('/onboarding/link-desktop/accounts');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(mobileWalletLinkControllerProvider);
    final scanError = previewError ?? state.scanError;
    if (scanError == null) {
      return MobileOnboardingStepScaffold(
        progress: _walletLinkScanProgress,
        onBack: () => Navigator.of(context).maybePop(),
        title: 'Scan QR Code',
        subtitle: 'Scan the code on your desktop',
        scrollable: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cameraHeight = constraints.maxHeight.clamp(420.0, 560.0);
            return _WalletLinkScanCard(
              cameraHeight: cameraHeight,
              forceStatus: previewCameraStatus,
              loading: state.loading,
              scanResetToken: state.scanResetToken,
              onScanned: (raw) => unawaited(_handleScan(context, ref, raw)),
              onClose: () => Navigator.of(context).maybePop(),
            );
          },
        ),
      );
    }

    final cameraHeight = _scanModalHeight(context);
    final content = _WalletLinkScanErrorCard(
      error: scanError,
      height: cameraHeight,
      onScanAgain: () => ref
          .read(mobileWalletLinkControllerProvider.notifier)
          .clearScanError(),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        MobileOnboardingStepScaffold(
          progress: _walletLinkScanProgress,
          onBack: () => Navigator.of(context).maybePop(),
          title: 'Scan QR Code',
          subtitle: 'Scan the code on your desktop',
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
              MobileModalCard(child: content),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletLinkScanCard extends StatefulWidget {
  const _WalletLinkScanCard({
    required this.cameraHeight,
    required this.loading,
    required this.scanResetToken,
    required this.onScanned,
    required this.onClose,
    this.forceStatus,
  });

  final double cameraHeight;
  final bool loading;
  final int scanResetToken;
  final ValueChanged<String> onScanned;
  final VoidCallback onClose;
  final AddressQrCameraStatus? forceStatus;

  @override
  State<_WalletLinkScanCard> createState() => _WalletLinkScanCardState();
}

class _WalletLinkScanCardState extends State<_WalletLinkScanCard> {
  late final MobileScannerController _previewController;

  @override
  void initState() {
    super.initState();
    _previewController = MobileScannerController(autoStart: false);
  }

  @override
  void dispose() {
    unawaited(_previewController.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final forced = widget.forceStatus;
    if (forced != null && forced != AddressQrCameraStatus.active) {
      return MobileAddressScanCardContent(
        status: forced,
        cameraHeight: widget.cameraHeight,
        caption: 'Scan the Vizor desktop QR',
        permissionBuilder:
            (context, status, unavailableDescription, onRetry, onClose) =>
                MobileKeystoneScanPermissionCard(
                  status: status,
                  unavailableDescription: unavailableDescription,
                  onRetry: onRetry,
                  cameraHeight: widget.cameraHeight,
                ),
        onTorch: () {},
        onClose: widget.onClose,
        onRetry: () {},
      );
    }

    return MobileQrScanCard(
      controller: forced == AddressQrCameraStatus.active
          ? _previewController
          : null,
      forceActiveForTesting: forced == AddressQrCameraStatus.active,
      cameraHeight: widget.cameraHeight,
      caption: widget.loading ? 'Reading link...' : 'Scan the Vizor desktop QR',
      permissionTitle: 'Scan the Vizor desktop QR',
      unavailableDescription:
          'Desktop link scanning needs a camera on this device.',
      closeEnabled: !widget.loading,
      permissionBuilder:
          (context, status, unavailableDescription, onRetry, onClose) =>
              MobileKeystoneScanPermissionCard(
                status: status,
                unavailableDescription: unavailableDescription,
                onRetry: onRetry,
                cameraHeight: widget.cameraHeight,
              ),
      onClose: widget.loading ? () {} : widget.onClose,
      cameraViewBuilder: (context, controller) => PlainQrScannerView(
        key: const ValueKey('mobile_wallet_link_scan_camera'),
        controller: controller,
        scanSessionResetToken: widget.scanResetToken,
        onComplete: widget.onScanned,
      ),
    );
  }
}

class _WalletLinkScanErrorCard extends StatelessWidget {
  const _WalletLinkScanErrorCard({
    required this.error,
    required this.height,
    required this.onScanAgain,
  });

  final MobileWalletLinkScanError error;
  final double height;
  final VoidCallback onScanAgain;

  String get _title => switch (error) {
    MobileWalletLinkScanError.invalid => "This isn't a Vizor link",
    MobileWalletLinkScanError.expired => 'Link expired',
    MobileWalletLinkScanError.failed => "Couldn't open this link",
  };

  String get _body => switch (error) {
    MobileWalletLinkScanError.invalid =>
      "The code you scanned isn't a Vizor desktop link. On your computer, open Settings -> Link Vizor Mobile.",
    MobileWalletLinkScanError.expired =>
      'The code on your computer timed out. On desktop, choose Generate new code and scan it again.',
    MobileWalletLinkScanError.failed =>
      'Check that the desktop code is still visible, then scan it again.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.xLarge),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.background.raised,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.warning,
                      size: 24,
                      color: colors.icon.warning,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  key: const ValueKey('mobile_wallet_link_scan_again'),
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  minWidth: 108,
                  leading: const AppIcon(AppIcons.renew),
                  onPressed: onScanAgain,
                  child: const Text('Scan again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MobileWalletLinkSelectAccountsScreen extends ConsumerWidget {
  const MobileWalletLinkSelectAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileWalletLinkControllerProvider);
    if (!state.hasPayload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/onboarding/link-desktop');
      });
    }

    return _WalletLinkSelectionScaffold(
      progress: _walletLinkAccountsProgress,
      title: 'Select Accounts',
      subtitle: const TextSpan(
        text: 'This copies the chosen accounts to your phone. ',
        children: [
          TextSpan(
            text: 'Nothing on your computer changes.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      listTitle:
          '${state.accounts.length} account${state.accounts.length == 1 ? '' : 's'} found',
      actionLabel: state.selectedAccountCount == state.importableAccountCount
          ? 'Deselect all'
          : 'Select all',
      onAction: state.selectedAccountCount == state.importableAccountCount
          ? () => ref
                .read(mobileWalletLinkControllerProvider.notifier)
                .deselectAllAccounts()
          : () => ref
                .read(mobileWalletLinkControllerProvider.notifier)
                .selectAllImportableAccounts(),
      buttonLabel:
          'Link ${state.selectedAccountCount} account${state.selectedAccountCount == 1 ? '' : 's'}',
      buttonEnabled: state.selectedAccountCount > 0,
      onButtonPressed: () {
        if (state.contacts.isEmpty) {
          _continueToPasscodeOrImport(context, ref);
          return;
        }
        context.push('/onboarding/link-desktop/contacts');
      },
      child: Column(
        children: [
          for (final account in state.accounts) ...[
            _WalletLinkAccountRow(
              account: account,
              selected: state.selectedAccountUuids.contains(account.uuid),
              onTap: () => ref
                  .read(mobileWalletLinkControllerProvider.notifier)
                  .toggleAccount(account.uuid),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
        ],
      ),
    );
  }
}

class MobileWalletLinkSelectContactsScreen extends ConsumerWidget {
  const MobileWalletLinkSelectContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileWalletLinkControllerProvider);
    if (!state.hasPayload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/onboarding/link-desktop');
      });
    }

    final groups = _groupContactsByNetwork(state.contacts);
    return _WalletLinkSelectionScaffold(
      progress: _walletLinkContactsProgress,
      title: 'Select Contacts',
      subtitle: const TextSpan(
        text:
            "All contacts are selected by default. Uncheck any you'd rather leave behind.",
      ),
      listTitle:
          '${state.contacts.length} contact${state.contacts.length == 1 ? '' : 's'} found',
      actionLabel: state.selectedContactCount == state.contacts.length
          ? 'Deselect all'
          : 'Select all',
      onAction: state.selectedContactCount == state.contacts.length
          ? () => ref
                .read(mobileWalletLinkControllerProvider.notifier)
                .deselectAllContacts()
          : () => ref
                .read(mobileWalletLinkControllerProvider.notifier)
                .selectAllContacts(),
      buttonLabel:
          'Import ${state.selectedContactCount} contact${state.selectedContactCount == 1 ? '' : 's'}',
      buttonEnabled: state.selectedAccountCount > 0,
      onButtonPressed: () => _continueToPasscodeOrImport(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in groups.entries) ...[
            _ContactGroupHeader(network: entry.key),
            const SizedBox(height: AppSpacing.xs),
            for (final contact in entry.value) ...[
              _WalletLinkContactRow(
                contact: contact,
                selected: state.selectedContactIds.contains(contact.id),
                onTap: () => ref
                    .read(mobileWalletLinkControllerProvider.notifier)
                    .toggleContact(contact.id),
              ),
              const SizedBox(height: AppSpacing.s),
            ],
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

Future<void> _continueToPasscodeOrImport(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(mobileWalletLinkControllerProvider);
  final payload = state.payload;
  if (payload == null || state.selectedAccounts.isEmpty) return;
  final accounts = [
    for (final account in state.selectedAccounts) account.toAccountImport(),
  ];
  final contacts = state.selectedContacts;
  final security = ref.read(appSecurityProvider);
  if (!security.isPasswordConfigured) {
    context.push(
      '/onboarding/set-passcode',
      extra: SetPasswordScreenArgs.importWalletLink(
        network: payload.network,
        accounts: accounts,
        contacts: contacts,
      ),
    );
    return;
  }

  final router = GoRouter.of(context);
  try {
    await runWithSyncPausedForAccountMutation(
      ref,
      () => ref
          .read(accountProvider.notifier)
          .importLinkedWalletAccounts(
            network: payload.network,
            accountsToImport: accounts,
          ),
    );
    await ref.read(addressBookProvider.notifier).importContacts(contacts);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(onboardingSubmitErrorMessage(error))),
    );
    return;
  }
  router.go('/home');
}

class _WalletLinkSelectionScaffold extends StatelessWidget {
  const _WalletLinkSelectionScaffold({
    required this.progress,
    required this.title,
    required this.subtitle,
    required this.listTitle,
    required this.actionLabel,
    required this.onAction,
    required this.buttonLabel,
    required this.buttonEnabled,
    required this.onButtonPressed,
    required this.child,
  });

  final double progress;
  final String title;
  final TextSpan subtitle;
  final String listTitle;
  final String actionLabel;
  final VoidCallback onAction;
  final String buttonLabel;
  final bool buttonEnabled;
  final VoidCallback onButtonPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileTopNav.steps(
              progress: progress,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.sm,
                      132,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppTypography.displayLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text.rich(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  listTitle,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onAction,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xxs,
                                    vertical: AppSpacing.xxs,
                                  ),
                                  child: Text(
                                    actionLabel,
                                    style: AppTypography.labelLarge.copyWith(
                                      color: colors.text.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        child,
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _SelectionBottomAction(
                      label: buttonLabel,
                      enabled: buttonEnabled,
                      onPressed: onButtonPressed,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBottomAction extends StatelessWidget {
  const _SelectionBottomAction({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = context.colors.background.window;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg, bg],
          stops: const [0, 0.35, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.s,
        ),
        child: AppButton(
          expand: true,
          onPressed: enabled ? onPressed : null,
          child: Text(label),
        ),
      ),
    );
  }
}

class _WalletLinkAccountRow extends StatelessWidget {
  const _WalletLinkAccountRow({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final WalletLinkTransferAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = account.isImportable;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
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
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(
                    account.isHardware ? AppIcons.keystone : AppIcons.user,
                    size: 20,
                    color: colors.icon.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _WalletLinkCheckbox(selected: selected && enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletLinkContactRow extends StatelessWidget {
  const _WalletLinkContactRow({
    required this.contact,
    required this.selected,
    required this.onTap,
  });

  final AddressBookContact contact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
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
        ),
        child: Row(
          children: [
            AddressBookNetworkIcon(network: contact.network, size: 32),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.addressPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _WalletLinkCheckbox(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _ContactGroupHeader extends StatelessWidget {
  const _ContactGroupHeader({required this.network});

  final AddressBookNetwork network;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Row(
        children: [
          AddressBookNetworkIcon(network: network, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Text(
            network.label,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletLinkCheckbox extends StatelessWidget {
  const _WalletLinkCheckbox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: selected
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 14,
                color: colors.text.inverse,
              ),
            )
          : null,
    );
  }
}

Map<AddressBookNetwork, List<AddressBookContact>> _groupContactsByNetwork(
  List<AddressBookContact> contacts,
) {
  final grouped = <AddressBookNetwork, List<AddressBookContact>>{};
  for (final contact in contacts) {
    grouped.putIfAbsent(contact.network, () => []).add(contact);
  }
  return grouped;
}
