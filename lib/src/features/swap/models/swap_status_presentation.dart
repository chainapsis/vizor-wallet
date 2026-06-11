import '../../address_book/models/address_book_contact.dart';

enum SwapStatusBadgeKind { liveQuote, completed, warning, failed }

enum SwapStatusTab { progress, details }

enum SwapStatusStepState { complete, active, pending }

class SwapStatusStepData {
  const SwapStatusStepData({
    required this.title,
    required this.state,
    this.completeTitle,
    this.activeTitle,
    this.pendingTitle,
    this.lastCheckedLabel,
    this.description,
  });

  final String title;
  final SwapStatusStepState state;
  final String? completeTitle;
  final String? activeTitle;
  final String? pendingTitle;
  final String? lastCheckedLabel;
  final String? description;

  String titleForState(SwapStatusStepState state) {
    return switch (state) {
      SwapStatusStepState.complete => completeTitle ?? title,
      SwapStatusStepState.active => activeTitle ?? title,
      SwapStatusStepState.pending => pendingTitle ?? title,
    };
  }

  SwapStatusStepData copyWithState(SwapStatusStepState state) {
    return SwapStatusStepData(
      title: title,
      state: state,
      completeTitle: completeTitle,
      activeTitle: activeTitle,
      pendingTitle: pendingTitle,
      lastCheckedLabel: lastCheckedLabel,
      description: description,
    );
  }
}

class SwapStatusDetailRowData {
  const SwapStatusDetailRowData({
    required this.label,
    required this.value,
    this.copyable = false,
    this.copyText,
    this.help = false,
    this.helpTooltip,
    this.linkUri,
    this.accountProfilePictureId,
    this.addressBookLabel,
    this.addressNetwork,
  });

  final String label;
  final String value;
  final bool copyable;
  final String? copyText;
  final bool help;
  final String? helpTooltip;

  /// External link opened when the row's trailing arrow is tapped (e.g. the
  /// completed swap's deposit tx row linking to the NEAR Intents explorer).
  final Uri? linkUri;
  final String? accountProfilePictureId;

  /// When this row is an address that matches a saved address-book contact,
  /// the contact's nickname. Renders as a matched-contact identity cell
  /// (nickname + saved mark above the network + address).
  final String? addressBookLabel;

  /// The contact's network, used to draw the chain chip on the address line.
  /// Only set when [addressBookLabel] is non-null.
  final AddressBookNetwork? addressNetwork;
}
