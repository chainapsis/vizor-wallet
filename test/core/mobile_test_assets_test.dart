import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_test_assets.dart';

const _desktop = 'assets/illustrations/desktop/hero.webp';
const _shared = 'assets/illustrations/hero.webp';
const _package = 'packages/example/assets/desktop/icon.svg';
const _codec = StandardMessageCodec();

ByteData _request(String key) =>
    ByteData.sublistView(utf8.encode(Uri(path: Uri.encodeFull(key)).path));

void main() {
  late MobileTestAssets assets;
  late List<String> forwarded;
  final originalBytes = ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
  final manifest = _codec.encodeMessage({
    _desktop: [
      {'asset': _desktop},
    ],
    _shared: [
      {'asset': _shared},
      {
        'asset': 'assets/illustrations/2.0x/hero.webp',
        'dpr': 2.0,
        'extra': true,
      },
      {'asset': _desktop, 'dpr': 3.0},
    ],
    _package: [
      {'asset': _package},
    ],
    'packages/zcash_wallet/$_desktop': [
      {'asset': 'packages/zcash_wallet/$_desktop'},
    ],
  })!;

  setUp(() {
    forwarded = [];
    assets = MobileTestAssets(
      manifest: manifest,
      originalLoad: (message) {
        forwarded.add(utf8.decode(Uint8List.sublistView(message!)));
        return SynchronousFuture(originalBytes);
      },
    );
  });

  test(
    'retains shared variants and dependency assets in the manifest',
    () async {
      final bytes = await assets.handle(_request('AssetManifest.bin'));
      final filtered = _codec.decodeMessage(bytes) as Map<Object?, Object?>;

      expect(filtered.keys, unorderedEquals([_shared, _package]));
      expect(filtered[_shared], [
        {'asset': _shared},
        {
          'asset': 'assets/illustrations/2.0x/hero.webp',
          'dpr': 2.0,
          'extra': true,
        },
      ]);
      expect(forwarded, isEmpty);
    },
  );

  test('blocks direct loads even when they skip manifest lookup', () async {
    expect(await assets.handle(_request(_desktop)), isNull);
    expect(assets.blockedRequests, {_desktop});
    expect(forwarded, isEmpty);
  });

  test(
    'self-package prefixes and encoded filenames cannot bypass the filter',
    () async {
      const prefixed = 'packages/zcash_wallet/$_desktop';
      const spaced = 'assets/illustrations/desktop/hero knight.webp';
      expect(await assets.handle(_request(prefixed)), isNull);
      expect(await assets.handle(_request(spaced)), isNull);
      expect(assets.blockedRequests, {prefixed, spaced});
      expect(forwarded, isEmpty);
    },
  );

  test('permitted loads forward the original request and bytes', () async {
    expect(await assets.handle(_request(_shared)), same(originalBytes));
    expect(await assets.handle(_request(_package)), same(originalBytes));
    expect(forwarded, [_shared, _package]);
    expect(assets.blockedRequests, isEmpty);
  });

  testWidgets('an image fallback preserves the blocked request', (
    tester,
  ) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _FilteredBundle(assets),
        child: MaterialApp(
          home: Image.asset(
            _desktop,
            errorBuilder: (_, _, _) => const Text('fallback'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(assets.blockedRequests, {_desktop});
  });
}

class _FilteredBundle extends CachingAssetBundle {
  _FilteredBundle(this.assets);

  final MobileTestAssets assets;

  @override
  Future<ByteData> load(String key) =>
      assets.handle(_request(key))!.then((bytes) {
        if (bytes == null) throw FlutterError('Unavailable mobile asset: $key');
        return bytes;
      });
}
