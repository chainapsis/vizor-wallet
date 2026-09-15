import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/services.dart'
    show FontLoader, MethodCall, MethodChannel, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/core/security/password_policy.dart';
import 'package:zcash_wallet/src/features/onboarding/unlock_screen.dart';
import 'package:zcash_wallet/widgetbook/gallery/migration_gallery.dart';
import 'package:zcash_wallet/widgetbook/migration_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Lane-agnostic: the layout knob is driven by explicit query params, never by
// the compiled lane, so both test lanes exercise the same combinations.
//
// Two environment facts shape the assertions below:
//  - real fonts are loaded, because the migration screens are dense enough
//    that the test-default font metrics overflow almost every row;
//  - the desktop migration screens are gated to the desktop lane in the
//    gallery (`AppCarousel` asserts the form factor), so the mobile lane
//    asserts the lane notice instead of the screen.
void main() {
  setUpAll(_loadAppFonts);

  testWidgets('every migration gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(migrationGalleryNodes).toList();
    expect(useCases.length, 22);

    for (final useCase in useCases) {
      final errors = await _pumpCollectingErrors(tester, useCase.builder);
      expect(errors, isEmpty, reason: useCase.name);
    }
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop flow and review knobs cover every option distinctly', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationFlowGalleryCase,
      label: 'Step',
      optionLabels: MigrationFlowStepCase.values
          .map(migrationFlowStepCaseLabel)
          .toList(),
      // The flow is one use case for both form factors, so every desktop
      // sweep pins the layout instead of relying on the compiled lane.
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPrivateReviewGalleryCase,
      label: 'Stage',
      optionLabels: MigrationPrivateReviewCase.values
          .map(migrationPrivateReviewCaseLabel)
          .toList(),
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationImmediateReviewGalleryCase,
      label: 'Stage',
      optionLabels: MigrationImmediateReviewCase.values
          .map(migrationImmediateReviewCaseLabel)
          .toList(),
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop status and schedule knobs cover every option', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPrivateStatusGalleryCase,
      label: 'Phase',
      optionLabels: MigrationPrivateStatusCase.values
          .map(migrationPrivateStatusCaseLabel)
          .toList(),
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationScheduleGalleryCase,
      label: 'Overlay',
      optionLabels: MigrationScheduleOverlayCase.values
          .map(migrationScheduleOverlayCaseLabel)
          .toList(),
      otherKnobs: _desktopLayout,
    );
    // The 1.5x option overflows by design — that is what the large-text
    // fixture exists to show.
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Text size',
      optionLabels: MigrationTextSizeCase.values
          .map(migrationTextSizeCaseLabel)
          .toList(),
      otherKnobs: _desktopLayout,
      allowLayoutOverflow: true,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile single-axis knobs cover every option distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileNotificationsGalleryCase,
      label: 'Screen',
      optionLabels: MigrationNotificationsCase.values
          .map(migrationNotificationsCaseLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileStartGalleryCase,
      label: 'Phase',
      optionLabels: MigrationMobileStartCase.values
          .map(migrationMobileStartCaseLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobilePreparationGalleryCase,
      label: 'State',
      optionLabels: MigrationPreparationCase.values
          .map(migrationPreparationCaseLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileProgressGalleryCase,
      label: 'State',
      optionLabels: MigrationProgressCase.values
          .map(migrationProgressCaseLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileHomeAttentionGalleryCase,
      label: 'Attention',
      optionLabels: MigrationHomeAttentionCase.values
          .map(migrationHomeAttentionCaseLabel)
          .toList(),
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile Keystone signing covers the state and round axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileKeystoneGalleryCase,
      label: 'State',
      optionLabels: MigrationKeystoneStateCase.values
          .map(migrationKeystoneStateCaseLabel)
          .toList(),
      otherKnobs: {
        'Rounds': migrationKeystoneRoundsCaseLabel(
          MigrationKeystoneRoundsCase.multi,
        ),
      },
    );
    // The round badge only exists on the request QR, so that is where the
    // second axis is swept.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileKeystoneGalleryCase,
      label: 'Rounds',
      optionLabels: MigrationKeystoneRoundsCase.values
          .map(migrationKeystoneRoundsCaseLabel)
          .toList(),
      otherKnobs: {
        'State': migrationKeystoneStateCaseLabel(
          MigrationKeystoneStateCase.requestQr,
        ),
      },
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('Keystone signing screens cover their stage axis', (
    tester,
  ) async {
    const stageLabels = ['Preparing', 'Request QR', 'Signing failed'];
    // Only the mobile combined and immediate screens open a camera, so only
    // they carry the Scanning stage the scanner fixture serves.
    for (final builder in const <WidgetBuilder>[
      buildMigrationKeystoneCombinedSignGalleryCase,
      buildMigrationKeystoneImmediateSignGalleryCase,
    ]) {
      await _expectKeystoneSignOptionsDistinct(
        tester,
        builder,
        label: 'Stage',
        optionLabels: const [...stageLabels, 'Scanning'],
        layout: WbLayout.mobile,
      );
    }

    for (final builder in const <WidgetBuilder>[
      buildMigrationKeystoneDenominationSignGalleryCase,
      buildMigrationKeystoneBatchSignGalleryCase,
    ]) {
      await _expectKeystoneSignOptionsDistinct(
        tester,
        builder,
        label: 'Stage',
        optionLabels: stageLabels,
        layout: WbLayout.mobile,
      );
    }

    for (final builder in const <WidgetBuilder>[
      buildMigrationKeystoneCombinedSignGalleryCase,
      buildMigrationKeystoneImmediateSignGalleryCase,
    ]) {
      await _expectKeystoneSignOptionsDistinct(
        tester,
        builder,
        label: 'Stage',
        optionLabels: stageLabels,
        layout: WbLayout.desktop,
      );
    }

    // The desktop denomination and batch classes take no preview request, so
    // the gallery drops Request QR there and the knob offers these two only.
    for (final builder in const <WidgetBuilder>[
      buildMigrationKeystoneDenominationSignGalleryCase,
      buildMigrationKeystoneBatchSignGalleryCase,
    ]) {
      await _expectKeystoneSignOptionsDistinct(
        tester,
        builder,
        label: 'Stage',
        optionLabels: const ['Preparing', 'Signing failed'],
        layout: WbLayout.desktop,
      );
    }
    await _drainFixtureTimers(tester);
  });

  testWidgets('Keystone signing screens cover their round axis', (
    tester,
  ) async {
    final roundLabels = MigrationKeystoneRoundsCase.values
        .map(migrationKeystoneRoundsCaseLabel)
        .toList();
    // The round badge and the per-round transaction count only exist on the
    // request QR, so that is where the second axis is swept.
    for (final builder in const <WidgetBuilder>[
      buildMigrationKeystoneCombinedSignGalleryCase,
      buildMigrationKeystoneDenominationSignGalleryCase,
      buildMigrationKeystoneBatchSignGalleryCase,
    ]) {
      await _expectKeystoneSignOptionsDistinct(
        tester,
        builder,
        label: 'Rounds',
        optionLabels: roundLabels,
        layout: WbLayout.mobile,
        otherKnobs: {'Stage': 'Request QR'},
      );
    }

    // The desktop combined screen states the plan in rounds before the first
    // QR, so it carries the axis too.
    await _expectKeystoneSignOptionsDistinct(
      tester,
      buildMigrationKeystoneCombinedSignGalleryCase,
      label: 'Rounds',
      optionLabels: roundLabels,
      layout: WbLayout.desktop,
      otherKnobs: {'Stage': 'Request QR'},
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('home surfaces cover both layouts', (tester) async {
    for (final layout in WbLayout.values) {
      await _expectOptionsDistinct(
        tester,
        buildMigrationHomeBannerGalleryCase,
        label: 'Mode',
        optionLabels: MigrationHomeBannerCase.values
            .map(migrationHomeBannerCaseLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
        // Off-lane tokens on a home screen are an approximation, not a break.
        tolerateOverflow: !wbLayoutMatchesLane(layout),
      );
    }

    await _expectOptionsDistinct(
      tester,
      buildMigrationHomeAnnouncementGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      // One of the two options is always the off-lane home screen.
      tolerateOverflow: true,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop home announcement persists only in preview memory', (
    tester,
  ) async {
    // Desktop-only interaction: the mobile announcement has its own tests.
    if (wbCompiledLaneLayout != WbLayout.desktop) return;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final platformCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      platformCalls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final errors = await _pumpCollectingErrors(
      tester,
      buildMigrationHomeAnnouncementGalleryCase,
      knobs: _desktopLayout,
    );
    expect(errors, isEmpty);

    final overlayFinder = find.byKey(
      const ValueKey('ironwood_migration_announcement_overlay'),
    );
    final container = ProviderScope.containerOf(tester.element(overlayFinder));
    final store = container.read(ironwoodMigrationAnnouncementStoreProvider);
    expect(
      store,
      isNot(isA<SharedPreferencesIronwoodMigrationAnnouncementStore>()),
    );

    await tester.tap(find.text('Official Release Note'));
    await tester.pump();
    expect(platformCalls, isEmpty);

    tester.widget<AppPaneModalOverlay>(overlayFinder).onDismiss();
    await tester.pump();
    expect(overlayFinder, findsNothing);
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile intro release note stays inside Widgetbook', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final platformCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      platformCalls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final errors = await _pumpCollectingErrors(
      tester,
      buildMigrationFlowGalleryCase,
      knobs: {
        ..._mobileLayout,
        'Step': migrationMobileStepCaseLabel(MigrationMobileStepCase.intro),
      },
    );
    expect(errors, isEmpty);

    await tester.tap(find.text('Official release note'));
    await tester.pump();
    expect(platformCalls, isEmpty);
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile flow knobs reach every step fixture', (tester) async {
    // The gallery case supplies the router scope the flow screens' back
    // handler reads, so every combination renders and can be swept on pixels.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationFlowGalleryCase,
      label: 'Step',
      optionLabels: MigrationMobileStepCase.values
          .map(migrationMobileStepCaseLabel)
          .toList(),
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );

    // 'Private option' only changes the migration-type step.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationFlowGalleryCase,
      label: 'Private option',
      optionLabels: MigrationPrivateOptionCase.values
          .map(migrationPrivateOptionCaseLabel)
          .toList(),
      otherKnobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Step': migrationMobileStepCaseLabel(
          MigrationMobileStepCase.migrationType,
        ),
      },
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('migration flow registers per-layout state axes', (tester) async {
    final desktop = await pumpUseCase(
      tester,
      buildMigrationFlowGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(
      desktop.knobs.keys,
      containsAll(<String>['Layout', 'Step', 'Flow data', 'Selection']),
    );
    expect(desktop.knobs.keys, isNot(contains('Private option')));

    final mobile = await pumpUseCase(
      tester,
      buildMigrationFlowGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(
      mobile.knobs.keys,
      containsAll(<String>['Layout', 'Step', 'Private option']),
    );
    expect(mobile.knobs.keys, isNot(contains('Flow data')));
    expect(mobile.knobs.keys, isNot(contains('Selection')));

    // The two layouts share the 'Step' label but not its option set.
    expect(desktop.knobs['Step']!.initialValue, isA<MigrationFlowStepCase>());
    expect(mobile.knobs['Step']!.initialValue, isA<MigrationMobileStepCase>());
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop flow data knob reaches the fallback shell', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationFlowGalleryCase,
      label: 'Flow data',
      optionLabels: MigrationFlowDataCase.values
          .map(migrationFlowDataCaseLabel)
          .toList(),
      // The fallback only differs on a step that prints the account figures.
      otherKnobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'Step': migrationFlowStepCaseLabel(MigrationFlowStepCase.intro),
      },
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('prepare gate reaches every redirect and toast', (tester) async {
    // Pixel fingerprints cannot separate these: the gate always renders the
    // same loading shell and only its toast copy and redirect differ.
    final outcomes = <String, Finder>{
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.syncing): find
          .byType(CircularProgressIndicator),
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.notAvailable): find
          .text('Migration is not available for this account.'),
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.syncFailed): find
          .text('Sync could not finish. Try again once Vizor is synced.'),
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.statusError): find
          .text("Couldn't verify migration status."),
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.notNeeded): find
          .text('Migration is not needed for this account.'),
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.resume): find.text(
        'Navigated to /migration/private/status',
      ),
      migrationPrepareGateCaseLabel(MigrationPrepareGateCase.start): find.text(
        'Navigated to /migration/intro',
      ),
    };
    for (final outcome in outcomes.entries) {
      final errors = await _pumpCollectingErrors(
        tester,
        buildMigrationPrepareGateGalleryCase,
        knobs: {'Gate': outcome.key},
        // The gate resolves its status future, shows the toast, and only then
        // lets the router settle on the destination — three separate frames.
        extraFrames: 6,
      );
      expect(errors, isEmpty, reason: outcome.key);
      expect(
        wbCompiledLaneLayout == WbLayout.desktop
            ? outcome.value
            : find.byKey(const ValueKey('wb_lane_only_notice')),
        findsOneWidget,
        reason: outcome.key,
      );
    }
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop private status covers its async states', (tester) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPrivateStatusGalleryCase,
      label: 'Data',
      optionLabels: MigrationStatusDataCase.values
          .map(migrationStatusDataCaseLabel)
          .toList(),
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop migration schedule covers its new axes', (tester) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationScheduleGalleryCase,
      label: 'Data',
      optionLabels: MigrationScheduleDataCase.values
          .map(migrationScheduleDataCaseLabel)
          .toList(),
      otherKnobs: _desktopLayout,
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationScheduleGalleryCase,
      label: 'Row status',
      optionLabels: MigrationSchedulePartCase.values
          .map(migrationSchedulePartCaseLabel)
          .toList(),
      otherKnobs: _desktopLayout,
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationScheduleGalleryCase,
      label: 'Stop available',
      optionLabels: const ['false', 'true'],
      otherKnobs: _desktopLayout,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop preparation schedule covers its new axes', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Data',
      optionLabels: migrationPreparationDataOptions(
        WbLayout.desktop,
      ).map(migrationPreparationDataCaseLabel).toList(),
      otherKnobs: _desktopLayout,
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Split status',
      optionLabels: MigrationPreparationTxCase.values
          .map(migrationPreparationTxCaseLabel)
          .toList(),
      otherKnobs: _desktopLayout,
    );
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Output',
      optionLabels: MigrationPreparationOutputCase.values
          .map(migrationPreparationOutputCaseLabel)
          .toList(),
      otherKnobs: _desktopLayout,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop virtual unlock covers badge and motion', (tester) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationVirtualUnlockGalleryCase,
      label: 'Migration badge',
      optionLabels: const ['true', 'false'],
    );
    // The loader only differs once a frame has elapsed, which is what the
    // extra frame in the sweep provides.
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationVirtualUnlockGalleryCase,
      label: 'Motion',
      optionLabels: MigrationMotionCase.values
          .map(migrationMotionCaseLabel)
          .toList(),
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile status route covers every phase', (tester) async {
    await _expectMobileStatusOptionsDistinct(
      tester,
      label: 'Phase',
      optionLabels: MigrationMobileStatusPhaseCase.values
          .map(migrationMobileStatusPhaseCaseLabel)
          .toList(),
    );
    // Every phase but the two preparation ones renders behind the sync
    // skeleton until the surface refresh resolves, so one phase past that gate
    // is asserted by copy: distinct pixels alone would not prove the fixture's
    // probes ever completed.
    final errors = await _pumpCollectingErrors(
      tester,
      buildMigrationMobileStatusGalleryCase,
      knobs: {
        'Phase': migrationMobileStatusPhaseCaseLabel(
          MigrationMobileStatusPhaseCase.complete,
        ),
      },
      extraFrames: 4,
    );
    expect(errors, isEmpty);
    expect(
      find.text(
        'Migration went successfully and you can spend your funds as usual.',
      ),
      findsOneWidget,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile status route covers its route branches', (tester) async {
    await _expectMobileStatusOptionsDistinct(
      tester,
      label: 'Route',
      optionLabels: MigrationMobileStatusRouteCase.values
          .map(migrationMobileStatusRouteCaseLabel)
          .toList(),
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile status route covers account and device axes', (
    tester,
  ) async {
    // The account axis only changes copy where the device owns the next step.
    await _expectMobileStatusOptionsDistinct(
      tester,
      label: 'Account',
      optionLabels: MigrationMobileAccountCase.values
          .map(migrationMobileAccountCaseLabel)
          .toList(),
      otherKnobs: {
        'Phase': migrationMobileStatusPhaseCaseLabel(
          MigrationMobileStatusPhaseCase.awaitingPreparation,
        ),
      },
    );
    // Notifications and background tracking both decide how the preparation
    // dial explains itself while splits confirm.
    const confirmingSplits = {'Phase': 'Confirming splits'};
    await _expectMobileStatusOptionsDistinct(
      tester,
      label: 'Notifications allowed',
      optionLabels: const ['true', 'false'],
      otherKnobs: confirmingSplits,
    );
    await _expectMobileStatusOptionsDistinct(
      tester,
      label: 'Background tracking',
      optionLabels: const ['true', 'false'],
      otherKnobs: confirmingSplits,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile live steps cover their axes', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileLiveStepsGalleryCase,
      label: 'Step',
      optionLabels: MigrationMobileLiveStepCase.values
          .map(migrationMobileLiveStepCaseLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileLiveStepsGalleryCase,
      label: 'Account',
      optionLabels: MigrationMobileAccountCase.values
          .map(migrationMobileAccountCaseLabel)
          .toList(),
    );
    // Both remaining axes belong to the migrating step: the preparing step
    // always lists its parts as pending and has no recovery action.
    const migrating = {'Step': 'Migrating'};
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileLiveStepsGalleryCase,
      label: 'Part status',
      optionLabels: MobileIronwoodMigrationPartStatus.values
          .map(migrationMobilePartStatusLabel)
          .toList(),
      otherKnobs: migrating,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileLiveStepsGalleryCase,
      label: 'Recovery',
      optionLabels: MigrationMobileRecoveryCase.values
          .map(migrationMobileRecoveryCaseLabel)
          .toList(),
      otherKnobs: migrating,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile schedules cover their async and row axes', (
    tester,
  ) async {
    // The unavailable option only separates from the loader once its failing
    // status future has resolved, which is a frame after the first build.
    await _expectOptionsDistinct(
      tester,
      buildMigrationScheduleGalleryCase,
      label: 'Data',
      optionLabels: MigrationScheduleDataCase.values
          .map(migrationScheduleDataCaseLabel)
          .toList(),
      otherKnobs: _mobileLayout,
      extraFrames: 2,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationScheduleGalleryCase,
      label: 'Row status',
      optionLabels: MigrationSchedulePartCase.values
          .map(migrationSchedulePartCaseLabel)
          .toList(),
      otherKnobs: _mobileLayout,
    );
    // The pending run's unassigned tail shows on a scheduled row (a completed
    // row prints no height at all), and on the mixed run's own fixtures.
    for (final rowStatus in [
      MigrationSchedulePartCase.mixed,
      MigrationSchedulePartCase.scheduled,
    ]) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildMigrationScheduleGalleryCase,
        label: 'Schedule',
        optionLabels: MigrationScheduleAssignmentCase.values
            .map(migrationScheduleAssignmentCaseLabel)
            .toList(),
        otherKnobs: {
          ..._mobileLayout,
          'Row status': migrationSchedulePartCaseLabel(rowStatus),
        },
      );
    }

    await _expectOptionsDistinct(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Data',
      optionLabels: migrationPreparationDataOptions(
        WbLayout.mobile,
      ).map(migrationPreparationDataCaseLabel).toList(),
      otherKnobs: _mobileLayout,
      extraFrames: 2,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Split status',
      optionLabels: MigrationPreparationTxCase.values
          .map(migrationPreparationTxCaseLabel)
          .toList(),
      otherKnobs: _mobileLayout,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      label: 'Output',
      optionLabels: MigrationPreparationOutputCase.values
          .map(migrationPreparationOutputCaseLabel)
          .toList(),
      otherKnobs: _mobileLayout,
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('the schedules register per-layout state axes', (tester) async {
    Future<Set<String>> knobsOf(WidgetBuilder builder, WbLayout layout) async {
      final state = await pumpUseCase(
        tester,
        builder,
        knobs: {'Layout': wbLayoutLabel(layout)},
      );
      return state.knobs.keys.toSet();
    }

    expect(await knobsOf(buildMigrationScheduleGalleryCase, WbLayout.desktop), {
      'Layout',
      'Overlay',
      'Data',
      'Row status',
      'Stop available',
    });
    expect(await knobsOf(buildMigrationScheduleGalleryCase, WbLayout.mobile), {
      'Layout',
      'Schedule',
      'Data',
      'Row status',
    });
    expect(
      await knobsOf(
        buildMigrationPreparationScheduleGalleryCase,
        WbLayout.desktop,
      ),
      {'Layout', 'Text size', 'Data', 'Split status', 'Output'},
    );
    expect(
      await knobsOf(
        buildMigrationPreparationScheduleGalleryCase,
        WbLayout.mobile,
      ),
      {'Layout', 'Data', 'Split status', 'Output'},
    );
    // The round-less run has no mobile fixture, so mobile does not offer it.
    expect(
      migrationPreparationDataOptions(WbLayout.mobile),
      isNot(contains(MigrationPreparationDataCase.empty)),
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('mobile Keystone signing covers its scanner axes', (
    tester,
  ) async {
    const scanner = {'State': 'Scanner'};
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileKeystoneGalleryCase,
      label: 'Scan progress',
      optionLabels: MigrationKeystoneScanProgressCase.values
          .map(migrationKeystoneScanProgressCaseLabel)
          .toList(),
      otherKnobs: scanner,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMigrationMobileKeystoneGalleryCase,
      label: 'Scanner message',
      optionLabels: MigrationKeystoneScannerMessageCase.values
          .map(migrationKeystoneScannerMessageCaseLabel)
          .toList(),
      otherKnobs: scanner,
    );
    await _drainFixtureTimers(tester);
  });

  _wave2MigrationGalleryTests();

  testWidgets('mobile Keystone signing announces the round it signs', (
    tester,
  ) async {
    // The round changes only the screen-reader label, so this axis is asserted
    // on semantics rather than on pixels.
    final semantics = tester.ensureSemantics();
    const expected = {
      'Denomination split': 'Confirm migration preparation with Keystone',
      'Migration batch': 'Confirm migration transfer with Keystone',
    };
    for (final round in expected.entries) {
      final errors = await _pumpCollectingErrors(
        tester,
        buildMigrationMobileKeystoneGalleryCase,
        knobs: {'State': 'Request QR', 'Round': round.key},
      );
      expect(errors, isEmpty, reason: round.key);
      expect(
        find.bySemanticsLabel(round.value),
        findsOneWidget,
        reason: round.key,
      );
    }
    semantics.dispose();
    await _drainFixtureTimers(tester);
  });
}

final Map<String, String> _desktopLayout = {
  'Layout': wbLayoutLabel(WbLayout.desktop),
};
final Map<String, String> _mobileLayout = {
  'Layout': wbLayoutLabel(WbLayout.mobile),
};

/// Sweeps one axis of the mobile status route.
///
/// The screen only leaves its sync skeleton after a chain of awaited probes —
/// coordinator refresh, route CTA, notification and background-tracking
/// lookups — and its redirect branches need another frame for the router, so
/// the sweep pumps several frames per option.
Future<void> _expectMobileStatusOptionsDistinct(
  WidgetTester tester, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
}) {
  return _expectOptionsDistinct(
    tester,
    buildMigrationMobileStatusGalleryCase,
    label: label,
    optionLabels: optionLabels,
    otherKnobs: otherKnobs,
    extraFrames: 4,
  );
}

/// Sweeps one Keystone signing axis with the `Layout` knob pinned, so the
/// sweep is the same in both test lanes; the off-lane render mixes this lane's
/// tokens into the other form factor's screen and may overflow.
Future<void> _expectKeystoneSignOptionsDistinct(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  required WbLayout layout,
  Map<String, String> otherKnobs = const {},
}) {
  return _expectOptionsDistinct(
    tester,
    builder,
    label: label,
    optionLabels: optionLabels,
    otherKnobs: {...otherKnobs, 'Layout': wbLayoutLabel(layout)},
    tolerateOverflow: !wbLayoutMatchesLane(layout),
  );
}

/// Sweeps a desktop-lane surface: the real screens in the desktop lane, the
/// `WbLaneOnly` notice in the mobile one.
Future<void> _expectDesktopOptionsDistinct(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
  bool allowLayoutOverflow = false,
}) async {
  if (wbCompiledLaneLayout == WbLayout.desktop) {
    await _expectOptionsDistinct(
      tester,
      builder,
      label: label,
      optionLabels: optionLabels,
      otherKnobs: otherKnobs,
      tolerateOverflow: allowLayoutOverflow,
    );
    return;
  }
  for (final option in optionLabels) {
    final errors = await _pumpCollectingErrors(
      tester,
      builder,
      knobs: {...otherKnobs, label: option},
    );
    expect(errors, isEmpty, reason: '$label / $option');
    expect(
      find.byKey(const ValueKey('wb_lane_only_notice')),
      findsOneWidget,
      reason: '$label / $option',
    );
  }
  await disposeTree(tester);
}

void _wave2MigrationGalleryTests() {
  testWidgets('private review reruns after live stage changes', (tester) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;
    final state = await pumpUseCase(
      tester,
      buildMigrationPrivateReviewGalleryCase,
      knobs: {
        'Stage': migrationPrivateReviewCaseLabel(
          MigrationPrivateReviewCase.planUnavailable,
        ),
      },
    );
    for (final stage in [
      MigrationPrivateReviewCase.planUnavailable,
      MigrationPrivateReviewCase.startError,
      MigrationPrivateReviewCase.planUnavailable,
      MigrationPrivateReviewCase.startError,
    ]) {
      state.updateQueryField(
        group: 'knobs',
        field: 'Stage',
        value: migrationPrivateReviewCaseLabel(stage),
      );
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          stage == MigrationPrivateReviewCase.startError
              ? "Couldn't start migration. Try again."
              : "Couldn't analyze this balance",
        ),
        findsOneWidget,
      );
    }
    await _drainFixtureTimers(tester);
  });

  testWidgets('virtual unlock resubmits after live password changes', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;
    final state = await pumpUseCase(
      tester,
      buildMigrationVirtualUnlockGalleryCase,
      knobs: {
        'Password': migrationVirtualUnlockCaseLabel(
          MigrationVirtualUnlockCase.idle,
        ),
      },
    );
    for (final password in [
      MigrationVirtualUnlockCase.submitting,
      MigrationVirtualUnlockCase.wrongPassword,
      MigrationVirtualUnlockCase.policyError,
      MigrationVirtualUnlockCase.wrongPassword,
      MigrationVirtualUnlockCase.submitting,
      MigrationVirtualUnlockCase.idle,
    ]) {
      state.updateQueryField(
        group: 'knobs',
        field: 'Password',
        value: migrationVirtualUnlockCaseLabel(password),
      );
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      final content = tester.widget<DesktopUnlockContent>(
        find.byType(DesktopUnlockContent),
      );
      expect(content.messageText, switch (password) {
        MigrationVirtualUnlockCase.wrongPassword =>
          'Incorrect password. Try again.',
        MigrationVirtualUnlockCase.policyError => kWalletPasswordAsciiMessage,
        _ => null,
      });
      if (password == MigrationVirtualUnlockCase.submitting) {
        expect(content.canSubmit, isFalse);
        expect(content.passwordController.text, isNotEmpty);
      }
      if (password == MigrationVirtualUnlockCase.idle) {
        expect(content.passwordController.text, isEmpty);
      }
    }
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop private review reaches its plan and start failures', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationPrivateReviewGalleryCase,
      label: 'Motion',
      optionLabels: MigrationMotionCase.values
          .map(migrationMotionCaseLabel)
          .toList(),
      otherKnobs: {
        'Stage': migrationPrivateReviewCaseLabel(
          MigrationPrivateReviewCase.findingBatches,
        ),
      },
    );

    if (wbCompiledLaneLayout == WbLayout.desktop) {
      var errors = await _pumpCollectingErrors(
        tester,
        buildMigrationPrivateReviewGalleryCase,
        knobs: {
          'Stage': migrationPrivateReviewCaseLabel(
            MigrationPrivateReviewCase.planUnavailable,
          ),
        },
        extraFrame: const Duration(milliseconds: 16),
      );
      expect(errors, isEmpty, reason: 'private review / plan unavailable');
      expect(find.text("Couldn't analyze this balance"), findsOneWidget);

      // The start error is several awaits past a tap on a button that only
      // exists after the analyzing transition, so it needs driven frames.
      errors = await _pumpCollectingErrors(
        tester,
        buildMigrationPrivateReviewGalleryCase,
        knobs: {
          'Stage': migrationPrivateReviewCaseLabel(
            MigrationPrivateReviewCase.startError,
          ),
        },
        extraFrame: const Duration(milliseconds: 16),
        extraFrames: 20,
      );
      // The fixture coordinator throws on start; the screen is expected to
      // turn that into the copy below rather than let it reach the framework.
      expect(errors, isEmpty, reason: 'private review / start error');
      expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    }
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop migration options covers both selections', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationFlowGalleryCase,
      label: 'Selection',
      optionLabels: MigrationOptionSelectionCase.values
          .map(migrationOptionSelectionCaseLabel)
          .toList(),
      otherKnobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'Step': migrationFlowStepCaseLabel(MigrationFlowStepCase.options),
      },
    );
    await _drainFixtureTimers(tester);
  });

  testWidgets('desktop virtual unlock covers the password submit', (
    tester,
  ) async {
    await _expectDesktopOptionsDistinct(
      tester,
      buildMigrationVirtualUnlockGalleryCase,
      label: 'Password',
      optionLabels: MigrationVirtualUnlockCase.values
          .map(migrationVirtualUnlockCaseLabel)
          .toList(),
    );

    if (wbCompiledLaneLayout == WbLayout.desktop) {
      var errors = await _pumpCollectingErrors(
        tester,
        buildMigrationVirtualUnlockGalleryCase,
        knobs: {
          'Password': migrationVirtualUnlockCaseLabel(
            MigrationVirtualUnlockCase.wrongPassword,
          ),
        },
        extraFrame: const Duration(milliseconds: 16),
        extraFrames: 3,
      );
      expect(errors, isEmpty, reason: 'virtual unlock / wrong password');
      expect(find.text('Incorrect password. Try again.'), findsOneWidget);

      // The charset policy rejects the password before the security provider
      // is called, so its message is a different line from the rejection.
      errors = await _pumpCollectingErrors(
        tester,
        buildMigrationVirtualUnlockGalleryCase,
        knobs: {
          'Password': migrationVirtualUnlockCaseLabel(
            MigrationVirtualUnlockCase.policyError,
          ),
        },
        extraFrame: const Duration(milliseconds: 16),
        extraFrames: 3,
      );
      expect(errors, isEmpty, reason: 'virtual unlock / policy error');
      expect(find.text(kWalletPasswordAsciiMessage), findsOneWidget);
      expect(find.text('Incorrect password. Try again.'), findsNothing);

      // Submitting keeps the field filled and the message line clear while
      // the confirm call is still in flight.
      errors = await _pumpCollectingErrors(
        tester,
        buildMigrationVirtualUnlockGalleryCase,
        knobs: {
          'Password': migrationVirtualUnlockCaseLabel(
            MigrationVirtualUnlockCase.submitting,
          ),
        },
        extraFrame: const Duration(milliseconds: 16),
        extraFrames: 3,
      );
      expect(errors, isEmpty, reason: 'virtual unlock / submitting');
      expect(find.text('Incorrect password. Try again.'), findsNothing);
    }
    await _drainFixtureTimers(tester);
  });
}

