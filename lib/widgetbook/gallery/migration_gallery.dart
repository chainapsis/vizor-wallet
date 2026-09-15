// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/features/migration/screens/ironwood_migration_flow_screen.dart';
import '../../src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import '../../src/features/migration/widgets/mobile/mobile_ironwood_keystone_signing_view.dart';
import '../migration_use_cases.dart';
import '../scanner_use_cases.dart' show ScannerMigrationStepCase;
import '../screen_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';
import 'scanner_gallery.dart' show buildScannerMigrationGalleryCase;
import '../support/wb_fake_scanner_platform.dart';

/// The Ironwood migration gallery: one use case per surface, each knob
/// dispatching to the fixtures in `screen_use_cases.dart` so figma_compare and
/// the tests keep every `build*UseCase` they bind to.
///
/// The Desktop and Mobile folders hold the surfaces that exist in one form
/// factor only (desktop has the review screens and the virtual unlock, mobile
/// has notification and preparation panels); the surfaces that exist in both —
/// the migration flow, the two schedules, the Keystone signing screens and the
/// two home surfaces — are a single use case with the `Layout` knob.
final List<WidgetbookNode> migrationGalleryNodes = [
  WidgetbookFolder(
    name: 'Desktop',
    children: [
      WidgetbookComponent(
        name: 'Prepare gate',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationPrepareGateGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Private review',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationPrivateReviewGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Immediate review',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationImmediateReviewGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Private status',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationPrivateStatusGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Virtual unlock',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationVirtualUnlockGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Mobile',
    children: [
      WidgetbookComponent(
        name: 'Notifications',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileNotificationsGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Start',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileStartGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Preparation',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobilePreparationGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Migration progress',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileProgressGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Migration status',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileStatusGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Preparing & migrating',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileLiveStepsGalleryCase,
          ),
        ],
      ),
      // Not folded into the root 'Keystone signing' screens: this is the view
      // all four of them mount, on placeholder QR and camera, so its scanner
      // and scan-help states are ones their preview harness cannot reach.
      WidgetbookComponent(
        name: 'Keystone signing',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileKeystoneGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Home attention',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationMobileHomeAttentionGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Keystone signing',
    children: [
      WidgetbookComponent(
        name: 'Combined sign',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationKeystoneCombinedSignGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Immediate sign',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationKeystoneImmediateSignGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Denomination split',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationKeystoneDenominationSignGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Migration batch',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildMigrationKeystoneBatchSignGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Migration flow',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildMigrationFlowGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Migration schedule',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildMigrationScheduleGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Preparation schedule',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildMigrationPreparationScheduleGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Home migration banner',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildMigrationHomeBannerGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Home announcement',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildMigrationHomeAnnouncementGalleryCase,
      ),
    ],
  ),
];

/// The desktop migration screens are desktop-lane only: they reach
/// `AppCarousel`, which asserts `kAppFormFactor == AppFormFactor.desktop`, so
/// the mobile binary cannot render them at all. The mobile screens below carry
/// no such assertion and stay browsable from either lane.
Widget _migrationDesktopOnly(Widget child) =>
    WbLaneOnly(layout: WbLayout.desktop, child: child);

// --- Migration flow --------------------------------------------------------

/// Informational steps of the desktop flow, before a migration type is picked,
/// plus the prepare step the gate route parks on.
enum MigrationFlowStepCase {
  intro,
  howItWorks,
  whatToExpect,
  options,
  preparing,
}

/// Where the shell's account figures come from; the fallback is what renders
/// when no account is selected yet.
enum MigrationFlowDataCase { account, fallback }

enum MigrationMobileStepCase { intro, howItWorks, migrationType, fastReview }

/// Whether the private option is offered; only Android hides it, and only the
/// migration-type step renders the difference.
enum MigrationPrivateOptionCase { available, unavailable }

/// Both flow screens under one `Layout` knob. The step sets do not line up —
/// desktop has 'What to expect' and the prepare step, mobile has the fast
/// review — so each layout registers its own step axis instead of sharing one.
Widget buildMigrationFlowGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return layout == WbLayout.mobile
      ? _migrationMobileFlowCase(context)
      : _migrationDesktopFlowCase(context);
}

Widget _migrationDesktopFlowCase(BuildContext context) {
  final step = wbStateKnob<MigrationFlowStepCase>(
    context,
    label: 'Step',
    options: MigrationFlowStepCase.values,
    labelBuilder: migrationFlowStepCaseLabel,
  );
  final flowData = wbStateKnob<MigrationFlowDataCase>(
    context,
    label: 'Flow data',
    options: MigrationFlowDataCase.values,
    labelBuilder: migrationFlowDataCaseLabel,
  );
  // Only the options step has a selection; the card's own tap is the only
  // thing that moves it, so it needs the driven fixture.
  final selection = wbStateKnob<MigrationOptionSelectionCase>(
    context,
    label: 'Selection',
    options: MigrationOptionSelectionCase.values,
    labelBuilder: migrationOptionSelectionCaseLabel,
  );
  if (step == MigrationFlowStepCase.options &&
      flowData == MigrationFlowDataCase.account &&
      selection == MigrationOptionSelectionCase.immediate) {
    return _migrationDesktopOnly(
      migrationOptionsSelectionFixture(selection: selection),
    );
  }
  // The four informational steps keep their own fixtures; the prepare step and
  // the fallback data have none, so those route through the parameterized one.
  if (step == MigrationFlowStepCase.preparing ||
      flowData == MigrationFlowDataCase.fallback) {
    return _migrationDesktopOnly(
      migrationFlowStepFixture(
        step: _migrationFlowStep(step),
        fallbackData: flowData == MigrationFlowDataCase.fallback,
      ),
    );
  }
  return _migrationDesktopOnly(switch (step) {
    MigrationFlowStepCase.intro => buildIronwoodMigrationIntroUseCase(context),
    MigrationFlowStepCase.howItWorks => buildIronwoodMigrationHowItWorksUseCase(
      context,
    ),
    MigrationFlowStepCase.whatToExpect =>
      buildIronwoodMigrationWhatToExpectUseCase(context),
    MigrationFlowStepCase.options => buildIronwoodMigrationOptionsUseCase(
      context,
    ),
    MigrationFlowStepCase.preparing => const SizedBox.shrink(),
  });
}

IronwoodMigrationFlowStep _migrationFlowStep(MigrationFlowStepCase step) {
  return switch (step) {
    MigrationFlowStepCase.intro => IronwoodMigrationFlowStep.intro,
    MigrationFlowStepCase.howItWorks => IronwoodMigrationFlowStep.howItWorks,
    MigrationFlowStepCase.whatToExpect =>
      IronwoodMigrationFlowStep.whatToExpect,
    MigrationFlowStepCase.options => IronwoodMigrationFlowStep.options,
    MigrationFlowStepCase.preparing => IronwoodMigrationFlowStep.prepare,
  };
}

String migrationFlowStepCaseLabel(MigrationFlowStepCase step) {
  return switch (step) {
    MigrationFlowStepCase.intro => 'About Ironwood',
    MigrationFlowStepCase.howItWorks => 'How it works',
    MigrationFlowStepCase.whatToExpect => 'What to expect',
    MigrationFlowStepCase.options => 'Migration options',
    MigrationFlowStepCase.preparing => 'Preparing',
  };
}

String migrationOptionSelectionCaseLabel(MigrationOptionSelectionCase mode) {
  return switch (mode) {
    MigrationOptionSelectionCase.private => 'Private',
    MigrationOptionSelectionCase.immediate => 'Immediate',
  };
}

String migrationFlowDataCaseLabel(MigrationFlowDataCase flowData) {
  return switch (flowData) {
    MigrationFlowDataCase.account => 'Account',
    MigrationFlowDataCase.fallback => 'No account yet',
  };
}

Widget _migrationMobileFlowCase(BuildContext context) {
  final step = wbStateKnob<MigrationMobileStepCase>(
    context,
    label: 'Step',
    options: MigrationMobileStepCase.values,
    labelBuilder: migrationMobileStepCaseLabel,
  );
  final privateOption = wbStateKnob<MigrationPrivateOptionCase>(
    context,
    label: 'Private option',
    options: MigrationPrivateOptionCase.values,
    labelBuilder: migrationPrivateOptionCaseLabel,
  );
  return Builder(
    builder: (BuildContext context) {
      if (step == MigrationMobileStepCase.migrationType &&
          privateOption == MigrationPrivateOptionCase.unavailable) {
        return buildMobileIronwoodMigrationAndroidOptionsUseCase(context);
      }
      return switch (step) {
        MigrationMobileStepCase.intro =>
          buildMobileIronwoodMigrationIntroUseCase(context),
        MigrationMobileStepCase.howItWorks =>
          buildMobileIronwoodMigrationHowItWorksUseCase(context),
        MigrationMobileStepCase.migrationType =>
          buildMobileIronwoodMigrationOptionsUseCase(context),
        MigrationMobileStepCase.fastReview =>
          buildMobileIronwoodMigrationFastReviewUseCase(context),
      };
    },
  );
}

String migrationMobileStepCaseLabel(MigrationMobileStepCase step) {
  return switch (step) {
    MigrationMobileStepCase.intro => 'About Ironwood',
    MigrationMobileStepCase.howItWorks => 'Ironwood steps',
    MigrationMobileStepCase.migrationType => 'Migration type',
    MigrationMobileStepCase.fastReview => 'Fast review',
  };
}

String migrationPrivateOptionCaseLabel(MigrationPrivateOptionCase option) {
  return switch (option) {
    MigrationPrivateOptionCase.available => 'Available',
    MigrationPrivateOptionCase.unavailable => 'Unavailable',
  };
}

// --- Desktop > Prepare gate ------------------------------------------------

Widget buildMigrationPrepareGateGalleryCase(BuildContext context) {
  final gate = wbStateKnob<MigrationPrepareGateCase>(
    context,
    label: 'Gate',
    options: MigrationPrepareGateCase.values,
    labelBuilder: migrationPrepareGateCaseLabel,
  );
  return _migrationDesktopOnly(migrationPrepareGateFixture(gate: gate));
}

String migrationPrepareGateCaseLabel(MigrationPrepareGateCase gate) {
  return switch (gate) {
    MigrationPrepareGateCase.syncing => 'Still syncing',
    MigrationPrepareGateCase.notAvailable => 'Not available',
    MigrationPrepareGateCase.syncFailed => 'Sync failed',
    MigrationPrepareGateCase.statusError => "Couldn't verify status",
    MigrationPrepareGateCase.notNeeded => 'Not needed',
    MigrationPrepareGateCase.resume => 'Resume migration',
    MigrationPrepareGateCase.start => 'Start migration',
  };
}

// --- Desktop > Private review ----------------------------------------------

/// Stages of the private review step; `keystoneRequest` is the hardware branch
/// the Start button routes to.
///
/// `buildIronwoodMigrationShuffleReviewUseCase` passes the default preview
/// stage, so it renders the same screen as 'Review' and earns no option.
enum MigrationPrivateReviewCase {
  review,
  findingBatches,
  keystoneRequest,
  planUnavailable,
  startError,
}

Widget buildMigrationPrivateReviewGalleryCase(BuildContext context) {
  final stage = wbStateKnob<MigrationPrivateReviewCase>(
    context,
    label: 'Stage',
    options: MigrationPrivateReviewCase.values,
    labelBuilder: migrationPrivateReviewCaseLabel,
  );
  // Only the analyzing stage animates, so the motion axis reads as a
  // no-op anywhere else.
  final motion = wbStateKnob<MigrationMotionCase>(
    context,
    label: 'Motion',
    options: MigrationMotionCase.values,
    labelBuilder: migrationMotionCaseLabel,
  );
  final screen = switch (stage) {
    MigrationPrivateReviewCase.review =>
      buildIronwoodMigrationPrivateReviewUseCase(context),
    MigrationPrivateReviewCase.findingBatches =>
      buildIronwoodMigrationAnalyzingUseCase(context),
    MigrationPrivateReviewCase.keystoneRequest =>
      buildIronwoodMigrationPrivateKeystoneRequestUseCase(context),
    MigrationPrivateReviewCase.planUnavailable =>
      migrationPrivateReviewDataFixture(
        data: MigrationPrivateReviewDataCase.unavailable,
      ),
    MigrationPrivateReviewCase.startError => migrationPrivateReviewDataFixture(
      data: MigrationPrivateReviewDataCase.startFailure,
    ),
  };
  return _migrationDesktopOnly(
    motion == MigrationMotionCase.reduced
        ? _migrationReducedMotion(screen)
        : screen,
  );
}

/// Freezes the analyzing donut and shimmer the way the OS setting does.
Widget _migrationReducedMotion(Widget child) {
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child,
    ),
  );
}

