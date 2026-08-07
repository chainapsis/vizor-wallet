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
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_clipboard.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

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
    expect(modalRect.size, const Size(312, 441));
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
    final amountField = tester.widget<TextField>(amountEditor);
    expect(amountField.focusNode?.hasFocus, isFalse);
    expect(amountField.cursorColor?.a, greaterThan(0));
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
    expect(tester.widget<TextField>(amountEditor).focusNode?.hasFocus, isTrue);
    expect(
      amountSemantics.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.setText,
      ),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('payment_link_amount_focus_ring')),
      findsOneWidget,
    );

    await tester.enterText(amountEditor, '1.25');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(amountSemantics.evaluate().single.value, '1.25');

    final editableRoot = tester.renderObject(
      find.descendant(of: amountEditor, matching: find.byType(EditableText)),
    );
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

    expect(find.text('Use max: 142.2298'), findsOneWidget);
    await tester.tap(find.text('Use max: 142.2298'));
    await tester.pump();
    expect(tester.widget<TextField>(amountEditor).controller?.text, '142.2298');
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
    expect(messageEditor, findsOneWidget);
    expect(find.text('Start typing...'), findsOneWidget);
    expect(
      tester.widget<TextField>(messageEditor).focusNode?.hasFocus,
      isFalse,
    );

    await tester.tap(messageEditor);
    await tester.pump();
    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    await tester.enterText(messageEditor, 'For you');
    await tester.pump();

    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('121/128'), findsOneWidget);

    var continueButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & review'),
    );
    expect(continueButton.onPressed, isNotNull);

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

    await tester.tap(find.text('Add Message'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(messageEditor).controller?.text, 'For you');

    await tester.tap(find.text('Skip message'));
    await tester.pumpAndSettle();
    expect(find.text('Card amount'), findsOneWidget);

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

      expect(
        find.text('Insufficient balance to cover the Card amount and fees.'),
        findsOneWidget,
      );
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

  testWidgets('keeps a created link private until ten confirmations', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(
      records: [_sharedRecovery],
      fundingConfirmationCount: 9,
    );
    await _pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);

    operations.fundingConfirmationCount = 10;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsNothing);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('changes the waiting label for the final three confirmations', (
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

    expect(find.text('Your link will be here'), findsOneWidget);

    operations.fundingConfirmationCount = 7;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Link will be available soon'), findsOneWidget);
    expect(find.text('Your link will be here'), findsNothing);

    operations.fundingConfirmationCount = 10;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Link will be available soon'), findsNothing);
  });

  testWidgets('shows a separate state when a valid link has no balance', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(claimable: false);
    final clipboard = _FakePaymentLinkClipboard(text: _incomingLink.encode());
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
      expect(find.text('Card amount'), findsOneWidget);
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
    final clipboard = _FakePaymentLinkClipboard(text: _incomingLink.encode());
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

    expect(find.text('You’ve received a gift!'), findsOneWidget);
    expect(find.text('4.45'), findsOneWidget);
    expect(find.text('Message attached.'), findsOneWidget);
    expect(find.text('Congratulations!'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pumpAndSettle();

    expect(find.text('Congratulations!'), findsOneWidget);
  });

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
        .ingest(_incomingLink.encode());
    await tester.pumpAndSettle();

    expect(find.text('You’ve received a gift!'), findsOneWidget);
    expect(find.text('4.45'), findsOneWidget);

    await tester.tap(find.text('Claim my gift'));
    await tester.pumpAndSettle();

    expect(operations.claimedLinks.map((link) => link.encode()), [
      _incomingLink.encode(),
    ]);
    expect(find.text('Gift claimed'), findsOneWidget);
  });

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
        .ingest(_incomingLink.encode());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PaymentLinkGiftCard>(find.byType(PaymentLinkGiftCard))
          .artwork,
      PaymentLinkCardArtwork.ruby,
    );

    await tester.tap(find.text('Claim my gift'));
    await tester.pump();

    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Received'), findsWidgets);
    expect(find.text('You’ve received a gift!'), findsNothing);
    final receivedThumbnail = tester.widget<Image>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey('payment_link_received_u1paymentlinkaddress'),
            ),
            matching: find.byType(Image),
          )
          .first,
    );
    expect(
      (receivedThumbnail.image as AssetImage).assetName,
      PaymentLinkCardArtwork.ruby.assetPath,
    );

    claimCompleter.complete(_broadcastedClaimResult);
    await tester.pumpAndSettle();

    expect(find.text('Receiving'), findsNothing);
    expect(find.text('Received'), findsWidgets);
    expect(find.text('Gift claimed'), findsOneWidget);
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
        .ingest(_incomingLink.encode());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim my gift'));
    await tester.pump();

    claimCompleter.complete(
      const PaymentLinkClaimResult(
        txids: 'pending-claim-txid',
        status: PaymentLinkClaimBroadcastStatus.pendingBroadcast,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Gift claim submitted'), findsOneWidget);
    expect(find.text('Gift claimed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(operations.discardedClaimAddresses, isEmpty);
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
        .ingest(_incomingLink.encode());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim my gift'));
    await tester.pump();

    expect(find.text('Receiving'), findsOneWidget);
    claimCompleter.completeError(StateError('claim failed'));
    await tester.pumpAndSettle();

    expect(find.text('Receiving'), findsNothing);
    expect(find.text('Claim'), findsOneWidget);
    expect(find.textContaining('Gift Card claim failed.'), findsOneWidget);
  });

  testWidgets('copies a persisted created link without reclaim controls', (
    tester,
  ) async {
    final operations = _FakePaymentLinkOperations(records: [_sharedRecovery]);
    await _pumpPaymentLinksScreen(tester, operations: operations);

    expect(find.text('4.45 ZEC'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Reclaim'), findsNothing);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
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
  AppBootstrapState? bootstrap,
  BigInt? spendableBalance,
}) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final paymentLinkOperations = operations ?? _FakePaymentLinkOperations();
  final paymentLinkClipboard = clipboard ?? _FakePaymentLinkClipboard();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap),
        paymentLinkOperationsProvider.overrideWithValue(paymentLinkOperations),
        paymentLinkClipboardProvider.overrideWithValue(paymentLinkClipboard),
        if (hardwareSigning != null)
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(
            hardwareSigning,
          ),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              isSyncComplete: true,
              percentage: 1,
              displayPercentage: 1,
              spendableBalance: spendableBalance ?? BigInt.from(14223000000),
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
    if (find
        .byKey(const ValueKey('payment_links_desktop_screen'))
        .evaluate()
        .isNotEmpty) {
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

final _sharedRecovery = PaymentLinkRecoveryRecord(
  link: _incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.shared,
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
    this.claimCompleter,
    this.fundingConfirmationCount = kPaymentLinkShareConfirmationTarget,
    this.claimable = true,
  }) : records = List.of(records);

  final Completer<PaymentLinkClaimResult>? claimCompleter;
  int fundingConfirmationCount;
  final bool claimable;
  final List<PaymentLinkRecoveryRecord> records;
  final List<BigInt> createdAmounts = [];
  final List<String> createdFromAccounts = [];
  final List<String?> createdArtworkIds = [];
  final List<String?> createdMessages = [];
  final List<VizorPaymentLink> sharedLinks = [];
  final List<VizorPaymentLink> claimedLinks = [];
  final List<String> discardedClaimAddresses = [];

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    return PaymentLinkFundingQuote(
      recipientAmountZatoshi: amountZatoshi,
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<VizorPaymentLink> createFundedLink({
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
        state: PaymentLinkRecoveryState.funded,
        updatedAt: DateTime.utc(2026, 8, 6),
        fundingTxids: 'funding-txid',
      ),
    );
    return link;
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async {
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
    return {
      for (final record in records)
        record.link.address: PaymentLinkFundingProgress(
          confirmationCount: fundingConfirmationCount,
        ),
    };
  }

  @override
  Future<PaymentLinkClaimSession> prepareClaim(VizorPaymentLink link) async {
    return PaymentLinkClaimSession(
      link: link,
      destinationAddress: 'u1receiver',
      directory: Directory('/tmp/vizor-payment-link-test'),
      dbPath: '/tmp/vizor-payment-link-test/wallet.db',
      accountUuid: 'payment-link-account',
      totalZatoshi: claimable ? link.amountZatoshi : BigInt.zero,
      claimableZatoshi: claimable ? link.amountZatoshi : BigInt.zero,
      feeZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) {
    return claimLink(session.link);
  }

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {
    discardedClaimAddresses.add(session.link.address);
  }

  @override
  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link) async {
    claimedLinks.add(link);
    return claimCompleter?.future ?? _broadcastedClaimResult;
  }
}

const _broadcastedClaimResult = PaymentLinkClaimResult(
  txids: 'claim-txid',
  status: PaymentLinkClaimBroadcastStatus.broadcasted,
);

class _FakePaymentLinkClipboard implements PaymentLinkClipboard {
  _FakePaymentLinkClipboard({this.text});

  String? text;
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
  Future<String?> readText() async => text;
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
  }) async => const ['ur:zcash-pczt/test'];

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
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const rust_sync.ExtractAndBroadcastPcztResult(
      txid: 'hardware-funding-txid',
      status: 'broadcasted',
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
