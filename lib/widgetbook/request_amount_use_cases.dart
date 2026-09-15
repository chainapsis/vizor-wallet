// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

/// Widgetbook states for the Receive "Request ZEC" flow.
///
/// Every state is a pure function of a [ZecRequestView], so what is reviewed
/// here is exactly what the widgets will render once they are wired.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/receive/widgets/receive_address_widgets.dart';
import '../src/features/receive/widgets/request/request_amount_card.dart';
import '../src/features/receive/widgets/request/request_amount_model.dart';
import '../src/features/receive/widgets/request/request_amount_sheet.dart';
import '../src/features/receive/widgets/request/request_qr_surface.dart';
import 'receive_screen_use_cases.dart';
import 'receive_use_cases.dart';
import 'support/wb_layout.dart';

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

/// The densest request the flow can produce: a real software account's UA
/// (178 characters) with the 512-byte message ZIP-321 allows, which pushes
/// the symbol to 113 modules. The result step has to widen for it rather
/// than draw its modules under the scan-reliability floor.
final _denseRequest = ZecRequestView(
  address: 'u1${'q' * 176}',
  amountZec: _amountZec,
  conversionText: _fiatText,
  messageText:
      'A table booking that runs to the full five hundred and twelve bytes '
      'a ZIP-321 memo is allowed to carry, because that is exactly the '
      'request the fixed result frame could not draw. '
      '${'m' * 333}',
);

/// ZEC typed but no live price to convert it: the readout is the same
/// placeholder the send composer shows, and the unit switch is inert.
const _priceUnavailableRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: _amountZec,
);

/// A number the chain cannot hold: more ZEC than will ever exist.
const _overSupplyRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: '',
  amountDisplayText: '25000000',
  conversionText: _fiatText,
  amountError: kRequestAmountSupplyError,
);

/// Not a decimal number at all — the backstop for the paths the field's own
/// formatters do not cover, such as a controller written to programmatically.
const _formatErrorRequest = ZecRequestView(
  address: _shieldedAddress,
  amountZec: '',
  amountDisplayText: '0.5.1',
  conversionText: _fiatText,
  amountError: kRequestAmountFormatError,
);

// ─── Knob-driven fixture ─────────────────────────────────────────────

/// The request states the fixtures above describe, as one knob axis.
///
/// Every option is one of the `ZecRequestView` constants; the gallery pairs
/// it with a layout and a step, and the `build*UseCase` functions below are
/// the combinations figma_compare and the tests bind to.
enum ReceiveRequestFixture {
  empty,
  amount,
  amountInUsd,
  priceUnavailable,
  amountAndMessage,
  transparentAddress,
  amountError,
  amountOverSupply,
  amountFormatError,
  denseMessage,
}

/// Renders one request state on the [layout]'s surface at [step].
///
/// [amountFocused] only reaches the desktop card: the mobile compose step
/// draws a static serif amount unless the live sheet hands it a controller.
Widget receiveRequestFixture({
  required WbLayout layout,
  required RequestModalStep step,
  required ReceiveRequestFixture fixture,
  bool messageExpanded = false,
  bool amountFocused = false,
  Widget? background,
}) {
  final request = receiveRequestView(fixture);
  // Price-unavailable is the only state whose unit toggle is inert.
  final toggleEnabled = fixture != ReceiveRequestFixture.priceUnavailable;
  if (layout == WbLayout.desktop) {
    return _desktop(
      request,
      step: step,
      messageExpanded: messageExpanded,
      toggleEnabled: toggleEnabled,
      amountFocused: amountFocused,
      background: background,
    );
  }
  return step == RequestModalStep.compose
      ? _mobileCompose(
          request,
          toggleEnabled: toggleEnabled,
          messageExpanded: messageExpanded,
          background: background,
        )
      : _mobileResult(request, background: background);
}

/// The live receive surface the modal opens over.
///
/// Production stacks the request surface on the receive pane itself, so the
/// pane stays visible under the scrim; passing no background leaves the flat
/// window colour the figma scenarios are captured on. The desktop screen is
/// gated to the desktop token lane: it overflows against the mobile set.
Widget receiveRequestPaneBackground(WbLayout layout) {
  return layout == WbLayout.desktop
      ? const WbLaneOnly(
          layout: WbLayout.desktop,
          child: _DesktopReceiveBackground(),
        )
      : receiveMobileScreenFixture(type: ReceiveAddressType.shielded);
}