String migrationPrivateReviewCaseLabel(MigrationPrivateReviewCase stage) {
  return switch (stage) {
    MigrationPrivateReviewCase.review => 'Review',
    MigrationPrivateReviewCase.findingBatches => 'Finding batches',
    MigrationPrivateReviewCase.keystoneRequest => 'Keystone request',
    MigrationPrivateReviewCase.planUnavailable => "Couldn't analyze",
    MigrationPrivateReviewCase.startError => "Couldn't start",
  };
}

// --- Desktop > Immediate review --------------------------------------------

enum MigrationImmediateReviewCase { review, keystoneRequest, keystoneScanner }

Widget buildMigrationImmediateReviewGalleryCase(BuildContext context) {
  final stage = wbStateKnob<MigrationImmediateReviewCase>(
    context,
    label: 'Stage',
    options: MigrationImmediateReviewCase.values,
    labelBuilder: migrationImmediateReviewCaseLabel,
  );
  return _migrationDesktopOnly(switch (stage) {
    MigrationImmediateReviewCase.review =>
      buildIronwoodMigrationImmediateReviewUseCase(context),
    MigrationImmediateReviewCase.keystoneRequest =>
      buildIronwoodMigrationImmediateKeystoneRequestUseCase(context),
    MigrationImmediateReviewCase.keystoneScanner =>
      buildIronwoodMigrationImmediateKeystoneScannerUseCase(context),
  });
}

