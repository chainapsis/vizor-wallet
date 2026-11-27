import 'delegate_mode_models.dart';
import 'proxy_delegation_models.dart';

/// Confirms the user's presence with the app's re-auth before a delegate
/// key signs; resolves true once the user confirmed.
typedef DelegateReauthCheck = Future<bool> Function();

/// The delegate-mode screens' only data source.
///
/// Delegate mode is app-level: the device holds one delegate key and one
/// registry entry, kept in app secure storage, not under a wallet account.
/// `composite_delegate_mode_repository.dart` implements it over the
/// zcash_voting delegate APIs, the attester API (contracts-v1 section 12.4)
/// and Vizor's participation reader.
///
/// Screens re-authenticate before [exportKey]. Signing ([register],
/// [submitBallot] and [retire]) asks the re-auth it is given right before it
/// reads the key, so nothing is asked when nothing new is signed.
abstract interface class DelegateModeRepository {
  /// The device's delegate key and its entry.
  Future<DelegateModeView> status();

  /// Creates the device's delegate key and stores it.
  Future<DelegateKeyInfo> createKey();

  /// Stores the key a typed, pasted or scanned `zvdsk1…` export holds as
  /// the device's, without a network request: the next [status] read finds
  /// its registry entry by key.
  ///
  /// Throws [DelegateKeyImportException] when [text] is not an export.
  Future<DelegateKeyInfo> importKey(String text);

  /// The device's key as its `zvdsk1…` export, to back up or move to
  /// another device. Callers re-authenticate first.
  Future<String> exportKey();

  /// Forgets the device's key and its pending register op in one write,
  /// then deletes its secret, so another key can be created or imported.
  /// Refused while the key's proven entry is live. Without a proven entry,
  /// callers first show the key's export and have the user confirm it is
  /// saved: a registration that still lands needs the key to ballot or
  /// retire.
  Future<void> startOver();

  /// The marker [key] is posted with (contracts-v1 section 11.5).
  Future<String> markerText(DelegateKeyInfo key);

  /// Asks the attester to attest [key] from the post at [proofUrl].
  ///
  /// Throws [DelegateVerifierRefusal] for every attester error, and
  /// [DelegateModeException] with [DelegateModeErrorKind.unavailable] when
  /// no attester answered.
  Future<DelegateAttestation> attest({
    required ProxyDelegateProvider provider,
    required String proofUrl,
    required DelegateKeyInfo key,
  });

  /// Signs REGISTER with the attested key after [reauth] and submits it on
  /// chain once.
  Future<DelegateRegisterResult> register(
    DelegateAttestation attestation, {
    required DelegateReauthCheck reauth,
  });

  /// Proxy rounds the delegate can act in, newest first.
  Future<List<DelegateRound>> rounds();

  /// One round.
  Future<DelegateRound> round(String roundId);

  /// Compares [options] with any ballot already on chain for the round.
  Future<ApiBallotPreflight> preflight(String roundId, List<int> options);

  /// Signs the round's one ballot with the entry's key after [reauth] and
  /// submits it once. A retry passes the stored ballot's options and
  /// resubmits it unchanged, without [reauth], since nothing new is signed.
  /// [onSigned] runs once the ballot is signed and stored, before it is
  /// posted.
  ///
  /// Throws [DelegateBallotStoredException] when the signed ballot is
  /// stored but no verdict arrives; it then stays stored for
  /// [resendStoredBallot].
  Future<ApiBallotSubmitResult> submitBallot(
    String roundId,
    List<int> options, {
    required DelegateReauthCheck reauth,
    void Function()? onSigned,
  });

  /// Posts the ballot this device signed for [roundId] once more, byte for
  /// byte and without re-auth, while the round's whole ballot list does not
  /// show the entry's ballot. Posts nothing when none is stored, the list
  /// shows this ballot, the entry is retired or the round is no longer
  /// ACTIVE ([DelegateBallotResend.done]); after voting ends the chain
  /// answers code 4, which ends the resends too. A different listed ballot comes back as
  /// its code 57 rejection. While the entry is suspended, as its
  /// proof or the chain's answer says, it reports
  /// [DelegateBallotResend.blocked].
  ///
  /// Throws [DelegateModeException] with
  /// [DelegateModeErrorKind.unavailable] when no answer arrives.
  Future<DelegateBallotResend> resendStoredBallot(String roundId);

  /// The ids of the ACTIVE rounds holding a ballot this device signed, so
  /// resends resume after a restart, and whether every round could be read.
  /// Without a registered key on the device it reads nothing over the
  /// network.
  Future<DelegateStoredBallotRounds> storedBallotRounds();

  /// Signs RETIRE with the entry's key after [reauth] and submits it. The
  /// entry is retired once the chain says so or its proof shows it.
  Future<DelegateRetireResult> retire({required DelegateReauthCheck reauth});
}

/// Text that is not a delegate key's `zvdsk1…` export.
class DelegateKeyImportException implements Exception {
  /// Creates the exception.
  const DelegateKeyImportException();

  @override
  String toString() => 'DelegateKeyImportException';
}

/// Failure kinds the delegate-mode screens tell apart.
enum DelegateModeErrorKind {
  /// The trust anchor no longer verifies the chain.
  cannotVerify,

  /// The voting chain or the storage did not answer.
  unavailable,

  /// The user dismissed the re-auth, so nothing was signed. Screens return
  /// to where they were without an error.
  cancelled,

  /// Any other failure.
  other,
}

/// A delegate-mode failure the screens can explain.
class DelegateModeException implements Exception {
  /// Creates the exception.
  const DelegateModeException(this.kind, [this.detail]);

  /// What failed.
  final DelegateModeErrorKind kind;

  /// Diagnostic text; never shown.
  final String? detail;

  @override
  String toString() =>
      'DelegateModeException($kind${detail == null ? '' : ': $detail'})';
}

/// A ballot that is signed and stored on this device but has no verdict
/// yet. The screens show it as submitted, and
/// [DelegateModeRepository.resendStoredBallot] sends it again.
class DelegateBallotStoredException extends DelegateModeException {
  /// Creates the exception.
  const DelegateBallotStoredException([String? detail])
    : super(DelegateModeErrorKind.unavailable, detail);
}
