@Tags(['mobile'])
library;

import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/keystone_shield_morph.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/particles/particle_field.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/keystone_shield_scanner_surface.dart';

const _parts = ['ur:zcash-pczt/first-frame', 'ur:zcash-pczt/second-frame'];
final _cloud = List.generate(
  80,
  (i) => ShieldParticleSample(
    position: Offset(125 + i % 10 * 8, 210 + i ~/ 10 * 8),
    velocity: const Offset(2, -1),
    size: 2,
    alpha: 0.6,
  ),
);
KeystoneShieldFocus _focus(KeystoneShieldFocusStage stage) =>
    KeystoneShieldFocus(
      stage: stage,
      urParts: _parts,
      scannerBuilder: (_, _) => const SizedBox.shrink(),
    );

Future<Uint8List> _raster(
  WidgetTester tester,
  KeystoneShieldMorph morph, {
  double dpr = 3,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 320, 320),
    Paint()..color = Colors.black,
  );
  morph.paint(canvas);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(
    () => picture.toImage((320 * dpr).round(), (320 * dpr).round()),
  );
  final data = (await tester.runAsync(() => image!.toByteData()))!;
  final bytes = Uint8List.fromList(data.buffer.asUint8List());
  image!.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  testWidgets(
    'the scene restores blur and finishes a scanner exit before success',
    (tester) async {
      final stage = ValueNotifier(KeystoneShieldFocusStage.qr);
      final phase = ValueNotifier(MobileShieldPhase.hardware);
      addTearDown(stage.dispose);
      addTearDown(phase.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: Listenable.merge([stage, phase]),
            builder: (_, _) => MobileShieldScene(
              phase: phase.value,
              amount: '14.12',
              resultAmount: '14.1199',
              title: phase.value == MobileShieldPhase.succeeded
                  ? 'Shielded successfully'
                  : stage.value == KeystoneShieldFocusStage.qr
                  ? 'Approve with Keystone'
                  : 'Scan your Keystone signature',
              footer: const SizedBox(height: 80),
              keystoneFocus: KeystoneShieldFocus(
                stage: stage.value,
                urParts: _parts,
                scannerBuilder: (constraints, morph) =>
                    KeystoneShieldScannerSurface(
                      constraints: constraints,
                      morph: morph,
                      cameraBuilder: (_) => const ColoredBox(
                        key: ValueKey('camera'),
                        color: Colors.black,
                      ),
                      onToggleTorch: () {},
                    ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pump(const Duration(seconds: 2));
      Color background() => tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('mobile_keystone_black_background')),
          )
          .color;
      expect(background(), Colors.black);
      stage.value = KeystoneShieldFocusStage.scanner;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 225));
      expect(background().a, inExclusiveRange(0.0, 1.0));
      await tester.pump(const Duration(seconds: 1));
      expect(background().a, 0);
      expect(find.byKey(const ValueKey('camera')), findsOneWidget);
      stage.value = KeystoneShieldFocusStage.cloud;
      phase.value = MobileShieldPhase.succeeded;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('camera')), findsOneWidget);
      expect(find.text('Shielded successfully'), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile_shield_complete')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('camera')), findsNothing);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.byKey(const ValueKey('mobile_shield_complete')),
        findsOneWidget,
      );
      expect(background().a, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('short screens with large text fit both QR and scanner anchors', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stage = ValueNotifier(KeystoneShieldFocusStage.qr);
    addTearDown(stage.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.5)),
          child: child!,
        ),
        home: ValueListenableBuilder(
          valueListenable: stage,
          builder: (_, value, _) => MobileShieldScene(
            phase: MobileShieldPhase.hardware,
            amount: '14.12',
            title: value == KeystoneShieldFocusStage.qr
                ? 'Approve with Keystone'
                : 'Scan your Keystone signature',
            footer: const SizedBox(height: 80),
            keystoneFocus: KeystoneShieldFocus(
              stage: value,
              urParts: _parts,
              scannerBuilder: (constraints, morph) =>
                  KeystoneShieldScannerSurface(
                    constraints: constraints,
                    morph: morph,
                    cameraBuilder: (_) => const ColoredBox(color: Colors.black),
                    onToggleTorch: () {},
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 20));
    final qr = tester.getRect(
      find.byKey(const ValueKey('mobile_shield_keystone_qr')),
    );
    expect(qr.width, lessThanOrEqualTo(272));
    expect(qr.center.dx, 160);
    stage.value = KeystoneShieldFocusStage.scanner;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('QR settles before frames cycle and uses an exact black hold', (
    tester,
  ) async {
    final morph = KeystoneShieldMorph()
      ..configure(_focus(KeystoneShieldFocusStage.qr));
    addTearDown(morph.dispose);
    morph.setBounds(
      KeystoneShieldAnchorKind.qr,
      const Rect.fromLTWH(40, 160, 280, 280),
    );
    morph.update(0, _cloud);
    morph.update(0.3, _cloud);
    expect(morph.blackMix, inExclusiveRange(0.0, 1.0));
    expect(morph.qrReady, isFalse);
    expect(morph.qrIndex, 0);
    morph.update(0.61, _cloud);
    expect(morph.blackMix, 1);
    expect(morph.qrReady, isTrue);
    morph.update(0.82, _cloud);
    expect(morph.qrIndex, 1);
    expect(morph.blackMix, 1);
    expect(morph.particles.every((p) => p.square == 1 && p.alpha == 1), isTrue);
  });

  for (final dpr in [1.0, 2.0, 3.0]) {
    testWidgets(
      'black QR modules and white quiet zone match every frame at DPR $dpr',
      (tester) async {
        const bounds = Rect.fromLTWH(11.3, 14.7, 280, 280);
        final morph = KeystoneShieldMorph()
          ..configure(_focus(KeystoneShieldFocusStage.qr));
        addTearDown(morph.dispose);
        morph.devicePixelRatio = dpr;
        morph.setBounds(KeystoneShieldAnchorKind.qr, bounds);
        morph.update(0, _cloud);
        morph.update(1.2, _cloud);
        for (var index = 0; index < _parts.length; index++) {
          morph.update(1.21 + index * 0.2, _cloud);
          expect(morph.qrIndex, index);
          final bytes = await _raster(tester, morph, dpr: dpr);
          final qr = QrImage(
            QrCode.fromData(
              data: _parts[index],
              errorCorrectLevel: QrErrorCorrectLevel.M,
            ),
          );
          final pitch = bounds.width / (qr.moduleCount + 8);
          int ink(int x, int y) => bytes[(y * (320 * dpr).round() + x) * 4];
          for (var y = -4; y < qr.moduleCount + 4; y++) {
            for (var x = -4; x < qr.moduleCount + 4; x++) {
              final expected =
                  x >= 0 &&
                  y >= 0 &&
                  x < qr.moduleCount &&
                  y < qr.moduleCount &&
                  qr.isDark(y, x);
              final px = ((bounds.left + (x + 4.5) * pitch) * dpr).floor();
              final py = ((bounds.top + (y + 4.5) * pitch) * dpr).floor();
              expect(
                ink(px, py),
                expected ? 0 : 255,
                reason: 'QR cell ($x, $y)',
              );
            }
          }
        }
      },
    );
  }

  testWidgets(
    'white particles occupy only light cells and the full quiet zone',
    (tester) async {
      const bounds = Rect.fromLTWH(0, 0, 280, 280);
      final frames = KeystoneShieldQrFrames(_parts);
      for (var index = 0; index < _parts.length; index++) {
        final image = frames.frame(index);
        final cells = frames.whiteCells(index, bounds, 3);
        final pitch = bounds.width / (image.moduleCount + 8);
        final positions = {
          for (final p in cells)
            (
              (p.position.dx / pitch).floor() - 4,
              (p.position.dy / pitch).floor() - 4,
            ),
        };
        expect(positions.length, cells.length);
        for (var y = -4; y < image.moduleCount + 4; y++) {
          for (var x = -4; x < image.moduleCount + 4; x++) {
            final dark =
                x >= 0 &&
                y >= 0 &&
                x < image.moduleCount &&
                y < image.moduleCount &&
                image.isDark(y, x);
            expect(positions.contains((x, y)), !dark);
          }
        }
        expect(
          cells.every(
            (p) => p.color == Colors.white && p.alpha == 1 && p.square == 1,
          ),
          isTrue,
        );
      }
    },
  );

  testWidgets(
    'settled QR and departing white particles have identical pixels',
    (tester) async {
      final morph = KeystoneShieldMorph()
        ..configure(_focus(KeystoneShieldFocusStage.qr));
      addTearDown(morph.dispose);
      await tester.runAsync(morph.prepare);
      morph.setBounds(
        KeystoneShieldAnchorKind.qr,
        const Rect.fromLTWH(11.3, 14.7, 280, 280),
      );
      morph.setBounds(
        KeystoneShieldAnchorKind.frame,
        const Rect.fromLTWH(20, 20, 260, 260),
      );
      morph.setBounds(
        KeystoneShieldAnchorKind.torch,
        const Rect.fromLTWH(148, 296, 24, 24),
      );
      morph.devicePixelRatio = 3;
      morph.update(0, _cloud);
      morph.update(0.61, _cloud);
      // Cover both animated QR frames, not only the first morph destination.
      morph.update(0.82, _cloud);
      final held = await _raster(tester, morph);
      morph.configure(_focus(KeystoneShieldFocusStage.scanner));
      morph.update(0.82, _cloud);
      expect(await _raster(tester, morph), orderedEquals(held));
      morph.update(1.3, _cloud);
      morph.configure(_focus(KeystoneShieldFocusStage.qr));
      morph.update(1.31, _cloud);
      morph.update(1.92, _cloud);
      expect(morph.qrReady, isTrue);
      final returned = await _raster(tester, morph);
      morph.configure(_focus(KeystoneShieldFocusStage.cloud));
      morph.update(1.92, _cloud);
      expect(await _raster(tester, morph), orderedEquals(returned));
    },
  );

  testWidgets('camera stays mounted while reverse targets are pending', (
    tester,
  ) async {
    final morph = KeystoneShieldMorph()
      ..configure(_focus(KeystoneShieldFocusStage.qr));
    addTearDown(morph.dispose);
    await tester.runAsync(morph.prepare);
    morph.setBounds(
      KeystoneShieldAnchorKind.qr,
      const Rect.fromLTWH(40, 160, 280, 280),
    );
    morph.setBounds(
      KeystoneShieldAnchorKind.frame,
      const Rect.fromLTWH(50, 140, 260, 260),
    );
    morph.setBounds(
      KeystoneShieldAnchorKind.torch,
      const Rect.fromLTWH(168, 450, 24, 24),
    );
    morph.update(0, _cloud);
    morph.update(1.2, _cloud);
    morph.configure(_focus(KeystoneShieldFocusStage.scanner));
    expect(morph.scannerOpacity, 0);
    morph.update(1.3, _cloud);
    morph.update(2.3, _cloud);
    expect(morph.scannerOpacity, 1);
    expect(morph.blackMix, 0);
    morph.configure(_focus(KeystoneShieldFocusStage.qr));
    expect(morph.scannerVisible, isTrue);
    expect(morph.scannerOpacity, 1);
    morph.update(2.31, _cloud);
    morph.update(2.7, _cloud);
    final previous = morph.particles.map((p) => p.position).toList();
    final black = morph.blackMix;
    morph.configure(_focus(KeystoneShieldFocusStage.scanner));
    morph.update(2.7, _cloud);
    expect(morph.blackMix, black);
    for (var i = 0; i < previous.length; i++) {
      expect(
        (morph.particles[i].position - previous[i]).distance,
        lessThan(0.001),
      );
    }
    morph.update(3.7, _cloud);
    morph.configure(_focus(KeystoneShieldFocusStage.cloud));
    expect(morph.scannerVisible, isTrue);
    morph.update(3.8, _cloud);
    expect(morph.cloudReady, isFalse);
    morph.update(4.8, _cloud);
    expect(morph.cloudReady, isTrue);
    expect(morph.blackMix, 0);
    for (var i = 0; i < _cloud.length; i++) {
      expect(morph.particles[i].position, _cloud[i].position);
    }
  });

  testWidgets('QR perimeter settles before its interior and readiness', (
    tester,
  ) async {
    const bounds = Rect.fromLTWH(40, 160, 280, 280);
    final morph = KeystoneShieldMorph()
      ..configure(_focus(KeystoneShieldFocusStage.qr));
    addTearDown(morph.dispose);
    morph.setBounds(KeystoneShieldAnchorKind.qr, bounds);
    morph.update(0, _cloud);
    morph.update(0.45, _cloud);
    expect(morph.qrReady, isFalse);
    final frames = KeystoneShieldQrFrames(_parts);
    final quiet = bounds.width * 4 / (frames.frame(0).moduleCount + 8);
    final targets = frames.whiteCells(0, bounds, 1);
    final settled = morph.particles
        .where((p) => p.alpha == 1 && p.square == 1)
        .map((p) => p.position)
        .toSet();
    final rim = targets.where(
      (p) => !bounds.deflate(quiet).contains(p.position),
    );
    expect(rim.every((p) => settled.contains(p.position)), isTrue);
    final middle = targets.where(
      (p) => bounds.deflate(90).contains(p.position),
    );
    expect(middle.any((p) => !settled.contains(p.position)), isTrue);
    morph.update(0.61, _cloud);
    expect(morph.qrReady, isTrue);
  });

  testWidgets('QR interior clears locally before the camera dominates', (
    tester,
  ) async {
    const qr = Rect.fromLTWH(40, 160, 280, 280);
    const frame = Rect.fromLTWH(50, 140, 260, 260);
    final morph = KeystoneShieldMorph()
      ..configure(_focus(KeystoneShieldFocusStage.qr));
    addTearDown(morph.dispose);
    await tester.runAsync(morph.prepare);
    morph.setBounds(KeystoneShieldAnchorKind.qr, qr);
    morph.setBounds(KeystoneShieldAnchorKind.frame, frame);
    morph.setBounds(
      KeystoneShieldAnchorKind.torch,
      const Rect.fromLTWH(168, 450, 24, 24),
    );
    morph.update(0, _cloud);
    morph.update(0.61, _cloud);
    morph.update(0.62, _cloud);
    final origin = List.of(morph.particles);
    morph.configure(_focus(KeystoneShieldFocusStage.scanner));
    morph.update(0.63, _cloud);
    morph.update(0.72, _cloud);
    expect(morph.scannerOpacity, 0);
    morph.update(0.855, _cloud);
    expect(morph.scannerOpacity, inExclusiveRange(0.0, 0.5));
    final middle = frame.deflate(45);
    expect(
      morph.particles.where(
        (p) => p.alpha > 0.02 && middle.contains(p.position),
      ),
      isEmpty,
    );
    for (var i = 0; i < origin.length; i++) {
      if (!middle.deflate(10).contains(origin[i].position)) continue;
      expect(
        (morph.particles[i].position - origin[i].position).distance,
        lessThanOrEqualTo(10.01),
      );
      expect(morph.particles[i].alpha, lessThan(0.02));
    }
    morph.update(1.09, _cloud);
    expect(morph.scannerOpacity, 1);
    expect(morph.scannerGlyphOpacity, 1);
    expect(morph.blackMix, 0);
  });

  testWidgets('QR remains usable without decorative cloud samples', (
    tester,
  ) async {
    final morph = KeystoneShieldMorph()
      ..configure(_focus(KeystoneShieldFocusStage.qr));
    addTearDown(morph.dispose);
    morph.setBounds(
      KeystoneShieldAnchorKind.qr,
      const Rect.fromLTWH(20, 100, 280, 280),
    );
    morph.update(0, const []);
    morph.update(2, const []);
    expect(morph.qrReady, isTrue);
    expect(morph.blackMix, 1);
  });

  testWidgets(
    'immediate reversals retain visible scanner glyphs and particles',
    (tester) async {
      final morph = KeystoneShieldMorph()
        ..configure(_focus(KeystoneShieldFocusStage.qr));
      addTearDown(morph.dispose);
      await tester.runAsync(morph.prepare);
      morph.setBounds(
        KeystoneShieldAnchorKind.qr,
        const Rect.fromLTWH(40, 160, 280, 280),
      );
      morph.setBounds(
        KeystoneShieldAnchorKind.frame,
        const Rect.fromLTWH(50, 140, 260, 260),
      );
      morph.setBounds(
        KeystoneShieldAnchorKind.torch,
        const Rect.fromLTWH(168, 450, 24, 24),
      );
      morph.update(0, _cloud);
      morph.update(0.61, _cloud);
      morph.configure(_focus(KeystoneShieldFocusStage.scanner));
      morph.update(0.62, _cloud);
      morph.update(1.08, _cloud);
      morph.configure(_focus(KeystoneShieldFocusStage.qr));
      morph.update(1.09, _cloud);
      morph.update(1.12, _cloud);
      final glyph = morph.scannerGlyphOpacity;
      final camera = morph.scannerOpacity;
      final black = morph.blackMix;
      final particles = List.of(morph.particles);
      expect(glyph, inExclusiveRange(0.0, 1.0));
      morph.configure(_focus(KeystoneShieldFocusStage.scanner));
      morph.update(1.12, _cloud);
      expect(morph.scannerGlyphOpacity, glyph);
      expect(morph.scannerOpacity, camera);
      expect(morph.blackMix, black);
      for (var i = 0; i < particles.length; i++) {
        expect(morph.particles[i].position, particles[i].position);
        expect(morph.particles[i].alpha, particles[i].alpha);
        expect(morph.particles[i].extent, particles[i].extent);
      }
    },
  );

  testWidgets('Reduce Motion preserves QR readiness and the restored blur', (
    tester,
  ) async {
    final morph = KeystoneShieldMorph()
      ..reduceMotion = true
      ..configure(_focus(KeystoneShieldFocusStage.qr));
    addTearDown(morph.dispose);
    morph.setBounds(
      KeystoneShieldAnchorKind.qr,
      const Rect.fromLTWH(40, 160, 280, 280),
    );
    morph.update(0, _cloud);
    for (var i = 0; i < _cloud.length; i++) {
      expect(morph.particles[i].position, _cloud[i].position);
    }
    morph.update(0.2, _cloud);
    expect(morph.qrReady, isTrue);
    expect(morph.blackMix, 1);
    morph.configure(_focus(KeystoneShieldFocusStage.cloud));
    morph.update(0.3, _cloud);
    morph.update(0.5, _cloud);
    expect(morph.cloudReady, isTrue);
    expect(morph.blackMix, 0);
  });
}