String migrationImmediateReviewCaseLabel(MigrationImmediateReviewCase stage) {
  return switch (stage) {
    MigrationImmediateReviewCase.review => 'Review',
    MigrationImmediateReviewCase.keystoneRequest => 'Keystone request',
    MigrationImmediateReviewCase.keystoneScanner => 'Keystone scanner',
  };
}

// --- Desktop > Private status ----------------------------------------------

/// Phases the private status screen presents, in the order a run walks them.
enum MigrationPrivateStatusCase {
  preparing,
  migrating,
  needsInput,
  readyToMigrate,
  needsSignature,
  broadcastScheduled,
  waitingConfirmations,
  complete,
}

Widget buildMigrationPrivateStatusGalleryCase(BuildContext context) {
  final phase = wbStateKnob<MigrationPrivateStatusCase>(
    context,
    label: 'Phase',
    options: MigrationPrivateStatusCase.values,
    labelBuilder: migrationPrivateStatusCaseLabel,
  );
  final data = wbStateKnob<MigrationStatusDataCase>(
    context,
    label: 'Data',
    options: MigrationStatusDataCase.values,
    labelBuilder: migrationStatusDataCaseLabel,
  );
  // A status the screen never receives outranks the phase: the phase fixtures
  // all hand it a resolved preview status.
  if (data != MigrationStatusDataCase.status) {
    return _migrationDesktopOnly(
      migrationPrivateStatusAsyncFixture(data: data),
    );
  }
  return _migrationDesktopOnly(switch (phase) {
    MigrationPrivateStatusCase.preparing =>
      buildIronwoodMigrationPrivateStatusWaitingUseCase(context),
    MigrationPrivateStatusCase.migrating =>
      buildIronwoodMigrationPrivateStatusMigratingUseCase(context),
    MigrationPrivateStatusCase.needsInput =>
      buildIronwoodMigrationPrivateStatusNeedsInputUseCase(context),
    MigrationPrivateStatusCase.readyToMigrate =>
      buildIronwoodMigrationPostPrepareWaitingUseCase(context),
    MigrationPrivateStatusCase.needsSignature =>
      buildIronwoodMigrationPostPrepareSigningUseCase(context),
    MigrationPrivateStatusCase.broadcastScheduled =>
      buildIronwoodMigrationPostPrepareProgressedUseCase(context),
    MigrationPrivateStatusCase.waitingConfirmations =>
      buildIronwoodMigrationPostPrepareActiveUseCase(context),
    MigrationPrivateStatusCase.complete =>
      buildIronwoodMigrationCompleteUseCase(context),
  });
}

String migrationPrivateStatusCaseLabel(MigrationPrivateStatusCase phase) {
  return switch (phase) {
    MigrationPrivateStatusCase.preparing => 'Preparing',
    MigrationPrivateStatusCase.migrating => 'Migrating',
    MigrationPrivateStatusCase.needsInput => 'Needs input',
    MigrationPrivateStatusCase.readyToMigrate => 'Ready to migrate',
    MigrationPrivateStatusCase.needsSignature => 'Needs signature',
    MigrationPrivateStatusCase.broadcastScheduled => 'Broadcast scheduled',
    MigrationPrivateStatusCase.waitingConfirmations => 'Confirming',
    MigrationPrivateStatusCase.complete => 'Complete',
  };
}

// --- Migration schedule ----------------------------------------------------

enum MigrationScheduleOverlayCase { none, manage, migrateNow, stop }

/// Whether the mobile run's tail already has broadcast heights; the pending
/// run is waiting on confirmations with its last parts still unscheduled.
enum MigrationScheduleAssignmentCase { assigned, pending }

/// Both schedule screens under one `Layout` knob: the data and row axes are
/// shared, the overlays and stop permission are desktop-only, and only the
/// mobile fixtures have the pending-assignment run.
Widget buildMigrationScheduleGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return layout == WbLayout.mobile
      ? _migrationMobileScheduleCase(context)
      : _migrationDesktopScheduleCase(context);
}

Widget _migrationMobileScheduleCase(BuildContext context) {
  final assignment = wbStateKnob<MigrationScheduleAssignmentCase>(
    context,
    label: 'Schedule',
    options: MigrationScheduleAssignmentCase.values,
    labelBuilder: migrationScheduleAssignmentCaseLabel,
  );
  final data = wbStateKnob<MigrationScheduleDataCase>(
    context,
    label: 'Data',
    options: MigrationScheduleDataCase.values,
    labelBuilder: migrationScheduleDataCaseLabel,
  );
  final rowStatus = wbStateKnob<MigrationSchedulePartCase>(
    context,
    label: 'Row status',
    options: MigrationSchedulePartCase.values,
    labelBuilder: migrationSchedulePartCaseLabel,
  );
  final pending = assignment == MigrationScheduleAssignmentCase.pending;
  // The two existing fixtures cover the mixed run; the parameterized one takes
  // over as soon as an async state or a row state moves.
  if (data == MigrationScheduleDataCase.schedule &&
      rowStatus == MigrationSchedulePartCase.mixed) {
    return pending
        ? buildMobileIronwoodMigrationSchedulePendingUseCase(context)
        : buildMobileIronwoodMigrationScheduleUseCase(context);
  }
  return migrationMobileScheduleFixture(
    preparation: false,
    pending: pending,
    data: data,
    rowStatus: rowStatus,
  );
}

String migrationScheduleAssignmentCaseLabel(
  MigrationScheduleAssignmentCase assignment,
) {
  return switch (assignment) {
    MigrationScheduleAssignmentCase.assigned => 'Heights assigned',
    MigrationScheduleAssignmentCase.pending => 'Heights pending',
  };
}

Widget _migrationDesktopScheduleCase(BuildContext context) {
  final overlay = wbStateKnob<MigrationScheduleOverlayCase>(
    context,
    label: 'Overlay',
    options: MigrationScheduleOverlayCase.values,
    labelBuilder: migrationScheduleOverlayCaseLabel,
  );
  final data = wbStateKnob<MigrationScheduleDataCase>(
    context,
    label: 'Data',
    options: MigrationScheduleDataCase.values,
    labelBuilder: migrationScheduleDataCaseLabel,
  );
  final rowStatus = wbStateKnob<MigrationSchedulePartCase>(
    context,
    label: 'Row status',
    options: MigrationSchedulePartCase.values,
    labelBuilder: migrationSchedulePartCaseLabel,
  );
  final canStop = wbBoolKnob(context, label: 'Stop available');

  if (data != MigrationScheduleDataCase.schedule) {
    return _migrationDesktopOnly(migrationScheduleFixture(data: data));
  }
  // The four overlay fixtures already cover the mixed run; the parameterized
  // fixture only takes over once a row state or the stop permission moves.
  if (rowStatus == MigrationSchedulePartCase.mixed && !canStop) {
    return _migrationDesktopOnly(switch (overlay) {
      MigrationScheduleOverlayCase.none =>
        buildIronwoodMigrationScheduleUseCase(context),
      MigrationScheduleOverlayCase.manage =>
        buildIronwoodMigrationManageScheduleUseCase(context),
      MigrationScheduleOverlayCase.migrateNow =>
        buildIronwoodMigrationImmediateConfirmationUseCase(context),
      MigrationScheduleOverlayCase.stop =>
        buildIronwoodMigrationStopConfirmationUseCase(context),
    });
  }
  return _migrationDesktopOnly(
    migrationScheduleFixture(
      data: data,
      rowStatus: rowStatus,
      overlay: _migrationSchedulePreviewOverlay(overlay),
      canStop: canStop,
    ),
  );
}

