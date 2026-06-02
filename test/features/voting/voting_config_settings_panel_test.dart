import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_config_settings_panel.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';

void main() {
  testWidgets('default source shows current URL', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await _pumpPanel(tester, store: _FakeVotingConfigSourceStore());

    expect(find.text('Current: Default'), findsOneWidget);
    expect(find.text(kDefaultStaticVotingConfigSource), findsOneWidget);
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

  testWidgets('copy action copies full source URL', (tester) async {
    const savedUrl =
        'https://example.com/path/for/voting/config/source/that/is/definitely/very/long/static-voting-config.json'
        '?checksum=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCall = call;
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

    await tester.tap(find.bySemanticsLabel('Copy source URL').first);
    await tester.pump();

    expect(clipboardCall, isNotNull);
    final clipboardArgs = clipboardCall!.arguments as Map<dynamic, dynamic>;
    expect(clipboardArgs['text'], kDefaultStaticVotingConfigSource);

    await tester.tap(find.bySemanticsLabel('Copy source URL').at(1));
    await tester.pump();

    final secondClipboardArgs = clipboardCall!.arguments as Map<dynamic, dynamic>;
    expect(secondClipboardArgs['text'], savedUrl);
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

class _FakeVotingConfigSourceStore implements VotingConfigSourceStore {
  _FakeVotingConfigSourceStore({this.savedSourcesJson});

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
