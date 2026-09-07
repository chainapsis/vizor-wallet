@Tags(['mobile'])
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await fonts.load();
    await (FontLoader(
      'Young Serif',
    )..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'))).load();
  });
  testWidgets(
    'claim stages preserve the same row, time, pool, amount and order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Builder(builder: buildGiftCardClaimTransitionPreview),
          ),
        ),
      );
      Future<void> renderStage() async {
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      }

      await renderStage();
      final cardFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ActivityFeedRow &&
            widget.row.title.toLowerCase().contains('card'),
      );
      final initialRow = tester.widget<ActivityFeedRow>(cardFinder).row;
      final initialState = tester.state(cardFinder);
      expect(initialRow.timestampText, isNot('--'));
      expect(initialRow.subtitle, 'Ironwood');
      for (var stage = 1; stage <= 4; stage++) {
        await tester.tap(find.byKey(ValueKey('gift_card_stage_$stage')));
        await renderStage();
        expect(cardFinder, findsOneWidget);
        final row = tester.widget<ActivityFeedRow>(cardFinder).row;
        expect(
          row.stableId,
          initialRow.stableId,
          reason: 'stage $stage identity',
        );
        expect(tester.state(cardFinder), same(initialState));
        expect(
          row.timestampText,
          initialRow.timestampText,
          reason: 'stage $stage timestamp',
        );
        expect(row.subtitle, 'Ironwood', reason: 'stage $stage pool');
        expect(
          row.amountText,
          initialRow.amountText,
          reason: 'stage $stage amount',
        );
        expect(
          row.title,
          stage == 4 ? 'Redeemed a gift card' : 'Redeeming a card...',
        );
        // The normal incoming transaction remains below the claim throughout.
        expect(
          tester.getTopLeft(cardFinder).dy,
          lessThan(tester.getTopLeft(find.text('Received')).dy),
        );
      }
    },
  );

  testWidgets(
    'a broadcast receipt stays live when wallet txid byte order differs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Builder(builder: buildGiftCardClaimDetailTransitionPreview),
          ),
        ),
      );
      Future<void> settleFrames() async {
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      }

      await settleFrames();
      final screen = tester.widget<MobileTransactionStatusScreen>(
        find.byType(MobileTransactionStatusScreen),
      );
      final claimTime = formatActivityTimestamp(
        screen.args.giftCard!.activityTimestamp,
      );
      expect(find.text('Redeeming a card...'), findsOneWidget);
      expect(find.text(claimTime), findsOneWidget);
      for (var stage = 1; stage <= 4; stage++) {
        await tester.tap(find.byKey(ValueKey('gift_card_stage_$stage')));
        await settleFrames();
        expect(find.text(claimTime), findsOneWidget);
        expect(
          find.text(
            stage == 4 ? 'Redeemed a gift card' : 'Redeeming a card...',
          ),
          findsOneWidget,
        );
      }
    },
  );

  final scenarios = [
    (
      'creating-row',
      buildGiftCardCreatingActivityPreview,
      'Creating a card...',
    ),
    (
      'created-detail',
      buildGiftCardCreatedDetailPreview,
      'Created a gift card',
    ),
    ('created-row', buildGiftCardCreatedActivityPreview, 'Created a gift card'),
    (
      'claim-broadcast',
      buildGiftCardClaimBroadcastPreview,
      'Redeeming a card...',
    ),
    (
      'claim-one',
      buildGiftCardClaimOneConfirmationPreview,
      'Redeeming a card...',
    ),
    (
      'claim-five',
      buildGiftCardClaimFiveConfirmationsPreview,
      'Redeeming a card...',
    ),
    ('claim-six', buildGiftCardClaimCompletePreview, 'Redeemed a gift card'),
    (
      'creating-detail',
      buildGiftCardCreatingDetailPreview,
      'Creating a card...',
    ),
    (
      'redeeming-detail',
      buildGiftCardRedeemingDetailPreview,
      'Redeeming a card...',
    ),
    (
      'redeemed-detail',
      buildGiftCardRedeemedDetailPreview,
      'Redeemed a gift card',
    ),
  ];
  for (final (name, builder, title) in scenarios) {
    testWidgets('$name renders its full title', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: RepaintBoundary(
              key: capture,
              child: Builder(builder: builder),
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final text = find.text(title);
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)).first,
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$name title must fit',
      );
      const capturePath = String.fromEnvironment('VIZOR_CAPTURE_DIR');
      if (capturePath.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(capturePath).create(recursive: true);
          await File(
            '$capturePath/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