IronwoodMigrationSchedulePreviewOverlay? _migrationSchedulePreviewOverlay(
  MigrationScheduleOverlayCase overlay,
) {
  return switch (overlay) {
    MigrationScheduleOverlayCase.none => null,
    MigrationScheduleOverlayCase.manage =>
      IronwoodMigrationSchedulePreviewOverlay.manage,
    MigrationScheduleOverlayCase.migrateNow =>
      IronwoodMigrationSchedulePreviewOverlay.immediateConfirmation,
    MigrationScheduleOverlayCase.stop =>
      IronwoodMigrationSchedulePreviewOverlay.stopConfirmation,
  };
}

String migrationScheduleOverlayCaseLabel(MigrationScheduleOverlayCase overlay) {
  return switch (overlay) {
    MigrationScheduleOverlayCase.none => 'None',
    MigrationScheduleOverlayCase.manage => 'Manage',
    MigrationScheduleOverlayCase.migrateNow => 'Migrate now',
    MigrationScheduleOverlayCase.stop => 'Stop',
  };
}

String migrationScheduleDataCaseLabel(MigrationScheduleDataCase data) {
  return switch (data) {
    MigrationScheduleDataCase.schedule => 'Schedule',
    MigrationScheduleDataCase.loading => 'Loading',
    MigrationScheduleDataCase.unavailable => 'Unavailable',
  };
}

String migrationSchedulePartCaseLabel(MigrationSchedulePartCase rowStatus) {
  return switch (rowStatus) {
    MigrationSchedulePartCase.mixed => 'Mixed run',
    MigrationSchedulePartCase.scheduled => 'Scheduled',
    MigrationSchedulePartCase.broadcasting => 'Waiting to be mined',
    MigrationSchedulePartCase.confirming => 'Confirming',
    MigrationSchedulePartCase.completed => 'Completed',
    MigrationSchedulePartCase.needsSignature => 'Ready to sign',
  };
}

String migrationStatusDataCaseLabel(MigrationStatusDataCase data) {
  return switch (data) {
    MigrationStatusDataCase.status => 'Status',
    MigrationStatusDataCase.loading => 'Loading',
    MigrationStatusDataCase.unavailable => 'Unavailable',
  };
}

// --- Preparation schedule --------------------------------------------------

enum MigrationTextSizeCase { standard, large }

/// Data options per layout: the round-less run has no mobile fixture.
List<MigrationPreparationDataCase> migrationPreparationDataOptions(
  WbLayout layout,
) {
  return layout == WbLayout.mobile
      ? const [
          MigrationPreparationDataCase.schedule,
          MigrationPreparationDataCase.loading,
          MigrationPreparationDataCase.unavailable,
        ]
      : MigrationPreparationDataCase.values;
}

/// Both preparation schedule screens under one `Layout` knob; only the desktop
/// screen has a large-text fixture.
Widget buildMigrationPreparationScheduleGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return layout == WbLayout.mobile
      ? _migrationMobilePreparationScheduleCase(context)
      : _migrationDesktopPreparationScheduleCase(context);
}

Widget _migrationMobilePreparationScheduleCase(BuildContext context) {
  final data = wbStateKnob<MigrationPreparationDataCase>(
    context,
    label: 'Data',
    options: migrationPreparationDataOptions(WbLayout.mobile),
    labelBuilder: migrationPreparationDataCaseLabel,
  );
  final txStatus = wbStateKnob<MigrationPreparationTxCase>(
    context,
    label: 'Split status',
    options: MigrationPreparationTxCase.values,
    labelBuilder: migrationPreparationTxCaseLabel,
  );
  final output = wbStateKnob<MigrationPreparationOutputCase>(
    context,
    label: 'Output',
    options: MigrationPreparationOutputCase.values,
    labelBuilder: migrationPreparationOutputCaseLabel,
  );
  if (data == MigrationPreparationDataCase.schedule &&
      txStatus == MigrationPreparationTxCase.mixed &&
      output == MigrationPreparationOutputCase.mixed) {
    return buildMobileIronwoodMigrationPreparationScheduleUseCase(context);
  }
  return migrationMobileScheduleFixture(
    preparation: true,
    data: switch (data) {
      MigrationPreparationDataCase.loading => MigrationScheduleDataCase.loading,
      MigrationPreparationDataCase.unavailable =>
        MigrationScheduleDataCase.unavailable,
      MigrationPreparationDataCase.schedule ||
      MigrationPreparationDataCase.empty => MigrationScheduleDataCase.schedule,
    },
    txStatus: txStatus,
    output: output,
  );
}

Widget _migrationDesktopPreparationScheduleCase(BuildContext context) {
  final textSize = wbStateKnob<MigrationTextSizeCase>(
    context,
    label: 'Text size',
    options: MigrationTextSizeCase.values,
    labelBuilder: migrationTextSizeCaseLabel,
  );
  final data = wbStateKnob<MigrationPreparationDataCase>(
    context,
    label: 'Data',
    options: migrationPreparationDataOptions(WbLayout.desktop),
    labelBuilder: migrationPreparationDataCaseLabel,
  );
  final txStatus = wbStateKnob<MigrationPreparationTxCase>(
    context,
    label: 'Split status',
    options: MigrationPreparationTxCase.values,
    labelBuilder: migrationPreparationTxCaseLabel,
  );
  final output = wbStateKnob<MigrationPreparationOutputCase>(
    context,
    label: 'Output',
    options: MigrationPreparationOutputCase.values,
    labelBuilder: migrationPreparationOutputCaseLabel,
  );

  final usesExistingFixture =
      data == MigrationPreparationDataCase.schedule &&
      txStatus == MigrationPreparationTxCase.mixed &&
      output == MigrationPreparationOutputCase.mixed;
  // Both existing builders stay the caller for the combination they cover; the
  // large-text one is already this screen under the same 1.5x scaler.
  if (usesExistingFixture) {
    return _migrationDesktopOnly(
      textSize == MigrationTextSizeCase.standard
          ? buildIronwoodMigrationPreparationScheduleUseCase(context)
          : buildIronwoodMigrationPreparationScheduleLargeTextUseCase(context),
    );
  }
  final screen = migrationPreparationScheduleFixture(
    data: data,
    txStatus: txStatus,
    output: output,
  );
  return _migrationDesktopOnly(
    textSize == MigrationTextSizeCase.standard
        ? screen
        : MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: screen,
          ),
  );
}

String migrationTextSizeCaseLabel(MigrationTextSizeCase textSize) {
  return switch (textSize) {
    MigrationTextSizeCase.standard => 'Standard',
    MigrationTextSizeCase.large => 'Large (1.5x)',
  };
}

