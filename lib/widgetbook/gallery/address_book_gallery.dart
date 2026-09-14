// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/core/profile_pictures.dart';
import '../../src/features/address_book/models/address_book_contact.dart';
import '../address_book_use_cases.dart';
import '../address_scan_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';

/// The Address book gallery: one use case per surface, each knob dispatching
/// to the fixtures in `address_book_use_cases.dart` so every `build*UseCase`
/// keeps the name its tests bind to.
final List<WidgetbookNode> addressBookGalleryNodes = [
  WidgetbookComponent(
    name: 'Address book screen',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildAddressBookScreenGalleryCase,
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Network icon',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildAddressBookNetworkIconGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'All networks',
            builder: buildAddressBookNetworkIconGridUseCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Contact name inline',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildContactNameInlineGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Address book modals',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildAddressBookModalsGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Contact picker',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildAddressBookContactPickerGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Contact row menu',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildAddressBookRowMenuGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Address scan',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildAddressScanGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Camera error overlay',
            builder: buildMobileScanCameraErrorOverlayGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Viewfinder corners',
            builder: buildMobileScanViewfinderGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Address book modals ---------------------------------------------------

/// Desktop modals the pane fixture can raise over the contacts list.
enum AddressBookModalCase {
  addContact,
  editContact,
  avatarPicker,
  networkSelector,
  networkSearchEmpty,
  removeContact,
}

Widget buildAddressBookModalsGalleryCase(BuildContext context) {
  final modal = wbStateKnob<AddressBookModalCase>(
    context,
    label: 'Modal',
    options: AddressBookModalCase.values,
    labelBuilder: addressBookModalCaseLabel,
  );
  return switch (modal) {
    AddressBookModalCase.addContact => buildAddressBookAddContactModalUseCase(
      context,
    ),
    AddressBookModalCase.editContact => buildAddressBookEditContactModalUseCase(
      context,
    ),
    AddressBookModalCase.avatarPicker => buildAddressBookAvatarModalUseCase(
      context,
    ),
    AddressBookModalCase.networkSelector => buildAddressBookNetworkModalUseCase(
      context,
    ),
    AddressBookModalCase.networkSearchEmpty =>
      buildAddressBookNetworkModalEmptyUseCase(context),
    AddressBookModalCase.removeContact =>
      buildAddressBookRemoveContactModalUseCase(context),
  };
}

String addressBookModalCaseLabel(AddressBookModalCase modal) {
  return switch (modal) {
    AddressBookModalCase.addContact => 'Add contact',
    AddressBookModalCase.editContact => 'Edit contact',
    AddressBookModalCase.avatarPicker => 'Avatar picker',
    AddressBookModalCase.networkSelector => 'Network selector',
    AddressBookModalCase.networkSearchEmpty => 'Network, no results',
    AddressBookModalCase.removeContact => 'Remove contact',
  };
}

// --- Contact picker --------------------------------------------------------

Widget buildAddressBookContactPickerGalleryCase(BuildContext context) {
  final contacts = wbStateKnob<AddressBookPickerContacts>(
    context,
    label: 'Contacts',
    options: AddressBookPickerContacts.values,
    labelBuilder: addressBookPickerContactsLabel,
  );
  final async = wbStateKnob<AddressBookPickerAsync>(
    context,
    label: 'Load',
    options: AddressBookPickerAsync.values,
    labelBuilder: addressBookPickerAsyncLabel,
  );
  final networks = wbStateKnob<AddressBookPickerNetworks>(
    context,
    label: 'Networks',
    options: AddressBookPickerNetworks.values,
    labelBuilder: addressBookPickerNetworksLabel,
  );
  final query = wbStateKnob<AddressBookPickerQuery>(
    context,
    label: 'Search',
    options: AddressBookPickerQuery.values,
    labelBuilder: addressBookPickerQueryLabel,
  );

  // No Layout knob: the picker branches on `kAppFormFactor` itself, so only
  // the compiled lane's presentation can render.
  return addressBookContactPickerFixture(
    contacts: contacts,
    async: async,
    networks: networks,
    query: query,
  );
}

String addressBookPickerContactsLabel(AddressBookPickerContacts contacts) {
  return switch (contacts) {
    AddressBookPickerContacts.results => 'Saved contacts',
    AddressBookPickerContacts.noResults => 'No contacts',
  };
}

String addressBookPickerAsyncLabel(AddressBookPickerAsync async) {
  return switch (async) {
    AddressBookPickerAsync.loaded => 'Loaded',
    AddressBookPickerAsync.loading => 'Loading',
    AddressBookPickerAsync.failed => "Couldn't load",
  };
}

String addressBookPickerNetworksLabel(AddressBookPickerNetworks networks) {
  return switch (networks) {
    AddressBookPickerNetworks.single => 'One network',
    AddressBookPickerNetworks.multiple => 'Several networks',
  };
}

String addressBookPickerQueryLabel(AddressBookPickerQuery query) {
  return switch (query) {
    AddressBookPickerQuery.empty => 'Empty',
    AddressBookPickerQuery.typed => 'Typed',
  };
}

// --- Address book screen ---------------------------------------------------
//
// One surface, one use case: the `Layout` knob picks the desktop or mobile
// screen, and each layout declares only the state axes its own screen has —
// desktop modals and their contact form, mobile sheets.
//
// `Preview` picks between the production screen driven through its providers
// and callbacks, and the older static snapshot each lane keeps: on desktop a
// hand-built mirror of the page (`_AddressBookFrame`), on mobile the production
// screen frozen under `IgnorePointer` in a phone frame with the home-indicator
// inset. The snapshots only cover the three list states, plus the desktop row
// menu.
//
// The live desktop branch is `WbLaneOnly(desktop)`: it mounts the real
// AppMainSidebar, which overflows the 1080x720 desktop window under mobile
// typography, so the off-lane render is wrong rather than approximate.

/// Which contact the row menu is opened on.
enum AddressBookRowMenuNetwork { zcash, otherNetwork }

/// Production screen, or the static snapshot fixtures.
enum AddressBookScreenPreview { live, snapshot }

const String addressBookScreenPreviewKnobLabel = 'Preview';
const String addressBookScreenSubmitFailsKnobLabel = 'Submit fails';
const String addressBookScreenMenuOpenKnobLabel = 'Menu open';

/// Knob label of the desktop snapshot's row context menu.
const String addressBookRowMenuKnobLabel = 'Row menu';

/// Contact-list states the mobile screen has a surface for.
///
/// `Loading` and `Couldn't load` are deliberately absent: the screen reads
/// `ref.watch(addressBookProvider).value ?? const AddressBookState()`, so both
/// render exactly the no-contacts frame — they would be dead options here.
/// The mobile snapshot has a fixture for exactly these three as well.
const List<MobileAddressBookLoad> mobileAddressBookLoadOptions = [
  MobileAddressBookLoad.contacts,
  MobileAddressBookLoad.noContacts,
  MobileAddressBookLoad.noSearchResults,
];

/// Desktop `State` options per preview: the snapshot mirror has no loading or
/// error fixture.
List<AddressBookScreenLoad> addressBookScreenLoadOptions(
  AddressBookScreenPreview preview,
) {
  return preview == AddressBookScreenPreview.live
      ? AddressBookScreenLoad.values
      : const [
          AddressBookScreenLoad.contacts,
          AddressBookScreenLoad.noContacts,
          AddressBookScreenLoad.noSearchResults,
        ];
}

/// Desktop modals production can open over each `State`.
///
/// Edit and remove start from a contact row's menu, so they need a listed
/// contact; the add form (and the picture and network pickers it opens) starts
/// from the add button, which the empty states keep. `Couldn't load` replaces
/// the list and the floating add bar with the error pane, so nothing opens.
List<AddressBookScreenModal> addressBookScreenModalOptions(
  AddressBookScreenLoad load,
) {
  return switch (load) {
    AddressBookScreenLoad.contacts => AddressBookScreenModal.values,
    AddressBookScreenLoad.noContacts ||
    AddressBookScreenLoad.noSearchResults ||
    AddressBookScreenLoad.loading => const [
      AddressBookScreenModal.none,
      AddressBookScreenModal.addContact,
      AddressBookScreenModal.avatarPicker,
      AddressBookScreenModal.networkSelector,
    ],
    AddressBookScreenLoad.failed => const [AddressBookScreenModal.none],
  };
}

Widget buildAddressBookScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final preview = wbStateKnob<AddressBookScreenPreview>(
    context,
    label: addressBookScreenPreviewKnobLabel,
    options: AddressBookScreenPreview.values,
    labelBuilder: addressBookScreenPreviewLabel,
  );
  final snapshot = preview == AddressBookScreenPreview.snapshot;

  // Knobs are re-registered on every build, so each branch registers only its
  // own axes instead of carrying the other one's dead knobs.
  if (layout == WbLayout.mobile) {
    return snapshot
        ? _addressBookMobileSnapshot(context)
        : _addressBookMobileScreen(context);
  }
  return snapshot
      ? _addressBookDesktopSnapshot(context)
      : _addressBookDesktopScreen(context);
}

String addressBookScreenPreviewLabel(AddressBookScreenPreview preview) {
  return switch (preview) {
    AddressBookScreenPreview.live => 'Live screen',
    AddressBookScreenPreview.snapshot => 'Static snapshot',
  };
}

Widget _addressBookMobileScreen(BuildContext context) {
  final load = wbStateKnob<MobileAddressBookLoad>(
    context,
    label: 'State',
    options: mobileAddressBookLoadOptions,
    labelBuilder: mobileAddressBookLoadLabel,
  );
  final overlay = wbStateKnob<MobileAddressBookOverlay>(
    context,
    label: 'Sheet',
    options: MobileAddressBookOverlay.values,
    labelBuilder: mobileAddressBookOverlayLabel,
  );
  final network = wbStateKnob<MobileAddressBookNetwork>(
    context,
    label: 'Network',
    options: MobileAddressBookNetwork.values,
    labelBuilder: mobileAddressBookNetworkLabel,
  );
  final draft = wbStateKnob<MobileAddressBookDraft>(
    context,
    label: 'Draft',
    options: MobileAddressBookDraft.values,
    labelBuilder: mobileAddressBookDraftLabel,
  );
  return mobileAddressBookScreenFixture(
    load: load,
    overlay: overlay,
    network: network,
    draft: draft,
  );
}

Widget _addressBookMobileSnapshot(BuildContext context) {
  final load = wbStateKnob<MobileAddressBookLoad>(
    context,
    label: 'State',
    options: mobileAddressBookLoadOptions,
    labelBuilder: mobileAddressBookLoadLabel,
  );
  return switch (load) {
    MobileAddressBookLoad.contacts => buildMobileContactsListUseCase(context),
    MobileAddressBookLoad.noContacts => buildMobileContactsNoContactsUseCase(
      context,
    ),
    // Only the three list states are offered.
    _ => buildMobileContactsEmptySearchUseCase(context),
  };
}

Widget _addressBookDesktopSnapshot(BuildContext context) {
  final load = wbStateKnob<AddressBookScreenLoad>(
    context,
    label: 'State',
    options: addressBookScreenLoadOptions(AddressBookScreenPreview.snapshot),
    labelBuilder: addressBookScreenLoadLabel,
  );
  // Only the contact list has a row to open the menu on, so the knob is not
  // registered for the empty states.
  final rowMenuOpen =
      load == AddressBookScreenLoad.contacts &&
      wbBoolKnob(context, label: addressBookRowMenuKnobLabel);
  if (rowMenuOpen) return buildAddressBookSolanaMenuUseCase(context);
  return switch (load) {
    AddressBookScreenLoad.contacts => buildAddressBookContactsListUseCase(
      context,
    ),
    AddressBookScreenLoad.noContacts => buildAddressBookNoContactsUseCase(
      context,
    ),
    // Only the three list states are offered.
    _ => buildAddressBookEmptySearchUseCase(context),
  };
}

Widget _addressBookDesktopScreen(BuildContext context) {
  final load = wbStateKnob<AddressBookScreenLoad>(
    context,
    label: 'State',
    options: addressBookScreenLoadOptions(AddressBookScreenPreview.live),
    labelBuilder: addressBookScreenLoadLabel,
  );
  final networks = wbStateKnob<AddressBookScreenContacts>(
    context,
    label: 'Networks',
    options: AddressBookScreenContacts.values,
    labelBuilder: addressBookScreenContactsLabel,
  );
  final modal = wbStateKnob<AddressBookScreenModal>(
    context,
    label: 'Modal',
    options: addressBookScreenModalOptions(load),
    labelBuilder: addressBookScreenModalLabel,
  );
  // Draft and Avatar seed the contact form, so they only bite while `Modal`
  // has one open; Remove contact ignores both. With the error pane up no form
  // or submit exists, so the three are not registered at all.
  final canOpenForm = load != AddressBookScreenLoad.failed;
  final draft = canOpenForm
      ? wbStateKnob<AddressBookScreenDraft>(
          context,
          label: 'Draft',
          options: AddressBookScreenDraft.values,
          labelBuilder: addressBookScreenDraftLabel,
        )
      : AddressBookScreenDraft.unchanged;
  final avatar = canOpenForm
      ? wbStateKnob<AddressBookScreenAvatar>(
          context,
          label: 'Avatar',
          options: AddressBookScreenAvatar.values,
          labelBuilder: addressBookScreenAvatarLabel,
        )
      : AddressBookScreenAvatar.defaultPicture;
  final submitFails =
      canOpenForm &&
      wbBoolKnob(context, label: addressBookScreenSubmitFailsKnobLabel);

  // No Window knob: 1080x720 is the desktop minimum *and* default window, so
  // the pane never gets a smaller or unbounded viewport in the real app.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: addressBookScreenFixture(
      load: load,
      contacts: networks,
      modal: modal,
      draft: draft,
      avatar: avatar,
      submitFails: submitFails,
    ),
  );
}

