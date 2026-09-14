// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:widgetbook/widgetbook.dart';

import '../accounts_settings_use_cases.dart';
import '../donation_use_cases.dart';
import 'pay_gallery.dart';
import '../screen_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';
import '../../src/core/profile_pictures.dart';
import '../../src/core/security/password_policy.dart';
import '../../src/core/theme/app_theme.dart';
import '../../src/features/accounts/screens/accounts_screen.dart';
import '../../src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../../src/features/about/screens/about_screen.dart';
import '../../src/features/about/screens/mobile/mobile_about_screens.dart';
import '../../src/features/settings/screens/mobile/mobile_endpoint_screen.dart';
import '../../src/features/settings/screens/mobile/mobile_explorer_screen.dart';
import '../../src/features/settings/screens/settings_endpoint_screen.dart';
import '../../src/features/settings/screens/settings_explorer_screen.dart';
import '../../src/features/settings/screens/settings_uninstall_screen.dart';
import '../../src/features/settings/widgets/settings_pane_backdrop.dart';
import '../../src/features/wallet_link/models/wallet_link_models.dart';
import '../../src/providers/account_provider.dart';
import '../../src/providers/app_security_provider.dart';
import '../../src/providers/biometric_unlock_provider.dart';
import '../../src/providers/network_privacy_provider.dart';
import '../../src/providers/rpc_endpoint_latency_provider.dart';
import '../../src/providers/windows_update_provider.dart';
import '../../src/services/biometric_unlock.dart';

