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
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('shows an animated QR skeleton while preparing PCZT', (
    tester,
  ) async {
    final prepareCompleter = Completer<MobileKeystonePcztSigningPayload>();
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
            preparePczt: (_, _) => prepareCompleter.future,
            onSigned: (_, _, _, _) async {},
            friendlyError: (_) => 'Keystone signing failed.',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_signing')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final placeholder = find.byKey(
      const ValueKey('test_keystone_sign_qr_placeholder'),
    );
    expect(placeholder, findsOneWidget);
    expect(
      find.descendant(of: placeholder, matching: find.byType(AnimatedBuilder)),
      findsOneWidget,
    );
    expect(find.text('Loading the QR code ...'), findsOneWidget);

    prepareCompleter.complete(
      MobileKeystonePcztSigningPayload(
        urParts: const ['ur:zcash-pczt/test'],
        pcztWithProofs: Future.value(const [1, 2, 3]),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('test_keystone_sign_qr_stage')),
      findsOneWidget,
    );
  });

  testWidgets('sizes the QR modal surface to the Figma mobile frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
            preparePczt: (_, _) async => MobileKeystonePcztSigningPayload(
              urParts: const ['ur:zcash-pczt/test'],
              pcztWithProofs: Future.value(const [1, 2, 3]),
            ),
            onSigned: (_, _, _, _) async {},
            friendlyError: (_) => 'Keystone signing failed.',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_signing')));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('test_keystone_sign_modal'))),
      const Size(393, 701),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('test_keystone_sign_modal_surface')),
      ),
      const Size(361, 669),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('test_keystone_sign_qr_stage'))),
      const Size(321, 321),
    );
  });

  testWidgets('ignores repeated scan completions after signing failure', (
    tester,
  ) async {
    ValueChanged<ScanResult>? completeScan;
    var signedCalls = 0;

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
            preparePczt: (_, _) async => MobileKeystonePcztSigningPayload(
              urParts: const ['ur:zcash-pczt/test'],
              pcztWithProofs: Future.value(const [1, 2, 3]),
            ),
            signedPcztDecoder: (_) async => Uint8List.fromList(const [9]),
            scannerBuilder: (_, onComplete, _) {
              completeScan = onComplete;
              return const SizedBox(key: ValueKey('fake_keystone_scanner'));
            },
            forceScannerActiveForTesting: true,
            onSigned: (_, _, _, _) async {
              signedCalls++;
              throw StateError('broadcast rejected');
            },
            friendlyError: (_) => 'Transaction could not be broadcast.',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_signing')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('test_keystone_sign_get_signature')),
    );
    await tester.pump();

    completeScan!(const ScanResult(urType: 'zcash-pczt', data: [1]));
    await tester.pump();
    await tester.pump();

    expect(signedCalls, 1);
    expect(find.text('Transaction could not be broadcast.'), findsOneWidget);

    completeScan!(const ScanResult(urType: 'zcash-pczt', data: [1]));
    await tester.pump();
    await tester.pump();

    expect(signedCalls, 1);
    expect(find.text('Transaction could not be broadcast.'), findsOneWidget);
  });

  testWidgets('resets scanner session after signed PCZT decode failure', (
    tester,
  ) async {
    ValueChanged<ScanResult>? completeScan;
    Object? initialResetToken;
    Object? retryResetToken;
    var decodeCalls = 0;
    var signedCalls = 0;

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
            preparePczt: (_, _) async => MobileKeystonePcztSigningPayload(
              urParts: const ['ur:zcash-pczt/test'],
              pcztWithProofs: Future.value(const [1, 2, 3]),
            ),
            signedPcztDecoder: (_) async {
              decodeCalls++;
              if (decodeCalls == 1) {
                throw StateError('invalid signed pczt');
              }
              return Uint8List.fromList(const [9]);
            },
            scannerBuilder: (_, onComplete, resetToken) {
              completeScan = onComplete;
              initialResetToken ??= resetToken;
              retryResetToken = resetToken;
              return const SizedBox(key: ValueKey('fake_keystone_scanner'));
            },
            forceScannerActiveForTesting: true,
            onSigned: (_, _, _, _) async {
              signedCalls++;
            },
            friendlyError: (_) => 'Keystone signing failed.',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_signing')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('test_keystone_sign_get_signature')),
    );
    await tester.pump();

    completeScan!(const ScanResult(urType: 'zcash-pczt', data: [1]));
    await tester.pump();
    await tester.pump();

    expect(decodeCalls, 1);
    expect(signedCalls, 0);
    expect(
      find.text('This QR code could not be decoded as a Keystone signature.'),
      findsOneWidget,
    );
    expect(retryResetToken, isNot(equals(initialResetToken)));

    completeScan!(const ScanResult(urType: 'zcash-pczt', data: [1]));
    await tester.pump();
    await tester.pump();

    expect(decodeCalls, 2);
    expect(signedCalls, 1);
  });

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
            scannerBuilder: (_, onComplete, _) {
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
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
    expect(find.text('Get signature'), findsOneWidget);
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
