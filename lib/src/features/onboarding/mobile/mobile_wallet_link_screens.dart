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
import '../../wallet_link/services/wallet_link_completion.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_keystone_scan_card.dart';
import 'mobile_onboarding_scaffold.dart';

const _walletLinkIntroProgress = 0.2;
const _walletLinkScanProgress = 0.4;
const _walletLinkAccountsProgress = 0.6;
const _walletLinkContactsProgress = 0.8;

typedef WalletLinkCompletionCallback =
    Future<void> Function({
      required String packageId,
      required String completionToken,
      required List<int> keyBytes,
      required int importedAccountCount,
      required int importedContactCount,
    });

class MobileWalletLinkIntroScreen extends StatelessWidget {
  const MobileWalletLinkIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: _walletLinkIntroProgress,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Link with Desktop',
      subtitle: 'Copy your desktop wallet to this phone',
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.monitor, size: 24, color: colors.icon.accent),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              'This copies the wallet and contacts to the phone. Nothing on the computer changes, and you can use both.',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
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
      'Go to Settings → Link Vizor Mobile',
      'Scan the QR code on your desktop from the next screen.',
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
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          if (index != steps.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
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
        subtitle: 'Copy your desktop wallet to this phone',
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
    MobileWalletLinkScanError.invalid => 'Invalid QR code',
    MobileWalletLinkScanError.expired => 'Link expired',
    MobileWalletLinkScanError.failed => "Couldn't open this link",
  };

  String get _body => switch (error) {
    MobileWalletLinkScanError.invalid =>
      "The code you scanned isn't a Vizor desktop link. On your computer, open Settings → Link Vizor Mobile.",
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
  const MobileWalletLinkSelectAccountsScreen({
    this.completeWalletLinkPackage = completeWalletLinkPackageBestEffort,
    super.key,
  });

  final WalletLinkCompletionCallback completeWalletLinkPackage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileWalletLinkControllerProvider);
    if (!state.hasPayload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/onboarding/link-desktop');
      });
    }

    final submitting = state.submitting;
    final allAccountsSelected =
        state.importableAccountCount > 0 &&
        state.selectedAccountCount == state.importableAccountCount;
    final canContinueWithContactsOnly =
        state.importableContactCount > 0 &&
        ref.watch(appSecurityProvider).isPasswordConfigured;
    final hasNothingToImport =
        state.importableAccountCount == 0 && state.importableContactCount == 0;
    final pendingAccounts = [
      for (final account in state.sortedAccounts)
        if (!state.isAccountAlreadyImported(account.uuid)) account,
    ];
    final alreadyImportedAccounts = [
      for (final account in state.sortedAccounts)
        if (state.isAccountAlreadyImported(account.uuid)) account,
    ];
    return _WalletLinkSelectionScaffold(
      progress: _walletLinkAccountsProgress,
      title: 'Select account',
      subtitle: hasNothingToImport
          ? const TextSpan(
              text: 'There is nothing new to import from this desktop link.',
            )
          : TextSpan(
              text:
                  '${_walletLinkCountLabel(state.importableAccountCount, 'account', 'accounts')} ready to import, '
                  '${alreadyImportedAccounts.length} already imported.',
            ),
      buttonLabel: hasNothingToImport
          ? 'Go back'
          : state.selectedAccountCount == 0
          ? 'Continue'
          : 'Link ${state.selectedAccountCount} account${state.selectedAccountCount == 1 ? '' : 's'}',
      buttonLoadingLabel: 'Importing...',
      buttonEnabled:
          hasNothingToImport ||
          state.selectedAccountCount > 0 ||
          canContinueWithContactsOnly,
      buttonLoading: submitting,
      onButtonPressed: () {
        if (hasNothingToImport) {
          unawaited(
            _completeEmptyWalletLinkAndGoBack(
              context,
              ref,
              completeWalletLinkPackage: completeWalletLinkPackage,
            ),
          );
          return;
        }
        if (state.contacts.isEmpty) {
          _continueToPasscodeOrImport(context, ref);
          return;
        }
        context.push('/onboarding/link-desktop/contacts');
      },
      child: hasNothingToImport
          ? const _WalletLinkNothingToImportCard()
          : Column(
              children: [
                if (pendingAccounts.isNotEmpty)
                  _WalletLinkListSection(
                    title:
                        '${_walletLinkCountLabel(pendingAccounts.length, 'account', 'accounts')} found',
                    actionLabel: allAccountsSelected
                        ? 'Deselect all'
                        : 'Select all',
                    onAction: submitting || state.importableAccountCount == 0
                        ? null
                        : allAccountsSelected
                        ? () => ref
                              .read(mobileWalletLinkControllerProvider.notifier)
                              .deselectAllAccounts()
                        : () => ref
                              .read(mobileWalletLinkControllerProvider.notifier)
                              .selectAllImportableAccounts(),
                    child: Column(
                      children: [
                        for (final (index, account)
                            in pendingAccounts.indexed) ...[
                          _WalletLinkAccountRow(
                            account: account,
                            selected: state.selectedAccountUuids.contains(
                              account.uuid,
                            ),
                            alreadyImported: false,
                            onTap:
                                submitting ||
                                    !state.isAccountSelectable(account)
                                ? null
                                : () => ref
                                      .read(
                                        mobileWalletLinkControllerProvider
                                            .notifier,
                                      )
                                      .toggleAccount(account.uuid),
                          ),
                          if (index != pendingAccounts.length - 1)
                            const SizedBox(height: AppSpacing.s),
                        ],
                      ],
                    ),
                  ),
                if (pendingAccounts.isNotEmpty &&
                    alreadyImportedAccounts.isNotEmpty)
                  const SizedBox(height: AppSpacing.base),
                if (alreadyImportedAccounts.isNotEmpty)
                  _WalletLinkListSection(
                    title: '${alreadyImportedAccounts.length} already imported',
                    child: Column(
                      children: [
                        for (final (index, account)
                            in alreadyImportedAccounts.indexed) ...[
                          _WalletLinkAccountRow(
                            account: account,
                            selected: false,
                            alreadyImported: true,
                            onTap: null,
                          ),
                          if (index != alreadyImportedAccounts.length - 1)
                            const SizedBox(height: AppSpacing.s),
                        ],
                      ],
                    ),
                  ),
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

    final submitting = state.submitting;
    final pendingContacts = [
      for (final contact in state.sortedContacts)
        if (!state.isContactAlreadyImported(contact.id)) contact,
    ];
    final alreadyImportedContacts = [
      for (final contact in state.sortedContacts)
        if (state.isContactAlreadyImported(contact.id)) contact,
    ];
    final groups = _groupContactsByNetwork(pendingContacts);
    final alreadyImportedGroups = _groupContactsByNetwork(
      alreadyImportedContacts,
    );
    final allContactsSelected =
        state.importableContactCount > 0 &&
        state.selectedContactCount == state.importableContactCount;
    return _WalletLinkSelectionScaffold(
      progress: _walletLinkContactsProgress,
      title: 'Import contacts',
      subtitle: TextSpan(
        text:
            '${_walletLinkCountLabel(state.contacts.length, 'contact', 'contacts')} found, '
            '${alreadyImportedContacts.length} already imported.',
      ),
      buttonLabel:
          'Import ${state.selectedContactCount} contact${state.selectedContactCount == 1 ? '' : 's'}',
      buttonLoadingLabel: 'Importing...',
      buttonEnabled:
          state.selectedAccountCount > 0 || state.selectedContactCount > 0,
      buttonLoading: submitting,
      onButtonPressed: () => _continueToPasscodeOrImport(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isNotEmpty)
            _WalletLinkListSection(
              title:
                  '${_walletLinkCountLabel(pendingContacts.length, 'contact', 'contacts')} found',
              actionLabel: allContactsSelected ? 'Deselect all' : 'Select all',
              onAction: submitting || state.importableContactCount == 0
                  ? null
                  : allContactsSelected
                  ? () => ref
                        .read(mobileWalletLinkControllerProvider.notifier)
                        .deselectAllContacts()
                  : () => ref
                        .read(mobileWalletLinkControllerProvider.notifier)
                        .selectAllContacts(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (groupIndex, entry) in groups.entries.indexed) ...[
                    _ContactGroupHeader(network: entry.key),
                    const SizedBox(height: AppSpacing.s),
                    for (final (contactIndex, contact)
                        in entry.value.indexed) ...[
                      _WalletLinkContactRow(
                        contact: contact,
                        selected: state.selectedContactIds.contains(contact.id),
                        alreadyImported: false,
                        onTap: submitting || !state.isContactSelectable(contact)
                            ? null
                            : () => ref
                                  .read(
                                    mobileWalletLinkControllerProvider.notifier,
                                  )
                                  .toggleContact(contact.id),
                      ),
                      if (contactIndex != entry.value.length - 1)
                        const SizedBox(height: AppSpacing.s),
                    ],
                    if (groupIndex != groups.length - 1)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          if (groups.isNotEmpty && alreadyImportedGroups.isNotEmpty)
            const SizedBox(height: AppSpacing.base),
          if (alreadyImportedGroups.isNotEmpty)
            _WalletLinkListSection(
              title: '${alreadyImportedContacts.length} already imported',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (groupIndex, entry)
                      in alreadyImportedGroups.entries.indexed) ...[
                    _ContactGroupHeader(network: entry.key),
                    const SizedBox(height: AppSpacing.s),
                    for (final (contactIndex, contact)
                        in entry.value.indexed) ...[
                      _WalletLinkContactRow(
                        contact: contact,
                        selected: false,
                        alreadyImported: true,
                        onTap: null,
                      ),
                      if (contactIndex != entry.value.length - 1)
                        const SizedBox(height: AppSpacing.s),
                    ],
                    if (groupIndex != alreadyImportedGroups.length - 1)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

void _goBackFromWalletLink(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.maybePop();
    return;
  }
  GoRouter.maybeOf(context)?.go('/onboarding/link-desktop');
}

Future<void> _completeEmptyWalletLinkAndGoBack(
  BuildContext context,
  WidgetRef ref, {
  required WalletLinkCompletionCallback completeWalletLinkPackage,
}) async {
  final state = ref.read(mobileWalletLinkControllerProvider);
  if (state.submitting) return;
  final packageId = state.packageId;
  final completionToken = state.completionToken;
  final keyBytes = state.keyBytes;
  if (packageId == null || completionToken == null || keyBytes == null) {
    _goBackFromWalletLink(context);
    return;
  }

  final controller = ref.read(mobileWalletLinkControllerProvider.notifier);
  controller.beginSubmit();
  try {
    await completeWalletLinkPackage(
      packageId: packageId,
      completionToken: completionToken,
      keyBytes: keyBytes,
      importedAccountCount: 0,
      importedContactCount: 0,
    );
  } catch (_) {
    // Completion is best-effort; the local no-op state should still exit.
  }
  if (!context.mounted) {
    controller.endSubmit();
    return;
  }
  controller.endSubmit();
  GoRouter.maybeOf(context)?.go('/onboarding/link-desktop');
}

Future<void> _continueToPasscodeOrImport(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(mobileWalletLinkControllerProvider);
  if (state.submitting) return;
  final payload = state.payload;
  if (payload == null ||
      (state.selectedAccounts.isEmpty && state.selectedContacts.isEmpty)) {
    return;
  }
  final packageId = state.packageId;
  final completionToken = state.completionToken;
  final keyBytes = state.keyBytes;
  if (packageId == null || completionToken == null || keyBytes == null) return;
  final accounts = [
    for (final account in state.selectedAccounts) account.toAccountImport(),
  ];
  final contacts = state.selectedContacts;
  final security = ref.read(appSecurityProvider);
  if (!security.isPasswordConfigured) {
    if (accounts.isEmpty) return;
    context.push(
      '/onboarding/set-passcode',
      extra: SetPasswordScreenArgs.importWalletLink(
        network: payload.network,
        accounts: accounts,
        contacts: contacts,
        packageId: packageId,
        completionToken: completionToken,
        keyBytes: keyBytes,
      ),
    );
    return;
  }

  final router = GoRouter.of(context);
  final controller = ref.read(mobileWalletLinkControllerProvider.notifier);
  controller.beginSubmit();
  try {
    if (accounts.isEmpty) {
      await ref
          .read(accountProvider.notifier)
          .validateLinkedWalletNetwork(payload.network);
    }
    final accountImportResult = accounts.isEmpty
        ? const LinkedWalletAccountsImportResult(
            importedCount: 0,
            skippedDuplicateCount: 0,
          )
        : await runWithSyncPausedForAccountMutation(
            ref,
            () => ref
                .read(accountProvider.notifier)
                .importLinkedWalletAccounts(
                  network: payload.network,
                  accountsToImport: accounts,
                ),
          );
    final importedContactCount = contacts.isEmpty
        ? 0
        : await ref.read(addressBookProvider.notifier).importContacts(contacts);
    await completeWalletLinkPackageBestEffort(
      packageId: packageId,
      completionToken: completionToken,
      keyBytes: keyBytes,
      importedAccountCount: accountImportResult.importedCount,
      importedContactCount: importedContactCount,
    );
  } catch (error) {
    controller.endSubmit();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(onboardingSubmitErrorMessage(error))),
    );
    return;
  }
  if (!context.mounted) {
    controller.endSubmit();
    return;
  }
  router.go('/home');
}

class _WalletLinkSelectionScaffold extends StatelessWidget {
  const _WalletLinkSelectionScaffold({
    required this.progress,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.buttonLoadingLabel,
    required this.buttonEnabled,
    required this.buttonLoading,
    required this.onButtonPressed,
    required this.child,
  });

  final double progress;
  final String title;
  final TextSpan subtitle;
  final String buttonLabel;
  final String buttonLoadingLabel;
  final bool buttonEnabled;
  final bool buttonLoading;
  final VoidCallback onButtonPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: !buttonLoading,
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTopNav.steps(
                progress: progress,
                showBackButton: !buttonLoading,
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
                          const SizedBox(height: AppSpacing.base),
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
                        loadingLabel: buttonLoadingLabel,
                        enabled: buttonEnabled,
                        loading: buttonLoading,
                        onPressed: onButtonPressed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletLinkListSection extends StatelessWidget {
  const _WalletLinkListSection({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              if (actionLabel != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      actionLabel!,
                      style: AppTypography.labelLarge.copyWith(
                        color: onAction == null
                            ? colors.text.disabled
                            : colors.text.secondary,
                        fontWeight: FontWeight.w500,
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
    );
  }
}

class _WalletLinkNothingToImportCard extends StatelessWidget {
  const _WalletLinkNothingToImportCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 156),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
                AppIcons.checkCircle,
                size: 24,
                color: colors.icon.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nothing to import',
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Everything in this desktop link is already on this phone.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBottomAction extends StatelessWidget {
  const _SelectionBottomAction({
    required this.label,
    required this.loadingLabel,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final String loadingLabel;
  final bool enabled;
  final bool loading;
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
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.s,
        ),
        child: AppButton(
          expand: true,
          leading: loading ? const AppIcon(AppIcons.loader) : null,
          onPressed: !loading && enabled ? onPressed : null,
          child: Text(loading ? loadingLabel : label),
        ),
      ),
    );
  }
}

class _WalletLinkAccountRow extends StatelessWidget {
  const _WalletLinkAccountRow({
    required this.account,
    required this.selected,
    required this.alreadyImported,
    required this.onTap,
  });

  final WalletLinkTransferAccount account;
  final bool selected;
  final bool alreadyImported;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = account.isImportable && !alreadyImported && onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
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
                  color: enabled ? colors.icon.accent : colors.icon.muted,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: account.isImportable
                          ? colors.text.accent
                          : colors.text.secondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (!alreadyImported) ...[
              const SizedBox(width: AppSpacing.xs),
              _WalletLinkCheckbox(selected: selected && account.isImportable),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletLinkContactRow extends StatelessWidget {
  const _WalletLinkContactRow({
    required this.contact,
    required this.selected,
    required this.alreadyImported,
    required this.onTap,
  });

  final AddressBookContact contact;
  final bool selected;
  final bool alreadyImported;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = !alreadyImported && onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
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
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.addressPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: enabled && selected
                          ? colors.text.accent
                          : colors.text.secondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (!alreadyImported) ...[
              const SizedBox(width: AppSpacing.xs),
              _WalletLinkCheckbox(selected: selected),
            ],
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
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        children: [
          AddressBookNetworkIcon(network: network, size: 20),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            network.label,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
              fontWeight: FontWeight.w500,
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
  Iterable<AddressBookContact> contacts,
) {
  final grouped = <AddressBookNetwork, List<AddressBookContact>>{};
  for (final contact in contacts) {
    grouped.putIfAbsent(contact.network, () => []).add(contact);
  }
  return grouped;
}

String _walletLinkCountLabel(int count, String singular, String plural) {
  return '$count ${count == 1 ? singular : plural}';
}
