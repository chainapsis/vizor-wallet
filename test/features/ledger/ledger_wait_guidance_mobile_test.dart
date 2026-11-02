@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';

import 'ledger_wait_guidance_test_support.dart';

void main() {
  registerLedgerWaitGuidanceTests();

  testWidgets('full wait guidance scrolls on a small screen with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var closes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        ],
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: MobileLedgerSigningSurface(
                  onBack: () => closes++,
                  canLeave: true,
                  child: LedgerSigningModal(
                    phase: LedgerSigningModalPhase.awaitingDevice,
                    signingStage: LedgerSigningStage.sending,
                    failure: null,
                    onCancel: () => closes++,
                    onFailureAction: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final instruction = find.text(kLedgerSigningWaitInstruction);
    expect(instruction, findsOneWidget);
    expect(tester.widget<Text>(instruction).maxLines, isNull);
    await tester.ensureVisible(find.text('Keep Ledger connected.'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keep Ledger connected.').hitTestable(), findsOneWidget);
    final close = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Close',
    );
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });
}
