import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../models/vizor_payment_link.dart';
import '../providers/payment_link_intake_provider.dart';
import '../services/payment_link_clipboard.dart';
import '../services/payment_link_recovery_store.dart';
import '../services/payment_link_service.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/payment_link_card_selector_rail.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_desktop_views.dart';
import '../widgets/payment_link_gift_card.dart';
import '../widgets/payment_link_keystone_signing_overlay.dart';

enum _PaymentLinksLocalPage {
  home,
  amount,
  message,
  review,
  ready,
  redeem,
  received,
}

/// Desktop Payment Link lifecycle.
///
/// The presentation remains local to this screen, while all secret creation,
/// recovery persistence, sync, and transaction work stays behind
/// [PaymentLinkOperations]. Artwork and message are not protocol fields in the
/// current v1 link, so received links intentionally render a generic card.
class PaymentLinksDesktopScreen extends ConsumerStatefulWidget {
  const PaymentLinksDesktopScreen({super.key});

  @override
  ConsumerState<PaymentLinksDesktopScreen> createState() =>
      _PaymentLinksDesktopScreenState();
}

class _PaymentLinksDesktopScreenState
    extends ConsumerState<PaymentLinksDesktopScreen> {
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

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
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  _PaymentLinksLocalPage _page = _PaymentLinksLocalPage.home;
  PaymentLinkCardArtwork _selectedArtwork = PaymentLinkCardArtwork.gift;
  PaymentLinkRedeemVisualState _redeemState =
      PaymentLinkRedeemVisualState.paste;
  PaymentLinkCardsTab _activeCardsTab = PaymentLinkCardsTab.created;
  List<PaymentLinkRecoveryRecord> _recoveries = const [];
  VizorPaymentLink? _readyLink;
  VizorPaymentLink? _receivedLink;
  PaymentLinkRecoveryRecord? _reclaimCandidate;
  _PaymentLinkKeystoneFundingRequest? _keystoneFundingRequest;
  bool _showHelp = false;
  bool _amountFocused = false;
  bool _readyShowsBack = false;
  bool _operationInProgress = false;
  bool _pendingIntakeScheduled = false;

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(_handleAmountFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_loadRecoveries());
      _consumePendingPaymentLink();
    });
  }

  @override
  void dispose() {
    _amountFocusNode
      ..removeListener(_handleAmountFocus)
      ..dispose();
    _amountController.dispose();
    _messageFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleAmountFocus() {
    if (_amountFocused == _amountFocusNode.hasFocus) return;
    setState(() => _amountFocused = _amountFocusNode.hasFocus);
  }

  void _showPage(_PaymentLinksLocalPage page) {
    _amountFocusNode.unfocus();
    _messageFocusNode.unfocus();
    setState(() {
      _page = page;
      _showHelp = false;
    });
  }

  void _startCreate() {
    _amountController.clear();
    _messageController.clear();
    setState(() {
      _selectedArtwork = PaymentLinkCardArtwork.gift;
      _readyLink = null;
      _readyShowsBack = false;
      _page = _PaymentLinksLocalPage.amount;
      _showHelp = false;
    });
  }

  void _showHelpOverlay() => setState(() => _showHelp = true);

  void _hideHelpOverlay() => setState(() => _showHelp = false);

  void _schedulePendingPaymentLink() {
    if (_pendingIntakeScheduled) return;
    _pendingIntakeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingIntakeScheduled = false;
      if (mounted) _consumePendingPaymentLink();
    });
  }

  void _consumePendingPaymentLink() {
    if (_operationInProgress) return;
    final link = ref.read(paymentLinkIntakeProvider.notifier).takePending();
    if (link == null || !mounted) return;
    setState(() {
      _receivedLink = link;
      _redeemState = PaymentLinkRedeemVisualState.paste;
      _page = _PaymentLinksLocalPage.received;
      _showHelp = false;
    });
  }

  Future<void> _loadRecoveries({bool showError = true}) async {
    try {
      final records = await ref
          .read(paymentLinkOperationsProvider)
          .loadCreatedLinkRecoveries();
      if (!mounted) return;
      final visible = records.where((record) => !record.isArchived).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() => _recoveries = visible);
    } catch (_) {
      if (mounted && showError) {
        _showError('Gift Cards could not be loaded.');
      }
    }
  }

  bool get _hasPositiveAmount {
    final amount = parseZecAmount(_amountController.text);
    return amount != null && amount > BigInt.zero;
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

  bool get _hasMessage => _messageController.text.trim().isNotEmpty;

  String? get _maxAmountText {
    final sync = ref.watch(syncProvider).value;
    if (sync == null ||
        !sync.hasBalanceData ||
        sync.spendableBalance <= BigInt.zero) {
      return null;
    }
    return formatZecAmount(sync.spendableBalance);
  }

  void _useMaxAmount() {
    final sync = ref.read(syncProvider).value;
    if (sync == null ||
        !sync.hasBalanceData ||
        sync.spendableBalance <= BigInt.zero) {
      return;
    }
    final text = formatZecAmount(sync.spendableBalance);
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _amountFocusNode.requestFocus();
    setState(() {});
  }

  void _handleMessageChanged(String _) => setState(() {});

  void _clearMessage() {
    _messageController.clear();
    _messageFocusNode.requestFocus();
    setState(() {});
  }

  void _skipMessage() {
    _messageController.clear();
    _showPage(_PaymentLinksLocalPage.review);
  }

  void _selectWizardStep(int step) {
    switch (step) {
      case 0:
        _showPage(_PaymentLinksLocalPage.amount);
      case 1:
        if (_hasPositiveAmount) _showPage(_PaymentLinksLocalPage.message);
    }
  }

  Future<void> _createFundedLink() async {
    if (_operationInProgress) return;
    final amount = parseZecAmount(_amountController.text.trim());
    final accountState = ref.read(accountProvider).value;
    final sourceAccountUuid = accountState?.activeAccountUuid;
    if (amount == null || amount <= BigInt.zero) {
      _showError('Enter a valid Gift Card amount.');
      return;
    }
    if (sourceAccountUuid == null || sourceAccountUuid.isEmpty) {
      _showError('No active account is available.');
      return;
    }
    if (ref.read(accountProvider.notifier).isActiveAccountHardware) {
      setState(() {
        _operationInProgress = true;
        _keystoneFundingRequest = _PaymentLinkKeystoneFundingRequest(
          amountZatoshi: amount,
          sourceAccountUuid: sourceAccountUuid,
        );
      });
      return;
    }

    setState(() => _operationInProgress = true);
    try {
      final link = await ref
          .read(paymentLinkOperationsProvider)
          .createFundedLink(
            amountZatoshi: amount,
            sourceAccountUuid: sourceAccountUuid,
          );
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      setState(() {
        _readyLink = link;
        _readyShowsBack = false;
        _page = _PaymentLinksLocalPage.ready;
      });
    } catch (_) {
      if (mounted) _showError('Gift Card creation failed. Try again.');
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  void _cancelKeystoneFunding() {
    setState(() {
      _keystoneFundingRequest = null;
      _operationInProgress = false;
    });
    unawaited(_loadRecoveries(showError: false));
  }

  Future<void> _completeKeystoneFunding(
    VizorPaymentLink link,
    String status,
    String? message,
  ) async {
    await _loadRecoveries(showError: false);
    if (!mounted) return;
    setState(() {
      _keystoneFundingRequest = null;
      _operationInProgress = false;
      _readyLink = link;
      _readyShowsBack = false;
      _page = _PaymentLinksLocalPage.ready;
    });
    if (status == 'broadcasted_storage_failed') {
      showAppToast(
        context,
        message ??
            'Funding was sent, but local transaction storage needs to sync.',
        iconName: AppIcons.warning,
      );
    }
  }

  Future<void> _copyPaymentLink(VizorPaymentLink link) async {
    if (_operationInProgress) return;
    setState(() => _operationInProgress = true);
    try {
      await ref.read(paymentLinkClipboardProvider).copySecret(link.encode());
      try {
        await ref
            .read(paymentLinkOperationsProvider)
            .markCreatedLinkShared(link);
        await _loadRecoveries(showError: false);
        if (mounted) showAppToast(context, 'Gift link copied');
      } catch (_) {
        if (mounted) {
          _showError('Gift link copied, but its status could not be updated.');
        }
      }
    } catch (_) {
      if (mounted) _showError('Gift link could not be copied.');
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _pastePaymentLink() async {
    if (_operationInProgress) return;
    setState(() {
      _operationInProgress = true;
      _redeemState = PaymentLinkRedeemVisualState.loading;
    });
    try {
      final rawLink = await ref.read(paymentLinkClipboardProvider).readText();
      if (rawLink == null || rawLink.trim().isEmpty) {
        if (mounted) {
          setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
        }
        return;
      }
      final notifier = ref.read(paymentLinkIntakeProvider.notifier);
      final result = notifier.ingest(rawLink);
      if (result != PaymentLinkIntakeResult.accepted) {
        if (mounted) {
          setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
        }
        return;
      }
      final link = notifier.takePending();
      if (link == null || !mounted) return;
      setState(() {
        _receivedLink = link;
        _redeemState = PaymentLinkRedeemVisualState.paste;
        _page = _PaymentLinksLocalPage.received;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _redeemState = PaymentLinkRedeemVisualState.invalid);
      }
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _clearClipboard() async {
    await ref.read(paymentLinkClipboardProvider).clear();
    ref.read(paymentLinkIntakeProvider.notifier).clearError();
    if (mounted) {
      setState(() => _redeemState = PaymentLinkRedeemVisualState.paste);
    }
  }

  Future<void> _claimReceivedLink() async {
    final link = _receivedLink;
    if (link == null || _operationInProgress) return;
    setState(() => _operationInProgress = true);
    try {
      await ref.read(paymentLinkOperationsProvider).claimLink(link);
      if (!mounted) return;
      setState(() {
        _receivedLink = null;
        _page = _PaymentLinksLocalPage.home;
      });
      showAppToast(context, 'Gift claimed');
    } catch (_) {
      if (mounted) {
        _showError(
          'Gift Card claim failed. It may still be waiting for confirmation '
          'or may already be spent.',
        );
      }
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  void _requestReclaim(PaymentLinkRecoveryRecord record) {
    if (_operationInProgress) return;
    setState(() => _reclaimCandidate = record);
  }

  void _dismissReclaim() {
    if (_operationInProgress) return;
    setState(() => _reclaimCandidate = null);
  }

  Future<void> _confirmReclaim() async {
    final record = _reclaimCandidate;
    if (record == null || _operationInProgress) return;
    setState(() => _operationInProgress = true);
    try {
      await ref.read(paymentLinkOperationsProvider).reclaimCreatedLink(record);
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      setState(() => _reclaimCandidate = null);
      showAppToast(context, 'Reclaim submitted');
    } catch (_) {
      if (mounted) {
        _showError(
          'Gift Card reclaim failed. It may still be waiting for confirmation '
          'or may already be spent.',
        );
      }
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  void _showError(String message) {
    showAppToast(
      context,
      message,
      iconName: AppIcons.warning,
      tone: AppToastTone.destructive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingLink = ref.watch(
      paymentLinkIntakeProvider.select((state) => state.pendingLink),
    );
    if (pendingLink != null) _schedulePendingPaymentLink();

    final currentPage = _buildCurrentPage();
    final keystoneRequest = _keystoneFundingRequest;
    final pane = keystoneRequest != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              currentPage,
              Positioned.fill(
                child: PaymentLinkKeystoneSigningOverlay(
                  amountZatoshi: keystoneRequest.amountZatoshi,
                  sourceAccountUuid: keystoneRequest.sourceAccountUuid,
                  onCancel: _cancelKeystoneFunding,
                  onFundingBroadcast: _completeKeystoneFunding,
                ),
              ),
            ],
          )
        : _reclaimCandidate != null
        ? _buildReclaimOverlay(currentPage)
        : _showHelp
        ? PaymentLinkHowItWorksDesktopView(
            background: _buildHome(),
            onClose: _hideHelpOverlay,
          )
        : currentPage;

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
      _PaymentLinksLocalPage.message => _buildMessage(),
      _PaymentLinksLocalPage.review => PaymentLinkReviewDesktopView(
        card: PaymentLinkGiftCard(
          artwork: _selectedArtwork,
          amountText: _amountController.text,
          showCaret: false,
        ),
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
        onConfirm: _operationInProgress ? null : _createFundedLink,
        onStepSelected: _operationInProgress ? null : _selectWizardStep,
        confirmLabel: _operationInProgress ? 'Creating...' : 'Confirm & create',
      ),
      _PaymentLinksLocalPage.ready => _buildReady(),
      _PaymentLinksLocalPage.redeem => PaymentLinkRedeemDesktopView(
        state: _redeemState,
        onBack: () => _showPage(_PaymentLinksLocalPage.home),
        onPaste: _operationInProgress ? null : _pastePaymentLink,
        onClearClipboard: _operationInProgress ? null : _clearClipboard,
      ),
      _PaymentLinksLocalPage.received => _buildReceived(),
    };
  }

  Widget _buildHome() {
    if (_recoveries.isNotEmpty) return _buildCardsList();
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
      onCreate: _startCreate,
      onRedeem: () => _showPage(_PaymentLinksLocalPage.redeem),
    );
  }

  Widget _buildCardsList() {
    final showingCreated = _activeCardsTab == PaymentLinkCardsTab.created;
    final available = showingCreated
        ? _recoveries
              .where(
                (record) => record.state != PaymentLinkRecoveryState.reclaiming,
              )
              .map(_buildRecoveryRow)
              .toList()
        : <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No received cards yet.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ];
    final reclaiming = showingCreated
        ? _recoveries
              .where(
                (record) => record.state == PaymentLinkRecoveryState.reclaiming,
              )
              .map(_buildRecoveryRow)
              .toList()
        : const <Widget>[];

    return PaymentLinkCardsDesktopView(
      pendingCards: available,
      createdCards: reclaiming,
      onBack: () => context.go('/home'),
      onCreate: _startCreate,
      onRedeem: () => _showPage(_PaymentLinksLocalPage.redeem),
      activeTab: _activeCardsTab,
      onTabSelected: (tab) => setState(() => _activeCardsTab = tab),
      pendingLabel: showingCreated ? 'Available' : 'Received',
      createdSectionLabel: reclaiming.isEmpty ? null : 'Submitted',
    );
  }

  Widget _buildRecoveryRow(PaymentLinkRecoveryRecord record) {
    final canUseLink =
        record.state == PaymentLinkRecoveryState.funded ||
        record.state == PaymentLinkRecoveryState.shared;
    final canReclaim =
        record.state != PaymentLinkRecoveryState.reclaiming &&
        !_operationInProgress;
    final copyEnabled = canUseLink && !_operationInProgress;
    final statusText = switch (record.state) {
      PaymentLinkRecoveryState.draft => 'Funding incomplete',
      PaymentLinkRecoveryState.funded ||
      PaymentLinkRecoveryState.shared => 'Copy link',
      PaymentLinkRecoveryState.reclaiming => 'Reclaiming',
    };
    return PaymentLinkCardListRow(
      key: ValueKey('payment_link_recovery_${record.link.address}'),
      thumbnail: Image.asset(
        PaymentLinkCardArtwork.gift.assetPath,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
      amountText: '${formatZecAmount(record.link.amountZatoshi)} ZEC',
      dateText: _formatCardDate(record.link.createdAt),
      statusText: statusText,
      onAction: copyEnabled ? () => _copyPaymentLink(record.link) : null,
      showCopyIcon: canUseLink,
      secondaryActionText: record.state == PaymentLinkRecoveryState.reclaiming
          ? null
          : 'Reclaim',
      onSecondaryAction: canReclaim ? () => _requestReclaim(record) : null,
    );
  }

  Widget _buildAmount() {
    final maxAmountText = _maxAmountText;
    return PaymentLinkAmountDesktopView(
      state: _amountVisualState,
      card: PaymentLinkGiftCard(
        artwork: _selectedArtwork,
        amountController: _amountController,
        amountFocusNode: _amountFocusNode,
        amountEditorKey: const ValueKey('payment_link_amount_editor'),
        amountInputFormatters: [_amountFormatter],
        onAmountChanged: _handleAmountChanged,
        maxAmountText: maxAmountText,
        onUseMax: maxAmountText == null ? null : _useMaxAmount,
        semanticLabel: 'Gift card amount input',
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

  Widget _buildMessage() {
    return PaymentLinkMessageDesktopView(
      state: _hasMessage
          ? PaymentLinkMessageVisualState.filled
          : PaymentLinkMessageVisualState.empty,
      card: PaymentLinkGiftCard(
        artwork: _selectedArtwork,
        showBack: true,
        messageController: _messageController,
        messageFocusNode: _messageFocusNode,
        messageEditorKey: const ValueKey('payment_link_message_editor'),
        messageInputFormatters: [LengthLimitingTextInputFormatter(128)],
        onMessageChanged: _handleMessageChanged,
        onDeleteMessage: _hasMessage ? _clearMessage : null,
        semanticLabel: 'Gift card message input',
      ),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onSkip: _skipMessage,
      onContinue: _hasMessage
          ? () => _showPage(_PaymentLinksLocalPage.review)
          : null,
      onStepSelected: _selectWizardStep,
    );
  }

  Widget _buildReady() {
    final link = _readyLink;
    if (link == null) return _buildHome();
    final amountText = formatZecAmount(link.amountZatoshi);
    final message = _messageController.text.trim();
    final hasMessage = message.isNotEmpty;
    final card = hasMessage
        ? PaymentLinkCardFlip(
            showBack: _readyShowsBack,
            front: PaymentLinkGiftCard(
              artwork: _selectedArtwork,
              amountText: amountText,
              showCaret: false,
            ),
            back: PaymentLinkGiftCard(
              artwork: _selectedArtwork,
              showBack: true,
              message: message,
              messageCharacterCount: message.length,
            ),
          )
        : PaymentLinkGiftCard(
            artwork: _selectedArtwork,
            amountText: amountText,
            showCaret: false,
          );
    return PaymentLinkReadyDesktopView(
      state: hasMessage
          ? PaymentLinkReadyVisualState.flipHint
          : PaymentLinkReadyVisualState.ready,
      card: card,
      decoration: const PaymentLinkConfetti(),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onCopy: _operationInProgress ? null : () => _copyPaymentLink(link),
      onCardTap: hasMessage
          ? () => setState(() => _readyShowsBack = !_readyShowsBack)
          : null,
      onReturnHome: () => _showPage(_PaymentLinksLocalPage.home),
      copyLabel: _operationInProgress ? 'Copying...' : 'Copy the gift link',
    );
  }

  Widget _buildReceived() {
    final link = _receivedLink;
    if (link == null) return _buildHome();
    return PaymentLinkReceivedDesktopView(
      card: PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.gift,
        amountText: formatZecAmount(link.amountZatoshi),
        showCaret: false,
      ),
      decoration: const PaymentLinkConfetti(),
      onBack: () => _showPage(_PaymentLinksLocalPage.home),
      onClaim: _operationInProgress ? null : _claimReceivedLink,
      claimLabel: _operationInProgress ? 'Claiming...' : 'Claim my gift',
    );
  }

  Widget _buildReclaimOverlay(Widget background) {
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        AppPaneModalOverlay(
          onDismiss: _dismissReclaim,
          child: AppModalCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reclaim gift card?',
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Any remaining balance will be sent back to the account '
                  'that created this card. The shared link will stop working '
                  'after the transaction confirms.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppModalActions(
                  onCancel: _operationInProgress ? null : _dismissReclaim,
                  actionLabel: _operationInProgress
                      ? 'Reclaiming...'
                      : 'Reclaim',
                  onAction: _operationInProgress ? null : _confirmReclaim,
                  actionVariant: AppButtonVariant.destructive,
                  actionLeading: _operationInProgress
                      ? const AppIcon(AppIcons.loader, size: 16)
                      : null,
                  cancelKey: const ValueKey(
                    'payment_link_reclaim_cancel_button',
                  ),
                  actionKey: const ValueKey(
                    'payment_link_reclaim_confirm_button',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatCardDate(DateTime date) {
    final local = date.toLocal();
    return '${_monthNames[local.month - 1]} ${local.day}';
  }
}

class _PaymentLinkKeystoneFundingRequest {
  const _PaymentLinkKeystoneFundingRequest({
    required this.amountZatoshi,
    required this.sourceAccountUuid,
  });

  final BigInt amountZatoshi;
  final String sourceAccountUuid;
}
