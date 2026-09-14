import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/account_name_policy.dart';
import 'package:zcash_wallet/src/core/security/password_policy.dart';
import 'package:zcash_wallet/src/features/settings/widgets/settings_pane_backdrop.dart';
import 'package:zcash_wallet/widgetbook/accounts_settings_use_cases.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/accounts_settings_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Desktop-lane suite: untagged, so `--tags mobile` never selects it. The layout
// knob is driven by explicit query params rather than by the compiled lane, but
// these are desktop surfaces and rendering them against mobile tokens overflows
// by design.
void main() {
  // Real app fonts: the square-glyph test font is much wider than Geist and
  // makes the endpoint screen report a RenderFlex overflow the app never has
  // (same reason as `settings_use_cases_test.dart`).
  setUpAll(() async {
    const fonts = <String, List<String>>{
      'Geist': [
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
      ],
      'Geist Mono': [
        'assets/fonts/GeistMono-Regular.ttf',
        'assets/fonts/GeistMono-Medium.ttf',
      ],
      'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
      'Inter': [
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Medium.ttf',
        'assets/fonts/Inter-SemiBold.ttf',
        'assets/fonts/Inter-Bold.ttf',
      ],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });

  // The reveal screens mount `SensitivePrivacyOverlay`, which talks to the
  // platform privacy channels; unmocked they throw on the test host.
  setUp(() {
    const privacyChannels = [
      MethodChannel('com.zcash.wallet/privacy_exposure'),
      MethodChannel('com.zcash.wallet/privacy_shield'),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in privacyChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
  });

  testWidgets('every accounts/settings gallery case builds at its defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(accountsSettingsGalleryNodes).toList();
    expect(useCases.length, 29);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  test('donation surfaces are registered under Settings', () {
    final useCases = widgetbookUseCases(accountsSettingsGalleryNodes).toList();
    expect(
      useCases.where(
        (entry) => entry.builder == buildDonationComposeGalleryCase,
      ),
      hasLength(1),
    );
    expect(
      useCases.where(
        (entry) => entry.builder == buildDonationRecipientRowGalleryCase,
      ),
      hasLength(1),
    );
  });

  // The row menus and the mobile sheets land on overlays above the capture
  // boundary, so the accounts screens are swept by the copy they put on
  // screen rather than by pixels.
  testWidgets('accounts screen registers each layout\'s own knobs', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: _desktopLayoutKnobs,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'Accounts',
      'Modal',
      'Row menu',
      'Remove blockers',
    });

    final mobile = await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(mobile.knobs.keys.toSet(), {
      'Layout',
      'Accounts',
      'Sheet',
      'Row menu',
      'Migration',
    });
    await disposeTree(tester);

    await _expectSettledOptionsDistinct(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('accounts screen desktop layout varies on all four axes', (
    tester,
  ) async {
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Accounts',
      optionLabels: AccountsListSize.values.map(accountsListSizeLabel).toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Modal',
      optionLabels: AccountsDesktopModal.values
          .map(accountsDesktopModalLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Row menu',
      optionLabels: AccountsDesktopRowMenu.values
          .map(accountsDesktopRowMenuLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    // Every blocker variant is warning copy inside the remove modal.
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Remove blockers',
      optionLabels: AccountsRemoveBlocker.values
          .map(accountsRemoveBlockerLabel)
          .toList(),
      otherKnobs: {
        ..._desktopLayoutKnobs,
        'Modal': accountsDesktopModalLabel(AccountsDesktopModal.removeAccount),
      },
    );
  });

  testWidgets('desktop accounts screen reaches the single and empty states', (
    tester,
  ) async {
    // One account left: removal is a full reset.
    await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Accounts': accountsListSizeLabel(AccountsListSize.single),
        'Modal': accountsDesktopModalLabel(AccountsDesktopModal.removeAccount),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reset Vizor'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Accounts': accountsListSizeLabel(AccountsListSize.none),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Accounts'), findsOneWidget);

    // The hardware row menu drops the seed-phrase shortcut a UFVK can't back.
    await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Row menu': accountsDesktopRowMenuLabel(
          AccountsDesktopRowMenu.keystoneAccount,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('View viewing key'), findsOneWidget);
    expect(find.text('View secret phrase'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('accounts screen mobile layout varies on all four axes', (
    tester,
  ) async {
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Accounts',
      optionLabels: AccountsListSize.values.map(accountsListSizeLabel).toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Sheet',
      optionLabels: AccountsMobileSheet.values
          .map(accountsMobileSheetLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Row menu',
      optionLabels: AccountsMobileRowMenu.values
          .map(accountsMobileRowMenuLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    // Migration only rewrites the remove sheet's description.
    await _expectSettledOptionsDistinctByText(
      tester,
      buildAccountsScreenGalleryCase,
      label: 'Migration',
      optionLabels: AccountsMigration.values
          .map(accountsMigrationLabel)
          .toList(),
      otherKnobs: {
        ..._mobileLayoutKnobs,
        'Sheet': accountsMobileSheetLabel(AccountsMobileSheet.removeAccount),
      },
    );
  });

  testWidgets('mobile hardware row menu drops the seed-phrase shortcut', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Row menu': accountsMobileRowMenuLabel(
          AccountsMobileRowMenu.keystoneAccount,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('View viewing key'), findsOneWidget);
    expect(find.text('View secret phrase'), findsNothing);

    // The single-account remove sheet is the reset copy, not a removal.
    await pumpUseCase(
      tester,
      buildAccountsScreenGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Accounts': accountsListSizeLabel(AccountsListSize.single),
        'Sheet': accountsMobileSheetLabel(AccountsMobileSheet.removeAccount),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reset Vizor'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('accounts switcher sheet varies on both axes', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsSwitcherSheetGalleryCase,
      label: 'Other accounts',
      optionLabels: AccountsSwitcherOthers.values
          .map(accountsSwitcherOthersLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsSwitcherSheetGalleryCase,
      label: 'Active account',
      optionLabels: AccountsSwitcherActive.values
          .map(accountsSwitcherActiveLabel)
          .toList(),
    );

    // No other accounts: the list and its title are both omitted.
    await pumpUseCase(
      tester,
      buildAccountsSwitcherSheetGalleryCase,
      knobs: {
        'Other accounts': accountsSwitcherOthersLabel(
          AccountsSwitcherOthers.none,
        ),
      },
    );
    expect(find.text('Other accounts'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_accounts_sheet_list')),
      findsNothing,
    );

    // Past four rows the list is capped and the scrollbar thumb is pinned.
    await pumpUseCase(
      tester,
      buildAccountsSwitcherSheetGalleryCase,
      knobs: {
        'Other accounts': accountsSwitcherOthersLabel(
          AccountsSwitcherOthers.twelve,
        ),
      },
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_accounts_sheet_list')))
          .height,
      216,
    );
    await disposeTree(tester);
  });

  testWidgets('profile picture sheet moves its selection ring', (tester) async {
    // The sheet is presented on the root navigator, above the capture
    // boundary, so each option is checked by its selected-badge key.
    for (final selection in AccountsPictureSelection.values) {
      await pumpUseCase(
        tester,
        buildAccountsProfilePictureSheetGalleryCase,
        knobs: {'Selection': accountsPictureSelectionLabel(selection)},
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: selection.name);
      expect(
        find.byKey(
          ValueKey(
            'mobile_account_pfp_selected_badge_'
            '${accountsPictureIdFor(selection)}',
          ),
        ),
        findsOneWidget,
        reason: selection.name,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('remove account modal covers scope and both checks', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsRemoveModalGalleryCase,
      label: 'Scope',
      optionLabels: AccountsRemoveScope.values
          .map(accountsRemoveScopeLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsRemoveModalGalleryCase,
      label: 'Swap check',
      optionLabels: AccountsRemoveSwapCheck.values
          .map(accountsRemoveSwapCheckLabel)
          .toList(),
    );
    // The swap check runs first, so gift-card copy needs it clear.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsRemoveModalGalleryCase,
      label: 'Gift card check',
      optionLabels: AccountsRemoveGiftCardCheck.values
          .map(accountsRemoveGiftCardCheckLabel)
          .toList(),
    );

    // The two gift-card checks fail with their own copy.
    await pumpUseCase(
      tester,
      buildAccountsRemoveModalGalleryCase,
      knobs: {
        'Gift card check': accountsRemoveGiftCardCheckLabel(
          AccountsRemoveGiftCardCheck.receivingFailed,
        ),
      },
    );
    expect(
      find.text(
        "Couldn't check this account for incoming gift cards. "
        'Try again before removing it.',
      ),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildAccountsRemoveModalGalleryCase,
      knobs: {
        'Gift card check': accountsRemoveGiftCardCheckLabel(
          AccountsRemoveGiftCardCheck.unsharedFailed,
        ),
      },
    );
    expect(
      find.text(
        "Couldn't check this account for unshared gift cards. "
        'Try again before removing it.',
      ),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildAccountsRemoveModalGalleryCase,
      knobs: {
        'Scope': accountsRemoveScopeLabel(AccountsRemoveScope.lastAccountReset),
      },
    );
    expect(find.text('Reset Vizor'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('edit account modal covers name and picture drafts', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsEditModalGalleryCase,
      label: 'Name',
      optionLabels: AccountsEditName.values.map(accountsEditNameLabel).toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsEditModalGalleryCase,
      label: 'Picture',
      optionLabels: AccountsEditPicture.values
          .map(accountsEditPictureLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildAccountsEditModalGalleryCase,
      knobs: {'Name': accountsEditNameLabel(AccountsEditName.tooLong)},
    );
    expect(find.text(kAccountNameLengthMessage), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('profile picture modal moves its selection', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsProfilePictureModalGalleryCase,
      label: 'Selection',
      optionLabels: AccountsPictureSelection.values
          .map(accountsPictureSelectionLabel)
          .toList(),
    );
  });

  testWidgets('account modal card covers every action-row combination', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsModalCardGalleryCase,
      label: 'Action variant',
      optionLabels: AccountsModalCardAction.values
          .map(accountsModalCardActionLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsModalCardGalleryCase,
      label: 'Action icon',
      optionLabels: AccountsModalCardIcon.values
          .map(accountsModalCardIconLabel)
          .toList(),
      otherKnobs: {
        'Action variant': accountsModalCardActionLabel(
          AccountsModalCardAction.destructive,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsModalCardGalleryCase,
      label: 'Cancel enabled',
      optionLabels: const ['true', 'false'],
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAccountsModalCardGalleryCase,
      label: 'Action enabled',
      optionLabels: const ['true', 'false'],
    );
  });

  testWidgets('settings screen registers each layout\'s own knobs', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: _desktopLayoutKnobs,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'Account',
      'Theme value',
      'Tor',
      'Scroll',
      'Modal',
    });

    final mobile = await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(mobile.knobs.keys.toSet(), {
      'Layout',
      'Account',
      'Theme value',
      'Scroll',
      'Biometric',
      'Keep awake',
      'Tor',
      'Sheet',
    });
    await disposeTree(tester);

    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('settings screen desktop layout varies on all five axes', (
    tester,
  ) async {
    // The pane modal and the updater dialogs land on different navigators, so
    // the overlay axis is swept by the copy it puts on screen.
    await _expectSettledOptionsDistinctByText(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Modal',
      optionLabels: SettingsDesktopModal.values
          .map(settingsDesktopModalLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Tor',
      optionLabels: SettingsDesktopTor.values
          .map(settingsDesktopTorLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Account',
      optionLabels: SettingsAccount.values.map(settingsAccountLabel).toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Theme value',
      optionLabels: SettingsThemeValue.values
          .map(settingsThemeValueLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    // A canvas shorter than the window so the preview's own 1080x720 box
    // engages and the list scrolls against the app's real travel (695px),
    // which is what the three stops are tuned against.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Scroll',
      optionLabels: SettingsDesktopScroll.values
          .map(settingsDesktopScrollLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
      canvasSize: const Size(1200, 500),
    );
  });

  testWidgets('desktop settings reaches the hardware and no-account states', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Account': settingsAccountLabel(SettingsAccount.keystone),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    // A Keystone account has no seed, so the row is there but inert.
    expect(find.text('Secret passphrase'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Account': settingsAccountLabel(SettingsAccount.none),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Wallet 1'), findsOneWidget);

    // The list builds every row whatever the offset, so `findsOneWidget` alone
    // says nothing about a scroll stop: assert the row is inside the viewport.
    // Support Vizor is the list's last row, so the bottom stop is the one that
    // reaches it.
    for (final (scroll, visible) in [
      (SettingsDesktopScroll.top, false),
      (SettingsDesktopScroll.bottom, true),
    ]) {
      await pumpUseCase(
        tester,
        buildSettingsScreenGalleryCase,
        knobs: {
          ..._desktopLayoutKnobs,
          'Scroll': settingsDesktopScrollLabel(scroll),
        },
        canvasSize: const Size(1200, 500),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final row = find.text('Support Vizor');
      expect(row, findsOneWidget);
      final viewport = tester.getRect(
        find.ancestor(of: row, matching: find.byType(Scrollable)).first,
      );
      final rect = tester.getRect(row);
      expect(
        rect.top >= viewport.top && rect.bottom <= viewport.bottom,
        visible,
        reason: 'Support Vizor at the ${scroll.name} stop',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('desktop settings reaches the theme and Windows update modals', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Modal': settingsDesktopModalLabel(SettingsDesktopModal.theme),
        'Theme value': settingsThemeValueLabel(SettingsThemeValue.dark),
      },
    );
    await _settle(tester);
    expect(find.text('System (Auto)'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.tap(find.text('Update'));
    await _settle(tester);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('System (Auto)'), findsNothing);

    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Modal': settingsDesktopModalLabel(SettingsDesktopModal.updates),
      },
    );
    await _settle(tester);
    expect(find.text('Version 1.4.2 is available.'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);

    final updatesState = await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Modal': settingsDesktopModalLabel(SettingsDesktopModal.updates),
      },
    );
    expect(updatesState.knobs.keys, contains('Updater'));

    // The Updates row exists only on Windows, so the modal is the one overlay
    // that also proves the platform override took.
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Modal': settingsDesktopModalLabel(SettingsDesktopModal.none),
      },
    );
    await _settle(tester);
    expect(find.text('Updates'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('Windows update modal renders every updater state', (
    tester,
  ) async {
    // Each option is one status line plus one primary action; the modal shows
    // nothing else that separates them.
    const expected = <SettingsUpdater, (String, String)>{
      SettingsUpdater.notChecked: (
        'Ready to check for updates.',
        'Check for updates',
      ),
      SettingsUpdater.available: (
        'Version 1.4.2 is available.',
        'Download update',
      ),
      SettingsUpdater.checking: ('Checking for updates.', 'Checking…'),
      SettingsUpdater.downloading: ('Downloading 42%.', 'Downloading…'),
      SettingsUpdater.readyToRestart: (
        'Version 1.4.2 is ready.',
        'Restart to update',
      ),
      SettingsUpdater.restarting: ('Restarting Vizor.', 'Restarting…'),
      SettingsUpdater.upToDate: ('Vizor is up to date.', 'Check for updates'),
      SettingsUpdater.failed: (
        "Couldn't complete the update. Try again.",
        'Try again',
      ),
      SettingsUpdater.failedWithDetail: (
        'The update package could not be downloaded. Try again.',
        'Try again',
      ),
      SettingsUpdater.unsupported: (
        'Updates are available in the installed Windows app.',
        'Check for updates',
      ),
    };

    for (final entry in expected.entries) {
      await pumpUseCase(
        tester,
        buildSettingsScreenGalleryCase,
        knobs: {
          ..._desktopLayoutKnobs,
          'Modal': settingsDesktopModalLabel(SettingsDesktopModal.updates),
          'Updater': settingsUpdaterLabel(entry.key),
        },
      );
      await _settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: settingsUpdaterLabel(entry.key),
      );
      expect(
        find.text(entry.value.$1),
        findsOneWidget,
        reason: settingsUpdaterLabel(entry.key),
      );
      expect(
        find.text(entry.value.$2),
        findsOneWidget,
        reason: settingsUpdaterLabel(entry.key),
      );
    }
    await disposeTree(tester);
  });

  testWidgets('Windows update dialogs render every copy variant', (
    tester,
  ) async {
    // Title plus the line under it: the dialogs carry nothing else that
    // separates one call site's copy from another's.
    const expected = <SettingsUpdateDialog, (String, String)>{
      SettingsUpdateDialog.privacyChoice: (
        'Use Tor for this update?',
        'Updating over Tor may take longer. Turning Tor off switches all '
            'Vizor network requests to a direct connection.',
      ),
      SettingsUpdateDialog.torRouteBlocked: (
        'Software updates unavailable over Tor',
        'Vizor kept direct requests blocked. Retry updates in Settings, or '
            'turn off Tor and try the download again.',
      ),
      SettingsUpdateDialog.torStillOn: (
        "Couldn't turn off Tor",
        'Tor remains on, so Vizor kept the update blocked. Try again, or turn '
            'off Tor in Settings before downloading.',
      ),
      SettingsUpdateDialog.updatesUnavailable: (
        'Software updates unavailable',
        'Tor is off, but software updates are still unavailable. Retry '
            'updates in Settings before downloading.',
      ),
      SettingsUpdateDialog.downloadNotStarted: (
        "Couldn't start the update",
        "Couldn't complete the update. Try again.",
      ),
      SettingsUpdateDialog.downloadNotReady: (
        "Couldn't start the update",
        'This update is no longer ready to download. Check for updates again.',
      ),
      SettingsUpdateDialog.updaterOffTor: (
        "Couldn't start the update",
        'The software updater is not connected to Tor. Retry updates in '
            'Settings, or turn off Tor and try again.',
      ),
    };

    for (final entry in expected.entries) {
      await pumpUseCase(
        tester,
        buildSettingsUpdateDialogsGalleryCase,
        knobs: {'Dialog': settingsUpdateDialogLabel(entry.key)},
      );
      await _settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: settingsUpdateDialogLabel(entry.key),
      );
      expect(
        find.text(entry.value.$1),
        findsOneWidget,
        reason: settingsUpdateDialogLabel(entry.key),
      );
      expect(
        find.text(entry.value.$2),
        findsOneWidget,
        reason: settingsUpdateDialogLabel(entry.key),
      );
    }
    await disposeTree(tester);

    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsUpdateDialogsGalleryCase,
      label: 'Dialog',
      optionLabels: SettingsUpdateDialog.values
          .map(settingsUpdateDialogLabel)
          .toList(),
    );
  });

  testWidgets('settings screen mobile layout varies on all eight axes', (
    tester,
  ) async {
    // Both sheets present on the root navigator, above the capture boundary.
    await _expectSettledOptionsDistinctByText(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Sheet',
      optionLabels: SettingsMobileSheet.values
          .map(settingsMobileSheetLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    // The three registered fixtures differ only after their post-frame scroll
    // jump, and only on a phone-sized canvas — their frame follows the ambient
    // MediaQuery, so a desktop canvas fits the whole list with nothing to
    // scroll.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Scroll',
      optionLabels: SettingsMobileScroll.values
          .map(settingsMobileScrollLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
      canvasSize: const Size(393, 852),
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Account',
      optionLabels: SettingsAccount.values.map(settingsAccountLabel).toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    // The System group is well below the fold on a phone, so the rows that
    // live in it are swept with the list parked on the Explorer row.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Biometric',
      optionLabels: SettingsBiometric.values
          .map(settingsBiometricLabel)
          .toList(),
      otherKnobs: _mobileSettingsSystemGroupKnobs,
    );
    // The enabled flag only reads out on a device that has the hardware.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Biometric enabled',
      optionLabels: const ['true', 'false'],
      otherKnobs: {
        ..._mobileSettingsSystemGroupKnobs,
        'Biometric': settingsBiometricLabel(SettingsBiometric.faceId),
      },
    );
    final noHardware = await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(noHardware.knobs.keys, isNot(contains('Biometric enabled')));
    final withHardware = await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Biometric': settingsBiometricLabel(SettingsBiometric.faceId),
      },
    );
    expect(withHardware.knobs.keys, contains('Biometric enabled'));
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Keep awake',
      optionLabels: SettingsKeepAwake.values
          .map(settingsKeepAwakeLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Theme value',
      optionLabels: SettingsThemeValue.values
          .map(settingsThemeValueLabel)
          .toList(),
      otherKnobs: _mobileSettingsSystemGroupKnobs,
    );
    // The Tor card is the last thing above the version footer.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsScreenGalleryCase,
      label: 'Tor',
      optionLabels: SettingsMobileTor.values
          .map(settingsMobileTorLabel)
          .toList(),
      otherKnobs: {
        ..._mobileLayoutKnobs,
        'Scroll': settingsMobileScrollLabel(SettingsMobileScroll.footer),
      },
      canvasSize: const Size(393, 852),
    );
  });

  testWidgets('mobile settings biometric row names the device hardware', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._mobileSettingsSystemGroupKnobs,
        'Biometric': settingsBiometricLabel(SettingsBiometric.fingerprint),
      },
      canvasSize: const Size(393, 852),
    );
    for (var frame = 0; frame < 4; frame += 1) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Fingerprint'), findsOneWidget);

    // No biometric hardware hides the row entirely; the Account knob keeps the
    // case on the parameterized fixture.
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._mobileSettingsSystemGroupKnobs,
        'Biometric': settingsBiometricLabel(SettingsBiometric.none),
        'Account': settingsAccountLabel(SettingsAccount.keystone),
      },
      canvasSize: const Size(393, 852),
    );
    for (var frame = 0; frame < 4; frame += 1) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Fingerprint'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('mobile settings opens the theme and disable-biometric sheets', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Sheet': settingsMobileSheetLabel(SettingsMobileSheet.theme),
        'Theme value': settingsThemeValueLabel(SettingsThemeValue.light),
      },
      canvasSize: const Size(393, 852),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('mobile_theme_update')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_theme_option_light')),
      findsOneWidget,
    );

    // The sheet only exists for a device with biometric unlock on, so the
    // option supplies the hardware the Biometric knobs left out.
    await pumpUseCase(
      tester,
      buildSettingsScreenGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Sheet': settingsMobileSheetLabel(SettingsMobileSheet.disableBiometric),
        'Biometric': settingsBiometricLabel(SettingsBiometric.touchId),
      },
      canvasSize: const Size(393, 852),
    );
    await _settle(tester);
    expect(find.text('Turn off Touch ID unlock?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_biometric_disable_confirm')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('network privacy registers each layout\'s own knobs', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: _desktopLayoutKnobs,
    );
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'Status',
      'Target',
      'Saved route',
      'Software updates',
      'Surface',
    });

    final mobile = await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(mobile.knobs.keys.toSet(), {
      'Layout',
      'Status',
      'Target',
      'Saved route',
    });
    await disposeTree(tester);

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('network privacy desktop covers the whole provider matrix', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Status',
      optionLabels: SettingsTorStatus.values
          .map(settingsTorStatusLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    // The target only changes what a transition or a failure says, so it is
    // swept mid-connect.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Target',
      optionLabels: SettingsTorRoute.values.map(settingsTorRouteLabel).toList(),
      otherKnobs: {
        ..._desktopLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.connecting),
      },
    );
    // The saved route is what the toggle draws, so it only separates the
    // states where the target has already moved off it.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Saved route',
      optionLabels: SettingsTorRoute.values.map(settingsTorRouteLabel).toList(),
      otherKnobs: {
        ..._desktopLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.connecting),
        'Target': settingsTorRouteLabel(SettingsTorRoute.direct),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Software updates',
      optionLabels: SettingsSoftwareUpdates.values
          .map(settingsSoftwareUpdatesLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Surface',
      optionLabels: const ['true', 'false'],
      otherKnobs: _desktopLayoutKnobs,
    );

    // A pending Tor connection stays escapable; a pending switch to direct
    // has nothing to cancel toward.
    await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.connecting),
        'Target': settingsTorRouteLabel(SettingsTorRoute.direct),
      },
    );
    expect(find.text('Switching to direct…'), findsOneWidget);
    // Mid-switch the wallet still has the Tor route, so the toggle reads on.
    expect(
      find.byKey(const ValueKey('network_privacy_status_connecting_true')),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.failed),
        'Target': settingsTorRouteLabel(SettingsTorRoute.direct),
        'Saved route': settingsTorRouteLabel(SettingsTorRoute.direct),
      },
    );
    expect(find.text('Switch failed'), findsOneWidget);
    expect(find.text('Try direct connection'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: {
        ..._desktopLayoutKnobs,
        'Software updates': settingsSoftwareUpdatesLabel(
          SettingsSoftwareUpdates.unavailable,
        ),
      },
    );
    expect(
      find.text(
        'Network requests connect directly. '
        'Software updates are unavailable.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry updates'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('network privacy mobile card covers the whole matrix', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Status',
      optionLabels: SettingsTorStatus.values
          .map(settingsTorStatusLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Target',
      optionLabels: SettingsTorRoute.values.map(settingsTorRouteLabel).toList(),
      otherKnobs: {
        ..._mobileLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.connecting),
      },
    );
    // The saved route is what separates a blocked wallet from an unsaved
    // setting, and only a failure reads it.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      label: 'Saved route',
      optionLabels: SettingsTorRoute.values.map(settingsTorRouteLabel).toList(),
      otherKnobs: {
        ..._mobileLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.failed),
      },
    );

    await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.failed),
        'Saved route': settingsTorRouteLabel(SettingsTorRoute.direct),
      },
    );
    expect(find.text('Setting not saved'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsNetworkPrivacyGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Status': settingsTorStatusLabel(SettingsTorStatus.failed),
        'Target': settingsTorRouteLabel(SettingsTorRoute.direct),
      },
    );
    expect(find.text('Switch failed'), findsOneWidget);
    expect(find.text('Try direct connection'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('confirm access card covers subtitle, error and state', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsConfirmAccessCardGalleryCase,
      label: 'Subtitle',
      optionLabels: SettingsConfirmAccessFlow.values
          .map(settingsConfirmAccessFlowLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsConfirmAccessCardGalleryCase,
      label: 'Error',
      optionLabels: SettingsConfirmAccessError.values
          .map(settingsConfirmAccessErrorLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsConfirmAccessCardGalleryCase,
      label: 'State',
      optionLabels: SettingsConfirmAccessState.values
          .map(settingsConfirmAccessStateLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildSettingsConfirmAccessCardGalleryCase,
      knobs: {
        'Subtitle': settingsConfirmAccessFlowLabel(
          SettingsConfirmAccessFlow.uninstall,
        ),
        'Error': settingsConfirmAccessErrorLabel(
          SettingsConfirmAccessError.passwordPolicy,
        ),
      },
    );
    expect(find.text('To uninstall Vizor.'), findsOneWidget);
    expect(find.text(kWalletPasswordMinLengthMessage), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('pane backdrop swaps its artwork', (tester) async {
    // The PNG decodes asynchronously, so the pixels are identical inside a
    // widget test; the asset the widget asked for is the signal.
    for (final art in SettingsBackdropArt.values) {
      await pumpUseCase(
        tester,
        buildSettingsPaneBackdropGalleryCase,
        knobs: {'Art': settingsBackdropArtLabel(art)},
      );
      expect(tester.takeException(), isNull, reason: art.name);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        art.assetPath,
        reason: art.name,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('explorer covers both lanes and both templates', (tester) async {
    for (final layout in WbLayout.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSettingsExplorerGalleryCase,
        label: 'Choice',
        optionLabels: SettingsExplorerChoice.values
            .map(settingsExplorerChoiceLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsExplorerGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      otherKnobs: {
        'Choice': settingsExplorerChoiceLabel(SettingsExplorerChoice.preset),
      },
    );
  });

  testWidgets('settings sub-screen stage knobs cover every option', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsPassphraseGalleryCase,
      label: 'Stage',
      optionLabels: SettingsPassphraseStage.values
          .map(settingsPassphraseStageLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsViewingKeyGalleryCase,
      label: 'Stage',
      optionLabels: SettingsViewingKeyStage.values
          .map(settingsViewingKeyStageLabel)
          .toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
    // The uninstall done stage plays an entry animation before it differs from
    // the confirm stage.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsUninstallGalleryCase,
      label: 'Stage',
      optionLabels: SettingsUninstallCase.values
          .map(settingsUninstallCaseLabel)
          .toList(),
    );
  });

  testWidgets('uninstall reaches its gate and removal stages', (tester) async {
    await pumpUseCase(
      tester,
      buildSettingsUninstallGalleryCase,
      knobs: {'Stage': settingsUninstallCaseLabel(SettingsUninstallCase.gate)},
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('To uninstall Vizor.'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsUninstallGalleryCase,
      knobs: {
        'Stage': settingsUninstallCaseLabel(SettingsUninstallCase.removing),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Removing data...'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('link mobile varies on every preview-state axis', (tester) async {
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'Stage',
      optionLabels: SettingsLinkMobileStage.values
          .map(settingsLinkMobileStageLabel)
          .toList(),
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'Phase',
      optionLabels: SettingsLinkMobilePhase.values
          .map(settingsLinkMobilePhaseLabel)
          .toList(),
    );
    // The countdown and the QR only exist while the code is on screen.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'Remaining',
      optionLabels: SettingsLinkMobileRemaining.values
          .map(settingsLinkMobileRemainingLabel)
          .toList(),
      otherKnobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.qrReady),
      },
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'QR payload',
      optionLabels: SettingsLinkMobileQr.values
          .map(settingsLinkMobileQrLabel)
          .toList(),
      otherKnobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.qrReady),
      },
    );
    // The counts only read out once mobile has reported what it imported.
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'Counts',
      optionLabels: SettingsLinkMobileCounts.values
          .map(settingsLinkMobileCountsLabel)
          .toList(),
      otherKnobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.linked),
      },
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'Imported counts',
      optionLabels: SettingsLinkMobileImported.values
          .map(settingsLinkMobileImportedLabel)
          .toList(),
      otherKnobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.linked),
      },
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsLinkMobileGalleryCase,
      label: 'Error message',
      optionLabels: SettingsLinkMobileError.values
          .map(settingsLinkMobileErrorLabel)
          .toList(),
      otherKnobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.error),
      },
    );
  });

  testWidgets('link mobile shows preparing, singular counts and the error', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSettingsLinkMobileGalleryCase,
      knobs: {
        'Phase': settingsLinkMobilePhaseLabel(
          SettingsLinkMobilePhase.preparing,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Preparing'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsLinkMobileGalleryCase,
      knobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.linked),
        'Counts': settingsLinkMobileCountsLabel(SettingsLinkMobileCounts.one),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('1 account and 1 contact were imported on mobile.'),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildSettingsLinkMobileGalleryCase,
      knobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.linked),
        'Imported counts': settingsLinkMobileImportedLabel(
          SettingsLinkMobileImported.estimated,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Vizor Mobile was linked to this wallet.'),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildSettingsLinkMobileGalleryCase,
      knobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.error),
        'Error message': settingsLinkMobileErrorLabel(
          SettingsLinkMobileError.fallback,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Link unavailable'), findsOneWidget);
    expect(find.text('Could not prepare the mobile link.'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsLinkMobileGalleryCase,
      knobs: {
        'Phase': settingsLinkMobilePhaseLabel(SettingsLinkMobilePhase.qrReady),
        'Remaining': settingsLinkMobileRemainingLabel(
          SettingsLinkMobileRemaining.none,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Expires in 0:00'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('utility document knob switches the legal document', (
    tester,
  ) async {
    await _expectSettledOptionsDistinct(
      tester,
      buildUtilityDocumentGalleryCase,
      label: 'Document',
      optionLabels: UtilityDocument.values.map(utilityDocumentLabel).toList(),
      otherKnobs: _desktopLayoutKnobs,
    );
  });

  testWidgets('secret passphrase reveal varies on words, BIP39 and birthday', (
    tester,
  ) async {
    final revealKnobs = {
      ..._desktopLayoutKnobs,
      'Stage': settingsPassphraseStageLabel(SettingsPassphraseStage.reveal),
    };
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsPassphraseGalleryCase,
      label: 'Word count',
      optionLabels: SettingsPassphraseWords.values
          .map(settingsPassphraseWordsLabel)
          .toList(),
      otherKnobs: revealKnobs,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsPassphraseGalleryCase,
      label: 'BIP39 passphrase',
      optionLabels: SettingsPassphraseBip39.values
          .map(settingsPassphraseBip39Label)
          .toList(),
      otherKnobs: revealKnobs,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsPassphraseGalleryCase,
      label: 'Birthday',
      optionLabels: SettingsPassphraseBirthday.values
          .map(settingsPassphraseBirthdayLabel)
          .toList(),
      otherKnobs: revealKnobs,
    );

    // The 13th word only exists in the 24-word phrase.
    await pumpUseCase(
      tester,
      buildSettingsPassphraseGalleryCase,
      knobs: {
        ...revealKnobs,
        'Word count': settingsPassphraseWordsLabel(
          SettingsPassphraseWords.twelve,
        ),
      },
    );
    expect(find.text('puzzle'), findsNothing);
    expect(find.text('genuine'), findsOneWidget);

    // An unavailable birthday is the '-' row on both birthday lines.
    await pumpUseCase(
      tester,
      buildSettingsPassphraseGalleryCase,
      knobs: {
        ...revealKnobs,
        'Birthday': settingsPassphraseBirthdayLabel(
          SettingsPassphraseBirthday.unavailable,
        ),
      },
    );
    expect(find.text('-'), findsNWidgets(2));
    expect(find.text('$kSettingsPreviewBirthdayHeight'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('secret passphrase registers each layout\'s own knobs', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildSettingsPassphraseGalleryCase,
      knobs: _desktopLayoutKnobs,
    );
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'Stage',
      'Word count',
      'BIP39 passphrase',
      'Birthday',
    });

    // Mobile has no reveal fixture, so its only axis is the device biometric.
    final mobile = await pumpUseCase(
      tester,
      buildSettingsPassphraseGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(mobile.knobs.keys.toSet(), {'Layout', 'Biometric'});
    await disposeTree(tester);

    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsPassphraseGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('mobile passphrase gate names the device biometric', (
    tester,
  ) async {
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsPassphraseGalleryCase,
      label: 'Biometric',
      optionLabels: SettingsBiometric.values
          .map(settingsBiometricLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );

    for (final (biometric, label) in const [
      (SettingsBiometric.faceId, 'Sign in with Face ID'),
      (SettingsBiometric.touchId, 'Sign in with Touch ID'),
      (SettingsBiometric.fingerprint, 'Sign in with fingerprint'),
    ]) {
      await pumpUseCase(
        tester,
        buildSettingsPassphraseGalleryCase,
        knobs: {
          ..._mobileLayoutKnobs,
          'Biometric': settingsBiometricLabel(biometric),
        },
      );
      await tester.pump();
      expect(find.text(label), findsOneWidget, reason: biometric.name);
    }

    await pumpUseCase(
      tester,
      buildSettingsPassphraseGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Biometric': settingsBiometricLabel(SettingsBiometric.none),
      },
    );
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.textContaining('Sign in with'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('mobile passphrase gate reveals the in-memory fixture secret', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSettingsPassphraseGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(find.text('Enter Passcode'), findsOneWidget);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.bySemanticsLabel('Digit $digit'));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('caution'), findsWidgets);
    await disposeTree(tester);
  });

  testWidgets('viewing key registers each layout\'s own knobs', (tester) async {
    final desktop = await pumpUseCase(
      tester,
      buildSettingsViewingKeyGalleryCase,
      knobs: _desktopLayoutKnobs,
    );
    expect(desktop.knobs.keys.toSet(), {'Layout', 'Stage'});

    final mobile = await pumpUseCase(
      tester,
      buildSettingsViewingKeyGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(mobile.knobs.keys.toSet(), {'Layout', 'Stage', 'Biometric'});
    await disposeTree(tester);

    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsViewingKeyGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('mobile viewing key covers its gate and reveal', (tester) async {
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsViewingKeyGalleryCase,
      label: 'Stage',
      optionLabels: SettingsViewingKeyStage.values
          .map(settingsViewingKeyStageLabel)
          .toList(),
      otherKnobs: _mobileLayoutKnobs,
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsViewingKeyGalleryCase,
      label: 'Biometric',
      optionLabels: SettingsBiometric.values
          .map(settingsBiometricLabel)
          .toList(),
      otherKnobs: {
        ..._mobileLayoutKnobs,
        'Stage': settingsViewingKeyStageLabel(SettingsViewingKeyStage.gate),
      },
    );

    // The registered reveal fixture stays the mobile layout's default stage.
    await pumpUseCase(
      tester,
      buildSettingsViewingKeyGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(find.text('Viewing Key'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('endpoint covers both lanes, the current host and latency', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await _expectSettledOptionsDistinct(
        tester,
        buildSettingsEndpointGalleryCase,
        label: 'Current endpoint',
        optionLabels: SettingsEndpointCurrent.values
            .map(settingsEndpointCurrentLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
      await _expectSettledOptionsDistinct(
        tester,
        buildSettingsEndpointGalleryCase,
        label: 'Latency',
        optionLabels: SettingsEndpointLatency.values
            .map(settingsEndpointLatencyLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsEndpointGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // A custom host is the current endpoint without being a preset row.
    await pumpUseCase(
      tester,
      buildSettingsEndpointGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Current endpoint': settingsEndpointCurrentLabel(
          SettingsEndpointCurrent.customHost,
        ),
      },
    );
    await tester.pump();
    expect(
      find.textContaining('lwd.example.org', findRichText: true),
      findsWidgets,
    );

    // A preset endpoint opens on the list tab with its floating update bar;
    // a custom one opens the screen's custom tab instead.
    await pumpUseCase(
      tester,
      buildSettingsEndpointGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Current endpoint': settingsEndpointCurrentLabel(
          SettingsEndpointCurrent.defaultPreset,
        ),
      },
    );
    await tester.pump();
    expect(find.text('Update endpoint'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('change password covers the desktop and mobile credentials', (
    tester,
  ) async {
    await _expectSettledOptionsDistinct(
      tester,
      buildSettingsChangePasswordGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    await pumpUseCase(
      tester,
      buildSettingsChangePasswordGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Confirm your access'), findsOneWidget);

    Future<void> enterPasscode(String value) async {
      for (final digit in value.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    await enterPasscode('123456');
    expect(find.text('Set New Passcode'), findsOneWidget);
    await enterPasscode('654321');
    expect(find.text('Confirm Passcode'), findsOneWidget);
    await enterPasscode('654321');
    // The complete keypad flow reaches the in-memory change handler without
    // touching the platform AppSecureStore.
    expect(find.text('Enter Passcode'), findsNothing);
    expect(find.text('Navigated to /preview'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('utility documents vary on wallet and pane', (tester) async {
    // About always renders inside the shell, so both axes are swept on a
    // legal document.
    final legalKnobs = {
      ..._desktopLayoutKnobs,
      'Document': utilityDocumentLabel(UtilityDocument.terms),
    };
    await _expectSettledOptionsDistinct(
      tester,
      buildUtilityDocumentGalleryCase,
      label: 'Wallet',
      optionLabels: UtilityWallet.values.map(utilityWalletLabel).toList(),
      otherKnobs: legalKnobs,
    );
    await _expectSettledOptionsDistinct(
      tester,
      buildUtilityDocumentGalleryCase,
      label: 'Pane',
      optionLabels: UtilityPane.values.map(utilityPaneLabel).toList(),
      otherKnobs: legalKnobs,
    );

    // Wallet present keeps the back link on Home; absent sends it to Welcome.
    await pumpUseCase(
      tester,
      buildUtilityDocumentGalleryCase,
      knobs: {
        ...legalKnobs,
        'Wallet': utilityWalletLabel(UtilityWallet.absent),
      },
    );
    await tester.pump();
    expect(find.text('Welcome'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile about and legal switch documents', (tester) async {
    await _expectSettledOptionsDistinct(
      tester,
      buildUtilityDocumentGalleryCase,
      label: 'Document',
      optionLabels: UtilityDocument.values.map(utilityDocumentLabel).toList(),
      otherKnobs: _mobileLayoutKnobs,
    );

    await pumpUseCase(
      tester,
      buildUtilityDocumentGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(find.text('About Vizor Wallet'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildUtilityDocumentGalleryCase,
      knobs: {
        ..._mobileLayoutKnobs,
        'Document': utilityDocumentLabel(UtilityDocument.privacy),
      },
    );
    expect(find.text('Privacy Policy'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('about and legal registers each layout\'s own knobs', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildUtilityDocumentGalleryCase,
      knobs: _desktopLayoutKnobs,
    );
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'Document',
      'Wallet',
      'Pane',
    });

    // Mobile has neither the sidebar shell nor the full pane.
    final mobile = await pumpUseCase(
      tester,
      buildUtilityDocumentGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(mobile.knobs.keys.toSet(), {'Layout', 'Document'});
    await disposeTree(tester);

    await _expectSettledOptionsDistinct(
      tester,
      buildUtilityDocumentGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('previously unregistered settings fixtures are reachable', (
    tester,
  ) async {
    // These builders rendered only through figma_compare before the gallery;
    // each now sits behind a knob option.
    for (final scroll in SettingsMobileScroll.values) {
      await pumpUseCase(
        tester,
        buildSettingsScreenGalleryCase,
        knobs: {
          ..._mobileLayoutKnobs,
          'Scroll': settingsMobileScrollLabel(scroll),
        },
      );
      expect(tester.takeException(), isNull, reason: scroll.name);
    }
    expect(find.text('Settings'), findsWidgets);

    // The mobile viewing-key reveal is the mobile layout's default stage.
    await pumpUseCase(
      tester,
      buildSettingsViewingKeyGalleryCase,
      knobs: _mobileLayoutKnobs,
    );
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  testWidgets('custom endpoint panel varies on its provider axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsCustomEndpointPanelGalleryCase,
      label: 'Latency',
      optionLabels: SettingsCustomEndpointLatency.values
          .map(settingsCustomEndpointLatencyLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsCustomEndpointPanelGalleryCase,
      label: 'Endpoint',
      optionLabels: SettingsCustomEndpointPreset.values
          .map(settingsCustomEndpointPresetLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsCustomEndpointPanelGalleryCase,
      label: 'Close button',
      optionLabels: const ['true', 'false'],
    );

    // Only the default preset carries the '(Default)' suffix, and only a
    // measured sample prints a latency.
    await pumpUseCase(
      tester,
      buildSettingsCustomEndpointPanelGalleryCase,
      knobs: {
        'Endpoint': settingsCustomEndpointPresetLabel(
          SettingsCustomEndpointPreset.defaultPreset,
        ),
        'Latency': settingsCustomEndpointLatencyLabel(
          SettingsCustomEndpointLatency.measured,
        ),
      },
    );
    expect(find.textContaining('42ms'), findsOneWidget);
    expect(find.textContaining('(Default)'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSettingsCustomEndpointPanelGalleryCase,
      knobs: {
        'Endpoint': settingsCustomEndpointPresetLabel(
          SettingsCustomEndpointPreset.custom,
        ),
      },
    );
    expect(find.textContaining('(Default)'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('custom endpoint form prints its message line', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSettingsCustomEndpointFormGalleryCase,
      label: 'Input',
      optionLabels: SettingsCustomEndpointInput.values
          .map(settingsCustomEndpointInputLabel)
          .toList(),
    );

    // The message is whatever the production normalizer says for that input,
    // so a reworded validation error cannot drift from the gallery.
    for (final input in const [
      SettingsCustomEndpointInput.hasSpace,
      SettingsCustomEndpointInput.notHttps,
      SettingsCustomEndpointInput.badPort,
    ]) {
      final expected = settingsPreviewEndpointMessage(
        settingsCustomEndpointInputText(input),
      );
      expect(
        expected,
        isNotNull,
        reason: settingsCustomEndpointInputLabel(input),
      );
      await pumpUseCase(
        tester,
        buildSettingsCustomEndpointFormGalleryCase,
        knobs: {'Input': settingsCustomEndpointInputLabel(input)},
      );
      expect(
        find.text(expected!),
        findsOneWidget,
        reason: settingsCustomEndpointInputLabel(input),
      );
    }

    // The two accepted inputs print nothing.
    for (final input in const [
      SettingsCustomEndpointInput.empty,
      SettingsCustomEndpointInput.valid,
    ]) {
      expect(
        settingsPreviewEndpointMessage(settingsCustomEndpointInputText(input)),
        isNull,
        reason: settingsCustomEndpointInputLabel(input),
      );
    }
    await disposeTree(tester);
  });

  testWidgets('new badge renders its pill', (tester) async {
    await pumpUseCase(tester, buildSettingsNewBadgeGalleryCase);
    expect(find.text('New'), findsOneWidget);
    await disposeTree(tester);
  });

  /// Pumps past a post-frame opener and its route transition.
  Future<void> pumpSettingsScreen(WidgetTester tester, String layout) =>
      pumpUseCase(
        tester,
        buildSettingsScreenGalleryCase,
        knobs: {'Layout': layout},
        path: 'screens/settings/settings-screen/screen',
      );

  testWidgets('settings screen theme dialog applies an in-memory choice', (
    tester,
  ) async {
    await pumpSettingsScreen(tester, 'Desktop');
    await tester.tap(find.text('Theme').last);
    await _settle(tester);
    await tester.tap(find.text('Dark').last);
    await tester.tap(find.text('Update').last);
    await _settle(tester);
    expect(find.text('Dark'), findsWidgets);
  });

  testWidgets('settings screen about route stays inert and returns', (
    tester,
  ) async {
    await pumpSettingsScreen(tester, 'Desktop');
    final about = find.text('About Vizor');
    await tester.scrollUntilVisible(about, 300);
    await tester.tap(about);
    await _settle(tester);
    expect(
      find.text('Preview only: external links are disabled.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings_flow_about_back')));
    await _settle(tester);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('settings screen sign out stays in memory', (tester) async {
    await pumpSettingsScreen(tester, 'Desktop');
    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    expect(find.text('Signed out (preview)'), findsOneWidget);
    expect(find.textContaining('secure storage was changed'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings_flow_signed_out_back')),
    );
    await _settle(tester);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('mobile settings endpoint applies in memory', (tester) async {
    await pumpSettingsScreen(tester, 'Mobile');
    const endpointKey = ValueKey('mobile_settings_endpoint_row');
    await tester.scrollUntilVisible(find.byKey(endpointKey), 300);
    await tester.tap(find.byKey(endpointKey));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_endpoint_tab_custom')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_endpoint_custom_field')),
      'mobile-preview.example:443',
    );
    await tester.tap(find.byKey(const ValueKey('mobile_endpoint_update')));
    await _settle(tester);
    expect(find.textContaining('mobile-preview.example:443'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Back'));
    await _settle(tester);
    expect(find.byKey(endpointKey), findsOneWidget);
    expect(find.text('mobile-preview.example:443'), findsOneWidget);
  });

  testWidgets('mobile settings explorer applies in memory', (tester) async {
    await pumpSettingsScreen(tester, 'Mobile');
    const explorerKey = ValueKey('mobile_settings_explorer_row');
    await tester.scrollUntilVisible(find.byKey(explorerKey), 300);
    await tester.tap(find.byKey(explorerKey));
    await _settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_explorer_option_custom')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_explorer_custom_field')),
      'https://preview-explorer.example/tx/{txid}',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mobile_explorer_update')));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Back'));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(explorerKey));
    expect(find.text('preview-explorer.example'), findsOneWidget);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame += 1) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// The Layout knob every folded surface carries; the state knobs a layout
/// registers are only reachable once it is selected.
final Map<String, String> _desktopLayoutKnobs = {
  'Layout': wbLayoutLabel(WbLayout.desktop),
};

final Map<String, String> _mobileLayoutKnobs = {
  'Layout': wbLayoutLabel(WbLayout.mobile),
};

/// Parks the mobile settings list on the Explorer row, which is the only way
/// the System group (theme, biometric) is laid out at all on a phone.
final Map<String, String> _mobileSettingsSystemGroupKnobs = {
  ..._mobileLayoutKnobs,
  'Scroll': settingsMobileScrollLabel(SettingsMobileScroll.explorerRow),
};

/// [expectKnobOptionsRenderDistinctly] with extra frames before the
/// fingerprint, for fixtures that reach their state through a post-frame
/// callback, a scroll jump, or an entry animation.
Future<void> _expectSettledOptionsDistinct(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
  Size canvasSize = const Size(1600, 1200),
}) async {
  await _expectOptionsDistinct(
    tester,
    builder,
    label: label,
    optionLabels: optionLabels,
    otherKnobs: otherKnobs,
    canvasSize: canvasSize,
    signature: (tester) => useCaseFingerprint(tester),
  );
}

/// Same sweep keyed on the copy on screen, for fixtures whose state lands on a
/// navigator above the capture boundary and so never reaches the pixels.
Future<void> _expectSettledOptionsDistinctByText(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
}) async {
  await _expectOptionsDistinct(
    tester,
    builder,
    label: label,
    optionLabels: optionLabels,
    otherKnobs: otherKnobs,
    canvasSize: const Size(1600, 1200),
    signature: (tester) async {
      final texts =
          tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? '')
              .where((data) => data.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return texts.join('\n');
    },
  );
}

Future<void> _expectOptionsDistinct(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  required Map<String, String> otherKnobs,
  required Size canvasSize,
  required Future<String> Function(WidgetTester tester) signature,
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    await pumpUseCase(
      tester,
      builder,
      knobs: {...otherKnobs, label: option},
      canvasSize: canvasSize,
    );
    for (var frame = 0; frame < 4; frame += 1) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull, reason: '$label / $option');

    final key = await signature(tester);
    final duplicate = seen[key];
    expect(
      duplicate,
      isNull,
      reason:
          "'$label' options '$duplicate' and '$option' render identically — "
          'the knob has a dead option or a duplicated dispatch.',
    );
    seen[key] = option;
  }
  await disposeTree(tester);
}
