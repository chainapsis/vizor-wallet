// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

/// Widgetbook states for the Receive "Request ZEC" flow.
///
/// Every state is a pure function of a [ZecRequestView], so what is reviewed
/// here is exactly what the widgets will render once they are wired.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/receive/widgets/receive_address_widgets.dart';
import '../src/features/receive/widgets/request/receive_request_entry.dart';
import '../src/features/receive/widgets/request/request_amount_card.dart';
import '../src/features/receive/widgets/request/request_amount_model.dart';
import '../src/features/receive/widgets/request/request_amount_sheet.dart';

/// The addresses the Receive use cases already preview, so the request states
/// and the address states describe the same wallet.
const _shieldedAddress =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const _transparentAddress = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

const _amountZec = '0.5';
const _amountUsd = '35.00';
const _fiatText = r'$35.00';
const _message = 'Table 4 — two flat whites';

const _emptyRequest = ZecRequestView(address: _shieldedAddress);

const _amountRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: _amountZec,
  conversionText: _fiatText,
);

const _amountWithMessageRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: _amountZec,
  conversionText: _fiatText,
  messageText: _message,
);

const _transparentRequest = ZecRequestView(
  address: _transparentAddress,
  amountZec: _amountZec,
  conversionText: _fiatText,
);

/// The amount error state: more decimals than a zatoshi can hold.
const _amountErrorRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: '',
  amountDisplayText: '0.123456789',
  conversionText: _fiatText,
  amountError: kRequestAmountDecimalsError,
);

/// USD entry mode — the amount is still 0.5 ZEC, the field just shows the
/// dollars it was typed in.
const _usdRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: _amountZec,
  amountDisplayText: _amountUsd,
  amountInputIsUsd: true,
  conversionText: '$_amountZec ZEC',
);

/// ZEC typed but no live price to convert it: the readout is the same
/// placeholder the send composer shows, and the unit switch is inert.
const _priceUnavailableRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: _amountZec,
);

// ─── Desktop ─────────────────────────────────────────────────────────

Widget buildRequestModalStepOneEmptyUseCase(BuildContext context) =>
    _desktop(_emptyRequest);

Widget buildRequestModalStepOneAmountUseCase(BuildContext context) =>
    _desktop(_amountRequest);

Widget buildRequestModalStepOnePriceUnavailableUseCase(BuildContext context) =>
    _desktop(_priceUnavailableRequest, toggleEnabled: false);
Widget buildRequestModalStepOneMessageUseCase(BuildContext context) =>
    _desktop(_amountWithMessageRequest, messageExpanded: true);

Widget buildRequestModalStepOneTransparentUseCase(BuildContext context) =>
    _desktop(_transparentRequest);

Widget buildRequestModalStepOneAmountErrorUseCase(BuildContext context) =>
    _desktop(_amountErrorRequest);

Widget buildRequestModalStepTwoShieldedUseCase(BuildContext context) =>
    _desktop(_amountWithMessageRequest, step: RequestModalStep.result);

Widget buildRequestModalStepTwoTransparentUseCase(BuildContext context) =>
    _desktop(_transparentRequest, step: RequestModalStep.result);

// ─── Mobile ──────────────────────────────────────────────────────────

Widget buildRequestMobileEntryUseCase(BuildContext context) {
  return _frame(
    const Size(393, 852),
    const MobileReceiveRequestEntryPreview(
      type: ReceiveAddressType.shielded,
      address: _shieldedAddress,
    ),
  );
}

Widget buildRequestMobileComposeEmptyUseCase(BuildContext context) =>
    _mobileCompose(_emptyRequest);

Widget buildRequestMobileComposeUsdUseCase(BuildContext context) =>
    _mobileCompose(_usdRequest);

Widget buildRequestMobileComposePriceUnavailableUseCase(BuildContext context) =>
    _mobileCompose(_priceUnavailableRequest, toggleEnabled: false);
Widget buildRequestMobileComposeMessageUseCase(BuildContext context) =>
    _mobileCompose(_amountWithMessageRequest);

Widget buildRequestMobileResultShieldedUseCase(BuildContext context) =>
    _mobileResult(_amountWithMessageRequest);

Widget buildRequestMobileResultTransparentUseCase(BuildContext context) =>
    _mobileResult(_transparentRequest);

// ─── Frames ──────────────────────────────────────────────────────────

Widget _desktop(
  ZecRequestView request, {
  RequestModalStep step = RequestModalStep.compose,
  bool messageExpanded = false,
  bool toggleEnabled = true,
}) {
  return _frame(
    // A desktop pane is the surface the request modal opens over.
    const Size(AppWindowSizing.contentAreaMaxWidth + AppSpacing.xl2, 720),
    RequestAmountSurface(
      request: request,
      step: step,
      messageExpanded: messageExpanded,
      onClose: _noop,
      onNext: _noop,
      onBack: _noop,
      onCopyLink: _noop,
      onSaveQrImage: _logPng('save QR image'),
      onAddMessage: _noop,
      onToggleAmountUnit: toggleEnabled ? _noop : null,
    ),
  );
}

Widget _mobileCompose(ZecRequestView request, {bool toggleEnabled = true}) {
  return _frame(
    const Size(393, 852),
    RequestAmountSheetSurface(
      child: RequestAmountSheetCompose(
        request: request,
        onClose: _noop,
        onToggleAmountUnit: toggleEnabled ? _noop : null,
        onAddMessage: _noop,
        onCreateRequest: _noop,
      ),
    ),
  );
}

Widget _mobileResult(ZecRequestView request) {
  return _frame(
    const Size(393, 852),
    RequestAmountSheetSurface(
      child: RequestAmountSheetResult(
        request: request,
        onBack: _noop,
        onClose: _noop,
        onShareRequest: (text, png) => debugPrint(
          'request: share ${png.length} byte PNG with '
          '${text.length} chars of text',
        ),
        onCopyLink: _noop,
      ),
    ),
  );
}

/// Fixed preview viewport so the modal is measured against a real screen
/// rather than against the Widgetbook chrome.
Widget _frame(Size size, Widget child) {
  return Center(
    child: SizedBox(
      key: const ValueKey('request_preview_frame'),
      width: size.width,
      height: size.height,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: size),
          child: child,
        ),
      ),
    ),
  );
}

void _noop() {}

/// Fixtures log rather than act: the flow is presentation-only until it is
/// wired, and a Widgetbook tap should still show that the bytes arrived.
ValueChanged<Uint8List> _logPng(String action) =>
    (png) => debugPrint('request: $action (${png.length} bytes)');
