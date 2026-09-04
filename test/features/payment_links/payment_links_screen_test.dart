import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_flip.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_qr_share_card.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_confetti.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_links_screen_support.dart';

void main() {
  setUpAll(loadPaymentLinksTestFonts);

  testWidgets('shows the truthful landing and help copy', (tester) async {
    await pumpPaymentLinksScreen(tester);

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
    await pumpPaymentLinksScreen(tester);

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
    final operations = FakePaymentLinkOperations();
    final clipboard = FakePaymentLinkClipboard();
    await pumpPaymentLinksScreen(
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
    final caretRect = globalCaretRect(
      findRenderEditable(editableRoot),
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
      final operations = FakePaymentLinkOperations(
        fundingMetadataSavedOnCreate: false,
      );
      await pumpPaymentLinksScreen(tester, operations: operations);

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
      await pumpPaymentLinksScreen(
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
    final operations = FakePaymentLinkOperations();
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
    await pumpPaymentLinksScreen(
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
    final operations = FakePaymentLinkOperations(
      records: [fundedRecovery],
      fundingConfirmationCount: 0,
    );
    await pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsNothing);

    operations.fundingConfirmationCount = 1;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsNothing);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsOneWidget);
  });

  testWidgets('removes an unshared Card after funding expires', (tester) async {
    final operations = FakePaymentLinkOperations(
      records: [fundedRecovery],
      fundingConfirmationCount: 0,
    );
    await pumpPaymentLinksScreen(tester, operations: operations);

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
    final operations = FakePaymentLinkOperations(fundingConfirmationCount: 0);
    await pumpPaymentLinksScreen(tester, operations: operations);

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
      final operations = FakePaymentLinkOperations(
        fundingBroadcastAcceptedOnCreate: false,
        fundingConfirmationCount: 0,
      );
      await pumpPaymentLinksScreen(tester, operations: operations);

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
    final operations = FakePaymentLinkOperations(claimable: false);
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
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
    final operations = FakePaymentLinkOperations(
      claimable: false,
      waitingForFundingConfirmations: true,
      fundingConfirmationCount: 2,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
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

  testWidgets('keeps the Card when the confirmation wait is left', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      claimable: false,
      waitingForFundingConfirmations: true,
      fundingConfirmationCount: 2,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for 6 confirmations.'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppBackLink, 'Home'));
    await tester.pumpAndSettle();

    // The Card is persisted as still-to-claim and keeps its claim database,
    // so it stays in the Received list instead of needing the bearer link.
    expect(operations.retainedClaimAddresses, [incomingLink.address]);
    expect(operations.discardedClaimAddresses, isEmpty);
    expect(operations.receivedRecords, hasLength(1));
    expect(operations.receivedRecords.single.address, incomingLink.address);
    expect(
      operations.receivedRecords.single.status,
      PaymentLinkReceivedStatus.readyToClaim,
    );
    expect(find.text('Waiting for 6 confirmations.'), findsNothing);
    expect(find.text('No Gift Cards yet'), findsNothing);
    expect(find.text('Claim'), findsOneWidget);
  });

  testWidgets('leaving a preview stops a later account switch from reopening '
      'redeem', (tester) async {
    final accountNotifier = SwitchablePaymentLinkAccountNotifier();
    final operations = FakePaymentLinkOperations();
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
      accountNotifier: accountNotifier,
      bootstrap: twoAccountBootstrap,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('You\u2019ve received\na gift card!'), findsOneWidget);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();

    expect(operations.discardedClaimAddresses, [incomingLink.address]);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Paste card link'), findsNothing);
    expect(find.textContaining('Active account changed.'), findsNothing);
    expect(find.text('No Gift Cards yet'), findsOneWidget);
  });

  testWidgets(
    'hardware creation opens Keystone signing and releases on cancel',
    (tester) async {
      final hardwareSigning = FakePaymentLinkHardwareSigningService();
      await pumpPaymentLinksScreen(
        tester,
        bootstrap: hardwareBootstrap,
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
    final operations = FakePaymentLinkOperations();
    await pumpPaymentLinksScreen(tester, operations: operations);

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
      final operations = FakePaymentLinkOperations();
      final accountNotifier = SwitchablePaymentLinkAccountNotifier();
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
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        accountNotifier: accountNotifier,
        bootstrap: twoAccountBootstrap,
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
    final hardwareSigning = FakePaymentLinkHardwareSigningService(
      createCompleter: createCompleter,
    );
    await pumpPaymentLinksScreen(
      tester,
      bootstrap: hardwareBootstrap,
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

  testWidgets('account switch cancels an open Keystone Gift Card request', (
    tester,
  ) async {
    final accountNotifier = SwitchablePaymentLinkAccountNotifier(
      twoAccountHardwareState,
    );
    final hardwareSigning = FakePaymentLinkHardwareSigningService();
    await pumpPaymentLinksScreen(
      tester,
      accountNotifier: accountNotifier,
      bootstrap: twoAccountHardwareBootstrap,
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
    await tester.pumpAndSettle();

    expect(find.byType(KeystoneSigningModal), findsOneWidget);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(KeystoneSigningModal), findsNothing);
    expect(hardwareSigning.discardedDrafts, [BigInt.one]);
    expect(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      findsOneWidget,
    );
  });

  testWidgets('account switch during a claim releases the prepared session', (
    tester,
  ) async {
    final accountNotifier = SwitchablePaymentLinkAccountNotifier();
    final operations = FakePaymentLinkOperations();
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
      accountNotifier: accountNotifier,
      bootstrap: twoAccountBootstrap,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('You\u2019ve received\na gift card!'), findsOneWidget);
    expect(operations.discardedClaimAddresses, isEmpty);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('You\u2019ve received\na gift card!'), findsNothing);
    expect(find.text('Paste card link'), findsOneWidget);
    expect(operations.discardedClaimAddresses, [incomingLink.address]);
    expect(find.textContaining('Active account changed.'), findsOneWidget);
  });

  testWidgets(
    'account switch during claim preparation releases the prepared session',
    (tester) async {
      final accountNotifier = SwitchablePaymentLinkAccountNotifier();
      final prepareClaimGate = Completer<void>();
      final operations = FakePaymentLinkOperations(
        prepareClaimGates: {1: prepareClaimGate},
      );
      final clipboard = FakePaymentLinkClipboard(
        text: incomingLink.toUri().toString(),
      );
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        clipboard: clipboard,
        accountNotifier: accountNotifier,
        bootstrap: twoAccountBootstrap,
      );

      await tester.tap(find.text('Redeem a card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste card link'));
      await tester.pump();

      accountNotifier.setActiveAccount('account-2');
      await tester.pump();

      prepareClaimGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('You\u2019ve received\na gift card!'), findsNothing);
      expect(find.text('Paste card link'), findsOneWidget);
      expect(operations.discardedClaimAddresses, [incomingLink.address]);
      expect(find.textContaining('Active account changed.'), findsOneWidget);
    },
  );

  testWidgets(
    'account switch during a waiting claim preparation keeps the Card',
    (tester) async {
      final accountNotifier = SwitchablePaymentLinkAccountNotifier();
      final prepareClaimGate = Completer<void>();
      final operations = FakePaymentLinkOperations(
        prepareClaimGates: {1: prepareClaimGate},
        waitingForFundingConfirmations: true,
        fundingConfirmationCount: 0,
      );
      final clipboard = FakePaymentLinkClipboard(
        text: incomingLink.toUri().toString(),
      );
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        clipboard: clipboard,
        accountNotifier: accountNotifier,
        bootstrap: twoAccountBootstrap,
      );

      await tester.tap(find.text('Redeem a card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste card link'));
      await tester.pump();

      accountNotifier.setActiveAccount('account-2');
      await tester.pump();

      prepareClaimGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(operations.retainedClaimAddresses, [incomingLink.address]);
      expect(operations.discardedClaimAddresses, isEmpty);
      expect(find.textContaining('Active account changed.'), findsOneWidget);
    },
  );

  testWidgets('account switch while waiting for confirmations keeps the Card', (
    tester,
  ) async {
    final accountNotifier = SwitchablePaymentLinkAccountNotifier();
    final operations = FakePaymentLinkOperations(
      waitingForFundingConfirmations: true,
      fundingConfirmationCount: 0,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
      accountNotifier: accountNotifier,
      bootstrap: twoAccountBootstrap,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for 6 confirmations.'), findsOneWidget);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(operations.retainedClaimAddresses, [incomingLink.address]);
    expect(operations.discardedClaimAddresses, isEmpty);
    expect(find.textContaining('Active account changed.'), findsOneWidget);
  });

  testWidgets('a confirmation refresh does not delete a retained claim', (
    tester,
  ) async {
    final refreshGate = Completer<void>();
    final operations = FakePaymentLinkOperations(
      prepareClaimGates: {2: refreshGate},
      waitingForFundingConfirmations: true,
      fundingConfirmationCount: 0,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 10));
    expect(operations.preparedLinks, hasLength(2));

    await tester.tap(find.widgetWithText(AppBackLink, 'Home'));
    await tester.pumpAndSettle();

    refreshGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(operations.retainedClaimAddresses, [incomingLink.address]);
    expect(operations.discardedClaimAddresses, isEmpty);
  });

  testWidgets('route dispose keeps a Card that is waiting to be claimable', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      waitingForFundingConfirmations: true,
      fundingConfirmationCount: 0,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(
        find.byKey(const ValueKey('payment_links_desktop_screen')),
      ),
    ).go('/home');
    await tester.pumpAndSettle();

    expect(operations.retainedClaimAddresses, [incomingLink.address]);
    expect(operations.discardedClaimAddresses, isEmpty);
  });

  testWidgets('route dispose keeps a preview of a listed Received Card', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      receivedRecords: [
        PaymentLinkReceivedRecord.fromLink(
          incomingLink,
          updatedAt: DateTime.utc(2026, 8, 6),
        ),
      ],
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(
        find.byKey(const ValueKey('payment_links_desktop_screen')),
      ),
    ).go('/home');
    await tester.pumpAndSettle();

    expect(operations.retainedClaimAddresses, [incomingLink.address]);
    expect(operations.discardedClaimAddresses, isEmpty);
  });

  testWidgets('route dispose releases a claimable preview', (tester) async {
    final operations = FakePaymentLinkOperations();
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(
        find.byKey(const ValueKey('payment_links_desktop_screen')),
      ),
    ).go('/home');
    await tester.pumpAndSettle();

    expect(operations.discardedClaimAddresses, [incomingLink.address]);
    expect(operations.retainedClaimAddresses, isEmpty);
  });

  testWidgets('created Cards list only the accounts that funded them', (
    tester,
  ) async {
    final accountNotifier = SwitchablePaymentLinkAccountNotifier();
    final operations = FakePaymentLinkOperations(
      records: [fundedRecovery, otherAccountRecovery, unknownOriginRecovery],
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      accountNotifier: accountNotifier,
      bootstrap: twoAccountBootstrap,
    );

    expect(
      find.byKey(ValueKey('payment_link_recovery_${incomingLink.address}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('payment_link_recovery_${otherAccountLink.address}')),
      findsNothing,
    );
    expect(
      find.byKey(
        ValueKey('payment_link_recovery_${unknownOriginLink.address}'),
      ),
      findsOneWidget,
    );

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(ValueKey('payment_link_recovery_${incomingLink.address}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('payment_link_recovery_${otherAccountLink.address}')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('payment_link_recovery_${unknownOriginLink.address}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an account switch leaves the metadata retry reachable', (
    tester,
  ) async {
    final accountNotifier = SwitchablePaymentLinkAccountNotifier();
    final operations = FakePaymentLinkOperations(
      fundingMetadataSavedOnCreate: false,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      accountNotifier: accountNotifier,
      bootstrap: twoAccountBootstrap,
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
    await tester.pumpAndSettle();

    expect(find.text('Try saving again'), findsOneWidget);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Try saving again'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      findsNothing,
    );

    await tester.tap(find.text('Try saving again'));
    await tester.pumpAndSettle();

    expect(operations.fundingMetadataRetries, 1);
  });

  testWidgets('enables manual redeem intake', (tester) async {
    final operations = FakePaymentLinkOperations();
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
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
    final operations = FakePaymentLinkOperations();
    final clipboardRead = Completer<String?>();
    final clipboard = FakePaymentLinkClipboard(readCompleter: clipboardRead);
    await pumpPaymentLinksScreen(
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
        .receive(incomingLink.toUri().toString());
    clipboardRead.complete(secondIncomingLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(operations.preparedLinks.single.address, secondIncomingLink.address);
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink?.address,
      incomingLink.address,
    );
  });

  testWidgets('confirms before checking a Gift Card with a long scan', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      longSyncConfirmationRequired: true,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
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

  testWidgets('declining the long scan warning keeps the Card', (tester) async {
    final operations = FakePaymentLinkOperations(
      longSyncConfirmationRequired: true,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(operations.keptLinkAddresses, [incomingLink.address]);
    expect(operations.receivedRecords.single.address, incomingLink.address);
  });

  testWidgets('a check that fails to run keeps the Card', (tester) async {
    final operations = FakePaymentLinkOperations(prepareClaimFailures: 1);
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(operations.keptLinkAddresses, [incomingLink.address]);
    expect(operations.receivedRecords.single.address, incomingLink.address);
  });

  testWidgets('routes an accepted incoming payment link and claims it', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations();
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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
      incomingLink.toUri().toString(),
    ]);
    expect(find.text('Gift claim submitted'), findsOneWidget);
    expect(find.text('Receiving...'), findsOneWidget);
  });

  testWidgets('defers an incoming Gift Card while another card is being made', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations();
    await pumpPaymentLinksScreen(tester, operations: operations);
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
        .receive(incomingLink.toUri().toString());
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
    final operations = FakePaymentLinkOperations(prepareClaimFailures: 1);
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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

  testWidgets('names the network when a pasted card is for another network', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      prepareClaimError: const PaymentLinkNetworkMismatchException(
        linkNetwork: 'test',
        walletNetwork: 'main',
      ),
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(
      find.text('This Gift Card is for a different Zcash network.'),
      findsOneWidget,
    );
    expect(
      find.text('Card balance could not be checked. Try again.'),
      findsNothing,
    );
    // A different network never resolves itself, so no retry is offered.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Paste card link'), findsOneWidget);
  });

  testWidgets('discards a previous claim wallet when its identity changes', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations();
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();

    final differentBirthdayLink = VizorPaymentLink(
      network: incomingLink.network,
      address: incomingLink.address,
      amountZatoshi: incomingLink.amountZatoshi,
      mnemonic: incomingLink.mnemonic,
      birthdayHeight: incomingLink.birthdayHeight - 1,
      label: incomingLink.label,
      createdAt: incomingLink.createdAt,
      presentation: incomingLink.presentation,
    );
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(differentBirthdayLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncCalls, [isFalse, isFalse]);
    expect(operations.discardedClaimAddresses, [incomingLink.address]);
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
  });

  testWidgets('does not reopen an in-flight received Gift Card', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      receivedRecords: [
        PaymentLinkReceivedRecord(
          network: incomingLink.network,
          address: incomingLink.address,
          amountZatoshi: incomingLink.amountZatoshi,
          createdAt: incomingLink.createdAt,
          artworkId: incomingLink.presentation?.artworkId,
          message: incomingLink.presentation?.message,
          status: PaymentLinkReceivedStatus.submitting,
          claimLink: incomingLink,
          destinationAccountUuid: 'account-1',
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      ],
      prepareClaimError: const PaymentLinkClaimInFlightException(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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
      final operations = FakePaymentLinkOperations(
        createdLoadGate: createdLoadGate,
        receivedLoadGate: receivedLoadGate,
      );
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        bootstrap: homeBootstrap,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(incomingLink.toUri().toString());
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
    final operations = FakePaymentLinkOperations(receivedLoadFailures: 1);

    await pumpPaymentLinksScreen(tester, operations: operations);
    await tester.pumpAndSettle();

    expect(operations.receivedLoadCalls, 2);
    expect(find.text('Received Gift Cards could not be loaded.'), findsNothing);
  });

  testWidgets('shows selected artwork and Receiving while claim is pending', (
    tester,
  ) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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

    claimCompleter.complete(broadcastedClaimResult);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Receiving...'), findsOneWidget);
    expect(find.text('Gift claim submitted'), findsOneWidget);

    operations.receivedClaimStatuses[incomingLink.address] =
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
    final operations = FakePaymentLinkOperations();
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(operations.receivedRecords.single.claimTxids, 'claim-txid');
    expect(find.text('Receiving...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPaymentLinksScreen(tester, operations: operations);
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
    final operations = FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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
    final operations = FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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
    final operations = FakePaymentLinkOperations(
      claimCompleters: {
        incomingLink.address: firstClaim,
        secondIncomingLink.address: secondClaim,
      },
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();
    expect(operations.claimedLinks.map((link) => link.address), [
      incomingLink.address,
    ]);

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(secondIncomingLink.toUri().toString());
    await tester.pumpAndSettle();
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    expect(operations.claimedLinks.map((link) => link.address), [
      incomingLink.address,
      secondIncomingLink.address,
    ]);
    firstClaim.complete(broadcastedClaimResult);
    secondClaim.complete(broadcastedClaimResult);
    await tester.pump();
  });

  testWidgets('does not reopen a Gift Card whose claim is submitting', (
    tester,
  ) async {
    final claim = Completer<PaymentLinkClaimResult>();
    final operations = FakePaymentLinkOperations(claimCompleter: claim);
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim the Gift Card'));
    await tester.pump();

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pump(const Duration(milliseconds: 250));

    expect(operations.allowLongSyncCalls, [isFalse]);
    expect(operations.claimedLinks, hasLength(1));
    claim.complete(broadcastedClaimResult);
    await tester.pump();
  });

  testWidgets('returns a failed claim to an actionable Received card', (
    tester,
  ) async {
    final claimCompleter = Completer<PaymentLinkClaimResult>();
    final operations = FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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
    final operations = FakePaymentLinkOperations(
      claimCompleter: claimCompleter,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      bootstrap: homeBootstrap,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
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
    final operations = FakePaymentLinkOperations(records: [sharedRecovery]);
    await pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('4.45 ZEC'), findsOneWidget);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsOneWidget);
    expect(find.bySemanticsLabel('Show Gift Card QR code'), findsOneWidget);
    expect(find.text('Reclaim'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Copy Gift Card link'));
    await tester.pumpAndSettle();
    expect(operations.sharedLinks, [incomingLink]);
  });

  testWidgets('saves the selected artwork QR image to the chosen path', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(records: [fundedRecovery]);
    final imageSaver = FakePaymentLinkQrImageSaver();
    await pumpPaymentLinksScreen(
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
    expect(shareCard.qrData, incomingLink.toUri().toString());

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
    expect(operations.sharedLinks, [incomingLink]);
  });

  testWidgets('received cards show only for the account they landed in, '
      'except unclaimed ones', (tester) async {
    PaymentLinkReceivedRecord record({
      required String address,
      required PaymentLinkReceivedStatus status,
      required String destinationAccountUuid,
    }) => PaymentLinkReceivedRecord(
      network: incomingLink.network,
      address: address,
      amountZatoshi: incomingLink.amountZatoshi,
      createdAt: incomingLink.createdAt,
      artworkId: incomingLink.presentation?.artworkId,
      message: incomingLink.presentation?.message,
      status: status,
      claimLink: incomingLink,
      destinationAccountUuid: destinationAccountUuid,
      claimTxids: status == PaymentLinkReceivedStatus.readyToClaim
          ? null
          : 'claim-txid',
      updatedAt: DateTime.utc(2026, 8, 6, 2),
    );
    final operations = FakePaymentLinkOperations(
      receivedRecords: [
        record(
          address: 'u1landedhere',
          status: PaymentLinkReceivedStatus.received,
          destinationAccountUuid: 'account-1',
        ),
        record(
          address: 'u1landedelsewhere',
          status: PaymentLinkReceivedStatus.received,
          destinationAccountUuid: 'account-2',
        ),
        record(
          address: 'u1stillclaimable',
          status: PaymentLinkReceivedStatus.readyToClaim,
          destinationAccountUuid: 'account-2',
        ),
      ],
    );
    await pumpPaymentLinksScreen(tester, operations: operations);

    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payment_link_received_u1landedhere')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_received_u1stillclaimable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_received_u1landedelsewhere')),
      findsNothing,
    );
  });

  testWidgets('shows an interrupted funding draft without reclaim controls', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(records: [draftRecovery]);
    await pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('Funding incomplete'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Reclaim'), findsNothing);
  });
}
