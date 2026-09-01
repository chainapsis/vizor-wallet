import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/widgetbook/ledger_use_cases.dart';

void main() {
  test('Ledger folder keeps its playgrounds separate from generic screens', () {
    final folder = buildLedgerWidgetbookFolder();

    expect(folder.name, 'Ledger');
    expect(
      folder.children!.map((child) => child.name),
      containsAll([
        'Onboarding & import',
        'Accounts',
        'Signing',
        'Mobile device picker',
        'Voting',
      ]),
    );
    expect(
      folder.leaves.map((leaf) => leaf.name),
      containsAll([
        'Desktop',
        'Mobile',
        'Mainnet',
        'Interactive',
        'Playground',
        'Devices found',
        'Empty',
        'Permission denied',
      ]),
    );
  });

  testWidgets('signing preview exposes multi-transaction Ledger review', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerSigningPreview(
        phase: LedgerSigningModalPhase.awaitingDevice,
        roundNumber: 2,
        roundCount: 3,
      ),
    );

    expect(find.text('Review Transaction 2 of 3 on your Ledger'), findsOne);
    expect(find.text('Waiting for approval · 2 of 3'), findsOne);
    expect(find.text('Zcash · Ledger'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing preview exposes failed readiness guidance', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerSigningPreview(
        phase: LedgerSigningModalPhase.failed,
        readiness: LedgerSigningPlaygroundReadiness.failed,
      ),
    );

    expect(find.text('Ledger needs attention'), findsOne);
    expect(find.text('Action needed'), findsOne);
    expect(
      find.text('Reconnect your Ledger and open the Zcash app.'),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing transport choices update only the preview account', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerSigningPreview(phase: LedgerSigningModalPhase.failed),
    );

    final usb = find.byKey(const ValueKey('ledger_connection_usb'));
    expect(tester.widget<AppButton>(usb).variant, AppButtonVariant.secondary);

    await tester.tap(usb);
    await tester.pump();

    expect(tester.widget<AppButton>(usb).variant, AppButtonVariant.primary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device picker previews found, empty, and denied states', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildLedgerDevicePickerFoundUseCase);
    await _pumpAsyncState(tester);
    expect(find.text('Ledger Flex'), findsWidgets);
    expect(find.text('Ledger Stax'), findsWidgets);

    await _pumpUseCase(tester, buildLedgerDevicePickerEmptyUseCase);
    await _pumpAsyncState(tester);
    expect(find.text('No Ledger devices found'), findsOne);
    expect(find.text('Try again'), findsOne);

    await _pumpUseCase(tester, buildLedgerDevicePickerPermissionDeniedUseCase);
    await _pumpAsyncState(tester);
    expect(find.text('Could not find your Ledger'), findsOne);
    expect(find.textContaining('Bluetooth permission is required'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voting preview advances through Ledger submission states', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerVotingPreview(
        bundleNumber: 2,
        bundleCount: 3,
        displayMemo: 'Round 7 delegation memo',
      ),
    );

    expect(find.text('Approve voting delegation'), findsOne);
    expect(find.text('Bundle 2 of 3'), findsOne);
    expect(find.text('Round 7 delegation memo'), findsOne);
    expect(find.byKey(const ValueKey('ledger_voting_signing_panel')), findsOne);
    expect(find.text('Checking your Ledger'), findsOne);
    expect(find.text('Signing with Keystone'), findsNothing);
    expect(find.text('Signing with Ledger'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Waiting for Ledger approval'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Bundle 3 of 3'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ledger_voting_signing_panel')),
      findsNothing,
    );
    expect(find.text('Advance to vote submission'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('1 of 2 ballots submitted'), findsOne);
    expect(find.text('Advance to finalizing'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Complete preview'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Restart preview'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ledger_voting_cancel')));
    await tester.pump();
    expect(find.text('Ledger voting approval was cancelled.'), findsOne);
    expect(find.text('Retry'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account details and rename previews use production surfaces', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildLedgerAccountDetailsUseCase);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Account details'), findsOne);
    expect(find.text('Ledger account 1'), findsWidgets);
    expect(find.text('ZIP-32 account index'), findsOne);
    expect(find.text('2870000'), findsOne);

    await _pumpUseCase(tester, buildLedgerRenameUseCase);
    expect(find.text('Rename group name'), findsOne);
    expect(find.text('Group name'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile account details preview uses the mobile surface', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileLedgerAccountDetailsUseCase);
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Account Details'), findsOne);
    expect(find.text('Ledger account 1'), findsOne);
    expect(find.text('Wallet birthday height'), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAsyncState(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
      home: Builder(builder: builder),
    ),
  );
  await tester.pump();
}
