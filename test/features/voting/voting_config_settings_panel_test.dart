import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_config_settings_panel.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';

void main() {
  testWidgets('default source does not duplicate the current URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await _pumpPanel(tester, store: _FakeVotingConfigSourceStore());

    expect(find.text('Voting config'), findsOneWidget);
    expect(find.text('Coinholder poll'), findsOneWidget);
    expect(find.text('Current: Default'), findsNothing);
    expect(find.text(kDefaultStaticVotingConfigSource), findsNothing);
  });

  testWidgets('source entries middle-truncate long URLs', (tester) async {
    const longUrl =
        'https://example.com/path/for/voting/config/source/that/is/definitely/very/long/static-voting-config.json'
        '?checksum=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final expectedDisplay = _expectedMiddleTruncate(longUrl);

    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await _pumpPanel(
      tester,
      store: _FakeVotingConfigSourceStore(
        savedSourcesJson: jsonEncode([
          {'id': 'saved-1', 'name': 'Long Source', 'sourceUrl': longUrl},
        ]),
      ),
    );

    expect(find.text(expectedDisplay), findsOneWidget);
  });

  testWidgets('active unsaved custom source is still rendered', (tester) async {
    const activeUrl =
        'https://example.com/active-unsaved/static-voting-config.json'
        '?checksum=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const savedUrl =
        'https://example.com/saved/static-voting-config.json'
        '?checksum=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await _pumpPanel(
      tester,
      store: _FakeVotingConfigSourceStore(
        sourceUrl: activeUrl,
        savedSourcesJson: jsonEncode([
          {'id': 'saved-1', 'name': 'Saved source', 'sourceUrl': savedUrl},
        ]),
      ),
    );

    expect(find.text('Custom source'), findsOneWidget);
    expect(find.text(_expectedMiddleTruncate(activeUrl)), findsOneWidget);
    expect(find.text('Saved source'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('copy action copies full source URL', (tester) async {
    const savedUrl =
        'https://example.com/path/for/voting/config/source/that/is/definitely/very/long/static-voting-config.json'
        '?checksum=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final copiedTexts = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final clipboardArgs = call.arguments as Map<dynamic, dynamic>;
          copiedTexts.add(clipboardArgs['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpPanel(
      tester,
      store: _FakeVotingConfigSourceStore(
        savedSourcesJson: jsonEncode([
          {'id': 'saved-copy', 'name': 'Saved Copy', 'sourceUrl': savedUrl},
        ]),
      ),
    );

    final copyIcons = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.copy,
    );
    expect(copyIcons, findsNWidgets(2));

    await tester.tap(copyIcons.first);
    await tester.pump();

    await tester.tap(copyIcons.at(1));
    await tester.pump();

    expect(
      copiedTexts,
      unorderedEquals([kDefaultStaticVotingConfigSource, savedUrl]),
    );
  });

  testWidgets('source selection is saved only after save', (tester) async {
    const savedUrl =
        'https://example.com/custom-static-voting-config.json'
        '?checksum=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final store = _FakeVotingConfigSourceStore(
      sourceUrl: savedUrl,
      savedSourcesJson: jsonEncode([
        {'id': 'saved-current', 'name': 'Saved source', 'sourceUrl': savedUrl},
      ]),
    );

    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await _pumpPanel(tester, store: store);

    expect(find.text('Use'), findsNothing);
    expect(store.sourceUrl, savedUrl);

    await tester.tap(find.text('Coinholder poll'));
    await tester.pump();

    expect(store.sourceUrl, savedUrl);

    final saveButton = tester.widget<AppButton>(
      find.ancestor(of: find.text('Save'), matching: find.byType(AppButton)),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.sourceUrl, isNull);
    expect(find.text('Current: Default'), findsNothing);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('config source actions are disabled during submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await _pumpPanel(
      tester,
      store: _FakeVotingConfigSourceStore(),
      guarded: true,
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

    expect(find.text('Static config URL'), findsNothing);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required _FakeVotingConfigSourceStore store,
  bool guarded = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(store),
        votingConfigProvider.overrideWith(_NoopVotingConfigNotifier.new),
        votingRoundsProvider.overrideWith(_NoopVotingRoundsNotifier.new),
        if (guarded)
          votingSubmissionGuardProvider.overrideWith(
            _GuardedVotingSubmissionGuardNotifier.new,
          ),
      ],
      child: WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, _) {
          return AppTheme(
            data: AppThemeData.light,
            child: const AppToastHost(
              child: Center(child: VotingConfigSettingsPanel()),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _expectedMiddleTruncate(String raw) {
  final compact = _compactForExpectation(raw);
  if (compact.length <= 56) return compact;
  return '${compact.substring(0, 28)}...${compact.substring(compact.length - 25)}';
}

String _compactForExpectation(String raw) {
  final uri = Uri.parse(raw);
  final path = uri.path.replaceFirst(RegExp(r'^/'), '');
  return path.isEmpty ? uri.host : '${uri.host}/$path';
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

class _NoopVotingConfigNotifier extends VotingConfigNotifier {
  @override
  Future<rust_config.ResolvedVotingConfig> build() async {
    return const rust_config.ResolvedVotingConfig(
      sourceFingerprint: 'source-fingerprint',
      trustedKeyFingerprint: 'trusted-key-fingerprint',
      dynamicConfigFingerprint: 'dynamic-config-fingerprint',
      voteServers: [],
      pirEndpoints: [],
      supportedVersions: rust_config.SupportedVersions(
        pir: [],
        voteProtocol: 'vote-protocol',
        tally: 'tally',
        voteServer: 'vote-server',
      ),
      authenticatedRounds: [],
      skippedRoundIds: [],
      conditions: [],
    );
  }

  @override
  Future<void> refresh() async {}
}

class _NoopVotingRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => const [];

  @override
  Future<void> reload() async {}
}

class _FakeVotingConfigSourceStore implements VotingConfigSourceStore {
  _FakeVotingConfigSourceStore({this.sourceUrl, this.savedSourcesJson});

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
