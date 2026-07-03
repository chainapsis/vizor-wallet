import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/review_buttons_stack.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_layout.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_status_content_view.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _transparentAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';

const _memo = 'Zcash is a privacy-focused ...';

void main() {
  testWidgets('in progress phase shows the loader status and no CTA', (
    tester,
  ) async {
    await _pump(tester, _statusView(SendStatusPhase.inProgress));

    expect(find.text('Send in progress...'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(_icon(AppIcons.loader), findsOneWidget);
    expect(_icon(AppIcons.arrowDown), findsOneWidget);
    expect(_icon(AppIcons.uturnUp), findsNothing);

    final statusText = tester.widget<Text>(find.text('In progress'));
    expect(statusText.style?.color, AppThemeData.light.colors.text.secondary);

    // Detail rows present in every phase.
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('25 May, 13:30'), findsOneWidget);
    expect(find.text('Tx ID'), findsOneWidget);
    expect(find.text('0123123124512512'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);

    // Read-only screen: no confirm/cancel stack.
    expect(find.byType(ReviewButtonsStack), findsNothing);
    expect(find.text('Confirm & send'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('completed phase shows the green check status', (tester) async {
    await _pump(tester, _statusView(SendStatusPhase.completed));

    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(_icon(AppIcons.checkCircle), findsOneWidget);
    expect(_icon(AppIcons.arrowDown), findsOneWidget);

    final statusText = tester.widget<Text>(find.text('Completed'));
    expect(
      statusText.style?.color,
      AppThemeData.light.colors.text.positiveStrong,
    );

    final card = tester.widget<ReviewWrapCard>(find.byType(ReviewWrapCard));
    expect(card.surfaceColor, isNull);
  });

  testWidgets('transparent raw recipient keeps a transparent badge', (
    tester,
  ) async {
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.completed,
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(
          address: _transparentAddress,
        ),
        isShieldedRecipient: false,
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text(truncatedAddress(_transparentAddress)), findsOneWidget);
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('TEX raw recipient keeps a TEX badge', (tester) async {
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.completed,
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _texAddress),
        isShieldedRecipient: false,
        recipientAddressType: 'tex',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text(truncatedAddress(_texAddress)), findsOneWidget);
    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('TEX contact recipient keeps a TEX label', (tester) async {
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.completed,
        amountText: '123.12 ZEC',
        recipient: const SendReviewContactRecipient(
          address: _texAddress,
          name: 'Mike',
          profilePictureId: 'pfp-02',
        ),
        isShieldedRecipient: false,
        recipientAddressType: 'tex',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text('Mike'), findsOneWidget);
    expect(find.byType(AppProfilePicture), findsOneWidget);
    expect(find.text('TEX - ${truncatedAddress(_texAddress)}'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets(
    'failed phase strikes the recipient, swaps the connector, and pins the '
    'card dark in the light theme',
    (tester) async {
      await _pump(tester, _statusView(SendStatusPhase.failed));

      expect(find.text('Send failed'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(_icon(AppIcons.cancel), findsOneWidget);
      expect(_icon(AppIcons.uturnUp), findsOneWidget);
      expect(_icon(AppIcons.arrowDown), findsNothing);

      // Strikethrough on the To-row headline; the amount stays plain.
      final recipientText = tester.widget<Text>(
        find.text(truncatedAddress(_address)),
      );
      expect(recipientText.style?.decoration, TextDecoration.lineThrough);
      final amountText = tester.widget<Text>(find.text('123.12 ZEC'));
      expect(amountText.style?.decoration, isNull);

      // Fixed dark surface in BOTH themes (pumped with the light theme here).
      final card = tester.widget<ReviewWrapCard>(find.byType(ReviewWrapCard));
      expect(card.surfaceColor, Primitives.p50Dark);
      expect(card.surfaceColor, const Color(0xFF1B1F1F));

      // Rows on the dark card resolve dark-theme tokens.
      final darkColors = AppThemeData.dark.colors;
      final statusText = tester.widget<Text>(find.text('Failed'));
      expect(statusText.style?.color, darkColors.text.destructive);
      final statusLabel = tester.widget<Text>(find.text('Status'));
      expect(statusLabel.style?.color, darkColors.text.destructive);
      final timestampLabel = tester.widget<Text>(find.text('Timestamp'));
      expect(timestampLabel.style?.color, darkColors.text.secondary);

      // No in-content CTA on failed — toolbar back only.
      expect(find.byType(ReviewButtonsStack), findsNothing);
    },
  );

  testWidgets('memo row is omitted when memoText is null', (tester) async {
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.completed,
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text('Message'), findsNothing);
    expect(find.text('Timestamp'), findsOneWidget);
  });

  testWidgets('tx id row fires the explorer callback', (tester) async {
    var opens = 0;
    await _pump(
      tester,
      _statusView(SendStatusPhase.completed, onOpenExplorer: () => opens++),
    );

    await tester.tap(find.text('0123123124512512'));
    await tester.pump();
    expect(opens, 1);
  });

  testWidgets('tx id row is omitted while no txid exists', (tester) async {
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.inProgress,
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        timestampText: '25 May, 13:30',
        txIdText: null,
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text('Tx ID'), findsNothing);
    expect(find.text('Timestamp'), findsOneWidget);
  });

  testWidgets('notice text renders under the wrap card', (tester) async {
    const notice =
        'Transaction was created locally but could not be broadcast.';
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.inProgress,
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
        noticeText: notice,
      ),
    );

    final noticeWidget = tester.widget<Text>(find.text(notice));
    expect(noticeWidget.style?.color, AppThemeData.light.colors.text.secondary);
  });

  testWidgets('expanded memo renders the full text with a collapse toggle', (
    tester,
  ) async {
    var toggles = 0;
    await _pump(
      tester,
      SendStatusContentView(
        phase: SendStatusPhase.completed,
        amountText: '123.12 ZEC',
        recipient: const SendReviewAddressRecipient(address: _address),
        memoText: _memo,
        memoExpanded: true,
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
        onExpandMemo: () => toggles++,
      ),
    );

    expect(find.text('Collapse'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_memo)).maxLines, isNull);

    await tester.tap(find.text('Collapse'));
    await tester.pump();
    expect(toggles, 1);
  });
}

Widget _statusView(SendStatusPhase phase, {VoidCallback? onOpenExplorer}) {
  return SendStatusContentView(
    phase: phase,
    amountText: '123.12 ZEC',
    fiatText: r'$250.12',
    recipient: const SendReviewAddressRecipient(address: _address),
    memoText: _memo,
    timestampText: '25 May, 13:30',
    txIdText: '0123123124512512',
    feeText: '0.012 ZEC',
    onOpenExplorer: onOpenExplorer,
  );
}

Finder _icon(String name) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == name,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(data: AppThemeData.light, child: child),
    ),
  );
  await tester.pump();
}
