import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_scanner.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';

void registerPaymentRequestScannerTests(
  Future<(ProviderContainer, GoRouter)> Function(
    WidgetTester,
    PaymentRequestScanner,
  )
  pump, {
  required void Function(Completer<void>?) holdRelease,
}) {
  const original = SendPrefillArgs(
    id: 'external',
    source: kPaymentUriPrefillSource,
    address: 'u1original',
    amountText: '0.5',
    memoText: 'old memo',
  );
  const scanned = SendPrefillArgs(
    id: 'scanned',
    source: kPaymentUriPrefillSource,
    address: 'u1scanned',
    amountText: '0.75',
    memoText: 'new memo',
  );

  for (final outcome in [
    'cancel',
    'replace',
    'clear',
    'newer request',
    'error',
  ]) {
    testWidgets('external request re-scan: $outcome', (tester) async {
      final result = Completer<SendPrefillArgs?>();
      final (container, router) = await pump(
        tester,
        (_, {required router, required networkName}) => result.future,
      );
      final notifier = container.read(paymentRequestFlowProvider.notifier);
      notifier.present(original, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('external_request_warning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_request_continue')),
        findsNothing,
      );
      final retained = container.read(paymentRequestFlowProvider)!;
      await tester.tap(find.byKey(const ValueKey('payment_request_scan')));
      await tester.pumpAndSettle();
      expect(find.text('Payment request'), findsNothing);
      expect(
        container
            .read(externalActionGuardProvider)
            .blocks(ExternalAction.paymentRequest),
        isTrue,
      );
      if (outcome == 'clear') notifier.clear();
      if (outcome == 'newer request') {
        notifier.present(
          const SendPrefillArgs(
            id: 'newer',
            source: kPaymentUriPrefillSource,
            address: 'u1newer',
            amountText: '1',
          ),
          source: PaymentRequestSource.link,
        );
      }
      if (outcome == 'error') {
        result.completeError(StateError('camera unavailable'));
      } else {
        result.complete(outcome == 'cancel' ? null : scanned);
      }
      await tester.pumpAndSettle();
      final current = container.read(paymentRequestFlowProvider);
      switch (outcome) {
        case 'cancel' || 'error':
          expect(current?.prefill, same(retained.prefill));
          expect(
            find.byKey(const ValueKey('external_request_warning')),
            findsOneWidget,
          );
        case 'replace':
          expect(router.state.uri.path, '/home');
          expect(current?.prefill.address, 'u1scanned');
          expect(current?.prefill.amountText, '0.75');
          expect(current?.prefill.memoText, 'new memo');
          expect(current?.view.source, PaymentRequestSource.qrCode);
          expect(
            find.byKey(const ValueKey('payment_request_transaction_content')),
            findsOneWidget,
          );
          expect(find.text('Review payment'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('external_request_warning')),
            findsNothing,
          );
          expect(
            container.read(externalActionGuardProvider).activeHoldCount,
            0,
          );
          await tester.tap(
            find.byKey(const ValueKey('payment_request_continue')),
          );
          await tester.pumpAndSettle();
          expect(container.read(paymentRequestFlowProvider), isNull);
          expect(router.state.uri.path, '/send/review');
          final extra = router.routerDelegate.currentConfiguration.extra;
          switch (extra) {
            case SendReviewArgs():
              expect(extra.address, 'u1scanned');
              expect(extra.amountZatoshi, BigInt.from(75000000));
              expect(extra.memo, 'new memo');
            case MobileSendReviewDraftArgs():
              expect(extra.recipient, 'u1scanned');
              expect(extra.amountText, '0.75');
              expect(extra.memo, 'new memo');
            default:
              fail('Expected the existing payment review payload, got $extra');
          }
          expect(
            find.byKey(const ValueKey('external_request_warning')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('payment_request_replaced_notice')),
            findsNothing,
          );
          expect(find.text('Payment request'), findsNothing);
        case 'clear':
          expect(current, isNull);
        case 'newer request':
          expect(current?.prefill.id, 'newer');
      }
      expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a scanner route returns to request details before review', (
    tester,
  ) async {
    final (container, router) = await pump(
      tester,
      (_, {required router, required networkName}) =>
          router.push<SendPrefillArgs>('/send/request-scan'),
    );
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(original, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment_request_scan')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/send/request-scan');
    router.pop(scanned);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home');
    expect(find.text('Payment request'), findsOneWidget);
    expect(find.text('Review payment'), findsOneWidget);
    expect(
      container.read(paymentRequestFlowProvider)?.prefill.address,
      scanned.address,
    );
    expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
    await tester.tap(find.byKey(const ValueKey('payment_request_continue')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/send/review');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'link details retain the proposal and a replacement starts at the warning',
    (tester) async {
      final (container, router) = await pump(
        tester,
        (_, {required router, required networkName}) async => scanned,
      );
      final notifier = container.read(paymentRequestFlowProvider.notifier);
      notifier.present(original, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();
      final retained = container.read(paymentRequestFlowProvider)!;
      await tester.tap(
        find.byKey(const ValueKey('payment_request_link_details')),
      );
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/home');
      expect(container.read(paymentRequestFlowProvider), same(retained));
      expect(find.text('Review payment'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('payment_request_memo_toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('old memo'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_request_back_to_intro')),
        findsNothing,
      );
      expect(find.text('Opened from another app'), findsNothing);
      expect(container.read(paymentRequestFlowProvider), same(retained));
      notifier.present(scanned, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('external_request_warning')),
        findsOneWidget,
      );
      expect(find.text('Review link details'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_request_transaction_content')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final fromScanner in [false, true]) {
    for (final amount in ['0.75', null, '2']) {
      testWidgets(
        '${fromScanner ? 'QR' : 'link details'} opens review or composer for amount $amount',
        (tester) async {
          final request = SendPrefillArgs(
            id: 'chosen',
            source: kPaymentUriPrefillSource,
            address: 'u1chosen',
            amountText: amount,
            memoText: '  exact memo  ',
          );
          final (container, router) = await pump(
            tester,
            (_, {required router, required networkName}) async => request,
          );
          container
              .read(paymentRequestFlowProvider.notifier)
              .present(
                fromScanner ? original : request,
                source: PaymentRequestSource.link,
              );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(
              ValueKey(
                fromScanner
                    ? 'payment_request_scan'
                    : 'payment_request_link_details',
              ),
            ),
          );
          await tester.pumpAndSettle();
          {
            // Both choices display their terms without navigating or
            // transferring the proposal until the user chooses an action.
            expect(router.state.uri.path, '/home');
            final details = container.read(paymentRequestFlowProvider)!;
            expect(details.prefill.address, request.address);
            final source = fromScanner
                ? PaymentRequestSource.qrCode
                : PaymentRequestSource.link;
            expect(details.prefill.requestSource, source);
            expect(details.view.source, source);
            expect(
              find.byKey(const ValueKey('payment_request_transaction_content')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('external_request_warning')),
              findsNothing,
            );
            await tester.tap(
              find.byKey(
                ValueKey(
                  amount == '2'
                      ? 'payment_request_edit'
                      : 'payment_request_continue',
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          final ready = amount == '0.75';
          expect(router.state.uri.path, ready ? '/send/review' : '/send');
          expect(container.read(paymentRequestFlowProvider), isNull);
          if (!ready) {
            final extra =
                router.routerDelegate.currentConfiguration.extra
                    as SendPrefillArgs;
            expect(extra.address, request.address);
            expect(extra.amountText, amount);
            expect(extra.memoText, '  exact memo  ');
            expect(
              extra.requestSource,
              fromScanner
                  ? PaymentRequestSource.qrCode
                  : PaymentRequestSource.link,
            );
          }
          expect(
            container.read(externalActionGuardProvider).activeHoldCount,
            0,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  for (final outcome in [
    'finish',
    'clear',
    'newer request',
    'navigate',
    'push',
  ]) {
    testWidgets('scanned request waits for release: $outcome', (tester) async {
      final (container, router) = await pump(
        tester,
        (_, {required router, required networkName}) async => scanned,
      );
      final notifier = container.read(paymentRequestFlowProvider.notifier);
      notifier.present(original, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      holdRelease(gate);
      await tester.tap(find.byKey(const ValueKey('payment_request_scan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(router.state.uri.path, '/home');
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_request_summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_request_transaction_content')),
        findsNothing,
      );
      expect(
        container.read(externalActionGuardProvider).activeHoldCount,
        greaterThan(0),
      );
      if (outcome == 'clear') notifier.clear();
      if (outcome == 'newer request') {
        notifier.present(original, source: PaymentRequestSource.link);
      }
      if (outcome == 'navigate') router.go('/send');
      if (outcome == 'push') unawaited(router.push('/send'));
      gate.complete();
      holdRelease(null);
      await tester.pumpAndSettle();
      expect(
        router.state.uri.path,
        (outcome == 'navigate' || outcome == 'push') ? '/send' : '/home',
      );
      if (outcome == 'finish') {
        expect(find.text('Review payment'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('payment_request_transaction_content')),
          findsOneWidget,
        );
        expect(
          container.read(paymentRequestFlowProvider)?.prefill.address,
          scanned.address,
        );
      }
      if (outcome == 'newer request') {
        expect(
          container.read(paymentRequestFlowProvider)?.prefill.id,
          original.id,
        );
      }
      expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