String migrationPreparationDataCaseLabel(MigrationPreparationDataCase data) {
  return switch (data) {
    MigrationPreparationDataCase.schedule => 'Schedule',
    MigrationPreparationDataCase.empty => 'No rounds yet',
    MigrationPreparationDataCase.loading => 'Loading',
    MigrationPreparationDataCase.unavailable => 'Unavailable',
  };
}

String migrationPreparationTxCaseLabel(MigrationPreparationTxCase txStatus) {
  return switch (txStatus) {
    MigrationPreparationTxCase.mixed => 'Mixed run',
    MigrationPreparationTxCase.awaitingInputs => 'Waiting for inputs',
    MigrationPreparationTxCase.scheduled => 'Scheduled',
    MigrationPreparationTxCase.broadcasting => 'Broadcasting',
    MigrationPreparationTxCase.confirming => 'Confirming',
    MigrationPreparationTxCase.completed => 'Completed',
  };
}

String migrationPreparationOutputCaseLabel(
  MigrationPreparationOutputCase output,
) {
  return switch (output) {
    MigrationPreparationOutputCase.mixed => 'Mixed',
    MigrationPreparationOutputCase.migration => 'For migration',
    MigrationPreparationOutputCase.change => 'Stays in Orchard',
    MigrationPreparationOutputCase.continuation => 'Used in next round',
  };
}

// --- Desktop > Virtual unlock ----------------------------------------------

enum MigrationMotionCase { animated, reduced }

Widget buildMigrationVirtualUnlockGalleryCase(BuildContext context) {
  final badge = wbBoolKnob(context, label: 'Migration badge', initial: true);
  final motion = wbStateKnob<MigrationMotionCase>(
    context,
    label: 'Motion',
    options: MigrationMotionCase.values,
    labelBuilder: migrationMotionCaseLabel,
  );
  final submit = wbStateKnob<MigrationVirtualUnlockCase>(
    context,
    label: 'Password',
    options: MigrationVirtualUnlockCase.values,
    labelBuilder: migrationVirtualUnlockCaseLabel,
  );
  // A submit is internal state behind the security provider, so it takes the
  // driven fixture rather than the badge/motion props.
  if (submit != MigrationVirtualUnlockCase.idle) {
    return _migrationDesktopOnly(
      migrationVirtualUnlockSubmitFixture(state: submit),
    );
  }
  if (badge && motion == MigrationMotionCase.animated) {
    return _migrationDesktopOnly(
      buildIronwoodMigrationPrivacyLockUseCase(context),
    );
  }
  return _migrationDesktopOnly(
    migrationVirtualUnlockFixture(
      showMigrationInProgress: badge,
      reducedMotion: motion == MigrationMotionCase.reduced,
    ),
  );
}

String migrationVirtualUnlockCaseLabel(MigrationVirtualUnlockCase state) {
  return switch (state) {
    MigrationVirtualUnlockCase.idle => 'Not entered',
    MigrationVirtualUnlockCase.submitting => 'Submitting',
    MigrationVirtualUnlockCase.wrongPassword => 'Wrong password',
    MigrationVirtualUnlockCase.policyError => 'Unsupported characters',
  };
}

String migrationMotionCaseLabel(MigrationMotionCase motion) {
  return switch (motion) {
    MigrationMotionCase.animated => 'Animated',
    MigrationMotionCase.reduced => 'Reduced',
  };
}

// --- Mobile > Notifications ------------------------------------------------

enum MigrationNotificationsCase { prompt, confirmSkip }

Widget buildMigrationMobileNotificationsGalleryCase(BuildContext context) {
  final screen = wbStateKnob<MigrationNotificationsCase>(
    context,
    label: 'Screen',
    options: MigrationNotificationsCase.values,
    labelBuilder: migrationNotificationsCaseLabel,
  );
  return switch (screen) {
    MigrationNotificationsCase.prompt =>
      buildMobileIronwoodMigrationNotificationsPromptUseCase(context),
    MigrationNotificationsCase.confirmSkip =>
      buildMobileIronwoodMigrationNotificationsConfirmationUseCase(context),
  };
}

String migrationNotificationsCaseLabel(MigrationNotificationsCase screen) {
  return switch (screen) {
    MigrationNotificationsCase.prompt => 'Enable',
    MigrationNotificationsCase.confirmSkip => 'Confirm skip',
  };
}

// --- Mobile > Start --------------------------------------------------------

enum MigrationMobileStartCase { loading, keystoneReady }

Widget buildMigrationMobileStartGalleryCase(BuildContext context) {
  final phase = wbStateKnob<MigrationMobileStartCase>(
    context,
    label: 'Phase',
    options: MigrationMobileStartCase.values,
    labelBuilder: migrationMobileStartCaseLabel,
  );
  return switch (phase) {
    MigrationMobileStartCase.loading =>
      buildMobileIronwoodMigrationStartLoadingUseCase(context),
    MigrationMobileStartCase.keystoneReady =>
      buildMobileIronwoodMigrationStartKeystoneReadyUseCase(context),
  };
}

String migrationMobileStartCaseLabel(MigrationMobileStartCase phase) {
  return switch (phase) {
    MigrationMobileStartCase.loading => 'Loading',
    MigrationMobileStartCase.keystoneReady => 'Keystone ready',
  };
}

// --- Mobile > Preparation --------------------------------------------------

enum MigrationPreparationCase {
  active,
  paused,
  pausedKeystone,
  syncing,
  complete,
}

Widget buildMigrationMobilePreparationGalleryCase(BuildContext context) {
  final state = wbStateKnob<MigrationPreparationCase>(
    context,
    label: 'State',
    options: MigrationPreparationCase.values,
    labelBuilder: migrationPreparationCaseLabel,
  );
  return switch (state) {
    MigrationPreparationCase.active =>
      buildMobileIronwoodMigrationPreparationActiveUseCase(context),
    MigrationPreparationCase.paused =>
      buildMobileIronwoodMigrationPreparationPausedUseCase(context),
    MigrationPreparationCase.pausedKeystone =>
      buildMobileIronwoodMigrationPreparationPausedKeystoneUseCase(context),
    MigrationPreparationCase.syncing =>
      buildMobileIronwoodMigrationPreparationSyncingUseCase(context),
    MigrationPreparationCase.complete =>
      buildMobileIronwoodMigrationPreparationCompleteUseCase(context),
  };
}

String migrationPreparationCaseLabel(MigrationPreparationCase state) {
  return switch (state) {
    MigrationPreparationCase.active => 'Active',
    MigrationPreparationCase.paused => 'Continue',
    MigrationPreparationCase.pausedKeystone => 'Continue, Keystone',
    MigrationPreparationCase.syncing => 'Syncing',
    MigrationPreparationCase.complete => 'Preparation done',
  };
}

// --- Mobile > Migration progress -------------------------------------------

enum MigrationProgressCase {
  syncing,
  waitingNotificationsOn,
  waitingNotificationsOff,
  needsInput,
  keystoneSignAll,
  broadcasting,
  complete,
}