String addressBookScreenLoadLabel(AddressBookScreenLoad load) {
  return switch (load) {
    AddressBookScreenLoad.contacts => 'Contacts',
    AddressBookScreenLoad.noContacts => 'No contacts',
    AddressBookScreenLoad.noSearchResults => 'No search results',
    AddressBookScreenLoad.loading => 'Loading',
    AddressBookScreenLoad.failed => "Couldn't load",
  };
}

String addressBookScreenContactsLabel(AddressBookScreenContacts contacts) {
  return switch (contacts) {
    AddressBookScreenContacts.zcashOnly => 'Zcash only',
    AddressBookScreenContacts.mixedNetworks => 'Mixed networks',
    AddressBookScreenContacts.allNetworks => 'Every network',
  };
}

String addressBookScreenModalLabel(AddressBookScreenModal modal) {
  return switch (modal) {
    AddressBookScreenModal.none => 'None',
    AddressBookScreenModal.addContact => 'Add contact',
    AddressBookScreenModal.editContact => 'Edit contact',
    AddressBookScreenModal.avatarPicker => 'Contact picture',
    AddressBookScreenModal.networkSelector => 'Select network',
    AddressBookScreenModal.removeContact => 'Remove contact',
  };
}

String addressBookScreenDraftLabel(AddressBookScreenDraft draft) {
  return switch (draft) {
    AddressBookScreenDraft.unchanged => 'As opened',
    AddressBookScreenDraft.labelTooLong => 'Label too long',
    AddressBookScreenDraft.invalidAddress => 'Invalid address',
    AddressBookScreenDraft.addressAdvisory => 'Address advisory',
  };
}

