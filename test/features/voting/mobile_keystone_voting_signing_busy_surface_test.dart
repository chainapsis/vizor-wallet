@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import '../../support/payment_uri_busy_surface_expectations.dart';

/// The mobile voting signing screen replaces the status content while the
/// bundles are being signed, so its whole lifetime is a live Keystone session.
/// The hold sits above the flow, which is keyed per bundle — a hold inside the
/// flow would dip to zero between bundles.
void main() {
  testWidgets('the mobile voting signing screen holds the payment-URI busy '
      'latch', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: MobileKeystoneVotingSigningScreen(
        presentation: VotingKeystoneStatusPresentation(
          bundleIndex: 0,
          urParts: const [_previewVotingUr],
          batchMemos: const [
            VotingKeystoneBatchMemo(
              bundleIndex: 0,
              bundleCount: 1,
              displayMemo: 'Amount: 1.25 ZEC\nProposal: Community grants',
            ),
          ],
          batchMessageCount: 1,
          batchTotalCount: 1,
          onSigned: _noopSigned,
          onSkipRemainingBundles: _noop,
        ),
      ),
      drainExceptions: true,
      postUnmountSettle: const Duration(seconds: 2),
    );
  });
}

Widget Function(Widget) _host(ProviderContainer container) =>
    (child) => UncontrolledProviderScope(
      container: container,
      child: AppTheme(
        data: AppThemeData.dark,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

Future<void> _noopSigned(List<int> _) async {}
void _noop() {}

const _previewVotingUr =
    'ur:zcash-sign-batch/1-1/lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcx';