Widget buildMigrationMobileProgressGalleryCase(BuildContext context) {
  final state = wbStateKnob<MigrationProgressCase>(
    context,
    label: 'State',
    options: MigrationProgressCase.values,
    labelBuilder: migrationProgressCaseLabel,
  );
  return switch (state) {
    MigrationProgressCase.syncing => buildMobileIronwoodMigrationSyncingUseCase(
      context,
    ),
    MigrationProgressCase.waitingNotificationsOn =>
      buildMobileIronwoodMigrationWaitingNotificationsOnUseCase(context),
    MigrationProgressCase.waitingNotificationsOff =>
      buildMobileIronwoodMigrationWaitingNotificationsOffUseCase(context),
    MigrationProgressCase.needsInput =>
      buildMobileIronwoodMigrationNeedsInputUseCase(context),
    MigrationProgressCase.keystoneSignAll =>
      buildMobileIronwoodMigrationKeystoneSignAllUseCase(context),
    MigrationProgressCase.broadcasting =>
      buildMobileIronwoodMigrationBroadcastingUseCase(context),
    MigrationProgressCase.complete =>
      buildMobileIronwoodMigrationCompleteUseCase(context),
  };
}

String migrationProgressCaseLabel(MigrationProgressCase state) {
  return switch (state) {
    MigrationProgressCase.syncing => 'Syncing',
    MigrationProgressCase.waitingNotificationsOn => 'Waiting, alerts on',
    MigrationProgressCase.waitingNotificationsOff => 'Waiting, alerts off',
    MigrationProgressCase.needsInput => 'Needs input',
    MigrationProgressCase.keystoneSignAll => 'Keystone sign all',
    MigrationProgressCase.broadcasting => 'Broadcasting',
    MigrationProgressCase.complete => 'Complete',
  };
}

// --- Mobile > Migration status ---------------------------------------------

Widget buildMigrationMobileStatusGalleryCase(BuildContext context) {
  final phase = wbStateKnob<MigrationMobileStatusPhaseCase>(
    context,
    label: 'Phase',
    options: MigrationMobileStatusPhaseCase.values,
    labelBuilder: migrationMobileStatusPhaseCaseLabel,
  );
  final account = wbStateKnob<MigrationMobileAccountCase>(
    context,
    label: 'Account',
    options: MigrationMobileAccountCase.values,
    labelBuilder: migrationMobileAccountCaseLabel,
  );
  final route = wbStateKnob<MigrationMobileStatusRouteCase>(
    context,
    label: 'Route',
    options: MigrationMobileStatusRouteCase.values,
    labelBuilder: migrationMobileStatusRouteCaseLabel,
  );
  final notifications = wbBoolKnob(
    context,
    label: 'Notifications allowed',
    initial: true,
  );
  final backgroundTracking = wbBoolKnob(
    context,
    label: 'Background tracking',
    initial: true,
  );
  return migrationMobileStatusFixture(
    phase: phase,
    account: account,
    notificationsAuthorized: notifications,
    backgroundTrackingSupported: backgroundTracking,
    route: route,
  );
}

String migrationMobileStatusPhaseCaseLabel(
  MigrationMobileStatusPhaseCase phase,
) {
  return switch (phase) {
    MigrationMobileStatusPhaseCase.awaitingPreparation =>
      'Awaiting preparation',
    MigrationMobileStatusPhaseCase.confirmingSplits => 'Confirming splits',
    MigrationMobileStatusPhaseCase.readyToMigrate => 'Ready to migrate',
    MigrationMobileStatusPhaseCase.broadcastScheduled => 'Broadcast scheduled',
    MigrationMobileStatusPhaseCase.broadcasting => 'Broadcasting',
    MigrationMobileStatusPhaseCase.confirmingMigration =>
      'Confirming migration',
    MigrationMobileStatusPhaseCase.needsRecovery => 'Needs recovery',
    MigrationMobileStatusPhaseCase.paused => 'Paused',
    MigrationMobileStatusPhaseCase.complete => 'Complete',
  };
}

String migrationMobileAccountCaseLabel(MigrationMobileAccountCase account) {
  return switch (account) {
    MigrationMobileAccountCase.software => 'Software',
    MigrationMobileAccountCase.keystone => 'Keystone',
  };
}

String migrationMobileStatusRouteCaseLabel(
  MigrationMobileStatusRouteCase route,
) {
  return switch (route) {
    MigrationMobileStatusRouteCase.status => 'Status',
    MigrationMobileStatusRouteCase.loading => 'Loading',
    MigrationMobileStatusRouteCase.redirectHome => 'Sent home',
    MigrationMobileStatusRouteCase.redirectStart => 'Sent to About Ironwood',
  };
}

// --- Mobile > Preparing & migrating ----------------------------------------

Widget buildMigrationMobileLiveStepsGalleryCase(BuildContext context) {
  final step = wbStateKnob<MigrationMobileLiveStepCase>(
    context,
    label: 'Step',
    options: MigrationMobileLiveStepCase.values,
    labelBuilder: migrationMobileLiveStepCaseLabel,
  );
  final account = wbStateKnob<MigrationMobileAccountCase>(
    context,
    label: 'Account',
    options: MigrationMobileAccountCase.values,
    labelBuilder: migrationMobileAccountCaseLabel,
  );
  final partStatus = wbStateKnob<MobileIronwoodMigrationPartStatus>(
    context,
    label: 'Part status',
    options: MobileIronwoodMigrationPartStatus.values,
    labelBuilder: migrationMobilePartStatusLabel,
  );
  final recovery = wbStateKnob<MigrationMobileRecoveryCase>(
    context,
    label: 'Recovery',
    options: MigrationMobileRecoveryCase.values,
    labelBuilder: migrationMobileRecoveryCaseLabel,
  );
  return migrationMobileLiveStepFixture(
    step: step,
    account: account,
    partStatus: partStatus,
    recovery: recovery,
  );
}

String migrationMobileLiveStepCaseLabel(MigrationMobileLiveStepCase step) {
  return switch (step) {
    MigrationMobileLiveStepCase.preparing => 'Preparing',
    MigrationMobileLiveStepCase.migrating => 'Migrating',
  };
}

/// Row states of the migrating step; the preparing step always lists its parts
/// as pending, so this axis only moves there.
String migrationMobilePartStatusLabel(
  MobileIronwoodMigrationPartStatus status,
) {
  return switch (status) {
    MobileIronwoodMigrationPartStatus.complete => 'Complete',
    MobileIronwoodMigrationPartStatus.needsInput => 'Needs input',
    MobileIronwoodMigrationPartStatus.active => 'Active',
    MobileIronwoodMigrationPartStatus.pending => 'Pending',
  };
}

String migrationMobileRecoveryCaseLabel(MigrationMobileRecoveryCase recovery) {
  return switch (recovery) {
    MigrationMobileRecoveryCase.none => 'None',
    MigrationMobileRecoveryCase.credentialRecovery => 'Credential recovery',
  };
}

// --- Mobile > Keystone signing ---------------------------------------------

enum MigrationKeystoneStateCase { loading, requestQr, scanner, scanHelp }