String addressBookScreenAvatarLabel(AddressBookScreenAvatar avatar) {
  // Read from the production option list so a picture rename cannot
  // desynchronize the knob.
  return switch (avatar) {
    AddressBookScreenAvatar.defaultPicture => 'Default',
    AddressBookScreenAvatar.pfp08 => resolveProfilePictureOption(
      'pfp-08',
    ).label,
    AddressBookScreenAvatar.lastOption => kProfilePictureOptions.last.label,
  };
}

// --- Contact row menu ------------------------------------------------------
//
// No Layout knob: the mobile row menu has no fixture — it inserts into the
// widgetbook's root overlay, above the theme addon, and asserts (see
// [MobileAddressBookOverlay]).

Widget buildAddressBookRowMenuGalleryCase(BuildContext context) {
  final network = wbStateKnob<AddressBookRowMenuNetwork>(
    context,
    label: 'Network',
    options: AddressBookRowMenuNetwork.values,
    labelBuilder: addressBookRowMenuNetworkLabel,
  );
  final open = wbBoolKnob(
    context,
    label: addressBookScreenMenuOpenKnobLabel,
    initial: true,
  );

  final zcash = network == AddressBookRowMenuNetwork.zcash;
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: addressBookScreenFixture(
      contacts: zcash
          ? AddressBookScreenContacts.zcashOnly
          : AddressBookScreenContacts.mixedNetworks,
      openMenuForContactId: !open
          ? null
          : zcash
          ? addressBookScreenZcashContactId
          : addressBookScreenOtherNetworkContactId,
    ),
  );
}