/// Const wrapper so [receiveRequestPaneBackground] can stay a const gate.
class _DesktopReceiveBackground extends StatelessWidget {
  const _DesktopReceiveBackground();

  @override
  Widget build(BuildContext context) => receiveDesktopScreenFixture();
}

/// The payload a request state's QR encodes, so a standalone code is measured
/// against the same URI the result step draws.
String receiveRequestQrData(ReceiveRequestFixture fixture) =>
    receiveRequestView(fixture).qrData;

/// The request view behind a [ReceiveRequestFixture] option.
ZecRequestView receiveRequestView(ReceiveRequestFixture fixture) {
  return switch (fixture) {
    ReceiveRequestFixture.empty => _emptyRequest,
    ReceiveRequestFixture.amount => _amountRequest,
    ReceiveRequestFixture.amountInUsd => _usdRequest,
    ReceiveRequestFixture.priceUnavailable => _priceUnavailableRequest,
    ReceiveRequestFixture.amountAndMessage => _amountWithMessageRequest,
    ReceiveRequestFixture.transparentAddress => _transparentRequest,
    ReceiveRequestFixture.amountError => _amountErrorRequest,
    ReceiveRequestFixture.amountOverSupply => _overSupplyRequest,
    ReceiveRequestFixture.amountFormatError => _formatErrorRequest,
    ReceiveRequestFixture.denseMessage => _denseRequest,
  };
}

Widget _desktopCase(ReceiveRequestFixture fixture, RequestModalStep step) =>
    receiveRequestFixture(
      layout: WbLayout.desktop,
      step: step,
      fixture: fixture,
      // The desktop card is the only surface that opens the editor by itself,
      // and only for the state whose message is what it is showing.
      messageExpanded:
          step == RequestModalStep.compose &&
          fixture == ReceiveRequestFixture.amountAndMessage,
    );

Widget _mobileCase(ReceiveRequestFixture fixture, RequestModalStep step) =>
    receiveRequestFixture(
      layout: WbLayout.mobile,
      step: step,
      fixture: fixture,
    );

// ─── Desktop ─────────────────────────────────────────────────────────

Widget buildRequestModalStepOnePriceUnavailableUseCase(BuildContext context) =>
    _desktopCase(
      ReceiveRequestFixture.priceUnavailable,
      RequestModalStep.compose,
    );

Widget buildRequestModalStepOneMessageUseCase(BuildContext context) =>
    _desktopCase(
      ReceiveRequestFixture.amountAndMessage,
      RequestModalStep.compose,
    );

Widget buildRequestModalStepTwoShieldedUseCase(BuildContext context) =>
    _desktopCase(
      ReceiveRequestFixture.amountAndMessage,
      RequestModalStep.result,
    );

Widget buildRequestModalStepTwoDenseUseCase(BuildContext context) =>
    _desktopCase(ReceiveRequestFixture.denseMessage, RequestModalStep.result);

// ─── Mobile ──────────────────────────────────────────────────────────

Widget buildRequestMobileComposePriceUnavailableUseCase(BuildContext context) =>
    _mobileCase(
      ReceiveRequestFixture.priceUnavailable,
      RequestModalStep.compose,
    );

Widget buildRequestMobileComposeMessageUseCase(BuildContext context) =>
    _mobileCase(
      ReceiveRequestFixture.amountAndMessage,
      RequestModalStep.compose,
    );

Widget buildRequestMobileComposeAmountErrorUseCase(BuildContext context) =>
    _mobileCase(ReceiveRequestFixture.amountError, RequestModalStep.compose);

Widget buildRequestMobileResultShieldedUseCase(BuildContext context) =>
    _mobileCase(
      ReceiveRequestFixture.amountAndMessage,
      RequestModalStep.result,
    );

Widget buildRequestModalStepOneEmptyUseCase(BuildContext context) =>
    _desktopCase(ReceiveRequestFixture.empty, RequestModalStep.compose);

Widget buildRequestModalStepOneAmountUseCase(BuildContext context) =>
    _desktopCase(ReceiveRequestFixture.amount, RequestModalStep.compose);

Widget buildRequestModalStepOneTransparentUseCase(BuildContext context) =>
    _desktopCase(
      ReceiveRequestFixture.transparentAddress,
      RequestModalStep.compose,
    );

Widget buildRequestModalStepOneAmountErrorUseCase(BuildContext context) =>
    _desktopCase(ReceiveRequestFixture.amountError, RequestModalStep.compose);

