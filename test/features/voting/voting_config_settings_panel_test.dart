import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_config_settings_panel.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';

void main() {
  testWidgets('config source actions are disabled during submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          votingConfigSourceStoreProvider.overrideWithValue(
            _FakeVotingConfigSourceStore(),
          ),
          votingSubmissionGuardProvider.overrideWith(
            _GuardedVotingSubmissionGuardNotifier.new,
          ),
        ],
        child: WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, _) {
            return AppTheme(
              data: AppThemeData.light,
              child: const Center(child: VotingConfigSettingsPanel()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = tester.widget<AppButton>(
      find.ancestor(
        of: find.text('Add custom source'),
        matching: find.byType(AppButton),
      ),
    );
    expect(addButton.onPressed, isNull);

    await tester.tap(find.text('Add custom source'));
    await tester.pump();

    expect(find.text('Add Custom Source'), findsNothing);
  });
}

class _GuardedVotingSubmissionGuardNotifier
    extends VotingSubmissionGuardNotifier {
  @override
  List<VotingSubmissionGuard> build() {
    return const [
      VotingSubmissionGuard(
        token: 1,
        accountUuid: 'account-1',
        roundId: 'round-1',
      ),
    ];
  }
}

class _FakeVotingConfigSourceStore implements VotingConfigSourceStore {
  String? sourceUrl;
  String? savedSourcesJson;

  @override
  Future<String?> readSourceUrl() async => sourceUrl;

  @override
  Future<void> writeSourceUrl(String sourceUrl) async {
    this.sourceUrl = sourceUrl;
  }

  @override
  Future<void> resetSourceUrl() async {
    sourceUrl = null;
  }

  @override
  Future<String?> readSavedSourcesJson() async => savedSourcesJson;

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) async {
    this.savedSourcesJson = savedSourcesJson;
  }
}
