import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
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
  bool privateTransparentRecovery = false,
  Future<String> Function(rust_sync.TransactionInfo)? debugLookup,
}) async {
  await tester.binding.setSurfaceSize(const Size(1512, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prioritized = <String>[];
  final router = GoRouter(
    initialLocation: '/activity/tx/$transparentDetailsTxid',
    routes: [
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => ActivityTransactionStatusScreen(
          args: ActivityTransactionStatusArgs(
            txidHex: transparentDetailsTxid,
            txKind: 'sent',
            initialTransaction: transparentSend(),
          ),
          historyLoader: (_) async => [transparentSend()],
          detailLoader: details.load,
          transparentDetailsPrioritizer: (txid) async => prioritized.add(txid),
          transparentDetailsDebugLookup: debugLookup,
          privateTransparentRecovery: privateTransparentRecovery,
        ),
      ),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        swapFeatureEnabledProvider.overrideWithValue(false),
        privacyModeProvider.overrideWith(PrivacyOff.new),
        enhancePirProvider.overrideWith(() => FakeEnhancePirNotifier(true)),
        appBootstrapProvider.overrideWithValue(transparentDetailsBootstrap()),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              percentage: 1,
            ),
          ),
        ),
        addressBookRepositoryProvider.overrideWithValue(EmptyAddressBook()),
        ownAccountAddressesProvider.overrideWith((ref) async => const {}),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return prioritized;
}

/// Disposes the screen, cancelling any poll.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('desktop receipt shows transparent recipients when available', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(
        rust_sync.TransparentDetailsState.available,
        recipients: transparentRecipients,
      ),
    ]);
    final prioritized = await _pump(tester, details);
    expect(
      find.byKey(const ValueKey('transparent_details_section')),
      findsOneWidget,
    );
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Your address'), findsOneWidget);
    expect(
      find.textContaining(truncatedAddress(transparentRecipientAddress)),
      findsOneWidget,
    );
    expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
    expect(prioritized, isEmpty, reason: 'available details are not prioritized');
    await _close(tester);
  });

  for (final state in [
    rust_sync.TransparentDetailsState.pending,
    rust_sync.TransparentDetailsState.unavailable,
  ]) {
    testWidgets('desktop receipt shows the unavailable notice when $state', (
      tester,
    ) async {
      final details = ScriptedDetails([transparentDetail(state)]);
      final prioritized = await _pump(tester, details);
      expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
      expect(prioritized, [
        transparentDetailsTxid,
      ], reason: 'asked once on open');
      await _close(tester);
    });
  }

  testWidgets('desktop receipt says not covered in private mode', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.notCovered),
    ]);
    final prioritized = await _pump(tester, details);
    expect(find.text(kTransparentDetailsNotCoveredText), findsOneWidget);
    expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
    expect(prioritized, isEmpty);
    final before = details.calls;
    await tester.pump(kTransparentDetailsPollInterval * 3);
    expect(details.calls, before, reason: 'nothing to wait for');
    await _close(tester);
  });

  testWidgets('desktop receipt polls while pending and stops once available', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.pending),
      transparentDetail(rust_sync.TransparentDetailsState.unavailable),
      transparentDetail(
        rust_sync.TransparentDetailsState.available,
        recipients: transparentRecipients,
      ),
    ]);
    final prioritized = await _pump(tester, details);
    expect(details.calls, 1);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval);
    await tester.pump();
    expect(details.calls, 2);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval);
    await tester.pump();
    expect(details.calls, 3);
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
    await tester.pump(kTransparentDetailsPollInterval * 4);
    expect(details.calls, 3, reason: 'polling stopped');
    expect(prioritized, [transparentDetailsTxid]);
    await _close(tester);
  });

  testWidgets('desktop dev builds offer a private lookup that stores nothing', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.unavailable),
    ]);
    await _pump(
      tester,
      details,
      privateTransparentRecovery: true,
      debugLookup: (_) async => '1 outputs · 2 private queries',
    );
    final button = find.byKey(
      const ValueKey('transparent_details_debug_lookup'),
    );
    expect(button, findsOneWidget);
    await tester.tap(find.text('Look up'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 outputs · 2 private queries'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('desktop default builds offer no private lookup', (tester) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.unavailable),
    ]);
    await _pump(tester, details);
    expect(
      find.byKey(const ValueKey('transparent_details_debug_lookup')),
      findsNothing,
    );
    await _close(tester);
  });
}
