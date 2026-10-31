import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/private_transparent_recovery_config.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/account_edit_modal.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_screen.dart';
import 'package:zcash_wallet/src/features/settings/settings_platform.dart';
import 'package:zcash_wallet/src/features/settings/widgets/enhance_pir_privacy_control.dart';
import 'package:zcash_wallet/src/features/settings/widgets/near_swap_privacy_info.dart';
import 'package:zcash_wallet/src/features/settings/widgets/swap_history_check_control.dart';
import 'package:zcash_wallet/src/providers/swap_history_check_provider.dart';
import 'package:zcash_wallet/src/features/settings/widgets/network_privacy_control.dart';
import 'package:zcash_wallet/src/features/settings/widgets/private_queries_turn_off.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_cards_provider.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart'
    show ReceiveError, ReceiveErrorKind, SwapRecoveryStatus;
import 'package:zcash_wallet/src/providers/windows_update_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('private recovery is labelled experimental', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();
    expect(
      find.textContaining('Experimental.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('private queries always describes private transparent recovery', (
    tester,
  ) async {
    Future<String> description() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: EnhancePirPrivacyControl(
              enabled: true,
              onToggle: () {},
              transition: null,
            ),
          ),
        ),
      );
      return tester
          .widget<Text>(
            find.byKey(const ValueKey('settings_enhance_pir_description')),
          )
          .data!;
    }

    final defaultCopy = await description();
    expect(defaultCopy, kPrivateQueriesSettingsCopy);
  });

  test('uninstall setting is supported only on macOS and Linux', () {
    expect(settingsUninstallSupported(platform: TargetPlatform.macOS), isTrue);
    expect(settingsUninstallSupported(platform: TargetPlatform.linux), isTrue);
    expect(
      settingsUninstallSupported(platform: TargetPlatform.windows),
      isFalse,
    );
    expect(settingsUninstallSupported(platform: TargetPlatform.iOS), isFalse);
    expect(
      settingsUninstallSupported(platform: TargetPlatform.android),
      isFalse,
    );
  });

  testWidgets('settings rows show hover and focus states', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    expect(_rowBackgroundColor(tester, 'Password'), isNull);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('ZecBlock'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Password')));
    await tester.pump();

    expect(
      _rowBackgroundColor(tester, 'Password'),
      AppThemeData.light.colors.background.base,
    );

    final detectorFinder = find.ancestor(
      of: find.text('Password'),
      matching: find.byType(FocusableActionDetector),
    );
    expect(detectorFinder, findsOneWidget);

    final detector = tester.widget<FocusableActionDetector>(detectorFinder);
    detector.onShowFocusHighlight?.call(true);
    await tester.pump();

    expect(_hasFocusRing(tester), isTrue);
  });

  for (final kind in HardwareSignerKind.values) {
    testWidgets('${kind.name} account disables secret passphrase', (
      tester,
    ) async {
      final hardwareAccount = AccountState(
        accounts: [
          AccountInfo(
            uuid: 'ledger-account',
            name: 'Ledger account',
            order: 0,
            isHardware: true,
            hardwareSignerKind: kind,
          ),
        ],
        activeAccountUuid: 'ledger-account',
        activeAddress: 'u1ledgeraddress',
      );

      await tester.pumpWidget(_settingsHarness(accountState: hardwareAccount));
      await tester.pump();

      expect(find.text('Secret passphrase'), findsOneWidget);
      expect(find.text('Account details'), findsNothing);
      expect(
        find.ancestor(
          of: find.text('Secret passphrase'),
          matching: find.byType(FocusableActionDetector),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Secret passphrase'));
      await tester.pumpAndSettle();
      expect(find.text('secret passphrase route'), findsNothing);
    });
  }

  testWidgets('software account preserves secret passphrase navigation', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    expect(find.text('Secret passphrase'), findsOneWidget);
    expect(find.text('Account details'), findsNothing);

    await tester.tap(find.text('Secret passphrase'));
    await tester.pumpAndSettle();

    expect(find.text('secret passphrase route'), findsOneWidget);
  });

  testWidgets('Gift Cards waits for its data before opening', (tester) async {
    final cards = Completer<PaymentLinkCardsSnapshot>();
    await tester.pumpWidget(
      _settingsHarness(
        extraOverrides: [
          paymentLinkCardsLoaderProvider.overrideWithValue(() => cards.future),
        ],
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('settings_gift_cards_row'));
    expect(row, findsOneWidget);
    expect(
      tester
          .widgetList<AppIcon>(
            find.descendant(of: row, matching: find.byType(AppIcon)),
          )
          .first
          .name,
      AppIcons.giftCardOutline,
    );
    expect(find.text('My gift cards'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('My gift cards')).dy,
      lessThan(tester.getTopLeft(find.text('Link Vizor mobile')).dy),
    );

    await tester.tap(row);
    await tester.pump();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('payment links route with data'), findsNothing);

    cards.complete(const PaymentLinkCardsSnapshot(created: [], received: []));
    await tester.pumpAndSettle();

    expect(find.text('payment links route with data'), findsOneWidget);
  });

  testWidgets('Gift Cards opens without data when the load fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        extraOverrides: [
          paymentLinkCardsLoaderProvider.overrideWithValue(
            () => Future<PaymentLinkCardsSnapshot>.error(StateError('x')),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings_gift_cards_row')));
    await tester.pumpAndSettle();

    expect(find.text('payment links route without data'), findsOneWidget);
    expect(find.text('payment links route with data'), findsNothing);
  });

  testWidgets('Gift Cards does not navigate after leaving settings', (
    tester,
  ) async {
    final cards = Completer<PaymentLinkCardsSnapshot>();
    await tester.pumpWidget(
      _settingsHarness(
        extraOverrides: [
          paymentLinkCardsLoaderProvider.overrideWithValue(() => cards.future),
        ],
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('settings_gift_cards_row'));
    final router = GoRouter.of(tester.element(row));
    await tester.tap(row);
    await tester.pump();

    router.go('/home');
    await tester.pumpAndSettle();
    cards.complete(const PaymentLinkCardsSnapshot(created: [], received: []));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
    expect(find.textContaining('payment links route'), findsNothing);
  });

  testWidgets('Gift Cards drops a slow open once a modal takes over', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final cards = Completer<PaymentLinkCardsSnapshot>();
    await tester.pumpWidget(
      _settingsHarness(
        extraOverrides: [
          paymentLinkCardsLoaderProvider.overrideWithValue(() => cards.future),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings_gift_cards_row')));
    await tester.pump();

    // The pane stays interactive while the cards load, so the user can open
    // a modal the late navigation would replace.
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('System (Auto)'), findsOneWidget);

    cards.complete(const PaymentLinkCardsSnapshot(created: [], received: []));
    await tester.pumpAndSettle();

    expect(find.text('System (Auto)'), findsOneWidget);
    expect(find.textContaining('payment links route'), findsNothing);
  });

  testWidgets('busy wallet keeps the rename modal open for retry', (
    tester,
  ) async {
    final coordinator = LinuxKeyringCoordinator.testing(enabled: false);
    addTearDown(coordinator.dispose);
    // The private queries toggle holds the wallet while it drains.
    final release = Completer<void>();
    final toggle = coordinator.runMutation(() => release.future);
    await tester.binding.setSurfaceSize(const Size(1512, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _settingsHarness(
        extraOverrides: [
          linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Account name'));
    await tester.pumpAndSettle();
    // The rename modal covers the swap history bound field.
    await tester.enterText(find.byType(TextField).hitTestable(), 'Savings');
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AccountEditModal), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(
      find.text('Finish the current wallet operation before starting another.'),
      findsOneWidget,
    );
    expect(find.text("Couldn't update account."), findsNothing);
    release.complete();
    await toggle;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings sections are grouped Personal to Danger zone', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    double sectionTop(String title) => tester.getTopLeft(find.text(title)).dy;

    // Personal leads, and Privacy sits after System (not between Account
    // and System as it used to). The System block is located by its first
    // row because "System" is also the theme value.
    expect(sectionTop('Personal'), lessThan(sectionTop('Account')));
    expect(sectionTop('Account'), lessThan(sectionTop('Endpoint')));
    expect(sectionTop('Endpoint'), lessThan(sectionTop('Privacy')));
    expect(sectionTop('Privacy'), lessThan(sectionTop('Misc')));

    // Personal owns the gift cards and address book entries.
    expect(find.text('Address book'), findsOneWidget);
    expect(find.text('Contacts'), findsNothing);
    expect(sectionTop('My gift cards'), lessThan(sectionTop('Address book')));
    expect(sectionTop('Address book'), lessThan(sectionTop('Account')));

    // Account keeps the renamed mobile-link row.
    expect(find.text('Link Vizor mobile'), findsOneWidget);
    expect(find.text('Link mobile'), findsNothing);
  });

  testWidgets('uninstall setting is hidden on Windows', (tester) async {
    _overridePlatform(TargetPlatform.windows);

    try {
      await tester.pumpWidget(_settingsHarness());
      await tester.pump();

      expect(find.text('Danger zone'), findsNothing);
      expect(find.text('Uninstall Vizor'), findsNothing);
    } finally {
      _resetPlatformOverride();
    }
  });

  testWidgets('Settings update download uses the Tor privacy choice', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.windows);
    final downloads = <String>[];
    await tester.binding.setSurfaceSize(const Size(1512, 1100));

    try {
      await tester.pumpWidget(
        _settingsHarness(
          networkPrivacyState: const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
          ),
          extraOverrides: [
            windowsUpdateProvider.overrideWith(
              () => _RecordingWindowsUpdateNotifier(downloads),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Updates'));
      await tester.pump();
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Download update'));
      await tester.pumpAndSettle();

      expect(find.text('Use Tor for this update?'), findsOneWidget);
      expect(downloads, isEmpty);

      await tester.tap(find.widgetWithText(AppButton, 'Continue with Tor'));
      await tester.pumpAndSettle();

      expect(downloads, ['download']);
    } finally {
      await tester.binding.setSurfaceSize(null);
      _resetPlatformOverride();
    }
  });

  testWidgets('Settings preserves the underlying Windows update error', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.windows);
    await tester.binding.setSurfaceSize(const Size(1512, 1100));

    try {
      await tester.pumpWidget(
        _settingsHarness(
          extraOverrides: [
            windowsUpdateProvider.overrideWith(
              () => _FailedWindowsUpdateNotifier(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Updates'));
      await tester.pump();
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      expect(find.text('Signed feed verification failed.'), findsOneWidget);
      expect(
        find.text("Couldn't complete the update. Try again."),
        findsNothing,
      );
    } finally {
      await tester.binding.setSurfaceSize(null);
      _resetPlatformOverride();
    }
  });

  testWidgets('settings hides legal links while keeping About Vizor', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    expect(find.text('About Vizor'), findsOneWidget);
    expect(find.text('Privacy policy'), findsNothing);
    expect(find.text('Terms of usage'), findsNothing);
    expect(find.text('Use Tor'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(
      find.text(
        'Tor is off. Requests to the Zcash network, in-app services, and software updates connect directly.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings Tor control explains transitions and toggles once', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pump();

    expect(find.text('Connecting…'), findsOneWidget);
    expect(
      find.text(
        'New requests wait until the Tor connection is ready. Turn Tor off to '
        'stop connecting and use a direct connection.',
      ),
      findsOneWidget,
    );

    final statusIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('network_privacy_status_icon')),
    );
    expect(statusIcon.name, AppIcons.loader);
    // Not dimmed: the control is the way out of the wait, so it has to look
    // like something the user may act on.
    expect(_toggleTrackOpacity(tester), 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('network_privacy_toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('network_privacy_toggle')));
    await tester.pump();
    // The bootstrap runs to a three-minute deadline with every request failing
    // closed, and relaunching starts the same wait, so switching to direct has
    // to stay reachable for the whole of it.
    expect(calls, [false]);
  });

  test('the toggle offers an escape from a pending Tor connection', () {
    // Every state maps to exactly one action, and the connecting-to-Tor state
    // maps to an escape rather than to nothing.
    NetworkPrivacyToggleAction actionFor({
      required bool torEnabled,
      required NetworkPrivacyConnectionStatus status,
      bool? targetTorEnabled,
    }) => networkPrivacyToggleAction(
      NetworkPrivacyState(
        torEnabled: torEnabled,
        status: status,
        targetTorEnabled: targetTorEnabled,
      ),
    );

    expect(
      actionFor(torEnabled: false, status: NetworkPrivacyConnectionStatus.off),
      NetworkPrivacyToggleAction.enable,
    );
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connected,
      ),
      NetworkPrivacyToggleAction.disable,
    );
    // A startup activation publishes no explicit target, so the effective one
    // is the route already shown — which is the state a user relaunching into a
    // blocked network lands in.
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
      ),
      NetworkPrivacyToggleAction.cancelPendingTor,
    );
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: true,
      ),
      NetworkPrivacyToggleAction.cancelPendingTor,
    );
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: false,
      ),
      NetworkPrivacyToggleAction.none,
    );
  });

  test('cancelling a pending Tor connection asks for the direct route', () {
    expect(
      NetworkPrivacyToggleAction.cancelPendingTor.requestedTorEnabled,
      isFalse,
    );
    expect(NetworkPrivacyToggleAction.enable.requestedTorEnabled, isTrue);
    expect(NetworkPrivacyToggleAction.disable.requestedTorEnabled, isFalse);
    // Leaving a wait is not a second transition, and does not announce itself
    // as one.
    expect(
      NetworkPrivacyToggleAction.cancelPendingTor.semanticsLabel,
      'Stop connecting to Tor',
    );
    expect(NetworkPrivacyToggleAction.disable.semanticsLabel, 'Use Tor');
    expect(NetworkPrivacyToggleAction.none.isInteractive, isFalse);
  });

  testWidgets('a switch to direct cannot be driven back into Tor', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
          targetTorEnabled: false,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pump();

    // Nothing to escape from here: the route is already on its way to direct.
    expect(_toggleTrackOpacity(tester), lessThan(1));
    await tester.ensureVisible(
      find.byKey(const ValueKey('network_privacy_toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey('network_privacy_toggle')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('NEAR swap privacy explains itself', (tester) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();
    // Private queries are off, which doesn't affect it.
    expect(find.text(kNearSwapPrivacyOffCopy), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings_near_swap_privacy_sub_option')),
        matching: find.byKey(
          const ValueKey('settings_near_swap_privacy_toggle'),
        ),
      ),
      findsOneWidget,
      reason: 'shown as an option of Private queries',
    );

    final info = find.byKey(const ValueKey('settings_near_swap_privacy_info'));
    await tester.ensureVisible(info);
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('near_swap_privacy_info_dialog'));
    expect(dialog, findsOneWidget);
    expect(find.text(kNearSwapPrivacyInfoTitle), findsOneWidget);
    for (final paragraph in kNearSwapPrivacyInfoParagraphs) {
      expect(find.text(paragraph), findsOneWidget);
    }
    // It names what one-time Zcash addresses leave linkable, including the
    // reuse the design allows.
    expect(find.textContaining('still shared with NEAR'), findsOneWidget);
    expect(
      find.textContaining('expired unpaid can be used again'),
      findsOneWidget,
    );
    expect(find.textContaining('two devices'), findsOneWidget);
    expect(find.textContaining('new Zcash addresses'), findsNothing);
    expect(
      find.textContaining("Hardware wallet accounts don't use"),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('near_swap_privacy_info_close')),
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('NEAR swap privacy describes one-time addresses', (tester) async {
    await tester.pumpWidget(
      _settingsHarness(enhancePirEnabled: true, nearSwapPrivacyEnabled: true),
    );
    await tester.pump();
    expect(find.text(kNearSwapPrivacyOnCopy), findsOneWidget);
    expect(find.text(kNearSwapPrivacyOffCopy), findsNothing);
  });

  testWidgets('NEAR swap privacy off describes regular addresses', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness(enhancePirEnabled: true));
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('settings_near_swap_privacy_description'),
            ),
          )
          .data,
      kNearSwapPrivacyOffCopy,
    );
    expect(find.text(kNearSwapPrivacyOnCopy), findsNothing);
  });

  for (final (name, own) in [
    ('while it changes', kEnhancePirChangingMessage),
    ('when it fails', kEnhancePirUnchangedMessage),
  ]) {
    testWidgets('NEAR swap privacy feedback shows under its own row $name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _settingsHarness(
          nearSwapPrivacyEnabled: true,
          extraOverrides: [
            nearSwapPrivacyTransitionProvider.overrideWith(
              () => _Feedback(own),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('settings_near_swap_privacy_sub_option'),
          ),
          matching: find.text(own),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings_enhance_pir_transition')),
        findsNothing,
      );
    });
  }

  testWidgets('Check swap history is offered with NEAR swap privacy and '
      'Private queries off', (tester) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();
    final dialog = await _openNearSwapPrivacyInfo(tester);
    expect(dialog, findsOneWidget);
    expect(find.text(kNearSwapPrivacyInfoParagraphs.last), findsOneWidget);
    expect(_troubleshooting, findsOneWidget);
    expect(find.byType(SwapHistoryCheckControl), findsOneWidget);
  });

  testWidgets('Settings leaves Check swap history to the explanation', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness(nearSwapPrivacyEnabled: true));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings_near_swap_privacy_toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings_near_swap_privacy_info')),
      findsOneWidget,
    );
    expect(find.byType(SwapHistoryCheckControl), findsNothing);
    for (final key in [
      'settings_swap_history_explanation',
      'settings_check_swap_history',
      'settings_cancel_swap_history',
      'settings_check_swap_history_status',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
  });

  testWidgets('the NEAR swap privacy explanation ends with troubleshooting', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness(nearSwapPrivacyEnabled: true));
    await tester.pump();
    final dialog = await _openNearSwapPrivacyInfo(tester);
    final section = find.descendant(of: dialog, matching: _troubleshooting);
    expect(section, findsOneWidget);
    // In the scrolling body, so a short window can still reach it.
    expect(
      find.descendant(
        of: find.descendant(
          of: dialog,
          matching: find.byType(SingleChildScrollView),
        ),
        matching: section,
      ),
      findsOneWidget,
    );
    for (final text in [
      kNearSwapPrivacyTroubleshootingTitle,
      kNearSwapPrivacyTroubleshootingCopy,
      kSwapHistoryCheckExplanation,
    ]) {
      expect(
        find.descendant(of: section, matching: find.text(text)),
        findsOneWidget,
      );
    }
    for (final key in [
      'settings_swap_history_explanation',
      'settings_check_swap_history',
      'settings_check_swap_history_status',
    ]) {
      expect(
        find.descendant(of: section, matching: find.byKey(ValueKey(key))),
        findsOneWidget,
        reason: key,
      );
    }
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(section).dy,
      greaterThan(
        tester.getBottomLeft(find.text(kNearSwapPrivacyInfoParagraphs.last)).dy,
      ),
      reason: 'after the explanation',
    );
  });

  testWidgets('a running history check survives closing the explanation', (
    tester,
  ) async {
    var begun = 0;
    final polls = <Completer<SwapRecoveryStatus>>[];
    await tester.pumpWidget(
      _settingsHarness(
        nearSwapPrivacyEnabled: true,
        extraOverrides: [
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async => begun++,
              cancel: () async {},
              status: () {
                final poll = Completer<SwapRecoveryStatus>();
                polls.add(poll);
                return poll.future;
              },
              pollInterval: Duration.zero,
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await _openNearSwapPrivacyInfo(tester);
    final start = find.byKey(const ValueKey('settings_check_swap_history'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(begun, 1);
    await _closeNearSwapPrivacyInfo(tester);
    expect(find.byType(SwapHistoryCheckControl), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(
        find.byKey(const ValueKey('settings_near_swap_privacy_sub_option')),
      ),
    );
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.checking);

    final status = find.byKey(
      const ValueKey('settings_check_swap_history_status'),
    );
    await _openNearSwapPrivacyInfo(tester);
    expect(
      tester.widget<Text>(status).data,
      swapHistoryCheckStatus(SwapHistoryCheck.checking),
    );
    expect(
      find.byKey(const ValueKey('settings_cancel_swap_history')),
      findsOneWidget,
    );
    await _closeNearSwapPrivacyInfo(tester);

    // The check finishes while the explanation is closed.
    for (final poll in polls) {
      poll.complete(_idleRecovery);
    }
    await tester.pumpAndSettle();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
    expect(begun, 1);
    await _openNearSwapPrivacyInfo(tester);
    expect(
      tester.widget<Text>(status).data,
      swapHistoryCheckStatus(SwapHistoryCheck.done),
    );
    expect(
      find.byKey(const ValueKey('settings_cancel_swap_history')),
      findsNothing,
    );
  });

  testWidgets('NEAR swap privacy is hidden while swaps are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        nearSwapPrivacyEnabled: true,
        extraOverrides: [swapFeatureEnabledProvider.overrideWithValue(false)],
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings_near_swap_privacy_sub_option')),
      findsNothing,
    );
    expect(find.byType(SwapHistoryCheckControl), findsNothing);
  });

  testWidgets('Check swap history asks for an update the service needs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        nearSwapPrivacyEnabled: true,
        extraOverrides: [
          swapRecoveryUpdateRequiredProvider.overrideWith((ref) async => true),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async {},
              status: () async => _idleRecovery,
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await _openNearSwapPrivacyInfo(tester);
    await tester.pump();
    final button = find.byKey(const ValueKey('settings_check_swap_history'));
    await tester.ensureVisible(button);
    expect(find.text(kSwapRecoveryUpdateMessage), findsOneWidget);
    expect(tester.widget<AppButton>(button).onPressed, isNull);
  });

  testWidgets('an interrupted history check still offers pause', (
    tester,
  ) async {
    var paused = false;
    // The wallet saves the job, then the round fails.
    var saved = false;
    SwapRecoveryStatus wallet() => SwapRecoveryStatus(
      roundDue: false,
      awaitingAdmission: false,
      checkingHistory: saved && !paused,
      manualCheckActive: saved && !paused,
      upgradeRequired: false,
    );
    await tester.pumpWidget(
      _settingsHarness(
        nearSwapPrivacyEnabled: true,
        extraOverrides: [
          swapRecoveryStatusReaderProvider.overrideWithValue(
            () async => wallet(),
          ),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {
                saved = true;
                throw const ReceiveError(
                  message: 'lookup failed after job was saved',
                  kind: ReceiveErrorKind.other,
                  historyStarted: true,
                );
              },
              cancel: () async {
                paused = true;
              },
              status: () async => wallet(),
            ),
          ),
        ],
      ),
    );
    await _openNearSwapPrivacyInfo(tester);
    final start = find.byKey(const ValueKey('settings_check_swap_history'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    final pause = find.byKey(const ValueKey('settings_cancel_swap_history'));
    expect(pause, findsOneWidget);
    await tester.ensureVisible(pause);
    await tester.tap(pause);
    await tester.pumpAndSettle();
    expect(paused, isTrue);
    expect(
      find.text(swapHistoryCheckStatus(SwapHistoryCheck.paused)),
      findsOneWidget,
    );
    // Let the stopped watch's last poll interval run out.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('Check swap history checks everything, pauses and resumes', (
    tester,
  ) async {
    var begun = 0;
    final polls = <Completer<SwapRecoveryStatus>>[];
    var paused = 0;
    await tester.pumpWidget(
      _settingsHarness(
        nearSwapPrivacyEnabled: true,
        extraOverrides: [
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async => begun++,
              cancel: () async => paused++,
              status: () {
                final poll = Completer<SwapRecoveryStatus>();
                polls.add(poll);
                return poll.future;
              },
              pollInterval: Duration.zero,
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await _openNearSwapPrivacyInfo(tester);
    expect(find.text(kSwapHistoryCheckExplanation), findsOneWidget);
    final start = find.byKey(const ValueKey('settings_check_swap_history'));
    final status = find.byKey(
      const ValueKey('settings_check_swap_history_status'),
    );
    expect(
      tester.widget<Text>(status).data,
      swapHistoryCheckStatus(SwapHistoryCheck.idle),
    );
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(begun, 1);
    expect(
      tester.widget<Text>(status).data,
      swapHistoryCheckStatus(SwapHistoryCheck.checking),
    );

    final pause = find.byKey(const ValueKey('settings_cancel_swap_history'));
    await tester.ensureVisible(pause);
    await tester.tap(pause);
    await tester.pumpAndSettle();
    expect(paused, 1);
    expect(
      tester.widget<Text>(status).data,
      swapHistoryCheckStatus(SwapHistoryCheck.paused),
    );

    final earlierPolls = polls.length;
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(begun, 2);
    // The resumed check polls once its zero-length interval elapses.
    await tester.pump(const Duration(milliseconds: 1));
    expect(polls.length, earlierPolls + 1);
    for (final poll in polls) {
      poll.complete(_idleRecovery);
    }
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(status).data,
      swapHistoryCheckStatus(SwapHistoryCheck.done),
    );
  });

  testWidgets('NEAR swap privacy names the hardware account exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        enhancePirEnabled: true,
        accountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'keystone-account',
              name: 'Keystone account',
              order: 0,
              isHardware: true,
            ),
          ],
          activeAccountUuid: 'keystone-account',
          activeAddress: 'u1keystoneaddress',
        ),
      ),
    );
    await tester.pump();
    expect(find.text(kNearSwapPrivacyHardwareCopy), findsOneWidget);
    expect(find.text(kNearSwapPrivacyOnCopy), findsNothing);
    // Hardware accounts have no one-time keys to check.
    expect(
      find.byKey(const ValueKey('settings_check_swap_history')),
      findsNothing,
    );
  });

  testWidgets('connected Tor state describes Vizor and external app routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Connected'), findsOneWidget);
    expect(
      find.text(
        'Vizor’s network requests go through Tor. Links opened in other apps '
        'use those apps’ network settings.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('network_privacy_status_icon')),
      findsNothing,
    );
    expect(_toggleTrackOpacity(tester), 1);

    final torIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('network_privacy_tor_icon')),
    );
    expect(torIcon.name, AppIcons.tor);
    expect(torIcon.size, 20);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('network_privacy_toggle_track')),
      ),
      const Size(44, 20),
    );
    expect(find.text('Advanced'), findsNothing);
    expect(find.text('Private queries'), findsOneWidget);
    expect(find.text('NEAR swap privacy'), findsOneWidget);
    final swapToggle = tester.widget<PrivacyToggle>(
      find.byKey(const ValueKey('settings_near_swap_privacy_toggle')),
    );
    // Off, but Private queries being off doesn't stop turning it on.
    expect(swapToggle.enabled, isFalse);
    expect(swapToggle.onToggle, isNotNull);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('settings_enhance_pir_toggle_track')),
      ),
      tester.getSize(
        find.byKey(const ValueKey('network_privacy_toggle_track')),
      ),
    );

    final status = tester.widget<Text>(
      find.byKey(const ValueKey('network_privacy_status_connected_true')),
    );
    expect(status.style?.fontSize, 14);
    expect(status.style?.fontWeight, FontWeight.w400);
    expect(status.style?.height, 16 / 14);
    expect(status.style?.color, AppThemeData.light.colors.text.brandCrimson);

    final description = tester.widget<Text>(
      find.byKey(const ValueKey('network_privacy_description_connected_true')),
    );
    expect(description.style?.fontSize, 14);
    expect(description.style?.fontWeight, FontWeight.w400);
    expect(description.style?.height, 21 / 14);
    expect(description.style?.color, AppThemeData.light.colors.text.accent);
  });

  testWidgets('Linux Tor copy assigns external traffic to the other app', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.linux);
    try {
      await tester.pumpWidget(
        _settingsHarness(
          networkPrivacyState: const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Vizor’s network requests go through Tor. Links opened in other apps '
          'use those apps’ network settings.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('software updates use Tor'), findsNothing);
    } finally {
      _resetPlatformOverride();
    }
  });

  testWidgets('private queries are hidden off mainnet', (tester) async {
    await tester.pumpWidget(
      _settingsHarness(network: 'test', enhancePirEnabled: true),
    );
    await tester.pump();

    expect(find.text('Private queries'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings_enhance_pir_toggle')),
      findsNothing,
    );
  });

  group('off mainnet, where private queries are unavailable', () {
    testWidgets('a public wallet shows no private queries control', (
      tester,
    ) async {
      await tester.pumpWidget(_settingsHarness(network: 'test'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings_enhance_pir_toggle')),
        findsNothing,
      );
    });

    for (final (reason, overrides) in <(String, List<Override>)>[
      (
        'an unfinished opt-out',
        <Override>[
          transparentPolicyStartupProvider.overrideWithValue(
            const TransparentPolicyStartup(optOutPending: true),
          ),
        ],
      ),
      (
        'a durably private wallet',
        <Override>[
          walletTransparentPrivateProvider.overrideWith(_PrivateWallet.new),
        ],
      ),
    ]) {
      testWidgets('$reason uses the single private queries toggle', (
        tester,
      ) async {
        final enhancePir = _RecordingToggle(false);
        await tester.binding.setSurfaceSize(const Size(1512, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _settingsHarness(
            network: 'test',
            extraOverrides: [
              enhancePirProvider.overrideWith(() => enhancePir),
              ...overrides,
            ],
          ),
        );
        await tester.pump();

        // The same toggle is available while the wallet remains private.
        expect(
          find.byKey(const ValueKey('settings_enhance_pir_toggle')),
          findsOneWidget,
        );
        final button = find.byKey(
          const ValueKey('settings_enhance_pir_toggle'),
        );
        expect(button, findsOneWidget);
        expect(find.text('Finish turning off'), findsNothing);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('settings_enhance_pir_status')),
              )
              .data,
          'On',
        );
        await tester.ensureVisible(button);

        // Turning off sends transparent lookups to the server, so it asks.
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(_turnOffDialog, findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('private_queries_turn_off_cancel')),
        );
        await tester.pumpAndSettle();
        expect(_turnOffDialog, findsNothing);
        expect(enhancePir.toggles, 0);

        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('private_queries_turn_off_confirm')),
        );
        await tester.pumpAndSettle();
        expect(enhancePir.toggles, 1);
      });
    }
  });

  group('turning private queries off', () {
    testWidgets('overlapping confirmations both turn private queries off', (
      tester,
    ) async {
      final enhancePir = _RecordingToggle(true);
      final confirmations = <Completer<bool>>[];
      await tester.binding.setSurfaceSize(const Size(1512, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _settingsHarness(
          enhancePirEnabled: true,
          extraOverrides: [
            enhancePirProvider.overrideWith(() => enhancePir),
            privateQueriesTurnOffConfirmerProvider.overrideWithValue((_) {
              final result = Completer<bool>();
              confirmations.add(result);
              return result.future;
            }),
          ],
        ),
      );
      await tester.pump();
      final toggle = find.byKey(const ValueKey('settings_enhance_pir_toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
      expect(confirmations, hasLength(2));

      confirmations.first.complete(true);
      await tester.pumpAndSettle();
      confirmations.last.complete(true);
      await tester.pumpAndSettle();

      expect(enhancePir.requests, [false, false]);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings_enhance_pir_status')),
            )
            .data,
        'Off',
      );
    });

    Future<_RecordingToggle> pumpToggle(
      WidgetTester tester, {
      required bool enabled,
      bool walletPrivate = false,
    }) async {
      final enhancePir = _RecordingToggle(enabled);
      await tester.binding.setSurfaceSize(const Size(1512, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _settingsHarness(
          enhancePirEnabled: enabled,
          extraOverrides: [
            enhancePirProvider.overrideWith(() => enhancePir),
            if (walletPrivate)
              walletTransparentPrivateProvider.overrideWith(_PrivateWallet.new),
          ],
        ),
      );
      await tester.pump();
      final toggle = find.byKey(const ValueKey('settings_enhance_pir_toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      return enhancePir;
    }

    testWidgets('a private wallet asks first and names what is sent', (
      tester,
    ) async {
      final enhancePir = await pumpToggle(
        tester,
        enabled: true,
        walletPrivate: true,
      );
      expect(_turnOffDialog, findsOneWidget);
      expect(find.text(kPrivateQueriesTurnOffTitle), findsOneWidget);
      expect(find.text(kPrivateQueriesTurnOffBody), findsOneWidget);
      expect(find.text(kPrivateQueriesTurnOffDisclosure), findsOneWidget);
      expect(
        kPrivateQueriesTurnOffDisclosure,
        allOf(
          contains('every transparent address of every account'),
          contains('IDs of transactions private recovery found'),
          contains('without Tor, to your IP address'),
        ),
      );
      expect(
        kPrivateQueriesTurnOffBody,
        'Vizor will rebuild your transparent history publicly, allowing the '
        'server to learn all your addresses.',
      );

      await tester.tap(
        find.byKey(const ValueKey('private_queries_turn_off_cancel')),
      );
      await tester.pumpAndSettle();
      expect(_turnOffDialog, findsNothing);
      expect(enhancePir.toggles, 0);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings_enhance_pir_status')),
            )
            .data,
        'On',
      );

      await tester.tap(
        find.byKey(const ValueKey('settings_enhance_pir_toggle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('private_queries_turn_off_confirm')),
      );
      await tester.pumpAndSettle();
      expect(enhancePir.toggles, 1);
    });

    testWidgets(
      'an existing wallet asks before its first private balance read',
      (tester) async {
        // Private queries on mainnet recover transparent funds privately, so
        // turning them off discloses even before the policy is reported.
        final enhancePir = await pumpToggle(tester, enabled: true);
        expect(_turnOffDialog, findsOneWidget);
        expect(enhancePir.toggles, 0);
      },
    );

    testWidgets('turning private queries on never asks', (tester) async {
      final enhancePir = await pumpToggle(
        tester,
        enabled: false,
        walletPrivate: false,
      );
      expect(_turnOffDialog, findsNothing);
      expect(enhancePir.toggles, 1);
    });
  });

  testWidgets('Tor stays effective while switching to direct', (tester) async {
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
          targetTorEnabled: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Switching to direct…'), findsOneWidget);
    expect(
      find.text(
        'Vizor is switching network requests and software updates to a direct connection.',
      ),
      findsOneWidget,
    );

    final statusIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('network_privacy_status_icon')),
    );
    expect(statusIcon.name, AppIcons.loader);
    expect(_toggleTrackOpacity(tester), lessThan(1));
  });

  testWidgets('Tor update-route failure remains visible after the toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
          softwareUpdatesAvailable: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Vizor’s network requests go through Tor, but software updates are '
        'unavailable.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry updates'), findsOneWidget);
  });

  testWidgets('failed Tor state offers retry and direct connection', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
          error: 'bootstrap failed',
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pump();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(
      find.text('Direct requests remain blocked. Try again or turn off Tor.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(calls, [true]);

    await tester.ensureVisible(
      find.byKey(const ValueKey('network_privacy_toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('network_privacy_toggle')));
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets('uninstall setting is shown on macOS and Linux', (tester) async {
    try {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
        _overridePlatform(platform);

        await tester.pumpWidget(_settingsHarness());
        await tester.pump();

        expect(find.text('Danger zone'), findsOneWidget);
        expect(find.text('Uninstall Vizor'), findsOneWidget);
      }
    } finally {
      _resetPlatformOverride();
    }
  });
}

void _overridePlatform(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
}

void _resetPlatformOverride() {
  debugDefaultTargetPlatformOverride = null;
}

/// Finds the troubleshooting section of the NEAR swap privacy explanation.
final _troubleshooting = find.byKey(
  const ValueKey('near_swap_privacy_troubleshooting'),
);

/// Opens the NEAR swap privacy explanation from its info button in Settings
/// and finds the dialog.
Future<Finder> _openNearSwapPrivacyInfo(WidgetTester tester) async {
  final info = find.byKey(const ValueKey('settings_near_swap_privacy_info'));
  await tester.ensureVisible(info);
  await tester.pumpAndSettle();
  await tester.tap(info);
  await tester.pumpAndSettle();
  return find.byKey(const ValueKey('near_swap_privacy_info_dialog'));
}

/// Closes the NEAR swap privacy explanation with its Close button.
Future<void> _closeNearSwapPrivacyInfo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('near_swap_privacy_info_close')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('near_swap_privacy_info_dialog')),
    findsNothing,
  );
}

Widget _settingsHarness({
  NetworkPrivacyState networkPrivacyState = const NetworkPrivacyState.off(),
  List<bool>? networkPrivacyCalls,
  List<Override> extraOverrides = const [],
  AccountState? accountState,
  String network = 'main',
  bool enhancePirEnabled = false,
  bool nearSwapPrivacyEnabled = false,
}) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/secret-passphrase',
        builder: (_, _) => const Text('secret passphrase route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/payment-links',
        builder: (_, state) => Text(
          state.extra is PaymentLinkCardsSnapshot
              ? 'payment links route with data'
              : 'payment links route without data',
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _settingsBootstrap(
          accountState ?? _bootstrap.initialAccountState,
          network: network,
          enhancePirEnabled: enhancePirEnabled,
          nearSwapPrivacyEnabled: nearSwapPrivacyEnabled,
        ),
      ),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      networkPrivacyProvider.overrideWith(
        () => _FakeNetworkPrivacyNotifier(
          networkPrivacyState,
          networkPrivacyCalls ?? <bool>[],
        ),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

/// Setting feedback fixed at `message`.
class _Feedback extends EnhancePirTransitionNotifier {
  _Feedback(this.message);

  final String? message;

  @override
  String? build() => message;
}

class _FakeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _FakeNetworkPrivacyNotifier(this.initialState, this.calls);

  final NetworkPrivacyState initialState;
  final List<bool> calls;

  @override
  NetworkPrivacyState build() => initialState;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    calls.add(enabled);
  }
}

class _RecordingWindowsUpdateNotifier extends WindowsUpdateNotifier {
  _RecordingWindowsUpdateNotifier(this.downloads);

  final List<String> downloads;

  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.available,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 0,
    pendingRestart: false,
    torProxyReady: true,
    message: '',
  );

  @override
  Future<WindowsUpdateDownloadResult> downloadUpdate() async {
    downloads.add('download');
    return const WindowsUpdateDownloadResult.started();
  }
}

