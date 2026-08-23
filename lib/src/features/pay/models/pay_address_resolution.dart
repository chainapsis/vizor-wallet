import '../../../core/naming/ens_chains.dart';
import '../../../core/naming/ens_name.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../swap/models/swap_models.dart';

/// True when [network] is both EVM and a chain Vizor can actually resolve
/// ENS names against (see [chainSupportsEnsNames]). `null` (unrecognized
/// chain ticker) and non-resolvable EVM chains both resolve to false.
bool payChainSupportsEns(AddressBookNetwork? network) =>
    chainSupportsEnsNames(network);

/// The address-format error to surface on the pay recipient field for
/// [network], shared by the desktop and mobile pay wizards.
///
/// A resolve failure recorded on [SwapState.destinationResolveStatus] (from
/// `SwapNotifier.submitDestinationAddress`) always wins. Otherwise, a
/// syntactically valid `.eth` name on a chain Vizor can resolve names
/// against is never a format error while typing — resolution happens only
/// on submit — so the raw [SwapState.destinationAddressFormatError] is
/// suppressed for it. Every other input, including a `.eth` name on a chain
/// without name support, keeps the underlying address-format check.
String? payEffectiveAddressError(SwapState state, AddressBookNetwork? network) {
  if (state.destinationResolveStatus == SwapDestinationResolveStatus.failed) {
    return state.destinationResolveError;
  }
  final typed = state.destinationText.trim();
  if (isEnsName(typed) && payChainSupportsEns(network)) return null;
  return state.destinationAddressFormatError;
}
