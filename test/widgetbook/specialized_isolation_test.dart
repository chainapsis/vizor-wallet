import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_tree_sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/migration_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/gift_cards_gallery.dart';
import 'package:zcash_wallet/widgetbook/gift_cards_screen_use_cases.dart';
import 'support/wb_gallery_harness.dart';
import '../figma_compare/figma_compare_font_loader.dart';

void main() {
  final rust = _NativeTrap();
  final nativeCalls = <String>[];
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('plugins.flutter.io/shared_preferences'),
    MethodChannel('plugins.flutter.io/url_launcher'),
  ];
  setUpAll(() async {
    await loadFigmaCompareFonts();
    RustLib.initMock(api: rust);
  });
  setUp(() {
    rust.calls.clear();
    nativeCalls.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add('${channel.name}:${call.method}');
            throw PlatformException(code: 'unexpected_preview_io');
          });
    }
  });
  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void expectIsolated() {
    expect(rust.calls, isEmpty);
    expect(nativeCalls, isEmpty);
  }

  final surfaces = <String, WidgetBuilder>{
    'Voting polls': buildVotingPollListCase,
    'Voting review': buildVotingReviewCase,
    'Migration flow': buildMigrationFlowGalleryCase,
    'Migration schedule': buildMigrationScheduleGalleryCase,
    'Migration signing': buildMigrationKeystoneCombinedSignGalleryCase,
  };
  for (final surface in surfaces.entries) {
    for (final action in {
      'Activity': '/activity',
      'Sign out': '/unlock',
    }.entries) {
      testWidgets('${surface.key} isolates ${action.key}', (tester) async {
        await pumpUseCase(tester, surface.value, knobs: {'Layout': 'Desktop'});
        await advance(tester);
        final sidebar = find.byType(AppMainSidebar);
        final context = tester.element(sidebar);
        final router = GoRouter.of(context);
        final container = ProviderScope.containerOf(context, listen: false);
        expect(container.exists(chainUpgradeStatusProvider), isFalse);
        if (surface.key.startsWith('Voting')) {
          await container
              .read(votingTreePreSyncProvider)
              .preSyncRound('preview');
          expect(container.exists(votingWalletDbPathProvider), isFalse);
          final forum = find.text('Forum discussion');
          if (forum.evaluate().isNotEmpty) {
            await tester.tap(forum.first);
            await advance(tester);
            expectIsolated();
          }
        }
        await tester.tap(
          find.descendant(of: sidebar, matching: find.text(action.key)),
        );
        await advance(tester);
        expect(router.routerDelegate.currentConfiguration.error, isNull);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          action.value,
        );
        await disposeTree(tester);
        await advance(tester);
        expectIsolated();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('gift card signature scan returns without native IO', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildGiftCardsKeystoneSigningGalleryCase,
      knobs: {
        'Phase': giftCardsKeystonePhaseLabel(GiftCardsKeystonePhase.ready),
      },
    );
    await advance(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Get signature'));
      await advance(tester);
      expect(
        find.text('Signature scanning is unavailable in this preview.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back to QR'));
      await advance(tester);
      expect(find.text('Get signature'), findsOneWidget);
    }
    await disposeTree(tester);
    await advance(tester);
    expectIsolated();
    expect(tester.takeException(), isNull);
  });
  testWidgets('migration stop confirmation stays in memory', (tester) async {
    await pumpUseCase(
      tester,
      buildMigrationScheduleGalleryCase,
      knobs: {'Layout': 'Desktop', 'Overlay': 'Stop', 'Stop available': 'true'},
    );
    await advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('ironwood_confirm_stop_migration_button')),
    );
    await advance(tester);
    expect(find.textContaining('/home'), findsWidgets);
    await disposeTree(tester);
    await advance(tester);
    expectIsolated();
    expect(tester.takeException(), isNull);
  });
  testWidgets('immediate migration cannot broadcast from preview', (
    tester,
  ) async {
    await pumpUseCase(tester, buildMigrationImmediateReviewGalleryCase);
    await advance(tester);
    await tester.tap(
      find.byKey(
        const ValueKey('ironwood_migration_immediate_broadcast_button'),
      ),
    );
    await advance(tester);
    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    await disposeTree(tester);
    await advance(tester);
    expectIsolated();
    expect(tester.takeException(), isNull);
  });
}

class _NativeTrap implements RustLibApi {
  final calls = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError('Unexpected native call: ${invocation.memberName}');
  }
}
