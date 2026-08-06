import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../widgets/payment_link_card_selector_rail.dart';
import '../widgets/payment_link_desktop_views.dart';
import '../widgets/payment_link_gift_card.dart';

enum _PaymentLinksLocalPage { home, amount, message, review, redeem }

/// Temporary desktop entry for reviewing the Payment Links presentation flow.
///
/// The screen deliberately owns only local UI state. It does not create,
/// claim, reclaim, persist, or broadcast payment links; transaction actions
/// stay disabled until their lifecycle states are connected.
class PaymentLinksDesktopScreen extends ConsumerStatefulWidget {
  const PaymentLinksDesktopScreen({super.key});

  @override
  ConsumerState<PaymentLinksDesktopScreen> createState() =>
      _PaymentLinksDesktopScreenState();
}

class _PaymentLinksDesktopScreenState
    extends ConsumerState<PaymentLinksDesktopScreen> {
  static final _amountFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final isNumericAmount = RegExp(
      r'^(?:\d+(?:\.\d{0,8})?|\.\d{0,8})?$',
    ).hasMatch(newValue.text);
    return isNumericAmount ? newValue : oldValue;
  });

  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();

  _PaymentLinksLocalPage _page = _PaymentLinksLocalPage.home;
  PaymentLinkCardArtwork _selectedArtwork = PaymentLinkCardArtwork.gift;
  bool _showHelp = false;
  bool _amountFocused = false;

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(_handleAmountFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    _amountFocusNode
      ..removeListener(_handleAmountFocus)
      ..dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _handleAmountFocus() {
    if (_amountFocused == _amountFocusNode.hasFocus) return;
    setState(() => _amountFocused = _amountFocusNode.hasFocus);
  }

  void _showPage(_PaymentLinksLocalPage page) {
    _amountFocusNode.unfocus();
    setState(() {
      _page = page;
      _showHelp = false;
    });
  }

  void _showHelpOverlay() => setState(() => _showHelp = true);

  void _hideHelpOverlay() => setState(() => _showHelp = false);

  bool get _hasPositiveAmount {
    final value = _amountController.text;
    final amount = double.tryParse(value.startsWith('.') ? '0$value' : value);
    return amount != null && amount > 0;
  }

  String? get _displayAmount {
    final value = _amountController.text;
    if (value.isNotEmpty) return value;
    return _amountFocused ? '' : null;
  }

  PaymentLinkAmountVisualState get _amountVisualState {
    if (_amountController.text.isEmpty) {
      return _amountFocused
          ? PaymentLinkAmountVisualState.focused
          : PaymentLinkAmountVisualState.empty;
    }
    return _hasPositiveAmount
        ? PaymentLinkAmountVisualState.amount
        : PaymentLinkAmountVisualState.focused;
  }

  void _handleAmountChanged(String _) => setState(() {});

  void _selectWizardStep(int step) {
    switch (step) {
      case 0:
        _showPage(_PaymentLinksLocalPage.amount);
      case 1:
        if (_hasPositiveAmount) _showPage(_PaymentLinksLocalPage.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pane = _showHelp
        ? PaymentLinkHowItWorksDesktopView(
            background: _buildHome(),
            onClose: _hideHelpOverlay,
          )
        : _buildCurrentPage();

    return AppDesktopShell(
      key: const ValueKey('payment_links_desktop_screen'),
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(padding: EdgeInsets.zero, child: pane),
    );
  }

  Widget _buildCurrentPage() {
    return switch (_page) {
      _PaymentLinksLocalPage.home => _buildHome(),
      _PaymentLinksLocalPage.amount => _buildAmount(),
      _PaymentLinksLocalPage.message => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.empty,
        card: PaymentLinkGiftCard(artwork: _selectedArtwork, showBack: true),
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
        onSkip: () => _showPage(_PaymentLinksLocalPage.review),
        onStepSelected: _selectWizardStep,
      ),
      _PaymentLinksLocalPage.review => PaymentLinkReviewDesktopView(
        card: PaymentLinkGiftCard(
          artwork: _selectedArtwork,
          amountText: _amountController.text,
          showCaret: false,
        ),
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
        onStepSelected: _selectWizardStep,
      ),
      _PaymentLinksLocalPage.redeem => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.paste,
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
      ),
    };
  }

  Widget _buildHome() {
    return PaymentLinksHomeDesktopView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.png',
        width: 243,
        height: 162,
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: () => context.go('/home'),
      onShowHelp: _showHelpOverlay,
      onCreate: () => _showPage(_PaymentLinksLocalPage.amount),
      onRedeem: () => _showPage(_PaymentLinksLocalPage.redeem),
    );
  }

  Widget _buildAmount() {
    return PaymentLinkAmountDesktopView(
      state: _amountVisualState,
      card: Stack(
        children: [
          PaymentLinkGiftCard(
            artwork: _selectedArtwork,
            amountText: _displayAmount,
            showCaret: _amountFocused,
            onTap: _amountFocusNode.requestFocus,
            semanticLabel: 'Gift card amount input',
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: ExcludeSemantics(
              child: Opacity(
                opacity: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: EditableText(
                    key: const ValueKey('payment_link_amount_editor'),
                    controller: _amountController,
                    focusNode: _amountFocusNode,
                    style: const TextStyle(
                      color: Color(0x00000000),
                      fontSize: 1,
                    ),
                    cursorColor: const Color(0x00000000),
                    backgroundCursorColor: const Color(0x00000000),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_amountFormatter],
                    autocorrect: false,
                    enableSuggestions: false,
                    enableInteractiveSelection: false,
                    onChanged: _handleAmountChanged,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      cardSelector: PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: _selectedArtwork,
        onSelected: (artwork) => setState(() => _selectedArtwork = artwork),
      ),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onCreate: _hasPositiveAmount
          ? () => _showPage(_PaymentLinksLocalPage.message)
          : null,
    );
  }
}
