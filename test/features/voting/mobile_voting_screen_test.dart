@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_bottom_safe_area.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/voting/voting_round_visibility_provider.dart';
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
    expect(find.bySemanticsLabel('Voting config settings'), findsOneWidget);
    expect(find.byType(MobileBottomSafeArea), findsOneWidget);
    expect(
      tester
          .widget<MobileBottomSafeArea>(find.byType(MobileBottomSafeArea))
          .bottomPadding,
      AppSpacing.md,
    );
    final firstAction = find.byKey(
      const ValueKey('voting_poll_action_snack-governance-active'),
    );
    expect(firstAction, findsOneWidget);
    final card = find.byKey(
      const ValueKey('voting_poll_card_snack-governance-active'),
    );
    final secondCard = find.byKey(
      const ValueKey('voting_poll_card_snack-governance-voted'),
    );
    expect(card, findsOneWidget);
    expect(secondCard, findsOneWidget);
    expect(tester.getTopLeft(card).dx, 16);
    final description = tester.widget<Text>(
      find.byKey(
        const ValueKey('voting_poll_description_snack-governance-active'),
      ),
    );
    expect(
      description.data,
      'A silly sample round for testing the shielded vote builder without '
      'using real governance content.',
    );
    expect(description.maxLines, 3);
    expect(description.overflow, TextOverflow.ellipsis);
    final cardDecoration = tester.widget<Ink>(card).decoration as BoxDecoration;
    expect(cardDecoration.boxShadow, isNotEmpty);
    final cardTap = tester.widget<InkWell>(
      find.byKey(
        const ValueKey('voting_poll_card_tap_snack-governance-active'),
      ),
    );
    expect(cardTap.onTap, isNotNull);
    expect(cardTap.borderRadius, BorderRadius.circular(AppRadii.large));
    expect(
      tester.getTopLeft(secondCard).dy - tester.getBottomLeft(card).dy,
      AppSpacing.md,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_settings_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('mobile_voting_config_sheet')),
      findsOneWidget,
    );
    expect(find.text('Voting config'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_voting_add_source')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Edit Community'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('mobile_voting_config_sheet'))),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_show_test_rounds')),
    );
    await tester.pump();
    expect(container.read(showTestVotingRoundsProvider).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('mobile_voting_add_source')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mobile_voting_source_name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_voting_source_url')),
      findsOneWidget,
    );
  });
}