/// Round split of the request; only the request QR shows the round badge.
enum MigrationKeystoneRoundsCase { multi, single }

/// Which signing round the view announces. Only the screen-reader label
/// changes, so the two options are pixel-identical by design.
enum MigrationKeystoneRoundCase { denominationSplit, migrationBatch }

/// Whether the scanner has multi-part progress to report yet.
enum MigrationKeystoneScanProgressCase { partial, none }

/// The caption under the viewfinder, as the signing screen sets it.
enum MigrationKeystoneScannerMessageCase {
  defaultPrompt,
  scanSignedQr,
  applyingSignature,
  waitingForProofs,
  scanFailed,
}

Widget buildMigrationMobileKeystoneGalleryCase(BuildContext context) {
  final state = wbStateKnob<MigrationKeystoneStateCase>(
    context,
    label: 'State',
    options: MigrationKeystoneStateCase.values,
    labelBuilder: migrationKeystoneStateCaseLabel,
  );
  final rounds = wbStateKnob<MigrationKeystoneRoundsCase>(
    context,
    label: 'Rounds',
    options: MigrationKeystoneRoundsCase.values,
    labelBuilder: migrationKeystoneRoundsCaseLabel,
  );
  final round = wbStateKnob<MigrationKeystoneRoundCase>(
    context,
    label: 'Round',
    options: MigrationKeystoneRoundCase.values,
    labelBuilder: migrationKeystoneRoundCaseLabel,
  );
  final scanProgress = wbStateKnob<MigrationKeystoneScanProgressCase>(
    context,
    label: 'Scan progress',
    options: MigrationKeystoneScanProgressCase.values,
    labelBuilder: migrationKeystoneScanProgressCaseLabel,
  );
  final message = wbStateKnob<MigrationKeystoneScannerMessageCase>(
    context,
    label: 'Scanner message',
    options: MigrationKeystoneScannerMessageCase.values,
    labelBuilder: migrationKeystoneScannerMessageCaseLabel,
  );

  // The scan-help option is the sheet over the scanner, which only the preview
  // surface fixture assembles, so the leaf axes do not reach it.
  final usesExistingFixture =
      state == MigrationKeystoneStateCase.scanHelp ||
      (round == MigrationKeystoneRoundCase.denominationSplit &&
          scanProgress == MigrationKeystoneScanProgressCase.partial &&
          message == MigrationKeystoneScannerMessageCase.defaultPrompt);
  if (usesExistingFixture) {
    if (state == MigrationKeystoneStateCase.requestQr &&
        rounds == MigrationKeystoneRoundsCase.single) {
      return buildMobileIronwoodMigrationKeystoneReadySingleRoundUseCase(
        context,
      );
    }
    return switch (state) {
      MigrationKeystoneStateCase.loading =>
        buildMobileIronwoodMigrationKeystoneLoadingUseCase(context),
      MigrationKeystoneStateCase.requestQr =>
        buildMobileIronwoodMigrationKeystoneReadyUseCase(context),
      MigrationKeystoneStateCase.scanner =>
        buildMobileIronwoodMigrationKeystoneScannerUseCase(context),
      MigrationKeystoneStateCase.scanHelp =>
        buildMobileIronwoodMigrationKeystoneHelpUseCase(context),
    };
  }
  return migrationMobileKeystoneSigningFixture(
    state: switch (state) {
      MigrationKeystoneStateCase.loading =>
        MobileIronwoodKeystoneSigningViewState.loading,
      MigrationKeystoneStateCase.requestQr =>
        MobileIronwoodKeystoneSigningViewState.ready,
      MigrationKeystoneStateCase.scanner ||
      MigrationKeystoneStateCase.scanHelp =>
        MobileIronwoodKeystoneSigningViewState.scanner,
    },
    round: round == MigrationKeystoneRoundCase.denominationSplit
        ? MobileIronwoodKeystoneSigningRound.denominationSplit
        : MobileIronwoodKeystoneSigningRound.migrationBatch,
    multiRound: rounds == MigrationKeystoneRoundsCase.multi,
    scanProgress: scanProgress == MigrationKeystoneScanProgressCase.partial,
    scannerMessage: migrationKeystoneScannerMessageText(message),
    scannerMessageIsError:
        message == MigrationKeystoneScannerMessageCase.scanFailed,
  );
}

String migrationKeystoneRoundCaseLabel(MigrationKeystoneRoundCase round) {
  return switch (round) {
    MigrationKeystoneRoundCase.denominationSplit => 'Denomination split',
    MigrationKeystoneRoundCase.migrationBatch => 'Migration batch',
  };
}

String migrationKeystoneScanProgressCaseLabel(
  MigrationKeystoneScanProgressCase progress,
) {
  return switch (progress) {
    MigrationKeystoneScanProgressCase.partial => 'Partly scanned',
    MigrationKeystoneScanProgressCase.none => 'Nothing scanned yet',
  };
}

String migrationKeystoneScannerMessageCaseLabel(
  MigrationKeystoneScannerMessageCase message,
) {
  return switch (message) {
    MigrationKeystoneScannerMessageCase.defaultPrompt => 'Confirm on Keystone',
    MigrationKeystoneScannerMessageCase.scanSignedQr => 'Scan the signed QR',
    MigrationKeystoneScannerMessageCase.applyingSignature =>
      'Applying signature',
    MigrationKeystoneScannerMessageCase.waitingForProofs =>
      'Waiting for proofs',
    MigrationKeystoneScannerMessageCase.scanFailed => 'Scan failed',
  };
}

/// The caption the signing screen passes for each state; null keeps the view's
/// own default prompt.
String? migrationKeystoneScannerMessageText(
  MigrationKeystoneScannerMessageCase message,
) {
  return switch (message) {
    MigrationKeystoneScannerMessageCase.defaultPrompt => null,
    MigrationKeystoneScannerMessageCase.scanSignedQr =>
      'Scan the new signed QR shown on Keystone.',
    MigrationKeystoneScannerMessageCase.applyingSignature =>
      'Applying the Keystone signature.',
    MigrationKeystoneScannerMessageCase.waitingForProofs =>
      'Signature captured. Waiting for local proofs.',
    MigrationKeystoneScannerMessageCase.scanFailed =>
      'Keep the QR code steady and fully visible.',
  };
}

String migrationKeystoneStateCaseLabel(MigrationKeystoneStateCase state) {
  return switch (state) {
    MigrationKeystoneStateCase.loading => 'Loading',
    MigrationKeystoneStateCase.requestQr => 'Request QR',
    MigrationKeystoneStateCase.scanner => 'Scanner',
    MigrationKeystoneStateCase.scanHelp => 'Scan help',
  };
}

String migrationKeystoneRoundsCaseLabel(MigrationKeystoneRoundsCase rounds) {
  return switch (rounds) {
    MigrationKeystoneRoundsCase.multi => 'Multi-round',
    MigrationKeystoneRoundsCase.single => 'Single round',
  };
}

// --- Mobile > Home attention -----------------------------------------------

enum MigrationHomeAttentionCase { banner, modal }

