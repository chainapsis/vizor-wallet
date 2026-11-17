/// The live mobile "Request ZEC" page: the two presentation steps with the
/// state, clipboard and share sheet behind them.
///
/// The page owns the draft rather than the Receive screen, so leaving it is
/// the only way to discard a half-typed request and nothing about it survives
/// into the screen underneath.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_memo_sheet.dart';
import '../../../../core/zcash/zip321_payment_request.dart'
    show stripUnsupportedZip321MemoText;
import '../../../../providers/account_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../services/request_qr_export.dart';
import '../../services/zec_request_draft.dart';
import '../../widgets/request/request_amount_model.dart';
import '../../widgets/request/request_amount_steps.dart';

/// Route of the request page. It takes the address as its `extra`.
const kReceiveRequestPath = '/receive/request';

/// Opens the request page for [address].
///
/// The address is snapshotted by the caller at the moment the page opens: a
/// renewed shielded address, or a swipe to the other pool behind the page,
/// must not repoint a link the user is in the middle of handing out.
Future<void> openReceiveRequest(
  BuildContext context, {
  required String address,
}) {
  return context.push<void>(kReceiveRequestPath, extra: address);
}

/// Opens the request page for the active account's shielded address, the
/// address the Receive screen opens on. Used where no Receive screen is open,
/// such as the mobile Home Receive sheet.
Future<void> openActiveAccountReceiveRequest(
  BuildContext context,
  WidgetRef ref,
) async {
  final accountState = ref.read(accountProvider).value;
  final accountUuid = accountState?.activeAccountUuid;
  if (accountUuid == null) return;
  var address = '';
  try {
    address = await ref
        .read(receiveAddressServiceProvider)
        .loadShieldedAddress(
          accountUuid: accountUuid,
          currentShieldedAddress: accountState?.activeAddress,
        );
  } catch (e) {
    log('ReceiveRequest: ERROR loading shielded address: $e');
  }
  if (!context.mounted) return;
  if (address.isEmpty) {
    showAppToast(context, context.l10n.receiveShieldedAddressLoadFailed);
    return;
  }
  await openReceiveRequest(context, address: address);
}

class MobileReceiveRequestScreen extends ConsumerStatefulWidget {
  const MobileReceiveRequestScreen({required this.address, super.key});

  final String address;

  @override
  ConsumerState<MobileReceiveRequestScreen> createState() =>
      _MobileReceiveRequestScreenState();
}

class _MobileReceiveRequestScreenState
    extends ConsumerState<MobileReceiveRequestScreen> {
  late ZecRequestDraft _draft = ZecRequestDraft(address: widget.address);

  /// The request as it was when the user pressed Create. The result step
  /// renders this snapshot, not the live draft: a USD request converts at the
  /// live price, and a price tick after the user confirmed must not rewrite
  /// the QR they are already showing someone.
  ZecRequestView? _result;
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  bool _showsResult = false;

  @override
  void initState() {
    super.initState();
    // Raise the keyboard after the page has opened, not during its entrance
    // (the helper waits for any route's entrance, not only a sheet's).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusWhenMobileSheetOpens(context, _amountFocusNode);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/receive');
    }
  }

  void _handleAmountChanged(String value) {
    // Through the draft's own setter, not `copyWith`: in USD mode it also
    // records the ZEC the dollars currently mean, so a price that expires
    // before the user switches back does not take the amount with it.
    setState(
      () => _draft = _draft.withInput(
        value,
        zecUsdUnitPrice: ref.read(zecLiveUsdUnitPriceProvider),
      ),
    );
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

  /// Opens Send's message sheet for the request's memo.
  ///
  /// The sheet drops the characters a ZIP-321 memo cannot carry as they are
  /// typed, so the field, its byte counter and the link are the same string.
  /// It pops null when cancelled and an empty string when the message was
  /// cleared.
  Future<void> _editMessage() async {
    final l10n = context.l10n;
    final next = await showMobileMemoSheet(
      context,
      initial: _draft.message ?? '',
      title: l10n.commonAddAMessage,
      hintText: l10n.receiveRequestMessageHint,
      clearLabel: l10n.commonClear,
      sanitize: stripUnsupportedZip321MemoText,
    );
    if (next == null || !mounted) return;
    setState(
      () => _draft = next.isEmpty
          ? _draft.copyWith(clearMessage: true)
          : _draft.copyWith(message: next),
    );
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

  /// Both hand-offs are fired with `unawaited`, so a throw would otherwise be
  /// an unhandled zone error: the user presses the button and nothing at all
  /// happens, which reads exactly like a share they have not made yet. Each
  /// failure names the other hand-off, which is still one tap away.
  Future<void> _copyLink(String uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri));
      unawaited(AppHaptics.copy());
    } catch (e) {
      log('ReceiveRequest: ERROR copying request link: $e');
      if (!mounted) return;
      showAppToast(
        context,
        context.l10n.receiveRequestCopyFailed,
        iconName: AppIcons.cancel,
        tone: AppToastTone.destructive,
      );
      return;
    }
    if (!mounted) return;
    showAppToast(context, context.l10n.receiveRequestLinkCopied);
  }

  Future<void> _share(Uint8List png) async {
    try {
      await ref.read(requestShareHandlerProvider)(
        png: png,
        fileName: kRequestQrShareFileName,
      );
    } catch (e) {
      log('ReceiveRequest: ERROR sharing request: $e');
      _reportShareFailed();
    }
  }

  /// The same sentence whether the share sheet refused the request or the QR
  /// never encoded: from where the user is standing they pressed Share and
  /// nothing left the app, and the link is still one tap away.
  void _reportShareFailed() {
    if (!mounted) return;
    showAppToast(
      context,
      context.l10n.receiveRequestShareFailed,
      iconName: AppIcons.cancel,
      tone: AppToastTone.destructive,
    );
  }

  void _backToCompose() {
    setState(() {
      _result = null;
      _showsResult = false;
    });
    // The compose field focused itself when it returned; the page is
    // already open, so focus it straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final zecUsdUnitPrice = ref.watch(zecLiveUsdUnitPriceProvider);
    final request = _draft.resolve(zecUsdUnitPrice: zecUsdUnitPrice);
    final onToggleUnit = _draft.canToggleUnit(zecUsdUnitPrice)
        ? _toggleAmountUnit
        : null;

    final Widget step;
    if (!_showsResult) {
      step = RequestAmountComposeStep(
        request: request,
        amountController: _amountController,
        amountFocusNode: _amountFocusNode,
        onAmountChanged: _handleAmountChanged,
        onToggleAmountUnit: onToggleUnit,
        onAddMessage: () => unawaited(_editMessage()),
        onCreateRequest: _createRequest,
        onBack: _close,
      );
    } else {
      // The confirmed snapshot is what the result step shows, copies and
      // shares; the live draft stays behind on the compose step.
      final result = _result ?? request;
      // System Back edits the request like the header's back does, instead of
      // leaving the page and losing what was typed.
      step = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backToCompose();
        },
        child: RequestAmountResultStep(
          request: result,
          onBack: _backToCompose,
          onCopyLink: () {
            final uri = result.requestUri;
            if (uri == null) return;
            unawaited(_copyLink(uri));
          },
          // Returned, not fired: the export button stays busy until the share
          // sheet has been handed the bytes and dismissed, so a second tap
          // cannot open a second sheet over the first.
          onShareRequest: _share,
          onShareError: _reportShareFailed,
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: AppToastHost(child: SafeArea(child: step)),
    );
  }
}
