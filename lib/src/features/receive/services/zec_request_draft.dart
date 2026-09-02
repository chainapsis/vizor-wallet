/// The editable half of the "Request ZEC" flow.
///
/// [ZecRequestView] is what the widgets draw; this is what the screen holds
/// while the user is still typing. Keeping the two apart is what lets the
/// desktop modal and the mobile sheet share one set of rules — which unit the
/// field is collecting, what the other-unit line says, and when an amount is
/// wrong — without either screen re-deriving them.
///
/// Pure: no providers, no widgets. The live ZEC/USD price is passed in, so a
/// missing price is an argument rather than a hidden dependency.
library;

import 'package:flutter/foundation.dart';

import '../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/zcash/zip321_payment_request_builder.dart';
import '../../../core/zcash/zip321_payment_request.dart'
    show stripUnsupportedZip321MemoText;
import '../../send/services/send_amount_conversion.dart';
import '../widgets/request/request_amount_model.dart';

/// True when [zecUsdUnitPrice] can actually convert an amount.
bool zecRequestPriceIsUsable(double? zecUsdUnitPrice) =>
    zecUsdUnitPrice != null && zecUsdUnitPrice.isFinite && zecUsdUnitPrice > 0;

@immutable
class ZecRequestDraft {
  const ZecRequestDraft({
    required this.address,
    this.input = '',
    this.inputIsUsd = false,
    this.message,
  });

  /// The address the request pays to, snapshotted when the flow opened: a
  /// shielded address the user renews mid-flow must not silently repoint a
  /// link they are about to hand out.
  final String address;

  /// Raw field text, in whichever unit [inputIsUsd] says.
  final String input;

  /// True while the field is collecting USD.
  final bool inputIsUsd;

  /// The optional encrypted memo, shielded addresses only.
  final String? message;

  ZecRequestDraft copyWith({
    String? address,
    String? input,
    bool? inputIsUsd,
    String? message,
    bool clearMessage = false,
  }) {
    return ZecRequestDraft(
      address: address ?? this.address,
      input: input ?? this.input,
      inputIsUsd: inputIsUsd ?? this.inputIsUsd,
      // Invisible bidi/control characters cannot travel in a ZIP-321 memo,
      // so they are dropped at the input boundary; the visible text is
      // unchanged and the request the composer hands out always parses.
      message: clearMessage
          ? null
          : (message == null
                ? this.message
                : stripUnsupportedZip321MemoText(message)),
    );
  }

  bool get isShielded => !zip321AddressIsTransparent(address);

  /// Whether the unit switch can be taken. USD mode needs a live price; ZEC
  /// mode always works, so a price that disappears never traps the field in a
  /// unit it can no longer convert.
  bool canToggleUnit(double? zecUsdUnitPrice) =>
      inputIsUsd || zecRequestPriceIsUsable(zecUsdUnitPrice);

  /// The same draft with the units swapped and [input] rewritten in the new
  /// unit, so the number on screen keeps meaning what it meant.
  ZecRequestDraft toggledUnit({required double? zecUsdUnitPrice}) {
    if (!canToggleUnit(zecUsdUnitPrice)) return this;

    if (inputIsUsd) {
      final zatoshi = sendZatoshiFromUsdText(input, zecUsdUnitPrice);
      return copyWith(
        inputIsUsd: false,
        input: zatoshi == null
            ? ''
            : ZecAmount.fromZatoshi(zatoshi).pretty().amountText,
      );
    }

    final zatoshi = parseZecAmount(input.trim());
    return copyWith(
      inputIsUsd: true,
      input: zatoshi == null || zatoshi <= BigInt.zero
          ? ''
          : sendSendableUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice!),
    );
  }

  /// The canonical ZEC amount this draft encodes, empty when there is not one
  /// yet. In USD mode it is converted at [zecUsdUnitPrice]; in ZEC mode it is
  /// what was typed.
  String amountZec({required double? zecUsdUnitPrice}) {
    if (!inputIsUsd) return input.trim();
    final zatoshi = sendZatoshiFromUsdText(input, zecUsdUnitPrice);
    if (zatoshi == null) return '';
    return ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
  }

  /// Everything the request widgets draw for this draft.
  ZecRequestView resolve({required double? zecUsdUnitPrice}) {
    final amount = amountZec(zecUsdUnitPrice: zecUsdUnitPrice);
    return ZecRequestView(
      address: address,
      amountZec: amount,
      amountDisplayText: input,
      amountInputIsUsd: inputIsUsd,
      conversionText: _conversionText(
        amountZec: amount,
        zecUsdUnitPrice: zecUsdUnitPrice,
      ),
      messageText: message,
      amountError: _amountError(amount),
    );
  }

  /// The other-unit line under the field.
  ///
  /// Null means "not known yet" — in ZEC mode with an amount typed and no
  /// live price, the widget shows its price-unavailable placeholder rather
  /// than a converted number nobody can vouch for.
  String? _conversionText({
    required String amountZec,
    required double? zecUsdUnitPrice,
  }) {
    if (inputIsUsd) {
      final zecText = amountZec.isEmpty ? '0' : amountZec;
      return '$zecText $kZcashDefaultCurrencyTicker';
    }

    final zatoshi = parseZecAmount(amountZec);
    if (zatoshi == null || zatoshi <= BigInt.zero) return r'$ 0';
    if (!zecRequestPriceIsUsable(zecUsdUnitPrice)) return null;
    return r'$ ' + sendUsdDisplayTextForZatoshi(zatoshi, zecUsdUnitPrice!);
  }

  /// Inline amount error, or null.
  ///
  /// A half-typed number ("0.", "0", "") is not an error, it is an amount
  /// that is not finished, and the flow already refuses to build a URI from
  /// it. Anything else the builder refuses is said out loud: without that, an
  /// amount the conversion line happily prices leaves "Create request"
  /// disabled with nothing on screen accounting for it.
  String? _amountError(String amountZec) {
    final raw = amountZec.trim();
    if (raw.isEmpty) return null;
    try {
      normalizeZip321Amount(raw);
      return null;
    } on Zip321BuildException catch (e) {
      return switch (e.kind) {
        Zip321BuildErrorKind.amountDecimals => kRequestAmountDecimalsError,
        Zip321BuildErrorKind.amountSupply => kRequestAmountSupplyError,
        // `amountFormat` covers two unrelated rejections: a number still
        // being typed, and text that is not a number. Only the second is
        // something the user can be asked to correct.
        Zip321BuildErrorKind.amountFormat =>
          _amountIsUnfinished(raw) ? null : kRequestAmountFormatError,
        _ => null,
      };
    }
  }
}

/// The grammar `normalizeZip321Amount` accepts, so text that matches it can
/// only have been refused for being zero.
final _plainDecimal = RegExp(r'^[0-9]+(?:\.[0-9]*)?$');

/// True while [amount] is a number the builder refuses only because it is not
/// a positive one *yet*: "0", "0.", "0.00", and the lone separator a field
/// passes through on the way to "0.5".
///
/// `.5` is deliberately not on this list. It is a finished number the field's
/// formatters would have completed to `0.5`, so reaching the draft in that
/// shape means something bypassed them — and the builder's refusal of it is
/// exactly what the user needs told.
bool _amountIsUnfinished(String amount) =>
    amount.isEmpty || amount == '.' || _plainDecimal.hasMatch(amount);
