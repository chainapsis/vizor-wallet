import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';

void main() {
  const roundId = 'El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv/3RE=';

  test('voting route helpers percent-encode round id path separators', () {
    expect(
      votingPollRoute(roundId),
      '/voting/poll/El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv%2F3RE%3D',
    );
    expect(
      votingReviewRoute(roundId),
      '/voting/poll/El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv%2F3RE%3D/review',
    );
    expect(
      votingStatusRoute(roundId),
      '/voting/poll/El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv%2F3RE%3D/status',
    );
    expect(
      votingSubmissionConfirmedRoute(roundId),
      '/voting/poll/El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv%2F3RE%3D/submitted',
    );
    expect(
      votingResultsRoute(roundId),
      '/voting/poll/El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv%2F3RE%3D/results',
    );
  });

  testWidgets('encoded voting poll route matches and decodes round id', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/voting/poll/:roundId',
          builder: (_, state) => Text(state.pathParameters['roundId'] ?? ''),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go(votingPollRoute(roundId));
    await tester.pumpAndSettle();

    expect(find.text(roundId), findsOneWidget);
  });
}
