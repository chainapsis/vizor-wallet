// Lane-agnostic: invoke this untagged file directly with
// --dart-define=VIZOR_FORM_FACTOR=mobile to exercise mobile tokens.
// --tags mobile excludes untagged files.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';

import 'support/request_amount_test_support.dart';

void main() {
  group('renderRequestQrPng', () {
    testWidgets(
      'encodes a request as a deterministic square PNG',
      (tester) async {
        final uri = requestWithAmount.requestUri!;
        await tester.runAsync(() async {
          final png = await renderRequestQrPng(uri, size: 256);
          final again = await renderRequestQrPng(uri, size: 256);

          expect(png, isNotEmpty);
          expect(png.sublist(0, 8), requestPngSignature);
          // Same request, same bytes: nothing theme- or time-dependent leaks in.
          expect(again, png);

          final decoded = await decodeImageFromList(png);
          expect(decoded.width, 256);
          expect(decoded.height, 256);
          decoded.dispose();
        });
      },
      timeout: requestEncodeTimeout,
    );

    testWidgets('refuses an empty request rather than encoding nothing', (
      tester,
    ) async {
      await expectLater(renderRequestQrPng(''), throwsArgumentError);
    });
  });

  group('RequestQrExportButton', () {
    testWidgets(
      'the button stays busy until the hand-off completes',
      (tester) async {
        // The desktop save dialog and the mobile share sheet both outlive the
        // PNG render; a second press while one is open would start a second
        // export.
        final handoff = Completer<void>();
        var delivered = 0;
        await pumpRequestWidget(
          tester,
          RequestQrExportButton(
            key: const ValueKey('export_button'),
            uri: 'zcash:u1exportbusy',
            label: 'Save QR image',
            onBytes: (_) {
              delivered++;
              return handoff.future;
            },
          ),
        );

        await tester.tap(find.byKey(const ValueKey('export_button')));
        await tester.pump();
        await settleRequestEncode(tester);

        expect(delivered, 1);
        expect(requestExportButton(tester, 'export_button').onPressed, isNull);

        handoff.complete();
        await tester.pump();

        expect(
          requestExportButton(tester, 'export_button').onPressed,
          isNotNull,
        );
      },
      timeout: requestEncodeTimeout,
    );

    testWidgets(
      'an encode that fails calls onError and frees the button',
      (tester) async {
        final delivered = <Uint8List>[];
        var errors = 0;
        await pumpRequestWidget(
          tester,
          RequestQrExportButton(
            key: const ValueKey('export_button'),
            // Past the byte capacity of every symbol version, so the encoder
            // refuses it. Before this the press was a silent no-op: the future
            // is unawaited, so the throw escaped as a zone error and the user
            // saw the spinner blink and nothing else.
            uri: 'zcash:${'u' * 4000}',
            label: 'Save QR image',
            onBytes: delivered.add,
            onError: () => errors++,
          ),
        );

        await tester.tap(find.byKey(const ValueKey('export_button')));
        await tester.pump();
        await settleRequestEncode(tester);

        expect(delivered, isEmpty);
        expect(errors, 1);
        expect(tester.takeException(), isNull);
        // Still pressable: the failure is reported, not terminal.
        expect(
          requestExportButton(tester, 'export_button').onPressed,
          isNotNull,
        );
      },
      timeout: requestEncodeTimeout,
    );
  });
}
