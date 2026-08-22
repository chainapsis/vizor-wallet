@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

void main() {
  testWidgets('mobile polls use the standard header and 16px content inset', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppTheme(
          data: AppThemeData.dark,
          child: Builder(builder: buildMobileVotingPollsUseCase),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Coinholder voting'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    final firstAction = find.byKey(
      const ValueKey('voting_poll_action_community-grants-2026'),
    );
    expect(firstAction, findsOneWidget);
    final card = find.byKey(
      const ValueKey('voting_poll_card_community-grants-2026'),
    );
    expect(card, findsOneWidget);
    expect(tester.getTopLeft(card).dx, 16);
  });
}
