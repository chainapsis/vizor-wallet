// ignore_for_file: depend_on_referenced_packages
// Figma comparison tooling is dev-only and may reuse Widgetbook fixtures.

import 'package:flutter/widgets.dart';

import '../widgetbook/home_use_cases.dart';
import '../widgetbook/mobile_pay_use_cases.dart';
import '../widgetbook/pay_use_cases.dart';
import '../widgetbook/carousel_use_cases.dart';
import '../widgetbook/screen_use_cases.dart';
import '../widgetbook/swap_use_cases.dart';
import '../widgetbook/voting_use_cases.dart';

typedef FigmaCompareScenarioBuilder = Widget Function(BuildContext context);

@immutable
class FigmaCompareScenario {
  const FigmaCompareScenario({
    required this.id,
    required this.description,
    required this.builder,
    this.desktop = true,
    this.mobile = false,
  });

  final String id;
  final String description;
  final FigmaCompareScenarioBuilder builder;
  final bool desktop;
  final bool mobile;
}

/// Deterministic previews for the screens changed on the current branch.
///
/// Add a scenario here only when its builder is isolated from production
/// storage, network, wallet, and Rust state. Widgetbook fixtures are preferred
/// because they are already used to review the same UI states.
const figmaCompareScenarios = <FigmaCompareScenario>[
  FigmaCompareScenario(
    id: 'settings-secret-passphrase-reveal',
    description: 'Desktop secret passphrase recovery with BIP39 passphrase',
    builder: buildSettingsSecretPassphraseRevealUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-secret-passphrase-reveal-without-bip39',
    description: 'Desktop secret passphrase recovery without BIP39 section',
    builder: buildSettingsSecretPassphraseRevealWithoutBip39UseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-viewing-key-reveal',
    description: 'Desktop viewing key reveal with privacy guidance',
    builder: buildSettingsViewingKeyRevealUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-settings-viewing-key-reveal',
    description: 'Mobile viewing key reveal with privacy guidance',
    builder: buildMobileSettingsViewingKeyRevealUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'import-secret-passphrase-empty',
    description: 'Desktop wallet import with empty mnemonic fields',
    builder: buildImportSecretPassphraseUseCase,
  ),
  FigmaCompareScenario(
    id: 'import-secret-passphrase-populated',
    description: 'Desktop wallet import with mnemonic and BIP39 passphrase',
    builder: buildImportSecretPassphrasePopulatedUseCase,
  ),
  FigmaCompareScenario(
    id: 'import-secret-passphrase-invalid-word',
    description: 'Desktop wallet import with an invalid mnemonic word',
    builder: buildImportSecretPassphraseInvalidWordUseCase,
  ),
  FigmaCompareScenario(
    id: 'import-secret-passphrase-modal',
    description: 'Desktop wallet import BIP39 passphrase modal',
    builder: buildImportSecretPassphraseModalUseCase,
  ),
  FigmaCompareScenario(
    id: 'app-carousel-preparation-card-1',
    description: 'Preparation information carousel with card 1 selected',
    builder: buildCarouselPreparationCardOneUseCase,
  ),
  FigmaCompareScenario(
    id: 'app-carousel-preparation-card-2',
    description: 'Preparation information carousel with card 2 selected',
    builder: buildCarouselPreparationCardTwoUseCase,
  ),
  FigmaCompareScenario(
    id: 'app-carousel-preparation-card-3',
    description: 'Preparation information carousel with card 3 selected',
    builder: buildCarouselPreparationCardThreeUseCase,
  ),
  FigmaCompareScenario(
    id: 'app-carousel-migration-card-1',
    description: 'Migration information carousel with card 1 selected',
    builder: buildCarouselMigrationCardOneUseCase,
  ),
  FigmaCompareScenario(
    id: 'app-carousel-migration-card-2',
    description: 'Migration information carousel with card 2 selected',
    builder: buildCarouselMigrationCardTwoUseCase,
  ),
  FigmaCompareScenario(
    id: 'app-carousel-migration-card-3',
    description: 'Migration information carousel with card 3 selected',
    builder: buildCarouselMigrationCardThreeUseCase,
  ),
  FigmaCompareScenario(
    id: 'pay-recipient',
    description: 'Pay recipient selection with recent contacts',
    builder: buildPayRecipientUseCase,
  ),
  FigmaCompareScenario(
    id: 'pay-recipient-new-address',
    description: 'Pay recipient with a valid newly typed address',
    builder: buildPayRecipientNewAddressUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-pay-recipient',
    description: 'Mobile Pay recipient selection with recent contacts',
    builder: buildMobilePayRecipientUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'pay-in-progress',
    description: 'Pay activity in-progress state',
    builder: buildPayInProgressUseCase,
  ),
  FigmaCompareScenario(
    id: 'pay-completed',
    description: 'Pay activity completed state',
    builder: buildPayCompletedUseCase,
  ),
  FigmaCompareScenario(
    id: 'customise-account',
    description: 'Desktop account personalisation onboarding screen',
    builder: buildCustomiseAccountUseCase,
  ),
  FigmaCompareScenario(
    id: 'import-customise-account',
    description: 'Desktop imported-account personalisation screen',
    builder: buildImportCustomiseAccountUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-main',
    description: 'Desktop settings with Tor privacy control',
    builder: buildSettingsMainUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-explorer',
    description: 'Desktop explorer settings with CipherScan selected',
    builder: buildSettingsExplorerUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-explorer-custom',
    description: 'Desktop explorer settings with a custom URL template',
    builder: buildSettingsExplorerCustomUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-settings-explorer',
    description: 'Mobile settings scrolled to the Explorer row',
    builder: buildMobileSettingsExplorerUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-explorer',
    description: 'Mobile explorer settings with CipherScan selected',
    builder: buildMobileExplorerUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-explorer-custom',
    description: 'Mobile explorer settings with a custom URL template',
    builder: buildMobileExplorerCustomUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-settings-footer',
    description: 'Mobile settings scrolled to the branded version footer',
    builder: buildMobileSettingsFooterUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'settings-tor-connecting',
    description: 'Desktop settings while Tor is connecting',
    builder: buildSettingsTorConnectingUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-tor-connected',
    description: 'Desktop settings with Tor connected',
    builder: buildSettingsTorConnectedUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-tor-switching-direct',
    description: 'Desktop settings while switching from Tor to direct',
    builder: buildSettingsTorSwitchingToDirectUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-tor-updates-unavailable',
    description: 'Desktop settings when Tor updates are unavailable',
    builder: buildSettingsTorUpdatesUnavailableUseCase,
  ),
  FigmaCompareScenario(
    id: 'settings-tor-failed',
    description: 'Desktop settings after Tor connection failure',
    builder: buildSettingsTorFailedUseCase,
  ),
  FigmaCompareScenario(
    id: 'welcome-large',
    description: 'Desktop first-wallet welcome screen',
    builder: buildWelcomeLargeUseCase,
  ),
  FigmaCompareScenario(
    id: 'welcome-network-settings',
    description: 'Desktop first-wallet network settings with Tor control',
    builder: buildWelcomeNetworkSettingsUseCase,
  ),
  FigmaCompareScenario(
    id: 'welcome-network-settings-tor-connected',
    description: 'Desktop first-wallet network settings with Tor connected',
    builder: buildWelcomeNetworkSettingsTorConnectedUseCase,
  ),
  FigmaCompareScenario(
    id: 'swap-tor-blocked',
    description: 'Desktop swap when the provider blocks a Tor exit',
    builder: buildSwapPageTorBlockedUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-customise-account',
    description: 'Mobile account personalisation onboarding screen',
    builder: buildMobileCustomiseAccountUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-default',
    description: 'Mobile home with deterministic balance and activity',
    builder: buildMobileHomeDefaultUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-polls',
    description: 'Mobile coinholder voting poll list with mock rounds',
    builder: buildMobileVotingPollsUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-polls-eligibility',
    description: 'Mobile voting list: ineligible, active, voted, closed',
    builder: buildMobileVotingPollsEligibilityUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-config-default',
    description: 'Mobile voting config matching Figma 8048:71604',
    builder: buildMobileVotingConfigDefaultUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-config',
    description: 'Mobile voting config source modal',
    builder: buildMobileVotingConfigUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-voted',
    description: 'Mobile completed coinholder vote detail',
    builder: buildMobileVotingVotedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-proposal-default',
    description: 'Mobile coinholder voting proposal with no selected choice',
    builder: buildMobileVotingProposalDefaultUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-ineligible-modal',
    description: 'Mobile voting eligibility dialog matching Figma 8048:71300',
    builder: buildMobileVotingIneligibleModalUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-eligible',
    description:
        'Mobile eligible voting detail with round timing and voting power',
    builder: buildMobileVotingEligibleUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-privacy-trim',
    description: 'Mobile voting detail with the excluded voting power notice',
    builder: buildMobileVotingPrivacyTrimUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-eligibility-error',
    description: 'Mobile voting detail with an eligibility lookup error',
    builder: buildMobileVotingEligibilityErrorUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-ineligible',
    description: 'Mobile ineligible voting detail matching Figma 8048:35024',
    builder: buildMobileVotingIneligibleUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-proposal-selected',
    description: 'Mobile coinholder voting proposal with a selected choice',
    builder: buildMobileVotingProposalSelectedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-results-full',
    description:
        'Mobile voting results with round summary and full option states',
    builder: buildMobileVotingResultsFullUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-results-winner',
    description: 'Mobile voting results with the selected winning option',
    builder: buildMobileVotingResultsWinnerUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-results',
    description: 'Mobile coinholder voting proposal result card',
    builder: buildMobileVotingResultsUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-submission-delegating',
    description: 'Mobile voting submission with delegation at 25 percent',
    builder: buildMobileVotingSubmissionDelegatingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-submission-casting',
    description: 'Mobile voting submission while casting votes',
    builder: buildMobileVotingSubmissionCastingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-submission-casting-compact',
    description: 'Compact mobile voting submission while casting votes',
    builder: buildMobileVotingSubmissionCastingCompactUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-submission-finalizing',
    description: 'Mobile voting submission while finalizing',
    builder: buildMobileVotingSubmissionFinalizingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-submitted',
    description: 'Mobile completed voting submission',
    builder: buildMobileVotingSubmittedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-keystone-request',
    description: 'Mobile voting Keystone request QR step',
    builder: buildMobileVotingKeystoneRequestUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-voting-keystone-scanner',
    description: 'Mobile voting Keystone signed-result scanner step',
    builder: buildMobileVotingKeystoneScannerUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-activity-default',
    description: 'Mobile Activity screen with deterministic transactions',
    builder: buildMobileActivityDefaultUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-importing',
    description: 'Mobile home while the initial wallet import is syncing',
    builder: buildMobileHomeImportingResponsiveUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-no-balance',
    description: 'Mobile home with no balance or activity',
    builder: buildMobileHomeNoBalanceUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-ironwood-migration-required',
    description:
        'Mobile home balance card in Ironwood migration-required state',
    builder: buildMobileHomeIronwoodMigrationRequiredUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-ironwood-migration-in-progress',
    description: 'Mobile home while an Ironwood migration is running',
    builder: buildMobileHomeIronwoodMigrationInProgressUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-ironwood-announcement',
    description: 'Mobile Ironwood migration announcement sheet',
    builder: buildMobileHomeIronwoodAnnouncementUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-announcement-modal',
    description: 'Ironwood migration announcement modal',
    builder: buildIronwoodMigrationAnnouncementModalUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-privacy-lock',
    description: 'Desktop virtual unlock shown during Ironwood migration',
    builder: buildIronwoodMigrationPrivacyLockUseCase,
  ),
  FigmaCompareScenario(
    id: 'desktop-home-ironwood-migration-required',
    description:
        'Desktop home balance card in Ironwood migration-required state',
    builder: buildDesktopHomeIronwoodMigrationRequiredUseCase,
  ),
  FigmaCompareScenario(
    id: 'desktop-home-ironwood-migration-in-progress',
    description:
        'Desktop home showing spendable Ironwood balance during migration',
    builder: buildDesktopHomeIronwoodMigrationInProgressUseCase,
  ),
  FigmaCompareScenario(
    id: 'desktop-home-sidebar-compact-balances',
    description: 'Desktop home sidebar with compact K balance labels',
    builder: buildDesktopHomeSidebarCompactBalancesUseCase,
  ),
  FigmaCompareScenario(
    id: 'desktop-home-sidebar-sync-network-error',
    description: 'Desktop home sidebar with a network sync failure',
    builder: buildDesktopHomeSidebarSyncNetworkErrorUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-intro',
    description: 'Ironwood migration intro screen',
    builder: buildIronwoodMigrationIntroUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-how-it-works',
    description: 'Ironwood migration explanation screen',
    builder: buildIronwoodMigrationHowItWorksUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-what-to-expect',
    description: 'Ironwood migration expectations screen',
    builder: buildIronwoodMigrationWhatToExpectUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-options',
    description: 'Ironwood migration option selection screen',
    builder: buildIronwoodMigrationOptionsUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-private-review',
    description: 'Ironwood private migration review screen',
    builder: buildIronwoodMigrationPrivateReviewUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-immediate-review',
    description: 'Ironwood immediate migration review screen',
    builder: buildIronwoodMigrationImmediateReviewUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-immediate-keystone-request',
    description: 'Immediate migration Keystone request modal',
    builder: buildIronwoodMigrationImmediateKeystoneRequestUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-immediate-keystone-scanner',
    description: 'Immediate migration Keystone signature scanner',
    builder: buildIronwoodMigrationImmediateKeystoneScannerUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-private-keystone-request',
    description: 'Private migration Keystone request QR',
    builder: buildIronwoodMigrationPrivateKeystoneRequestUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-analyzing',
    description: 'Ironwood migration balance analysis loader',
    builder: buildIronwoodMigrationAnalyzingUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-shuffle-review',
    description: 'Ironwood private migration shuffled review screen',
    builder: buildIronwoodMigrationShuffleReviewUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-private-status-waiting',
    description: 'Ironwood private migration waiting status screen',
    builder: buildIronwoodMigrationPrivateStatusWaitingUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-private-status-migrating',
    description: 'Ironwood private migration transfer status screen',
    builder: buildIronwoodMigrationPrivateStatusMigratingUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-private-status-needs-input',
    description: 'Ironwood Keystone migration status requiring a signature',
    builder: buildIronwoodMigrationPrivateStatusNeedsInputUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-post-prepare-waiting',
    description: 'Ironwood migration waiting for the next signing window',
    builder: buildIronwoodMigrationPostPrepareWaitingUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-post-prepare-signing',
    description: 'Ironwood Keystone migration batch ready to sign',
    builder: buildIronwoodMigrationPostPrepareSigningUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-post-prepare-progressed',
    description: 'Ironwood migration after the first batch is available',
    builder: buildIronwoodMigrationPostPrepareProgressedUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-post-prepare-active',
    description: 'Ironwood migration with a later batch in progress',
    builder: buildIronwoodMigrationPostPrepareActiveUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-schedule',
    description: 'Ironwood migration schedule',
    builder: buildIronwoodMigrationScheduleUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-preparation-schedule',
    description: 'Ironwood migration preparation schedule',
    builder: buildIronwoodMigrationPreparationScheduleUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-manage-schedule',
    description: 'Ironwood migration schedule management choices',
    builder: buildIronwoodMigrationManageScheduleUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-immediate-confirmation',
    description: 'Ironwood immediate migration final confirmation',
    builder: buildIronwoodMigrationImmediateConfirmationUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-stop-confirmation',
    description: 'Ironwood migration cancellation final confirmation',
    builder: buildIronwoodMigrationStopConfirmationUseCase,
  ),
  FigmaCompareScenario(
    id: 'ironwood-migration-complete',
    description: 'Ironwood migration completion',
    builder: buildIronwoodMigrationCompleteUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-intro',
    description: 'Mobile About Ironwood migration screen',
    builder: buildMobileIronwoodMigrationIntroUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-how-it-works',
    description: 'Mobile Ironwood migration steps screen',
    builder: buildMobileIronwoodMigrationHowItWorksUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-options',
    description: 'Mobile Ironwood migration type screen',
    builder: buildMobileIronwoodMigrationOptionsUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-android-options',
    description: 'Android Ironwood migration type screen',
    builder: buildMobileIronwoodMigrationAndroidOptionsUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-fast-review',
    description: 'Mobile immediate Ironwood migration review screen',
    builder: buildMobileIronwoodMigrationFastReviewUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-notifications',
    description: 'Mobile private migration notification opt-in screen',
    builder: buildMobileIronwoodMigrationNotificationsPromptUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-notifications-confirmation',
    description: 'Mobile notification opt-out confirmation modal',
    builder: buildMobileIronwoodMigrationNotificationsConfirmationUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-start-loading',
    description: 'Mobile private migration start loading screen',
    builder: buildMobileIronwoodMigrationStartLoadingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-start-keystone-ready',
    description: 'Mobile private migration ready for Keystone signing',
    builder: buildMobileIronwoodMigrationStartKeystoneReadyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-preparation-active',
    description: 'Mobile private migration preparation in progress',
    builder: buildMobileIronwoodMigrationPreparationActiveUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-preparation-paused',
    description: 'Mobile private migration preparation continuation',
    builder: buildMobileIronwoodMigrationPreparationPausedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-preparation-paused-keystone',
    description: 'Mobile Keystone migration preparation continuation',
    builder: buildMobileIronwoodMigrationPreparationPausedKeystoneUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-preparation-syncing',
    description:
        'Mobile foreground sync reconstructed from the preparation surface',
    builder: buildMobileIronwoodMigrationPreparationSyncingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-syncing',
    description: 'Mobile migration foreground sync state',
    builder: buildMobileIronwoodMigrationSyncingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-preparation-complete',
    description: 'Mobile migration preparation complete modal',
    builder: buildMobileIronwoodMigrationPreparationCompleteCaptureUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-waiting-notifications-on',
    description: 'Mobile migration waiting with notifications enabled',
    builder: buildMobileIronwoodMigrationWaitingNotificationsOnUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-waiting-notifications-off',
    description: 'Mobile migration waiting with notifications disabled',
    builder: buildMobileIronwoodMigrationWaitingNotificationsOffUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-needs-input',
    description: 'Mobile migration batch ready for signature',
    builder: buildMobileIronwoodMigrationNeedsInputUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-schedule',
    description: 'Mobile Ironwood migration schedule',
    builder: buildMobileIronwoodMigrationScheduleUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-schedule-pending',
    description:
        'Mobile Ironwood migration schedule with parts Rust has not assigned '
        'a height to yet',
    builder: buildMobileIronwoodMigrationSchedulePendingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-preparation-schedule',
    description: 'Mobile Ironwood preparation transaction schedule',
    builder: buildMobileIronwoodMigrationPreparationScheduleUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-keystone-sign-all',
    description: 'Mobile Keystone migration signing all child transactions',
    builder: buildMobileIronwoodMigrationKeystoneSignAllUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-broadcasting',
    description: 'Mobile migration batch broadcasting',
    builder: buildMobileIronwoodMigrationBroadcastingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-complete',
    description: 'Mobile migration completion screen',
    builder: buildMobileIronwoodMigrationCompleteUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-ironwood-migration-attention',
    description: 'Mobile home migration signature attention card',
    builder: buildMobileIronwoodMigrationHomeAttentionUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-ironwood-migration-attention-modal',
    description: 'Mobile home migration signature attention modal',
    builder: buildMobileIronwoodMigrationHomeAttentionModalUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-keystone-scan-help',
    description: 'Mobile Keystone QR scan help modal',
    builder: buildMobileIronwoodMigrationKeystoneHelpUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-keystone-loading',
    description: 'Mobile Ironwood Keystone request loading screen',
    builder: buildMobileIronwoodMigrationKeystoneLoadingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-keystone-ready',
    description: 'Mobile Ironwood Keystone request QR screen',
    builder: buildMobileIronwoodMigrationKeystoneReadyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-keystone-scanner',
    description: 'Mobile Ironwood Keystone signature scanner screen',
    builder: buildMobileIronwoodMigrationKeystoneScannerUseCase,
    desktop: false,
    mobile: true,
  ),
];

FigmaCompareScenario? findFigmaCompareScenario(String id) {
  for (final scenario in figmaCompareScenarios) {
    if (scenario.id == id) return scenario;
  }
  return null;
}
