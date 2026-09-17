import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_progress_status.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;

class _ScanningBle extends fixture.FakeBle {
  final updates = StreamController<LedgerDiscoveryUpdate>();
  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => updates.stream;
}

void main() {
  for (final select in [false, true]) {
    testWidgets(
      'scan remains active and ${select ? 'allows selection' : 'becomes a retry action only on completion'}',
      (tester) async {
        final ble = _ScanningBle();
        final accounts = fixture.FakeAccounts();
        final container = fixture.containerFor(ble, accounts);
        addTearDown(container.dispose);
        addTearDown(ble.updates.close);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: AppTheme(
                data: AppThemeData.light,
                child: Center(
                  child: LedgerAccessRecoveryModal(
                    account: fixture.account,
                    pairingRecovery: true,
                    onRetry: () {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Try again'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Searching nearby…'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Searching'), findsNothing);
        expect(find.text('Search again'), findsNothing);
        expect(tester.hasRunningAnimations, isTrue);
        ble.updates.add(const LedgerDevicesDiscovered([fixture.device]));
        await tester.pump();
        expect(find.text('Still searching nearby…'), findsOneWidget);
        if (select) {
          await tester.tap(find.text('Ledger Flex'));
          await tester.pumpAndSettle();
          expect(find.text('Your Ledger is connected'), findsOneWidget);
          expect(accounts.writes, 1);
        } else {
          ble.updates.add(const LedgerDiscoveryEnded());
          await tester.pumpAndSettle();
          expect(find.text('Still searching nearby…'), findsNothing);
          expect(
            find.widgetWithText(AppButton, 'Search again'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('progress announces status and respects reduced motion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AppTheme(
            data: AppThemeData.light,
            child: const LedgerProgressStatus(label: 'Saving connection…'),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Saving connection…'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(AppButton), findsNothing);
    semantics.dispose();
  });
}