String addressBookRowMenuNetworkLabel(AddressBookRowMenuNetwork network) {
  return switch (network) {
    AddressBookRowMenuNetwork.zcash => 'Zcash contact',
    AddressBookRowMenuNetwork.otherNetwork => 'Other network',
  };
}

// --- Address book screen > mobile labels ------------------------------------

String mobileAddressBookLoadLabel(MobileAddressBookLoad load) {
  return switch (load) {
    MobileAddressBookLoad.contacts => 'Contacts',
    MobileAddressBookLoad.noContacts => 'No contacts',
    MobileAddressBookLoad.noSearchResults => 'No search results',
    MobileAddressBookLoad.loading => 'Loading',
    MobileAddressBookLoad.failed => "Couldn't load",
  };
}

String mobileAddressBookOverlayLabel(MobileAddressBookOverlay overlay) {
  return switch (overlay) {
    MobileAddressBookOverlay.none => 'None',
    MobileAddressBookOverlay.addContact => 'Add contact',
    MobileAddressBookOverlay.networkPicker => 'Select network',
  };
}

String mobileAddressBookNetworkLabel(MobileAddressBookNetwork network) {
  return switch (network) {
    MobileAddressBookNetwork.zcash => 'Zcash',
    MobileAddressBookNetwork.solana => 'Solana',
  };
}

