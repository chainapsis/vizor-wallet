import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_picture.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/proxy_delegate_widgets.dart';

import 'support/delegate_picture_fakes.dart';
import 'support/proxy_test_harness.dart';
import 'support/proxy_values.dart';

/// A picture keyed [key] whose bytes do not matter to the fake decoder.
ProxyDelegatePicture _picture(String key) =>
    ProxyDelegatePicture(webp: Uint8List.fromList([1, 2, 3]), key: key);

/// A wallet list listing, with a picture when [pictured].
ProxyDelegateListing _listing({bool pictured = true}) => proxyListingOf(
  index: 17,
  reviewed: true,
  handle: 'alice_votes',
  displayName: 'Alice',
  picture: pictured ? Uint8List.fromList([1, 2, 3]) : null,
);

/// Pumps [child] with [cache] behind every avatar.
Future<void> _pump(
  WidgetTester tester,
  Widget child,
  DelegatePictureCache cache,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [delegatePictureCacheProvider.overrideWithValue(cache)],
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(body: child),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DelegatePictureCache', () {
    test('decodes each picture once and hands out separate handles', () async {
      final decoder = FakeDelegatePictureDecoder();
      final cache = DelegatePictureCache(decoder);
      addTearDown(cache.clear);

      final first = (await cache.load(_picture('aa')))!;
      final second = (await cache.load(_picture('aa')))!;
      final peeked = cache.cached(_picture('aa'))!;

      expect(decoder.calls, ['aa']);
      expect((first.width, first.height), (128, 128));
      expect(first.isCloneOf(second) && second.isCloneOf(peeked), isTrue);
      first.dispose();
      expect(second.debugDisposed, isFalse);
      for (final image in [second, peeked]) {
        image.dispose();
      }
    });

    test('concurrent loads share one decode', () async {
      final decoder = FakeDelegatePictureDecoder();
      final cache = DelegatePictureCache(decoder);
      addTearDown(cache.clear);

      final images = await Future.wait([
        cache.load(_picture('aa')),
        cache.load(_picture('aa')),
      ]);

      expect(decoder.calls, ['aa']);
      expect(images, everyElement(isNotNull));
      for (final image in images) {
        image!.dispose();
      }
    });

    test('a refused picture is null, never thrown, and tried again', () async {
      final decoder = FakeDelegatePictureDecoder()..failure = 'HashMismatch';
      final cache = DelegatePictureCache(decoder);
      addTearDown(cache.clear);

      expect(await cache.load(_picture('aa')), isNull);
      expect(cache.cached(_picture('aa')), isNull);
      decoder.failure = null;
      final image = await cache.load(_picture('aa'));
      expect(image, isNotNull);
      expect(decoder.calls, ['aa', 'aa']);
      image!.dispose();
    });

    test('pixels that are not 128 px are never drawn', () async {
      final decoder = FakeDelegatePictureDecoder()..edge = 64;
      final cache = DelegatePictureCache(decoder);
      addTearDown(cache.clear);

      expect(await cache.load(_picture('aa')), isNull);
    });

    test('evicts the least recently used picture past capacity', () async {
      final decoder = FakeDelegatePictureDecoder();
      final cache = DelegatePictureCache(decoder, capacity: 2);
      addTearDown(cache.clear);

      final held = (await cache.load(_picture('aa')))!;
      (await cache.load(_picture('bb')))!.dispose();
      cache.cached(_picture('aa'))!.dispose();
      (await cache.load(_picture('cc')))!.dispose();

      expect(cache.cached(_picture('bb')), isNull);
      final kept = cache.cached(_picture('aa'))!;
      kept.dispose();
      expect(held.debugDisposed, isFalse, reason: 'a handed-out handle lives');
      held.dispose();
    });
  });

  group('ProxyDelegateAvatar', () {
    testWidgets('draws a decoded picture in place of the identicon', (
      tester,
    ) async {
      final cache = DelegatePictureCache(FakeDelegatePictureDecoder());
      addTearDown(cache.clear);
      final listing = _listing();
      final picture = listing.listPicture!;
      await tester.runAsync(() async => (await cache.load(picture))?.dispose());

      await _pump(tester, ProxyDelegateSummary(entry: listing), cache);

      expect(find.byType(RawImage), findsOne);
      expect(find.byType(ProxyIdenticon), findsNothing);
      expect(find.text('Alice'), findsOne);
    });

    testWidgets('shows the identicon without a picture or on failure', (
      tester,
    ) async {
      final decoder = FakeDelegatePictureDecoder()..failure = 'Malformed';
      final cache = DelegatePictureCache(decoder);
      addTearDown(cache.clear);

      await _pump(
        tester,
        ProxyDelegateSummary(entry: _listing(pictured: false)),
        cache,
      );
      expect(find.byType(ProxyIdenticon), findsOne);
      expect(decoder.calls, isEmpty);

      final listing = _listing();
      await _pump(tester, ProxyDelegateSummary(entry: listing), cache);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(decoder.calls, [listing.listPicture!.key]);
      expect(find.byType(ProxyIdenticon), findsOne);
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('a picture decoded after mounting replaces the identicon', (
      tester,
    ) async {
      final cache = DelegatePictureCache(FakeDelegatePictureDecoder());
      addTearDown(cache.clear);

      await _pump(tester, ProxyDelegateSummary(entry: _listing()), cache);
      expect(find.byType(ProxyIdenticon), findsOne);
      await settleDelegatePictures(tester);

      expect(find.byType(RawImage), findsOne);
      expect(find.byType(ProxyIdenticon), findsNothing);
    });
  });

  group('screens', () {
    /// A cache over the fake decoder that already holds [pictures].
    Future<DelegatePictureCache> warmed(
      WidgetTester tester,
      List<ProxyDelegatePicture> pictures,
    ) async {
      final cache = DelegatePictureCache(FakeDelegatePictureDecoder());
      addTearDown(cache.clear);
      await tester.runAsync(() async {
        for (final picture in pictures) {
          (await cache.load(picture))?.dispose();
        }
      });
      return cache;
    }

    testWidgets('PD-2 and PD-3 show a listed delegate\'s picture', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      final alice = proxyEntry(scenario, 'alice_votes');
      final bjorn = proxyEntry(scenario, 'bjorn_dev');
      final cache = await warmed(tester, [alice.listPicture!]);
      expect(bjorn.picture, isNull);

      await pumpProxyRoute(
        tester,
        proxyDelegateDirectoryRoute(kProxyTestRoundId),
        scenario: scenario,
        pictureCache: cache,
      );
      Finder inRow(ProxyDelegateListing entry, Type type) => find.descendant(
        of: find.byKey(ValueKey('proxy_delegate_row_${entry.index}')),
        matching: find.byType(type),
      );
      expect(inRow(alice, RawImage), findsOne);
      expect(inRow(bjorn, RawImage), findsNothing);
      expect(inRow(bjorn, ProxyIdenticon), findsOne);

      await pumpProxyRoute(
        tester,
        proxyDelegateProfileRoute(kProxyTestRoundId, alice.index),
        scenario: scenario,
        pictureCache: cache,
      );
      expect(find.byType(RawImage), findsOne);
      expect(find.byType(ProxyIdenticon), findsNothing);
    });
  });
}
