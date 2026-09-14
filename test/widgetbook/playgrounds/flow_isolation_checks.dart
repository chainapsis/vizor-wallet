import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import '../../figma_compare/figma_compare_font_loader.dart';
import '../support/wb_receive_qr.dart';
import '../support/wb_gallery_harness.dart';

const _captureDirectory = String.fromEnvironment('VIZOR_FLOW_CAPTURE_DIR');
String _screenPath(String feature) =>
    'screens/$feature/${feature == 'swap' ? 'swap-page' : '$feature-screen'}/screen';
final _screenPaths = [
  'send',
  'swap',
  'pay',
  'receive',
  'settings',
].map(_screenPath).toSet();
const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Lead-owned integration gate: every registered flow starts without touching
/// the real wallet boundary, including calls caught internally by a provider.
void registerFlowIsolationChecks() {
  final rust = _UnexpectedRustCalls();
  final storageCalls = <String>[];

  setUpAll(() async {
    RustLib.initMock(api: rust);
    if (_captureDirectory.isNotEmpty) await loadFigmaCompareFonts();
  });

  setUp(() {
    rust.calls.clear();
    storageCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
          storageCalls.add(call.method);
          throw PlatformException(code: 'unexpected_flow_storage_access');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  test('each main feature has one screen entry and no separate flow entry', () {
    WidgetbookRoot(children: widgetbookDirectories);
    final flows = widgetbookUseCases()
        .where((entry) => _screenPaths.contains(entry.path))
        .toList();
    expect(flows, hasLength(5));
    expect(
      widgetbookUseCases().where((entry) => entry.name == 'Flow playground'),
      isEmpty,
    );
    for (final feature in ['send', 'swap', 'pay', 'receive', 'settings']) {
      expect(
        flows.where((entry) => entry.path.startsWith('screens/$feature/')),
        hasLength(1),
        reason: '$feature needs its own navigable flow, not a global preset',
      );
    }
  });

  for (final feature in ['send', 'swap', 'pay', 'receive', 'settings']) {
    testWidgets('$feature flow starts isolated in its compiled lane', (
      tester,
    ) async {
      final root = WidgetbookRoot(children: widgetbookDirectories);
      final entry = widgetbookUseCases().singleWhere(
        (entry) => entry.path == _screenPath(feature),
      );
      await pumpUseCase(
        tester,
        entry.builder,
        root: root,
        path: entry.path,
        knobs: {'Layout': wbLayoutLabel(wbCompiledLaneLayout)},
        canvasSize: wbCompiledLaneLayout == WbLayout.desktop
            ? const Size(1080, 720)
            : kWbPhoneSize,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(rust.calls, isEmpty, reason: 'flow must use in-memory services');
      expect(
        storageCalls,
        isEmpty,
        reason: 'flow must not access wallet storage',
      );

      if (_captureDirectory.isNotEmpty) {
        if (feature == 'receive') {
          expect(await waitForLoadedReceiveQr(tester), isNull);
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(kWbCaptureKey),
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return await image.toByteData(format: ui.ImageByteFormat.png);
          } finally {
            image.dispose();
          }
        });
        final directory = Directory(_captureDirectory)
          ..createSync(recursive: true);
        File(
          '${directory.path}/$feature.${wbCompiledLaneLayout.name}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      }

      await disposeTree(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        rust.calls,
        isEmpty,
        reason: 'unmount must not clean up real proposals',
      );
      expect(storageCalls, isEmpty);
    });
  }
}

class _UnexpectedRustCalls implements RustLibApi {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError('Flow tried to call Rust: ${invocation.memberName}');
  }
}
