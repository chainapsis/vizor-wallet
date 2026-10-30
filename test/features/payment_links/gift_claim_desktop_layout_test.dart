@Tags(['desktop'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_check_progress_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_motion.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_claim_outcome_view.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_confetti.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_wizard_chrome.dart';
import 'package:zcash_wallet/src/core/layout/app_pane_scroll_scaffold.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../figma_compare/figma_compare_font_loader.dart';
import '../../support/payment_links_screen_support.dart';

const _slotKey = ValueKey('payment_link_claim_card_slot');
const _claimKey = ValueKey('payment_link_claim_button');

void main() {
  setUpAll(() async {
    expect(kAppFormFactor, AppFormFactor.desktop);
    await loadFigmaCompareFonts();
  });

  for (final size in [
    const Size(320, 568),
    const Size(520, 600),
    const Size(804, 704),
    const Size(1080, 720),
    const Size(1440, 960),
  ]) {
    for (final scale in [1.0, 1.4, 2.0]) {
      for (final hasMessage in [false, true]) {
        testWidgets(
          'claim stage preserves bounds at $size text=$scale message=$hasMessage',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final boundary = GlobalKey();
            final theme =
                Platform.environment['GIFT_DESKTOP_LAYOUT_THEME'] == 'light'
                ? AppThemeData.light
                : AppThemeData.dark;
            Future<void> pump(PaymentLinkClaimDesktopState state) async {
              await tester.pumpWidget(
                MaterialApp(
                  builder: (context, child) => AppTheme(
                    data: theme,
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                  ),
                  home: Scaffold(
                    body: RepaintBoundary(
                      key: boundary,
                      child: ColoredBox(
                        color: theme.colors.background.window,
                        child: PaymentLinkReceivedDesktopView(
                          state: state,
                          card: state == PaymentLinkClaimDesktopState.loading
                              ? const PaymentLinkLoadingCard()
                              : const PaymentLinkGiftCard(
                                  artwork: PaymentLinkCardArtwork.ruby,
                                  amountText: '4.45',
                                  showCaret: false,
                                ),
                          waitingStatusLabel: 'Checking the gift… 100%',
                          onBack: () {},
                          onClaim: () {},
                          onRevealMessage: hasMessage ? () {} : null,
                          statusContent: PaymentLinkClaimOutcomeView(
                            availability: PaymentLinkAvailability.noBalance,
                            embedded: true,
                            onBack: () {},
                            onCheck: () {},
                          ),
                          decoration: const PaymentLinkConfetti(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            await pump(PaymentLinkClaimDesktopState.loading);
            if (size == const Size(804, 704) && scale == 1 && hasMessage) {
              await _capture(
                tester,
                boundary,
                'pane-${size.width.toInt()}-loading',
              );
            }
            final original = tester.getRect(find.byKey(_slotKey));
            final motion = tester.state(find.byType(PaymentLinkCardMotion));
            _expectRect(
              tester.getRect(
                find.byKey(const ValueKey('payment_link_loading_card')),
              ),
              original,
            );
            final scroll = tester.state<ScrollableState>(
              find.descendant(
                of: find.byKey(AppPaneScrollScaffold.scrollViewKey),
                matching: find.byType(Scrollable),
              ),
            );
            // Preserve a nonzero offset as well as the unscrolled stage.
            if (scroll.position.maxScrollExtent > 0) {
              scroll.position.jumpTo(scroll.position.maxScrollExtent);
              await tester.pump();
            }
            final scrolled = tester.getRect(find.byKey(_slotKey));
            final offset = scroll.position.pixels;
            for (final state in [
              PaymentLinkClaimDesktopState.checking,
              PaymentLinkClaimDesktopState.waiting,
              PaymentLinkClaimDesktopState.outcome,
              PaymentLinkClaimDesktopState.ready,
            ]) {
              await pump(state);
              _expectRect(tester.getRect(find.byKey(_slotKey)), scrolled);
              expect(
                tester.state(find.byType(PaymentLinkCardMotion)),
                same(motion),
              );
              expect(scroll.position.pixels, offset);
              final entry = tester.widget<Transform>(
                find.byKey(const ValueKey('payment_link_tilt_transform')),
              );
              expect(
                entry.transform.entry(0, 0),
                1,
                reason: 'Completion must not start a new 0.85 entry scale',
              );
              expect(
                find.byKey(_claimKey),
                state == PaymentLinkClaimDesktopState.ready
                    ? findsOneWidget
                    : findsNothing,
              );
              expect(tester.takeException(), isNull);
            }
            await tester.pumpAndSettle();
            if (size == const Size(804, 704) && scale == 1 && hasMessage) {
              await _capture(
                tester,
                boundary,
                'pane-${size.width.toInt()}-loaded',
              );
            }
            expect(
              find.ancestor(
                of: find.byType(PaymentLinkConfetti),
                matching: find.byKey(
                  const ValueKey('payment_link_reveal_transform'),
                ),
              ),
              findsNothing,
            );
            if (hasMessage) {
              final message = tester.getRect(
                find.byKey(
                  const ValueKey('payment_link_received_message_block'),
                ),
              );
              expect(
                message.bottom,
                lessThanOrEqualTo(tester.getRect(find.byKey(_claimKey)).top),
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final size in [const Size(1080, 720), const Size(1920, 1280)]) {
    for (final result in [
      'no balance',
      'claimed elsewhere',
      'network error',
      'invalid card',
      'confirmations',
    ]) {
      testWidgets('production $result keeps the claim stage at $size', (
        tester,
      ) async {
        final gate = Completer<void>();
        final operations =
            FakePaymentLinkOperations(
                prepareClaimGates: {1: gate},
                prepareClaimError: result == 'network error'
                    ? StateError('offline')
                    : result == 'invalid card'
                    ? const FormatException('invalid')
                    : null,
                waitingForFundingConfirmations: result == 'confirmations',
                fundingConfirmationCount: 1,
              )
              ..claimable = result == 'confirmations'
              ..claimAvailability = result == 'claimed elsewhere'
                  ? PaymentLinkAvailability.claimedElsewhere
                  : PaymentLinkAvailability.noBalance;
        await pumpPaymentLinksScreen(
          tester,
          logicalSize: size,
          operations: operations,
          clipboard: FakePaymentLinkClipboard(
            text: incomingLink.toUri().toString(),
          ),
        );
        await tester.tap(find.text('Redeem a card'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste card link'));
        await tester.pump();
        final original = tester.getRect(find.byKey(_slotKey));
        final motion = tester.state(find.byType(PaymentLinkCardMotion));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp).first),
        );
        container
            .read(giftCardCheckProgressProvider.notifier)
            .update(
              incomingLink,
              rust_sync.ApiGiftCardCheckProgress(
                phase: 'checking',
                completed: BigInt.from(50),
                total: BigInt.from(100),
                fundingHeight: incomingLink.birthdayHeight + 1,
                checkedHeight: incomingLink.birthdayHeight + 50,
                totalZatoshi: incomingLink.amountZatoshi + BigInt.from(10000),
                unspentZatoshi: incomingLink.amountZatoshi + BigInt.from(10000),
                complete: false,
              ),
            );
        await tester.pump();
        _expectRect(tester.getRect(find.byKey(_slotKey)), original);
        gate.complete();
        container
            .read(giftCardCheckProgressProvider.notifier)
            .clear(incomingLink);
        await tester.pumpAndSettle();
        _expectRect(tester.getRect(find.byKey(_slotKey)), original);
        expect(tester.state(find.byType(PaymentLinkCardMotion)), same(motion));
        expect(find.byKey(_claimKey), findsNothing);
        expect(find.byType(PaymentLinkConfetti), findsNothing);
        expect(
          find.text(switch (result) {
            'no balance' => 'No balance',
            'claimed elsewhere' => 'Claimed elsewhere',
            'network error' => 'Try again',
            'invalid card' => 'The link doesn’t look legit.',
            _ => 'Your Gift Card\nis almost ready!',
          }),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        if (result == 'network error') {
          await tester.tap(find.text('Try again'));
          await tester.pumpAndSettle();
          _expectRect(tester.getRect(find.byKey(_slotKey)), original);
          expect(operations.preparedLinks, hasLength(2));
          await tester.tap(find.text('My Cards'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Redeem a card'));
          await tester.pumpAndSettle();
          expect(find.text('Paste card link').hitTestable(), findsOneWidget);
          expect(find.text('Try again'), findsNothing);
          expect(find.byKey(_slotKey), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final size in [
    const Size(1080, 720),
    const Size(1280, 853),
    const Size(1440, 960),
    const Size(1920, 1280),
  ]) {
    for (final discovered in [false, true]) {
      testWidgets(
        'production claim preserves skeleton at $size discovery=$discovered',
        (tester) async {
          final gate = Completer<void>();
          final boundary = GlobalKey();
          await pumpPaymentLinksScreen(
            tester,
            logicalSize: size,
            captureBoundaryKey: boundary,
            operations: FakePaymentLinkOperations(prepareClaimGates: {1: gate}),
            clipboard: FakePaymentLinkClipboard(
              text: incomingLink.toUri().toString(),
            ),
          );
          await tester.tap(find.text('Redeem a card'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Paste card link'));
          await tester.pump();
          final skeleton = tester.getRect(
            find.byKey(const ValueKey('payment_link_loading_card')),
          );
          final motion = tester.state(find.byType(PaymentLinkCardMotion));
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp).first),
          );
          if (discovered) {
            container
                .read(giftCardCheckProgressProvider.notifier)
                .update(
                  incomingLink,
                  rust_sync.ApiGiftCardCheckProgress(
                    phase: 'checking',
                    completed: BigInt.from(50),
                    total: BigInt.from(100),
                    fundingHeight: incomingLink.birthdayHeight + 1,
                    checkedHeight: incomingLink.birthdayHeight + 50,
                    totalZatoshi:
                        incomingLink.amountZatoshi + BigInt.from(10000),
                    unspentZatoshi:
                        incomingLink.amountZatoshi + BigInt.from(10000),
                    complete: false,
                  ),
                );
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.getRect(find.byKey(_slotKey)), skeleton);
            expect(
              tester.getRect(find.byType(PaymentLinkGiftCard).first),
              skeleton,
            );
            expect(
              tester.state(find.byType(PaymentLinkCardMotion)),
              same(motion),
            );
          }
          await _capture(
            tester,
            boundary,
            '${size.width.toInt()}-discovery-$discovered-checking',
          );
          gate.complete();
          container
              .read(giftCardCheckProgressProvider.notifier)
              .clear(incomingLink);
          await tester.pump();
          expect(tester.getRect(find.byKey(_slotKey)), skeleton);
          expect(
            tester.state(find.byType(PaymentLinkCardMotion)),
            same(motion),
          );
          expect(
            tester
                .widget<Transform>(
                  find.byKey(const ValueKey('payment_link_tilt_transform')),
                )
                .transform
                .entry(0, 0),
            1,
          );
          await tester.pumpAndSettle();
          final loaded = tester.getRect(find.byType(PaymentLinkGiftCard).first);
          expect(loaded.left, closeTo(skeleton.left, 0.1));
          expect(loaded.top, closeTo(skeleton.top, 0.1));
          expect(loaded.width, closeTo(skeleton.width, 0.1));
          expect(loaded.height, closeTo(skeleton.height, 0.1));
          expect(find.byKey(_claimKey), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            boundary,
            '${size.width.toInt()}-discovery-$discovered-loaded',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['GIFT_DESKTOP_LAYOUT_CAPTURE_DIR'];
  if (directory == null) return;
  // Optional widget captures; production state and network remain mocked.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
  });
  await tester.pump();
  await expectLater(
    find.byKey(key),
    matchesGoldenFile(Uri.file('$directory/$name.png')),
  );
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.001));
  expect(actual.top, closeTo(expected.top, 0.001));
  expect(actual.width, closeTo(expected.width, 0.001));
  expect(actual.height, closeTo(expected.height, 0.001));
}
