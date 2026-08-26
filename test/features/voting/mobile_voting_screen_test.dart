@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_bottom_safe_area.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/src/providers/voting/voting_round_visibility_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_poll_eligibility_provider.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_polls_screen.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

void main() {
  testWidgets(
    'only confirmed eligibility shows View, and refresh clears stale labels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      var result = Completer<VotingPollEligibility>();
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Builder(
              builder: (context) => buildMobileVotingPollsEligibilityUseCase(
                context,
                loadEligibility: (_) => result.future,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not eligible for this round'), findsNothing);
      expect(find.text('Vote'), findsNWidgets(2));
      result.complete(VotingPollEligibility.ineligible);
      await tester.pumpAndSettle();
      expect(find.text('Not eligible for this round'), findsNWidgets(2));
      expect(find.text('View'), findsNWidgets(2));
      result = Completer<VotingPollEligibility>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VotingPollsView)),
      );
      container.invalidate(votingPollEligibilityProvider);
      await tester.pumpAndSettle();
      expect(find.text('Not eligible for this round'), findsNothing);
      result.completeError(StateError('Eligibility unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Not eligible for this round'), findsNothing);
      expect(find.text('Vote'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.byType(VotingForumLinkButton), findsNWidgets(3));
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
    final descriptionFinder = find.byKey(
      const ValueKey('voting_poll_description_snack-governance-active'),
    );
    final description = tester.widget<Text>(descriptionFinder);
    expect(
      description.data,
      'Welcome\nThis poll resolves outstanding NU7 scope questions following '
      'the early-2026 sentiment polling. Already in NU7, established by prior '
      'consensus.',
    );
    expect(description.maxLines, 3);
    expect(description.overflow, TextOverflow.ellipsis);
    expect(
      tester.renderObject<RenderParagraph>(descriptionFinder).didExceedMaxLines,
      isTrue,
    );
    expect(tester.getSize(card).height, tester.getSize(secondCard).height);
    final cardDecoration = tester.widget<Ink>(card).decoration as BoxDecoration;
    expect(cardDecoration.boxShadow, isNotEmpty);
    final cardTap = tester.widget<InkWell>(
      find.byKey(
        const ValueKey('voting_poll_card_tap_snack-governance-active'),
      ),
    );
    expect(cardTap.onTap, isNotNull);
    expect(cardTap.borderRadius, BorderRadius.circular(AppRadii.large));
    expect(cardTap.splashFactory, NoSplash.splashFactory);
    expect(
      cardTap.overlayColor?.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    expect(cardTap.overlayColor?.resolve({WidgetState.focused}), isNull);
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
    expect(find.text('Vote config'), findsOneWidget);
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

    final cancel = find.text('Cancel');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    final close = find.byKey(const ValueKey('mobile_voting_config_close'));
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_voting_config_sheet')),
      findsNothing,
    );
    expect(container.read(showTestVotingRoundsProvider).value, isTrue);
    expect(find.text('Coinholder voting'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_settings_button')),
    );
    await tester.pumpAndSettle();
    final closeIcon = find.bySemanticsLabel('Close').last;
    expect(tester.getSize(closeIcon), const Size(32, 32));
    await tester.tap(closeIcon);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_voting_config_sheet')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
