// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/features/receive/widgets/receive_address_widgets.dart';
import '../../src/features/receive/widgets/request/request_amount_model.dart';
import '../receive_screen_use_cases.dart';
import '../receive_use_cases.dart';
import '../request_amount_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';

/// The Receive gallery: one use case per surface, dispatching to the fixtures
/// in `receive_use_cases.dart`, `receive_screen_use_cases.dart` and
/// `request_amount_use_cases.dart` so figma_compare and the tests keep every
/// `build*UseCase` they bind to.
///
/// The screen is one `Screen` case with a `Layout` knob; its `Address`
/// axis is registered per layout because the desktop pane's four outcomes do
/// not exist on the mobile pane.
///
/// The mobile options carry no `WbLaneOnly`: they are the same token
/// approximation the flat mobile cases already shipped, and gating them would
/// make the whole mobile side of Receive invisible in the desktop lane. The
/// desktop `ReceiveScreen` is gated the other way — its fixed-coordinate pane
/// overflows by 2pt against the mobile token set.
final List<WidgetbookNode> receiveGalleryNodes = [
  WidgetbookComponent(
    name: 'Receive screen',
    useCases: [
      WidgetbookUseCase(name: 'Screen', builder: buildReceiveScreenGalleryCase),
      WidgetbookUseCase(
        name: 'Address info sheet',
        builder: buildReceiveAddressInfoGalleryCase,
      ),
      // Its own case: the entry mock exists only for the shielded desktop
      // pane, so it cannot be an option on the Address axis.
      WidgetbookUseCase(
        name: 'Request ZEC entry',
        builder: buildReceiveDesktopRequestEntryUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Request ZEC',
    useCases: [
      WidgetbookUseCase(
        name: 'Compose',
        builder: buildReceiveRequestComposeGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Result',
        builder: buildReceiveRequestResultGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Request sheet',
        builder: buildReceiveRequestSheetGalleryCase,
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Receive components',
        useCases: [
          WidgetbookUseCase(
            name: 'Copy address button',
            builder: buildReceiveCopyAddressButtonGalleryCase,
          ),
          WidgetbookUseCase(name: 'Tabs', builder: buildReceiveTabsGalleryCase),
          WidgetbookUseCase(
            name: 'QR surface',
            builder: buildReceiveQrSurfaceGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Renew button',
            builder: buildReceiveRenewButtonGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Address line',
            builder: buildReceiveAddressLineGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Request parts',
        useCases: [
          WidgetbookUseCase(
            name: 'QR surface',
            builder: buildReceiveRequestQrSurfaceGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'QR export button',
            builder: buildReceiveRequestQrExportGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Amount rows',
            builder: buildReceiveRequestAmountRowsGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Shared axes -----------------------------------------------------------

/// Which pool the address on screen belongs to.
enum ReceivePoolCase { shielded, transparent }

String receivePoolCaseLabel(ReceivePoolCase pool) {
  return switch (pool) {
    ReceivePoolCase.shielded => 'Shielded',
    ReceivePoolCase.transparent => 'Transparent',
  };
}

ReceiveAddressType _addressType(ReceivePoolCase pool) {
  return pool == ReceivePoolCase.shielded
      ? ReceiveAddressType.shielded
      : ReceiveAddressType.transparent;
}

ReceivePoolCase _poolKnob(BuildContext context) {
  return wbStateKnob<ReceivePoolCase>(
    context,
    label: 'Pool',
    options: ReceivePoolCase.values,
    labelBuilder: receivePoolCaseLabel,
  );
}

// --- Receive screen ---------------------------------------------------------

/// How the desktop screen's address load resolved.
enum ReceiveAddressCase { loaded, loading, empty, failed }

/// The mobile pane only ever shows an address or nothing: a failed load is
/// caught into the same empty address the actions are disabled on.
enum ReceiveMobileAddressCase { loaded, unavailable }

/// Both form factors in one case. The `Address` axis is registered per layout
/// rather than filtered: the two panes resolve a load into different outcomes.
///
/// Only the desktop branch is lane-gated: `_ReceivePane` pins its content
/// block to 656/724pt, which the taller mobile typography overflows.
Widget buildReceiveScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final pool = _poolKnob(context);
  if (layout == WbLayout.mobile) {
    final address = wbStateKnob<ReceiveMobileAddressCase>(
      context,
      label: 'Address',
      options: ReceiveMobileAddressCase.values,
      labelBuilder: receiveMobileAddressCaseLabel,
    );
    // The Screen entry owns the actual request sheet journey. Its preview
    // fixture keeps the same in-memory addresses, price and share handler as
    // the static screen, so opening Request never reaches device services.
    return receiveMobileFlowFixture(
      type: _addressType(pool),
      addressAvailable: address == ReceiveMobileAddressCase.loaded,
    );
  }
  final address = wbStateKnob<ReceiveAddressCase>(
    context,
    label: 'Address',
    options: ReceiveAddressCase.values,
    labelBuilder: receiveAddressCaseLabel,
  );
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: receiveDesktopScreenFixture(
      pool: _addressType(pool),
      outcome: switch (address) {
        ReceiveAddressCase.loaded => ReceiveScreenAddressOutcome.resolved,
        ReceiveAddressCase.loading => ReceiveScreenAddressOutcome.pending,
        ReceiveAddressCase.empty => ReceiveScreenAddressOutcome.empty,
        ReceiveAddressCase.failed => ReceiveScreenAddressOutcome.failed,
      },
    ),
  );
}

String receiveAddressCaseLabel(ReceiveAddressCase address) {
  return switch (address) {
    ReceiveAddressCase.loaded => 'Loaded',
    ReceiveAddressCase.loading => 'Loading',
    ReceiveAddressCase.empty => 'Empty',
    ReceiveAddressCase.failed => 'Failed to load',
  };
}

String receiveMobileAddressCaseLabel(ReceiveMobileAddressCase address) {
  return switch (address) {
    ReceiveMobileAddressCase.loaded => 'Loaded',
    ReceiveMobileAddressCase.unavailable => 'Unavailable',
  };
}

// --- Receive screen > Address info sheet -----------------------------------

/// Its own case rather than an overlay option on the screen: the desktop half
/// of this pair is a private dialog with no fixture, so a Layout knob here
/// would carry a dead option.
Widget buildReceiveAddressInfoGalleryCase(BuildContext context) {
  final pool = wbStateKnob<ReceivePoolCase>(
    context,
    label: 'Type',
    options: ReceivePoolCase.values,
    labelBuilder: receivePoolCaseLabel,
  );
  return switch (pool) {
    ReceivePoolCase.shielded => buildReceiveMobileShieldedSheetUseCase(context),
    ReceivePoolCase.transparent => buildReceiveMobileTransparentSheetUseCase(
      context,
    ),
  };
}

// --- Receive components ----------------------------------------------------

/// Whether the component was handed an address at all.
enum ReceiveComponentAddressCase { present, empty }

String receiveComponentAddressCaseLabel(ReceiveComponentAddressCase address) {
  return switch (address) {
    ReceiveComponentAddressCase.present => 'Present',
    ReceiveComponentAddressCase.empty => 'Empty',
  };
}

const kReceiveCopyEnabledKnob = 'Enabled';

/// The pool axis every address component carries, labelled the way the
/// components' own props name it.
ReceivePoolCase _typeKnob(BuildContext context) {
  return wbStateKnob<ReceivePoolCase>(
    context,
    label: 'Type',
    options: ReceivePoolCase.values,
    labelBuilder: receivePoolCaseLabel,
  );
}

bool _addressPresentKnob(BuildContext context) {
  return wbStateKnob<ReceiveComponentAddressCase>(
        context,
        label: 'Address',
        options: ReceiveComponentAddressCase.values,
        labelBuilder: receiveComponentAddressCaseLabel,
      ) ==
      ReceiveComponentAddressCase.present;
}

/// No Layout knob: the button hard-codes the desktop pane's 230×44 slot, and
/// the mobile pane copies through its own text button instead.
Widget buildReceiveCopyAddressButtonGalleryCase(BuildContext context) {
  final pool = _typeKnob(context);
  final enabled = wbBoolKnob(
    context,
    label: kReceiveCopyEnabledKnob,
    initial: true,
  );
  return receiveCopyAddressButtonFixture(
    type: _addressType(pool),
    enabled: enabled,
  );
}

/// Layout is the call site's argument set: the desktop pane leaves
/// `alwaysDarkSelected` off, which nothing else in the gallery renders.
Widget buildReceiveTabsGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final selected = wbStateKnob<ReceivePoolCase>(
    context,
    label: 'Selected',
    options: ReceivePoolCase.values,
    labelBuilder: receivePoolCaseLabel,
  );
  return receiveTabsFixture(selected: _addressType(selected), layout: layout);
}

/// The transparent code's light and dark treatment is the Theme addon, not a
/// knob: the surface picks it from the theme, not from a prop.
Widget buildReceiveQrSurfaceGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final pool = _typeKnob(context);
  final present = _addressPresentKnob(context);
  return receiveQrSurfaceFixture(
    type: _addressType(pool),
    layout: layout,
    addressAvailable: present,
  );
}

/// Whether the renew round-trip is in flight.
///
/// No disabled option and no Layout knob: `onTap: null` only changes the
/// cursor, and both call sites ask for the same 48pt button.
enum ReceiveRenewCase { idle, renewing }

String receiveRenewCaseLabel(ReceiveRenewCase state) {
  return switch (state) {
    ReceiveRenewCase.idle => 'Idle',
    ReceiveRenewCase.renewing => 'Renewing',
  };
}

Widget buildReceiveRenewButtonGalleryCase(BuildContext context) {
  final state = wbStateKnob<ReceiveRenewCase>(
    context,
    label: 'State',
    options: ReceiveRenewCase.values,
    labelBuilder: receiveRenewCaseLabel,
  );
  return receiveRenewButtonFixture(
    renewing: state == ReceiveRenewCase.renewing,
  );
}

/// Layout is the styling axis: the desktop pane keeps the dark accent, the
/// mobile frame tints the address secondary and scales it to fit.
Widget buildReceiveAddressLineGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final pool = _typeKnob(context);
  final present = _addressPresentKnob(context);
  return receiveAddressLineFixture(
    type: _addressType(pool),
    layout: layout,
    addressAvailable: present,
  );
}

// --- Request ZEC -----------------------------------------------------------

/// Compose states; `denseMessage` is a result-step fixture, so it is absent.
const List<ReceiveRequestFixture> kReceiveRequestComposeCases = [
  ReceiveRequestFixture.empty,
  ReceiveRequestFixture.amount,
  ReceiveRequestFixture.amountInUsd,
  ReceiveRequestFixture.priceUnavailable,
  ReceiveRequestFixture.amountAndMessage,
  ReceiveRequestFixture.transparentAddress,
  ReceiveRequestFixture.amountError,
  ReceiveRequestFixture.amountOverSupply,
  ReceiveRequestFixture.amountFormatError,
];

/// What the request modal sits on.
enum ReceiveRequestBackgroundCase { flat, receivePane }

String receiveRequestBackgroundCaseLabel(ReceiveRequestBackgroundCase value) {
  return switch (value) {
    ReceiveRequestBackgroundCase.flat => 'Flat',
    ReceiveRequestBackgroundCase.receivePane => 'Receive pane',
  };
}

const kReceiveRequestMessageExpandedKnob = 'Message expanded';
const kReceiveRequestAmountFocusedKnob = 'Amount focused';

/// The modal's background, or null for the flat window colour.
Widget? _backgroundKnob(BuildContext context, WbLayout layout) {
  final background = wbStateKnob<ReceiveRequestBackgroundCase>(
    context,
    label: 'Background',
    options: ReceiveRequestBackgroundCase.values,
    labelBuilder: receiveRequestBackgroundCaseLabel,
  );
  return background == ReceiveRequestBackgroundCase.flat
      ? null
      : receiveRequestPaneBackground(layout);
}

/// Result states; an amount error never reaches the result step, and the
/// unit-entry states produce the same summary as `amount`.
const List<ReceiveRequestFixture> kReceiveRequestResultCases = [
  ReceiveRequestFixture.empty,
  ReceiveRequestFixture.amountAndMessage,
  ReceiveRequestFixture.transparentAddress,
  ReceiveRequestFixture.denseMessage,
];

/// 'Amount' and 'Amount and message' only differ while 'Message expanded' is
/// on: with the editor collapsed the card draws both states identically, which
/// is the product's behaviour, not a dead option.
Widget buildReceiveRequestComposeGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final fixture = wbStateKnob<ReceiveRequestFixture>(
    context,
    label: 'Request',
    options: kReceiveRequestComposeCases,
    labelBuilder: receiveRequestFixtureLabel,
  );
  final messageExpanded = wbBoolKnob(
    context,
    label: kReceiveRequestMessageExpandedKnob,
  );
  // Registered on desktop only: the mobile amount is a static display until
  // the live sheet hands it a controller, so the axis does not exist there.
  final amountFocused =
      layout == WbLayout.desktop &&
      wbBoolKnob(context, label: kReceiveRequestAmountFocusedKnob);
  return receiveRequestFixture(
    layout: layout,
    step: RequestModalStep.compose,
    fixture: fixture,
    messageExpanded: messageExpanded,
    amountFocused: amountFocused,
    background: _backgroundKnob(context, layout),
  );
}

Widget buildReceiveRequestResultGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final fixture = wbStateKnob<ReceiveRequestFixture>(
    context,
    label: 'Request',
    options: kReceiveRequestResultCases,
    labelBuilder: receiveRequestFixtureLabel,
  );
  return receiveRequestFixture(
    layout: layout,
    step: RequestModalStep.result,
    fixture: fixture,
    background: _backgroundKnob(context, layout),
  );
}

String receiveRequestFixtureLabel(ReceiveRequestFixture fixture) {
  return switch (fixture) {
    ReceiveRequestFixture.empty => 'No amount',
    ReceiveRequestFixture.amount => 'Amount',
    ReceiveRequestFixture.amountInUsd => 'Amount in USD',
    ReceiveRequestFixture.priceUnavailable => 'No price',
    ReceiveRequestFixture.amountAndMessage => 'Amount and message',
    ReceiveRequestFixture.transparentAddress => 'Transparent address',
    ReceiveRequestFixture.amountError => 'Amount error',
    ReceiveRequestFixture.amountOverSupply => 'Over supply',
    ReceiveRequestFixture.amountFormatError => 'Not a number',
    ReceiveRequestFixture.denseMessage => '512-byte message',
  };
}

// --- Request ZEC > Request sheet -------------------------------------------

/// Whether a live ZEC price is available to convert the amount with.
enum ReceiveRequestPriceCase { live, unavailable }

/// The live sheet: its steps, the message editor and the toasts are reached by
/// interacting with it, not by seeding state. The presentational snapshots of
/// those steps stay on the Compose and Result cases.
Widget buildReceiveRequestSheetGalleryCase(BuildContext context) {
  final pool = _poolKnob(context);
  final price = wbStateKnob<ReceiveRequestPriceCase>(
    context,
    label: 'Price',
    options: ReceiveRequestPriceCase.values,
    labelBuilder: receiveRequestPriceCaseLabel,
  );
  return receiveRequestSheetFixture(
    pool: _addressType(pool),
    priceAvailable: price == ReceiveRequestPriceCase.live,
  );
}

String receiveRequestPriceCaseLabel(ReceiveRequestPriceCase price) {
  return switch (price) {
    ReceiveRequestPriceCase.live => 'Live',
    ReceiveRequestPriceCase.unavailable => 'Unavailable',
  };
}

// --- Request components > QR surface ---------------------------------------

/// What the standalone code encodes.
enum ReceiveRequestQrDataCase { normal, denseMessage, empty }

Widget buildReceiveRequestQrSurfaceGalleryCase(BuildContext context) {
  final data = wbStateKnob<ReceiveRequestQrDataCase>(
    context,
    label: 'Data',
    options: ReceiveRequestQrDataCase.values,
    labelBuilder: receiveRequestQrDataCaseLabel,
  );
  final size = wbStateKnob<RequestQrPreviewSize>(
    context,
    label: 'Size',
    options: RequestQrPreviewSize.values,
    labelBuilder: receiveRequestQrSizeLabel,
  );
  return requestQrSurfaceFixture(
    data: switch (data) {
      ReceiveRequestQrDataCase.normal => receiveRequestQrData(
        ReceiveRequestFixture.amount,
      ),
      ReceiveRequestQrDataCase.denseMessage => receiveRequestQrData(
        ReceiveRequestFixture.denseMessage,
      ),
      // No request and no address to fall back on: the placeholder state.
      ReceiveRequestQrDataCase.empty => '',
    },
    size: size,
  );
}

String receiveRequestQrDataCaseLabel(ReceiveRequestQrDataCase data) {
  return switch (data) {
    ReceiveRequestQrDataCase.normal => 'Normal',
    ReceiveRequestQrDataCase.denseMessage => '512-byte message',
    ReceiveRequestQrDataCase.empty => 'Empty',
  };
}

/// Named after the surface each side belongs to, not the number: the axis is
/// which call site, and only the smaller one shows the dense growth.
String receiveRequestQrSizeLabel(RequestQrPreviewSize size) {
  return switch (size) {
    RequestQrPreviewSize.desktopModal => 'Desktop modal',
    RequestQrPreviewSize.mobileSheet => 'Mobile sheet',
  };
}

// --- Request components > QR export button ---------------------------------

const kReceiveRequestExportEnabledKnob = 'Enabled';

Widget buildReceiveRequestQrExportGalleryCase(BuildContext context) {
  final action = wbStateKnob<RequestQrExportAction>(
    context,
    label: 'Action',
    options: RequestQrExportAction.values,
    labelBuilder: receiveRequestExportActionLabel,
  );
  final enabled = wbBoolKnob(
    context,
    label: kReceiveRequestExportEnabledKnob,
    initial: true,
  );
  return requestQrExportButtonFixture(action: action, enabled: enabled);
}

String receiveRequestExportActionLabel(RequestQrExportAction action) {
  return switch (action) {
    RequestQrExportAction.saveImage => 'Save QR image',
    RequestQrExportAction.shareRequest => 'Share request',
  };
}

// --- Request components > Amount rows --------------------------------------

/// Which unit the amount field is collecting.
enum ReceiveRequestUnitCase { zec, usd }

/// The three inline amount errors the field can carry.
enum ReceiveRequestErrorCase { decimals, overSupply, notANumber }

/// 'Unit' and 'Error' are sub-axes of 'Row': the amount field is the only row
/// that reads the unit and the error row the only one that reads the text, so
/// the other three options ignore both.
Widget buildReceiveRequestAmountRowsGalleryCase(BuildContext context) {
  final row = wbStateKnob<RequestAmountRowCase>(
    context,
    label: 'Row',
    options: RequestAmountRowCase.values,
    labelBuilder: receiveRequestRowLabel,
  );
  final unit = row == RequestAmountRowCase.amountField
      ? wbStateKnob<ReceiveRequestUnitCase>(
          context,
          label: 'Unit',
          options: ReceiveRequestUnitCase.values,
          labelBuilder: receiveRequestUnitLabel,
        )
      : ReceiveRequestUnitCase.zec;
  final error = row == RequestAmountRowCase.amountError
      ? wbStateKnob<ReceiveRequestErrorCase>(
          context,
          label: 'Error',
          options: ReceiveRequestErrorCase.values,
          labelBuilder: receiveRequestErrorLabel,
        )
      : ReceiveRequestErrorCase.decimals;
  return requestAmountRowFixture(
    row: row,
    amountInUsd: unit == ReceiveRequestUnitCase.usd,
    errorText: switch (error) {
      ReceiveRequestErrorCase.decimals => kRequestAmountDecimalsError,
      ReceiveRequestErrorCase.overSupply => kRequestAmountSupplyError,
      ReceiveRequestErrorCase.notANumber => kRequestAmountFormatError,
    },
  );
}

String receiveRequestUnitLabel(ReceiveRequestUnitCase unit) {
  return switch (unit) {
    ReceiveRequestUnitCase.zec => 'ZEC',
    ReceiveRequestUnitCase.usd => 'USD',
  };
}

String receiveRequestRowLabel(RequestAmountRowCase row) {
  return switch (row) {
    RequestAmountRowCase.amountField => 'Amount field',
    RequestAmountRowCase.amountError => 'Amount error',
    RequestAmountRowCase.addMessage => 'Add message',
    RequestAmountRowCase.messageField => 'Message field',
    RequestAmountRowCase.header => 'Header',
  };
}

String receiveRequestErrorLabel(ReceiveRequestErrorCase error) {
  return switch (error) {
    ReceiveRequestErrorCase.decimals => 'Decimals',
    ReceiveRequestErrorCase.overSupply => 'Over supply',
    ReceiveRequestErrorCase.notANumber => 'Not a number',
  };
}
