import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/near_intents_service_notice.dart';

import 'service_status_fixture.dart';

void serviceNoticeWidgetChecks() {
  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    testWidgets(
      'current and scheduled notices wrap at narrow width in ${identical(theme, AppThemeData.dark) ? 'dark' : 'light'}',
      (tester) async {
        for (final upcoming in [false, true]) {
          final notice = serviceStatusFixture(
            upcoming: upcoming,
            windows: 2,
          ).noticeFor(inputChain: 'zec', outputChain: 'eth')!;
          await tester.pumpWidget(
            MaterialApp(
              home: AppTheme(
                data: theme,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.6),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: SizedBox(
                        width: 288,
                        child: NearIntentsServiceNoticeCard(
                          notice: notice,
                          onDetails: () async {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(
            find.text(
              upcoming ? 'Maintenance scheduled' : 'Swaps may not work',
            ),
            findsOneWidget,
          );
          expect(find.text('Starts'), findsNWidgets(2));
          expect(find.text('Ends'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'incidents do not invent maintenance times; Details opens the fixed page',
    (tester) async {
      final now = DateTime.utc(2026, 11, 3);
      final status = NearIntentsServiceStatus(
        now: now,
        incidentsFetchedAt: now,
        incidents: const [
          NearIntentsServiceIssue(chains: {'*'}),
        ],
      );
      Uri? opened;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nearIntentsServiceStatusProvider.overrideWith(
              () => FixtureServiceStatusNotifier(status),
            ),
            nearIntentsServiceStatusPageLauncherProvider.overrideWithValue((
              uri,
            ) async {
              opened = uri;
              return true;
            }),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: const Scaffold(
                body: NearIntentsServiceNotice(
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  payMode: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Payments may not work'), findsOneWidget);
      expect(find.text('Starts'), findsNothing);
      expect(find.text('Ends'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(
        opened.toString(),
        'https://partners.near-intents.org/shield/status',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected chains and a covering route remove the first-screen notice',
    (tester) async {
      final now = DateTime.utc(2026, 11, 3);
      final status = NearIntentsServiceStatus(
        now: now,
        incidentsFetchedAt: now,
        incidents: const [
          NearIntentsServiceIssue(chains: {'eth'}),
        ],
      );
      final navigator = GlobalKey<NavigatorState>();
      var asset = SwapAsset.sol;
      late StateSetter update;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nearIntentsServiceStatusProvider.overrideWith(
              () => FixtureServiceStatusNotifier(status),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return NearIntentsServiceNotice(
                      direction: SwapDirection.zecToExternal,
                      externalAsset: asset,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Swaps may not work'), findsNothing);
      update(() => asset = SwapAsset.eth);
      await tester.pump();
      expect(find.text('Swaps may not work'), findsOneWidget);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Review')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Swaps may not work', skipOffstage: false),
        findsNothing,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Swaps may not work'), findsOneWidget);
    },
  );
}
