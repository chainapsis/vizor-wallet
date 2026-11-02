import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void registerLedgerWaitGuidanceTests() {
  for (final model in <String?>['stax', 'nanoX', null]) {
    testWidgets('sending guidance is the same for model $model', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = kAppFormFactor == AppFormFactor.mobile
          ? const Size(393, 852)
          : const Size(1080, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_Account.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: const Center(
                child: LedgerSigningModal(
                  accountUuid: 'ledger',
                  phase: LedgerSigningModalPhase.awaitingDevice,
                  failure: null,
                  onCancel: null,
                  onFailureAction: null,
                ),
              ),
            ),
          ),
        ),
      );
      final report = container
          .read(ledgerSigningProgressProvider.notifier)
          .begin('ledger');
      report('sending', deviceModel: model);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(kLedgerSigningWaitInstruction), findsOneWidget);
      expect(find.text('Keep Ledger connected.'), findsOneWidget);
      expect(find.text('Sign transaction'), findsOneWidget);
      expect(tester.takeException(), isNull);

      report('reviewing');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('When prompted, check the amount and recipient on Ledger.'),
        findsOneWidget,
      );
      expect(find.textContaining('seconds'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.loader,
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.text(
                'When prompted, check the amount and recipient on Ledger.',
              ),
            )
            .style
            ?.fontWeight,
        AppTypography.bodyMediumStrong.fontWeight,
      );
      report('finishing');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Finishing the Ledger request.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.loader,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('seconds'), findsNothing);

      container.read(ledgerSigningProgressProvider.notifier).begin('other')(
        'sending',
        deviceModel: 'flex',
      );
      await tester.pump();
      expect(find.text('Prepare transaction'), findsOneWidget);
      expect(find.textContaining('seconds'), findsNothing);
    });
  }
}

class _Account extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'ledger',
        name: 'Ledger',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
        ledgerDeviceId: 'old-flex',
        ledgerDeviceName: 'Ledger Flex',
        ledgerDeviceModel: 'Ledger Flex',
      ),
    ],
    activeAccountUuid: 'ledger',
  );
}
