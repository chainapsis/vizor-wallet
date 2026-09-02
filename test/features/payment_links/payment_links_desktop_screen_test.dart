import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_clipboard.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_qr_image_saver.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_flip.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_confetti.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await loader.load();
  });

  testWidgets('shows the truthful landing and help copy', (tester) async {
    await _pumpPaymentLinksScreen(tester);

    expect(
      find.byKey(const ValueKey('payment_links_desktop_screen')),
      findsOneWidget,
    );
    expect(find.text('No Gift Cards yet'), findsOneWidget);

    await tester.tap(find.text('How Gift Cards work'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Enter amount to gift, pick a design, add a message (optional) '
        'and create your Card with a single click.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('claim secret'), findsOneWidget);
    expect(
      find.textContaining('All data in the link is encrypted'),
      findsNothing,
    );
    expect(
      find.text(
        'Recipient can redeem the Card in their Vizor wallet using the Link. '
        'The sender covers the deposit and redeem fees, so the recipient '
        'receives the full Card amount.',
      ),
      findsOneWidget,
    );

    final modalRect = tester.getRect(find.byType(AppModalCard));
    expect(modalRect.size, const Size(312, 420));
    final closeRect = tester.getRect(
      find.byKey(const ValueKey('payment_link_help_close_button')),
    );
    expect(closeRect.center.dx, modalRect.center.dx);
    expect(modalRect.bottom - closeRect.bottom, AppSpacing.md);

    await tester.tap(
      find.byKey(const ValueKey('payment_link_help_close_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('No Gift Cards yet'), findsOneWidget);
  });

  testWidgets('landing text actions expose visible desktop hover feedback', (
    tester,
  ) async {
    await _pumpPaymentLinksScreen(tester);

    final hoverFeedback = find.byKey(
      const ValueKey('payment_link_text_action_hover_How Gift Cards work'),
    );
    expect(tester.widget<AnimatedOpacity>(hoverFeedback).opacity, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('How Gift Cards work')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.widget<AnimatedOpacity>(hoverFeedback).opacity, lessThan(1));
  });

  testWidgets('enables creation after the local review is complete', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final operations = _FakePaymentLinkOperations();
    final clipboard = _FakePaymentLinkClipboard();
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Create new card'));
    await tester.pumpAndSettle();

    final amountEditor = find.byKey(
      const ValueKey('payment_link_amount_editor'),
    );
    expect(find.text('Use max: 142.2298'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment_link_max_button')), findsNothing);
    final amountField = tester.widget<EditableText>(amountEditor);
    expect(amountField.focusNode.hasFocus, isFalse);
    expect(amountField.cursorColor.a, greaterThan(0));
    expect(amountField.cursorOpacityAnimates, isTrue);
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(
              const ValueKey('payment_link_amount_input_mouse_region'),
            ),
          )
          .cursor,
      SystemMouseCursors.text,
    );
    expect(
      find.ancestor(
        of: amountEditor,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion && widget.cursor == SystemMouseCursors.text,
        ),
      ),
      findsWidgets,
    );
    final amountSemantics = find.semantics.byLabel(
      RegExp(r'^Gift card amount input(?:\n|$)'),
    );
    expect(amountSemantics, findsOne);
    expect(find.semantics.byFlag(SemanticsFlag.isTextField), findsOne);
    final amountNode = amountSemantics.evaluate().single;
    expect(amountNode.flagsCollection.isTextField, isTrue);
    expect(amountNode.label, startsWith('Gift card amount input'));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(amountEditor));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const ValueKey('payment_link_amount_hover_ring')),
      findsOneWidget,
    );

    await tester.tap(amountEditor);
    await tester.pump();
    expect(
      tester.widget<EditableText>(amountEditor).focusNode.hasFocus,
      isTrue,
    );
    expect(
      amountSemantics.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.setText,
      ),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('payment_link_amount_focus_ring')),
      findsNothing,
    );

    await tester.enterText(amountEditor, '1.25');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(amountSemantics.evaluate().single.value, '1.25');

    final editableRoot = tester.renderObject(amountEditor);
    final caretRect = _globalCaretRect(
      _findRenderEditable(editableRoot),
      '1.25'.length,
    );
    final editorRect = tester.getRect(amountEditor);
    expect(caretRect.width, greaterThan(0));
    expect(caretRect.height, greaterThan(0));
    expect(editorRect.overlaps(caretRect), isTrue);

    expect(
      find.descendant(
        of: find.byType(PaymentLinkGiftCard),
        matching: find.text('1.25'),
      ),
      findsOneWidget,
    );

    expect(find.text('Use max: 142.2298'), findsNothing);
    expect(find.text('Max'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('payment_link_max_button')));
    await tester.pump();
    expect(
      tester.widget<EditableText>(amountEditor).controller.text,
      '142.2298',
    );
    await tester.enterText(amountEditor, '1.25');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('payment_link_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Message'), findsOneWidget);

    final messageEditor = find.byKey(
      const ValueKey('payment_link_message_editor'),
    );
    expect(messageEditor, findsNothing);
    expect(find.text('Start typing...'), findsOneWidget);
    expect(
      tester
          .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
          .showBack,
      isFalse,
    );

    await tester.tap(find.text('Start typing...'));
    await tester.pump();
    expect(
      tester
          .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
          .showBack,
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(messageEditor, findsOneWidget);
    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    expect(
      tester.widget<TextField>(messageEditor).decoration?.hintText,
      isNull,
    );

    await tester.enterText(messageEditor, 'For you');
    await tester.pump();

    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    expect(find.text('For you'), findsOneWidget);
    expect(
      tester.widget<TextField>(messageEditor).decoration?.hintText,
      isNull,
    );
    expect(find.text('121/128'), findsOneWidget);

    var continueButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & review'),
    );
    expect(continueButton.onPressed, isNotNull);

    await tester.enterText(
      messageEditor,
      List.filled(25, '👨‍👩‍👧‍👦').join(),
    );
    await tester.pump();
    expect(
      find.text('This message is too large. Try using fewer complex emoji.'),
      findsOneWidget,
    );
    continueButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & review'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.enterText(messageEditor, List.filled(128, '한').join());
    await tester.pump();
    expect(
      find.text('This message is too large. Try using fewer complex emoji.'),
      findsNothing,
    );
    expect(find.text('0/128'), findsOneWidget);
    continueButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & review'),
    );
    expect(continueButton.onPressed, isNotNull);

    await tester.enterText(messageEditor, 'For you');
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Delete gift card message'));
    await tester.pump();
    expect(tester.widget<TextField>(messageEditor).controller?.text, isEmpty);
    expect(find.text('128/128'), findsOneWidget);
    continueButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.enterText(messageEditor, '   \n');
    await tester.pump();
    continueButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.enterText(messageEditor, 'For you');
    await tester.pump();
    await tester.tap(find.text('Confirm & review'));
    await tester.pumpAndSettle();
    expect(find.text('Card amount'), findsOneWidget);
    expect(find.text('Card fee (deposit + redeem)'), findsOneWidget);
    expect(find.text('1.2502 ZEC'), findsOneWidget);
    expect(
      tester
          .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
          .showBack,
      isFalse,
    );
    expect(find.text('For you'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
          .showBack,
      isTrue,
    );
    expect(find.text('For you'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Show gift card front'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
          .showBack,
      isFalse,
    );

    await tester.tap(find.text('Add Message'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(messageEditor).controller?.text, 'For you');

    await tester.tap(find.text('Skip message'));
    await tester.pumpAndSettle();
    expect(find.text('Card amount'), findsOneWidget);
    expect(find.byType(PaymentLinkCardFlip), findsNothing);

    final confirmButton = tester.widget<AppButton>(
      find
          .ancestor(
            of: find.text('Create card'),
            matching: find.byType(AppButton),
          )
          .first,
    );
    expect(confirmButton.onPressed, isNotNull);
    await tester.tap(find.text('Create card'));
    await tester.pumpAndSettle();

    expect(operations.createdAmounts, [BigInt.from(125000000)]);
    expect(operations.createdFromAccounts, ['account-1']);
    expect(find.textContaining('is ready!'), findsOneWidget);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(operations.sharedLinks, hasLength(1));
    expect(clipboard.copiedSecrets, hasLength(1));
    semantics.dispose();
  });

  testWidgets(
    'retries recovery metadata without submitting Gift Card funding twice',
    (tester) async {
      final operations = _FakePaymentLinkOperations(
        fundingMetadataSavedOnCreate: false,
      );
      await _pumpPaymentLinksScreen(tester, operations: operations);

      await tester.tap(find.text('Create new card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '0.1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create card'));
      await tester.pumpAndSettle();

      expect(operations.createdAmounts, [BigInt.from(10000000)]);
      expect(find.text('Try saving again'), findsOneWidget);
      expect(
        find.textContaining(
          'Funding was sent, but the Gift Card could not be saved.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('is ready!'), findsNothing);

      await tester.tap(find.text('Try saving again'));
      await tester.pumpAndSettle();

      expect(operations.createdAmounts, [BigInt.from(10000000)]);
      expect(operations.fundingMetadataRetries, 1);
      expect(find.textContaining('is ready!'), findsOneWidget);
      expect(operations.records.single.state, PaymentLinkRecoveryState.funded);
      expect(operations.records.single.fundingTxids, 'funding-txid');
    },
  );

  testWidgets(
    'disables Continue when the Card amount and fees exceed balance',
    (tester) async {
      await _pumpPaymentLinksScreen(
        tester,
        spendableBalance: BigInt.from(100000000),
      );

      await tester.tap(find.text('Create new card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '1',
      );
      await tester.pump();

      expect(find.text('Above your maximum ZEC'), findsOneWidget);
      final selectorRect = tester.getRect(
        find.byType(PaymentLinkCardSelectorRail),
      );
      final errorRect = tester.getRect(
        find.byKey(const ValueKey('payment_link_amount_supporting_text')),
      );
      expect(errorRect.top - selectorRect.bottom, AppSpacing.s);
      expect(find.text('Enter amount'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('payment_link_amount_continue_button')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('estimates the Card fee automatically after sync completes', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    final syncNotifier = FakeSyncNotifier(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
        percentage: 0.7,
        displayTargetPercentage: 0.7,
        spendableBalance: BigInt.from(14223000000),
        displaySpendableBalance: BigInt.from(14223000000),
      ),
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      syncNotifier: syncNotifier,
    );

    await tester.tap(find.text('Create new card'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '0.1',
    );
    await tester.pump();

    expect(
      find.text('Card fee will be estimated when wallet sync completes.'),
      findsOneWidget,
    );
    expect(operations.quotedAccounts, isEmpty);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('payment_link_amount_continue_button')),
          )
          .onPressed,
      isNull,
    );

    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
        percentage: 1,
        displayTargetPercentage: 1,
        spendableBalance: BigInt.from(14223000000),
        displaySpendableBalance: BigInt.from(14223000000),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(operations.quotedAccounts, ['account-1']);
    expect(
      find.text('Card fee will be estimated when wallet sync completes.'),
      findsNothing,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('payment_link_amount_continue_button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('uses one confirmation after an uncertain funding restart', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(
      records: [_fundedRecovery],
      fundingConfirmationCount: 0,
    );
    await _pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsNothing);

    operations.fundingConfirmationCount = 1;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsNothing);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsOneWidget);
  });

  testWidgets('removes an unshared Card after funding expires', (tester) async {
    final operations = _FakePaymentLinkOperations(
      records: [_fundedRecovery],
      fundingConfirmationCount: 0,
    );
    await _pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('Preparing...'), findsOneWidget);

    operations.expireFundingOnInspect = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(operations.records, isEmpty);
    expect(find.text('Preparing...'), findsNothing);
  });

  testWidgets('makes the link available after funding is accepted', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(fundingConfirmationCount: 0);
    await _pumpPaymentLinksScreen(tester, operations: operations);

    await tester.tap(find.text('Create new card'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '0.1',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create card'));
    await tester.pumpAndSettle();

    expect(find.text('Copy link'), findsOneWidget);
    expect(find.textContaining('is ready!'), findsOneWidget);
    expect(find.byType(PaymentLinkConfetti), findsOneWidget);
  });

  testWidgets(
    'waits for one confirmation when broadcast acceptance is unsure',
    (tester) async {
      final operations = _FakePaymentLinkOperations(
        fundingBroadcastAcceptedOnCreate: false,
        fundingConfirmationCount: 0,
      );
      await _pumpPaymentLinksScreen(tester, operations: operations);

      await tester.tap(find.text('Create new card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '0.1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create card'));
      await tester.pumpAndSettle();

      expect(find.text('Wait 1:15 to get the link'), findsOneWidget);
      expect(find.text('Copy link'), findsNothing);

      operations.fundingConfirmationCount = 1;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('Copy link'), findsOneWidget);
    },
  );

  testWidgets('shows a separate state when a valid link has no balance', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(claimable: false);
    final clipboard = _FakePaymentLinkClipboard(
      text: _incomingLink.toUri().toString(),
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('This Card has no available balance.'), findsOneWidget);
    expect(find.text('The link doesn’t look legit.'), findsNothing);
  });

  testWidgets('waits for six confirmations before exposing the claim action', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(
      claimable: false,
      waitingForFundingConfirmations: true,
      fundingConfirmationCount: 2,
    );
    final clipboard = _FakePaymentLinkClipboard(
      text: _incomingLink.toUri().toString(),
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for 6 confirmations.'), findsOneWidget);
    expect(find.text('Wait 5:00 to claim'), findsOneWidget);
    expect(find.text('Claim the Gift Card'), findsNothing);

    operations
      ..claimable = true
      ..waitingForFundingConfirmations = false
      ..fundingConfirmationCount = 6;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Claim the Gift Card'), findsOneWidget);
    expect(find.text('Waiting for 6 confirmations.'), findsNothing);
  });

  testWidgets(
    'hardware creation opens Keystone signing and releases on cancel',
    (tester) async {
      final hardwareSigning = _FakePaymentLinkHardwareSigningService();
      await _pumpPaymentLinksScreen(
        tester,
        bootstrap: _hardwareBootstrap,
        hardwareSigning: hardwareSigning,
      );

      await tester.tap(find.text('Create new card'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_card_selector_ruby')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '0.1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start typing...'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_message_editor')),
        'For Keystone',
      );
      await tester.pump();
      await tester.tap(find.text('Confirm & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create card'));

      for (var i = 0; i < 20 && hardwareSigning.createdAmounts.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(hardwareSigning.createdAmounts, [BigInt.from(10000000)]);
      expect(hardwareSigning.createdFromAccounts, ['hardware-account']);
      expect(hardwareSigning.createdArtworkIds, ['ruby']);
      expect(hardwareSigning.createdMessages, ['For Keystone']);
      expect(find.byType(KeystoneSigningModal), findsOneWidget);
      expect(find.text('Sign Gift Card on Keystone'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(hardwareSigning.discardedDrafts, [BigInt.one]);
      expect(find.byType(KeystoneSigningModal), findsNothing);
      expect(
        find.text('Card amount'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .join(' | '),
      );
    },
  );

  testWidgets('sends the selected artwork and message through creation', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    await _pumpPaymentLinksScreen(tester, operations: operations);

    await tester.tap(find.text('Create new card'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_card_selector_ruby')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '0.1',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start typing...'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_message_editor')),
      'Congratulations!',
    );
    await tester.pump();
    await tester.tap(find.text('Confirm & review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create card'));
    await tester.pumpAndSettle();

    expect(operations.createdArtworkIds, ['ruby']);
    expect(operations.createdMessages, ['Congratulations!']);
  });

  testWidgets(
    'requotes and returns to amount when the active account changes',
    (tester) async {
      final operations = _FakePaymentLinkOperations();
      final accountNotifier = _SwitchablePaymentLinkAccountNotifier();
      final syncNotifier = FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          percentage: 1,
          displayTargetPercentage: 1,
          spendableBalance: BigInt.from(14223000000),
          displaySpendableBalance: BigInt.from(14223000000),
        ),
      );
      await _pumpPaymentLinksScreen(
        tester,
        operations: operations,
        accountNotifier: accountNotifier,
        bootstrap: _twoAccountBootstrap,
        syncNotifier: syncNotifier,
      );

      await tester.tap(find.text('Create new card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '0.1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip message'));
      await tester.pumpAndSettle();
      expect(find.text('Create card'), findsOneWidget);

      accountNotifier.setActiveAccount('account-2');
      await tester.pump();

      final requotedAmountEditor = find.byKey(
        const ValueKey('payment_link_amount_editor'),
      );
      expect(requotedAmountEditor, findsOneWidget);
      expect(
        tester.widget<EditableText>(requotedAmountEditor).controller.text,
        '0.1',
      );
      expect(find.text('Create card'), findsNothing);
      expect(
        find.text(
          'Active account changed. Review the Gift Card amount and fees again.',
        ),
        findsOneWidget,
      );

      syncNotifier.emit(
        SyncState(
          accountUuid: 'account-2',
          hasAccountScopedData: true,
          isSyncComplete: true,
          percentage: 1,
          displayTargetPercentage: 1,
          spendableBalance: BigInt.from(14223000000),
          displaySpendableBalance: BigInt.from(14223000000),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create card'));
      await tester.pumpAndSettle();

      expect(operations.quotedAccounts, ['account-1', 'account-2']);
      expect(operations.createdFromAccounts, ['account-2']);
    },
  );

  testWidgets('hardware cancel releases a draft that finishes preparing late', (
    tester,
  ) async {
    final createCompleter = Completer<PaymentLinkHardwarePcztDraft>();
    final hardwareSigning = _FakePaymentLinkHardwareSigningService(
      createCompleter: createCompleter,
    );
    await _pumpPaymentLinksScreen(
      tester,
      bootstrap: _hardwareBootstrap,
      hardwareSigning: hardwareSigning,
    );

    await tester.tap(find.text('Create new card'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '0.1',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create card'));
    await tester.pump();

    expect(find.byType(KeystoneSigningModal), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.byType(KeystoneSigningModal), findsNothing);

    createCompleter.complete(hardwareSigning.draft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(hardwareSigning.discardedDrafts, [BigInt.one]);
  });

  testWidgets('enables manual redeem intake', (tester) async {
    final operations = _FakePaymentLinkOperations();
    final clipboard = _FakePaymentLinkClipboard(
      text: _incomingLink.toUri().toString(),
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();

    final pasteButton = tester.widget<AppButton>(
      find
          .ancestor(
            of: find.text('Paste card link'),
            matching: find.byType(AppButton),
          )
          .first,
    );
    expect(pasteButton.onPressed, isNotNull);

    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    expect(find.text('4.45'), findsOneWidget);
    expect(find.text('Message attached.'), findsOneWidget);
    expect(find.text('Congratulations!'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pumpAndSettle();

    expect(find.text('Congratulations!'), findsOneWidget);
  });

  testWidgets('pastes the clipboard Card without consuming a queued link', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    final clipboardRead = Completer<String?>();
    final clipboard = _FakePaymentLinkClipboard(readCompleter: clipboardRead);
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pump();

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    clipboardRead.complete(_secondIncomingLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(
      operations.preparedLinks.single.address,
      _secondIncomingLink.address,
    );
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink?.address,
      _incomingLink.address,
    );
  });

  testWidgets('confirms before checking a Gift Card with a long scan', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(
      longSyncConfirmationRequired: true,
    );
    final clipboard = _FakePaymentLinkClipboard(
      text: _incomingLink.toUri().toString(),
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('This Gift Card may take a while'), findsOneWidget);
    expect(
      find.text(
        'Vizor needs to scan more history than usual before it can verify the '
        'balance. This is safe, but it may take a long time.',
      ),
      findsOneWidget,
    );
    expect(operations.allowLongSyncCalls, [isFalse]);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(find.text('This Gift Card may take a while'), findsNothing);
    expect(find.text('Paste card link'), findsOneWidget);

    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check Gift Card'));
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncCalls, [isFalse, isFalse, isTrue]);
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
  });

  testWidgets(
    'mobile confirms before checking a Gift Card with a long scan',
    (tester) async {
      final operations = _FakePaymentLinkOperations(
        longSyncConfirmationRequired: true,
      );
      final clipboard = _FakePaymentLinkClipboard(
        text: _incomingLink.toUri().toString(),
      );
      await _pumpPaymentLinksScreen(
        tester,
        operations: operations,
        clipboard: clipboard,
      );

      expect(
        find.byKey(const ValueKey('payment_links_mobile_screen')),
        findsOneWidget,
      );
      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('payment_link_long_sync_warning_sheet')),
        findsOneWidget,
      );
      expect(operations.allowLongSyncCalls, [isFalse]);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payment_link_long_sync_warning_sheet')),
        findsNothing,
      );

      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check Gift Card'));
      await tester.pumpAndSettle();

      expect(operations.allowLongSyncCalls, [isFalse, isFalse, isTrue]);
      expect(find.text('You’ve received a gift!'), findsOneWidget);
    },
    tags: ['mobile'],
  );

  testWidgets('routes an accepted incoming payment link and claims it', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    expect(find.text('4.45'), findsOneWidget);
    expect(operations.receivedRecords, isEmpty);
    expect(
      find.byKey(const ValueKey('payment_link_received_u1paymentlinkaddress')),
      findsNothing,
    );

    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(operations.claimedLinks.map((link) => link.toUri().toString()), [
      _incomingLink.toUri().toString(),
    ]);
    expect(find.text('Gift claim submitted'), findsOneWidget);
    expect(find.text('Receiving...'), findsOneWidget);
  });

  testWidgets('defers an incoming Gift Card while another card is being made', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    await _pumpPaymentLinksScreen(tester, operations: operations);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    await tester.tap(find.text('Create new card'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      findsOneWidget,
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      findsOneWidget,
    );
    expect(find.text(kPaymentLinkDeferredByActiveFlowMessage), findsOneWidget);
    expect(operations.allowLongSyncCalls, isEmpty);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncCalls, [isFalse]);
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
  });

  testWidgets('retries an incoming link without requiring the clipboard', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(prepareClaimFailures: 1);
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text('Card balance could not be checked. Try again.'),
      findsOneWidget,
    );
    expect(operations.allowLongSyncCalls, [isFalse]);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncCalls, [isFalse, isFalse]);
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
  });

  testWidgets('discards a previous claim wallet when its identity changes', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();

    final differentBirthdayLink = VizorPaymentLink(
      network: _incomingLink.network,
      address: _incomingLink.address,
      amountZatoshi: _incomingLink.amountZatoshi,
      mnemonic: _incomingLink.mnemonic,
      birthdayHeight: _incomingLink.birthdayHeight - 1,
      label: _incomingLink.label,
      createdAt: _incomingLink.createdAt,
      presentation: _incomingLink.presentation,
    );
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(differentBirthdayLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncCalls, [isFalse, isFalse]);
    expect(operations.discardedClaimAddresses, [_incomingLink.address]);
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
  });

  testWidgets('does not reopen an in-flight received Gift Card', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(
      receivedRecords: [
        PaymentLinkReceivedRecord(
          network: _incomingLink.network,
          address: _incomingLink.address,
          amountZatoshi: _incomingLink.amountZatoshi,
          createdAt: _incomingLink.createdAt,
          artworkId: _incomingLink.presentation?.artworkId,
          message: _incomingLink.presentation?.message,
          status: PaymentLinkReceivedStatus.submitting,
          claimLink: _incomingLink,
          destinationAccountUuid: 'account-1',
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      ],
      prepareClaimError: const PaymentLinkClaimInFlightException(),
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(
      find.text('This Gift Card is already being received.'),
      findsOneWidget,
    );
    expect(find.text('Receiving...'), findsOneWidget);
    expect(operations.discardedClaimAddresses, isEmpty);
  });

  testWidgets(
    'loads Created and Received in parallel before consuming an incoming link',
    (tester) async {
      final createdLoadGate = Completer<void>();
      final receivedLoadGate = Completer<void>();
      final operations = _FakePaymentLinkOperations(
        createdLoadGate: createdLoadGate,
        receivedLoadGate: receivedLoadGate,
      );
      await _pumpPaymentLinksScreen(
        tester,
        operations: operations,
        bootstrap: _homeBootstrap,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(_incomingLink.toUri().toString());
      for (var i = 0; i < 10 && operations.receivedLoadCalls == 0; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(operations.createdLoadCalls, 1);
      // App-level recovery and the route's initial snapshot both begin before
      // intake is consumed; neither waits for the Created-card load.
      expect(operations.receivedLoadCalls, 2);
      expect(operations.allowLongSyncCalls, isEmpty);

      createdLoadGate.complete();
      await tester.pump();
      expect(operations.allowLongSyncCalls, isEmpty);

      receivedLoadGate.complete();
      await tester.pumpAndSettle();

      expect(operations.allowLongSyncCalls, [isFalse]);
      expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    },
  );

  testWidgets('retries a transient Received load before showing an error', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(receivedLoadFailures: 1);

    await _pumpPaymentLinksScreen(tester, operations: operations);
    await tester.pumpAndSettle();

    expect(operations.receivedLoadCalls, 2);
    expect(find.text('Received Gift Cards could not be loaded.'), findsNothing);
  });

  testWidgets(
    'mobile keeps a checked Gift Card out of Received until claim starts',
    (tester) async {
      final operations = _FakePaymentLinkOperations();
      await _pumpPaymentLinksScreen(
        tester,
        operations: operations,
        bootstrap: _homeBootstrap,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(_incomingLink.toUri().toString());
      await tester.pumpAndSettle();

      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(operations.receivedRecords, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_claim_button')),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(operations.receivedRecords, hasLength(1));
      expect(
        operations.receivedRecords.single.status,
        PaymentLinkReceivedStatus.receiving,
      );
    },
    tags: ['mobile'],
  );

  testWidgets('shows selected artwork and Receiving while claim is pending', (
    tester,
  ) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PaymentLinkGiftCard>(find.byType(PaymentLinkGiftCard))
          .artwork,
      PaymentLinkCardArtwork.ruby,
    );

    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    expect(find.text('Receiving...'), findsOneWidget);
    expect(find.text('Received'), findsWidgets);
    expect(find.text('You’ve received\na gift card!'), findsNothing);
    final receivedRow = find.byKey(
      const ValueKey('payment_link_received_u1paymentlinkaddress'),
    );
    expect(
      find.descendant(
        of: receivedRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsOneWidget,
    );
    final receivedThumbnail = tester.widget<Image>(
      find.descendant(of: receivedRow, matching: find.byType(Image)).first,
    );
    expect(
      (receivedThumbnail.image as AssetImage).assetName,
      PaymentLinkCardArtwork.ruby.assetPath,
    );

    claimCompleter.complete(_broadcastedClaimResult);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Receiving...'), findsOneWidget);
    expect(find.text('Gift claim submitted'), findsOneWidget);

    operations.receivedClaimStatuses[_incomingLink.address] =
        PaymentLinkReceivedStatus.received;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Receiving...'), findsNothing);
    expect(find.text('Received'), findsWidgets);
    expect(
      find.descendant(
        of: receivedRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsNothing,
    );
    expect(operations.receivedRecords.single.claimLink, isNull);
  });

  testWidgets('restores an in-flight received Card after the screen restarts', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations();
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(operations.receivedRecords.single.claimTxids, 'claim-txid');
    expect(find.text('Receiving...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpPaymentLinksScreen(tester, operations: operations);
    await tester.tap(find.text('Received').first);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Receiving...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_received_u1paymentlinkaddress')),
      findsOneWidget,
    );
  });

  testWidgets('keeps a pending broadcast in Receiving state', (tester) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    claimCompleter.complete(
      const PaymentLinkClaimResult(
        txids: 'pending-claim-txid',
        status: PaymentLinkClaimBroadcastStatus.pendingBroadcast,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Receiving...'), findsOneWidget);
    expect(find.text('Gift claim submitted'), findsOneWidget);
    expect(find.text('Gift claimed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(operations.discardedClaimAddresses, isEmpty);
  });

  testWidgets('keeps the claim database while submission is in flight', (
    tester,
  ) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(operations.discardedClaimAddresses, isEmpty);

    claimCompleter.complete(
      const PaymentLinkClaimResult(
        txids: 'pending-claim-txid',
        status: PaymentLinkClaimBroadcastStatus.pendingBroadcast,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(operations.discardedClaimAddresses, isEmpty);
  });

  testWidgets('prepares a second Gift Card while the first claim broadcasts', (
    tester,
  ) async {
    final firstClaim = Completer<PaymentLinkClaimResult>();
    final secondClaim = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(
      claimCompleters: {
        _incomingLink.address: firstClaim,
        _secondIncomingLink.address: secondClaim,
      },
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();
    expect(operations.claimedLinks.map((link) => link.address), [
      _incomingLink.address,
    ]);

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_secondIncomingLink.toUri().toString());
    await tester.pumpAndSettle();
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    expect(operations.claimedLinks.map((link) => link.address), [
      _incomingLink.address,
      _secondIncomingLink.address,
    ]);
    firstClaim.complete(_broadcastedClaimResult);
    secondClaim.complete(_broadcastedClaimResult);
    await tester.pump();
  });

  testWidgets('does not reopen a Gift Card whose claim is submitting', (
    tester,
  ) async {
    final claim = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(claimCompleter: claim);
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pump(const Duration(milliseconds: 250));

    expect(operations.allowLongSyncCalls, [isFalse]);
    expect(operations.claimedLinks, hasLength(1));
    claim.complete(_broadcastedClaimResult);
    await tester.pump();
  });

  testWidgets('returns a failed claim to an actionable Received card', (
    tester,
  ) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    expect(find.text('Receiving...'), findsOneWidget);
    claimCompleter.completeError(StateError('claim failed'));
    await tester.pumpAndSettle();

    expect(find.text('Receiving...'), findsNothing);
    expect(find.text('Claim'), findsOneWidget);
    expect(find.textContaining('Gift Card claim failed.'), findsOneWidget);
  });

  testWidgets('reopens intake when the prepared destination changed', (
    tester,
  ) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = _FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: _homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    claimCompleter.completeError(
      const PaymentLinkClaimDestinationChangedException(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paste card link'), findsOneWidget);
    expect(
      find.textContaining(
        'Receiving account changed. Open the Gift Card again to continue.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Gift Card claim failed.'), findsNothing);
  });

  testWidgets('copies a persisted created link without reclaim controls', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(records: [_sharedRecovery]);
    await _pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('4.45 ZEC'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsOneWidget);
    expect(find.bySemanticsLabel('Show Gift Card QR code'), findsOneWidget);
    expect(find.text('Reclaim'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Copy Gift Card link'));
    await tester.pumpAndSettle();
    expect(operations.sharedLinks, [_incomingLink]);
  });

  testWidgets('saves the selected artwork QR image to the chosen path', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(records: [_fundedRecovery]);
    final imageSaver = _FakePaymentLinkQrImageSaver();
    await _pumpPaymentLinksScreen(
      tester,
      operations: operations,
      qrImageSaver: imageSaver,
    );

    await tester.tap(find.bySemanticsLabel('Show Gift Card QR code'));
    await tester.pumpAndSettle();

    expect(find.text('Share Gift Card'), findsOneWidget);
    final shareCard = tester.widget<PaymentLinkQrShareCard>(
      find.byType(PaymentLinkQrShareCard),
    );
    expect(shareCard.artwork, PaymentLinkCardArtwork.ruby);
    expect(shareCard.qrData, _incomingLink.toUri().toString());

    await tester.tap(find.text('Save QR code'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 50; attempt++) {
        if (imageSaver.savedImages.isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(imageSaver.savedImages, hasLength(1));
    expect(
      imageSaver.savedImages.single.take(8),
      orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
    );
    expect(operations.sharedLinks, [_incomingLink]);
  });

  testWidgets('shows an interrupted funding draft without reclaim controls', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(records: [_draftRecovery]);
    await _pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('Funding incomplete'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Reclaim'), findsNothing);
  });
}

Future<void> _pumpPaymentLinksScreen(
  WidgetTester tester, {
  _FakePaymentLinkOperations? operations,
  _FakePaymentLinkClipboard? clipboard,
  PaymentLinkHardwareSigningService? hardwareSigning,
  PaymentLinkQrImageSaver? qrImageSaver,
  AccountNotifier? accountNotifier,
  AppBootstrapState? bootstrap,
  BigInt? spendableBalance,
  FakeSyncNotifier? syncNotifier,
}) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final paymentLinkOperations = operations ?? _FakePaymentLinkOperations();
  final paymentLinkClipboard = clipboard ?? _FakePaymentLinkClipboard();
  final appBootstrap = bootstrap ?? _bootstrap;
  final initialAccountUuid =
      appBootstrap.initialAccountState.activeAccountUuid ?? 'account-1';

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(appBootstrap),
        if (accountNotifier != null)
          accountProvider.overrideWith(() => accountNotifier),
        paymentLinkOperationsProvider.overrideWithValue(paymentLinkOperations),
        paymentLinkClipboardProvider.overrideWithValue(paymentLinkClipboard),
        if (qrImageSaver != null)
          paymentLinkQrImageSaverProvider.overrideWithValue(qrImageSaver),
        if (hardwareSigning != null)
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(
            hardwareSigning,
          ),
        syncProvider.overrideWith(
          () =>
              syncNotifier ??
              FakeSyncNotifier(
                SyncState(
                  accountUuid: initialAccountUuid,
                  hasAccountScopedData: true,
                  isSyncComplete: true,
                  percentage: 1,
                  displayTargetPercentage: 1,
                  spendableBalance:
                      spendableBalance ?? BigInt.from(14223000000),
                  displaySpendableBalance:
                      spendableBalance ?? BigInt.from(14223000000),
                ),
              ),
        ),
        ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
          return const IronwoodHomeMigrationCtaState.hidden();
        }),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
        ironwoodPostMigrationStateProvider.overrideWith((ref) async {
          return const IronwoodPostMigrationState.unavailable();
        }),
        ironwoodMigrationAnnouncementProvider.overrideWith((ref) async {
          return const IronwoodMigrationAnnouncementState.hidden();
        }),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          _FakeMigrationCoordinator.new,
        ),
      ],
      child: const ZcashWalletApp(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    final hasDesktopScreen = find
        .byKey(const ValueKey('payment_links_desktop_screen'))
        .evaluate()
        .isNotEmpty;
    final hasMobileScreen = find
        .byKey(const ValueKey('payment_links_mobile_screen'))
        .evaluate()
        .isNotEmpty;
    if (hasDesktopScreen || hasMobileScreen) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _homeBootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _hardwareAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'hardware-account',
      name: 'Keystone',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'hardware-account',
  activeAddress: 'u1hardwareaddress',
);

final _hardwareBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: _hardwareAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _twoAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-2',
      name: 'Savings',
      order: 1,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

final _twoAccountBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: _twoAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _incomingLink = VizorPaymentLink(
  network: 'main',
  address: 'u1paymentlinkaddress',
  amountZatoshi: BigInt.from(445000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
  presentation: const PaymentLinkPresentation(
    artworkId: 'ruby',
    message: 'Congratulations!',
  ),
);

final _secondIncomingLink = VizorPaymentLink(
  network: 'main',
  address: 'u1secondpaymentlinkaddress',
  amountZatoshi: BigInt.from(225000000),
  mnemonic: List.filled(24, 'legal').join(' '),
  birthdayHeight: 3000001,
  label: 'Second payment link',
  createdAt: DateTime.utc(2026, 8, 7),
  presentation: const PaymentLinkPresentation(
    artworkId: 'gift',
    message: 'A second gift!',
  ),
);

final _sharedRecovery = PaymentLinkRecoveryRecord(
  link: _incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.shared,
  updatedAt: DateTime.utc(2026, 8, 6),
  fundingTxids: 'funding-txid',
);

final _fundedRecovery = PaymentLinkRecoveryRecord(
  link: _incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.funded,
  updatedAt: DateTime.utc(2026, 8, 6),
  fundingTxids: 'funding-txid',
);

final _draftRecovery = PaymentLinkRecoveryRecord(
  link: _incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.draft,
  updatedAt: DateTime.utc(2026, 8, 6),
);

class _FakePaymentLinkOperations implements PaymentLinkOperations {
  _FakePaymentLinkOperations({
    List<PaymentLinkRecoveryRecord> records = const [],
    List<PaymentLinkReceivedRecord> receivedRecords = const [],
    this.claimCompleter,
    this.claimCompleters = const {},
    this.createdLoadGate,
    this.receivedLoadGate,
    this.receivedLoadFailures = 0,
    this.prepareClaimFailures = 0,
    this.prepareClaimError,
    this.fundingMetadataSavedOnCreate = true,
    this.fundingBroadcastAcceptedOnCreate = true,
    this.fundingConfirmationCount = kPaymentLinkShareConfirmationTarget,
    this.claimable = true,
    this.waitingForFundingConfirmations = false,
    this.longSyncConfirmationRequired = false,
  }) : records = List.of(records),
       receivedRecords = List.of(receivedRecords);

  final Completer<PaymentLinkClaimResult>? claimCompleter;
  final Map<String, Completer<PaymentLinkClaimResult>> claimCompleters;
  final Completer<void>? createdLoadGate;
  final Completer<void>? receivedLoadGate;
  int receivedLoadFailures;
  int prepareClaimFailures;
  final Object? prepareClaimError;
  final bool fundingMetadataSavedOnCreate;
  final bool fundingBroadcastAcceptedOnCreate;
  int fundingConfirmationCount;
  bool expireFundingOnInspect = false;
  bool claimable;
  bool waitingForFundingConfirmations;
  final bool longSyncConfirmationRequired;
  final List<PaymentLinkRecoveryRecord> records;
  final List<PaymentLinkReceivedRecord> receivedRecords;
  final Map<String, PaymentLinkReceivedStatus> receivedClaimStatuses = {};
  final List<BigInt> createdAmounts = [];
  final List<String> createdFromAccounts = [];
  final List<String?> createdArtworkIds = [];
  final List<String?> createdMessages = [];
  final List<String> quotedAccounts = [];
  final List<String> maxQuotedAccounts = [];
  final List<VizorPaymentLink> sharedLinks = [];
  final List<VizorPaymentLink> claimedLinks = [];
  final List<String> discardedClaimAddresses = [];
  final List<bool> allowLongSyncCalls = [];
  final List<VizorPaymentLink> preparedLinks = [];
  int createdLoadCalls = 0;
  int receivedLoadCalls = 0;
  int fundingMetadataRetries = 0;

  @override
  Future<PaymentLinkFundingQuote> quoteMaxFunding({
    required String sourceAccountUuid,
  }) async {
    maxQuotedAccounts.add(sourceAccountUuid);
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: BigInt.from(14222980000),
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    quotedAccounts.add(sourceAccountUuid);
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: amountZatoshi,
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    createdFromAccounts.add(sourceAccountUuid);
    createdArtworkIds.add(presentation?.artworkId);
    createdMessages.add(presentation?.message);
    final link = VizorPaymentLink(
      network: 'main',
      address: 'u1createdpaymentlinkaddress',
      amountZatoshi: amountZatoshi,
      mnemonic: List.filled(24, 'abandon').join(' '),
      birthdayHeight: 3000000,
      label: 'Payment link',
      createdAt: DateTime.utc(2026, 8, 6),
      presentation: presentation,
    );
    records.add(
      PaymentLinkRecoveryRecord(
        link: link,
        sourceAccountUuid: sourceAccountUuid,
        state: fundingMetadataSavedOnCreate
            ? PaymentLinkRecoveryState.funded
            : PaymentLinkRecoveryState.draft,
        updatedAt: DateTime.utc(2026, 8, 6),
        fundingTxids: fundingMetadataSavedOnCreate ? 'funding-txid' : null,
      ),
    );
    return PaymentLinkFundingResult(
      link: link,
      txids: 'funding-txid',
      fundingMetadataSaved: fundingMetadataSavedOnCreate,
      broadcastAccepted: fundingBroadcastAcceptedOnCreate,
    );
  }

  @override
  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  }) async {
    fundingMetadataRetries += 1;
    final index = records.indexWhere(
      (record) => record.link.address == address,
    );
    records[index] = records[index].copyWith(
      state: PaymentLinkRecoveryState.funded,
      fundingTxids: fundingTxids,
      updatedAt: DateTime.utc(2026, 8, 6, 1),
    );
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async {
    createdLoadCalls += 1;
    await createdLoadGate?.future;
    return List.unmodifiable(records);
  }

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) async {
    sharedLinks.add(link);
    final index = records.indexWhere(
      (record) => record.link.address == link.address,
    );
    final updated = records[index].copyWith(
      state: PaymentLinkRecoveryState.shared,
      updatedAt: DateTime.utc(2026, 8, 6, 1),
    );
    records[index] = updated;
    return updated;
  }

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    final expiredAddresses = expireFundingOnInspect
        ? {
            for (final record in records)
              if (record.state == PaymentLinkRecoveryState.funded)
                record.link.address,
          }
        : const <String>{};
    this.records.removeWhere(
      (record) => expiredAddresses.contains(record.link.address),
    );
    return {
      for (final record in records)
        if (!expiredAddresses.contains(record.link.address))
          record.link.address: PaymentLinkFundingProgress(
            confirmationCount: fundingConfirmationCount,
          ),
    };
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async {
    receivedLoadCalls += 1;
    await receivedLoadGate?.future;
    if (receivedLoadFailures > 0) {
      receivedLoadFailures -= 1;
      throw StateError('transient Received load failure');
    }
    return List.unmodifiable(receivedRecords);
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records,
  ) async {
    for (var index = 0; index < receivedRecords.length; index++) {
      final record = receivedRecords[index];
      final status = receivedClaimStatuses[record.address] ?? record.status;
      receivedRecords[index] = switch (status) {
        PaymentLinkReceivedStatus.readyToClaim => record.copyWith(
          status: status,
          destinationAccountUuid: null,
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 3),
        ),
        PaymentLinkReceivedStatus.submitting => record.copyWith(
          status: status,
          destinationAccountUuid: record.destinationAccountUuid ?? 'account-1',
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 3),
        ),
        PaymentLinkReceivedStatus.receiving => record,
        PaymentLinkReceivedStatus.received => record.copyWith(
          status: status,
          claimLink: null,
          updatedAt: DateTime.utc(2026, 8, 6, 3),
        ),
      };
    }
    return List.unmodifiable(receivedRecords);
  }

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    preparedLinks.add(link);
    allowLongSyncCalls.add(allowLongSync);
    final configuredError = prepareClaimError;
    if (configuredError != null) throw configuredError;
    if (prepareClaimFailures > 0) {
      prepareClaimFailures -= 1;
      throw StateError('transient claim preparation failure');
    }
    if (longSyncConfirmationRequired && !allowLongSync) {
      throw const PaymentLinkLongSyncConfirmationRequired();
    }
    return PaymentLinkClaimSession(
      link: link,
      destinationAddress: 'u1receiver',
      destinationAccountUuid: 'account-1',
      directory: Directory('/tmp/vizor-payment-link-test'),
      dbPath: '/tmp/vizor-payment-link-test/wallet.db',
      accountUuid: 'payment-link-account',
      totalZatoshi: claimable ? link.amountZatoshi : BigInt.zero,
      claimableZatoshi: claimable ? link.amountZatoshi : BigInt.zero,
      feeZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
      fundingConfirmationCount: fundingConfirmationCount,
      waitingForFundingConfirmations: waitingForFundingConfirmations,
    );
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    if (!receivedRecords.any(
      (record) => record.address == session.link.address,
    )) {
      receivedRecords.insert(
        0,
        PaymentLinkReceivedRecord.fromLink(
          session.link,
          updatedAt: DateTime.utc(2026, 8, 6),
        ),
      );
    }
    try {
      final result = await claimLink(session.link);
      _replaceReceivedRecord(
        session.link.address,
        (record) => record.copyWith(
          status: PaymentLinkReceivedStatus.receiving,
          destinationAccountUuid: session.destinationAccountUuid,
          claimTxids: result.txids,
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      );
      return result;
    } catch (_) {
      _replaceReceivedRecord(
        session.link.address,
        (record) => record.copyWith(
          status: PaymentLinkReceivedStatus.readyToClaim,
          destinationAccountUuid: null,
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {
    discardedClaimAddresses.add(session.link.address);
  }

  @override
  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link) async {
    claimedLinks.add(link);
    return claimCompleters[link.address]?.future ??
        claimCompleter?.future ??
        _broadcastedClaimResult;
  }

  void _replaceReceivedRecord(
    String address,
    PaymentLinkReceivedRecord Function(PaymentLinkReceivedRecord record) update,
  ) {
    final index = receivedRecords.indexWhere(
      (record) => record.address == address,
    );
    if (index >= 0) receivedRecords[index] = update(receivedRecords[index]);
  }
}

class _SwitchablePaymentLinkAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => _twoAccountState;

  void setActiveAccount(String uuid) {
    final current = state.value ?? _twoAccountState;
    state = AsyncData(
      current.copyWith(
        activeAccountUuid: uuid,
        activeAddress: 'u1${uuid}address',
      ),
    );
  }
}

const _broadcastedClaimResult = PaymentLinkClaimResult(
  txids: 'claim-txid',
  status: PaymentLinkClaimBroadcastStatus.broadcasted,
);

class _FakePaymentLinkClipboard implements PaymentLinkClipboard {
  _FakePaymentLinkClipboard({this.text, this.readCompleter});

  String? text;
  final Completer<String?>? readCompleter;
  final List<String> copiedSecrets = [];
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    text = '';
  }

  @override
  Future<void> copySecret(String text) async {
    copiedSecrets.add(text);
    this.text = text;
  }

  @override
  Future<String?> readText() => readCompleter?.future ?? Future.value(text);
}

class _FakePaymentLinkQrImageSaver implements PaymentLinkQrImageSaver {
  final List<Uint8List> savedImages = [];

  @override
  Future<bool> savePng(Uint8List pngBytes) async {
    savedImages.add(Uint8List.fromList(pngBytes));
    return true;
  }
}

class _FakePaymentLinkHardwareSigningService
    implements PaymentLinkHardwareSigningService {
  _FakePaymentLinkHardwareSigningService({this.createCompleter});

  final Completer<PaymentLinkHardwarePcztDraft>? createCompleter;
  final createdAmounts = <BigInt>[];
  final createdFromAccounts = <String>[];
  final createdArtworkIds = <String?>[];
  final createdMessages = <String?>[];
  final discardedDrafts = <BigInt>[];

  PaymentLinkHardwarePcztDraft get draft => PaymentLinkHardwarePcztDraft(
    link: _incomingLink,
    pcztBytes: const [1, 2, 3],
    needsSaplingParams: false,
    feeZatoshi: BigInt.from(10000),
    proposalId: BigInt.one,
    sendFlowId: 'test-payment-link-hardware',
  );

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    createdFromAccounts.add(sourceAccountUuid);
    createdArtworkIds.add(presentation?.artworkId);
    createdMessages.add(presentation?.message);
    return createCompleter?.future ?? draft;
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async => const ['ur:zcash-sign-batch/test'];

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async => const [10, 11];

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [7, 8, 9];

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    discardedDrafts.add(draft.proposalId);
  }

  @override
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const PaymentLinkHardwareFundingResult(
      txids: 'hardware-funding-txid',
      status: 'broadcasted',
      fundingMetadataSaved: true,
    );
  }
}

class _FakeMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

Rect _globalCaretRect(RenderEditable editable, int offset) {
  final caretLocal = editable.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
  return editable.localToGlobal(caretLocal.topLeft) & caretLocal.size;
}

RenderEditable _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found!;
}
