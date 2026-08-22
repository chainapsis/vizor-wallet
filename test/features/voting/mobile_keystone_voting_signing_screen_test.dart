@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

void main() {
  testWidgets('uses the mobile Keystone two-step signing presentation', (
    tester,
  ) async {
    await _pumpSigningScreen(tester);

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Scan with Keystone'), findsOneWidget);
    expect(find.text('2 of 3 remaining bundles'), findsOneWidget);
    expect(find.text('Bundle 1 of 3'), findsOneWidget);
    expect(find.textContaining('Amount: 1.25 ZEC'), findsOneWidget);
    expect(find.text('Skip unsigned bundles'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_keystone_get_signature')),
    );
    await tester.pump();

    expect(find.text('Step 2/2'), findsOneWidget);
    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_voting_keystone_scanner_card')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the camera open after a recoverable voting scan error', (
    tester,
  ) async {
    await _pumpSigningScreen(
      tester,
      onSigned: (_) async => throw StateError('Signature does not match vote'),
      interactiveScanner: true,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_keystone_get_signature')),
    );
    await tester.pump();
    tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('fake_voting_scanner')),
        )
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Signature does not match vote'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_voting_keystone_scanner_card')),
      findsOneWidget,
    );
  });

  testWidgets('fits a compact mobile viewport without layout overflow', (
    tester,
  ) async {
    await _pumpSigningScreen(tester, viewport: const Size(320, 568));

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Skip unsigned bundles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSigningScreen(
  WidgetTester tester, {
  Future<void> Function(List<int>)? onSigned,
  bool interactiveScanner = false,
  Size viewport = const Size(393, 852),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AppTheme(
          data: AppThemeData.dark,
          child: MobileKeystoneVotingSigningScreen(
            presentation: VotingKeystoneStatusPresentation(
              bundleIndex: 0,
              urParts: const [_previewVotingUr],
              batchMemos: const [
                VotingKeystoneBatchMemo(
                  bundleIndex: 0,
                  bundleCount: 3,
                  displayMemo: 'Amount: 1.25 ZEC\nProposal: Community grants',
                ),
                VotingKeystoneBatchMemo(
                  bundleIndex: 1,
                  bundleCount: 3,
                  displayMemo: 'Amount: 0.75 ZEC\nProposal: Network priorities',
                ),
              ],
              batchMessageCount: 2,
              batchTotalCount: 3,
              canSkipRemainingBundles: true,
              onSigned: onSigned ?? _noopSigned,
              onSkipRemainingBundles: _noop,
            ),
            scannerBuilder: (_, complete, progress, _) => GestureDetector(
              key: const ValueKey('fake_voting_scanner'),
              behavior: HitTestBehavior.opaque,
              onTap: interactiveScanner
                  ? () {
                      progress(100);
                      complete(
                        const ScanResult(
                          urType: 'zcash-batch-sig-result',
                          data: [1, 2, 3],
                        ),
                      );
                    }
                  : null,
              child: const ColoredBox(color: Color(0xFF111515)),
            ),
            forceScannerActiveForTesting: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _noopSigned(List<int> _) async {}
void _noop() {}

const _previewVotingUr =
    'ur:zcash-sign-batch/1-1/lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcx';