Widget buildMigrationMobileHomeAttentionGalleryCase(BuildContext context) {
  final attention = wbStateKnob<MigrationHomeAttentionCase>(
    context,
    label: 'Attention',
    options: MigrationHomeAttentionCase.values,
    labelBuilder: migrationHomeAttentionCaseLabel,
  );
  return switch (attention) {
    MigrationHomeAttentionCase.banner =>
      buildMobileIronwoodMigrationHomeAttentionUseCase(context),
    MigrationHomeAttentionCase.modal =>
      buildMobileIronwoodMigrationHomeAttentionModalUseCase(context),
  };
}

String migrationHomeAttentionCaseLabel(MigrationHomeAttentionCase attention) {
  return switch (attention) {
    MigrationHomeAttentionCase.banner => 'Banner',
    MigrationHomeAttentionCase.modal => 'Modal',
  };
}

// --- Keystone signing ------------------------------------------------------

/// Both layouts of every signing screen are one dispatcher: desktop and mobile
/// are separate widget classes over the same private screen and the same three
/// stages, so the form factor is a knob rather than a sibling component.
Widget buildMigrationKeystoneCombinedSignGalleryCase(BuildContext context) {
  return _migrationKeystoneSignGalleryCase(
    context,
    MigrationKeystoneSignStep.combined,
  );
}

/// Immediate signing is one transaction, so it carries no rounds axis; the
/// desktop 'Scanning' state already lives under 'Immediate review'.
Widget buildMigrationKeystoneImmediateSignGalleryCase(BuildContext context) {
  return _migrationKeystoneSignGalleryCase(
    context,
    MigrationKeystoneSignStep.immediate,
    rounds: false,
  );
}

Widget buildMigrationKeystoneDenominationSignGalleryCase(BuildContext context) {
  return _migrationKeystoneSignGalleryCase(
    context,
    MigrationKeystoneSignStep.denomination,
  );
}

Widget buildMigrationKeystoneBatchSignGalleryCase(BuildContext context) {
  return _migrationKeystoneSignGalleryCase(
    context,
    MigrationKeystoneSignStep.batch,
  );
}

Widget _migrationKeystoneSignGalleryCase(
  BuildContext context,
  MigrationKeystoneSignStep step, {
  bool rounds = true,
}) {
  final layout = wbLayoutKnob(context);
  // The desktop denomination and batch screens take no preview request, so a
  // Request QR there renders the preparing spinner and never a round badge.
  final requestQrReachable =
      layout == WbLayout.mobile ||
      (step != MigrationKeystoneSignStep.denomination &&
          step != MigrationKeystoneSignStep.batch);
  // Scanning is served by the scanner fixture, which only the combined and
  // immediate mobile screens reach: the desktop branch swaps the scanner for a
  // static placeholder, and the denomination/batch previews never start one.
  final scanStep = layout == WbLayout.mobile ? _migrationScanStep(step) : null;
  final stage = wbStateKnob<MigrationKeystoneSignStage>(
    context,
    label: 'Stage',
    options: [
      if (requestQrReachable) ...[
        MigrationKeystoneSignStage.preparing,
        MigrationKeystoneSignStage.requestQr,
        MigrationKeystoneSignStage.failed,
      ] else ...[
        MigrationKeystoneSignStage.preparing,
        MigrationKeystoneSignStage.failed,
      ],
      if (scanStep != null) MigrationKeystoneSignStage.scanning,
    ],
    labelBuilder: migrationKeystoneSignStageLabel,
    initial: requestQrReachable
        ? MigrationKeystoneSignStage.requestQr
        : MigrationKeystoneSignStage.preparing,
  );
  if (stage == MigrationKeystoneSignStage.scanning && scanStep != null) {
    WbFakeUrScanRustApi.install();
    return buildScannerMigrationGalleryCase(context, step: scanStep);
  }
  final roundSplit = rounds && requestQrReachable
      ? wbStateKnob<MigrationKeystoneRoundsCase>(
          context,
          label: 'Rounds',
          options: MigrationKeystoneRoundsCase.values,
          labelBuilder: migrationKeystoneRoundsCaseLabel,
        )
      : MigrationKeystoneRoundsCase.single;
  return migrationKeystoneSignFixture(
    step: step,
    layout: layout,
    stage: stage,
    multiRound: roundSplit == MigrationKeystoneRoundsCase.multi,
  );
}

/// The signing screens the scanner fixture covers; null for the two whose
/// preview never opens a camera.
ScannerMigrationStepCase? _migrationScanStep(MigrationKeystoneSignStep step) {
  return switch (step) {
    MigrationKeystoneSignStep.combined => ScannerMigrationStepCase.combined,
    MigrationKeystoneSignStep.immediate => ScannerMigrationStepCase.immediate,
    MigrationKeystoneSignStep.denomination ||
    MigrationKeystoneSignStep.batch => null,
  };
}

String migrationKeystoneSignStageLabel(MigrationKeystoneSignStage stage) {
  return switch (stage) {
    MigrationKeystoneSignStage.preparing => 'Preparing',
    MigrationKeystoneSignStage.requestQr => 'Request QR',
    MigrationKeystoneSignStage.failed => 'Signing failed',
    MigrationKeystoneSignStage.scanning => 'Scanning',
  };
}

// --- Home migration banner -------------------------------------------------

enum MigrationHomeBannerCase { migrationRequired, inProgress }

Widget buildMigrationHomeBannerGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final mode = wbStateKnob<MigrationHomeBannerCase>(
    context,
    label: 'Mode',
    options: MigrationHomeBannerCase.values,
    labelBuilder: migrationHomeBannerCaseLabel,
  );
  // Both home fixtures carry their own desktop-window / phone frame and render
  // in either lane, so the knob dispatches instead of gating the off-lane
  // preview behind `WbLaneOnly` — off-lane tokens are an approximation here,
  // not an assertion failure.
  if (layout == WbLayout.mobile) {
    return switch (mode) {
      MigrationHomeBannerCase.migrationRequired =>
        buildMobileHomeIronwoodMigrationRequiredUseCase(context),
      MigrationHomeBannerCase.inProgress =>
        buildMobileHomeIronwoodMigrationInProgressUseCase(context),
    };
  }
  return switch (mode) {
    MigrationHomeBannerCase.migrationRequired =>
      buildDesktopHomeIronwoodMigrationRequiredUseCase(context),
    MigrationHomeBannerCase.inProgress =>
      buildDesktopHomeIronwoodMigrationInProgressUseCase(context),
  };
}

String migrationHomeBannerCaseLabel(MigrationHomeBannerCase mode) {
  return switch (mode) {
    MigrationHomeBannerCase.migrationRequired => 'Migration required',
    MigrationHomeBannerCase.inProgress => 'In progress',
  };
}

// --- Home announcement -----------------------------------------------------

/// `buildIronwoodMigrationAnnouncementModalUseCase` is a one-line alias of the
/// desktop builder below, so it needs no option of its own.
Widget buildMigrationHomeAnnouncementGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return layout == WbLayout.mobile
      ? buildMobileHomeIronwoodAnnouncementUseCase(context)
      : buildDesktopHomeIronwoodMigrationAnnouncementUseCase(context);
}
