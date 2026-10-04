@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';

void main() {
  const expected = {
    OnboardingFlow.gift: [
      OnboardingStage.passcode,
      OnboardingStage.customiseAccount,
    ],
    OnboardingFlow.create: [
      OnboardingStage.addressTypes,
      OnboardingStage.thingsToKnow,
      OnboardingStage.secretPassphrase,
      OnboardingStage.passcode,
      OnboardingStage.customiseAccount,
    ],
    OnboardingFlow.importWallet: [
      OnboardingStage.phraseEntry,
      OnboardingStage.phraseReview,
      OnboardingStage.birthday,
      OnboardingStage.passcode,
      OnboardingStage.customiseAccount,
    ],
    OnboardingFlow.keystone: [
      OnboardingStage.deviceIntro,
      OnboardingStage.deviceScan,
      OnboardingStage.accountSelection,
      OnboardingStage.birthday,
      OnboardingStage.passcode,
      OnboardingStage.customiseAccount,
    ],
    OnboardingFlow.ledger: [
      OnboardingStage.deviceConnect,
      OnboardingStage.birthday,
      OnboardingStage.passcode,
      OnboardingStage.customiseAccount,
    ],
    OnboardingFlow.walletLink: [
      OnboardingStage.linkIntro,
      OnboardingStage.linkScan,
      OnboardingStage.accountSelection,
      OnboardingStage.contactSelection,
      OnboardingStage.passcode,
    ],
  };

  test('shared entry and account-ready positions retain their meanings', () {
    expect(OnboardingProgressPosition.start.value, closeTo(60 / 196, 1e-10));
    expect(OnboardingProgressPosition.accountReady.value, 1);
  });

  for (final flow in OnboardingFlow.values) {
    for (final mode in OnboardingSetupMode.values) {
      test('$flow / $mode has only its intended stages and advances', () {
        final plan = OnboardingProgressPlan.forFlow(flow, setupMode: mode);
        final stages = expected[flow]!;
        expect(
          plan.stages,
          mode == OnboardingSetupMode.createPasscode
              ? stages
              : stages.where((s) => s != OnboardingStage.passcode).toList(),
        );
        var previous = OnboardingProgressPosition.start.value;
        for (final stage in plan.stages) {
          final value = plan.at(stage).value;
          expect(value, greaterThan(previous));
          expect(value, lessThan(1));
          previous = value;
        }
        expect(() => plan.stages.clear(), throwsUnsupportedError);
        if (mode == OnboardingSetupMode.reusePasscode) {
          expect(() => plan.at(OnboardingStage.passcode), throwsArgumentError);
        }
      });
    }
  }

  test(
    'software import retains approved fills; hardware advances past selection',
    () {
      final import = OnboardingProgressPlan.forFlow(
        OnboardingFlow.importWallet,
        setupMode: OnboardingSetupMode.createPasscode,
      );
      expect(
        import.at(OnboardingStage.phraseEntry).value,
        closeTo(0.42176870748, 1e-10),
      );
      expect(
        import.at(OnboardingStage.customiseAccount).value,
        closeTo(0.88435374150, 1e-10),
      );
      final ledger = OnboardingProgressPlan.forFlow(
        OnboardingFlow.ledger,
        setupMode: OnboardingSetupMode.reusePasscode,
      );
      expect(
        ledger.at(OnboardingStage.deviceConnect).value,
        closeTo(0.47959183673, 1e-10),
      );
      expect(() => import.at(OnboardingStage.deviceScan), throwsArgumentError);
    },
  );
}
