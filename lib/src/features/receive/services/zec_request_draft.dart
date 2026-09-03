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
    this.usdModeZecInput = '',
    this.usdInputIsDerived = false,
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

  /// The canonical ZEC text behind a USD-mode field.
  ///
  /// In ZEC mode the field itself is canonical and this is ignored; in USD
  /// mode it is the last ZEC value the typed dollars converted to. It exists
  /// so leaving USD mode does not need a price: the live price can expire
  /// while the composer is open, and a unit switch that answers that by
  /// erasing the number the user typed is worse than the stale unit was.
  /// The desktop send composer keeps `_amountText` alive across the same
  /// switch for the same reason.
  final String usdModeZecInput;

  /// True while the USD field shows a number the draft wrote there itself —
  /// the ZEC amount converted on a unit switch — rather than one the user
  /// typed.
  ///
  /// The distinction decides what the request means. Dollars the user typed
  /// are the amount, and the ZEC they buy floats with the live price until
  /// the request is created. Dollars the switch derived are only a rendering
  /// of the ZEC the user typed, rounded to a cent, so the request keeps that
  /// ZEC exactly rather than converting the rounding back. The first
  /// keystroke on the USD field ends the derived state.
  final bool usdInputIsDerived;

  ZecRequestDraft copyWith({
    String? address,
    String? input,
    bool? inputIsUsd,
    String? message,
    String? usdModeZecInput,
    bool? usdInputIsDerived,
    bool clearMessage = false,
  }) {
    return ZecRequestDraft(
      address: address ?? this.address,
      input: input ?? this.input,
      inputIsUsd: inputIsUsd ?? this.inputIsUsd,
      usdModeZecInput: usdModeZecInput ?? this.usdModeZecInput,
      usdInputIsDerived: usdInputIsDerived ?? this.usdInputIsDerived,
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

  /// The ZEC value a switch back to ZEC mode would restore.
  String get zecInput => inputIsUsd ? usdModeZecInput : input.trim();

  /// The same draft with [value] in the field and the canonical ZEC value
  /// kept in step with it.
  ///
  /// Every keystroke goes through here rather than through `copyWith` so USD
  /// mode always carries the ZEC it last meant. A keystroke typed while the
  /// price is missing cannot be converted, so it leaves the previous
  /// canonical value standing — clearing the field is the one thing that
  /// clears it too.
  ZecRequestDraft withInput(String value, {required double? zecUsdUnitPrice}) {
    if (!inputIsUsd) {
      return copyWith(input: value, usdModeZecInput: '');
    }
    final zatoshi = sendZatoshiFromUsdText(value, zecUsdUnitPrice);
    if (zatoshi != null) {
      return copyWith(
        input: value,
        usdModeZecInput: ZecAmount.fromZatoshi(zatoshi).pretty().amountText,
        usdInputIsDerived: false,
      );
    }
    return copyWith(
      input: value,
      usdModeZecInput: value.trim().isEmpty ? '' : usdModeZecInput,
      usdInputIsDerived: false,
    );
  }

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
      // Dollars the switch itself wrote are a rounding of the ZEC the user
      // typed (0.5 ZEC at $35.123 shows as $17.56, which converts back to
      // 0.49995729), so the switch back restores that ZEC rather than the
      // rounding. Dollars the user typed convert at the live price; without
      // one, the switch restores the ZEC the draft has been carrying rather
      // than emptying the field.
      final converted = _convertedZec(zecUsdUnitPrice);
      final next = usdInputIsDerived || converted.isEmpty
          ? usdModeZecInput
          : converted;
      return copyWith(
        inputIsUsd: false,
        input: next,
        usdModeZecInput: '',
        usdInputIsDerived: false,
      );
    }

    final zatoshi = parseZecAmount(input.trim());
    return copyWith(
      inputIsUsd: true,
      input: zatoshi == null || zatoshi <= BigInt.zero
          ? ''
          : sendSendableUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice!),
      usdModeZecInput: input.trim(),
      usdInputIsDerived: true,
    );
  }

  /// The canonical ZEC amount this draft encodes, empty when there is not one
  /// yet. In ZEC mode it is what was typed. In USD mode it is what the
  /// dollars in the field mean: typed dollars convert at [zecUsdUnitPrice],
  /// dollars a unit switch derived stand for the ZEC that was typed before
  /// it ([usdModeZecInput]), so that merely switching units never changes
  /// the request — the field shows a cent rounding, and converting *that*
  /// back would encode a payment a few zatoshi away from the typed one.
  String amountZec({required double? zecUsdUnitPrice}) {
    if (!inputIsUsd) return input.trim();
    final converted = _convertedZec(zecUsdUnitPrice);
    if (converted.isEmpty) return '';
    return usdInputIsDerived && usdModeZecInput.isNotEmpty
        ? usdModeZecInput
        : converted;
  }

  /// [input] converted from dollars at [zecUsdUnitPrice], empty when it does
  /// not convert.
  String _convertedZec(double? zecUsdUnitPrice) {
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
