import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart' show buildIncomingLinkHostForTest;
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_provider.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_secret_operation_guard.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart'
    show SecretPassphraseRevealWarningCard;
import 'package:zcash_wallet/src/features/settings/screens/settings_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_host.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse '
    'access accident account accuse achieve acid acoustic acquire across act '
    'action actor actress actual';
const _bip39Passphrase = 'correct horse battery staple with extra words';

const _accountState = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1currentaddress',
);

void main() {
  for (final completeBackup in [false, true]) {
    for (final failSave in [false, true]) {
      testWidgets(
        'incoming payment request waits for backup ${completeBackup ? 'completion' : 'deferral'} ${failSave ? 'failure' : 'success'}',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1080, 720));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final privacy = SensitivePrivacyOverlayController(
            initiallySafe: true,
          );
          addTearDown(privacy.dispose);
          final incomingUris = _FakeIncomingUriService();
          addTearDown(incomingUris.dispose);
          final account = _FakeAccountNotifier(backupPending: true)
            ..backupSave = Completer<void>();
          await tester.pumpWidget(
            _harness(
              privacyController: privacy,
              accountNotifier: () => account,
              showBackupIntro: !completeBackup,
              incomingUris: incomingUris,
            ),
          );
          await tester.pumpAndSettle();
          if (completeBackup) {
            await tester.enterText(find.byType(EditableText), 'Correct123!');
            await tester.pump();
            await tester.tap(find.bySemanticsLabel('Confirm password'));
            await tester.pumpAndSettle();
          }
          final container = ProviderScope.containerOf(
            tester.element(find.byType(SettingsSeedPhraseScreen)),
            listen: false,
          );
          final action = find.byKey(
            ValueKey(
              completeBackup
                  ? 'desktop_seed_backed_up'
                  : 'desktop_seed_backup_remind_later',
            ),
          );
          await tester.tap(action);
          await tester.pump();
          incomingUris.emit('zcash:u1recipient');
          await tester.pumpAndSettle();
          expect(find.byType(PaymentRequestSurface), findsNothing);
          expect(find.text('Enter amount'), findsNothing);
          expect(find.byType(SettingsSeedPhraseScreen), findsOneWidget);
          expect(container.read(paymentUriBusySurfaceProvider), 1);
          expect(container.read(paymentUriPrefillProvider), isNotNull);

          if (failSave) {
            account.backupSave!.completeError(StateError('late write failure'));
          } else {
            account.backupSave!.complete();
          }
          await tester.pumpAndSettle();
          expect(container.read(paymentUriBusySurfaceProvider), 0);
          expect(container.read(paymentUriPrefillProvider), isNull);
          expect(find.byType(PaymentRequestSurface), findsOneWidget);
          if (failSave) {
            expect(find.byType(SettingsSeedPhraseScreen), findsOneWidget);
            expect(find.text('Couldn’t save that. Try again.'), findsOneWidget);
            if (completeBackup) expect(find.text('abandon'), findsOneWidget);
            // Dismiss the request through the pane scrim, then retry the write.
            await tester.tapAt(const Offset(300, 690));
            await tester.pumpAndSettle();
            expect(find.byType(PaymentRequestSurface), findsNothing);
            account.backupSave = Completer<void>();
            await tester.tap(action);
            await tester.pump();
            expect(container.read(paymentUriBusySurfaceProvider), 1);
            account.backupSave!.complete();
            await tester.pumpAndSettle();
            expect(container.read(paymentUriBusySurfaceProvider), 0);
            expect(find.text('home-destination'), findsOneWidget);
          } else {
            expect(find.text('home-destination'), findsOneWidget);
            await tester.tap(find.widgetWithText(AppButton, 'Enter amount'));
            await tester.pumpAndSettle();
            expect(find.text('send-destination'), findsOneWidget);
          }
          expect(completeBackup ? account.completed : account.snoozed, [
            'account-2',
          ]);
        },
      );
    }
  }

  testWidgets('an unmounted backup write releases only its own URI hold', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
    addTearDown(privacy.dispose);
    final account = _FakeAccountNotifier(backupPending: true)
      ..backupSave = Completer<void>();
    await tester.pumpWidget(
      _harness(
        privacyController: privacy,
        accountNotifier: () => account,
        showBackupIntro: true,
      ),
    );
    await tester.pumpAndSettle();
    final screen = tester.element(find.byType(SettingsSeedPhraseScreen));
    final router = GoRouter.of(screen);
    final container = ProviderScope.containerOf(screen, listen: false);
    final otherHolder = container.read(paymentUriBusySurfaceProvider.notifier);
    otherHolder.acquire();
    await tester.tap(
      find.byKey(const ValueKey('desktop_seed_backup_remind_later')),
    );
    await tester.pump();
    expect(container.read(paymentUriBusySurfaceProvider), 2);
    router.go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSeedPhraseScreen), findsNothing);
    expect(container.read(paymentUriBusySurfaceProvider), 2);
    account.backupSave!.completeError(StateError('failure after unmount'));
    await tester.pumpAndSettle();
    expect(container.read(paymentUriBusySurfaceProvider), 1);
    otherHolder.release();
    expect(container.read(paymentUriBusySurfaceProvider), 0);
    expect(tester.takeException(), isNull);
  });

  for (final completeBackup in [false, true]) {
    testWidgets(
      'accepted account switch prevents backup ${completeBackup ? 'completion' : 'deferral'} from starting',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1080, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
        addTearDown(privacy.dispose);
        final account = _FakeAccountNotifier(backupPending: true)
          ..pendingSwitch = Completer<void>()
          ..backupSave = Completer<void>();
        await tester.pumpWidget(
          _harness(
            privacyController: privacy,
            accountNotifier: () => account,
            showBackupIntro: !completeBackup,
          ),
        );
        await tester.pumpAndSettle();
        if (completeBackup) {
          await tester.enterText(find.byType(EditableText), 'Correct123!');
          await tester.pump();
          await tester.tap(find.bySemanticsLabel('Confirm password'));
          await tester.pumpAndSettle();
        }
        final action = find.byKey(
          ValueKey(
            completeBackup
                ? 'desktop_seed_backed_up'
                : 'desktop_seed_backup_remind_later',
          ),
        );
        final acceptedSave = tester.widget<AppButton>(action).onPressed!;
        await tester.tap(find.byKey(const ValueKey('sidebar_accounts_button')));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('sidebar_account_popover_row_account-2')),
        );
        await tester.pump();
        expect(account.switched, ['account-2']);
        expect(
          find.byKey(const ValueKey('sidebar_accounts_popover')),
          findsNothing,
        );
        expect(tester.widget<AppButton>(action).onPressed, isNull);
        // A callback accepted before the rebuild must check the pending
        // navigation too, rather than starting persistence behind it.
        acceptedSave();
        await tester.tap(action);
        await tester.pump();
        expect(account.backupWriteAttempts, isEmpty);
        expect(find.byType(SettingsSeedPhraseScreen), findsOneWidget);

        account.pendingSwitch!.complete();
        await tester.pumpAndSettle();
        expect(find.text('home-destination'), findsOneWidget);
        expect(account.backupWriteAttempts, isEmpty);
        expect(account.state.requireValue.accounts.last.setupPending, isTrue);
      },
    );
  }

  testWidgets('all accepted Pay entries settle before backup can be retried', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
    addTearDown(privacy.dispose);
    final account = _FakeAccountNotifier(backupPending: true)
      ..failBackupSave = true;
    final swap = _FakeSwapNotifier();
    await tester.pumpWidget(
      _harness(
        privacyController: privacy,
        accountNotifier: () => account,
        swapNotifier: swap,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('desktop_seed_backed_up'));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('sidebar_pay_button')));
      await tester.pump();
    }
    expect(swap.pendingEntries, hasLength(2));
    expect(tester.widget<AppButton>(action).onPressed, isNull);
    swap.pendingEntries.first.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(action).onPressed, isNull);
    await tester.tap(action);
    await tester.pump();
    expect(account.backupWriteAttempts, isEmpty);

    swap.pendingEntries.last.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(action).onPressed, isNotNull);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t save that. Try again.'), findsOneWidget);
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('pay-destination'), findsNothing);
    account.failBackupSave = false;
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(account.completed, ['account-2']);
    expect(find.text('home-destination'), findsOneWidget);
  });

  testWidgets('accepted Pay navigation leaves before a backup write starts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
    addTearDown(privacy.dispose);
    final account = _FakeAccountNotifier(backupPending: true);
    final swap = _FakeSwapNotifier();
    await tester.pumpWidget(
      _harness(
        privacyController: privacy,
        accountNotifier: () => account,
        swapNotifier: swap,
        showBackupIntro: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar_pay_button')));
    await tester.pump();
    final action = find.byKey(
      const ValueKey('desktop_seed_backup_remind_later'),
    );
    expect(tester.widget<AppButton>(action).onPressed, isNull);
    await tester.tap(action);
    await tester.pump();
    expect(account.backupWriteAttempts, isEmpty);
    swap.pendingEntries.single.complete(SwapAsset.usdc);
    await tester.pumpAndSettle();
    expect(find.text('pay-destination'), findsOneWidget);
    expect(account.backupWriteAttempts, isEmpty);
    expect(account.state.requireValue.accounts.last.setupPending, isTrue);
  });

  for (final completeBackup in [false, true]) {
    testWidgets(
      'pending backup ${completeBackup ? 'completion' : 'deferral'} blocks exits and retains a late failure',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1080, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
        addTearDown(privacy.dispose);
        final account = _FakeAccountNotifier(backupPending: true)
          ..backupSave = Completer<void>();
        await tester.pumpWidget(
          _harness(
            privacyController: privacy,
            accountNotifier: () => account,
            showBackupIntro: !completeBackup,
            startAtHome: true,
          ),
        );
        await tester.pumpAndSettle();
        final router = GoRouter.of(
          tester.element(find.text('home-destination')),
        );
        unawaited(router.push('/settings/secret-passphrase'));
        await tester.pumpAndSettle();
        if (completeBackup) {
          await tester.enterText(find.byType(EditableText), 'Correct123!');
          await tester.pump();
          await tester.tap(find.bySemanticsLabel('Confirm password'));
          await tester.pumpAndSettle();
        }
        final backLink = find.byType(AppBackLink);
        final backFocus = Focus.of(
          tester.element(
            find.descendant(of: backLink, matching: find.text('Home')),
          ),
        );
        await tester.tap(
          find.byKey(
            ValueKey(
              completeBackup
                  ? 'desktop_seed_backed_up'
                  : 'desktop_seed_backup_remind_later',
            ),
          ),
        );
        await tester.pump();

        await tester.tap(backLink, warnIfMissed: false);
        await tester.pump();
        expect(
          find.byType(SettingsSeedPhraseScreen),
          findsOneWidget,
          reason: 'toolbar must stay blocked',
        );
        for (final label in ['Home', 'Settings']) {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) => widget is AppSidebarItem && widget.label == label,
            ),
            warnIfMissed: false,
          );
          await tester.pump();
          expect(
            find.byType(SettingsSeedPhraseScreen),
            findsOneWidget,
            reason: '$label must stay blocked',
          );
        }
        backFocus.requestFocus();
        await tester.pump();
        expect(backFocus.hasFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          find.byType(SettingsSeedPhraseScreen),
          findsOneWidget,
          reason: 'keyboard must stay blocked',
        );
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(SettingsSeedPhraseScreen), findsOneWidget);
        expect(find.text('home-destination'), findsNothing);

        account.backupSave!.completeError(StateError('late write failure'));
        await tester.pumpAndSettle();
        expect(find.text('Couldn’t save that. Try again.'), findsOneWidget);
        expect(account.state.requireValue.accounts.last.setupPending, isTrue);
        expect(account.completed, isEmpty);
        expect(account.snoozed, isEmpty);
        if (completeBackup) expect(find.text('abandon'), findsOneWidget);

        await tester.tap(backLink);
        await tester.pumpAndSettle();
        expect(find.text('home-destination'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'successful backup write returns to the previous Settings route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
      addTearDown(privacy.dispose);
      final account = _FakeAccountNotifier(backupPending: true)
        ..backupSave = Completer<void>();
      await tester.pumpWidget(
        _harness(
          privacyController: privacy,
          accountNotifier: () => account,
          startAtHome: true,
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.text('home-destination')));
      router.go('/settings');
      await tester.pumpAndSettle();
      unawaited(router.push('/settings/secret-passphrase'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Correct123!');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Confirm password'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop_seed_backed_up')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('settings-destination'), findsNothing);
      account.backupSave!.complete();
      await tester.pumpAndSettle();
      expect(account.completed, ['account-2']);
      expect(account.state.requireValue.accounts.last.setupPending, isFalse);
      expect(router.canPop(), isFalse);
      expect(find.text('settings-destination'), findsOneWidget);
    },
  );

  testWidgets('backup warning still requires a valid password before reveal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
    addTearDown(privacy.dispose);
    final account = _FakeAccountNotifier(backupPending: true);
    await tester.pumpWidget(
      _harness(
        privacyController: privacy,
        accountNotifier: () => account,
        showBackupIntro: true,
        passwordValid: false,
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('desktop_seed_backup_intro_continue')),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Incorrect123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    expect(find.text('abandon'), findsNothing);
    expect(account.requestedMnemonicUuids, isEmpty);
    expect(account.completed, isEmpty);
  });

  testWidgets(
    'reminder deferral waits for persistence and can retry a failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
      addTearDown(privacy.dispose);
      final account = _FakeAccountNotifier(backupPending: true)
        ..failBackupSave = true;
      await tester.pumpWidget(
        _harness(
          privacyController: privacy,
          accountNotifier: () => account,
          showBackupIntro: true,
        ),
      );
      await tester.pump();
      final defer = find.byKey(
        const ValueKey('desktop_seed_backup_remind_later'),
      );
      await tester.tap(defer);
      await tester.pump();
      expect(find.text('Couldn’t save that. Try again.'), findsOneWidget);
      expect(find.text('home-destination'), findsNothing);
      expect(account.snoozed, isEmpty);
      account.failBackupSave = false;
      account.backupSave = Completer<void>();
      await tester.tap(defer);
      await tester.pump();
      expect(tester.widget<AppButton>(defer).onPressed, isNull);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('desktop_seed_backup_intro_continue')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('home-destination'), findsNothing);
      account.backupSave!.complete();
      await tester.pumpAndSettle();
      expect(account.snoozed, ['account-2']);
      expect(account.completed, isEmpty);
      expect(account.requestedMnemonicUuids, isEmpty);
      expect(account.state.requireValue.accounts.last.setupPending, isTrue);
      expect(find.text('home-destination'), findsOneWidget);
    },
  );

  testWidgets(
    'backup intro can defer the requested account without revealing its phrase',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
      addTearDown(privacy.dispose);
      final account = _FakeAccountNotifier(backupPending: true);
      await tester.pumpWidget(
        _harness(
          privacyController: privacy,
          accountNotifier: () => account,
          showBackupIntro: true,
        ),
      );
      await tester.pump();
      expect(find.text('abandon'), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('desktop_seed_backup_remind_later')),
      );
      await tester.pumpAndSettle();
      expect(account.snoozed, ['account-2']);
      expect(account.requestedMnemonicUuids, isEmpty);
      expect(account.state.requireValue.accounts.last.setupPending, isTrue);
      expect(find.text('home-destination'), findsOneWidget);
    },
  );

  testWidgets(
    'backup completion waits for persistence and retains the phrase after failure',
    (tester) async {
      await loadFigmaCompareFonts();
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
      addTearDown(privacy.dispose);
      final account = _FakeAccountNotifier(backupPending: true);
      await tester.pumpWidget(
        _harness(
          privacyController: privacy,
          accountNotifier: () => account,
          showBackupIntro: true,
        ),
      );
      await tester.pump();
      final warningBounds = tester.getRect(
        find.byType(SecretPassphraseRevealWarningCard),
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop_seed_backup_intro_continue')),
      );
      await tester.pump();
      expect(find.text('abandon'), findsNothing);
      await tester.enterText(find.byType(EditableText), 'Correct123!');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Confirm password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('abandon'), findsOneWidget);
      final phraseCard = find
          .ancestor(
            of: find.byKey(const ValueKey('settings_seed_phrase_copy_button')),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getRect(phraseCard), warningBounds);
      account.failBackupSave = true;
      final completeButton = find.byKey(
        const ValueKey('desktop_seed_backed_up'),
      );
      final paneBounds = tester.getRect(find.byType(SensitivePrivacyOverlay));
      expect(completeButton.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(completeButton).dy,
        lessThanOrEqualTo(paneBounds.bottom - AppSpacing.md),
      );
      await tester.tap(completeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final saveError = find.text('Couldn’t save that. Try again.');
      expect(saveError.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(saveError).dy,
        lessThanOrEqualTo(paneBounds.bottom - AppSpacing.md),
      );
      final birthdayCard = find
          .ancestor(
            of: find.text('Birthday block height'),
            matching: find.byType(Container),
          )
          .first;
      final buttonBounds = tester.getRect(completeButton);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pump();
      expect(tester.getRect(completeButton), buttonBounds);
      expect(
        tester.getBottomRight(birthdayCard).dy,
        lessThanOrEqualTo(
          tester.getBottomRight(find.byType(SingleChildScrollView)).dy,
        ),
      );
      expect(find.text('abandon'), findsOneWidget);
      expect(account.state.requireValue.accounts.last.setupPending, isTrue);
      account.failBackupSave = false;
      account.backupSave = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('desktop_seed_backed_up')));
      await tester.pump();
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('desktop_seed_backed_up')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('home-destination'), findsNothing);
      account.backupSave!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(account.completed, ['account-2']);
      expect(account.state.requireValue.accounts.first.setupPending, isFalse);
      expect(account.state.requireValue.accounts.last.setupPending, isFalse);
      expect(find.text('home-destination'), findsOneWidget);
      expect(find.text('abandon'), findsNothing);
    },
  );

  testWidgets('failed backup save keeps the standard birthday card in view', (
    tester,
  ) async {
    await loadFigmaCompareFonts();
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacy = SensitivePrivacyOverlayController(initiallySafe: true);
    addTearDown(privacy.dispose);
    final account = _FakeAccountNotifier(
      backupPending: true,
      bip39Passphrase: '',
    )..failBackupSave = true;
    await tester.pumpWidget(
      _harness(privacyController: privacy, accountNotifier: () => account),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final firstWord = find.byKey(const ValueKey('settings_seed_phrase_word_1'));
    final wordBounds = tester.getRect(firstWord);
    final completeButton = find.byKey(const ValueKey('desktop_seed_backed_up'));
    await tester.tap(completeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final birthdayCard = find
        .ancestor(
          of: find.text('Birthday block height'),
          matching: find.byType(Container),
        )
        .first;
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(
      tester.getRect(birthdayCard).bottom,
      lessThanOrEqualTo(viewport.bottom),
      reason: 'Retry feedback must not clip the birthday card at 1080 × 720.',
    );
    expect(tester.getRect(firstWord), wordBounds);
    expect(
      find.text('Couldn’t save that. Try again.').hitTestable(),
      findsOneWidget,
    );
    expect(completeButton.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveals the requested account without making it active', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);
    late _FakeAccountNotifier accountNotifier;

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => accountNotifier = _FakeAccountNotifier(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();

    expect(accountNotifier.requestedMnemonicUuids, ['account-2']);
    expect(accountNotifier.state.requireValue.activeAccountUuid, 'account-1');
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('BIP39 Passphrase: $_bip39Passphrase'), findsOneWidget);

    for (var index = 1; index <= 24; index++) {
      expect(
        find.byKey(ValueKey('settings_seed_phrase_word_$index')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('settings_seed_phrase_underline_$index')),
        findsOneWidget,
      );
    }

    final word1 = tester.getTopLeft(
      find.byKey(const ValueKey('settings_seed_phrase_word_1')),
    );
    final word2 = tester.getTopLeft(
      find.byKey(const ValueKey('settings_seed_phrase_word_2')),
    );
    final word3 = tester.getTopLeft(
      find.byKey(const ValueKey('settings_seed_phrase_word_3')),
    );
    final word4 = tester.getTopLeft(
      find.byKey(const ValueKey('settings_seed_phrase_word_4')),
    );
    expect(word2.dy, word1.dy);
    expect(word3.dy, word1.dy);
    expect(word1.dx, lessThan(word2.dx));
    expect(word2.dx, lessThan(word3.dx));
    expect(word4.dy, greaterThan(word1.dy));

    final firstUnderline = tester.widget<Positioned>(
      find.byKey(const ValueKey('settings_seed_phrase_underline_1')),
    );
    expect(firstUnderline.left, 22.5);
    expect(firstUnderline.width, 87);

    final phraseCopyButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('settings_seed_phrase_copy_button')),
    );
    expect(phraseCopyButton.variant, AppButtonVariant.secondary);
    expect(phraseCopyButton.height, 24);
    expect(phraseCopyButton.trailing, isNull);

    final bip39CopyButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('settings_bip39_passphrase_copy_button')),
    );
    expect(bip39CopyButton.variant, AppButtonVariant.ghost);
    expect(bip39CopyButton.height, 24);
    expect(bip39CopyButton.trailing, isNull);

    final footer = tester.widget<Container>(
      find.byKey(const ValueKey('settings_bip39_passphrase_footer')),
    );
    final footerDecoration = footer.decoration as BoxDecoration;
    expect(footerDecoration.color, AppThemeData.light.colors.background.ground);
    expect(footerDecoration.boxShadow, hasLength(4));
  });

  testWidgets('hides the BIP39 section when the account has no passphrase', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => _FakeAccountNotifier(bip39Passphrase: ''),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();

    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('BIP39 Passphrase'), findsNothing);
    expect(find.bySemanticsLabel('Copy BIP39 passphrase'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings_bip39_passphrase_footer')),
      findsNothing,
    );
  });

  testWidgets('Linux does not reveal a delayed secret after lock and unlock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);
    final secret = Completer<SoftwareWalletSecret?>();
    final store = AppSecureStore.testing(
      storage: const FlutterSecureStorage(),
      enforceSessionGeneration: true,
    )..setSessionPassword('Correct123!');
    final accountNotifier = _FakeAccountNotifier(pendingSecret: secret);
    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => accountNotifier,
        secureStore: store,
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();
    expect(accountNotifier.requestedMnemonicUuids, ['account-2']);
    store.clearSessionPassword();
    store.setSessionPassword('Correct123!');
    secret.complete(const SoftwareWalletSecret(mnemonic: _mnemonic));
    await tester.pump();

    expect(find.text('abandon'), findsNothing);
    expect(
      find.text('The wallet session changed. Enter your password again.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Confirm password'), findsOneWidget);
  });

  testWidgets('describes removal of the requested account accurately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);
    late _FakeAccountNotifier accountNotifier;

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => accountNotifier = _FakeAccountNotifier(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();
    accountNotifier.removeRequestedAccount();
    await tester.pump();

    expect(
      find.text('Selected account changed. Enter your password again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Active account changed'), findsNothing);
  });
}

