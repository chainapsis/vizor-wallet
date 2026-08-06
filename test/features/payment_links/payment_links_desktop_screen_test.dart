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
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
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
        'and create your card with a single click.',
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
        'Recipient can redeem the card in their Vizor wallet using the link. '
        'A small fee will be deducted from the card balance in order to make '
        'a shielded transaction.',
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

  testWidgets('keeps the local wizard interactive but creation disabled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpPaymentLinksScreen(tester);

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
    await tester.pump();

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

    expect(find.text('Use max: 142.23'), findsOneWidget);
    await tester.tap(find.text('Use max: 142.23'));
    await tester.pump();
    expect(tester.widget<TextField>(amountEditor).controller?.text, '142.23');

    await tester.tap(find.text('Create card'));
    await tester.pumpAndSettle();
    expect(find.text('Attach a message'), findsOneWidget);

    final messageEditor = find.byKey(
      const ValueKey('payment_link_message_editor'),
    );
    expect(messageEditor, findsOneWidget);
    expect(
      tester.widget<TextField>(messageEditor).focusNode?.hasFocus,
      isFalse,
    );

    await tester.tap(messageEditor);
    await tester.enterText(messageEditor, 'For you');
    await tester.pump();

    expect(tester.widget<TextField>(messageEditor).focusNode?.hasFocus, isTrue);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('121/128'), findsOneWidget);

    var continueButton = tester.widget<AppButton>(
      find
          .ancestor(of: find.text('Continue'), matching: find.byType(AppButton))
          .first,
    );
    expect(continueButton.onPressed, isNotNull);

    await tester.tap(find.bySemanticsLabel('Delete gift card message'));
    await tester.pump();
    expect(tester.widget<TextField>(messageEditor).controller?.text, isEmpty);
    expect(find.text('128/128'), findsOneWidget);
    continueButton = tester.widget<AppButton>(
      find
          .ancestor(of: find.text('Continue'), matching: find.byType(AppButton))
          .first,
    );
    expect(continueButton.onPressed, isNull);

    await tester.enterText(messageEditor, '   \n');
    await tester.pump();
    continueButton = tester.widget<AppButton>(
      find
          .ancestor(of: find.text('Continue'), matching: find.byType(AppButton))
          .first,
    );
    expect(continueButton.onPressed, isNull);

    await tester.enterText(messageEditor, 'For you');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review your Gift Card'), findsOneWidget);
    expect(find.textContaining('Creating fee'), findsNothing);

    await tester.tap(find.text('Add Message'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(messageEditor).controller?.text, 'For you');

    await tester.tap(find.text('Skip message'));
    await tester.pumpAndSettle();
    expect(find.text('Review your Gift Card'), findsOneWidget);
    expect(find.textContaining('Creating fee'), findsNothing);

    final confirmButton = tester.widget<AppButton>(
      find
          .ancestor(
            of: find.text('Confirm & create'),
            matching: find.byType(AppButton),
          )
          .first,
    );
    expect(confirmButton.onPressed, isNull);
    semantics.dispose();
  });

  testWidgets('keeps manual redeem intake disabled', (tester) async {
    await _pumpPaymentLinksScreen(tester);

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
    expect(pasteButton.onPressed, isNull);
  });
}

Future<void> _pumpPaymentLinksScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              isSyncComplete: true,
              percentage: 1,
              displayPercentage: 1,
              spendableBalance: BigInt.from(14223000000),
              displaySpendableBalance: BigInt.from(14223000000),
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
  await tester.pumpAndSettle();
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
