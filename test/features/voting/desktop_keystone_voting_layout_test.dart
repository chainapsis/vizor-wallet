@Tags(['desktop'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zxing2/qrcode.dart' as zxing;

import '../../support/keystone_qr_fixtures.dart';

final _parts = [for (final f in keystoneQrDensityFixtures.take(2)) f.part];
const _memos = [
  VotingKeystoneBatchMemo(
    bundleIndex: 1,
    bundleCount: 3,
    displayMemo: 'Proposal: Community grants\nAmount: 1.25 ZEC',
  ),
  VotingKeystoneBatchMemo(
    bundleIndex: 2,
    bundleCount: 3,
    displayMemo: 'Proposal: Network priorities\nAmount: 0.75 ZEC',
  ),
];

VotingStatusContent _content({
  VoidCallback? onScan,
  bool ready = true,
  bool skip = true,
  String? error,
  int bundle = 1,
  List<String>? parts,
  String? terminalNotice,
}) => VotingStatusContent(
  phase: VotingSessionPhase.keystoneSigning,
  isHardwareAccount: true,
  keystoneSigningBundleIndex: bundle,
  keystoneUrParts: ready ? (parts ?? _parts) : const [],
  keystoneQrError: error,
  terminalDelegationNotice: terminalNotice,
  keystoneBatchMemos: _memos,
  keystoneBatchMessageCount: 2,
  keystoneBatchTotalCount: 3,
  canSkipRemainingKeystoneBundles: skip,
  onScanKeystone: onScan ?? () {},
  onSkipKeystoneBundles: () {},
);

Future<void> _pump(
  WidgetTester tester,
  Widget content, {
  Locale locale = const Locale('en'),
  double scale = 1,
  double pixelRatio = 1,
  Size size = const Size(1080, 720),
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appSupportedLocales(preview: true),
        locale: locale,
        home: AppTheme(
          data: AppThemeData.dark,
          child: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: size,
                devicePixelRatio: pixelRatio,
                textScaler: TextScaler.linear(scale),
              ),
              child: Center(
                child: SizedBox(
                  // Match the desktop shell's 256px sidebar and 8px margins.
                  width: size.width - 280,
                  height: size.height - 16,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final ratio in [1.0, 1.25, 2.0]) {
    testWidgets('desktop voting frames decode on the pixel grid at ${ratio}x', (
      tester,
    ) async {
      final boundaryKey = GlobalKey();
      await _pump(
        tester,
        RepaintBoundary(key: boundaryKey, child: _content()),
        pixelRatio: ratio,
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      for (final surface in ['normal', 'enlarged']) {
        if (surface == 'enlarged') {
          await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
          await tester.pump();
        }
        final stage = find.byKey(ValueKey('voting_qr_$surface'));
        final rect = tester
            .getRect(stage)
            .shift(-boundary.localToGlobal(Offset.zero));
        for (var i = 0; i < _parts.length; i++) {
          final fixture = keystoneQrDensityFixtures[i];
          final text = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: ratio);
            try {
              final rgba = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final source =
                  zxing.RGBLuminanceSource(
                    image.width,
                    image.height,
                    rgba.buffer.asInt32List(),
                  ).crop(
                    (rect.left * ratio).round(),
                    (rect.top * ratio).round(),
                    (rect.width * ratio).round(),
                    (rect.height * ratio).round(),
                  );
              final count = fixture.alphanumericModuleCount;
              final pitch = source.width ~/ (count + 8);
              final margin = (source.width - count * pitch) ~/ 2;
              // The top-left finder starts with seven solid black modules.
              final row = source.getRow(margin, null).buffer.asUint8List();
              expect(row.take(margin), everyElement(255));
              expect(row.skip(margin).take(7 * pitch), everyElement(0));
              expect(row[margin + 7 * pitch], 255);
              return zxing.QRCodeReader()
                  .decode(zxing.BinaryBitmap(zxing.HybridBinarizer(source)))
                  .text;
            } finally {
              image.dispose();
            }
          });
          expect(text, fixture.part);
          await tester.pump(keystoneQrFrameInterval);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    '400px QR and 472px enlargement share playback at the minimum window size',
    (tester) async {
      await _pump(tester, _content());
      expect(
        tester.getSize(find.byKey(const ValueKey('voting_qr_normal'))),
        const Size(400, 400),
      );
      await tester.tap(find.byKey(const ValueKey('keystone_memo_next')));
      await tester.pump();
      expect(find.text('Bundle 3 of 3 memo'), findsOneWidget);
      final playback = tester
          .widget<KeystonePcztQrStage>(
            find.byKey(const ValueKey('voting_qr_normal')),
          )
          .playback!;
      await tester.pump(const Duration(milliseconds: 100));
      final index = playback.value;
      await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('voting_qr_enlarged'))),
        const Size(472, 472),
      );
      expect(
        tester
            .widget<KeystonePcztQrStage>(
              find.byKey(const ValueKey('voting_qr_enlarged')),
            )
            .playback,
        same(playback),
      );
      expect(playback.value, index);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('voting_qr_overlay')),
          matching: find.text('Bundle 3 of 3 · Amount: 0.75 ZEC'),
        ),
        findsOneWidget,
      );
      await tester.pump(keystoneQrFrameInterval);
      expect(playback.value, (index + 1) % _parts.length);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('voting_qr_overlay')), findsNothing);
      expect(find.text('Bundle 3 of 3 memo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('enlarged Scan closes the overlay before invoking the scanner', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      _content(
        onScan: () {
          expect(find.byKey(const ValueKey('voting_qr_overlay')), findsNothing);
          calls++;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('voting_qr_overlay')),
        matching: find.byKey(const ValueKey('voting_scan_signature')),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'updated requests refresh an open enlargement and leaving signing removes it',
    (tester) async {
      final content = ValueNotifier<Widget>(_content());
      addTearDown(content.dispose);
      await _pump(
        tester,
        ValueListenableBuilder(
          valueListenable: content,
          builder: (_, value, _) => value,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
      await tester.pump();
      final nextParts = [_parts.last];
      content.value = _content(bundle: 2, parts: nextParts);
      await tester.pump();
      expect(find.byKey(const ValueKey('voting_qr_overlay')), findsOneWidget);
      final stage = tester.widget<KeystonePcztQrStage>(
        find.byKey(const ValueKey('voting_qr_enlarged')),
      );
      expect(stage.urParts, nextParts);
      expect(stage.playback!.value, 0);
      await tester.pump(keystoneQrFrameInterval);
      expect(stage.playback!.value, 0);
      content.value = const VotingStatusContent(
        phase: VotingSessionPhase.delegating,
        isHardwareAccount: true,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('voting_qr_overlay')), findsNothing);
      expect(find.text('Submitting votes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('help is opt-in and loading cannot enlarge or scan', (
    tester,
  ) async {
    await _pump(tester, _content(ready: false, skip: false));
    expect(
      find.byKey(const ValueKey('voting_use_signed_bundles')),
      findsNothing,
    );
    expect(find.byType(KeystonePcztQrStage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
    await tester.pump();
    expect(find.byKey(const ValueKey('voting_qr_overlay')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('voting_scan_help')));
    await tester.pump();
    expect(find.textContaining('keyst.one/firmware'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a new terminal-bundle warning dismisses enlargement and remains visible',
    (tester) async {
      final content = ValueNotifier<Widget>(_content());
      addTearDown(content.dispose);
      await _pump(
        tester,
        ValueListenableBuilder(
          valueListenable: content,
          builder: (_, value, _) => value,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
      await tester.pump();
      content.value = _content(
        terminalNotice: 'Delegation for bundle 1 cannot continue.',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('voting_qr_overlay')), findsNothing);
      expect(
        find.text('Delegation for bundle 1 cannot continue.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('voting_status_terminal_delegation')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('enlargement traps keyboard focus and returns it on close', (
    tester,
  ) async {
    await _pump(tester, _content(), size: const Size(1296, 864));
    await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('voting_qr_enlarged'))),
      const Size(480, 480),
    );
    final close = tester.widget<AppButton>(
      find.byKey(const ValueKey('voting_close_enlarged_qr')),
    );
    expect(close.focusNode!.hasFocus, isTrue);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        focused.findAncestorWidgetOfExactType<BlockSemantics>(),
        isNotNull,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    final enlarge = tester.widget<AppButton>(
      find.byKey(const ValueKey('voting_enlarge_qr')),
    );
    expect(enlarge.focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in ['en', 'ko', 'zh']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$locale at text scale $scale fits normal and enlarged screens',
        (tester) async {
          await _pump(tester, _content(), locale: Locale(locale), scale: scale);
          expect(tester.takeException(), isNull);
          final enlarge = find.byKey(const ValueKey('voting_enlarge_qr'));
          await tester.ensureVisible(enlarge);
          await tester.tap(enlarge);
          await tester.pump();
          expect(tester.takeException(), isNull);
          final box = tester.getRect(
            find.byKey(const ValueKey('voting_qr_enlarged')),
          );
          expect(box.left, greaterThanOrEqualTo(0));
          expect(box.bottom, lessThanOrEqualTo(720));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
