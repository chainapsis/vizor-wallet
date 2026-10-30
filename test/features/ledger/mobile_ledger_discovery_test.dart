@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_pairing_session.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;
import '../../support/ledger_discovery_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'mobile picker connects and releases quiet discovery ($platform)',
      (tester) async {
        final native = LedgerDiscoveryChannel();
        LedgerBleDevice? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: MobileLedgerDeviceSheet(
                service: native.service,
                onSelected: (d) => selected = d,
                onClose: () {},
              ),
            ),
          ),
        );
        await pumpLedgerDiscovery(tester);
        await native.devices();
        await pumpLedgerDiscovery(tester);
        await tester.tap(find.text('Ledger Stax · A37E'));
        await pumpLedgerDiscovery(tester);
        expect(selected?.id, 'stax');
        expect(native.calls.where((e) => e == 'connect'), hasLength(1));
        expect(native.eventCalls.where((e) => e == 'cancel'), hasLength(1));
        await native.emit(null);
        await pumpLedgerDiscovery(tester);
        expect(native.eventCalls.where((e) => e == 'cancel'), hasLength(1));
        await tester.pumpWidget(const SizedBox());
        await pumpLedgerDiscovery(tester);
        await tester.runAsync(native.dispose);
      },
      variant: TargetPlatformVariant({platform}),
    );
    testWidgets(
      'shared mobile signing picker connects and releases its discovery listener ($platform)',
      (tester) async {
        final native = LedgerDiscoveryChannel();
        final pairingKey = GlobalKey<LedgerPairingSessionState>();
        final container = ProviderContainer(
          overrides: [
            ledgerMobileBleServiceProvider.overrideWithValue(native.service),
            accountProvider.overrideWith(fixture.FakeAccounts.new),
            appSecurityProvider.overrideWith(fixture.FakeSecurity.new),
            ledgerTargetPlatformProvider.overrideWithValue(platform),
            ledgerRustOperationCancellerProvider.overrideWithValue(() async {}),
          ],
        );
        final request = LedgerDeviceSelectionRequest(
          accountUuid: 'a',
          check: () {},
          prepareDiscovery: () async {},
          verify: (d, _, _) async {
            await native.service.connect(d);
            return false;
          },
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: LedgerPairingSession(
                key: pairingKey,
                accountUuid: 'a',
                selectionRequest: request,
                onRetry: () {},
                onClose: () {},
                onBusyChanged: (_) {},
                builder: (_, s) => Text(s.stage.name),
              ),
            ),
          ),
        );
        await pumpLedgerDiscovery(tester);
        await native.devices();
        await pumpLedgerDiscovery(tester);
        await pairingKey.currentState!.select(
          const LedgerBleDevice(id: 'stax', name: 'A37E', model: 'Ledger Stax'),
        );
        await pumpLedgerDiscovery(tester);
        expect((await request.result).device?.id, 'stax');
        expect(native.calls.where((e) => e == 'connect'), hasLength(1));
        expect(native.eventCalls.where((e) => e == 'cancel'), hasLength(1));
        await native.emit(null);
        await pumpLedgerDiscovery(tester);
        expect(native.eventCalls.where((e) => e == 'cancel'), hasLength(1));
        await tester.pumpWidget(const SizedBox());
        await pumpLedgerDiscovery(tester);
        container.dispose();
        await tester.runAsync(native.dispose);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}
