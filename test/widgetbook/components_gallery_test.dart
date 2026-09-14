import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Icons, Material, MaterialApp, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/layout/app_pane_scroll_scaffold.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_carousel.dart';
import 'package:zcash_wallet/src/core/widgets/app_context_menu.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture_picker_modal.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_transaction_progress_screen.dart';
import 'package:zcash_wallet/src/core/widgets/network_fallback_toast.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/widgetbook/context_menu_use_cases.dart';
import 'package:zcash_wallet/widgetbook/core_use_cases.dart';
import 'package:zcash_wallet/widgetbook/gallery/components_gallery.dart';
import 'package:zcash_wallet/widgetbook/mobile_shell_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/toast_use_cases.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

/// Whether this binary compiled the desktop token set.
const bool _desktopLane = wbCompiledLaneLayout == WbLayout.desktop;

// Lane-agnostic: nothing here asserts a token metric, so both lanes run the
// same combinations. The mobile-shell cases render their own 393px frame in
// either lane; only their tokens differ. The two lane-dependent cases are the
// carousel, whose widget asserts the desktop form factor, and the main
// sidebar, which overflows under the mobile type tokens; both are gated with
// `WbLaneOnly`, so their sweeps run in the desktop lane only.
void main() {
  // The sidebar case swaps `defaultTargetPlatform` while it is mounted; make
  // sure a failed teardown cannot leak the override into later tests.
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('every components gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = [
      ...widgetbookUseCases(componentsGalleryNodes),
      ...widgetbookUseCases(tokensGalleryNodes),
      ...widgetbookUseCases(colorsGalleryNodes),
    ];
    expect(useCases.length, 50);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('button playground covers variant, size and state', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsButtonCase,
      label: 'Variant',
      optionLabels: AppButtonVariant.values
          .map(componentsButtonVariantLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsButtonCase,
      label: 'Size',
      optionLabels: AppButtonSize.values
          .map(componentsButtonSizeLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsButtonCase,
      label: 'State',
      optionLabels: ComponentsButtonState.values
          .map(componentsButtonStateLabel)
          .toList(),
    );
  });

  testWidgets('button playground icon toggles drop each slot', (tester) async {
    await pumpUseCase(tester, buildComponentsButtonCase);
    expect(find.byType(Icon), findsNWidgets(2));

    await pumpUseCase(
      tester,
      buildComponentsButtonCase,
      knobs: {'Leading icon': 'false'},
    );
    expect(find.byType(Icon), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsButtonCase,
      knobs: {'Leading icon': 'false', 'Trailing icon': 'false'},
    );
    expect(find.byType(Icon), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('button playground reaches the mediumLarge size', (tester) async {
    // No single `build*UseCase` renders mediumLarge; the knob is its only
    // entry point outside the matrix.
    await pumpUseCase(
      tester,
      buildComponentsButtonCase,
      knobs: {'Size': componentsButtonSizeLabel(AppButtonSize.mediumLarge)},
    );

    expect(find.text('Add to contacts'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('carousel previews only the desktop lane', (tester) async {
    // Both branches assert: `AppCarousel` asserts the desktop form factor, so
    // the desktop lane must render it and the mobile lane must show the run
    // command instead of asserting.
    for (final card in ComponentsCarouselCard.values) {
      await pumpUseCase(
        tester,
        buildComponentsCarouselCase,
        knobs: {'Card': componentsCarouselCardLabel(card)},
      );
      expect(tester.takeException(), isNull, reason: '$card');
      final notice = find.byKey(const ValueKey('wb_lane_only_notice'));
      if (_desktopLane) {
        expect(notice, findsNothing, reason: '$card');
        expect(find.byType(AppCarousel), findsOneWidget, reason: '$card');
      } else {
        expect(notice, findsOneWidget, reason: '$card');
        expect(find.byType(AppCarousel), findsNothing, reason: '$card');
      }
    }
    await disposeTree(tester);
  });

  testWidgets('carousel playground covers both decks and every card', (
    tester,
  ) async {
    if (!_desktopLane) return;

    for (final deck in ComponentsCarouselDeck.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildComponentsCarouselCase,
        label: 'Card',
        // 'Autoplay' starts on card 1, so it only differs from 'Card 1' once
        // the 5s timer fires — asserted separately below.
        optionLabels: const [
          ComponentsCarouselCard.one,
          ComponentsCarouselCard.two,
          ComponentsCarouselCard.three,
        ].map(componentsCarouselCardLabel).toList(),
        otherKnobs: {'Deck': componentsCarouselDeckLabel(deck)},
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsCarouselCase,
      label: 'Deck',
      optionLabels: ComponentsCarouselDeck.values
          .map(componentsCarouselDeckLabel)
          .toList(),
      otherKnobs: {
        'Card': componentsCarouselCardLabel(ComponentsCarouselCard.one),
      },
    );
  });

  testWidgets('carousel autoplay option advances on its own', (tester) async {
    if (!_desktopLane) return;

    await pumpUseCase(
      tester,
      buildComponentsCarouselCase,
      knobs: {
        'Deck': componentsCarouselDeckLabel(ComponentsCarouselDeck.migration),
        'Card': componentsCarouselCardLabel(ComponentsCarouselCard.autoplay),
      },
    );

    // Every page is built inside the PageView, so the assertion is the page
    // the viewport actually shows: the pixels move on their own after the 5s
    // autoplay interval plus the 400ms transition.
    await tester.pump(const Duration(seconds: 1));
    final firstPage = await useCaseFingerprint(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(await useCaseFingerprint(tester), isNot(firstPage));

    await pumpUseCase(
      tester,
      buildComponentsCarouselCase,
      knobs: {
        'Deck': componentsCarouselDeckLabel(ComponentsCarouselDeck.migration),
        'Card': componentsCarouselCardLabel(ComponentsCarouselCard.one),
      },
    );
    await tester.pump(const Duration(seconds: 1));
    final staticPage = await useCaseFingerprint(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(await useCaseFingerprint(tester), staticPage);
    await disposeTree(tester);
  });

  testWidgets('single-axis dispatchers cover every option distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsContextMenuCase,
      label: 'Menu',
      optionLabels: ComponentsContextMenu.values
          .map(componentsContextMenuLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsReviewWrapCardCase,
      label: 'Outcome',
      optionLabels: ComponentsReviewWrapCardOutcome.values
          .map(componentsReviewWrapCardOutcomeLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsTextFieldCase,
      label: 'Tone',
      optionLabels: componentsTextFieldTones
          .map(componentsTextFieldToneLabel)
          .toList(),
    );
  });

  testWidgets('text field playground switches to the multiline shell', (
    tester,
  ) async {
    await pumpUseCase(tester, buildComponentsTextFieldCase);
    expect(find.text('Send to'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsTextFieldCase,
      knobs: {'Text area': 'true'},
    );
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('512/512'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('loading icon motion knob drives the spinner', (tester) async {
    // Animated and static loaders are pixel-identical on the first frame, so
    // the distinguishing assertion is the widget flag, not a fingerprint.
    for (final motion in ComponentsLoadingIconMotion.values) {
      await pumpUseCase(
        tester,
        buildComponentsLoadingIconCase,
        knobs: {'Motion': componentsLoadingIconMotionLabel(motion)},
      );
      expect(tester.takeException(), isNull, reason: '$motion');

      final loaders = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .map((icon) => icon.animated)
          .toList();
      expect(loaders, isNotEmpty, reason: '$motion');
      expect(
        loaders,
        everyElement(motion == ComponentsLoadingIconMotion.animated),
        reason: '$motion',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('colour sheets cover every ramp, group and button sheet', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildColorsPrimitivesCase,
      label: 'Ramp',
      optionLabels: ColorsPrimitiveRamp.values
          .map(colorsPrimitiveRampLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildColorsSemanticCase,
      label: 'Group',
      optionLabels: ColorsSemanticGroup.values
          .map(colorsSemanticGroupLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildColorsButtonCase,
      label: 'Sheet',
      optionLabels: ColorsButtonSheet.values
          .map(colorsButtonSheetLabel)
          .toList(),
    );
  });

  testWidgets('sync keep-awake lock covers mode, progress and screen height', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsSyncKeepAwakeLockCase,
      label: 'Mode',
      optionLabels: componentsSyncKeepAwakeModes
          .map(componentsSyncKeepAwakeModeLabel)
          .toList(),
    );
    // Only the syncing mode draws the ring, so the other two axes are swept
    // with Mode pinned there.
    final syncingMode = componentsSyncKeepAwakeModeLabel(
      SyncKeepAwakePrivacyLockMode.syncing,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsSyncKeepAwakeLockCase,
      label: 'Progress',
      optionLabels: ComponentsSyncProgress.values
          .map(componentsSyncProgressLabel)
          .toList(),
      otherKnobs: {'Mode': syncingMode},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsSyncKeepAwakeLockCase,
      label: 'Screen height',
      optionLabels: ComponentsScreenHeight.values
          .map(componentsScreenHeightLabel)
          .toList(),
      otherKnobs: {'Mode': syncingMode},
    );
  });

  testWidgets('sync keep-awake biometric knob swaps the unlock glyph', (
    tester,
  ) async {
    // Icon assets are SVGs, which do not rasterise in a widget test, so the
    // distinguishing assertion is the glyph widget rather than a fingerprint.
    for (final biometric in CoreBiometricCase.values) {
      await pumpUseCase(
        tester,
        buildComponentsSyncKeepAwakeLockCase,
        knobs: {'Biometric': componentsBiometricLabel(biometric)},
      );
      expect(tester.takeException(), isNull, reason: '$biometric');

      switch (biometric) {
        case CoreBiometricCase.faceId:
          expect(_appIconNamed(tester, 'face_id'), findsOneWidget);
        case CoreBiometricCase.touchId:
          expect(_appIconNamed(tester, 'touch_id'), findsOneWidget);
        case CoreBiometricCase.fingerprint:
          expect(find.byIcon(Icons.fingerprint), findsOneWidget);
        case CoreBiometricCase.passcodeOnly:
          expect(_appIconNamed(tester, 'unlock'), findsOneWidget);
      }
    }
    await disposeTree(tester);
  });

  testWidgets('transaction progress screen covers phase and actions', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsTransactionProgressCase,
      label: 'Phase',
      optionLabels: MobileTransactionProgressPhase.values
          .map(componentsTransactionPhaseLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsTransactionProgressCase,
      label: 'Actions',
      optionLabels: ComponentsTransactionActions.values
          .map(componentsTransactionActionsLabel)
          .toList(),
    );
  });

  testWidgets('transaction progress back-blocked knob drives PopScope', (
    tester,
  ) async {
    // `canPop` changes no pixels, so the knob is asserted on the widget.
    for (final blocked in [false, true]) {
      await pumpUseCase(
        tester,
        buildComponentsTransactionProgressCase,
        knobs: {'Back blocked': '$blocked'},
      );
      final popScope = tester.widget<PopScope<void>>(
        find.byType(PopScope<void>),
      );
      expect(popScope.canPop, !blocked, reason: 'blocked=$blocked');
    }
    await disposeTree(tester);
  });

  testWidgets('transaction progress badge covers phase and its toggles', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsTransactionProgressBadgeCase,
      label: 'Phase',
      optionLabels: componentsTransactionBadgePhases
          .map(componentsTransactionPhaseLabel)
          .toList(),
    );

    // Terminal motion and the in-progress tint are widget props, not first
    // frame pixels: the ripple starts at zero and the tint only applies to
    // the in-progress circle.
    for (final enabled in [true, false]) {
      await pumpUseCase(
        tester,
        buildComponentsTransactionProgressBadgeCase,
        knobs: {
          'Phase': componentsTransactionPhaseLabel(
            MobileTransactionProgressPhase.succeeded,
          ),
          'Terminal animation': '$enabled',
        },
      );
      final badge = tester.widget<MobileTransactionProgressBadge>(
        find.byType(MobileTransactionProgressBadge),
      );
      expect(badge.terminalAnimationEnabled, enabled);
    }

    for (final tinted in [false, true]) {
      await pumpUseCase(
        tester,
        buildComponentsTransactionProgressBadgeCase,
        knobs: {'Tinted in-progress colours': '$tinted'},
      );
      final badge = tester.widget<MobileTransactionProgressBadge>(
        find.byType(MobileTransactionProgressBadge),
      );
      expect(badge.inProgressCircleColor != null, tinted);
      expect(badge.inProgressIconColor != null, tinted);
    }
    await disposeTree(tester);
  });

  testWidgets('linux keyring gate covers every blocking phase', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsLinuxKeyringGateCase,
      label: 'Phase',
      optionLabels: CoreLinuxKeyringCase.values
          .map(componentsLinuxKeyringLabel)
          .toList(),
    );

    // Cancel needs a request id as well as the flag, and never shows on the
    // ambiguous-write phase.
    for (final canCancel in [false, true]) {
      await pumpUseCase(
        tester,
        buildComponentsLinuxKeyringGateCase,
        knobs: {'Cancel available': '$canCancel'},
      );
      expect(
        find.text('Cancel'),
        canCancel ? findsOneWidget : findsNothing,
        reason: 'canCancel=$canCancel',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('linux keyring startup covers each bootstrap outcome', (
    tester,
  ) async {
    for (final bootstrap in CoreLinuxStartupCase.values) {
      await pumpUseCase(
        tester,
        buildComponentsLinuxKeyringStartupCase,
        knobs: {'Bootstrap': componentsLinuxStartupLabel(bootstrap)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$bootstrap');

      switch (bootstrap) {
        case CoreLinuxStartupCase.pending:
          expect(find.text('Opening Vizor'), findsOneWidget);
        case CoreLinuxStartupCase.loaded:
          expect(find.text('Opening Vizor'), findsNothing);
          expect(find.text('Unable to open Vizor'), findsNothing);
        case CoreLinuxStartupCase.failed:
          expect(find.text('Unable to open Vizor'), findsOneWidget);
          expect(find.text('Quit'), findsOneWidget);
      }
    }
    await disposeTree(tester);
  });

  testWidgets('mobile top nav playground covers every variant axis', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMobileTopNavCase,
      label: 'Variant',
      optionLabels: MobileTopNavVariantCase.values
          .map(componentsTopNavVariantLabel)
          .toList(),
    );
    // 'Failed' is covered separately: it is the longest sync copy and the
    // test's fallback font overruns the 393px frame, so it cannot be asserted
    // with a clean-render fingerprint.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMobileTopNavCase,
      label: 'Sync',
      optionLabels: const [
        MobileTopNavSyncCase.hidden,
        MobileTopNavSyncCase.synced,
        MobileTopNavSyncCase.syncing,
      ].map(componentsTopNavSyncLabel).toList(),
      otherKnobs: {
        'Variant': componentsTopNavVariantLabel(
          MobileTopNavVariantCase.account,
        ),
      },
    );
    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {
        'Variant': componentsTopNavVariantLabel(
          MobileTopNavVariantCase.account,
        ),
        'Sync': componentsTopNavSyncLabel(MobileTopNavSyncCase.failed),
      },
    );
    expect(find.textContaining('Syncing failed'), findsOneWidget);
    _expectOnlyOverflow(tester);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMobileTopNavCase,
      label: 'Progress',
      optionLabels: ComponentsTopNavProgress.values
          .map(componentsTopNavProgressLabel)
          .toList(),
      otherKnobs: {
        'Variant': componentsTopNavVariantLabel(MobileTopNavVariantCase.steps),
      },
    );
  });

  testWidgets('mobile top nav playground toggles are wired', (tester) async {
    final backVariant = componentsTopNavVariantLabel(
      MobileTopNavVariantCase.back,
    );
    final accountVariant = componentsTopNavVariantLabel(
      MobileTopNavVariantCase.account,
    );

    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {'Variant': accountVariant, 'Balance label': 'true'},
    );
    expect(find.text('140.12 ZEC'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {'Variant': backVariant, 'Trailing lockup': 'true'},
    );
    expect(find.text('Powered by NEAR Intents'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {'Variant': backVariant, 'Back action': 'false'},
    );
    expect(find.bySemanticsLabel('Back'), findsNothing);

    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {
        'Variant': backVariant,
        'Back icon': componentsTopNavBackIconLabel(
          MobileTopNavBackIconCase.cross,
        ),
      },
    );
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    // Reduced motion stops the shimmer ticker; the first frame of an animated
    // shimmer is pixel-identical to the static label, so the running ticker is
    // the distinguishing signal.
    final syncing = componentsTopNavSyncLabel(MobileTopNavSyncCase.syncing);
    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {
        'Variant': accountVariant,
        'Sync': syncing,
        'Reduced motion': 'false',
      },
    );
    expect(tester.hasRunningAnimations, isTrue);

    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavCase,
      knobs: {
        'Variant': accountVariant,
        'Sync': syncing,
        'Reduced motion': 'true',
      },
    );
    expect(tester.hasRunningAnimations, isFalse);
    await disposeTree(tester);
  });

  testWidgets('mobile top nav account binds account and sync providers', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMobileTopNavAccountCase,
      label: 'Account',
      optionLabels: CoreAccountCase.values.map(componentsAccountLabel).toList(),
    );
    // As in the playground, the failed label overruns the 393px frame under
    // the test's fallback font, so it is covered by its copy instead.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMobileTopNavAccountCase,
      label: 'Sync',
      optionLabels: const [
        CoreSyncCase.synced,
        CoreSyncCase.syncing,
      ].map(componentsSyncLabel).toList(),
    );
    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavAccountCase,
      knobs: {'Sync': componentsSyncLabel(CoreSyncCase.failed)},
    );
    expect(find.textContaining('Syncing failed'), findsOneWidget);
    _expectOnlyOverflow(tester);

    await pumpUseCase(tester, buildComponentsMobileTopNavAccountCase);
    expect(find.text('Vizor is synced'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileTopNavAccountCase,
      knobs: {'Show sync status': 'false'},
    );
    expect(find.text('Vizor is synced'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('main sidebar covers account, route, sync and spacing', (
    tester,
  ) async {
    if (!_desktopLane) {
      // Gated surface: the mobile binary shows the run command, not a sidebar.
      await pumpUseCase(tester, buildComponentsMainSidebarCase);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
      expect(find.byType(AppMainSidebar), findsNothing);
      await disposeTree(tester);
      return;
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMainSidebarCase,
      label: 'Account',
      optionLabels: componentsSidebarAccounts
          .map(componentsAccountLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMainSidebarCase,
      label: 'Active route',
      optionLabels: CoreSidebarRoute.values
          .map(componentsSidebarRouteLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMainSidebarCase,
      label: 'Sync',
      optionLabels: CoreSyncCase.values.map(componentsSyncLabel).toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMainSidebarCase,
      label: 'Platform spacing',
      optionLabels: ComponentsSidebarPlatform.values
          .map(componentsSidebarPlatformLabel)
          .toList(),
    );
    // 'Needs input' is the hardware-signing prompt, so the migration axis is
    // swept on the Keystone account.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsMainSidebarCase,
      label: 'Migration section',
      optionLabels: CoreSidebarMigrationCase.values
          .map(componentsSidebarMigrationLabel)
          .toList(),
      otherKnobs: {'Account': componentsAccountLabel(CoreAccountCase.keystone)},
    );
  });

  testWidgets('main sidebar privacy and swap toggles are wired', (
    tester,
  ) async {
    if (!_desktopLane) return;

    await pumpUseCase(tester, buildComponentsMainSidebarCase);
    expect(find.byType(AppMainSidebar), findsOneWidget);
    expect(find.text('Swap'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMainSidebarCase,
      knobs: {'Swap enabled': 'false'},
    );
    expect(find.text('Swap'), findsNothing);
    expect(find.text('Pay'), findsNothing);

    await pumpUseCase(
      tester,
      buildComponentsMainSidebarCase,
      knobs: {'Privacy mode': 'true'},
    );
    expect(find.text('142.23 ZEC'), findsNothing);
    expect(find.text('****** ZEC'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('toast playground covers tone, icon and message', (tester) async {
    await pumpUseCase(tester, buildComponentsToastPlaygroundCase);
    expect(_toastWithTone(AppToastTone.neutral), findsOneWidget);
    expect(_appIconNamed(tester, AppIcons.checkCircle), findsOneWidget);
    expect(find.text('Address copied'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsToastPlaygroundCase,
      knobs: {
        'Tone': componentsToastToneLabel(AppToastTone.destructive),
        'Icon': componentsToastIconLabel(ComponentsToastIcon.warning),
        'Message': componentsToastMessageLabel(ComponentsToastMessage.wrapping),
      },
    );
    expect(_toastWithTone(AppToastTone.destructive), findsOneWidget);
    expect(_appIconNamed(tester, AppIcons.warning), findsOneWidget);
    expect(
      find.text('Transaction hash copied to your clipboard'),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildComponentsToastPlaygroundCase,
      knobs: {'Icon': componentsToastIconLabel(ComponentsToastIcon.copy)},
    );
    expect(_appIconNamed(tester, AppIcons.copy), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('toast host shows in the shell and through the overlay '
      'fallback', (tester) async {
    // The fixture fires `showAppToast` once per option from a post-frame
    // callback, so the toast is already on screen after the pump.
    await pumpUseCase(tester, buildComponentsToastHostCase);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(AppToastHost),
        matching: find.byType(AppToast),
      ),
      findsOneWidget,
    );
    expect(find.text('Address copied'), findsOneWidget);
    final desktopTop = tester.getTopLeft(find.byType(AppToast)).dy;

    await pumpUseCase(
      tester,
      buildComponentsToastHostCase,
      knobs: {
        'Inset': componentsToastInsetLabel(ComponentsToastInset.phoneNotch),
      },
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(AppToast)).dy,
      greaterThan(desktopTop),
    );

    await pumpUseCase(
      tester,
      buildComponentsToastHostCase,
      knobs: {'Tone': componentsToastToneLabel(AppToastTone.destructive)},
    );
    await tester.pump();
    expect(_toastWithTone(AppToastTone.destructive), findsOneWidget);
    expect(find.text("Couldn't copy the address"), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsToastHostCase,
      knobs: {
        'Host': componentsToastHostLabel(ComponentsToastHostMount.absent),
      },
    );
    await tester.pump();
    expect(find.byType(AppToastHost), findsNothing);
    expect(find.byType(AppToast), findsOneWidget);
    await disposeTree(tester);
    // Lets the fallback overlay entry finish removing itself.
    await tester.pump();
  });

  testWidgets('network fallback toast covers every notice and both widths', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsNetworkFallbackToastCase,
      label: 'Message',
      optionLabels: ComponentsNetworkNotice.values
          .map(componentsNetworkNoticeLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsNetworkFallbackToastCase,
      label: 'Width',
      optionLabels: ComponentsToastWidth.values
          .map(componentsToastWidthLabel)
          .toList(),
      otherKnobs: {
        'Message': componentsNetworkNoticeLabel(
          ComponentsNetworkNotice.updatesUnavailable,
        ),
      },
    );

    await pumpUseCase(tester, buildComponentsNetworkFallbackToastCase);
    expect(find.text(kWbEndpointFailoverNotice), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsNetworkFallbackToastCase,
      knobs: {
        'Message': componentsNetworkNoticeLabel(
          ComponentsNetworkNotice.torStartupFailed,
        ),
      },
    );
    expect(find.text(kTorStartupFailureNotice), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('network fallback host shows the notice and clears the sidebar', (
    tester,
  ) async {
    await pumpUseCase(tester, buildComponentsNetworkFallbackHostCase);
    // Past the host's 220ms slide-in.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(kWbEndpointFailoverNotice), findsOneWidget);
    final noShell = tester.getTopLeft(find.byType(NetworkFallbackToast));

    await pumpUseCase(
      tester,
      buildComponentsNetworkFallbackHostCase,
      knobs: {
        'Message': componentsNetworkNoticeLabel(
          ComponentsNetworkNotice.torStartupFailed,
        ),
        'Top inset': componentsToastInsetLabel(ComponentsToastInset.phoneNotch),
      },
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(kTorStartupFailureNotice), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(NetworkFallbackToast)).dy,
      greaterThan(noShell.dy),
    );

    // The sidebar option publishes a ContentOverlayInset, which the host reads
    // from the global notifier a frame later.
    await pumpUseCase(
      tester,
      buildComponentsNetworkFallbackHostCase,
      knobs: {
        'Shell': componentsToastShellLabel(ComponentsToastShell.desktopSidebar),
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getTopLeft(find.byType(NetworkFallbackToast)).dx,
      greaterThan(noShell.dx),
    );
    await disposeTree(tester);
    // Releases the published inset before the next test reads it.
    await tester.pump();
  });

  testWidgets('tx fee info sheet presents the real sheet with both copies', (
    tester,
  ) async {
    await pumpUseCase(tester, buildComponentsTxFeeInfoSheetCase);
    await tester.pumpAndSettle();
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.textContaining('ZIP 317'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsTxFeeInfoSheetCase,
      knobs: {'Copy': componentsTxFeeSheetCopyLabel(CoreTxFeeSheetCopy.custom)},
    );
    await tester.pumpAndSettle();
    expect(find.text(kCoreTxFeeCustomTitle), findsOneWidget);
    expect(find.text(kCoreTxFeeCustomDescription), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('unsupported sheet presents each message', (tester) async {
    await pumpUseCase(tester, buildComponentsUnsupportedSheetCase);
    await tester.pumpAndSettle();
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.text('This feature is still in progress.'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsUnsupportedSheetCase,
      knobs: {
        'Message': componentsUnsupportedSheetCopyLabel(
          CoreUnsupportedSheetCopy.keystoneConnect,
        ),
      },
    );
    await tester.pumpAndSettle();
    expect(find.text(kCoreUnsupportedKeystoneMessage), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsUnsupportedSheetCase,
      knobs: {
        'Message': componentsUnsupportedSheetCopyLabel(
          CoreUnsupportedSheetCopy.biometricUnlock,
        ),
      },
    );
    await tester.pumpAndSettle();
    expect(find.text(kCoreUnsupportedBiometricMessage), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('tooltip playground covers content, placement and trigger', (
    tester,
  ) async {
    await pumpUseCase(tester, buildComponentsTooltipCase);
    await tester.pumpAndSettle();
    final anchorTop = tester.getTopLeft(find.text(kCoreTooltipAnchorLabel)).dy;
    expect(_tooltipBubble(kCoreTooltipPlainMessage), findsOneWidget);
    expect(
      tester.getTopLeft(_tooltipBubble(kCoreTooltipPlainMessage)).dy,
      lessThan(anchorTop),
    );

    await pumpUseCase(
      tester,
      buildComponentsTooltipCase,
      knobs: {
        'Placement': componentsTooltipPlacementLabel(
          ComponentsTooltipPlacement.below,
        ),
      },
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_tooltipBubble(kCoreTooltipPlainMessage)).dy,
      greaterThan(anchorTop),
    );

    await pumpUseCase(
      tester,
      buildComponentsTooltipCase,
      knobs: {
        'Content': componentsTooltipContentLabel(ComponentsTooltipContent.rich),
      },
    );
    await tester.pumpAndSettle();
    expect(_tooltipBubble(kCoreTooltipRichMessage), findsOneWidget);
    expect(_tooltipBubble(kCoreTooltipPlainMessage), findsNothing);

    // The tap option is not forced visible; the bubble appears on tap.
    await pumpUseCase(
      tester,
      buildComponentsTooltipCase,
      knobs: {'Trigger': componentsTooltipTriggerLabel(CoreTooltipTrigger.tap)},
    );
    await tester.pumpAndSettle();
    expect(_tooltipBubble(kCoreTooltipPlainMessage), findsNothing);
    await tester.tap(find.text(kCoreTooltipAnchorLabel));
    await tester.pumpAndSettle();
    expect(_tooltipBubble(kCoreTooltipPlainMessage), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('context menu anchor case self-corrects at every pane edge', (
    tester,
  ) async {
    // The menu measures itself in a post-frame callback and translates on the
    // frame after, so each option is read from its applied correction.
    Future<Offset> correction(ContextMenuAnchor anchor) async {
      await pumpUseCase(
        tester,
        buildComponentsContextMenuAnchorCase,
        knobs: {'Anchor': componentsContextMenuAnchorLabel(anchor)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$anchor');
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(AppContextMenu),
              matching: find.byType(Transform),
            )
            .first,
      );
      final storage = transform.transform.storage;
      return Offset(storage[12], storage[13]);
    }

    expect(await correction(ContextMenuAnchor.topLeft), Offset.zero);

    final topRight = await correction(ContextMenuAnchor.topRight);
    expect(topRight.dx, lessThan(0));
    expect(topRight.dy, 0);

    final bottomLeft = await correction(ContextMenuAnchor.bottomLeft);
    expect(bottomLeft.dx, 0);
    expect(bottomLeft.dy, lessThan(0));

    final bottomRight = await correction(ContextMenuAnchor.bottomRight);
    expect(bottomRight.dx, lessThan(0));
    expect(bottomRight.dy, lessThan(0));

    // Too tall to flip: it clamps to the bottom edge, a much smaller lift than
    // the full flip the short menu gets.
    final clamped = await correction(ContextMenuAnchor.tallClamped);
    expect(clamped.dy, lessThan(0));
    expect(clamped.dy, greaterThan(bottomLeft.dy));
    await disposeTree(tester);
  });

  testWidgets('context menu anchor width knob resizes the menu', (
    tester,
  ) async {
    for (final width in ComponentsContextMenuWidth.values) {
      await pumpUseCase(
        tester,
        buildComponentsContextMenuAnchorCase,
        knobs: {'Width': componentsContextMenuWidthLabel(width)},
      );
      expect(
        tester.widget<AppContextMenu>(find.byType(AppContextMenu)).width,
        width == ComponentsContextMenuWidth.narrow
            ? kContextMenuNarrowWidth
            : 160,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('modal card covers highlight, width, body and bottom padding', (
    tester,
  ) async {
    const highlightKey = ValueKey('app_modal_inner_highlight');
    Size cardSize() => tester.getSize(find.byType(AppModalCard));

    await pumpUseCase(tester, buildComponentsModalCardCase);
    expect(find.byKey(highlightKey), findsNothing);
    expect(cardSize().width, kAppModalCardWidth);
    final defaultHeight = cardSize().height;

    await pumpUseCase(
      tester,
      buildComponentsModalCardCase,
      knobs: {'Highlight': 'true'},
    );
    expect(find.byKey(highlightKey), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsModalCardCase,
      knobs: {
        'Width': componentsModalCardWidthLabel(ComponentsModalCardWidth.wide),
      },
    );
    expect(cardSize().width, kCoreModalCardWideWidth);

    await pumpUseCase(
      tester,
      buildComponentsModalCardCase,
      knobs: {
        'Body': componentsModalCardBodyLabel(CoreModalCardBody.scrolling),
      },
    );
    expect(find.text('${kCoreModalCardRowPrefix}1'), findsOneWidget);
    expect(cardSize().height, greaterThan(defaultHeight));

    await pumpUseCase(
      tester,
      buildComponentsModalCardCase,
      knobs: {
        'Bottom padding': componentsModalCardPaddingLabel(
          ComponentsModalCardPadding.flush,
        ),
      },
    );
    expect(cardSize().height, defaultHeight - AppSpacing.md);
    await disposeTree(tester);
  });

  testWidgets('modal actions covers variant, disabled states and the icon', (
    tester,
  ) async {
    AppButton buttonAt(String key) =>
        tester.widget<AppButton>(find.byKey(ValueKey(key)));

    await pumpUseCase(tester, buildComponentsModalActionsCase);
    expect(buttonAt('modal_action_button').variant, AppButtonVariant.primary);
    expect(buttonAt('modal_action_button').onPressed, isNotNull);
    expect(buttonAt('modal_cancel_button').onPressed, isNotNull);
    expect(_appIconNamed(tester, AppIcons.trash), findsNothing);

    await pumpUseCase(
      tester,
      buildComponentsModalActionsCase,
      knobs: {
        'Action variant': componentsButtonVariantLabel(
          AppButtonVariant.destructive,
        ),
      },
    );
    expect(
      buttonAt('modal_action_button').variant,
      AppButtonVariant.destructive,
    );

    await pumpUseCase(
      tester,
      buildComponentsModalActionsCase,
      knobs: {'Action enabled': 'false'},
    );
    expect(buttonAt('modal_action_button').onPressed, isNull);

    await pumpUseCase(
      tester,
      buildComponentsModalActionsCase,
      knobs: {'Cancel enabled': 'false'},
    );
    expect(buttonAt('modal_cancel_button').onPressed, isNull);

    await pumpUseCase(
      tester,
      buildComponentsModalActionsCase,
      knobs: {'Action leading icon': 'true'},
    );
    expect(_appIconNamed(tester, AppIcons.trash), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('pane overlay covers alignment, scrim and corner radius', (
    tester,
  ) async {
    AppPaneModalOverlay overlay() =>
        tester.widget<AppPaneModalOverlay>(find.byType(AppPaneModalOverlay));

    await pumpUseCase(tester, buildComponentsPaneModalOverlayCase);
    final centerTop = tester.getTopLeft(find.byType(AppModalCard)).dy;
    expect(overlay().scrimColor, isNull);
    expect(overlay().borderRadius, AppPaneModalOverlay.defaultBorderRadius);

    await pumpUseCase(
      tester,
      buildComponentsPaneModalOverlayCase,
      knobs: {
        'Alignment': componentsPaneModalAlignmentLabel(
          CorePaneModalAlignment.top,
        ),
      },
    );
    expect(
      tester.getTopLeft(find.byType(AppModalCard)).dy,
      lessThan(centerTop),
    );

    await pumpUseCase(
      tester,
      buildComponentsPaneModalOverlayCase,
      knobs: {
        'Alignment': componentsPaneModalAlignmentLabel(
          CorePaneModalAlignment.bottom,
        ),
      },
    );
    expect(
      tester.getTopLeft(find.byType(AppModalCard)).dy,
      greaterThan(centerTop),
    );

    await pumpUseCase(
      tester,
      buildComponentsPaneModalOverlayCase,
      knobs: {'Custom scrim': 'true'},
    );
    expect(overlay().scrimColor, isNotNull);

    await pumpUseCase(
      tester,
      buildComponentsPaneModalOverlayCase,
      knobs: {'Large corner radius': 'true'},
    );
    expect(
      overlay().borderRadius,
      const BorderRadius.all(Radius.circular(AppRadii.xLarge)),
    );
    await disposeTree(tester);
  });

  testWidgets('profile picture picker reaches updating and the inline error', (
    tester,
  ) async {
    Future<void> pickAndUpdate() async {
      // The Update action only enables once the selection differs from the
      // current picture, so the flow is two taps.
      await tester.tap(
        find.byKey(const ValueKey('profile_picture_option_pfp-08')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('modal_action_button')));
      await tester.pump();
    }

    Future<void> pumpPicker(CoreProfilePickerOutcome outcome) async {
      await pumpUseCase(
        tester,
        buildComponentsProfilePicturePickerCase,
        knobs: {'Update outcome': componentsProfilePickerOutcomeLabel(outcome)},
      );
    }

    await pumpPicker(CoreProfilePickerOutcome.succeeds);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('modal_action_button')))
          .onPressed,
      isNull,
    );
    await pickAndUpdate();
    await tester.pumpAndSettle();
    expect(find.text('Updating...'), findsNothing);
    expect(find.text(kCoreProfilePickerError), findsNothing);

    await pumpPicker(CoreProfilePickerOutcome.inFlight);
    await pickAndUpdate();
    expect(find.text('Updating...'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('modal_cancel_button')))
          .onPressed,
      isNull,
    );

    await pumpPicker(CoreProfilePickerOutcome.fails);
    await pickAndUpdate();
    await tester.pumpAndSettle();
    expect(find.text(kCoreProfilePickerError), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('profile picture picker covers current picture and option size', (
    tester,
  ) async {
    AppProfilePicturePickerModal picker() =>
        tester.widget<AppProfilePicturePickerModal>(
          find.byType(AppProfilePicturePickerModal),
        );

    await pumpUseCase(tester, buildComponentsProfilePicturePickerCase);
    expect(picker().currentProfilePictureId, 'pfp-01');
    expect(picker().optionSize, AppProfilePictureSize.navLarge);

    await pumpUseCase(
      tester,
      buildComponentsProfilePicturePickerCase,
      knobs: {
        'Current picture': componentsProfilePictureLabel(
          ComponentsProfilePicture.alternate,
        ),
      },
    );
    expect(picker().currentProfilePictureId, kCoreProfilePickerAlternateId);

    await pumpUseCase(
      tester,
      buildComponentsProfilePicturePickerCase,
      knobs: {
        'Option size': componentsProfilePickerSizeLabel(
          AppProfilePictureSize.large,
        ),
      },
    );
    expect(picker().optionSize, AppProfilePictureSize.large);
    await disposeTree(tester);
  });

  testWidgets('mobile modal scaffold covers title, close, leading and body', (
    tester,
  ) async {
    await pumpUseCase(tester, buildComponentsMobileModalScaffoldCase);
    expect(find.text(kCoreMobileModalTitle), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.text(kCoreMobileModalBodyText), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalScaffoldCase,
      knobs: {
        'Title': componentsMobileModalTitleLabel(CoreMobileModalTitle.hidden),
      },
    );
    expect(find.text(kCoreMobileModalTitle), findsNothing);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalScaffoldCase,
      knobs: {
        'Title': componentsMobileModalTitleLabel(
          CoreMobileModalTitle.longWrapping,
        ),
      },
    );
    expect(
      tester.widget<Text>(find.text(kCoreMobileModalLongTitle)).maxLines,
      2,
    );

    await pumpUseCase(
      tester,
      buildComponentsMobileModalScaffoldCase,
      knobs: {'Close button': 'false'},
    );
    expect(find.bySemanticsLabel('Close'), findsNothing);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalScaffoldCase,
      knobs: {
        'Leading': componentsMobileModalLeadingLabel(
          CoreMobileModalLeading.icon,
        ),
      },
    );
    expect(_appIconNamed(tester, AppIcons.shieldKeyhole), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalScaffoldCase,
      knobs: {
        'Leading': componentsMobileModalLeadingLabel(
          CoreMobileModalLeading.avatar,
        ),
      },
    );
    expect(find.byType(AppProfilePicture), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalScaffoldCase,
      knobs: {'Body': componentsMobileModalBodyLabel(CoreMobileModalBody.long)},
    );
    // Constrained: the list scrolls inside the card instead of growing it, so
    // its tail is laid out past the card's own bottom edge.
    expect(
      tester
          .widget<MobileModalScaffold>(find.byType(MobileModalScaffold))
          .constrainBody,
      isTrue,
    );
    expect(find.text(kCoreMobileModalFirstRow), findsOneWidget);
    expect(
      tester.getRect(find.text(kCoreMobileModalLastRow)).bottom,
      greaterThan(tester.getRect(find.byType(MobileModalCard)).bottom),
    );
    expect(find.text('Copy address'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile modal card covers keyboard, platform and background', (
    tester,
  ) async {
    // The card owns the gap between its body and the bottom of the phone.
    double bottomGap() {
      final card = tester.getRect(find.byType(MobileModalCard));
      final body = tester.getRect(find.byKey(kCoreMobileModalBodyKey));
      return card.bottom - body.bottom;
    }

    double sideMargin() {
      final card = tester.getRect(find.byType(MobileModalCard));
      final body = tester.getRect(find.byKey(kCoreMobileModalBodyKey));
      return body.left - card.left;
    }

    await pumpUseCase(tester, buildComponentsMobileModalCardCase);
    expect(find.byType(MobileModalOverlay), findsOneWidget);
    expect(bottomGap(), AppSpacing.base);
    expect(sideMargin(), AppSpacing.sm);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalCardCase,
      knobs: {
        'Platform': componentsMobilePlatformLabel(
          ComponentsMobilePlatform.android,
        ),
      },
    );
    // Android stacks its navigation-bar inset on top of the visual gap.
    expect(bottomGap(), AppSpacing.base + 34);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalCardCase,
      knobs: {'Keyboard': componentsKeyboardLabel(ComponentsKeyboard.open)},
    );
    expect(bottomGap(), 300 + AppSpacing.sm);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalCardCase,
      knobs: {'Transparent background': 'true'},
    );
    expect(
      tester
          .widget<MobileModalCard>(find.byType(MobileModalCard))
          .transparentBackground,
      isTrue,
    );
    expect(sideMargin(), 0);

    await pumpUseCase(tester, buildComponentsMobileModalCardCase);
    expect(find.byType(AppMobileTabBar), findsOneWidget);

    await pumpUseCase(
      tester,
      buildComponentsMobileModalCardCase,
      knobs: {
        'Background': componentsMobileModalBackgroundLabel(
          CoreMobileModalBackground.blank,
        ),
      },
    );
    expect(find.byType(AppMobileTabBar), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('decorative divider covers both widths', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsDecorativeDividerCase,
      label: 'Width',
      optionLabels: CoreDividerWidth.values
          .map(componentsDividerWidthLabel)
          .toList(),
    );
  });

  testWidgets('pane scroll scaffold pins its toolbar over the slivers', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildComponentsPaneScrollScaffoldCase,
      label: 'Content',
      optionLabels: CorePaneScaffoldContent.values
          .map(componentsPaneScaffoldContentLabel)
          .toList(),
    );

    // The first row starts below the 48px toolbar band, which is what the
    // scaffold's content padding exists to guarantee.
    await pumpUseCase(tester, buildComponentsPaneScrollScaffoldCase);
    expect(find.byType(AppPaneSliverScrollScaffold), findsOneWidget);
    final scaffoldTop = tester
        .getRect(find.byType(AppPaneSliverScrollScaffold))
        .top;
    final rowTop = tester.getRect(find.byKey(kCorePaneScaffoldFirstRowKey)).top;
    expect(
      rowTop - scaffoldTop,
      greaterThanOrEqualTo(AppPaneScrollScaffold.toolbarHeight),
    );
    await disposeTree(tester);
  });

  testWidgets('platform override survives a direct swap between fixtures', (
    tester,
  ) async {
    // Widgetbook replaces a use case without an empty frame between, so the
    // outgoing fixture's dispose runs after the incoming one has claimed the
    // global — it must not restore what it captured.
    Future<void> pumpCard(Key key, TargetPlatform platform) {
      return tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Material(
              type: MaterialType.transparency,
              child: KeyedSubtree(
                key: key,
                child: Builder(
                  builder: (context) => mobileModalCardFixture(
                    context,
                    transparentBackground: false,
                    keyboardOpen: false,
                    platform: platform,
                    background: CoreMobileModalBackground.blank,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpCard(const ValueKey('a'), TargetPlatform.android);
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.android);

    await pumpCard(const ValueKey('b'), TargetPlatform.iOS);
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.iOS);

    await disposeTree(tester);
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}

/// Asserts the pending exception is the known overflow, if any, so an
/// unrelated layout error is not swallowed with it.
void _expectOnlyOverflow(WidgetTester tester) {
  expect(
    tester.takeException(),
    anyOf(
      isNull,
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('overflowed'),
      ),
    ),
  );
}

/// Finds an [AppToast] rendered with [tone].
Finder _toastWithTone(AppToastTone tone) {
  return find.byWidgetPredicate(
    (widget) => widget is AppToast && widget.tone == tone,
    description: 'AppToast(${tone.name})',
  );
}

/// Finds the tooltip bubble by its text; `Tooltip` renders both plain and rich
/// messages as a `RichText`, and no `Text` in the fixture carries this copy.
Finder _tooltipBubble(String message) {
  return find.text(message, findRichText: true);
}

/// Finds an [AppIcon] by the asset name it renders.
Finder _appIconNamed(WidgetTester tester, String name) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == name,
    description: 'AppIcon($name)',
  );
}