String mobileAddressBookDraftLabel(MobileAddressBookDraft draft) {
  return switch (draft) {
    MobileAddressBookDraft.asOpened => 'As opened',
    MobileAddressBookDraft.invalidAddress => 'Invalid address',
    MobileAddressBookDraft.typing => 'Typing a name',
  };
}

// --- Network icon -----------------------------------------------------------

Widget buildAddressBookNetworkIconGalleryCase(BuildContext context) {
  final network = wbStateKnob<AddressBookNetwork>(
    context,
    label: 'Network',
    options: AddressBookNetwork.values,
    labelBuilder: (value) => value.label,
  );
  final size = wbStateKnob<AddressBookNetworkIconSize>(
    context,
    label: 'Size',
    options: AddressBookNetworkIconSize.values,
    labelBuilder: addressBookNetworkIconSizeLabel,
  );
  return addressBookNetworkIconFixture(network: network, size: size);
}

String addressBookNetworkIconSizeLabel(AddressBookNetworkIconSize size) {
  return switch (size) {
    AddressBookNetworkIconSize.row => 'Contact row (24)',
    AddressBookNetworkIconSize.groupLabel => 'Group label (16)',
    AddressBookNetworkIconSize.badge => 'Avatar badge (12)',
  };
}

// --- Contact name inline ----------------------------------------------------

