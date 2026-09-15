import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/widgetbook/gallery/migration_gallery.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

class _NativeTrap extends RustLibApi {
  final calls = <Symbol>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('Unexpected native preview call');
  }
}

void main() {
  final rust = _NativeTrap();
  final calls = <String>[];
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
    calls.clear();
    rust.calls.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add('${channel.name}:${call.method}');
            throw StateError('Unexpected platform preview call');
          });
    }
  });
  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  for (final gallery in [true, false]) {
    testWidgets(
      'mobile fast review isolates submit and navigation gallery=$gallery',
      (tester) async {
        await pumpUseCase(
          tester,
          (context) => ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWith((ref) {
                calls.add('bootstrap');
                throw StateError('Preview must not load wallet bootstrap');
              }),
            ],
            child: Builder(
              builder: gallery
                  ? buildMigrationFlowGalleryCase
                  : buildMobileIronwoodMigrationFastReviewUseCase,
            ),
          ),
          knobs: {'Layout': 'Mobile', 'Step': 'Fast review'},
        );

        Future<void> advance() async {
          for (var frame = 0; frame < 12; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(tester.takeException(), isNull);
        }

        await advance();
        // Back and Done must remain inside this mounted preview router.
        await tester.tap(find.text('Consider another option'));
        await advance();
        expect(find.text('Private'), findsOneWidget);
        // The private action queries only the fake permission service and
        // lands on an explicit execution boundary, never native preparation.
        await tester.tap(find.text('Continue'));
        await advance();
        expect(
          find.text(
            'Private migration execution is unavailable in this preview.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Back to options'));
        await advance();
        // Follow the real informational back links, then walk forward again.
        for (var step = 0; step < 2; step++) {
          await tester.tap(
            find.descendant(
              of: find.byType(MobileTopNav),
              matching: find.byType(GestureDetector),
            ),
          );
          await advance();
        }
        await tester.tap(find.text('Official release note'));
        await advance();
        await tester.tap(find.text('Next'));
        await advance();
        await tester.tap(find.text('Continue'));
        await advance();
        expect(find.text('Private'), findsOneWidget);
        await tester.tap(find.text('Immediate'));
        await advance();
        await tester.tap(find.text('Continue'));
        await advance();
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.tap(find.text('Continue anyway'));
          await advance();
          expect(find.text('Migration submitted'), findsOneWidget);
          expect(
            find.text(
              'Simulated preview. No transaction was signed or broadcast.',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Done'));
          await advance();
          expect(find.text('Preview: /home'), findsOneWidget);
          await tester.tap(find.text('Restart preview'));
          await advance();
          expect(find.text('Continue anyway'), findsOneWidget);
        }
        expect(calls, isEmpty);
        expect(rust.calls, isEmpty);
        await disposeTree(tester);
      },
    );
  }
}
