/// The live mobile "Request ZEC" sheet: the two presentation steps with the
/// state, clipboard and share sheet behind them.
///
/// The sheet owns the draft rather than the Receive screen, so closing it is
/// the only way to discard a half-typed request and nothing about it survives
/// into the screen underneath.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../services/request_qr_export.dart';
import '../../services/zec_request_draft.dart';
import '../request/request_amount_model.dart';
import '../request/request_amount_sheet.dart';

/// Opens the request flow for [address].
///
/// The address is snapshotted by the caller at the moment the sheet opens: a
/// renewed shielded address, or a swipe to the other pool behind the sheet,
/// must not repoint a link the user is in the middle of handing out.
Future<void> showReceiveRequestSheet(
  BuildContext context, {
  required String address,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (_) => ReceiveRequestSheet(address: address),
  );
}

class ReceiveRequestSheet extends ConsumerStatefulWidget {
  const ReceiveRequestSheet({required this.address, super.key});

  final String address;

  @override
  ConsumerState<ReceiveRequestSheet> createState() =>
      _ReceiveRequestSheetState();
}

class _ReceiveRequestSheetState extends ConsumerState<ReceiveRequestSheet> {
  late ZecRequestDraft _draft = ZecRequestDraft(address: widget.address);

  /// The request as it was when the user pressed Create. The result step
  /// renders this snapshot, not the live draft: a USD request converts at the
  /// live price, and a price tick after the user confirmed must not rewrite
  /// the QR they are already showing someone.
  ZecRequestView? _result;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _showsResult = false;
  bool _messageExpanded = false;

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _handleAmountChanged(String value) {
    setState(() => _draft = _draft.copyWith(input: value));
  }

  void _handleMessageChanged(String value) {
    setState(() => _draft = _draft.copyWith(message: value));
  }

  void _toggleAmountUnit() {
    final next = _draft.toggledUnit(
      zecUsdUnitPrice: ref.read(zecLiveUsdUnitPriceProvider),
    );
    if (next.inputIsUsd == _draft.inputIsUsd) return;
    _amountController.value = TextEditingValue(
      text: next.input,
      selection: TextSelection.collapsed(offset: next.input.length),
    );
    setState(() => _draft = next);
  }

  void _expandMessage() {
    if (_messageExpanded) return;
    setState(() => _messageExpanded = true);
  }

  void _createRequest() {
    final result = _draft.resolve(
      zecUsdUnitPrice: ref.read(zecLiveUsdUnitPriceProvider),
    );
    // Guarded on the same `isReady` the button is disabled by.
    if (!result.isReady) return;
    // The keypad has nothing left to do on the result step, and the QR needs
    // the room it was taking.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _result = result;
      _showsResult = true;
    });
  }

  Future<void> _copyLink(String uri) async {
    await Clipboard.setData(ClipboardData(text: uri));
    if (!mounted) return;
    showAppToast(context, kRequestLinkCopiedToast);
  }

  Future<void> _share(String text, Uint8List png) async {
    await ref.read(requestShareHandlerProvider)(
      text: text,
      png: png,
      fileName: kRequestQrShareFileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final zecUsdUnitPrice = ref.watch(zecLiveUsdUnitPriceProvider);
    final request = _draft.resolve(zecUsdUnitPrice: zecUsdUnitPrice);
    final onToggleUnit = _draft.canToggleUnit(zecUsdUnitPrice)
        ? _toggleAmountUnit
        : null;

    if (!_showsResult) {
      return RequestAmountSheetCompose(
        request: request,
        amountController: _amountController,
        messageController: _messageController,
        messageExpanded: _messageExpanded,
        onAmountChanged: _handleAmountChanged,
        onMessageChanged: _handleMessageChanged,
        onToggleAmountUnit: onToggleUnit,
        onAddMessage: _expandMessage,
        onCreateRequest: _createRequest,
        onClose: _close,
      );
    }

    return RequestAmountSheetResult(
      request: _result ?? request,
      onBack: () => setState(() {
        _result = null;
        _showsResult = false;
      }),
      onClose: _close,
      onCopyLink: () {
        final uri = request.requestUri;
        if (uri == null) return;
        unawaited(_copyLink(uri));
      },
      onShareRequest: (text, png) => unawaited(_share(text, png)),
    );
  }
}
