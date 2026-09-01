/// Create-flow step ordering for the steps-nav progress track:
/// welcome -> method selection -> intro -> address types -> things to know ->
/// secret passphrase -> passcode -> customise account. Welcome itself does not
/// show the track, but the following steps still count it so create progress
/// starts after the user has already passed the first screen. Biometrics is a
/// terminal completion screen and keeps its full progress value.
const kMobileCreateStepCount = 8;

/// Import-flow step ordering:
/// secret passphrase entry (paste or manual) -> review -> birthday -> passcode
/// -> customise account.
const kMobileImportStepCount = 5;

/// Track fill for step N. Denominator is one past the step count so the
/// track is never empty on the first step nor full while the last step is
/// still in progress.
double mobileCreateProgress(int step) => step / (kMobileCreateStepCount + 1);

double mobileImportProgress(int step) => step / (kMobileImportStepCount + 1);

/// Keystone owns its own literal progress values today (0.2/0.4/0.6/0.8).
/// Keep its passcode step on the previous 5/6 fill while create progress
/// counts welcome and the shared method-selection screen.
const kMobileKeystonePasscodeProgress = 5 / 6;
const kMobileKeystoneCustomiseProgress = 6 / 7;

/// Desktop-link import has intro, scan, account selection, contact selection,
/// then passcode.
const kMobileWalletLinkPasscodeProgress = 5 / 6;

/// Ledger onboarding has connect, birthday, passcode (first account only),
/// then account customisation. The optional passcode step keeps additional
/// account setup shorter without changing the relative order of the screens.
const kMobileLedgerConnectProgress = 1 / 5;
const kMobileLedgerBirthdayProgress = 2 / 5;
const kMobileLedgerPasscodeProgress = 3 / 5;
const kMobileLedgerCustomiseProgress = 4 / 5;