Widget buildRequestModalStepTwoTransparentUseCase(BuildContext context) =>
    _desktopCase(
      ReceiveRequestFixture.transparentAddress,
      RequestModalStep.result,
    );

Widget buildRequestMobileComposeEmptyUseCase(BuildContext context) =>
    _mobileCase(ReceiveRequestFixture.empty, RequestModalStep.compose);

Widget buildRequestMobileComposeUsdUseCase(BuildContext context) =>
    _mobileCase(ReceiveRequestFixture.amountInUsd, RequestModalStep.compose);

Widget buildRequestMobileResultTransparentUseCase(BuildContext context) =>
    _mobileCase(
      ReceiveRequestFixture.transparentAddress,
      RequestModalStep.result,
    );

Widget buildRequestMobileEntryUseCase(BuildContext context) =>
    buildReceiveMobileShieldedUseCase(context);

// ─── Frames ──────────────────────────────────────────────────────────

Widget _desktop(
  ZecRequestView request, {
  RequestModalStep step = RequestModalStep.compose,
  bool messageExpanded = false,
  bool toggleEnabled = true,
  bool amountFocused = false,
  Widget? background,
}) {
  final surface = RequestAmountSurface(
    request: request,
    step: step,
    messageExpanded: messageExpanded,
    // Production hands the surface an empty background and stacks the live
    // pane behind it, so the scrim is confined to the pane.
    background: background == null ? null : const SizedBox.expand(),
    onClose: _noop,
    onNext: _noop,
    onBack: _noop,
    onCopyLink: _noop,
    onSaveQrImage: _logPng('save QR image'),
    onAddMessage: _noop,
    onToggleAmountUnit: toggleEnabled ? _noop : null,
  );
  final modal = amountFocused ? _FocusAmountField(child: surface) : surface;
  if (background == null) {
    const size = Size(
      AppWindowSizing.contentAreaMaxWidth + AppSpacing.xl2,
      720,
    );
    return WbScaleDownBox(size: size, child: _frame(size, modal));
  }
  // The live receive screen needs the whole window it draws its shell in, and
  // the modal sits in the pane rect the shell leaves beside the sidebar — so
  // the sidebar stays outside the scrim, as it does in production.
  const windowSize = Size(kWbDesktopWindowWidth, kReceiveScreenWindowHeight);
  return WbScaleDownBox(
    size: windowSize,
    child: _frame(
      windowSize,
      Stack(
        fit: StackFit.expand,
        children: [
          background,
          Padding(
            padding: EdgeInsets.only(
              left: appDesktopPaneLeftInset(kAppDesktopSidebarWidth),
              top: kAppDesktopShellMargin,
              right: kAppDesktopShellMargin,
              bottom: kAppDesktopShellMargin,
            ),
            child: modal,
          ),
        ],
      ),
    ),
  );
}

Widget _mobileCompose(
  ZecRequestView request, {
  bool toggleEnabled = true,
  bool messageExpanded = false,
  Widget? background,
}) {
  // Phone box only: `scaleDown` fits a shorter canvas and stays scale 1.0 at
  // the 393×852 capture viewport. The desktop `_frame` sizes stay untouched.
  return WbScaleDownBox(
    size: const Size(393, 852),
    child: _frame(
      const Size(393, 852),
      RequestAmountSheetSurface(
        background: background,
        child: RequestAmountSheetCompose(
          request: request,
          messageExpanded: messageExpanded,
          onClose: _noop,
          onToggleAmountUnit: toggleEnabled ? _noop : null,
          onAddMessage: _noop,
          onCreateRequest: _noop,
        ),
      ),
    ),
  );
}

Widget _mobileResult(ZecRequestView request, {Widget? background}) {
  return WbScaleDownBox(
    size: const Size(393, 852),
    child: _frame(
      const Size(393, 852),
      RequestAmountSheetSurface(
        background: background,
        child: RequestAmountSheetResult(
          request: request,
          onBack: _noop,
          onClose: _noop,
          onShareRequest: (png) =>
              debugPrint('request: share ${png.length} byte PNG'),
          onCopyLink: _noop,
        ),
      ),
    ),
  );
}

// ─── Request components ──────────────────────────────────────────────

/// The two sides production gives the request code.
///
/// Only the mobile sheet's is under what a 512-byte message needs, which is
/// where the surface's growth is visible.
enum RequestQrPreviewSize { desktopModal, mobileSheet }

