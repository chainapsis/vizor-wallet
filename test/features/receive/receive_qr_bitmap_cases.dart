import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';

/// Registered by both receive-screen suites so the normal desktop and mobile
/// lanes exercise the same asynchronous bitmap lifecycle regressions.
void registerReceiveQrBitmapTests() {
  group('receive QR bitmap lifecycle', () {
    late _BadgeStreams badges;

    setUp(() {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      badges = _BadgeStreams();
    });
    tearDown(() {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      badges.dispose();
    });

    testWidgets('renders a delayed badge after its cache entry is cleared', (
      tester,
    ) async {
      final shield = badges.install(_shieldAsset);
      await tester.pumpWidget(_surface());
      expect(find.byType(RawImage), findsNothing);

      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      shield.emit(const Color(0xFFCC0000));
      await _finishBitmap(tester);

      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      // No replacement decode or snapshot image should enter the global cache.
      expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
      expect(PaintingBinding.instance.imageCache.currentSize, 0);
      expect(shield.hasListeners, isFalse);
    });

    testWidgets('cache replacement cannot repaint an ended QR canvas', (
      tester,
    ) async {
      final first = badges.install(_shieldAsset);
      await tester.pumpWidget(_surface());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      final replacement = badges.install(_shieldAsset);

      // The old exporter would resolve the replacement stream while painting
      // the first frame, end its recording, then repaint that invalid Canvas.
      first.emit(const Color(0xFFCC0000));
      replacement.emit(const Color(0xFF000000));
      await _finishBitmap(tester);

      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(first.hasListeners, isFalse);
      expect(replacement.hasListeners, isFalse);
    });

    testWidgets('unmounting detaches a pending badge listener', (tester) async {
      final shield = badges.install(_shieldAsset);
      await tester.pumpWidget(_surface());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      expect(shield.hasListeners, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(shield.hasListeners, isFalse);
      shield.emit(const Color(0xFFCC0000));
      await _finishBitmap(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('switching pools ignores the previous delayed badge', (
      tester,
    ) async {
      final shield = badges.install(_shieldAsset);
      final transparent = badges.install(_transparentAsset);
      await tester.pumpWidget(_surface());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      // The transparent asset is reinstalled after clearing the cache.
      badges.reinstall(_transparentAsset, transparent);
      await tester.pumpWidget(_surface(type: ReceiveAddressType.transparent));

      expect(shield.hasListeners, isFalse);
      shield.emit(const Color(0xFFCC0000));
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);

      transparent.emit(const Color(0xFF000000));
      await _finishBitmap(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a badge decode error reaches the QR error state', (
      tester,
    ) async {
      final shield = badges.install(_shieldAsset);
      await tester.pumpWidget(_surface());
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      shield.fail(StateError('badge decode failed'));
      await tester.pump();

      expect(find.text('QR unavailable'), findsOneWidget);
      expect(shield.hasListeners, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses a warm badge without retaining an extra cache entry', (
      tester,
    ) async {
      final shield = badges.install(_shieldAsset);
      shield.emit(const Color(0xFFCC0000));
      final cacheSize = PaintingBinding.instance.imageCache.currentSize;
      await tester.pumpWidget(_surface());
      await _finishBitmap(tester);

      expect(find.byType(RawImage), findsOneWidget);
      expect(PaintingBinding.instance.imageCache.currentSize, cacheSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes the displayed bitmap on unmount', (tester) async {
      final shield = badges.install(_shieldAsset);
      shield.emit(const Color(0xFFCC0000));
      await tester.pumpWidget(_surface());
      await _finishBitmap(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(image.debugDisposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(image.debugDisposed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('later badge frames do not repaint the finished bitmap', (
      tester,
    ) async {
      final shield = badges.install(_shieldAsset);
      await tester.pumpWidget(_surface());
      shield.emit(const Color(0xFFCC0000));
      await _finishBitmap(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;

      shield.emit(const Color(0xFF000000));
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(image));
      expect(tester.takeException(), isNull);
    });
  });
}

const _shieldAsset = 'assets/icons/receive_qr_shield_crimson.png';
const _transparentAsset = 'assets/icons/receive_qr_transparent_dark.png';

Widget _surface({ReceiveAddressType type = ReceiveAddressType.shielded}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: AppTheme(
        data: AppThemeData.dark,
        child: Center(
          child: ReceiveQrSurface(
            address: type == ReceiveAddressType.shielded
                ? 'u1test-shielded-address'
                : 't1test-transparent-address',
            size: 256,
            paddingX: 16,
            paddingY: 16,
            type: type,
            scanOptimized: type == ReceiveAddressType.transparent,
          ),
        ),
      ),
    );

Future<void> _finishBitmap(WidgetTester tester) async {
  // Picture.toImage completes in the real async zone. Complete all controlled
  // image loads before waiting; no arbitrary sleep or permanent spinner settle.
  await tester.pump();
  await tester.runAsync(() async {
    await tester.pumpAndSettle();
  });
  await tester.pump();
}

class _BadgeStreams {
  final _handles = <ImageStreamCompleterHandle>[];

  _ControlledBadge install(String asset) {
    final stream = _ControlledBadge();
    _handles.add(stream.keepAlive());
    reinstall(asset, stream);
    return stream;
  }

  void reinstall(String asset, _ControlledBadge stream) {
    PaintingBinding.instance.imageCache.putIfAbsent(
      AssetBundleImageKey(bundle: rootBundle, name: asset, scale: 1),
      () => stream,
    );
  }

  void dispose() {
    for (final handle in _handles) {
      handle.dispose();
    }
  }
}

class _ControlledBadge extends ImageStreamCompleter {
  void emit(Color color) {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = color);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(16, 16);
    picture.dispose();
    setImage(ImageInfo(image: image));
  }

  void fail(Object error) => reportError(
    context: ErrorDescription('loading a controlled QR badge'),
    exception: error,
    stack: StackTrace.current,
  );
}
