@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(find.text('Amount: 1.25000000 ZEC.'), findsOneWidget);
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

  testWidgets('paints the amount the memo ends with, not just the sentence', (
    tester,
  ) async {
    await _pumpSigningScreen(tester);

    _expectFullyPainted(tester, 'Amount: 1.25000000 ZEC.');
  });

  testWidgets('paints each bundle amount while paging between memos', (
    tester,
  ) async {
    await _pumpSigningScreen(tester);
    _expectFullyPainted(tester, 'Amount: 1.25000000 ZEC.');

    await tester.tap(find.bySemanticsLabel('Next voting bundle'));
    await tester.pump();

    expect(find.text('Bundle 2 of 3'), findsOneWidget);
    _expectFullyPainted(tester, 'Amount: 0.75000000 ZEC.');
  });

  testWidgets('keeps the amount painted when the round name is long', (
    tester,
  ) async {
    // `display_memo()` budgets 414 bytes for the round name, and round names
    // come from remote voting config. The memo box must clamp the sentence
    // rather than push the amount off screen or overflow the column.
    await _pumpSigningScreen(
      tester,
      viewport: const Size(320, 568),
      memos: [
        VotingKeystoneBatchMemo(
          bundleIndex: 0,
          bundleCount: 1,
          displayMemo: _votingDisplayMemo(
            amount: '13.00000000',
            round: 'R' * 414,
          ),
        ),
      ],
    );

    _expectFullyPainted(tester, 'Amount: 13.00000000 ZEC.');
    expect(tester.takeException(), isNull);
  });
}

/// Builds the memo string `zcash_voting`'s `display_memo()` produces: a fixed
/// sentence, then the per-bundle amount on a second line after a `\n`.
String _votingDisplayMemo({
  required String amount,
  String round = 'NU7 Scope',
}) {
  return 'I am authorizing this hotkey managed by my wallet to vote on '
      '$round.\nAmount: $amount ZEC.';
}

/// Fails when [text] is on screen as a widget but clipped by its own
/// `maxLines`.
///
/// `find.text` matches the widget's string, not the glyphs the paragraph
/// paints, so a clamped `Text` satisfies it while the user sees nothing. That
/// is how the dropped voting amount reached a release. Measure the paragraph
/// against an unclamped layout of the same string instead.
void _expectFullyPainted(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: '"$text" is not on screen');

  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final unclamped = TextPainter(
    text: TextSpan(text: text, style: paragraph.text.style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: paragraph.size.width);

  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(unclamped.height),
    reason:
        '"$text" is clipped: the paragraph paints '
        '${paragraph.size.height}px of ${unclamped.height}px',
  );
}

Future<void> _pumpSigningScreen(
  WidgetTester tester, {
  Future<void> Function(List<int>)? onSigned,
  bool interactiveScanner = false,
  Size viewport = const Size(393, 852),
  List<VotingKeystoneBatchMemo>? memos,
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
              batchMemos:
                  memos ??
                  [
                    VotingKeystoneBatchMemo(
                      bundleIndex: 0,
                      bundleCount: 3,
                      displayMemo: _votingDisplayMemo(amount: '1.25000000'),
                    ),
                    VotingKeystoneBatchMemo(
                      bundleIndex: 1,
                      bundleCount: 3,
                      displayMemo: _votingDisplayMemo(amount: '0.75000000'),
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
