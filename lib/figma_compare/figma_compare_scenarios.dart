// ignore_for_file: depend_on_referenced_packages
// Figma comparison tooling is dev-only and may reuse Widgetbook fixtures.

import 'package:flutter/widgets.dart';

import '../widgetbook/home_use_cases.dart';
import '../widgetbook/pay_use_cases.dart';
import '../widgetbook/screen_use_cases.dart';

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
    id: 'mobile-ironwood-migration-analyzing',
    description: 'Mobile Ironwood balance analysis screen',
    builder: buildMobileIronwoodMigrationAnalyzingUseCase,
    desktop: false,
    mobile: true,
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
    id: 'mobile-home-default',
    description: 'Mobile home with deterministic balance and activity',
    builder: buildMobileHomeDefaultUseCase,
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
    id: 'mobile-ironwood-migration-private-review',
    description: 'Mobile private Ironwood migration review screen',
    builder: buildMobileIronwoodMigrationPrivateReviewUseCase,
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
    id: 'mobile-ironwood-migration-preparing',
    description: 'Mobile Ironwood migration preparing screen',
    builder: buildMobileIronwoodMigrationPreparingUseCase,
    desktop: false,
    mobile: true,
  ),
  FigmaCompareScenario(
    id: 'mobile-ironwood-migration-migrating',
    description: 'Mobile Ironwood migration progress screen',
    builder: buildMobileIronwoodMigrationMigratingUseCase,
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