/// Accounts, Settings and Utility as knob-driven galleries. Every knob option
/// dispatches to a `build*UseCase` in `screen_use_cases.dart`, so
/// figma_compare and the fixture tests keep every builder they bind to.
///
/// The mobile fixtures carry their own phone frame and are already browsed
/// from the desktop binary today, so they dispatch directly rather than
/// through `WbLaneOnly` — hiding them off-lane would drop existing coverage.
final List<WidgetbookNode> accountsSettingsGalleryNodes = [
  WidgetbookFolder(
    name: 'Accounts',
    children: [
      WidgetbookComponent(
        name: 'Accounts screen',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildAccountsScreenGalleryCase,
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Components',
        children: [
          WidgetbookComponent(
            name: 'Accounts sheet',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildAccountsSwitcherSheetGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Profile picture sheet',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildAccountsProfilePictureSheetGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Remove account modal',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildAccountsRemoveModalGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Edit account modal',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildAccountsEditModalGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Profile picture modal',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildAccountsProfilePictureModalGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Account modal card',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildAccountsModalCardGalleryCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Settings',
    children: [
      WidgetbookComponent(
        name: 'Settings screen',
        useCases: [
          WidgetbookUseCase(
            name: 'Screen',
            builder: buildSettingsScreenGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Endpoint',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsEndpointGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Explorer',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsExplorerGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Secret passphrase',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsPassphraseGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Viewing key',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsViewingKeyGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Change password',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsChangePasswordGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Donation',
        useCases: [
          WidgetbookUseCase(
            name: 'Compose',
            builder: buildDonationComposeGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Screen',
            builder: buildDonationScreenGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Review',
            builder: buildDonationReviewGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Status',
            builder: buildDonationStatusGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Uninstall',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsUninstallGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Link mobile',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSettingsLinkMobileGalleryCase,
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Components',
        children: [
          WidgetbookComponent(
            name: 'Network privacy',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildSettingsNetworkPrivacyGalleryCase,
              ),
            ],
          ),
          // The updater's download dialogs are root-navigator `showDialog`s that
          // the Updates modal preview cannot host, so they are their own surface.
          WidgetbookComponent(
            name: 'Windows update dialogs',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildSettingsUpdateDialogsGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Confirm access card',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildSettingsConfirmAccessCardGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Pane backdrop',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildSettingsPaneBackdropGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Custom endpoint',
            // The panel's only production host is the onboarding welcome screen
            // (welcome.dart:152), already registered under Onboarding > Welcome
            // with the Tor axis; these two cases carry the endpoint, latency,
            // close-button and message-line axes that case has no knobs for.
            // Folding them into Welcome and dropping this entry is an integrator
            // call — the Welcome case is another stream's file.
            useCases: [
              WidgetbookUseCase(
                name: 'Panel',
                builder: buildSettingsCustomEndpointPanelGalleryCase,
              ),
              WidgetbookUseCase(
                name: 'Form',
                builder: buildSettingsCustomEndpointFormGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'New badge',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildSettingsNewBadgeGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Donation recipient row',
            useCases: [
              WidgetbookUseCase(
                name: 'Row',
                builder: buildDonationRecipientRowGalleryCase,
              ),
              WidgetbookUseCase(
                name: 'Vizor badge',
                builder: buildDonationVizorBadgeUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Utility',
    children: [
      WidgetbookComponent(
        name: 'About and legal',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildUtilityDocumentGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Accounts --------------------------------------------------------------

/// How many accounts the previewed screen lists.
enum AccountsListSize { four, single, twenty, none }

String accountsListSizeLabel(AccountsListSize size) {
  return switch (size) {
    AccountsListSize.four => '4 accounts',
    AccountsListSize.single => 'Single account',
    AccountsListSize.twenty => '20 accounts',
    AccountsListSize.none => 'No accounts',
  };
}

AccountState accountsStateFor(AccountsListSize size) {
  return switch (size) {
    AccountsListSize.four => accountsPreviewDesignState,
    AccountsListSize.single => accountsPreviewSingleState,
    AccountsListSize.twenty => accountsPreviewManyState,
    AccountsListSize.none => accountsPreviewEmptyState,
  };
}

/// The account a modal or sheet opens for; the single-account state has only
/// the anchor account and the empty state has none.
String? accountsTargetUuidFor(AccountsListSize size) {
  return switch (size) {
    AccountsListSize.none => null,
    AccountsListSize.single => accountsPreviewCurrentUuid,
    AccountsListSize.four ||
    AccountsListSize.twenty => accountsPreviewKeystoneUuid,
  };
}

enum AccountsDesktopModal { none, editAccount, profilePicture, removeAccount }

String accountsDesktopModalLabel(AccountsDesktopModal modal) {
  return switch (modal) {
    AccountsDesktopModal.none => 'None',
    AccountsDesktopModal.editAccount => 'Edit account',
    AccountsDesktopModal.profilePicture => 'Profile picture',
    AccountsDesktopModal.removeAccount => 'Remove account',
  };
}

enum AccountsDesktopRowMenu {
  closed,
  currentAccount,
  otherAccount,
  keystoneAccount,
}

String accountsDesktopRowMenuLabel(AccountsDesktopRowMenu menu) {
  return switch (menu) {
    AccountsDesktopRowMenu.closed => 'Closed',
    AccountsDesktopRowMenu.currentAccount => 'Current account',
    AccountsDesktopRowMenu.otherAccount => 'Other account',
    AccountsDesktopRowMenu.keystoneAccount => 'Keystone account',
  };
}

/// What stops a removal, as the accounts screen can reach it: the three count
/// families the remove modal watches.
enum AccountsRemoveBlocker {
  none,
  checkingSwaps,
  activeSwaps,
  checkingGiftCards,
  receivingCard,
  unsharedCards,
}

String accountsRemoveBlockerLabel(AccountsRemoveBlocker blocker) {
  return switch (blocker) {
    AccountsRemoveBlocker.none => 'None',
    AccountsRemoveBlocker.checkingSwaps => 'Checking swaps',
    AccountsRemoveBlocker.activeSwaps => '2 active swaps',
    AccountsRemoveBlocker.checkingGiftCards => 'Checking gift cards',
    AccountsRemoveBlocker.receivingCard => '1 receiving card',
    AccountsRemoveBlocker.unsharedCards => '3 unshared cards',
  };
}

enum AccountsMobileSheet { none, editAccount, removeAccount }

String accountsMobileSheetLabel(AccountsMobileSheet sheet) {
  return switch (sheet) {
    AccountsMobileSheet.none => 'None',
    AccountsMobileSheet.editAccount => 'Edit account',
    AccountsMobileSheet.removeAccount => 'Remove account',
  };
}

enum AccountsMobileRowMenu { closed, softwareAccount, keystoneAccount }

String accountsMobileRowMenuLabel(AccountsMobileRowMenu menu) {
  return switch (menu) {
    AccountsMobileRowMenu.closed => 'Closed',
    AccountsMobileRowMenu.softwareAccount => 'Software account',
    AccountsMobileRowMenu.keystoneAccount => 'Keystone account',
  };
}

/// Whether the previewed account has a migration run in flight; the remove
/// sheet swaps its whole description for the migration wording.
enum AccountsMigration { none, active }

String accountsMigrationLabel(AccountsMigration migration) {
  return migration == AccountsMigration.none ? 'None' : 'Active';
}

/// The overlay and row-menu axes are per layout: the profile-picture modal and
/// the current-account menu are desktop-only, the migration wording and the
/// software/Keystone menu split mobile-only.
Widget buildAccountsScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final size = wbStateKnob<AccountsListSize>(
    context,
    label: 'Accounts',
    options: AccountsListSize.values,
    labelBuilder: accountsListSizeLabel,
  );

  if (layout == WbLayout.mobile) {
    final sheet = wbStateKnob<AccountsMobileSheet>(
      context,
      label: 'Sheet',
      options: AccountsMobileSheet.values,
      labelBuilder: accountsMobileSheetLabel,
    );
    final rowMenu = wbStateKnob<AccountsMobileRowMenu>(
      context,
      label: 'Row menu',
      options: AccountsMobileRowMenu.values,
      labelBuilder: accountsMobileRowMenuLabel,
    );
    final migration = wbStateKnob<AccountsMigration>(
      context,
      label: 'Migration',
      options: AccountsMigration.values,
      labelBuilder: accountsMigrationLabel,
    );

    final target = accountsTargetUuidFor(size);
    return accountsMobileScreenFixture(
      accountState: accountsStateFor(size),
      initialSheetAccountUuid: sheet == AccountsMobileSheet.none
          ? null
          : target,
      initialSheet: switch (sheet) {
        AccountsMobileSheet.none => null,
        AccountsMobileSheet.editAccount =>
          MobileAccountsInitialSheet.editAccount,
        AccountsMobileSheet.removeAccount =>
          MobileAccountsInitialSheet.removeAccount,
      },
      initialOpenMenuAccountUuid: switch (rowMenu) {
        AccountsMobileRowMenu.closed => null,
        AccountsMobileRowMenu.softwareAccount => accountsPreviewOtherUuid,
        AccountsMobileRowMenu.keystoneAccount => accountsPreviewKeystoneUuid,
      },
      migrationActive: migration == AccountsMigration.active,
    );
  }

  final modal = wbStateKnob<AccountsDesktopModal>(
    context,
    label: 'Modal',
    options: AccountsDesktopModal.values,
    labelBuilder: accountsDesktopModalLabel,
  );
  final rowMenu = wbStateKnob<AccountsDesktopRowMenu>(
    context,
    label: 'Row menu',
    options: AccountsDesktopRowMenu.values,
    labelBuilder: accountsDesktopRowMenuLabel,
  );
  final blocker = wbStateKnob<AccountsRemoveBlocker>(
    context,
    label: 'Remove blockers',
    options: AccountsRemoveBlocker.values,
    labelBuilder: accountsRemoveBlockerLabel,
  );

  final target = accountsTargetUuidFor(size);
  return accountsDesktopScreenFixture(
    accountState: accountsStateFor(size),
    initialOpenMenuAccountUuid: switch (rowMenu) {
      AccountsDesktopRowMenu.closed => null,
      AccountsDesktopRowMenu.currentAccount => accountsPreviewCurrentUuid,
      AccountsDesktopRowMenu.otherAccount => accountsPreviewOtherUuid,
      AccountsDesktopRowMenu.keystoneAccount => accountsPreviewKeystoneUuid,
    },
    initialModalAccountUuid: modal == AccountsDesktopModal.none ? null : target,
    initialModal: switch (modal) {
      AccountsDesktopModal.none => null,
      AccountsDesktopModal.editAccount =>
        AccountsScreenInitialModal.editAccount,
      AccountsDesktopModal.profilePicture =>
        AccountsScreenInitialModal.profilePicture,
      AccountsDesktopModal.removeAccount =>
        AccountsScreenInitialModal.removeAccount,
    },
    pendingSwapCount: blocker == AccountsRemoveBlocker.activeSwaps ? 2 : 0,
    checkingPendingSwaps: blocker == AccountsRemoveBlocker.checkingSwaps,
    receivingGiftCardCount: blocker == AccountsRemoveBlocker.receivingCard
        ? 1
        : 0,
    checkingReceivingGiftCards:
        blocker == AccountsRemoveBlocker.checkingGiftCards,
    unsharedGiftCardCount: blocker == AccountsRemoveBlocker.unsharedCards
        ? 3
        : 0,
  );
}

// --- Accounts sheet --------------------------------------------------------

enum AccountsSwitcherOthers { none, three, twelve }

String accountsSwitcherOthersLabel(AccountsSwitcherOthers others) {
  return switch (others) {
    AccountsSwitcherOthers.none => 'None',
    AccountsSwitcherOthers.three => '3',
    AccountsSwitcherOthers.twelve => '12',
  };
}

enum AccountsSwitcherActive { software, keystone }

String accountsSwitcherActiveLabel(AccountsSwitcherActive active) {
  return active == AccountsSwitcherActive.software ? 'Software' : 'Keystone';
}

Widget buildAccountsSwitcherSheetGalleryCase(BuildContext context) {
  final others = wbStateKnob<AccountsSwitcherOthers>(
    context,
    label: 'Other accounts',
    options: AccountsSwitcherOthers.values,
    labelBuilder: accountsSwitcherOthersLabel,
    initial: AccountsSwitcherOthers.three,
  );
  final active = wbStateKnob<AccountsSwitcherActive>(
    context,
    label: 'Active account',
    options: AccountsSwitcherActive.values,
    labelBuilder: accountsSwitcherActiveLabel,
  );
  return accountsSwitcherSheetFixture(
    otherAccountCount: switch (others) {
      AccountsSwitcherOthers.none => 0,
      AccountsSwitcherOthers.three => 3,
      AccountsSwitcherOthers.twelve => 12,
    },
    activeIsHardware: active == AccountsSwitcherActive.keystone,
  );
}

// --- Profile picture -------------------------------------------------------

/// Which picture the picker opens on.
enum AccountsPictureSelection { defaultPicture, pictureEight }

String accountsPictureSelectionLabel(AccountsPictureSelection selection) {
  return selection == AccountsPictureSelection.defaultPicture
      ? 'Default'
      : 'Picture 8';
}

String accountsPictureIdFor(AccountsPictureSelection selection) {
  return selection == AccountsPictureSelection.defaultPicture
      ? kDefaultProfilePictureId
      : 'pfp-08';
}

Widget buildAccountsProfilePictureSheetGalleryCase(BuildContext context) {
  final selection = wbStateKnob<AccountsPictureSelection>(
    context,
    label: 'Selection',
    options: AccountsPictureSelection.values,
    labelBuilder: accountsPictureSelectionLabel,
  );
  return accountsProfilePictureSheetFixture(
    selectedId: accountsPictureIdFor(selection),
  );
}

Widget buildAccountsProfilePictureModalGalleryCase(BuildContext context) {
  final selection = wbStateKnob<AccountsPictureSelection>(
    context,
    label: 'Selection',
    options: AccountsPictureSelection.values,
    labelBuilder: accountsPictureSelectionLabel,
  );
  return accountsProfilePictureModalFixture(
    currentProfilePictureId: accountsPictureIdFor(selection),
  );
}

// --- Remove account modal --------------------------------------------------

/// Whether the modal removes one account or resets the whole wallet.
enum AccountsRemoveScope { removeAccount, lastAccountReset }

String accountsRemoveScopeLabel(AccountsRemoveScope scope) {
  return scope == AccountsRemoveScope.removeAccount
      ? 'Remove account'
      : 'Last account reset';
}

enum AccountsRemoveSwapCheck { none, checking, activeSwaps, failed }

String accountsRemoveSwapCheckLabel(AccountsRemoveSwapCheck check) {
  return switch (check) {
    AccountsRemoveSwapCheck.none => 'None',
    AccountsRemoveSwapCheck.checking => 'Checking',
    AccountsRemoveSwapCheck.activeSwaps => '3 active swaps',
    AccountsRemoveSwapCheck.failed => 'Check failed',
  };
}

enum AccountsRemoveGiftCardCheck {
  none,
  checkingReceiving,
  receivingCard,
  receivingFailed,
  checkingUnshared,
  unsharedCards,
  unsharedFailed,
}

String accountsRemoveGiftCardCheckLabel(AccountsRemoveGiftCardCheck check) {
  return switch (check) {
    AccountsRemoveGiftCardCheck.none => 'None',
    AccountsRemoveGiftCardCheck.checkingReceiving => 'Checking receiving',
    AccountsRemoveGiftCardCheck.receivingCard => '1 receiving card',
    AccountsRemoveGiftCardCheck.receivingFailed => 'Receiving check failed',
    AccountsRemoveGiftCardCheck.checkingUnshared => 'Checking unshared',
    AccountsRemoveGiftCardCheck.unsharedCards => '4 unshared cards',
    AccountsRemoveGiftCardCheck.unsharedFailed => 'Unshared check failed',
  };
}

Widget buildAccountsRemoveModalGalleryCase(BuildContext context) {
  final scope = wbStateKnob<AccountsRemoveScope>(
    context,
    label: 'Scope',
    options: AccountsRemoveScope.values,
    labelBuilder: accountsRemoveScopeLabel,
  );
  final swapCheck = wbStateKnob<AccountsRemoveSwapCheck>(
    context,
    label: 'Swap check',
    options: AccountsRemoveSwapCheck.values,
    labelBuilder: accountsRemoveSwapCheckLabel,
  );
  final giftCardCheck = wbStateKnob<AccountsRemoveGiftCardCheck>(
    context,
    label: 'Gift card check',
    options: AccountsRemoveGiftCardCheck.values,
    labelBuilder: accountsRemoveGiftCardCheckLabel,
  );
  return accountsRemoveModalFixture(
    isLastAccount: scope == AccountsRemoveScope.lastAccountReset,
    pendingSwapCount: swapCheck == AccountsRemoveSwapCheck.activeSwaps ? 3 : 0,
    checkingPendingSwaps: swapCheck == AccountsRemoveSwapCheck.checking,
    pendingSwapCheckFailed: swapCheck == AccountsRemoveSwapCheck.failed,
    receivingGiftCardCount:
        giftCardCheck == AccountsRemoveGiftCardCheck.receivingCard ? 1 : 0,
    checkingReceivingGiftCards:
        giftCardCheck == AccountsRemoveGiftCardCheck.checkingReceiving,
    unsharedGiftCardCount:
        giftCardCheck == AccountsRemoveGiftCardCheck.unsharedCards ? 4 : 0,
    checkingUnsharedGiftCards:
        giftCardCheck == AccountsRemoveGiftCardCheck.checkingUnshared,
    receivingGiftCardCheckFailed:
        giftCardCheck == AccountsRemoveGiftCardCheck.receivingFailed,
    unsharedGiftCardCheckFailed:
        giftCardCheck == AccountsRemoveGiftCardCheck.unsharedFailed,
  );
}

// --- Edit account modal ----------------------------------------------------

enum AccountsEditName { unchanged, renamed, tooLong }

String accountsEditNameLabel(AccountsEditName name) {
  return switch (name) {
    AccountsEditName.unchanged => 'Unchanged',
    AccountsEditName.renamed => 'Renamed',
    AccountsEditName.tooLong => 'Too long',
  };
}

enum AccountsEditPicture { unchanged, changed }

String accountsEditPictureLabel(AccountsEditPicture picture) {
  return picture == AccountsEditPicture.unchanged ? 'Unchanged' : 'Changed';
}

Widget buildAccountsEditModalGalleryCase(BuildContext context) {
  final name = wbStateKnob<AccountsEditName>(
    context,
    label: 'Name',
    options: AccountsEditName.values,
    labelBuilder: accountsEditNameLabel,
  );
  final picture = wbStateKnob<AccountsEditPicture>(
    context,
    label: 'Picture',
    options: AccountsEditPicture.values,
    labelBuilder: accountsEditPictureLabel,
  );
  return accountsEditModalFixture(
    initialName: switch (name) {
      AccountsEditName.unchanged => 'Account Name',
      AccountsEditName.renamed => 'Travel Vault',
      AccountsEditName.tooLong => 'An account name well past twenty',
    },
    profilePictureChanged: picture == AccountsEditPicture.changed,
  );
}

// --- Account modal card ----------------------------------------------------

enum AccountsModalCardAction { primary, destructive }

String accountsModalCardActionLabel(AccountsModalCardAction action) {
  return action == AccountsModalCardAction.primary ? 'Primary' : 'Destructive';
}

enum AccountsModalCardIcon { none, trash }

String accountsModalCardIconLabel(AccountsModalCardIcon icon) {
  return icon == AccountsModalCardIcon.none ? 'None' : 'Trash';
}

Widget buildAccountsModalCardGalleryCase(BuildContext context) {
  final action = wbStateKnob<AccountsModalCardAction>(
    context,
    label: 'Action variant',
    options: AccountsModalCardAction.values,
    labelBuilder: accountsModalCardActionLabel,
  );
  final icon = wbStateKnob<AccountsModalCardIcon>(
    context,
    label: 'Action icon',
    options: AccountsModalCardIcon.values,
    labelBuilder: accountsModalCardIconLabel,
  );
  final cancelEnabled = wbBoolKnob(
    context,
    label: 'Cancel enabled',
    initial: true,
  );
  final actionEnabled = wbBoolKnob(
    context,
    label: 'Action enabled',
    initial: true,
  );
  return accountsModalCardFixture(
    destructiveAction: action == AccountsModalCardAction.destructive,
    trashIcon: icon == AccountsModalCardIcon.trash,
    cancelEnabled: cancelEnabled,
    actionEnabled: actionEnabled,
  );
}

// --- Settings screen -------------------------------------------------------

/// Which account is active on a settings screen; the hardware and no-account
/// states are what disable the Account block's rows.
enum SettingsAccount { software, keystone, none }

String settingsAccountLabel(SettingsAccount account) {
  return switch (account) {
    SettingsAccount.software => 'Software',
    SettingsAccount.keystone => 'Keystone',
    SettingsAccount.none => 'None',
  };
}

AccountState settingsAccountStateFor(SettingsAccount account) {
  return switch (account) {
    SettingsAccount.software => accountsPreviewDesignState,
    SettingsAccount.keystone => accountsPreviewKeystoneActiveState,
    SettingsAccount.none => accountsPreviewEmptyState,
  };
}

/// The stored theme preference the Theme row reports. The preview's own
/// colours stay on the Theme addon.
enum SettingsThemeValue { system, light, dark }

String settingsThemeValueLabel(SettingsThemeValue theme) {
  return switch (theme) {
    SettingsThemeValue.system => 'System',
    SettingsThemeValue.light => 'Light',
    SettingsThemeValue.dark => 'Dark',
  };
}

ThemeMode settingsThemeModeFor(SettingsThemeValue theme) {
  return switch (theme) {
    SettingsThemeValue.system => ThemeMode.system,
    SettingsThemeValue.light => ThemeMode.light,
    SettingsThemeValue.dark => ThemeMode.dark,
  };
}

/// Desktop Tor states, including the two that only exist when software
/// updates cannot go through the current route.
enum SettingsDesktopTor {
  off,
  connecting,
  connected,
  switchingToDirect,
  failed,
  updatesUnavailable,
}

String settingsDesktopTorLabel(SettingsDesktopTor tor) {
  return switch (tor) {
    SettingsDesktopTor.off => 'Off',
    SettingsDesktopTor.connecting => 'Connecting',
    SettingsDesktopTor.connected => 'Connected',
    SettingsDesktopTor.switchingToDirect => 'Switching to direct',
    SettingsDesktopTor.failed => 'Failed',
    SettingsDesktopTor.updatesUnavailable => 'Updates unavailable',
  };
}

NetworkPrivacyState settingsDesktopTorStateFor(SettingsDesktopTor tor) {
  return switch (tor) {
    SettingsDesktopTor.off => const NetworkPrivacyState.off(),
    SettingsDesktopTor.connecting => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connecting,
    ),
    SettingsDesktopTor.connected => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connected,
    ),
    SettingsDesktopTor.switchingToDirect => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connecting,
      targetTorEnabled: false,
    ),
    SettingsDesktopTor.failed => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      error: 'Preview Tor bootstrap failure',
    ),
    SettingsDesktopTor.updatesUnavailable => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connected,
      softwareUpdatesAvailable: false,
    ),
  };
}

/// Where the desktop settings list is parked.
///
/// [system] is the mid-list stop; the Support Vizor row is the list's *last*
/// row, so it is what [bottom] shows rather than a stop of its own.
enum SettingsDesktopScroll { top, system, bottom }

String settingsDesktopScrollLabel(SettingsDesktopScroll scroll) {
  return switch (scroll) {
    SettingsDesktopScroll.top => 'Top',
    SettingsDesktopScroll.system => 'System',
    SettingsDesktopScroll.bottom => 'Bottom',
  };
}

/// Which overlay the desktop settings screen opens on. `Updates` is the
/// Windows-only updater modal; its download dialogs are root-navigator
/// `showDialog`s and preview in the `Update dialogs` case instead.
enum SettingsDesktopModal { none, theme, updates }

String settingsDesktopModalLabel(SettingsDesktopModal modal) {
  return switch (modal) {
    SettingsDesktopModal.none => 'None',
    SettingsDesktopModal.theme => 'Theme',
    SettingsDesktopModal.updates => 'Updates',
  };
}

/// The updater states the Updates modal renders differently. `notChecked` is
/// the state before any check runs, `unsupported` the non-Windows build's
/// copy, and the two failure options separate the app's own fallback line
/// from an installer message the modal echoes verbatim.
enum SettingsUpdater {
  notChecked,
  available,
  checking,
  downloading,
  readyToRestart,
  restarting,
  upToDate,
  failed,
  failedWithDetail,
  unsupported,
}

String settingsUpdaterLabel(SettingsUpdater updater) {
  return switch (updater) {
    SettingsUpdater.notChecked => 'Not checked yet',
    SettingsUpdater.available => 'Update available',
    SettingsUpdater.checking => 'Checking',
    SettingsUpdater.downloading => 'Downloading',
    SettingsUpdater.readyToRestart => 'Ready to restart',
    SettingsUpdater.restarting => 'Restarting',
    SettingsUpdater.upToDate => 'Up to date',
    SettingsUpdater.failed => 'Failed',
    SettingsUpdater.failedWithDetail => 'Failed with detail',
    SettingsUpdater.unsupported => 'Not supported',
  };
}

WindowsUpdateState settingsUpdaterStateFor(SettingsUpdater updater) {
  return settingsPreviewWindowsUpdateStateFor(
    switch (updater) {
      SettingsUpdater.notChecked => WindowsUpdateStatus.idle,
      SettingsUpdater.available => WindowsUpdateStatus.available,
      SettingsUpdater.checking => WindowsUpdateStatus.checking,
      SettingsUpdater.downloading => WindowsUpdateStatus.downloading,
      SettingsUpdater.readyToRestart => WindowsUpdateStatus.ready,
      SettingsUpdater.restarting => WindowsUpdateStatus.applying,
      SettingsUpdater.upToDate => WindowsUpdateStatus.noUpdate,
      SettingsUpdater.failed ||
      SettingsUpdater.failedWithDetail => WindowsUpdateStatus.failed,
      SettingsUpdater.unsupported => WindowsUpdateStatus.unavailable,
    },
    supported: updater != SettingsUpdater.unsupported,
    // Only the installer-reported failure carries a message; the plain one
    // leaves the modal on its own copy.
    message: updater == SettingsUpdater.failedWithDetail
        ? 'The update package could not be downloaded. Try again.'
        : '',
  );
}

SettingsPreviewDesktopModal settingsDesktopModalTargetFor(
  SettingsDesktopModal modal,
) {
  return switch (modal) {
    SettingsDesktopModal.none => SettingsPreviewDesktopModal.none,
    SettingsDesktopModal.theme => SettingsPreviewDesktopModal.theme,
    SettingsDesktopModal.updates => SettingsPreviewDesktopModal.updates,
  };
}

/// Which Windows update download dialog the preview shows. The Tor options
/// come from the pre-download privacy checks, the last three from a download
/// the updater refused to start.
enum SettingsUpdateDialog {
  privacyChoice,
  torRouteBlocked,
  torStillOn,
  updatesUnavailable,
  downloadNotStarted,
  downloadNotReady,
  updaterOffTor,
}

String settingsUpdateDialogLabel(SettingsUpdateDialog dialog) {
  return switch (dialog) {
    SettingsUpdateDialog.privacyChoice => 'Tor choice',
    SettingsUpdateDialog.torRouteBlocked => 'Updates blocked over Tor',
    SettingsUpdateDialog.torStillOn => 'Tor still on',
    SettingsUpdateDialog.updatesUnavailable => 'Updates unavailable',
    SettingsUpdateDialog.downloadNotStarted => "Download didn't start",
    SettingsUpdateDialog.downloadNotReady => 'No longer ready',
    SettingsUpdateDialog.updaterOffTor => 'Updater off Tor',
  };
}

SettingsPreviewUpdateDialog settingsUpdateDialogTargetFor(
  SettingsUpdateDialog dialog,
) {
  return switch (dialog) {
    SettingsUpdateDialog.privacyChoice =>
      SettingsPreviewUpdateDialog.privacyChoice,
    SettingsUpdateDialog.torRouteBlocked =>
      SettingsPreviewUpdateDialog.torRouteBlocked,
    SettingsUpdateDialog.torStillOn => SettingsPreviewUpdateDialog.torStillOn,
    SettingsUpdateDialog.updatesUnavailable =>
      SettingsPreviewUpdateDialog.updatesUnavailable,
    SettingsUpdateDialog.downloadNotStarted =>
      SettingsPreviewUpdateDialog.downloadNotStarted,
    SettingsUpdateDialog.downloadNotReady =>
      SettingsPreviewUpdateDialog.downloadNotReady,
    SettingsUpdateDialog.updaterOffTor =>
      SettingsPreviewUpdateDialog.updaterOffTor,
  };
}

Widget buildSettingsUpdateDialogsGalleryCase(BuildContext context) {
  final dialog = wbStateKnob<SettingsUpdateDialog>(
    context,
    label: 'Dialog',
    options: SettingsUpdateDialog.values,
    labelBuilder: settingsUpdateDialogLabel,
  );
  return settingsUpdateDialogFixture(
    dialog: settingsUpdateDialogTargetFor(dialog),
  );
}

/// Scroll position of the mobile settings list.
enum SettingsMobileScroll { top, explorerRow, footer }

String settingsMobileScrollLabel(SettingsMobileScroll scroll) {
  return switch (scroll) {
    SettingsMobileScroll.top => 'Top',
    SettingsMobileScroll.explorerRow => 'Explorer row',
    SettingsMobileScroll.footer => 'Footer',
  };
}

MobileSettingsScrollTarget settingsMobileScrollTargetFor(
  SettingsMobileScroll scroll,
) {
  return switch (scroll) {
    SettingsMobileScroll.top => MobileSettingsScrollTarget.top,
    SettingsMobileScroll.explorerRow => MobileSettingsScrollTarget.explorerRow,
    SettingsMobileScroll.footer => MobileSettingsScrollTarget.footer,
  };
}

/// What the device offers behind the biometric row; `None` hides the row.
enum SettingsBiometric { none, faceId, touchId, fingerprint }

String settingsBiometricLabel(SettingsBiometric biometric) {
  return switch (biometric) {
    SettingsBiometric.none => 'None',
    SettingsBiometric.faceId => 'Face ID',
    SettingsBiometric.touchId => 'Touch ID',
    SettingsBiometric.fingerprint => 'Fingerprint',
  };
}

BiometricUnlockState settingsBiometricStateFor(
  SettingsBiometric biometric, {
  required bool enabled,
}) {
  if (biometric == SettingsBiometric.none) {
    return BiometricUnlockState(
      availability: BiometricAvailability.unavailable,
      enabled: enabled,
    );
  }
  return BiometricUnlockState(
    availability: BiometricAvailability(
      supported: true,
      enrolled: true,
      kind: switch (biometric) {
        SettingsBiometric.faceId => BiometricKind.face,
        SettingsBiometric.touchId => BiometricKind.touchId,
        SettingsBiometric.fingerprint => BiometricKind.fingerprint,
        SettingsBiometric.none => BiometricKind.none,
      },
    ),
    enabled: enabled,
  );
}

/// Whether the mobile keep-awake card's toggle is on.
enum SettingsKeepAwake { off, on }

String settingsKeepAwakeLabel(SettingsKeepAwake keepAwake) {
  return keepAwake == SettingsKeepAwake.off ? 'Off' : 'On';
}

/// Tor states the mobile card can show.
enum SettingsMobileTor { off, connecting, connected, failed }

String settingsMobileTorLabel(SettingsMobileTor tor) {
  return switch (tor) {
    SettingsMobileTor.off => 'Off',
    SettingsMobileTor.connecting => 'Connecting',
    SettingsMobileTor.connected => 'Connected',
    SettingsMobileTor.failed => 'Failed',
  };
}

NetworkPrivacyState settingsMobileTorStateFor(SettingsMobileTor tor) {
  return switch (tor) {
    SettingsMobileTor.off => const NetworkPrivacyState.off(),
    SettingsMobileTor.connecting => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connecting,
    ),
    SettingsMobileTor.connected => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connected,
    ),
    SettingsMobileTor.failed => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
    ),
  };
}

/// Which sheet the mobile settings list opens on. `Disable biometric` only
/// exists on a device that has biometrics enrolled and unlock turned on, so it
/// supplies both when the Biometric knobs say otherwise.
enum SettingsMobileSheet { none, theme, disableBiometric }

String settingsMobileSheetLabel(SettingsMobileSheet sheet) {
  return switch (sheet) {
    SettingsMobileSheet.none => 'None',
    SettingsMobileSheet.theme => 'Theme',
    SettingsMobileSheet.disableBiometric => 'Disable biometric',
  };
}

SettingsPreviewMobileSheet settingsMobileSheetTargetFor(
  SettingsMobileSheet sheet,
) {
  return switch (sheet) {
    SettingsMobileSheet.none => SettingsPreviewMobileSheet.none,
    SettingsMobileSheet.theme => SettingsPreviewMobileSheet.theme,
    SettingsMobileSheet.disableBiometric =>
      SettingsPreviewMobileSheet.disableBiometric,
  };
}

/// Account and the stored theme value are the only axes both layouts share:
/// the updater and the desktop scroll stops are desktop-only, the device
/// biometric and keep-awake rows mobile-only, and each layout's Tor and
/// Scroll axes have their own option sets.
Widget buildSettingsScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final account = wbStateKnob<SettingsAccount>(
    context,
    label: 'Account',
    options: SettingsAccount.values,
    labelBuilder: settingsAccountLabel,
  );
  final theme = wbStateKnob<SettingsThemeValue>(
    context,
    label: 'Theme value',
    options: SettingsThemeValue.values,
    labelBuilder: settingsThemeValueLabel,
  );

  if (layout == WbLayout.mobile) {
    final scroll = wbStateKnob<SettingsMobileScroll>(
      context,
      label: 'Scroll',
      options: SettingsMobileScroll.values,
      labelBuilder: settingsMobileScrollLabel,
    );
    final biometric = wbStateKnob<SettingsBiometric>(
      context,
      label: 'Biometric',
      options: SettingsBiometric.values,
      labelBuilder: settingsBiometricLabel,
    );
    final sheet = wbStateKnob<SettingsMobileSheet>(
      context,
      label: 'Sheet',
      options: SettingsMobileSheet.values,
      labelBuilder: settingsMobileSheetLabel,
    );
    final biometricEnabled =
        biometric != SettingsBiometric.none &&
            sheet != SettingsMobileSheet.disableBiometric
        ? wbBoolKnob(context, label: 'Biometric enabled')
        : sheet == SettingsMobileSheet.disableBiometric;
    final keepAwake = wbStateKnob<SettingsKeepAwake>(
      context,
      label: 'Keep awake',
      options: SettingsKeepAwake.values,
      labelBuilder: settingsKeepAwakeLabel,
    );
    final tor = wbStateKnob<SettingsMobileTor>(
      context,
      label: 'Tor',
      options: SettingsMobileTor.values,
      labelBuilder: settingsMobileTorLabel,
    );
    final disableBiometricSheet = sheet == SettingsMobileSheet.disableBiometric;
    return settingsMobileScreenFixture(
      accountState: settingsAccountStateFor(account),
      themeMode: settingsThemeModeFor(theme),
      networkPrivacyState: settingsMobileTorStateFor(tor),
      biometricState: settingsBiometricStateFor(
        disableBiometricSheet && biometric == SettingsBiometric.none
            ? SettingsBiometric.faceId
            : biometric,
        enabled: biometricEnabled || disableBiometricSheet,
      ),
      keepAwakeEnabled: keepAwake == SettingsKeepAwake.on,
      scroll: settingsMobileScrollTargetFor(scroll),
      sheet: settingsMobileSheetTargetFor(sheet),
      interactive: true,
      routeBuilders: _settingsPreviewRoutes(layout),
      rpcEndpointConfig: settingsPreviewDefaultEndpoint,
      endpointLatency: settingsPreviewEndpointLatencyState(),
      explorerUrlTemplate: '',
      appSecurityState: const AppSecurityState(
        isPasswordConfigured: true,
        isUnlocked: true,
      ),
    );
  }

  final tor = wbStateKnob<SettingsDesktopTor>(
    context,
    label: 'Tor',
    options: SettingsDesktopTor.values,
    labelBuilder: settingsDesktopTorLabel,
  );
  final scroll = wbStateKnob<SettingsDesktopScroll>(
    context,
    label: 'Scroll',
    options: SettingsDesktopScroll.values,
    labelBuilder: settingsDesktopScrollLabel,
  );
  final modal = wbStateKnob<SettingsDesktopModal>(
    context,
    label: 'Modal',
    options: SettingsDesktopModal.values,
    labelBuilder: settingsDesktopModalLabel,
  );
  // The fixture swaps to Windows only for the Updates modal, which is also the
  // only place this status is visible.
  final updater = modal == SettingsDesktopModal.updates
      ? wbStateKnob<SettingsUpdater>(
          context,
          label: 'Updater',
          options: SettingsUpdater.values,
          initial: SettingsUpdater.available,
          labelBuilder: settingsUpdaterLabel,
        )
      : SettingsUpdater.available;
  return settingsDesktopScreenFixture(
    updater: settingsUpdaterStateFor(updater),
    accountState: settingsAccountStateFor(account),
    themeMode: settingsThemeModeFor(theme),
    networkPrivacyState: settingsDesktopTorStateFor(tor),
    modal: settingsDesktopModalTargetFor(modal),
    routeBuilders: _settingsPreviewRoutes(layout),
    rpcEndpointConfig: settingsPreviewDefaultEndpoint,
    endpointLatency: settingsPreviewEndpointLatencyState(),
    explorerUrlTemplate: '',
    appSecurityState: const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    ),
    initialScrollOffset: switch (scroll) {
      SettingsDesktopScroll.top => 0,
      // The preview is the app's real 1080x720 window, whose 704px viewport
      // leaves 695px of travel, so the System block is the only section that
      // a middle stop can show whole. The Support Vizor row sits at the very
      // end of the list and only enters the viewport in the last ~20px of
      // travel, which is what the bottom stop already shows —
      // `settings-support-vizor` in `figma_compare_scenarios.dart` is the
      // capture for that row.
      SettingsDesktopScroll.system => 400,
      // Past the list end; the scroll position clamps to the bottom.
      SettingsDesktopScroll.bottom => 4000,
    },
  );
}

Map<String, WidgetBuilder> _settingsPreviewRoutes(WbLayout layout) {
  return {
    '/settings/endpoint': (_) => layout == WbLayout.desktop
        ? const SettingsEndpointScreen()
        : const MobileEndpointScreen(),
    '/settings/explorer': (_) => layout == WbLayout.desktop
        ? const SettingsExplorerScreen()
        : const MobileExplorerScreen(),
    '/about': (routeContext) => _PreviewSafeAboutRoute(
      content: layout == WbLayout.desktop
          ? const AboutScreen()
          : const MobileAboutScreen(),
      onBack: () => Navigator.of(routeContext).maybePop(),
    ),
    '/unlock': (routeContext) =>
        _PreviewSignedOutRoute(onBack: () => routeContext.go('/settings')),
    for (final path in const [
      '/settings/secret-passphrase',
      '/settings/seed-phrase',
      '/settings/viewing-key',
      '/settings/change-password',
      '/settings/link-mobile',
      '/settings/uninstall',
      '/settings/address-book',
      '/address-book',
      '/voting',
      '/payment-links',
      '/donation',
      '/privacy',
      '/terms',
      '/home',
      '/send',
      '/receive',
      '/activity',
      '/accounts',
    ])
      path: (routeContext) => _PreviewOnlySettingsRoute(
        title: _routeTitle(path),
        onBack: () => Navigator.of(routeContext).maybePop(),
      ),
  };
}

String _routeTitle(String path) => switch (path) {
  '/settings/secret-passphrase' ||
  '/settings/seed-phrase' => 'Secret Passphrase',
  '/settings/viewing-key' => 'Viewing Key',
  '/settings/change-password' => 'Password',
  '/settings/link-mobile' => 'Link mobile',
  '/settings/uninstall' => 'Uninstall Vizor',
  '/settings/address-book' || '/address-book' => 'Address book',
  '/voting' => 'Coinholder voting',
  '/payment-links' => 'Gift cards',
  '/donation' => 'Donation',
  '/privacy' => 'Privacy policy',
  '/terms' => 'Terms of use',
  '/home' => 'Home',
  '/send' => 'Send',
  '/receive' => 'Receive',
  '/activity' => 'Activity',
  '/accounts' => 'Accounts',
  _ => 'Settings',
};

class _PreviewSafeAboutRoute extends StatelessWidget {
  const _PreviewSafeAboutRoute({required this.content, required this.onBack});

  final Widget content;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      IgnorePointer(child: content),
      SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: context.colors.background.window,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: const ValueKey('settings_flow_about_back'),
                    onPressed: onBack,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Text('Preview only: external links are disabled.'),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _PreviewSignedOutRoute extends StatelessWidget {
  const _PreviewSignedOutRoute({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Signed out (preview)', style: AppTypography.headlineLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'No wallet session or secure storage was changed. Use Reset '
              'preview for a fresh session, or go back to Settings.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              key: const ValueKey('settings_flow_signed_out_back'),
              onPressed: onBack,
              child: const Text('Back to settings'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewOnlySettingsRoute extends StatelessWidget {
  const _PreviewOnlySettingsRoute({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    appBar: AppBar(
      title: Text(title),
      leading: IconButton(
        key: const ValueKey('settings_flow_back'),
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.headlineLarge),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'This action needs a wallet, secure storage, or device service. '
            'It is unavailable in this isolated preview.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    ),
  );
}

// --- Network privacy -------------------------------------------------------

/// Connection status published by the network-privacy provider.
enum SettingsTorStatus { off, connecting, connected, failed }

String settingsTorStatusLabel(SettingsTorStatus status) {
  return switch (status) {
    SettingsTorStatus.off => 'Off',
    SettingsTorStatus.connecting => 'Connecting',
    SettingsTorStatus.connected => 'Connected',
    SettingsTorStatus.failed => 'Failed',
  };
}

NetworkPrivacyConnectionStatus settingsTorConnectionStatusFor(
  SettingsTorStatus status,
) {
  return switch (status) {
    SettingsTorStatus.off => NetworkPrivacyConnectionStatus.off,
    SettingsTorStatus.connecting => NetworkPrivacyConnectionStatus.connecting,
    SettingsTorStatus.connected => NetworkPrivacyConnectionStatus.connected,
    SettingsTorStatus.failed => NetworkPrivacyConnectionStatus.failed,
  };
}

/// A route the control can be asked for or has saved.
enum SettingsTorRoute { tor, direct }

String settingsTorRouteLabel(SettingsTorRoute route) {
  return route == SettingsTorRoute.tor ? 'Tor' : 'Direct';
}

/// Whether software updates can reach the network on the current route.
enum SettingsSoftwareUpdates { available, unavailable }

String settingsSoftwareUpdatesLabel(SettingsSoftwareUpdates updates) {
  return updates == SettingsSoftwareUpdates.available
      ? 'Available'
      : 'Unavailable';
}

/// Both layouts read the same provider triple; only the desktop control also
/// reports whether software updates can reach the network, and only it has a
/// surface to sit on.
Widget buildSettingsNetworkPrivacyGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final status = wbStateKnob<SettingsTorStatus>(
    context,
    label: 'Status',
    options: SettingsTorStatus.values,
    labelBuilder: settingsTorStatusLabel,
  );
  final target = wbStateKnob<SettingsTorRoute>(
    context,
    label: 'Target',
    options: SettingsTorRoute.values,
    labelBuilder: settingsTorRouteLabel,
  );
  // Desktop draws its toggle on the saved route, so a mid-switch state keeps
  // the route the wallet still has; mobile reads it to separate "requests stay
  // blocked" from "the setting was not saved" on a failure.
  final saved = wbStateKnob<SettingsTorRoute>(
    context,
    label: 'Saved route',
    options: SettingsTorRoute.values,
    labelBuilder: settingsTorRouteLabel,
  );

  if (layout == WbLayout.mobile) {
    return settingsMobileNetworkPrivacyCardFixture(
      state: NetworkPrivacyState(
        torEnabled: saved == SettingsTorRoute.tor,
        status: settingsTorConnectionStatusFor(status),
        targetTorEnabled: target == SettingsTorRoute.tor,
      ),
    );
  }

  final updates = wbStateKnob<SettingsSoftwareUpdates>(
    context,
    label: 'Software updates',
    options: SettingsSoftwareUpdates.values,
    labelBuilder: settingsSoftwareUpdatesLabel,
  );
  final surface = wbBoolKnob(context, label: 'Surface', initial: true);

  return settingsNetworkPrivacyControlFixture(
    state: NetworkPrivacyState(
      torEnabled: saved == SettingsTorRoute.tor,
      status: settingsTorConnectionStatusFor(status),
      targetTorEnabled: target == SettingsTorRoute.tor,
      softwareUpdatesAvailable: updates == SettingsSoftwareUpdates.available,
    ),
    showSurface: surface,
  );
}

// --- Confirm access card ---------------------------------------------------

/// Which flow's gate is on screen; only the subtitle differs.
enum SettingsConfirmAccessFlow {
  secretPassphrase,
  viewingKey,
  currentPassword,
  uninstall,
  linkMobile,
}

String settingsConfirmAccessFlowLabel(SettingsConfirmAccessFlow flow) {
  return switch (flow) {
    SettingsConfirmAccessFlow.secretPassphrase => 'Secret passphrase',
    SettingsConfirmAccessFlow.viewingKey => 'Viewing key',
    SettingsConfirmAccessFlow.currentPassword => 'Current password',
    SettingsConfirmAccessFlow.uninstall => 'Uninstall',
    SettingsConfirmAccessFlow.linkMobile => 'Link mobile',
  };
}

String settingsConfirmAccessSubtitleFor(SettingsConfirmAccessFlow flow) {
  return switch (flow) {
    SettingsConfirmAccessFlow.secretPassphrase =>
      'To view the secret passphrase.',
    SettingsConfirmAccessFlow.viewingKey => 'To view the viewing key.',
    SettingsConfirmAccessFlow.currentPassword =>
      'Enter your current password first.',
    SettingsConfirmAccessFlow.uninstall => 'To uninstall Vizor.',
    SettingsConfirmAccessFlow.linkMobile => 'To link Vizor Mobile.',
  };
}

enum SettingsConfirmAccessError {
  none,
  passwordPolicy,
  incorrectPassword,
  accountChanged,
  sessionChanged,
  checkFailed,
}

String settingsConfirmAccessErrorLabel(SettingsConfirmAccessError error) {
  return switch (error) {
    SettingsConfirmAccessError.none => 'None',
    SettingsConfirmAccessError.passwordPolicy => 'Password policy',
    SettingsConfirmAccessError.incorrectPassword => 'Incorrect password',
    SettingsConfirmAccessError.accountChanged => 'Account changed',
    SettingsConfirmAccessError.sessionChanged => 'Session changed',
    SettingsConfirmAccessError.checkFailed => 'Check failed',
  };
}

String? settingsConfirmAccessErrorTextFor(SettingsConfirmAccessError error) {
  return switch (error) {
    SettingsConfirmAccessError.none => null,
    SettingsConfirmAccessError.passwordPolicy =>
      kWalletPasswordMinLengthMessage,
    SettingsConfirmAccessError.incorrectPassword =>
      'Incorrect password. Please try again.',
    SettingsConfirmAccessError.accountChanged =>
      'Selected account changed. Enter your password again.',
    SettingsConfirmAccessError.sessionChanged =>
      'The wallet session changed. Enter your password again.',
    SettingsConfirmAccessError.checkFailed =>
      "Couldn't check your password. Please try again.",
  };
}

enum SettingsConfirmAccessState { empty, filled, submitting }

String settingsConfirmAccessStateLabel(SettingsConfirmAccessState state) {
  return switch (state) {
    SettingsConfirmAccessState.empty => 'Empty',
    SettingsConfirmAccessState.filled => 'Filled',
    SettingsConfirmAccessState.submitting => 'Submitting',
  };
}

Widget buildSettingsConfirmAccessCardGalleryCase(BuildContext context) {
  final flow = wbStateKnob<SettingsConfirmAccessFlow>(
    context,
    label: 'Subtitle',
    options: SettingsConfirmAccessFlow.values,
    labelBuilder: settingsConfirmAccessFlowLabel,
  );
  final error = wbStateKnob<SettingsConfirmAccessError>(
    context,
    label: 'Error',
    options: SettingsConfirmAccessError.values,
    labelBuilder: settingsConfirmAccessErrorLabel,
  );
  final state = wbStateKnob<SettingsConfirmAccessState>(
    context,
    label: 'State',
    options: SettingsConfirmAccessState.values,
    labelBuilder: settingsConfirmAccessStateLabel,
  );
  return settingsConfirmAccessCardFixture(
    subtitle: settingsConfirmAccessSubtitleFor(flow),
    errorText: settingsConfirmAccessErrorTextFor(error),
    password: state == SettingsConfirmAccessState.empty
        ? ''
        : 'preview-password',
    isSubmitting: state == SettingsConfirmAccessState.submitting,
  );
}

// --- Pane backdrop ---------------------------------------------------------

String settingsBackdropArtLabel(SettingsBackdropArt art) {
  return art == SettingsBackdropArt.castle ? 'Castle' : 'Vault';
}

Widget buildSettingsPaneBackdropGalleryCase(BuildContext context) {
  final art = wbStateKnob<SettingsBackdropArt>(
    context,
    label: 'Art',
    options: SettingsBackdropArt.values,
    labelBuilder: settingsBackdropArtLabel,
  );
  return settingsPaneBackdropFixture(art: art);
}

// --- Settings sub-screens --------------------------------------------------

enum SettingsExplorerChoice { preset, custom }

Widget buildSettingsExplorerGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final choice = wbStateKnob<SettingsExplorerChoice>(
    context,
    label: 'Choice',
    options: SettingsExplorerChoice.values,
    labelBuilder: settingsExplorerChoiceLabel,
  );
  if (layout == WbLayout.mobile) {
    return switch (choice) {
      SettingsExplorerChoice.preset => buildMobileExplorerUseCase(context),
      SettingsExplorerChoice.custom => buildMobileExplorerCustomUseCase(
        context,
      ),
    };
  }
  return switch (choice) {
    SettingsExplorerChoice.preset => buildSettingsExplorerUseCase(context),
    SettingsExplorerChoice.custom => buildSettingsExplorerCustomUseCase(
      context,
    ),
  };
}

String settingsExplorerChoiceLabel(SettingsExplorerChoice choice) {
  return switch (choice) {
    SettingsExplorerChoice.preset => 'Preset',
    SettingsExplorerChoice.custom => 'Custom',
  };
}

enum SettingsPassphraseStage { gate, reveal }

/// How many words the account's seed has.
enum SettingsPassphraseWords { twentyFour, twelve }

/// Whether the account was created with a BIP39 passphrase.
enum SettingsPassphraseBip39 { off, on }

/// Whether the birthday lookups came back; unavailable is the '-' row.
enum SettingsPassphraseBirthday { loaded, unavailable }

/// Mobile only has the gate: its reveal needs a real passcode check, so the
/// desktop stage and seed axes are not offered there and the device biometric
/// axis is not offered on desktop.
Widget buildSettingsPassphraseGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  if (layout == WbLayout.mobile) {
    final biometric = wbStateKnob<SettingsBiometric>(
      context,
      label: 'Biometric',
      options: SettingsBiometric.values,
      labelBuilder: settingsBiometricLabel,
    );
    return settingsMobileSeedPhraseGateFixture(
      biometricState: settingsGateBiometricStateFor(biometric),
    );
  }

  final stage = wbStateKnob<SettingsPassphraseStage>(
    context,
    label: 'Stage',
    options: SettingsPassphraseStage.values,
    labelBuilder: settingsPassphraseStageLabel,
  );
  final words = wbStateKnob<SettingsPassphraseWords>(
    context,
    label: 'Word count',
    options: SettingsPassphraseWords.values,
    labelBuilder: settingsPassphraseWordsLabel,
  );
  final bip39 = wbStateKnob<SettingsPassphraseBip39>(
    context,
    label: 'BIP39 passphrase',
    options: SettingsPassphraseBip39.values,
    labelBuilder: settingsPassphraseBip39Label,
  );
  final birthday = wbStateKnob<SettingsPassphraseBirthday>(
    context,
    label: 'Birthday',
    options: SettingsPassphraseBirthday.values,
    labelBuilder: settingsPassphraseBirthdayLabel,
  );
  if (stage == SettingsPassphraseStage.gate) {
    return buildSettingsSecretPassphraseGateUseCase(context);
  }
  final birthdayLoaded = birthday == SettingsPassphraseBirthday.loaded;
  return settingsSeedPhraseRevealFixture(
    mnemonic: words == SettingsPassphraseWords.twelve
        ? settingsPreviewMnemonic12Words
        : settingsPreviewMnemonic24Words,
    bip39Passphrase: bip39 == SettingsPassphraseBip39.on
        ? settingsPreviewBip39Passphrase
        : null,
    birthdayHeight: birthdayLoaded ? kSettingsPreviewBirthdayHeight : 0,
    birthdayBlockTime: birthdayLoaded ? kSettingsPreviewBirthdayBlockTime : 0,
  );
}

String settingsPassphraseStageLabel(SettingsPassphraseStage stage) {
  return switch (stage) {
    SettingsPassphraseStage.gate => 'Gate',
    SettingsPassphraseStage.reveal => 'Reveal',
  };
}

String settingsPassphraseWordsLabel(SettingsPassphraseWords words) {
  return switch (words) {
    SettingsPassphraseWords.twentyFour => '24 words',
    SettingsPassphraseWords.twelve => '12 words',
  };
}

String settingsPassphraseBip39Label(SettingsPassphraseBip39 bip39) {
  return bip39 == SettingsPassphraseBip39.off ? 'Off' : 'On';
}

String settingsPassphraseBirthdayLabel(SettingsPassphraseBirthday birthday) {
  return switch (birthday) {
    SettingsPassphraseBirthday.loaded => 'Loaded',
    SettingsPassphraseBirthday.unavailable => 'Unavailable',
  };
}

/// A gate footer only appears for a device that offers biometrics *and* has
/// them enabled, so the two travel together on this axis.
BiometricUnlockState settingsGateBiometricStateFor(
  SettingsBiometric biometric,
) {
  return settingsBiometricStateFor(
    biometric,
    enabled: biometric != SettingsBiometric.none,
  );
}

enum SettingsViewingKeyStage { gate, reveal }

/// Mobile opens on the reveal, which is the state that has a registered
/// fixture there, and carries the device-biometric axis its gate varies on.
Widget buildSettingsViewingKeyGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final mobile = layout == WbLayout.mobile;
  final stage = wbStateKnob<SettingsViewingKeyStage>(
    context,
    label: 'Stage',
    options: SettingsViewingKeyStage.values,
    labelBuilder: settingsViewingKeyStageLabel,
    initial: mobile
        ? SettingsViewingKeyStage.reveal
        : SettingsViewingKeyStage.gate,
  );
  if (mobile) {
    final biometric = wbStateKnob<SettingsBiometric>(
      context,
      label: 'Biometric',
      options: SettingsBiometric.values,
      labelBuilder: settingsBiometricLabel,
    );
    return switch (stage) {
      SettingsViewingKeyStage.gate => settingsMobileViewingKeyGateFixture(
        biometricState: settingsGateBiometricStateFor(biometric),
      ),
      SettingsViewingKeyStage.reveal =>
        buildMobileSettingsViewingKeyRevealUseCase(context),
    };
  }
  return switch (stage) {
    SettingsViewingKeyStage.gate => buildSettingsViewingKeyGateUseCase(context),
    SettingsViewingKeyStage.reveal => buildSettingsViewingKeyRevealUseCase(
      context,
    ),
  };
}

String settingsViewingKeyStageLabel(SettingsViewingKeyStage stage) {
  return switch (stage) {
    SettingsViewingKeyStage.gate => 'Gate',
    SettingsViewingKeyStage.reveal => 'Reveal',
  };
}

/// Which endpoint the wallet is pointed at right now. A host outside the
/// preset list opens the screen on its custom tab, which is where production
/// parks a non-preset endpoint.
enum SettingsEndpointCurrent { defaultPreset, customHost }

/// Whether the latency probe has reported.
enum SettingsEndpointLatency { off, on }

Widget buildSettingsEndpointGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final current = wbStateKnob<SettingsEndpointCurrent>(
    context,
    label: 'Current endpoint',
    options: SettingsEndpointCurrent.values,
    labelBuilder: settingsEndpointCurrentLabel,
  );
  final latency = wbStateKnob<SettingsEndpointLatency>(
    context,
    label: 'Latency',
    options: SettingsEndpointLatency.values,
    labelBuilder: settingsEndpointLatencyLabel,
  );
  final endpoint = current == SettingsEndpointCurrent.customHost
      ? settingsPreviewCustomEndpoint
      : settingsPreviewDefaultEndpoint;
  final latencyState = latency == SettingsEndpointLatency.on
      ? settingsPreviewEndpointLatencyState()
      : const RpcEndpointLatencyState();
  if (layout == WbLayout.mobile) {
    return settingsMobileEndpointScreenFixture(
      endpoint: endpoint,
      latency: latencyState,
    );
  }
  return settingsEndpointScreenFixture(
    endpoint: endpoint,
    latency: latencyState,
  );
}

String settingsEndpointCurrentLabel(SettingsEndpointCurrent current) {
  return switch (current) {
    SettingsEndpointCurrent.defaultPreset => 'Default preset',
    SettingsEndpointCurrent.customHost => 'Custom host',
  };
}

String settingsEndpointLatencyLabel(SettingsEndpointLatency latency) {
  return latency == SettingsEndpointLatency.off ? 'Off' : 'On';
}

/// Desktop asks for a password, mobile for a 6-digit passcode; same surface.
Widget buildSettingsChangePasswordGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return layout == WbLayout.mobile
      ? settingsMobileChangePasscodeFixture()
      : buildSettingsChangePasswordGateUseCase(context);
}

enum SettingsUninstallCase { confirm, gate, removing, done }

Widget buildSettingsUninstallGalleryCase(BuildContext context) {
  final stage = wbStateKnob<SettingsUninstallCase>(
    context,
    label: 'Stage',
    options: SettingsUninstallCase.values,
    labelBuilder: settingsUninstallCaseLabel,
  );
  return switch (stage) {
    SettingsUninstallCase.confirm => buildSettingsUninstallConfirmUseCase(
      context,
    ),
    SettingsUninstallCase.gate => settingsUninstallScreenFixture(
      stage: SettingsUninstallStage.gate,
    ),
    SettingsUninstallCase.removing => settingsUninstallScreenFixture(
      stage: SettingsUninstallStage.removing,
    ),
    SettingsUninstallCase.done => buildSettingsUninstallDoneUseCase(context),
  };
}

String settingsUninstallCaseLabel(SettingsUninstallCase stage) {
  return switch (stage) {
    SettingsUninstallCase.confirm => 'Confirm',
    SettingsUninstallCase.gate => 'Gate',
    SettingsUninstallCase.removing => 'Removing',
    SettingsUninstallCase.done => 'Done',
  };
}

// --- Link mobile -----------------------------------------------------------

/// Whether the screen is still behind its password gate or running a session.
enum SettingsLinkMobileStage { gate, session }

String settingsLinkMobileStageLabel(SettingsLinkMobileStage stage) {
  return stage == SettingsLinkMobileStage.gate ? 'Gate' : 'Session';
}

enum SettingsLinkMobilePhase {
  idle,
  preparing,
  qrReady,
  linked,
  expired,
  error,
}

String settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase phase) {
  return switch (phase) {
    SettingsLinkMobilePhase.idle => 'Idle',
    SettingsLinkMobilePhase.preparing => 'Preparing',
    SettingsLinkMobilePhase.qrReady => 'QR ready',
    SettingsLinkMobilePhase.linked => 'Linked',
    SettingsLinkMobilePhase.expired => 'Expired',
    SettingsLinkMobilePhase.error => 'Error',
  };
}

WalletLinkPhase settingsLinkMobileWalletPhaseFor(
  SettingsLinkMobilePhase phase,
) {
  return switch (phase) {
    SettingsLinkMobilePhase.idle => WalletLinkPhase.idle,
    SettingsLinkMobilePhase.preparing => WalletLinkPhase.preparing,
    SettingsLinkMobilePhase.qrReady => WalletLinkPhase.ready,
    SettingsLinkMobilePhase.linked => WalletLinkPhase.linked,
    SettingsLinkMobilePhase.expired => WalletLinkPhase.expired,
    SettingsLinkMobilePhase.error => WalletLinkPhase.error,
  };
}

/// How much of the one-minute session is left.
enum SettingsLinkMobileRemaining { nearlyFull, nearlyOut, none }

String settingsLinkMobileRemainingLabel(SettingsLinkMobileRemaining remaining) {
  return switch (remaining) {
    SettingsLinkMobileRemaining.nearlyFull => '59s',
    SettingsLinkMobileRemaining.nearlyOut => '5s',
    SettingsLinkMobileRemaining.none => '0s',
  };
}

Duration settingsLinkMobileRemainingFor(SettingsLinkMobileRemaining remaining) {
  return switch (remaining) {
    SettingsLinkMobileRemaining.nearlyFull => const Duration(seconds: 59),
    SettingsLinkMobileRemaining.nearlyOut => const Duration(seconds: 5),
    SettingsLinkMobileRemaining.none => Duration.zero,
  };
}

/// How much this wallet has to hand over; the singular case has its own copy.
enum SettingsLinkMobileCounts { none, one, many }

String settingsLinkMobileCountsLabel(SettingsLinkMobileCounts counts) {
  return switch (counts) {
    SettingsLinkMobileCounts.none => 'None',
    SettingsLinkMobileCounts.one => 'One account, one contact',
    SettingsLinkMobileCounts.many => 'Six accounts, twenty contacts',
  };
}

/// Whether the linked screen reports what mobile actually imported.
enum SettingsLinkMobileImported { estimated, actual }

String settingsLinkMobileImportedLabel(SettingsLinkMobileImported imported) {
  return imported == SettingsLinkMobileImported.estimated
      ? 'Estimated'
      : 'Actual';
}

/// Whether the QR carries a real pairing payload or the empty placeholder.
enum SettingsLinkMobileQr { real, placeholder }

String settingsLinkMobileQrLabel(SettingsLinkMobileQr qr) {
  return qr == SettingsLinkMobileQr.real ? 'Real' : 'Placeholder';
}

/// Whether the failure carries a message from the provider or falls back.
enum SettingsLinkMobileError { providerMessage, fallback }

String settingsLinkMobileErrorLabel(SettingsLinkMobileError error) {
  return error == SettingsLinkMobileError.providerMessage
      ? 'Provider message'
      : 'Fallback';
}

const _settingsLinkMobileQrPayload =
    'vizor://wallet-link/v1?id=7f28d351-2b4c-4cb8-ae15-93824cb4f8db'
    '&key=previewTransferKey123&endpoint=http%3A%2F%2Flocalhost%3A3000';

Widget buildSettingsLinkMobileGalleryCase(BuildContext context) {
  final stage = wbStateKnob<SettingsLinkMobileStage>(
    context,
    label: 'Stage',
    options: SettingsLinkMobileStage.values,
    labelBuilder: settingsLinkMobileStageLabel,
    initial: SettingsLinkMobileStage.session,
  );
  final phase = wbStateKnob<SettingsLinkMobilePhase>(
    context,
    label: 'Phase',
    options: SettingsLinkMobilePhase.values,
    labelBuilder: settingsLinkMobilePhaseLabel,
  );
  final remaining = wbStateKnob<SettingsLinkMobileRemaining>(
    context,
    label: 'Remaining',
    options: SettingsLinkMobileRemaining.values,
    labelBuilder: settingsLinkMobileRemainingLabel,
  );
  final counts = wbStateKnob<SettingsLinkMobileCounts>(
    context,
    label: 'Counts',
    options: SettingsLinkMobileCounts.values,
    labelBuilder: settingsLinkMobileCountsLabel,
    initial: SettingsLinkMobileCounts.many,
  );
  final imported = wbStateKnob<SettingsLinkMobileImported>(
    context,
    label: 'Imported counts',
    options: SettingsLinkMobileImported.values,
    labelBuilder: settingsLinkMobileImportedLabel,
    initial: SettingsLinkMobileImported.actual,
  );
  final qr = wbStateKnob<SettingsLinkMobileQr>(
    context,
    label: 'QR payload',
    options: SettingsLinkMobileQr.values,
    labelBuilder: settingsLinkMobileQrLabel,
  );
  final error = wbStateKnob<SettingsLinkMobileError>(
    context,
    label: 'Error message',
    options: SettingsLinkMobileError.values,
    labelBuilder: settingsLinkMobileErrorLabel,
  );

  if (stage == SettingsLinkMobileStage.gate) {
    return buildSettingsWalletLinkConfirmAccessUseCase(context);
  }
  return settingsWalletLinkScreenFixture(
    previewState: WalletLinkState(
      phase: settingsLinkMobileWalletPhaseFor(phase),
      qrPayload: qr == SettingsLinkMobileQr.real
          ? _settingsLinkMobileQrPayload
          : '',
      remaining: settingsLinkMobileRemainingFor(remaining),
      accountCount: switch (counts) {
        SettingsLinkMobileCounts.none => 0,
        SettingsLinkMobileCounts.one => 1,
        SettingsLinkMobileCounts.many => 6,
      },
      contactCount: switch (counts) {
        SettingsLinkMobileCounts.none => 0,
        SettingsLinkMobileCounts.one => 1,
        SettingsLinkMobileCounts.many => 20,
      },
      actualImportCounts: imported == SettingsLinkMobileImported.actual,
      errorMessage: error == SettingsLinkMobileError.providerMessage
          ? "Couldn't reach the link relay. Check your connection."
          : null,
    ),
  );
}

// --- Utility ---------------------------------------------------------------

enum UtilityDocument { about, terms, privacy }

/// Whether a wallet exists: without one the legal pages are public routes and
/// drop the sidebar.
enum UtilityWallet { present, absent }

/// The onboarding entries force the bare pane even when a wallet exists.
/// About has no such variant — it always renders inside the shell.
enum UtilityPane { shell, fullPane }

/// Mobile has neither the sidebar shell nor the onboarding full pane, so only
/// the document axis is offered there.
Widget buildUtilityDocumentGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final document = wbStateKnob<UtilityDocument>(
    context,
    label: 'Document',
    options: UtilityDocument.values,
    labelBuilder: utilityDocumentLabel,
  );
  if (layout == WbLayout.mobile) {
    return utilityMobileDocumentScreenFixture(
      path: utilityDocumentPath(document),
    );
  }
  final wallet = wbStateKnob<UtilityWallet>(
    context,
    label: 'Wallet',
    options: UtilityWallet.values,
    labelBuilder: utilityWalletLabel,
  );
  final pane = wbStateKnob<UtilityPane>(
    context,
    label: 'Pane',
    options: UtilityPane.values,
    labelBuilder: utilityPaneLabel,
  );
  final hasWallet = wallet == UtilityWallet.present;
  // The three registered fixtures are exactly these combinations; every other
  // one goes through the parameterized fixture.
  if (pane == UtilityPane.shell) {
    if (document == UtilityDocument.about && hasWallet) {
      return buildAboutUtilityUseCase(context);
    }
    if (document == UtilityDocument.terms && !hasWallet) {
      return buildTermsUtilityUseCase(context);
    }
    if (document == UtilityDocument.privacy && !hasWallet) {
      return buildPrivacyUtilityUseCase(context);
    }
  }
  return utilityDocumentScreenFixture(
    path: utilityDocumentPath(document),
    hasWallet: hasWallet,
    forceFullPane: pane == UtilityPane.fullPane,
  );
}

String utilityDocumentPath(UtilityDocument document) {
  return switch (document) {
    UtilityDocument.about => '/about',
    UtilityDocument.terms => '/terms',
    UtilityDocument.privacy => '/privacy',
  };
}

String utilityWalletLabel(UtilityWallet wallet) {
  return wallet == UtilityWallet.present ? 'Present' : 'Absent';
}

String utilityPaneLabel(UtilityPane pane) {
  return switch (pane) {
    UtilityPane.shell => 'Shell with sidebar',
    UtilityPane.fullPane => 'Full pane',
  };
}

String utilityDocumentLabel(UtilityDocument document) {
  return switch (document) {
    UtilityDocument.about => 'About',
    UtilityDocument.terms => 'Terms',
    UtilityDocument.privacy => 'Privacy',
  };
}

// --- Custom endpoint -------------------------------------------------------

String settingsCustomEndpointPresetLabel(SettingsCustomEndpointPreset preset) {
  return preset == SettingsCustomEndpointPreset.custom ? 'Custom' : 'Default';
}

String settingsCustomEndpointLatencyLabel(
  SettingsCustomEndpointLatency latency,
) {
  return switch (latency) {
    SettingsCustomEndpointLatency.none => 'None',
    SettingsCustomEndpointLatency.checking => 'Checking',
    SettingsCustomEndpointLatency.measured => '42 ms',
    SettingsCustomEndpointLatency.unavailable => 'Unavailable',
  };
}

Widget buildSettingsCustomEndpointPanelGalleryCase(BuildContext context) {
  final preset = wbStateKnob<SettingsCustomEndpointPreset>(
    context,
    label: 'Endpoint',
    options: SettingsCustomEndpointPreset.values,
    labelBuilder: settingsCustomEndpointPresetLabel,
  );
  final latency = wbStateKnob<SettingsCustomEndpointLatency>(
    context,
    label: 'Latency',
    options: SettingsCustomEndpointLatency.values,
    labelBuilder: settingsCustomEndpointLatencyLabel,
  );
  return settingsCustomEndpointPanelFixture(
    preset: preset,
    latency: latency,
    // The panel's Tor axis is registered once, on Onboarding > Welcome >
    // Network settings, which hosts this same panel in production.
    networkPrivacyState: const NetworkPrivacyState.off(),
    // The close button only exists where the panel is a dismissible overlay.
    closable: wbBoolKnob(context, label: 'Close button', initial: true),
  );
}

/// What the endpoint field holds. The message under it comes from the
/// production normalizer, so each option is an input that actually fails it
/// (the panel normalizes with `allowDefaultPort: true`, which is why a bare
/// host is accepted rather than rejected).
enum SettingsCustomEndpointInput { empty, valid, hasSpace, notHttps, badPort }

String settingsCustomEndpointInputLabel(SettingsCustomEndpointInput input) {
  return switch (input) {
    SettingsCustomEndpointInput.empty => 'Empty',
    SettingsCustomEndpointInput.valid => 'Host and port',
    SettingsCustomEndpointInput.hasSpace => 'Has a space',
    SettingsCustomEndpointInput.notHttps => 'Not https',
    SettingsCustomEndpointInput.badPort => 'Port out of range',
  };
}

String settingsCustomEndpointInputText(SettingsCustomEndpointInput input) {
  return switch (input) {
    SettingsCustomEndpointInput.empty => '',
    SettingsCustomEndpointInput.valid => 'lwd.example.invalid:9067',
    SettingsCustomEndpointInput.hasSpace => 'lwd example.invalid:9067',
    SettingsCustomEndpointInput.notHttps => 'http://lwd.example.invalid:9067',
    SettingsCustomEndpointInput.badPort => 'lwd.example.invalid:99999',
  };
}

Widget buildSettingsCustomEndpointFormGalleryCase(BuildContext context) {
  final input = wbStateKnob<SettingsCustomEndpointInput>(
    context,
    label: 'Input',
    options: SettingsCustomEndpointInput.values,
    initial: SettingsCustomEndpointInput.valid,
    labelBuilder: settingsCustomEndpointInputLabel,
  );
  return settingsCustomEndpointFormFixture(
    text: settingsCustomEndpointInputText(input),
  );
}

Widget buildSettingsNewBadgeGalleryCase(BuildContext context) {
  return settingsNewBadgeFixture();
}