Widget buildContactNameInlineGalleryCase(BuildContext context) {
  final address = wbStateKnob<ContactNameInlineAddress>(
    context,
    label: 'Address',
    options: ContactNameInlineAddress.values,
    labelBuilder: contactNameInlineAddressLabel,
  );
  final name = wbStateKnob<ContactNameInlineName>(
    context,
    label: 'Name',
    options: ContactNameInlineName.values,
    labelBuilder: contactNameInlineNameLabel,
  );
  return contactNameInlineFixture(address: address, name: name);
}

String contactNameInlineAddressLabel(ContactNameInlineAddress address) {
  return switch (address) {
    ContactNameInlineAddress.none => 'Name only',
    ContactNameInlineAddress.compactAddress => 'With address',
  };
}

String contactNameInlineNameLabel(ContactNameInlineName name) {
  return switch (name) {
    ContactNameInlineName.short => 'Short',
    ContactNameInlineName.overflowing => 'Too long for the row',
  };
}

// --- Address scan ----------------------------------------------------------

/// Knob label of the scan card's close affordance, shared with the test.
const String addressScanCardCloseKnobLabel = 'Close enabled';

/// The address scanner of both lanes: desktop hosts open the scan modal,
/// mobile hosts the bottom-sheet scan card.
Widget buildAddressScanGalleryCase(BuildContext context) {
  return wbLayoutKnob(context) == WbLayout.mobile
      ? _addressScanCardCase(context)
      : _addressScanModalCase(context);
}

Widget _addressScanModalCase(BuildContext context) {
  final camera = wbStateKnob<AddressScanModalCamera>(
    context,
    label: 'Camera',
    options: AddressScanModalCamera.values,
    labelBuilder: addressScanModalCameraLabel,
    initial: AddressScanModalCamera.active,
  );
  final error = wbStateKnob<AddressScanModalError>(
    context,
    label: 'Scanned code',
    options: AddressScanModalError.values,
    labelBuilder: addressScanModalErrorLabel,
  );
  final picker = wbStateKnob<AddressScanModalPicker>(
    context,
    label: 'Camera picker',
    options: AddressScanModalPicker.values,
    labelBuilder: addressScanModalPickerLabel,
  );

  // Lane-gated: the modal branches on `kAppFormFactor` itself, so the mobile
  // lane would render its hug-content geometry rather than the desktop modal.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: addressQrScanModalFixture(
      camera: camera,
      error: error,
      picker: picker,
    ),
  );
}

String addressScanModalCameraLabel(AddressScanModalCamera camera) {
  return switch (camera) {
    AddressScanModalCamera.requesting => 'Asking for access',
    AddressScanModalCamera.denied => 'Access denied',
    AddressScanModalCamera.active => 'Camera ready',
    AddressScanModalCamera.loading => 'Starting camera',
    AddressScanModalCamera.unavailable => 'No camera',
    AddressScanModalCamera.unavailableDetail => 'No camera, system message',
  };
}

String addressScanModalErrorLabel(AddressScanModalError error) {
  return switch (error) {
    AddressScanModalError.none => 'Nothing scanned yet',
    AddressScanModalError.noAddress => 'No address in the QR code',
  };
}

String addressScanModalPickerLabel(AddressScanModalPicker picker) {
  return switch (picker) {
    AddressScanModalPicker.canSwitch => 'Can switch camera',
    AddressScanModalPicker.singleCamera => 'One camera only',
  };
}

