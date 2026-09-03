import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_notice.dart';

// The unlock screens tell the user about an expired link and navigate to
// /home in the same turn, so the notice has to outlive the screen that asked
// for it. That is why `showPaymentUriNotice` takes the messenger rather than a
// BuildContext: the screen's context is unmounted by the time the post-frame
// callback runs, the app-level ScaffoldMessengerState is not.
void main() {
  testWidgets('a notice asked for on the way out still arrives', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                showPaymentUriNotice(messenger, kPaymentUriExpiredMessage);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('home')),
                  ),
                );
              },
              child: const Text('unlock'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('unlock'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text(kPaymentUriExpiredMessage), findsOneWidget);
  });

  testWidgets('a second notice replaces the first rather than queueing', (
    tester,
  ) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const Scaffold(body: Text('screen'));
          },
        ),
      ),
    );

    showPaymentUriNotice(messenger, kPaymentUriExpiredMessage);
    await tester.pump();
    await tester.pump();
    showPaymentUriNotice(messenger, kPaymentUriUnavailableMessage);
    await tester.pumpAndSettle();

    expect(find.text(kPaymentUriExpiredMessage), findsNothing);
    expect(find.text(kPaymentUriUnavailableMessage), findsOneWidget);
  });
}