Widget _harness({
  required SensitivePrivacyOverlayController privacyController,
  required AccountNotifier Function() accountNotifier,
  AppSecureStore? secureStore,
  bool showBackupIntro = false,
  bool passwordValid = true,
  bool startAtHome = false,
  _FakeSwapNotifier? swapNotifier,
  _FakeIncomingUriService? incomingUris,
}) {
  final router = GoRouter(
    initialLocation: startAtHome
        ? '/home'
        : incomingUris != null
        ? '/setup/backup'
        : '/settings/secret-passphrase',
    routes: [
      for (final path in ['/settings/secret-passphrase', '/setup/backup'])
        GoRoute(
          path: path,
          builder: (_, _) => SettingsSeedPhraseScreen(
            accountUuid: 'account-2',
            showBackupIntro: showBackupIntro,
            privacyOverlayController: privacyController,
            birthdayHeightLoader: (_) async => 3428019,
            birthdayBlockTimeLoader: (_) async => 1785196800,
          ),
        ),
      GoRoute(path: '/accounts', builder: (_, _) => const SizedBox()),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings-destination'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-destination')),
      GoRoute(path: '/pay', builder: (_, _) => const Text('pay-destination')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send-destination')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      if (secureStore != null)
        linuxSecretOperationStoreProvider.overrideWithValue(secureStore),
      accountProvider.overrideWith(accountNotifier),
      appSecurityProvider.overrideWith(
        () => _FakeSecurityNotifier(valid: passwordValid),
      ),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      if (incomingUris != null) ...[
        incomingUriServiceProvider.overrideWithValue(incomingUris),
        paymentRequestPrecheckProvider.overrideWithValue(
          _amountlessPaymentPrecheck(),
        ),
        addressBookProvider.overrideWith(_EmptyAddressBookNotifier.new),
        ownAccountAddressesProvider.overrideWith((ref) async => const {}),
        zecHomeUsdUnitPriceProvider.overrideWithValue(null),
        migrationSendGateProvider.overrideWithValue(false),
      ],
      if (swapNotifier != null) ...[
        swapFeatureEnabledProvider.overrideWithValue(true),
        swapStateProvider.overrideWith(() => swapNotifier),
      ],
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.light,
        child: incomingUris == null
            ? child!
            : buildIncomingLinkHostForTest(
                router: router,
                child: PaymentRequestHost(router: router, child: child!),
              ),
      ),
    ),
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/secret-passphrase',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier({
    this.bip39Passphrase = _bip39Passphrase,
    this.pendingSecret,
    this.backupPending = false,
  });

  final Completer<SoftwareWalletSecret?>? pendingSecret;

  final String bip39Passphrase;
  final bool backupPending;
  bool failBackupSave = false;
  Completer<void>? backupSave;
  Completer<void>? pendingSwitch;
  final switched = <String>[];
  final backupWriteAttempts = <String>[];
  final completed = <String>[];
  final snoozed = <String>[];
  final requestedMnemonicUuids = <String>[];

  @override
  FutureOr<AccountState> build() => _accountState.copyWith(
    accounts: [
      _accountState.accounts.first,
      _accountState.accounts.last.copyWith(setupPending: backupPending),
    ],
  );

  @override
  Future<void> markBackedUp(String uuid) async {
    backupWriteAttempts.add(uuid);
    if (failBackupSave) throw StateError('write failed');
    await backupSave?.future;
    completed.add(uuid);
    state = AsyncData(
      state.requireValue.copyWith(
        accounts: [
          for (final a in state.requireValue.accounts)
            a.uuid == uuid ? a.copyWith(setupPending: false) : a,
        ],
      ),
    );
  }

  @override
  Future<void> snoozeBackupReminder(String uuid, {DateTime? now}) async {
    backupWriteAttempts.add(uuid);
    if (failBackupSave) throw StateError('write failed');
    await backupSave?.future;
    snoozed.add(uuid);
  }

  @override
  Future<void> switchAccount(String uuid) async {
    switched.add(uuid);
    await pendingSwitch?.future;
    state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  }

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async {
    requestedMnemonicUuids.add(uuid);
    if (pendingSecret != null) return pendingSecret!.future;
    return SoftwareWalletSecret(
      mnemonic: _mnemonic,
      bip39Passphrase: bip39Passphrase,
    );
  }

  void removeRequestedAccount() {
    state = AsyncData(
      state.requireValue.copyWith(
        accounts: state.requireValue.accounts
            .where((account) => account.uuid != 'account-2')
            .toList(),
      ),
    );
  }
}