Widget _addressScanCardCase(BuildContext context) {
  final camera = wbStateKnob<AddressScanCardCamera>(
    context,
    label: 'Camera',
    options: AddressScanCardCamera.values,
    labelBuilder: addressScanCardCameraLabel,
    initial: AddressScanCardCamera.active,
  );
  final error = wbStateKnob<AddressScanCardError>(
    context,
    label: 'Caption',
    options: AddressScanCardError.values,
    labelBuilder: addressScanCardErrorLabel,
  );
  final copy = wbStateKnob<AddressScanCardCopy>(
    context,
    label: 'Flow',
    options: AddressScanCardCopy.values,
    labelBuilder: addressScanCardCopyLabel,
  );
  final chrome = wbStateKnob<AddressScanCardChrome>(
    context,
    label: 'Permission chrome',
    options: AddressScanCardChrome.values,
    labelBuilder: addressScanCardChromeLabel,
  );
  final height = wbStateKnob<AddressScanCardHeight>(
    context,
    label: 'Height',
    options: AddressScanCardHeight.values,
    labelBuilder: addressScanCardHeightLabel,
  );
  final closeEnabled = wbBoolKnob(
    context,
    label: addressScanCardCloseKnobLabel,
    initial: true,
  );

  return mobileAddressScanCardFixture(
    camera: camera,
    error: error,
    copy: copy,
    chrome: chrome,
    height: height,
    closeEnabled: closeEnabled,
  );
}

String addressScanCardCameraLabel(AddressScanCardCamera camera) {
  return switch (camera) {
    AddressScanCardCamera.requesting => 'Asking for access',
    AddressScanCardCamera.denied => 'Access denied',
    AddressScanCardCamera.active => 'Camera ready',
    AddressScanCardCamera.loading => 'Starting camera',
    AddressScanCardCamera.unavailable => 'No camera',
  };
}

String addressScanCardErrorLabel(AddressScanCardError error) {
  return switch (error) {
    AddressScanCardError.none => 'Idle prompt',
    AddressScanCardError.wrongCode => 'Wrong QR code',
    AddressScanCardError.keepSteady => 'Keep the code steady',
  };
}

String addressScanCardCopyLabel(AddressScanCardCopy copy) {
  return switch (copy) {
    AddressScanCardCopy.sendAndSwap => 'Send and swap',
    AddressScanCardCopy.contacts => 'Contacts',
    AddressScanCardCopy.pay => 'Pay',
    AddressScanCardCopy.giftCard => 'Gift card',
  };
}

String addressScanCardChromeLabel(AddressScanCardChrome chrome) {
  return switch (chrome) {
    AddressScanCardChrome.permissionCard => 'Shared permission card',
    AddressScanCardChrome.keystoneCard => 'Keystone permission card',
  };
}

String addressScanCardHeightLabel(AddressScanCardHeight height) {
  return switch (height) {
    AddressScanCardHeight.modal => 'Bottom sheet',
    AddressScanCardHeight.inPage => 'In-page (420)',
  };
}

Widget buildMobileScanCameraErrorOverlayGalleryCase(BuildContext context) {
  final error = wbStateKnob<MobileScanOverlayError>(
    context,
    label: 'Camera',
    options: MobileScanOverlayError.values,
    labelBuilder: mobileScanOverlayErrorLabel,
    initial: MobileScanOverlayError.permissionDenied,
  );
  return mobileScanCameraErrorOverlayFixture(error: error);
}

String mobileScanOverlayErrorLabel(MobileScanOverlayError error) {
  return switch (error) {
    MobileScanOverlayError.none => 'Scanning, no error',
    MobileScanOverlayError.permissionDenied => 'Access denied',
    MobileScanOverlayError.unavailable => 'Camera unavailable',
  };
}

Widget buildMobileScanViewfinderGalleryCase(BuildContext context) {
  final variant = wbStateKnob<MobileScanViewfinderVariant>(
    context,
    label: 'Brackets',
    options: MobileScanViewfinderVariant.values,
    labelBuilder: mobileScanViewfinderVariantLabel,
  );
  return mobileScanViewfinderCornersFixture(variant: variant);
}

String mobileScanViewfinderVariantLabel(MobileScanViewfinderVariant variant) {
  return switch (variant) {
    MobileScanViewfinderVariant.fullScreen => 'Full-screen scanner',
    MobileScanViewfinderVariant.card => 'Scan card',
    MobileScanViewfinderVariant.keystone => 'Keystone signing',
    MobileScanViewfinderVariant.allThree => 'All three, side by side',
  };
}
