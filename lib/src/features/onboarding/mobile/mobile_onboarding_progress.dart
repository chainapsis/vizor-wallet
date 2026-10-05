/// Account preparation progress, separate from QR decoding and wallet sync.
enum OnboardingFlow { create, importWallet, keystone, ledger, walletLink, gift }

enum OnboardingSetupMode { createPasscode, reusePasscode }

enum OnboardingStage {
  addressTypes,
  thingsToKnow,
  secretPassphrase,
  phraseEntry,
  phraseReview,
  deviceIntro,
  deviceScan,
  deviceConnect,
  linkIntro,
  linkScan,
  accountSelection,
  contactSelection,
  birthday,
  passcode,
  customiseAccount,
}

/// A semantic position supplied to shared screens; only renderers use [value].
class OnboardingProgressPosition {
  const OnboardingProgressPosition._(this.value);
  static const start = OnboardingProgressPosition._(60 / 196);
  static const accountReady = OnboardingProgressPosition._(1);
  final double value;
}

/// Immutable, deterministic plan for one account-preparation path.
class OnboardingProgressPlan {
  OnboardingProgressPlan.forFlow(this.flow, {required this.setupMode})
    : stages = List.unmodifiable([
        for (final stage in _stagesFor(flow))
          if (setupMode == OnboardingSetupMode.createPasscode ||
              stage != OnboardingStage.passcode)
            stage,
      ]);

  final OnboardingFlow flow;
  final OnboardingSetupMode setupMode;
  final List<OnboardingStage> stages;

  OnboardingProgressPosition at(OnboardingStage stage) {
    final index = stages.indexOf(stage);
    if (index < 0) {
      throw ArgumentError.value(stage, 'stage', 'Not in $flow / $setupMode');
    }
    final start = OnboardingProgressPosition.start.value;
    return OnboardingProgressPosition._(
      start + (1 - start) * (index + 1) / (stages.length + 1),
    );
  }

  static List<OnboardingStage> _stagesFor(OnboardingFlow flow) =>
      switch (flow) {
        OnboardingFlow.gift => const [
          OnboardingStage.passcode,
          OnboardingStage.customiseAccount,
        ],
        OnboardingFlow.create => const [
          OnboardingStage.addressTypes,
          OnboardingStage.thingsToKnow,
          OnboardingStage.secretPassphrase,
          OnboardingStage.passcode,
          OnboardingStage.customiseAccount,
        ],
        OnboardingFlow.importWallet => const [
          OnboardingStage.phraseEntry,
          OnboardingStage.phraseReview,
          OnboardingStage.birthday,
          OnboardingStage.passcode,
          OnboardingStage.customiseAccount,
        ],
        OnboardingFlow.keystone => const [
          OnboardingStage.deviceIntro,
          OnboardingStage.deviceScan,
          OnboardingStage.accountSelection,
          OnboardingStage.birthday,
          OnboardingStage.passcode,
          OnboardingStage.customiseAccount,
        ],
        OnboardingFlow.ledger => const [
          OnboardingStage.deviceConnect,
          OnboardingStage.birthday,
          OnboardingStage.passcode,
          OnboardingStage.customiseAccount,
        ],
        OnboardingFlow.walletLink => const [
          OnboardingStage.linkIntro,
          OnboardingStage.linkScan,
          OnboardingStage.accountSelection,
          OnboardingStage.contactSelection,
          OnboardingStage.passcode,
        ],
      };
}
