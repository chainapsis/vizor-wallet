// ignore_for_file: depend_on_referenced_packages
// Figma comparison tooling is dev-only and may reuse Widgetbook fixtures.

import 'package:flutter/widgets.dart';

import '../widgetbook/activity_use_cases.dart';
import '../widgetbook/home_use_cases.dart';
import '../widgetbook/mobile_pay_use_cases.dart';
import '../widgetbook/pay_use_cases.dart';
import '../widgetbook/payment_link_mobile_use_cases.dart';
import '../widgetbook/payment_link_use_cases.dart';
import '../widgetbook/payment_request_use_cases.dart';
import '../widgetbook/receive_use_cases.dart';
import '../widgetbook/request_amount_use_cases.dart';
import '../widgetbook/carousel_use_cases.dart';
import '../widgetbook/screen_use_cases.dart';
import '../widgetbook/send_review_status_use_cases.dart';
import '../widgetbook/swap_use_cases.dart';
import '../widgetbook/voting_use_cases.dart';
import 'zip321_prefill_use_cases.dart';

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
    id: 'activity-gift-cards',
    description: 'Desktop Activity with Gift Card creation and redemption',
    builder: buildActivityPageUseCase,
  ),
  FigmaCompareScenario(
    id: 'activity-gift-card-created-detail',
    description: 'Desktop created Gift Card activity detail',
    builder: buildCreatedGiftCardActivityDetailUseCase,
  ),
  FigmaCompareScenario(
    id: 'activity-gift-card-redeemed-detail',
    description: 'Desktop redeemed Gift Card activity detail',
    builder: buildRedeemedGiftCardActivityDetailUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-empty',
    description: 'Desktop Gift Cards empty state',
    builder: buildPaymentLinkEmptyUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-help',
    description: 'Desktop Gift Cards help modal',
    builder: buildPaymentLinkHelpUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-empty',
    description: 'Desktop Gift Card amount step without an amount',
    builder: buildPaymentLinkCreateEmptyUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-focused',
    description: 'Desktop Gift Card amount step with focused input',
    builder: buildPaymentLinkCreateFocusedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-amount',
    description: 'Desktop Gift Card amount step with ZEC value',
    builder: buildPaymentLinkCreateAmountUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-amount-editor',
    description: 'Desktop Gift Card focused amount editor with ZEC value',
    builder: buildPaymentLinkInteractiveFocusedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-insufficient',
    description: 'Desktop Gift Card amount step with insufficient balance',
    builder: buildPaymentLinkCreateInsufficientUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-syncing',
    description: 'Desktop Gift Card amount step waiting for wallet sync',
    builder: buildPaymentLinkCreateSyncingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-fiat-loading',
    description: 'Desktop Gift Card amount step while fiat price loads',
    builder: buildPaymentLinkCreateFiatLoadingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-create-fiat',
    description: 'Desktop Gift Card amount step with fiat value',
    builder: buildPaymentLinkCreateFiatUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-message-empty',
    description: 'Desktop Gift Card empty optional-message step',
    builder: buildPaymentLinkMessageEmptyUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-message-filled',
    description: 'Desktop Gift Card filled optional-message step',
    builder: buildPaymentLinkMessageFilledUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-message-editing',
    description: 'Desktop Gift Card focused empty message editor',
    builder: buildPaymentLinkMessageEditingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-message-too-large',
    description: 'Desktop Gift Card message exceeding its UTF-8 byte limit',
    builder: buildPaymentLinkMessageTooLargeUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-review',
    description: 'Desktop Gift Card review fixture',
    builder: buildPaymentLinkReviewUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-review-message',
    description: 'Desktop Gift Card review with its message revealed',
    builder: buildPaymentLinkReviewMessageUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-ready-waiting',
    description: 'Desktop Gift Card waiting for confirmations',
    builder: buildPaymentLinkReadyWaitingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-ready',
    description: 'Desktop Gift Card ready state',
    builder: buildPaymentLinkReadyUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-motion-handoff',
    description: 'Desktop Gift Card motion handoff playground',
    builder: buildPaymentLinkMotionHandoffUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-cards-list',
    description: 'Desktop created Gift Cards list fixture',
    builder: buildPaymentLinkCardsListUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-share-qr',
    description: 'Desktop selected-artwork Gift Card QR export',
    builder: buildPaymentLinkShareQrUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-redeem-paste',
    description: 'Desktop Gift Card redeem paste state',
    builder: buildPaymentLinkRedeemPasteUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-redeem-long-sync-warning',
    description: 'Desktop Gift Card long-sync warning',
    builder: buildPaymentLinkRedeemLongSyncWarningUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-redeem-loading',
    description: 'Desktop Gift Card redeem loading state',
    builder: buildPaymentLinkRedeemLoadingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-redeem-invalid',
    description: 'Desktop Gift Card redeem invalid-link state',
    builder: buildPaymentLinkRedeemInvalidUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-redeem-unavailable',
    description: 'Desktop Gift Card redeem no-balance state',
    builder: buildPaymentLinkRedeemUnavailableUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-received-waiting',
    description: 'Desktop received Gift Card waiting for confirmations',
    builder: buildPaymentLinkReceivedWaitingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-received',
    description: 'Desktop received Gift Card preview',
    builder: buildPaymentLinkReceivedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-link-received-message',
    description: 'Desktop received Gift Card message preview',
    builder: buildPaymentLinkReceivedMessageUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-home-empty',
    description: 'Mobile Gift Cards empty state',
    builder: buildMobilePaymentLinkHomeEmptyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-links-home-cards',
    description: 'Mobile Gift Card list with created and received cards',
    builder: buildMobilePaymentLinkHomeCardsUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-amount-empty',
    description: 'Mobile Gift Card amount step without an amount',
    builder: buildMobilePaymentLinkAmountEmptyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-amount-filled',
    description: 'Mobile Gift Card amount step with a ZEC value',
    builder: buildMobilePaymentLinkAmountFilledUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-amount-focused',
    description: 'Mobile Gift Card focused amount editor without OS keyboard',
    builder: buildMobilePaymentLinkAmountFocusedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-message-empty',
    description: 'Mobile Gift Card optional-message step without a message',
    builder: buildMobilePaymentLinkMessageEmptyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-message-filled',
    description: 'Mobile Gift Card optional-message step with a message',
    builder: buildMobilePaymentLinkMessageFilledUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-message-focused',
    description: 'Mobile Gift Card focused empty message editor',
    builder: buildMobilePaymentLinkMessageFocusedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-review',
    description: 'Mobile Gift Card fee review fixture',
    builder: buildMobilePaymentLinkReviewUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-ready-celebrating',
    description: 'Mobile Gift Card deposited celebration state',
    builder: buildMobilePaymentLinkReadyCelebratingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-ready-shareable',
    description: 'Mobile Gift Card shareable state',
    builder: buildMobilePaymentLinkReadyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-redeem-paste',
    description: 'Mobile Gift Card redeem paste state',
    builder: buildMobilePaymentLinkRedeemPasteUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-redeem-long-sync-warning',
    description: 'Mobile Gift Card long-sync warning',
    builder: buildMobilePaymentLinkRedeemLongSyncWarningUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-redeem-loading',
    description: 'Mobile Gift Card redeem checking state',
    builder: buildMobilePaymentLinkRedeemLoadingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-redeem-invalid',
    description: 'Mobile Gift Card invalid-link state',
    builder: buildMobilePaymentLinkRedeemInvalidUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-received-waiting',
    description: 'Mobile received Gift Card waiting for confirmations',
    builder: buildMobilePaymentLinkReceivedWaitingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-link-received',
    description: 'Mobile received Gift Card claim state',
    builder: buildMobilePaymentLinkReceivedUseCase,
    desktop: false,
    mobile: true,
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
    id: 'mobile-settings-main',
    description: 'Mobile settings at the Account group',
    builder: buildMobileSettingsMainUseCase,
    desktop: false,
    mobile: true,
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
    id: 'mobile-home-tor-connecting',
    description: 'Mobile home while the Tor route is still connecting',
    builder: buildMobileHomeTorConnectingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-home-tor-failed',
    description: 'Mobile home after the Tor bootstrap failed',
    builder: buildMobileHomeTorFailedUseCase,
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
    id: 'desktop-home-tor-connecting',
    description: 'Desktop home while the Tor route is still connecting',
    builder: buildDesktopHomeTorConnectingUseCase,
  ),
  FigmaCompareScenario(
    id: 'desktop-home-tor-failed',
    description: 'Desktop home after the Tor bootstrap failed',
    builder: buildDesktopHomeTorFailedUseCase,
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
  FigmaCompareScenario(
    id: 'zip321-desktop-send-prefill',
    description: 'Desktop /send opened from a ZIP-321 payment link',
    builder: buildZip321DesktopSendPrefillUseCase,
  ),
  FigmaCompareScenario(
    id: 'zip321-desktop-send-prefill-no-memo',
    description: 'Desktop /send from a ZIP-321 link without a memo',
    builder: buildZip321DesktopSendPrefillNoMemoUseCase,
  ),
  FigmaCompareScenario(
    id: 'zip321-mobile-send-amount-step',
    description: 'Mobile /send jumped to the amount step from a payment link',
    builder: buildZip321MobileSendAmountStepUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'zip321-mobile-send-recipient-fallback',
    description: 'Mobile /send bounced back to the recipient step',
    builder: buildZip321MobileSendRecipientFallbackUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'send-review-payment-request-contact',
    description:
        'Desktop review of a payment request paying a saved contact, with '
        'the link label on its own row',
    builder: buildSendReviewPaymentRequestContactUseCase,
  ),
  FigmaCompareScenario(
    id: 'send-review-payment-request-address',
    description:
        'Desktop review of a payment request paying a raw address, with the '
        'link label on its own row',
    builder: buildSendReviewPaymentRequestAddressUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-send-review-payment-request',
    description: 'Mobile review of a payment request with the link label row',
    builder: buildZip321MobileSendReviewRequestUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'payment-request-full',
    description: 'Desktop payment request card with label, message and note',
    builder: buildPaymentRequestFullUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-minimal',
    description: 'Desktop payment request card with amount and address only',
    builder: buildPaymentRequestMinimalUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-long-values',
    description:
        'Desktop payment request card with 80-char label and 512-byte message',
    builder: buildPaymentRequestLongValuesUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-long-values-expanded',
    description: 'Desktop payment request card with the long message expanded',
    builder: buildPaymentRequestLongValuesExpandedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-address-expanded',
    description: 'Desktop payment request card with the full address open',
    builder: buildPaymentRequestAddressExpandedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-checking',
    description: 'Desktop payment request card while checks are running',
    builder: buildPaymentRequestCheckingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-error',
    description: 'Desktop payment request card with an invalid address',
    builder: buildPaymentRequestInvalidAddressUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-insufficient',
    description: 'Desktop payment request card with not enough ZEC',
    builder: buildPaymentRequestInsufficientUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-syncing',
    description: 'Desktop payment request card while the wallet is syncing',
    builder: buildPaymentRequestSyncingUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-replaced',
    description: 'Desktop payment request card with the replaced-link notice',
    builder: buildPaymentRequestReplacedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-transparent',
    description: 'Desktop payment request card paying a transparent address',
    builder: buildPaymentRequestTransparentUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-contact',
    description: 'Desktop payment request card paying a saved contact',
    builder: buildPaymentRequestContactUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-own-account',
    description: "Desktop payment request card paying the user's own account",
    builder: buildPaymentRequestOwnAccountUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-own-account-expanded',
    description: 'Desktop payment request card, own account, address open',
    builder: buildPaymentRequestOwnAccountExpandedUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-note-only',
    description: 'Desktop payment request card with a note and no message',
    builder: buildPaymentRequestNoteOnlyUseCase,
  ),
  FigmaCompareScenario(
    id: 'payment-request-no-amount',
    description: 'Desktop payment request card for a link with no amount',
    builder: buildPaymentRequestNoAmountUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-full',
    description: 'Mobile payment request sheet with label, message and note',
    builder: buildMobilePaymentRequestFullUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-minimal',
    description: 'Mobile payment request sheet with amount and address only',
    builder: buildMobilePaymentRequestMinimalUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-long-values',
    description:
        'Mobile payment request sheet with 80-char label and 512-byte message',
    builder: buildMobilePaymentRequestLongValuesUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-long-values-expanded',
    description: 'Mobile payment request sheet with the long message expanded',
    builder: buildMobilePaymentRequestLongValuesExpandedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-address-expanded',
    description: 'Mobile payment request sheet with the full address open',
    builder: buildMobilePaymentRequestAddressExpandedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-checking',
    description: 'Mobile payment request sheet while checks are running',
    builder: buildMobilePaymentRequestCheckingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-error',
    description: 'Mobile payment request sheet with an invalid address',
    builder: buildMobilePaymentRequestInvalidAddressUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-insufficient',
    description: 'Mobile payment request sheet with not enough ZEC',
    builder: buildMobilePaymentRequestInsufficientUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-syncing',
    description: 'Mobile payment request sheet while the wallet is syncing',
    builder: buildMobilePaymentRequestSyncingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-replaced',
    description: 'Mobile payment request sheet with the replaced-link notice',
    builder: buildMobilePaymentRequestReplacedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-transparent',
    description: 'Mobile payment request sheet paying a transparent address',
    builder: buildMobilePaymentRequestTransparentUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-contact',
    description: 'Mobile payment request sheet paying a saved contact',
    builder: buildMobilePaymentRequestContactUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-own-account',
    description: "Mobile payment request sheet paying the user's own account",
    builder: buildMobilePaymentRequestOwnAccountUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-own-account-expanded',
    description: 'Mobile payment request sheet, own account, address open',
    builder: buildMobilePaymentRequestOwnAccountExpandedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-no-amount',
    description: 'Mobile payment request sheet for a link with no amount',
    builder: buildMobilePaymentRequestNoAmountUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-payment-request-note-only',
    description: 'Mobile payment request sheet with a note and no message',
    builder: buildMobilePaymentRequestNoteOnlyUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'receive-request-modal-step-1',
    description: 'Desktop request modal step one with an open message',
    builder: buildRequestModalStepOneMessageUseCase,
  ),
  FigmaCompareScenario(
    id: 'receive-request-modal-step-2',
    description: 'Desktop request modal step two with the request QR',
    builder: buildRequestModalStepTwoShieldedUseCase,
  ),
  FigmaCompareScenario(
    id: 'receive-request-modal-step-2-dense',
    description: 'Desktop request modal step two with a 512-byte message',
    builder: buildRequestModalStepTwoDenseUseCase,
  ),
  FigmaCompareScenario(
    id: 'mobile-receive-shielded',
    description: 'Mobile receive screen with the request entry beside share',
    builder: buildReceiveMobileShieldedUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'receive-request-compose-no-price',
    description: 'Desktop request modal step one with no live price',
    builder: buildRequestModalStepOnePriceUnavailableUseCase,
    desktop: true,
    mobile: false,
  ),
  FigmaCompareScenario(
    id: 'mobile-receive-request-compose-no-price',
    description: 'Mobile request sheet step one with no live price',
    builder: buildRequestMobileComposePriceUnavailableUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-receive-request-compose',
    description: 'Mobile request sheet step one with an amount and a message',
    builder: buildRequestMobileComposeMessageUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-receive-request-compose-error',
    description: 'Mobile request sheet step one with an invalid amount',
    builder: buildRequestMobileComposeAmountErrorUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'receive-desktop-shielded',
    description: 'Desktop receive pane with the request entry beside copy',
    builder: buildReceiveDesktopRequestEntryUseCase,
    desktop: true,
    mobile: false,
  ),
  FigmaCompareScenario(
    id: 'receive-request-result',
    description: 'Desktop request modal step two with the shielded request QR',
    builder: buildRequestModalStepTwoShieldedUseCase,
    desktop: true,
    mobile: false,
  ),
  FigmaCompareScenario(
    id: 'mobile-receive-request-result',
    description: 'Mobile request sheet step two with the shielded request QR',
    builder: buildRequestMobileResultShieldedUseCase,
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
