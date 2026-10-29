import '../../../main.dart' show log;
import 'zns_name_resolver.dart';

/// Why a Zcash name in the send recipient field has no usable address yet.
///
/// Desktop and mobile send show the same [message] under the field. Each
/// message fits one line beside the status icon at phone width.
enum ZnsLookupStatus {
  /// The lookup is in flight.
  resolving('Looking up name'),

  /// The resolver has no live registration for the name.
  notRegistered('This name is not registered'),

  /// The wallet's network has no ZNS registry (regtest).
  unsupportedNetwork("Names aren't available on this network"),

  /// No resolver answered, or its reply could not be read.
  failed("Couldn't reach the name service"),

  /// The name points to an address this wallet cannot pay.
  unusableAddress('This name points to an invalid address');

  const ZnsLookupStatus(this.message);

  final String message;

  /// True for every state that blocks review.
  bool get isError => this != resolving;

  /// The send screens' address type for this state: `'error'` when the
  /// lookup itself failed, `'invalid'` when it answered with no usable
  /// address, and empty while it runs.
  String get addressType => switch (this) {
    resolving => '',
    failed => 'error',
    notRegistered || unsupportedNetwork || unusableAddress => 'invalid',
  };
}

/// How long a name field waits after the last edit before it looks the
/// name up. Editing inside `alice.zcash` would otherwise send each partial
/// name to the resolver, one request per keystroke.
const kZnsLookupDebounce = Duration(milliseconds: 350);

/// What a name lookup produced for the send recipient field.
sealed class ZnsRecipientLookup {
  const ZnsRecipientLookup();
}

final class ZnsRecipientFound extends ZnsRecipientLookup {
  const ZnsRecipientFound(this.resolution);

  final ZnsResolution resolution;
}

final class ZnsRecipientMissing extends ZnsRecipientLookup {
  const ZnsRecipientMissing(this.status);

  final ZnsLookupStatus status;
}

/// Looks up bare name [name] with [resolver], which is null where the network
/// has no registry. Never throws: every failure becomes a
/// [ZnsRecipientMissing] status for the field to show.
Future<ZnsRecipientLookup> lookUpZnsRecipient(
  ZnsNameResolver? resolver,
  String name,
) async {
  if (resolver == null) {
    return const ZnsRecipientMissing(ZnsLookupStatus.unsupportedNetwork);
  }
  try {
    final resolution = await resolver.resolve(name);
    return resolution == null
        ? const ZnsRecipientMissing(ZnsLookupStatus.notRegistered)
        : ZnsRecipientFound(resolution);
  } catch (e) {
    log('ZNS: lookup error: $e');
    return const ZnsRecipientMissing(ZnsLookupStatus.failed);
  }
}

/// The Zcash name state of one send recipient field.
///
/// The screen owns the field text and calls these methods inside `setState`.
/// A resolution counts only while the field still holds the text it was
/// resolved from, so a late or stale answer can never redirect a payment.
class ZnsRecipientState {
  ZnsRecipientState({String? carriedName}) : _carriedName = carriedName;

  ({String input, ZnsResolution resolution})? _resolved;

  /// A name an earlier send step resolved, carried for display while the
  /// field already holds its address.
  String? _carriedName;

  ZnsLookupStatus? _status;

  /// Why the name in the field has no usable address yet, or null.
  ZnsLookupStatus? get status => _status;

  /// The field moved on: forget the lookup and any carried name.
  void reset() {
    clearLookup();
    _carriedName = null;
  }

  /// Forget the lookup, keeping a carried name.
  void clearLookup() {
    _resolved = null;
    _status = null;
  }

  void begin() {
    _resolved = null;
    _status = ZnsLookupStatus.resolving;
  }

  void fail(ZnsLookupStatus status) {
    _resolved = null;
    _status = status;
  }

  /// Settles a validation pass of field text [input]. [resolution] is the
  /// name's registration, or null when [input] was not a name.
  /// [addressValid] is the wallet's verdict on the address that was checked.
  void settle(
    String input,
    ZnsResolution? resolution, {
    required bool addressValid,
  }) {
    if (resolution == null) {
      clearLookup();
    } else if (addressValid) {
      _resolved = (input: input.trim(), resolution: resolution);
      _status = null;
    } else {
      fail(ZnsLookupStatus.unusableAddress);
    }
  }

  /// The resolution for [fieldText], or null if the field holds other text.
  ZnsResolution? resolutionFor(String fieldText) {
    final resolved = _resolved;
    if (resolved == null || resolved.input != fieldText.trim()) return null;
    return resolved.resolution;
  }

  /// The address a send with recipient [fieldText] pays.
  String paymentAddress(String fieldText) =>
      resolutionFor(fieldText)?.address ?? fieldText.trim();

  /// The Zcash name the recipient was entered as, for display.
  String? displayName(String fieldText) =>
      resolutionFor(fieldText)?.displayName ?? _carriedName;
}
