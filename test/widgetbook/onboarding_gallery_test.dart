import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/security/password_policy.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_chrome.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/widgetbook/gallery/onboarding_gallery.dart';
import 'package:zcash_wallet/widgetbook/onboarding_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_fake_scanner_platform.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Runs in both lanes. Assertions are render fingerprints or copy, never token
// metrics — but four desktop cards measurably overflow under mobile tokens and
// are `WbLaneOnly`, so those assertions are guarded on `wbCompiledLaneLayout`.
// The surfaces that exist in both form factors are one use case with a
// `Layout` knob, so their sweeps pass the layout through `otherKnobs`.
void main() {
  // Real fonts: the fixed-height onboarding auth card (lost password) fits
  // Geist metrics but overflows the fallback test font.
  setUpAll(_loadAppFonts);
  // The desktop Keystone scan step mounts the real scanner card, which reads
  // the camera platform and the Rust UR decoder.
  setUpAll(WbFakeUrScanRustApi.install);
  tearDown(WbFakeMobileScannerPlatform.reset);

  // The seed and Keystone screens mount `SensitivePrivacyOverlay` and the
  // wallet-link scanner disposes a (never started) scanner controller; both
  // talk to native channels that the test host has no implementation for.
  setUp(() {
    const privacyChannels = [
      MethodChannel('com.zcash.wallet/privacy_exposure'),
      MethodChannel('com.zcash.wallet/privacy_shield'),
      MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in privacyChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
  });

  testWidgets('every onboarding gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = [
      ...widgetbookUseCases(onboardingGalleryNodes),
      ...widgetbookUseCases(keystoneGalleryNodes),
    ];
    expect(useCases.length, 43);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('every folded surface builds in both layouts', (tester) async {
    for (final surface in _foldedLayoutCases.entries) {
      for (final layout in WbLayout.values) {
        await pumpUseCase(
          tester,
          surface.value,
          knobs: {'Layout': wbLayoutLabel(layout)},
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${surface.key} / ${wbLayoutLabel(layout)}',
        );
      }
    }
    await disposeTree(tester);
  });

  testWidgets('the Layout knob swaps the screen on every folded surface', (
    tester,
  ) async {
    for (final surface in _foldedLayoutCases.entries) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        surface.value,
        label: 'Layout',
        optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      );
    }
  });

  testWidgets('the folded surfaces register their axes per layout', (
    tester,
  ) async {
    Future<Iterable<String>> knobsOf(
      WidgetBuilder builder,
      WbLayout layout,
    ) async {
      final state = await pumpUseCase(
        tester,
        builder,
        knobs: {'Layout': wbLayoutLabel(layout)},
      );
      return state.knobs.keys.toList();
    }

    // Desktop welcome opens the network-settings panel; mobile only varies on
    // the entry point it was pushed from.
    expect(
      await knobsOf(buildOnboardingWelcomeGalleryCase, WbLayout.desktop),
      containsAll(<String>['Layout', 'Panel', 'Tor']),
    );
    expect(
      await knobsOf(buildOnboardingWelcomeGalleryCase, WbLayout.mobile),
      containsAll(<String>['Layout', 'Entry']),
    );
    expect(
      await knobsOf(buildOnboardingWelcomeGalleryCase, WbLayout.mobile),
      isNot(contains('Panel')),
    );

    // Mobile unlock is a passcode screen with three axes; the desktop screen
    // has none a preview can drive.
    expect(
      await knobsOf(buildOnboardingUnlockGalleryCase, WbLayout.mobile),
      containsAll(<String>['Layout', 'Biometric', 'Overlay', 'Attempt']),
    );
    expect(
      await knobsOf(buildOnboardingUnlockGalleryCase, WbLayout.desktop),
      isNot(contains('Biometric')),
    );

    // The mobile passphrase screen has one fixture per state, so it carries no
    // separate privacy axis. Its desktop knobs live under `WbLaneOnly`.
    expect(
      await knobsOf(
        buildOnboardingSecretPassphraseGalleryCase,
        WbLayout.mobile,
      ),
      allOf(
        containsAll(<String>['Layout', 'State']),
        isNot(contains('Privacy')),
      ),
    );
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      expect(
        await knobsOf(
          buildOnboardingSecretPassphraseGalleryCase,
          WbLayout.desktop,
        ),
        containsAll(<String>['Layout', 'State', 'Privacy']),
      );
    }

    // The remaining folds put every state axis on the desktop half: the mobile
    // steps have a single fixture each.
    for (final surface in <String, (WidgetBuilder, List<String>)>{
      'Customise account': (
        buildOnboardingCustomiseAccountGalleryCase,
        ['Flow'],
      ),
      'Keystone scan': (buildOnboardingKeystoneScanGalleryCase, ['Scan']),
      'Keystone select account': (
        buildOnboardingKeystoneSelectAccountGalleryCase,
        ['Accounts', 'Selection'],
      ),
      'Keystone birthday': (
        buildOnboardingKeystoneBirthdayGalleryCase,
        ['Metadata'],
      ),
    }.entries) {
      final (builder, desktopOnly) = surface.value;
      expect(
        await knobsOf(builder, WbLayout.desktop),
        containsAll(<String>['Layout', ...desktopOnly]),
        reason: surface.key,
      );
      for (final knob in desktopOnly) {
        expect(
          await knobsOf(builder, WbLayout.mobile),
          isNot(contains(knob)),
          reason: '${surface.key} / $knob',
        );
      }
    }

    // Set password: the flow axis is desktop-only and sits under `WbLaneOnly`;
    // the mobile passcode step has a single fixture.
    expect(
      await knobsOf(buildOnboardingSetPasswordGalleryCase, WbLayout.mobile),
      isNot(contains('Flow')),
    );
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      expect(
        await knobsOf(buildOnboardingSetPasswordGalleryCase, WbLayout.desktop),
        containsAll(<String>['Layout', 'Flow']),
      );
    }

    // Keystone signing: the modal's action and instruction axes are desktop
    // only; both lanes carry a phase, each over its own enum.
    expect(
      await knobsOf(
        buildOnboardingKeystoneSigningGalleryCase,
        WbLayout.desktop,
      ),
      containsAll(<String>['Layout', 'Phase', 'Actions', 'Instruction']),
    );
    final signingMobile = await knobsOf(
      buildOnboardingKeystoneSigningGalleryCase,
      WbLayout.mobile,
    );
    expect(signingMobile, containsAll(<String>['Layout', 'Phase']));
    expect(signingMobile, isNot(contains('Actions')));
    expect(signingMobile, isNot(contains('Instruction')));

    // The three explainers vary on nothing but the form factor.
    for (final builder in [
      buildOnboardingIntroZcashGalleryCase,
      buildOnboardingAddressTypesGalleryCase,
      buildOnboardingThingsToKnowGalleryCase,
      buildOnboardingKeystoneIntroGalleryCase,
    ]) {
      for (final layout in WbLayout.values) {
        expect(await knobsOf(builder, layout), <String>['Layout']);
      }
    }
    await disposeTree(tester);
  });

  testWidgets('desktop welcome covers the panel and Tor axes', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWelcomeGalleryCase,
      label: 'Tor',
      optionLabels: OnboardingWelcomeTor.values
          .map(onboardingWelcomeTorLabel)
          .toList(),
      otherKnobs: {
        'Layout': _desktop,
        'Panel': onboardingWelcomePanelLabel(
          OnboardingWelcomePanel.networkSettings,
        ),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWelcomeGalleryCase,
      label: 'Panel',
      optionLabels: OnboardingWelcomePanel.values
          .map(onboardingWelcomePanelLabel)
          .toList(),
      otherKnobs: {
        'Layout': _desktop,
        'Tor': onboardingWelcomeTorLabel(OnboardingWelcomeTor.off),
      },
    );
  });

  testWidgets('mobile welcome covers both entry points', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWelcomeGalleryCase,
      label: 'Entry',
      optionLabels: OnboardingMobileWelcomeEntry.values
          .map(onboardingMobileWelcomeEntryLabel)
          .toList(),
      otherKnobs: {'Layout': _mobile},
    );
  });

  testWidgets('mobile unlock covers the biometric and overlay axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingUnlockGalleryCase,
      label: 'Biometric',
      optionLabels: OnboardingMobileUnlockBiometric.values
          .map(onboardingMobileUnlockBiometricLabel)
          .toList(),
      otherKnobs: {
        'Layout': _mobile,
        'Overlay': onboardingMobileUnlockOverlayLabel(
          OnboardingMobileUnlockOverlay.none,
        ),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingUnlockGalleryCase,
      label: 'Overlay',
      optionLabels: OnboardingMobileUnlockOverlay.values
          .map(onboardingMobileUnlockOverlayLabel)
          .toList(),
      otherKnobs: {
        'Layout': _mobile,
        'Biometric': onboardingMobileUnlockBiometricLabel(
          OnboardingMobileUnlockBiometric.none,
        ),
      },
    );
  });

  testWidgets('the desktop-only cards preview only the desktop lane', (
    tester,
  ) async {
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildOnboardingLostPasswordGalleryCase,
        label: 'Countdown',
        optionLabels: OnboardingLostPasswordCountdown.values
            .map(onboardingLostPasswordCountdownLabel)
            .toList(),
        otherKnobs: {
          'Gift card claims': onboardingLostPasswordClaimsLabel(
            OnboardingLostPasswordClaims.none,
          ),
        },
      );
      await pumpUseCase(
        tester,
        buildOnboardingUnlockGalleryCase,
        knobs: {'Layout': _desktop},
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsNothing);
      await disposeTree(tester);
      return;
    }

    // Off lane: every one of these measurably overflows under mobile tokens,
    // so each shows the lane notice instead. The folded surfaces need the
    // layout selected, because the knob defaults to this lane's own.
    for (final builder in [
      buildOnboardingUnlockGalleryCase,
      buildOnboardingUnlockContentGalleryCase,
      buildOnboardingLostPasswordGalleryCase,
      buildOnboardingIntroZcashGalleryCase,
      buildOnboardingSecretPassphraseGalleryCase,
      buildOnboardingSetPasswordGalleryCase,
    ]) {
      await pumpUseCase(tester, builder, knobs: {'Layout': _desktop});
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    }
    await disposeTree(tester);
  });

  testWidgets('the lost-password card warns about a Gift Card being received', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await pumpUseCase(
      tester,
      buildOnboardingLostPasswordGalleryCase,
      knobs: {
        'Gift card claims': onboardingLostPasswordClaimsLabel(
          OnboardingLostPasswordClaims.oneInFlight,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text(kWalletResetInFlightGiftCardWarningMessage), findsOne);

    await pumpUseCase(
      tester,
      buildOnboardingLostPasswordGalleryCase,
      knobs: {
        'Gift card claims': onboardingLostPasswordClaimsLabel(
          OnboardingLostPasswordClaims.none,
        ),
      },
    );
    expect(find.text(kWalletResetInFlightGiftCardWarningMessage), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('the unlock card body covers each of its four axes', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingUnlockContentGalleryCase,
      label: 'Message',
      optionLabels: OnboardingUnlockMessage.values
          .map(onboardingUnlockMessageLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingUnlockContentGalleryCase,
      label: 'Forgot password',
      optionLabels: OnboardingUnlockForgotPassword.values
          .map(onboardingUnlockForgotPasswordLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingUnlockContentGalleryCase,
      label: 'Description',
      optionLabels: OnboardingUnlockDescription.values
          .map(onboardingUnlockDescriptionLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingUnlockContentGalleryCase,
      label: 'Password entered',
      optionLabels: const ['false', 'true'],
    );

    // The password-policy option is lane-dependent copy, so assert the token.
    await pumpUseCase(
      tester,
      buildOnboardingUnlockContentGalleryCase,
      knobs: {
        'Message': onboardingUnlockMessageLabel(
          OnboardingUnlockMessage.passwordTooShort,
        ),
      },
    );
    expect(find.text(kWalletPasswordMinLengthMessage), findsOne);
    await disposeTree(tester);
  });

  testWidgets('the create-flow explainers render their own screen per layout', (
    tester,
  ) async {
    for (final expected in {
      // The desktop intro is lane-gated (12px overflow under mobile tokens);
      // its two siblings measure clean and stay previewable in either lane.
      if (wbCompiledLaneLayout == WbLayout.desktop)
        'The Shielded World': buildOnboardingIntroZcashGalleryCase,
      'Zcash Address Types': buildOnboardingAddressTypesGalleryCase,
      'Time to sync': buildOnboardingThingsToKnowGalleryCase,
    }.entries) {
      await pumpUseCase(tester, expected.value, knobs: {'Layout': _desktop});
      expect(tester.takeException(), isNull, reason: expected.key);
      expect(find.text(expected.key), findsOne, reason: expected.key);
    }

    for (final expected in {
      'Tell me how Zcash works': buildOnboardingIntroZcashGalleryCase,
      'Shielded Address': buildOnboardingAddressTypesGalleryCase,
      'Things to know': buildOnboardingThingsToKnowGalleryCase,
    }.entries) {
      await pumpUseCase(tester, expected.value, knobs: {'Layout': _mobile});
      expect(tester.takeException(), isNull, reason: expected.key);
      expect(find.text(expected.key), findsWidgets, reason: expected.key);
    }
    await disposeTree(tester);
  });

  testWidgets('desktop secret passphrase covers the reveal and privacy axes', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSecretPassphraseGalleryCase,
      label: 'State',
      optionLabels: OnboardingSecretPassphraseReveal.values
          .map(onboardingSecretPassphraseRevealLabel)
          .toList(),
      otherKnobs: {
        'Layout': _desktop,
        'Privacy': onboardingSecretPassphrasePrivacyLabel(
          OnboardingSecretPassphrasePrivacy.visible,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSecretPassphraseGalleryCase,
      label: 'Privacy',
      optionLabels: OnboardingSecretPassphrasePrivacy.values
          .map(onboardingSecretPassphrasePrivacyLabel)
          .toList(),
      otherKnobs: {
        'Layout': _desktop,
        'State': onboardingSecretPassphraseRevealLabel(
          OnboardingSecretPassphraseReveal.revealed,
        ),
      },
    );

    // The hidden state is the one that must never reach `generateMnemonic`.
    await pumpUseCase(
      tester,
      buildOnboardingSecretPassphraseGalleryCase,
      knobs: {
        'Layout': _desktop,
        'State': onboardingSecretPassphraseRevealLabel(
          OnboardingSecretPassphraseReveal.hidden,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Reveal the phrase'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('set password covers all four setup flows', (tester) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSetPasswordGalleryCase,
      label: 'Flow',
      optionLabels: SetPasswordFlow.values
          .map(onboardingSetPasswordFlowLabel)
          .toList(),
      otherKnobs: {'Layout': _desktop},
    );

    // Wallet Link is the only flow whose submit button finishes the setup.
    await pumpUseCase(
      tester,
      buildOnboardingSetPasswordGalleryCase,
      knobs: {
        'Layout': _desktop,
        'Flow': onboardingSetPasswordFlowLabel(
          SetPasswordFlow.importWalletLink,
        ),
      },
    );
    expect(find.text('Set password & finish'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('storage unavailable covers every bootstrap failure', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingStorageUnavailableGalleryCase,
      label: 'Failure',
      optionLabels: AppBootstrapFailureKind.values
          .map(onboardingStorageFailureLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildOnboardingStorageUnavailableGalleryCase,
      knobs: {
        'Failure': onboardingStorageFailureLabel(
          AppBootstrapFailureKind.walletDbMigrationFailed,
        ),
      },
    );
    expect(find.text('Unable to update wallet database'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('desktop single-axis knobs cover every option distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingImportPassphraseGalleryCase,
      label: 'State',
      optionLabels: OnboardingImportPassphraseState.values
          .map(onboardingImportPassphraseStateLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingCustomiseAccountGalleryCase,
      label: 'Flow',
      optionLabels: OnboardingCustomiseAccountFlow.values
          .map(onboardingCustomiseAccountFlowLabel)
          .toList(),
      otherKnobs: {'Layout': _desktop},
    );
  });

  testWidgets('mobile single-axis knobs cover every option distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSecretPassphraseGalleryCase,
      label: 'State',
      optionLabels: OnboardingMobilePassphraseState.values
          .map(onboardingMobilePassphraseStateLabel)
          .toList(),
      otherKnobs: {'Layout': _mobile},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingMobileBiometricsGalleryCase,
      label: 'Method',
      optionLabels: OnboardingMobileBiometricsMethod.values
          .map(onboardingMobileBiometricsMethodLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingMobileImportPasteGalleryCase,
      label: 'State',
      optionLabels: OnboardingMobileImportPasteState.values
          .map(onboardingMobileImportPasteStateLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingMobileImportManualGalleryCase,
      label: 'Entry',
      optionLabels: OnboardingMobileImportManualEntry.values
          .map(onboardingMobileImportManualEntryLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingMobileImportReviewGalleryCase,
      label: 'Words',
      optionLabels: OnboardingMobileImportWords.values
          .map(onboardingMobileImportWordsLabel)
          .toList(),
    );
  });

  testWidgets('Keystone knobs cover every option distinctly', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneScanGalleryCase,
      label: 'Camera',
      optionLabels: OnboardingKeystoneCamera.values
          .map(onboardingKeystoneCameraLabel)
          .toList(),
      // The desktop half is the real scanner card; its own camera and scan
      // axes are swept in `scanner_gallery_test.dart`.
      otherKnobs: {'Layout': _mobile},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystonePcztQrGalleryCase,
      label: 'Rendering',
      optionLabels: OnboardingKeystoneQrRendering.values
          .map(onboardingKeystoneQrRenderingLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneSigningGalleryCase,
      label: 'Phase',
      optionLabels: OnboardingKeystoneSigningPhase.values
          .map(onboardingKeystoneSigningPhaseLabel)
          .toList(),
      otherKnobs: {'Layout': _mobile},
    );
  });

  testWidgets('import birthday covers the tab and metadata axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingImportBirthdayGalleryCase,
      label: 'Tab',
      optionLabels: ImportBirthdayTab.values
          .map(onboardingImportBirthdayTabLabel)
          .toList(),
      otherKnobs: {
        'Metadata': onboardingImportBirthdayMetadataLabel(
          OnboardingImportBirthdayMetadata.loaded,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingImportBirthdayGalleryCase,
      label: 'Metadata',
      optionLabels: OnboardingImportBirthdayMetadata.values
          .map(onboardingImportBirthdayMetadataLabel)
          .toList(),
      otherKnobs: {
        'Tab': onboardingImportBirthdayTabLabel(ImportBirthdayTab.date),
      },
    );

    // The failed option is the only one that must never reach lightwalletd.
    await pumpUseCase(
      tester,
      buildOnboardingImportBirthdayGalleryCase,
      knobs: {
        'Metadata': onboardingImportBirthdayMetadataLabel(
          OnboardingImportBirthdayMetadata.failed,
        ),
      },
    );
    expect(find.text('Could not load wallet birthday metadata.'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('account discovery covers the account and balance axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingImportDiscoveryGalleryCase,
      label: 'Accounts',
      optionLabels: OnboardingImportDiscoveryAccounts.values
          .map(onboardingImportDiscoveryAccountsLabel)
          .toList(),
      otherKnobs: {
        'Balance': onboardingImportDiscoveryBalanceLabel(
          OnboardingImportDiscoveryBalance.loaded,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingImportDiscoveryGalleryCase,
      label: 'Balance',
      optionLabels: OnboardingImportDiscoveryBalance.values
          .map(onboardingImportDiscoveryBalanceLabel)
          .toList(),
      // One row settles in a single pump, so the three outcomes are the only
      // difference between these renders.
      otherKnobs: {
        'Accounts': onboardingImportDiscoveryAccountsLabel(
          OnboardingImportDiscoveryAccounts.one,
        ),
      },
    );
  });

  testWidgets('account discovery previews the desktop modal and the sheet', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildOnboardingImportDiscoveryGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('import_account_discovery_confirm_button')),
      findsOne,
    );

    await pumpUseCase(
      tester,
      buildOnboardingImportDiscoveryGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('mobile_import_account_discovery_sheet')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('import_account_discovery_confirm_button')),
      findsNothing,
    );
    await disposeTree(tester);
  });

  testWidgets('empty selection decides whether Import stays enabled', (
    tester,
  ) async {
    for (final allowed in [true, false]) {
      await pumpUseCase(
        tester,
        buildOnboardingImportDiscoveryGalleryCase,
        knobs: {
          'Accounts': onboardingImportDiscoveryAccountsLabel(
            OnboardingImportDiscoveryAccounts.one,
          ),
          'Allow empty selection': '$allowed',
        },
      );
      // Rows start selected; deselecting the only one is what the knob gates.
      await tester.tap(
        find.byKey(const ValueKey('import_account_discovery_row_1')),
      );
      await tester.pump();

      final confirm = tester.widget<AppButton>(
        find.byKey(const ValueKey('import_account_discovery_confirm_button')),
      );
      expect(
        confirm.onPressed,
        allowed ? isNotNull : isNull,
        reason: 'allow empty selection: $allowed',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('the birthday calendar covers presentation and range', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingBirthdayCalendarGalleryCase,
      label: 'Presentation',
      optionLabels: OnboardingBirthdayCalendarPresentation.values
          .map(onboardingBirthdayCalendarPresentationLabel)
          .toList(),
      otherKnobs: {
        'Range': onboardingBirthdayCalendarRangeLabel(
          OnboardingBirthdayCalendarRange.midRange,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingBirthdayCalendarGalleryCase,
      label: 'Range',
      optionLabels: OnboardingBirthdayCalendarRange.values
          .map(onboardingBirthdayCalendarRangeLabel)
          .toList(),
    );

    // The range ends are the states where a nav arrow is disabled.
    await pumpUseCase(
      tester,
      buildOnboardingBirthdayCalendarGalleryCase,
      knobs: {
        'Range': onboardingBirthdayCalendarRangeLabel(
          OnboardingBirthdayCalendarRange.earliest,
        ),
      },
    );
    expect(find.text('October 2016'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('the unknown-birthday warning renders in both layouts', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildOnboardingUnknownBirthdayGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Import from the earliest height?'), findsOne);
    expect(
      find.byKey(const ValueKey('mobile_import_birthday_unknown_height_sheet')),
      findsNothing,
    );

    await pumpUseCase(
      tester,
      buildOnboardingUnknownBirthdayGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Import from the earliest height?'), findsOne);
    expect(
      find.byKey(
        const ValueKey('mobile_import_birthday_unknown_height_confirm'),
      ),
      findsOne,
    );
    await disposeTree(tester);
  });

  testWidgets('the Keystone intro renders a screen in each layout', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildOnboardingKeystoneIntroGalleryCase,
      knobs: {'Layout': _desktop},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Connect Keystone'), findsOne);
    expect(find.byKey(_mobileKeystoneIntroContinue), findsNothing);

    // Both screens carry the same title, so the mobile step is identified by
    // its own bottom action.
    await pumpUseCase(
      tester,
      buildOnboardingKeystoneIntroGalleryCase,
      knobs: {'Layout': _mobile},
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(_mobileKeystoneIntroContinue), findsOne);
    await disposeTree(tester);
  });

  testWidgets('the desktop Keystone birthday step covers the metadata axis', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneBirthdayGalleryCase,
      label: 'Metadata',
      optionLabels: OnboardingKeystoneBirthdayMetadata.values
          .map(onboardingKeystoneBirthdayMetadataLabel)
          .toList(),
      otherKnobs: {'Layout': _desktop},
    );

    // The failed load is the only option that reports the metadata error.
    await pumpUseCase(
      tester,
      buildOnboardingKeystoneBirthdayGalleryCase,
      knobs: {
        'Layout': _desktop,
        'Metadata': onboardingKeystoneBirthdayMetadataLabel(
          OnboardingKeystoneBirthdayMetadata.failed,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Could not load wallet birthday metadata.'), findsOne);

    await pumpUseCase(
      tester,
      buildOnboardingKeystoneBirthdayGalleryCase,
      knobs: {
        'Layout': _desktop,
        'Metadata': onboardingKeystoneBirthdayMetadataLabel(
          OnboardingKeystoneBirthdayMetadata.loaded,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Could not load wallet birthday metadata.'), findsNothing);
    // Both options show this placeholder; it guards the field's presence, while
    // the distinguishing work is the error copy above plus the render sweep.
    expect(find.text('mm/dd/yyyy'), findsOne);
    await tester.tap(find.text('mm/dd/yyyy'));
    await tester.pump();
    expect(find.text('September 2026'), findsOneWidget);
    // The deterministic preview tip is September 1, so this is the enabled
    // date at the calendar boundary; later September cells are disabled.
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('keystone_birthday_submit_button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.text('Could not estimate the wallet birthday height.'),
      findsNothing,
    );
    await disposeTree(tester);
  });

  testWidgets('the desktop Keystone picker covers accounts and selection', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneSelectAccountGalleryCase,
      label: 'Accounts',
      optionLabels: OnboardingKeystoneAccounts.values
          .map(onboardingKeystoneAccountsLabel)
          .toList(),
      otherKnobs: {
        'Layout': _desktop,
        'Selection': onboardingKeystoneSelectionLabel(
          OnboardingKeystoneSelection.first,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneSelectAccountGalleryCase,
      label: 'Selection',
      optionLabels: OnboardingKeystoneSelection.values
          .map(onboardingKeystoneSelectionLabel)
          .toList(),
      otherKnobs: {
        'Layout': _desktop,
        'Accounts': onboardingKeystoneAccountsLabel(
          OnboardingKeystoneAccounts.four,
        ),
      },
    );

    // Nothing selected is the state that disables the confirm button.
    await pumpUseCase(
      tester,
      buildOnboardingKeystoneSelectAccountGalleryCase,
      knobs: {
        'Layout': _desktop,
        'Selection': onboardingKeystoneSelectionLabel(
          OnboardingKeystoneSelection.none,
        ),
      },
    );
    expect(find.text('4 accounts found'), findsOne);

    // The two dropdowns are independent, so an empty list has to survive every
    // Selection option rather than indexing past the end of it.
    for (final selection in OnboardingKeystoneSelection.values) {
      await pumpUseCase(
        tester,
        buildOnboardingKeystoneSelectAccountGalleryCase,
        knobs: {
          'Layout': _desktop,
          'Accounts': onboardingKeystoneAccountsLabel(
            OnboardingKeystoneAccounts.none,
          ),
          'Selection': onboardingKeystoneSelectionLabel(selection),
        },
      );
      expect(tester.takeException(), isNull, reason: selection.name);
      expect(find.text('0 accounts found'), findsOne, reason: selection.name);
    }
    await disposeTree(tester);
  });

  testWidgets('Keystone transaction progress covers its three axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneProgressGalleryCase,
      label: 'Presentation',
      optionLabels: OnboardingKeystoneProgressPresentation.values
          .map(onboardingKeystoneProgressPresentationLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneProgressGalleryCase,
      label: 'Label',
      optionLabels: OnboardingKeystoneProgressLabel.values
          .map(onboardingKeystoneProgressLabelLabel)
          .toList(),
    );

    // The camera row belongs to the panel, so it is swept there.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneProgressGalleryCase,
      label: 'Camera row',
      optionLabels: const ['false', 'true'],
      otherKnobs: {
        'Presentation': onboardingKeystoneProgressPresentationLabel(
          OnboardingKeystoneProgressPresentation.panel,
        ),
      },
    );

    await pumpUseCase(
      tester,
      buildOnboardingKeystoneProgressGalleryCase,
      knobs: {'Camera row': 'true'},
    );
    expect(find.text('Submitting the transaction'), findsOne);
    expect(find.text('Camera'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('the desktop Keystone signing modal covers its three axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneSigningGalleryCase,
      label: 'Phase',
      optionLabels: KeystoneSigningModalPhase.values
          .map(onboardingKeystoneSigningModalPhaseLabel)
          .toList(),
      otherKnobs: {'Layout': _desktop},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneSigningGalleryCase,
      label: 'Actions',
      optionLabels: OnboardingKeystoneSigningActions.values
          .map(onboardingKeystoneSigningActionsLabel)
          .toList(),
      otherKnobs: {'Layout': _desktop},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneSigningGalleryCase,
      label: 'Instruction',
      optionLabels: const ['false', 'true'],
      otherKnobs: {'Layout': _desktop},
    );
  });

  testWidgets('previously unregistered import fixtures are now reachable', (
    tester,
  ) async {
    // The four ImportSecretPassphrase builders and the import CustomiseAccount
    // builder rendered only through figma_compare before this gallery.
    await pumpUseCase(
      tester,
      buildOnboardingImportPassphraseGalleryCase,
      knobs: {
        'State': onboardingImportPassphraseStateLabel(
          OnboardingImportPassphraseState.bip39Modal,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('BIP39'), findsWidgets);

    await pumpUseCase(
      tester,
      buildOnboardingCustomiseAccountGalleryCase,
      knobs: {
        'Layout': _desktop,
        'Flow': onboardingCustomiseAccountFlowLabel(
          OnboardingCustomiseAccountFlow.importWallet,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  testWidgets('the mobile onboarding entry screens render their own content', (
    tester,
  ) async {
    // The welcome screen is a folded surface, so its mobile half is selected
    // on the knob; the explainers are asserted with their desktop halves.
    await pumpUseCase(
      tester,
      buildOnboardingWelcomeGalleryCase,
      knobs: {'Layout': _mobile},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Get started'), findsWidgets);

    for (final expected in {
      'Welcome to Vizor': buildOnboardingMobileMethodSelectionUseCase,
      'Link with Desktop': buildOnboardingMobileWalletLinkIntroUseCase,
    }.entries) {
      await pumpUseCase(tester, expected.value);
      expect(tester.takeException(), isNull, reason: expected.key);
      expect(find.text(expected.key), findsWidgets, reason: expected.key);
    }
    await disposeTree(tester);
  });

  testWidgets('the wallet-link scanner covers camera, error and reading', (
    tester,
  ) async {
    const noError = OnboardingWalletLinkScanErrorCase.none;
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWalletLinkScanGalleryCase,
      label: 'Camera',
      optionLabels: OnboardingWalletLinkCamera.values
          .map(onboardingWalletLinkCameraLabel)
          .toList(),
      otherKnobs: {'Error': onboardingWalletLinkScanErrorLabel(noError)},
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWalletLinkScanGalleryCase,
      label: 'Error',
      optionLabels: OnboardingWalletLinkScanErrorCase.values
          .map(onboardingWalletLinkScanErrorLabel)
          .toList(),
      otherKnobs: {
        'Camera': onboardingWalletLinkCameraLabel(
          OnboardingWalletLinkCamera.active,
        ),
      },
    );

    // 'Reading link' only reaches the active camera card, where it swaps the
    // caption and disables the close control.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWalletLinkScanGalleryCase,
      label: 'Reading link',
      optionLabels: const ['false', 'true'],
      otherKnobs: {
        'Camera': onboardingWalletLinkCameraLabel(
          OnboardingWalletLinkCamera.active,
        ),
        'Error': onboardingWalletLinkScanErrorLabel(noError),
      },
    );

    await pumpUseCase(
      tester,
      buildOnboardingWalletLinkScanGalleryCase,
      knobs: {
        'Error': onboardingWalletLinkScanErrorLabel(
          OnboardingWalletLinkScanErrorCase.expired,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Link expired'), findsOne);
    expect(find.text('Scan again'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('wallet-link selection covers list, payload and selection', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWalletLinkAccountsGalleryCase,
      label: 'List',
      optionLabels: OnboardingWalletLinkList.values
          .map(onboardingWalletLinkListLabel)
          .toList(),
    );

    for (final list in OnboardingWalletLinkList.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildOnboardingWalletLinkAccountsGalleryCase,
        label: 'Payload',
        optionLabels: OnboardingWalletLinkAccounts.values
            .map(onboardingWalletLinkAccountsLabel)
            .toList(),
        otherKnobs: {
          'List': onboardingWalletLinkListLabel(list),
          'Selection': onboardingWalletLinkSelectionLabel(
            OnboardingWalletLinkSelection.all,
          ),
        },
      );

      // Selection only moves rows that are still importable, so it is swept on
      // the payload whose rows are all pending.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildOnboardingWalletLinkAccountsGalleryCase,
        label: 'Selection',
        optionLabels: OnboardingWalletLinkSelection.values
            .map(onboardingWalletLinkSelectionLabel)
            .toList(),
        otherKnobs: {
          'List': onboardingWalletLinkListLabel(list),
          'Payload': onboardingWalletLinkAccountsLabel(
            OnboardingWalletLinkAccounts.pendingOnly,
          ),
        },
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingWalletLinkAccountsGalleryCase,
      label: 'Submitting',
      optionLabels: const ['false', 'true'],
      otherKnobs: {
        'Payload': onboardingWalletLinkAccountsLabel(
          OnboardingWalletLinkAccounts.mixed,
        ),
        'Selection': onboardingWalletLinkSelectionLabel(
          OnboardingWalletLinkSelection.all,
        ),
      },
    );
  });

  testWidgets('the wallet-link contacts step labels its own list', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildOnboardingWalletLinkAccountsGalleryCase,
      knobs: {
        'List': onboardingWalletLinkListLabel(
          OnboardingWalletLinkList.contacts,
        ),
        'Payload': onboardingWalletLinkAccountsLabel(
          OnboardingWalletLinkAccounts.pendingOnly,
        ),
        'Selection': onboardingWalletLinkSelectionLabel(
          OnboardingWalletLinkSelection.all,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Import contacts'), findsOne);
    expect(
      find.text('Import $onboardingMobileWalletLinkContactCount contacts'),
      findsOne,
    );
    expect(find.text('Deselect all'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('wallet-link accounts labels its action for each payload', (
    tester,
  ) async {
    Future<void> pumpAccounts({
      required OnboardingWalletLinkAccounts accounts,
      required OnboardingWalletLinkSelection selection,
      bool submitting = false,
    }) async {
      await pumpUseCase(
        tester,
        buildOnboardingWalletLinkAccountsGalleryCase,
        knobs: {
          'Payload': onboardingWalletLinkAccountsLabel(accounts),
          'Selection': onboardingWalletLinkSelectionLabel(selection),
          if (submitting) 'Submitting': 'true',
        },
      );
      expect(tester.takeException(), isNull);
    }

    await pumpAccounts(
      accounts: OnboardingWalletLinkAccounts.nothingToImport,
      selection: OnboardingWalletLinkSelection.none,
    );
    expect(find.text('Go back'), findsOne);

    await pumpAccounts(
      accounts: OnboardingWalletLinkAccounts.pendingOnly,
      selection: OnboardingWalletLinkSelection.none,
    );
    expect(find.text('Continue'), findsOne);
    expect(find.text('Select all'), findsOne);

    await pumpAccounts(
      accounts: OnboardingWalletLinkAccounts.pendingOnly,
      selection: OnboardingWalletLinkSelection.partial,
    );
    expect(find.text('Link 1 account'), findsOne);

    await pumpAccounts(
      accounts: OnboardingWalletLinkAccounts.pendingOnly,
      selection: OnboardingWalletLinkSelection.all,
    );
    expect(
      find.text('Link $onboardingMobileWalletLinkAccountCount accounts'),
      findsOne,
    );
    expect(find.text('Deselect all'), findsOne);

    await pumpAccounts(
      accounts: OnboardingWalletLinkAccounts.alreadyImportedOnly,
      selection: OnboardingWalletLinkSelection.none,
    );
    expect(
      find.text('$onboardingMobileWalletLinkAccountCount already imported'),
      findsOne,
    );

    await pumpAccounts(
      accounts: OnboardingWalletLinkAccounts.mixed,
      selection: OnboardingWalletLinkSelection.all,
      submitting: true,
    );
    expect(find.text('Importing...'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('the three onboarding shells cover their step axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingCreateShellGalleryCase,
      label: 'Step',
      optionLabels: OnboardingStep.values.map((step) => step.label).toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingImportShellGalleryCase,
      label: 'Step',
      optionLabels: ImportOnboardingStep.values
          .map((step) => step.label)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingKeystoneShellGalleryCase,
      label: 'Step',
      optionLabels: KeystoneOnboardingStep.values
          .map((step) => step.label)
          .toList(),
    );
  });

  testWidgets('the onboarding shells drop the password step on request', (
    tester,
  ) async {
    for (final builder in [
      buildOnboardingCreateShellGalleryCase,
      buildOnboardingImportShellGalleryCase,
      buildOnboardingKeystoneShellGalleryCase,
    ]) {
      await pumpUseCase(tester, builder, knobs: {'Show password step': 'true'});
      expect(tester.takeException(), isNull);
      expect(find.text('Set Password'), findsOne);

      await pumpUseCase(
        tester,
        builder,
        knobs: {'Show password step': 'false'},
      );
      expect(find.text('Set Password'), findsNothing);
    }
    await disposeTree(tester);
  });

  testWidgets('the create shell swaps its sidebar art when the seed is shown', (
    tester,
  ) async {
    final knobs = {'Step': OnboardingStep.secretPassphrase.label};
    await pumpUseCase(
      tester,
      buildOnboardingCreateShellGalleryCase,
      knobs: {...knobs, 'Passphrase revealed': 'false'},
    );
    expect(tester.takeException(), isNull);
    final closed = _assetImageNames(tester);

    await pumpUseCase(
      tester,
      buildOnboardingCreateShellGalleryCase,
      knobs: {...knobs, 'Passphrase revealed': 'true'},
    );
    final open = _assetImageNames(tester);

    expect(closed, isNotEmpty);
    expect(open, isNot(closed));
    await disposeTree(tester);
  });

  testWidgets('the onboarding sidebar covers flow, active step and taps', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSidebarGalleryCase,
      label: 'Flow',
      optionLabels: OnboardingSidebarFlow.values
          .map(onboardingSidebarFlowLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSidebarGalleryCase,
      label: 'Active step',
      optionLabels: OnboardingSidebarActive.values
          .map(onboardingSidebarActiveLabel)
          .toList(),
    );

    // The tap slot adds no paint, so it is asserted on the widget it inserts.
    final tappableRows = find.descendant(
      of: find.byType(OnboardingSidebarItem),
      matching: find.byType(GestureDetector),
    );
    await pumpUseCase(
      tester,
      buildOnboardingSidebarGalleryCase,
      knobs: {'Tappable steps': 'false'},
    );
    expect(tester.takeException(), isNull);
    expect(tappableRows, findsNothing);

    await pumpUseCase(
      tester,
      buildOnboardingSidebarGalleryCase,
      knobs: {'Tappable steps': 'true'},
    );
    expect(
      tappableRows,
      findsNWidgets(find.byType(OnboardingSidebarItem).evaluate().length),
    );
    await disposeTree(tester);
  });

  testWidgets('the pane chrome covers the back link and the overlay slot', (
    tester,
  ) async {
    Future<void> pumpChrome(OnboardingPaneBack back, {bool overlay = false}) {
      return pumpUseCase(
        tester,
        buildOnboardingPaneChromeGalleryCase,
        knobs: {
          'Back link': onboardingPaneBackLabel(back),
          'Overlay': overlay ? 'true' : 'false',
        },
      );
    }

    await pumpChrome(OnboardingPaneBack.route);
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome'), findsOne);
    expect(find.text('Pane overlay'), findsNothing);

    await pumpChrome(OnboardingPaneBack.callback);
    expect(find.text(ImportOnboardingStep.secretPassphrase.label), findsOne);

    await pumpChrome(OnboardingPaneBack.none);
    expect(find.text('Welcome'), findsNothing);
    expect(
      find.text(ImportOnboardingStep.secretPassphrase.label),
      findsNothing,
    );

    await pumpChrome(OnboardingPaneBack.route, overlay: true);
    expect(find.text('Pane overlay'), findsOne);
    await disposeTree(tester);
  });

  testWidgets('the auth shell covers its card boxes and padding', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingAuthShellGalleryCase,
      label: 'Card',
      optionLabels: OnboardingAuthCardBox.values
          .map(onboardingAuthCardBoxLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildOnboardingAuthShellGalleryCase,
      knobs: {'Compact padding': 'false'},
    );
    expect(tester.takeException(), isNull);
    final roomy = tester.getRect(find.text('Card content'));

    await pumpUseCase(
      tester,
      buildOnboardingAuthShellGalleryCase,
      knobs: {'Compact padding': 'true'},
    );
    expect(tester.getRect(find.text('Card content')).top, isNot(roomy.top));
    await disposeTree(tester);
  });

  testWidgets('the Keystone scan help tooltip follows its visible knob', (
    tester,
  ) async {
    const tooltip = ValueKey('keystone_scan_help_tooltip');

    await pumpUseCase(
      tester,
      buildOnboardingKeystoneScanHelpGalleryCase,
      knobs: {'Visible': 'true'},
    );
    // The portal shows itself in a post-frame callback.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(tooltip), findsOne);
    expect(find.byKey(const ValueKey('keystone_scan_help_anchor')), findsOne);

    await pumpUseCase(
      tester,
      buildOnboardingKeystoneScanHelpGalleryCase,
      knobs: {'Visible': 'false'},
    );
    await tester.pump();
    expect(find.byKey(tooltip), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('mobile unlock reaches its three submit states', (tester) async {
    // The rejected-passcode path fires the error haptic; without a handler the
    // channel call would surface as an unhandled platform exception.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      const MethodChannel('com.zcash.wallet/haptics'),
      SystemChannels.platform,
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    Future<void> pumpAttempt(OnboardingMobileUnlockAttempt attempt) async {
      await pumpUseCase(
        tester,
        buildOnboardingUnlockGalleryCase,
        knobs: {
          'Layout': _mobile,
          'Attempt': onboardingMobileUnlockAttemptLabel(attempt),
        },
      );
      // Mount driver -> six digits -> submit -> the unlock future settles.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: attempt.name);
    }

    await pumpAttempt(OnboardingMobileUnlockAttempt.waiting);
    expect(find.text('Enter your passcode to open Vizor'), findsOne);

    await pumpAttempt(OnboardingMobileUnlockAttempt.submitting);
    expect(find.text('Opening your wallet...'), findsOne);

    await pumpAttempt(OnboardingMobileUnlockAttempt.incorrectPasscode);
    expect(find.text('Incorrect Passcode'), findsOne);

    await pumpAttempt(OnboardingMobileUnlockAttempt.openFailed);
    expect(find.text("Couldn't open your wallet. Please try again."), findsOne);
    await disposeTree(tester);
  });

  testWidgets('mobile biometrics disables both actions while turning on', (
    tester,
  ) async {
    Future<AppButton> pumpBiometrics(
      OnboardingMobileBiometricsState state,
      Key key,
    ) async {
      await pumpUseCase(
        tester,
        buildOnboardingMobileBiometricsGalleryCase,
        knobs: {'State': onboardingMobileBiometricsStateLabel(state)},
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: state.name);
      return tester.widget<AppButton>(find.byKey(key));
    }

    const enableKey = ValueKey('mobile_biometrics_enable');
    const notNowKey = ValueKey('mobile_biometrics_not_now');

    expect(
      (await pumpBiometrics(
        OnboardingMobileBiometricsState.offered,
        enableKey,
      )).onPressed,
      isNotNull,
    );
    expect(
      (await pumpBiometrics(
        OnboardingMobileBiometricsState.enabling,
        enableKey,
      )).onPressed,
      isNull,
    );
    expect(
      (await pumpBiometrics(
        OnboardingMobileBiometricsState.enabling,
        notNowKey,
      )).onPressed,
      isNull,
    );
    await disposeTree(tester);
  });

  testWidgets('the seed card covers its word, copy and gap axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSeedCardGalleryCase,
      label: 'Words',
      optionLabels: OnboardingSeedCardWords.values
          .map(onboardingSeedCardWordsLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingSeedCardGalleryCase,
      label: 'Copy action',
      optionLabels: OnboardingSeedCardCopy.values
          .map(onboardingSeedCardCopyLabel)
          .toList(),
    );

    for (final knobs in [
      {'Obscured': 'true'},
      {'Onboarding row gap': 'false'},
    ]) {
      await pumpUseCase(tester, buildOnboardingSeedCardGalleryCase);
      expect(tester.takeException(), isNull);
      final base = await useCaseFingerprint(tester);

      await pumpUseCase(
        tester,
        buildOnboardingSeedCardGalleryCase,
        knobs: knobs,
      );
      expect(await useCaseFingerprint(tester), isNot(base), reason: '$knobs');
    }
    await disposeTree(tester);
  });

  testWidgets('the passcode field covers its filled and message axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingPasscodeFieldGalleryCase,
      label: 'Filled',
      optionLabels: OnboardingPasscodeFilled.values
          .map(onboardingPasscodeFilledLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildOnboardingPasscodeFieldGalleryCase,
      knobs: {
        'Message': onboardingPasscodeErrorLabel(
          OnboardingPasscodeError.incorrectPasscode,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Incorrect Passcode'), findsOne);

    await pumpUseCase(
      tester,
      buildOnboardingPasscodeFieldGalleryCase,
      knobs: {
        'Message': onboardingPasscodeErrorLabel(
          OnboardingPasscodeError.openFailed,
        ),
      },
    );
    expect(find.text("Couldn't open your wallet. Please try again."), findsOne);

    await pumpUseCase(
      tester,
      buildOnboardingPasscodeFieldGalleryCase,
      knobs: {
        'Message': onboardingPasscodeErrorLabel(OnboardingPasscodeError.none),
      },
    );
    expect(find.text('Incorrect Passcode'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('the passcode keypad covers its four axes', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingPasscodeKeypadGalleryCase,
      label: 'Biometric',
      optionLabels: OnboardingPasscodeBiometric.values
          .map(onboardingPasscodeBiometricLabel)
          .toList(),
    );

    for (final knobs in [
      {'Can delete': 'false'},
      {'Show help': 'false'},
      {'Enabled': 'false'},
    ]) {
      await pumpUseCase(tester, buildOnboardingPasscodeKeypadGalleryCase);
      expect(tester.takeException(), isNull);
      final base = await useCaseFingerprint(tester);

      await pumpUseCase(
        tester,
        buildOnboardingPasscodeKeypadGalleryCase,
        knobs: knobs,
      );
      expect(await useCaseFingerprint(tester), isNot(base), reason: '$knobs');
    }
    await disposeTree(tester);
  });

  testWidgets('the mobile step scaffold covers its slots and chrome', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingStepScaffoldGalleryCase,
      label: 'Progress',
      optionLabels: OnboardingStepScaffoldProgress.values
          .map(onboardingStepScaffoldProgressLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildOnboardingStepScaffoldGalleryCase,
      label: 'Slots',
      optionLabels: OnboardingStepScaffoldSlots.values
          .map(onboardingStepScaffoldSlotsLabel)
          .toList(),
    );

    for (final knobs in [
      {'Show back button': 'false'},
      {'Scrollable': 'false'},
    ]) {
      await pumpUseCase(tester, buildOnboardingStepScaffoldGalleryCase);
      expect(tester.takeException(), isNull);
      final base = await useCaseFingerprint(tester);

      await pumpUseCase(
        tester,
        buildOnboardingStepScaffoldGalleryCase,
        knobs: knobs,
      );
      expect(await useCaseFingerprint(tester), isNot(base), reason: '$knobs');
    }
    await disposeTree(tester);
  });
}

/// The `Layout` knob's two option labels.
final String _desktop = wbLayoutLabel(WbLayout.desktop);
final String _mobile = wbLayoutLabel(WbLayout.mobile);

/// The mobile Keystone intro's bottom action: both intros share the title, so
/// this is what tells the two layouts apart.
const Key _mobileKeystoneIntroContinue = ValueKey(
  'mobile_keystone_intro_continue',
);

/// The surfaces that exist in both form factors, which the gallery registers
/// as one `Playground` use case with a `Layout` knob each.
final Map<String, WidgetBuilder> _foldedLayoutCases = {
  'Welcome': buildOnboardingWelcomeGalleryCase,
  'Intro to Zcash': buildOnboardingIntroZcashGalleryCase,
  'Address types': buildOnboardingAddressTypesGalleryCase,
  'Things to know': buildOnboardingThingsToKnowGalleryCase,
  'Secret passphrase': buildOnboardingSecretPassphraseGalleryCase,
  'Unlock': buildOnboardingUnlockGalleryCase,
  'Customise account': buildOnboardingCustomiseAccountGalleryCase,
  'Keystone intro': buildOnboardingKeystoneIntroGalleryCase,
  'Keystone scan': buildOnboardingKeystoneScanGalleryCase,
  'Keystone select account': buildOnboardingKeystoneSelectAccountGalleryCase,
  'Keystone birthday': buildOnboardingKeystoneBirthdayGalleryCase,
  'Set password': buildOnboardingSetPasswordGalleryCase,
  'Keystone signing': buildOnboardingKeystoneSigningGalleryCase,
};

/// Every asset image currently mounted, which is how the sidebar art axis is
/// asserted without reaching into the private illustration widget.
Set<String> _assetImageNames(WidgetTester tester) {
  return tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .whereType<AssetImage>()
      .map((image) => image.assetName)
      .toSet();
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), youngSerif.load()]);
}