class _FakeSecurityNotifier extends AppSecurityNotifier {
  _FakeSecurityNotifier({this.valid = true});
  final bool valid;

  @override
  Future<bool> confirmPassword(String password) async => valid;
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async =>
      SyncState(accountUuid: 'account-1', hasAccountScopedData: true);

  @override
  Future<void> refreshAfterAccountSwitch() async {}
}

class _FakeSwapNotifier extends SwapNotifier {
  final pendingEntries = <Completer<SwapAsset?>>[];

  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
  );

  @override
  Future<SwapAsset?> resolvePaySelectedAssetForEntry({
    required String accountUuid,
  }) {
    final entry = Completer<SwapAsset?>();
    pendingEntries.add(entry);
    return entry.future;
  }

  @override
  bool preparePayFromShieldedZec({
    SwapAsset? preferredAsset,
    String? expectedAccountUuid,
  }) => true;
}

class _FakeIncomingUriService extends IncomingUriService {
  final _uris = StreamController<String>.broadcast();

  @override
  Stream<String> get uriStream => _uris.stream;

  @override
  Future<void> initialize() async {}

  void emit(String uri) => _uris.add(uri);

  @override
  Future<void> dispose() => _uris.close();
}

class _EmptyAddressBookNotifier extends AddressBookNotifier {
  @override
  Future<AddressBookState> build() async => const AddressBookState();
}

PaymentRequestPrecheck _amountlessPaymentPrecheck() => PaymentRequestPrecheck(
  readNetworkName: () => kZcashDefaultNetworkName,
  spendableIsAuthoritativeNow: () => true,
  validateAddress: ({required String address, required String network}) async =>
      rust_sync.AddressValidationResult(
        isValid: true,
        addressType: 'unified',
        wrongNetwork: false,
      ),
  proposeTransfer:
      ({
        required String accountUuid,
        required String sendFlowId,
        required String address,
        required String addressType,
        required BigInt amountZatoshi,
        String? memo,
        bool isPaymentRequest = false,
        String? requestedBy,
        BigInt? requestedAmountZatoshi,
      }) async => throw StateError('An amountless request must not propose'),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
        required String accountUuid,
      }) async => true,
);