/// The QR block on its own, in a frame roomy enough that the code is drawn at
/// the side it asks for rather than the one the frame allows.
Widget requestQrSurfaceFixture({
  required String data,
  RequestQrPreviewSize size = RequestQrPreviewSize.desktopModal,
}) {
  return Center(
    child: SizedBox.fromSize(
      size: const Size.square(480),
      child: Center(
        child: RequestQrSurface(
          data: data,
          size: size == RequestQrPreviewSize.desktopModal
              ? kRequestModalQrSize
              : kRequestSheetQrSize,
          padding: AppSpacing.sm,
        ),
      ),
    ),
  );
}

/// The two call sites of [RequestQrExportButton].
enum RequestQrExportAction { saveImage, shareRequest }

/// One export button with the props its call site passes.
///
/// [enabled] seeds the disabled state the way the flow reaches it: before a
/// request exists there is no URI to encode and nothing to hand the bytes to.
Widget requestQrExportButtonFixture({
  required RequestQrExportAction action,
  bool enabled = true,
}) {
  final save = action == RequestQrExportAction.saveImage;
  return _cardWidthFrame(
    RequestQrExportButton(
      uri: enabled ? _amountRequest.requestUri : null,
      label: save ? 'Save QR image' : 'Share request',
      icon: save ? AppIcons.arrowDownCircle : AppIcons.share,
      variant: save ? AppButtonVariant.secondary : AppButtonVariant.primary,
      onBytes: enabled ? _logPng(save ? 'save QR image' : 'share') : null,
    ),
  );
}

/// The prop-driven rows the two request steps are assembled from.
enum RequestAmountRowCase {
  amountField,
  amountError,
  addMessage,
  messageField,
  header,
}

/// One compose row at the width the desktop modal gives it.
Widget requestAmountRowFixture({
  required RequestAmountRowCase row,
  bool amountInUsd = false,
  String errorText = kRequestAmountDecimalsError,
}) {
  return _cardWidthFrame(switch (row) {
    RequestAmountRowCase.amountField => RequestAmountField(
      request: amountInUsd ? _usdRequest : _amountRequest,
      onToggleUnit: _noop,
    ),
    RequestAmountRowCase.amountError => RequestAmountErrorRow(text: errorText),
    RequestAmountRowCase.addMessage => RequestAddMessageCard(onTap: _noop),
    RequestAmountRowCase.messageField => RequestMessageField(
      text: _message,
      onClose: _noop,
    ),
    RequestAmountRowCase.header => RequestModalHeader(
      onBack: _noop,
      onClose: _noop,
    ),
  });
}

/// Components are reviewed at the width the modal card gives them, since that
/// is the only width their wrapping and truncation were tuned against.
Widget _cardWidthFrame(Widget child) {
  return Center(
    child: SizedBox(width: kRequestModalCardWidth, child: child),
  );
}

/// Focuses the amount field once the surface is mounted.
///
/// [RequestAmountSurface] composes the card itself, so the card's own
/// `amountFocused` prop cannot be reached from outside it; focusing the real
/// field is the state a user's first click leaves behind anyway.
class _FocusAmountField extends StatefulWidget {
  const _FocusAmountField({required this.child});

  final Widget child;

  @override
  State<_FocusAmountField> createState() => _FocusAmountFieldState();
}

class _FocusAmountFieldState extends State<_FocusAmountField> {
  static const _amountFieldKey = ValueKey('request_amount_field');
  static const _maxFrames = 10;

  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _focusWhenFieldExists();
  }

  /// The field's focus node only exists once the text field is mounted, so
  /// re-arm until it is there.
  void _focusWhenFieldExists() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _amountFocusNode(context);
      if (node != null) {
        node.requestFocus();
        return;
      }
      if (++_frames >= _maxFrames) return;
      _focusWhenFieldExists();
    });
  }

  FocusNode? _amountFocusNode(BuildContext root) {
    Element? field;
    void findField(Element element) {
      if (field != null) return;
      if (element.widget.key == _amountFieldKey) {
        field = element;
        return;
      }
      element.visitChildElements(findField);
    }

    root.visitChildElements(findField);

    FocusNode? node;
    void findEditable(Element element) {
      if (node != null) return;
      final candidate = element.widget;
      if (candidate is EditableText) {
        node = candidate.focusNode;
        return;
      }
      element.visitChildElements(findEditable);
    }

    field?.visitChildElements(findEditable);
    return node;
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
