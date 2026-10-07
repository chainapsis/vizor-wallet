@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_enhance_pir_notifier.dart';
import '../../fakes/fake_sync_notifier.dart';
import 'transparent_details_test_support.dart';

Future<List<String>> _pump(
  WidgetTester tester,
  ScriptedDetails details, {
  FakeSyncNotifier? sync,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prioritized = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        swapFeatureEnabledProvider.overrideWithValue(false),
        privacyModeProvider.overrideWith(PrivacyOff.new),
        enhancePirProvider.overrideWith(() => FakeEnhancePirNotifier(true)),
        appBootstrapProvider.overrideWithValue(transparentDetailsBootstrap()),
        syncProvider.overrideWith(
          () =>
              sync ??
              FakeSyncNotifier(
                SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
              ),
        ),
        addressBookRepositoryProvider.overrideWithValue(EmptyAddressBook()),
        ownAccountAddressesProvider.overrideWith((ref) async => const {}),
        giftCardActivityIndexProvider.overrideWith(
          (ref, _) async => GiftCardActivityIndex.empty,
        ),
      ],
      child: MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: MobileTransactionStatusScreen(
            args: MobileTransactionStatusArgs(
              txidHex: transparentDetailsTxid,
              txKind: 'sent',
              initialTransaction: transparentSend(),
            ),
            historyLoader: (_) async => [transparentSend()],
            detailLoader: details.load,
            transparentDetailsPrioritizer: (txid) async =>
                prioritized.add(txid),
            privateTransparentRecovery: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return prioritized;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  transparentDetailsRefreshTests(
    pump: (tester, details, sync) async {
      await _pump(tester, details, sync: sync);
    },
  );
  testWidgets('mobile receipt shows transparent recipients when available', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(
        rust_sync.TransparentDetailsState.available,
        recipients: transparentRecipients,
      ),
    ]);
    final prioritized = await _pump(tester, details);
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Your address'), findsOneWidget);
    expect(
      find.textContaining(truncatedAddress(transparentRecipientAddress)),
      findsWidgets,
    );
    expect(prioritized, isEmpty);
    await _close(tester);
  });

  testWidgets('mobile receipt shows the unavailable notice', (tester) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.unavailable),
    ]);
    final prioritized = await _pump(tester, details);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    expect(prioritized, [transparentDetailsTxid]);
    await _close(tester);
  });

  testWidgets('mobile receipt says not covered in private mode', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.notCovered),
    ]);
    await _pump(tester, details);
    expect(find.text(kTransparentDetailsNotCoveredText), findsOneWidget);
    await _close(tester);
  });

  testWidgets('mobile receipt polls while pending and stops once available', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.pending),
      transparentDetail(
        rust_sync.TransparentDetailsState.available,
        recipients: transparentRecipients,
      ),
    ]);
    await _pump(tester, details);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval);
    await tester.pump();
    expect(details.calls, 2);
    expect(find.text('Recipient'), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval * 4);
    expect(details.calls, 2, reason: 'polling stopped');
    await _close(tester);
  });
}
