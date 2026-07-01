@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

void main() {
  testWidgets('cancel controls stay disabled while finalizing signed PCZT', (
    tester,
  ) async {
    final signingCompleter = Completer<void>();
    ValueChanged<ScanResult>? completeScan;

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Center(
            child: TextButton(
              key: const ValueKey('open_signing'),
              onPressed: () => context.push('/sign'),
              child: const Text('Open signing'),
            ),
          ),
        ),
        GoRoute(
          path: '/sign',
          builder: (_, _) => MobileKeystonePcztSigningFlow(
            title: 'Confirm transaction',
            description: 'Scan with Keystone.',
            keyPrefix: 'test_keystone_sign',
            finalizingSignatureLabel: 'Broadcasting ZEC deposit...',
            preparePczt: (_, _) async => MobileKeystonePcztSigningPayload(
              urParts: const ['ur:zcash-pczt/test'],
              pcztWithProofs: Future.value(const [1, 2, 3]),
            ),
            signedPcztDecoder: (_) async => Uint8List.fromList(const [9]),
            scannerBuilder: (_, onComplete) {
              completeScan = onComplete;
              return const SizedBox(key: ValueKey('fake_keystone_scanner'));
            },
            forceScannerActiveForTesting: true,
            onSigned: (_, _, _, _) => signingCompleter.future,
            friendlyError: (_) => 'Keystone signing failed.',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_signing')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.text('Scan with your Keystone'), findsOneWidget);
    expect(find.text('Get Signature'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('test_keystone_sign_get_signature')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('fake_keystone_scanner')), findsOneWidget);

    completeScan!(const ScanResult(urType: 'zcash-pczt', data: [1]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Broadcasting ZEC deposit...'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel('Close scanner'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('fake_keystone_scanner')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake_keystone_scanner')), findsOneWidget);

    signingCompleter.complete();
    await tester.pump();
  });
}