class _FailedWindowsUpdateNotifier extends WindowsUpdateNotifier {
  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.failed,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 0,
    pendingRestart: false,
    torProxyReady: true,
    message: 'Signed feed verification failed.',
  );
}

final _bootstrap = _bootstrapForNetwork('main');

AppBootstrapState _bootstrapForNetwork(
  String network, {
  bool enhancePirEnabled = false,
}) => AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1settingsscreenaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: network,
  rpcEndpointConfig: defaultRpcEndpointConfig(network),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
  enhancePirEnabled: enhancePirEnabled,
);

AppBootstrapState _settingsBootstrap(
  AccountState accountState, {
  String network = 'main',
  bool enhancePirEnabled = false,
  bool nearSwapPrivacyEnabled = false,
}) => AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: network,
  rpcEndpointConfig: defaultRpcEndpointConfig(network),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
  enhancePirEnabled: enhancePirEnabled,
  nearSwapPrivacyEnabled: nearSwapPrivacyEnabled,
);

double _toggleTrackOpacity(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(
          of: find.byKey(const ValueKey('network_privacy_toggle_track')),
          matching: find.byType(Opacity),
        )
        .first,
  );
  return opacity.opacity;
}

Color? _rowBackgroundColor(WidgetTester tester, String label) {
  final container = tester.widget<Container>(_rowContainerFinder(label));
  return (container.decoration as BoxDecoration?)?.color;
}

Finder _rowContainerFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.padding ==
              const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
    ),
  );
}

bool _hasFocusRing(WidgetTester tester) {
  final focusRing = find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    if (border is! Border) return false;
    return border.top.color == AppThemeData.light.colors.state.focusRing &&
        border.top.width == 2;
  });
  return focusRing.evaluate().isNotEmpty;
}

final _turnOffDialog = find.byKey(
  const ValueKey('private_queries_turn_off_dialog'),
);

class _RecordingToggle extends EnhancePirNotifier {
  _RecordingToggle(this.enabled);

  final bool enabled;
  int toggles = 0;
  final requests = <bool>[];

  @override
  bool build() => enabled;

  @override
  Future<void> set(bool enabled) async {
    toggles++;
    requests.add(enabled);
    state = enabled;
  }
}

class _PrivateWallet extends WalletTransparentPrivateNotifier {
  @override
  bool build() => true;
}

/// A wallet with no unfinished history check and no update needed.
const _idleRecovery = SwapRecoveryStatus(
  roundDue: false,
  awaitingAdmission: false,
  checkingHistory: false,
  manualCheckActive: false,
  upgradeRequired: false,
);