/// Knob sweep that compares one frame in and may tolerate a layout overflow.
///
/// The shared [expectKnobOptionsRenderDistinctly] compares the first frame and
/// requires a clean render; the desktop migration surfaces need neither — the
/// review screen and the analyzing donut only diverge on the second frame, and
/// an off-lane or large-text screen overflows by design.
Future<void> _expectOptionsDistinct(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
  bool tolerateOverflow = false,
  int extraFrames = 0,
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    final errors = await _pumpCollectingErrors(
      tester,
      builder,
      knobs: {...otherKnobs, label: option},
      extraFrame: const Duration(milliseconds: 16),
      extraFrames: extraFrames,
    );
    expect(
      tolerateOverflow
          ? errors.where((error) => !error.contains('overflowed'))
          : errors,
      isEmpty,
      reason: '$label / $option',
    );

    final fingerprint = await useCaseFingerprint(tester);
    final duplicate = seen[fingerprint];
    expect(
      duplicate,
      isNull,
      reason:
          "'$label' options '$duplicate' and '$option' render identically — "
          'the knob has a dead option or a duplicated dispatch.',
    );
    seen[fingerprint] = option;
  }
  await disposeTree(tester);
}

/// Pumps [builder] while collecting framework errors individually.
///
/// `tester.takeException()` collapses several errors into one summary object
/// that cannot be classified, and the migration screens routinely raise more
/// than one overflow per frame.
Future<List<String>> _pumpCollectingErrors(
  WidgetTester tester,
  WidgetBuilder builder, {
  Map<String, String> knobs = const {},
  Duration? extraFrame,
  int extraFrames = 0,
}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add('${details.exception}');
  try {
    await pumpUseCase(tester, builder, knobs: knobs);
    if (extraFrame != null) await tester.pump(extraFrame);
    for (var frame = 0; frame < extraFrames; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// Lets one-shot fixture timers (the preparation-complete modal's 400 ms
/// reveal) fire after the tree is gone, which the binding checks for.
Future<void> _drainFixtureTimers(WidgetTester tester) async {
  await disposeTree(tester);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Bold.ttf'));
  final geistMono = FontLoader('Geist Mono')
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), geistMono.load(), youngSerif.load()]);
}
