/// Create-flow step ordering for the steps-nav progress track:
/// welcome -> intro -> address types -> things to know -> secret passphrase ->
/// passcode -> customise account. Welcome itself does not
/// show the track, but the following steps still count it so create progress
/// starts after the user has already passed the first screen. Biometrics is a
/// terminal completion screen and keeps its full progress value.
const kMobileCreateStepCount = 7;

/// Import-flow steps after method selection:
/// secret passphrase entry (paste or manual) -> review -> birthday -> passcode
/// -> customise account.
const kMobileImportStepCount = 5;

/// Initial fill shared by the import/hardware choices and create Introduction.
const kMobileSelectionProgress = 60 / 196;

/// Track fill for step N. Denominator is one past the step count so the
/// track is never empty on the first step nor full while the last step is
/// still in progress.
double mobileCreateProgress(int step) => step / (kMobileCreateStepCount + 1);

/// Fill the remaining track after selection, reserving full progress for
/// terminal completion.
double mobileImportProgress(int step) =>
    kMobileSelectionProgress +
    (1 - kMobileSelectionProgress) * step / (kMobileImportStepCount + 1);

/// Keystone owns its own literal progress values today (0.2/0.4/0.6/0.8).
/// Keep its passcode step on the previous 5/6 fill while create progress
/// counts Welcome and the education screens.
const kMobileKeystonePasscodeProgress = 5 / 6;
const kMobileKeystoneCustomiseProgress = 6 / 7;

/// Desktop-link import has intro, scan, account selection, contact selection,
/// then passcode.
const kMobileWalletLinkPasscodeProgress = 5 / 6;

/// Ledger: connect, birthday, passcode, then account customisation.
const kMobileLedgerPasscodeProgress = 0.75;
const kMobileLedgerCustomiseProgress = 0.875;
