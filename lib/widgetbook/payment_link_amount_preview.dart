import 'dart:async';

import 'package:flutter/material.dart';

import '../src/core/formatting/zec_amount.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import '../src/features/payment_links/widgets/payment_link_amount_card.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/features/send/services/send_amount_conversion.dart';

const kPaymentLinkPreviewUsdPrice = 250.0;

/// Shared deterministic amount composer, without wallet or pricing providers.
class PaymentLinkAmountPreview extends StatefulWidget {
  const PaymentLinkAmountPreview({
    this.initialAmount = '0.2',
    this.initialCurrency = PaymentLinkAmountCurrency.zec,
    this.initialArtwork = PaymentLinkCardArtwork.chestLava,
    this.focusAmount = false,
    this.priceAvailable = true,
    this.priceLoading = false,
    this.priceDelay,
    this.supportingText,
    this.supportingTextIsError = false,
    this.enableContinue = true,
    this.showMax = true,
    this.onAmountChanged,
    this.onCurrencyChanged,
    this.onArtworkChanged,
    this.onContinue,
    super.key,
  });

  final String initialAmount;
  final PaymentLinkAmountCurrency initialCurrency;
  final PaymentLinkCardArtwork initialArtwork;
  final bool focusAmount;
  final bool priceAvailable;
  final bool priceLoading;
  final Duration? priceDelay;
  final String? supportingText;
  final bool supportingTextIsError;
  final bool enableContinue;
  final bool showMax;
  final ValueChanged<BigInt?>? onAmountChanged;
  final ValueChanged<PaymentLinkAmountCurrency>? onCurrencyChanged;
  final ValueChanged<PaymentLinkCardArtwork>? onArtworkChanged;
  final VoidCallback? onContinue;

  @override
  State<PaymentLinkAmountPreview> createState() =>
      _PaymentLinkAmountPreviewState();
}

class _PaymentLinkAmountPreviewState extends State<PaymentLinkAmountPreview> {
  static final _max = BigInt.from(14222980000);
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _priceTimer;
  late PaymentLinkAmountCurrency _currency;
  late PaymentLinkCardArtwork _artwork;
  BigInt? _amount;
  bool _waitingForPrice = false;

  bool get _isUsd => _currency == PaymentLinkAmountCurrency.usd;
  bool get _hasAmount => _amount != null && _amount! > BigInt.zero;
  bool get _priceLoading => widget.priceLoading || _waitingForPrice;
  bool get _priceAvailable => widget.priceAvailable && !_priceLoading;
  bool get _usdEnabled =>
      _priceAvailable &&
      (!_hasAmount ||
          sendSendableUsdInputTextForZatoshi(
            _amount!,
            kPaymentLinkPreviewUsdPrice,
          ).isNotEmpty);

  @override
  void initState() {
    super.initState();
    _currency = widget.initialCurrency;
    _artwork = widget.initialArtwork;
    _amount = parseZecAmount(widget.initialAmount);
    _updateVisibleAmount();
    _focus.addListener(_handleFocusChanged);
    if (widget.focusAmount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    if (widget.priceDelay case final delay?) {
      _waitingForPrice = true;
      _priceTimer = Timer(delay, () {
        if (mounted) setState(() => _waitingForPrice = false);
      });
    }
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _controller.dispose();
    _focus
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  void _updateVisibleAmount() {
    final amount = _amount;
    final text = amount == null
        ? ''
        : _isUsd
        ? sendUsdInputTextForZatoshi(amount, kPaymentLinkPreviewUsdPrice)
        : formatZecAmount(amount);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _changeCurrency(PaymentLinkAmountCurrency currency) {
    final wasEditing = _focus.hasFocus;
    setState(() => _currency = currency);
    _updateVisibleAmount();
    if (wasEditing) _focus.requestFocus();
    widget.onCurrencyChanged?.call(currency);
  }

  void _changeAmount(String text) {
    setState(() {
      _amount = _isUsd
          ? sendZatoshiFromUsdText(text, kPaymentLinkPreviewUsdPrice)
          : parseZecAmount(text);
    });
    widget.onAmountChanged?.call(_amount);
  }

  void _useMax() {
    setState(() {
      _amount = _max;
      _updateVisibleAmount();
    });
    _focus.requestFocus();
    widget.onAmountChanged?.call(_amount);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final conversion = _hasAmount
        ? _isUsd
              ? '≈ ${formatZecAmount(_amount!)} ZEC'
              : _priceAvailable
              ? '≈ \$${sendUsdDisplayTextForZatoshi(_amount!, kPaymentLinkPreviewUsdPrice)}'
              : null
        : null;
    final card = PaymentLinkAmountCard(
      artwork: _artwork,
      amountController: _controller,
      amountFocusNode: _focus,
      currency: _currency,
      onCurrencyChanged: _changeCurrency,
      usdEnabled: _usdEnabled,
      usdDisabledReason: _priceLoading
          ? 'Fetching USD price…'
          : !_priceAvailable
          ? 'USD price unavailable'
          : 'Amount is too small for USD input.',
      onAmountChanged: _changeAmount,
      supportingText: conversion,
      supportingLoading: _priceLoading && _hasAmount,
      maxAmountText: widget.showMax
          ? _isUsd
                ? sendUsdInputTextForZatoshi(_max, kPaymentLinkPreviewUsdPrice)
                : formatZecAmount(_max)
          : null,
      onUseMax: widget.showMax ? _useMax : null,
      cardWidth: mobile ? 361 : PaymentLinkGiftCard.width,
      cardHeight: mobile ? 225.625 : PaymentLinkGiftCard.height,
    );
    final selector = PaymentLinkCardSelectorRail(
      artworks: PaymentLinkCardArtwork.values,
      selected: _artwork,
      onSelected: (artwork) {
        setState(() => _artwork = artwork);
        widget.onArtworkChanged?.call(artwork);
      },
      width: mobile ? 393 : PaymentLinkCardSelectorRail.defaultWidth,
      itemWidth: mobile ? 80 : PaymentLinkCardSelector.width,
      itemHeight: mobile ? 60 : PaymentLinkCardSelector.height,
      artworkWidth: mobile ? 76 : 60,
      artworkHeight: mobile ? 56 : 44,
      edgeMaskInset: mobile ? AppSpacing.sm : 17,
      edgeFadeFraction: mobile ? 0.3 : 0.15,
      inactiveOpacity: mobile ? 1 : 0.5,
      loop: mobile,
    );
    final onContinue = _hasAmount && widget.enableContinue
        ? widget.onContinue ?? _noop
        : null;
    if (mobile) {
      return PaymentLinkAmountMobileView(
        card: card,
        cardSelector: selector,
        onBack: _noop,
        onContinue: onContinue,
        supportingText: widget.supportingText,
        supportingTextIsError: widget.supportingTextIsError,
      );
    }
    return PaymentLinkAmountDesktopView(
      state: !_hasAmount
          ? _focus.hasFocus
                ? PaymentLinkAmountVisualState.focused
                : PaymentLinkAmountVisualState.empty
          : _priceLoading
          ? PaymentLinkAmountVisualState.fiatLoading
          : _priceAvailable
          ? PaymentLinkAmountVisualState.fiatLoaded
          : PaymentLinkAmountVisualState.amount,
      card: card,
      cardSelector: selector,
      onBack: _noop,
      onCreate: onContinue,
      supportingText: widget.supportingText,
      supportingTextIsError: widget.supportingTextIsError,
      emptyActionLabel: widget.supportingTextIsError
          ? 'Enter amount'
          : 'Continue',
    );
  }
}

void _noop() {}
