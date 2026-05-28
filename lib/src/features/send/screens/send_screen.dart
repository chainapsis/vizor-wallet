import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import 'send_review_screen.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final activeAccountUuid = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
    final sync = ref.watch(
      syncProvider.select(
        (value) =>
            (value.value ?? SyncState()).scopedToAccount(activeAccountUuid),
      ),
    );
    final spendableBalance = sync.spendableBalance;

    return _SendComposeBody(
      key: ValueKey(activeAccountUuid),
      walletAsync: walletAsync,
      activeAccountUuid: activeAccountUuid,
      spendableBalance: spendableBalance,
    );
  }
}

class _SendComposeBody extends ConsumerStatefulWidget {
  const _SendComposeBody({
    super.key,
    required this.walletAsync,
    required this.activeAccountUuid,
    required this.spendableBalance,
  });

  final AsyncValue<WalletState> walletAsync;
  final String? activeAccountUuid;
  final BigInt spendableBalance;

  @override
  ConsumerState<_SendComposeBody> createState() => _SendComposeBodyState();
}

class _MaxQuote {
  const _MaxQuote({
    required this.accountUuid,
    required this.address,
    required this.memo,
    required this.amountZatoshi,
  });

  final String accountUuid;
  final String address;
  final String memo;
  final BigInt amountZatoshi;
}

class _AddressTextEditingController extends TextEditingController {
  // Emphasize the visible address edges while keeping the middle neutral.
  static const _highlightPrefixLength = 6;
  static const _highlightSuffixLength = 5;

  // Updated by the parent build before the TextField paints.
  Color? edgeHighlightColor;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final highlightColor = edgeHighlightColor;
    if (highlightColor == null) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final text = value.text;
    final baseStyle = style ?? const TextStyle();
    final highlightStyle = baseStyle.copyWith(color: highlightColor);

    if (text.length <= _highlightPrefixLength + _highlightSuffixLength) {
      return TextSpan(text: text, style: highlightStyle);
    }

    final suffixStart = text.length - _highlightSuffixLength;
    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(
          text: text.substring(0, _highlightPrefixLength),
          style: highlightStyle,
        ),
        TextSpan(text: text.substring(_highlightPrefixLength, suffixStart)),
        TextSpan(text: text.substring(suffixStart), style: highlightStyle),
      ],
    );
  }
}

String _newSendFlowId() {
  final random = math.Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _SendComposeBodyState extends ConsumerState<_SendComposeBody> {
  static const _singleLineFieldOverlayReserve = 20.0;
  static const _singleLineFieldGap = AppSpacing.xs;
  static const _multilineFieldOverlayReserve = 24.0;
  static const _maxDebounceDuration = Duration(milliseconds: 300);
  final _addressController = _AddressTextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _addressFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();
  final _memoFocusNode = FocusNode();
  final _memoScrollController = ScrollController();
  late final String _sendFlowId = _newSendFlowId();
  bool _isSending = false;
  bool _messageExpanded = false;
  String? _error;
  String _addressType = '';
  String?
  _amountError; // null = no error, empty string = silent invalid (empty/dot)
  bool _isMaxMode = false;
  bool _isResolvingMax = false;
  bool _programmaticAmountEdit = false;
  _MaxQuote? _maxQuote;
  Timer? _maxDebounceTimer;
  int _addressSeq = 0;
  int _maxSeq = 0;
  int _validateSeq = 0;

  @override
  void initState() {
    super.initState();
    _memoController.addListener(_handleMemoChanged);
    _addressFocusNode.addListener(_handleFieldVisualStateChanged);
    _amountFocusNode.addListener(_handleFieldVisualStateChanged);
    _memoFocusNode.addListener(_handleFieldVisualStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    _maxDebounceTimer?.cancel();
    _memoController.removeListener(_handleMemoChanged);
    _addressFocusNode.removeListener(_handleFieldVisualStateChanged);
    _amountFocusNode.removeListener(_handleFieldVisualStateChanged);
    _memoFocusNode.removeListener(_handleFieldVisualStateChanged);
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _addressFocusNode.dispose();
    _amountFocusNode.dispose();
    _memoFocusNode.dispose();
    _memoScrollController.dispose();
    super.dispose();
  }

  void _handleMemoChanged() {
    if (_memoController.text.isNotEmpty && !_messageExpanded) {
      _messageExpanded = true;
    }
    if (_isMaxMode) {
      _scheduleMaxEstimate();
    } else {
      _validateAmount();
    }
    if (mounted) setState(() {});
  }

  void _handleFieldVisualStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _SendComposeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spendableBalance != widget.spendableBalance) {
      if (_isMaxMode) {
        _scheduleMaxEstimate(immediate: true);
      } else if (_amountController.text.trim().isNotEmpty) {
        _validateAmount();
      }
    }
  }

  Future<void> _validateAddress() async {
    final seq = ++_addressSeq;
    final addr = _addressController.text.trim();
    if (addr.isEmpty) {
      if (!mounted || seq != _addressSeq) return;
      setState(() => _addressType = '');
      _handleAddressValidationSettled();
      return;
    }
    try {
      final result = await rust_sync.validateAddress(address: addr);
      if (!mounted || seq != _addressSeq) return;
      setState(
        () => _addressType = result.isValid ? result.addressType : 'invalid',
      );
      _handleAddressValidationSettled();
    } catch (e) {
      log('Send: address validation error: $e');
      if (!mounted || seq != _addressSeq) return;
      setState(() => _addressType = 'error');
      _handleAddressValidationSettled();
    }
  }

  void _handleAddressValidationSettled() {
    if (_isMaxMode) {
      _scheduleMaxEstimate();
    } else {
      _validateAmount();
    }
  }

  void _handleAddressChanged() {
    _addressSeq++;
    _maxDebounceTimer?.cancel();
    setState(() {
      _addressType = '';
      _error = null;
      if (_isMaxMode) {
        _validateSeq++;
        _maxSeq++;
        _maxQuote = null;
        _isResolvingMax = false;
        _amountError = '';
      }
    });
    unawaited(_validateAddress());
    if (!_isMaxMode) {
      _validateAmount();
    }
  }

  void _handleAmountChanged() {
    if (_programmaticAmountEdit) return;
    if (_isMaxMode) {
      _maxDebounceTimer?.cancel();
      _maxSeq++;
      setState(() {
        _isMaxMode = false;
        _isResolvingMax = false;
        _maxQuote = null;
        _error = null;
      });
    }
    _validateAmount();
  }

  bool get _hasValidAddress =>
      _addressController.text.trim().isNotEmpty &&
      _addressType.isNotEmpty &&
      _addressType != 'invalid' &&
      _addressType != 'error';

  bool get _isShieldedAddress =>
      _addressType == 'unified' || _addressType == 'sapling';

  bool get _isConfirmedTransparentAddress => _addressType == 'transparent';

  bool get _showMemoControls => !_isConfirmedTransparentAddress;

  String get _effectiveMemo =>
      _isConfirmedTransparentAddress ? '' : _memoController.text.trim();

  bool get _showAmountError =>
      _amountError != null && _amountError!.trim().isNotEmpty;

  bool get _hasCurrentMaxQuote {
    final quote = _maxQuote;
    if (quote == null) return false;
    return quote.accountUuid == widget.activeAccountUuid &&
        quote.address == _addressController.text.trim() &&
        quote.memo == _effectiveMemo &&
        parseZecAmount(_amountController.text.trim()) == quote.amountZatoshi;
  }

  int get _memoLength => utf8.encode(_memoController.text).length;

  String? get _memoError {
    final memo = _effectiveMemo;
    if (utf8.encode(memo).length > 512) return 'Message is too long';
    if (memo.isNotEmpty && !_isShieldedAddress) {
      return 'Message is only available for shielded addresses';
    }
    return null;
  }

  bool get _canReview =>
      !_isSending &&
      !_isResolvingMax &&
      _hasValidAddress &&
      _isAmountValid &&
      (!_isMaxMode || _hasCurrentMaxQuote) &&
      _memoError == null &&
      (_isShieldedAddress || _effectiveMemo.isEmpty);

  void _activateMaxMode() {
    if (_isResolvingMax) return;
    setState(() {
      _isMaxMode = true;
      _maxQuote = null;
      _error = null;
    });
    _scheduleMaxEstimate(immediate: true);
  }

  String? _maxEstimatePreconditionError() {
    if (widget.activeAccountUuid == null) return 'No active account';
    if (!_hasValidAddress) return 'Enter a valid address to use Max';
    return _memoError;
  }

  void _scheduleMaxEstimate({bool immediate = false}) {
    _maxDebounceTimer?.cancel();
    _validateSeq++;
    final seq = ++_maxSeq;
    if (!_isMaxMode) return;

    final preconditionError = _maxEstimatePreconditionError();
    setState(() {
      _maxQuote = null;
      _isResolvingMax = preconditionError == null;
      _amountError = preconditionError ?? '';
      _error = null;
    });

    if (preconditionError != null) return;

    if (immediate) {
      unawaited(_resolveMaxEstimate(seq));
    } else {
      _maxDebounceTimer = Timer(
        _maxDebounceDuration,
        () => unawaited(_resolveMaxEstimate(seq)),
      );
    }
  }

  Future<void> _resolveMaxEstimate(int seq) async {
    final accountUuid = widget.activeAccountUuid;
    final address = _addressController.text.trim();
    final memo = _effectiveMemo;
    if (accountUuid == null || !_isMaxMode || seq != _maxSeq) return;

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      if (!mounted || !_isMaxMode || seq != _maxSeq) return;

      final estimate = await rust_sync.estimateSendMax(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        toAddress: address,
        memo: memo.isNotEmpty ? memo : null,
      );

      if (!mounted || !_isMaxMode || seq != _maxSeq) return;

      if (estimate.amountZatoshi <= BigInt.zero) {
        setState(() {
          _isResolvingMax = false;
          _maxQuote = null;
          _amountError = 'Insufficient shielded balance to cover fee';
        });
        return;
      }

      final amountText = ZecAmount.fromZatoshi(
        estimate.amountZatoshi,
      ).pretty().amountText;
      _programmaticAmountEdit = true;
      _amountController.value = TextEditingValue(
        text: amountText,
        selection: TextSelection.collapsed(offset: amountText.length),
      );
      _programmaticAmountEdit = false;

      setState(() {
        _isResolvingMax = false;
        _amountError = null;
        _maxQuote = _MaxQuote(
          accountUuid: accountUuid,
          address: address,
          memo: memo,
          amountZatoshi: estimate.amountZatoshi,
        );
      });
    } catch (e) {
      if (!mounted || !_isMaxMode || seq != _maxSeq) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        _isResolvingMax = false;
        _maxQuote = null;
        if (msg.contains('insufficient')) {
          _amountError = 'Insufficient shielded balance to cover fee';
        } else {
          _amountError = 'Max amount unavailable';
        }
      });
    } finally {
      _programmaticAmountEdit = false;
    }
  }

  Future<void> _validateAmount() async {
    final seq = ++_validateSeq;
    final text = _amountController.text.trim();

    // Empty or just "." — silently invalid (no error shown, button disabled)
    if (text.isEmpty || text == '.') {
      setState(() => _amountError = '');
      return;
    }

    final zatoshi = parseZecAmount(text);
    if (zatoshi == null || zatoshi <= BigInt.zero) {
      setState(() => _amountError = 'Invalid amount');
      return;
    }

    // Quick balance pre-check
    final spendable = widget.spendableBalance;
    if (zatoshi > spendable) {
      setState(() => _amountError = 'Insufficient shielded balance');
      return;
    }

    // Need valid address to estimate fee
    final address = _addressController.text.trim();
    if (address.isEmpty ||
        _addressType == 'invalid' ||
        _addressType == 'error' ||
        _addressType.isEmpty) {
      setState(() => _amountError = null);
      return;
    }

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      if (!mounted || seq != _validateSeq) return;
      final memo = _effectiveMemo;
      final accountUuid = widget.activeAccountUuid;
      if (accountUuid == null) {
        setState(() => _amountError = null);
        return;
      }
      final fee = await rust_sync.estimateFee(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        toAddress: address,
        amountZatoshi: zatoshi,
        memo: memo.isNotEmpty ? memo : null,
      );

      // Stale check — new input arrived while awaiting
      if (!mounted || seq != _validateSeq) return;

      final totalNeeded = zatoshi + fee;
      if (totalNeeded > spendable) {
        final feeText = ZecAmount.fromZatoshi(fee).fee.toString();
        setState(
          () => _amountError = 'Insufficient shielded balance (fee: $feeText)',
        );
      } else {
        setState(() => _amountError = null);
      }
    } catch (e) {
      if (!mounted || seq != _validateSeq) return;
      final msg = e.toString();
      if (msg.contains('InsufficientFunds') || msg.contains('insufficient')) {
        setState(
          () => _amountError = 'Insufficient shielded balance including fee',
        );
      } else {
        log('Send: fee estimation failed (non-blocking): $e');
        setState(() => _amountError = null);
      }
    }
  }

  bool get _isAmountValid => _amountError == null;

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
      return 'Insufficient shielded balance to cover amount and fee.';
    }
    if (lower.contains('grpc connect failed') ||
        lower.contains('connection refused') ||
        lower.contains('dns error') ||
        lower.contains('tls error')) {
      return 'Network error. Check your connection and try again.';
    }
    // Partial broadcast must be checked before generic "broadcast rejected"
    if (lower.contains('broadcast failed after') &&
        lower.contains('txs sent')) {
      return 'Some parts of this transaction were sent. Open Activity to see '
          'what went through before you try again.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'The network rejected this transaction. Try again.';
    }
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be sent. Try again.';
    }
    return 'Send failed. Try again.';
  }

  Future<void> _openReview() async {
    setState(() {
      _isSending = true;
      _error = null;
    });

    BigInt? activeProposalId;
    var pushedReview = false;

    try {
      final address = _addressController.text.trim();
      final amountZatoshi = parseZecAmount(_amountController.text.trim());

      if (_isResolvingMax) {
        setState(() {
          _error = 'Calculating max amount';
          _isSending = false;
        });
        return;
      }

      if (!_hasValidAddress) {
        setState(() {
          _error = 'Enter a valid address';
          _isSending = false;
        });
        return;
      }

      if (amountZatoshi == null || amountZatoshi <= BigInt.zero) {
        setState(() {
          _error = 'Invalid amount';
          _isSending = false;
        });
        return;
      }

      if (_memoError != null) {
        setState(() {
          _error = _memoError;
          _isSending = false;
        });
        return;
      }

      // Check balance before proposing
      final spendable = widget.spendableBalance;
      if (amountZatoshi > spendable) {
        setState(() {
          _error = 'Insufficient shielded balance.';
          _isSending = false;
        });
        return;
      }

      final memo = _effectiveMemo;
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      if (!mounted) return;

      // Step 1: Propose transfer
      log('Send: proposing transfer');
      final accountUuid = widget.activeAccountUuid;
      if (accountUuid == null) {
        setState(() {
          _error = 'No active account';
          _isSending = false;
        });
        return;
      }
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        sendFlowId: _sendFlowId,
        toAddress: address,
        amountZatoshi: amountZatoshi,
        memo: memo.isNotEmpty ? memo : null,
      );
      activeProposalId = proposal.proposalId;

      if (!mounted) {
        return;
      }
      setState(() => _isSending = false);
      pushedReview = true;
      await context.push(
        '/send/review',
        extra: SendReviewArgs(
          proposalId: proposal.proposalId,
          sendFlowId: _sendFlowId,
          proposalAccountUuid: accountUuid,
          address: address,
          addressType: _addressType,
          amountZatoshi: amountZatoshi,
          feeZatoshi: proposal.feeZatoshi,
          memo: memo.isNotEmpty ? memo : null,
          needsSaplingParams: proposal.needsSaplingParams,
        ),
      );
    } catch (e) {
      log('Send: review preparation error: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e.toString());
        _isSending = false;
      });
    } finally {
      if (activeProposalId != null && !pushedReview) {
        try {
          await rust_sync.discardProposal(
            proposalId: activeProposalId,
            sendFlowId: _sendFlowId,
          );
          log('Send: released proposal $activeProposalId (review not opened)');
        } catch (e) {
          log('Send: discardProposal cleanup failed (non-critical): $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spendable = widget.spendableBalance;
    final visibleSpendableText = ZecAmount.fromZatoshi(
      spendable,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final spendableText = hideAmountIfPrivacyMode(
      visibleSpendableText,
      privacyModeEnabled: ref.watch(privacyModeProvider),
    );
    final colors = context.colors;

    _addressController.edgeHighlightColor = _isShieldedAddress
        ? colors.icon.success
        : null;

    final addressTone = switch (_addressType) {
      'unified' || 'sapling' => AppTextFieldTone.success,
      'invalid' || 'error' => AppTextFieldTone.destructive,
      _ => AppTextFieldTone.neutral,
    };
    final addressMessage = switch (_addressType) {
      'unified' || 'sapling' => 'Shielded Address',
      'transparent' => 'Transparent Address',
      'invalid' => 'Invalid address',
      'error' => 'Address validation failed',
      _ => null,
    };
    final addressMessageIcon = switch (_addressType) {
      'unified' || 'sapling' => AppIcon(
        AppIcons.shieldKeyhole,
        size: 16,
        color: colors.icon.success,
      ),
      'invalid' || 'error' => AppIcon(
        AppIcons.warning,
        size: 16,
        color: colors.text.destructive,
      ),
      'transparent' => AppIcon(
        AppIcons.transparentBalance,
        size: 16,
        color: colors.icon.muted,
      ),
      _ => null,
    };
    final addressMessageStyle = switch (_addressType) {
      'transparent' => AppTypography.labelMedium.copyWith(
        color: colors.text.muted,
      ),
      _ => null,
    };
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: SizedBox.expand(
          child: widget.walletAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                'Something went wrong. Try again in a moment.\n\n'
                'Details: $err',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
            ),
            data: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SendPageToolbar(),
                Expanded(
                  child: _SendMainContent(
                    child: _SendComposeLayout(
                      reviewButton: AppButton(
                        key: const ValueKey('send_review_button'),
                        onPressed: _canReview ? _openReview : null,
                        variant: AppButtonVariant.primary,
                        minWidth: 256,
                        trailing: _isSending
                            ? null
                            : const AppIcon(AppIcons.chevronForward),
                        child: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Review'),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SendFieldSurface(
                            child: AppTextField(
                              key: const ValueKey('send_address_field'),
                              label: 'Send to',
                              rightSlot: const _SendFieldRightLink(
                                label: 'Contacts',
                              ),
                              tone: addressTone,
                              focusNode: _addressFocusNode,
                              controller: _addressController,
                              hintText: 'Zcash Address',
                              leading: AppIcon(
                                AppIcons.plane,
                                size: 20,
                                color: _addressController.text.trim().isNotEmpty
                                    ? colors.icon.accent
                                    : colors.icon.regular,
                              ),
                              leadingSlotWidth: 32,
                              trailingSlotWidth: 40,
                              inputHorizontalPadding: AppSpacing.s,
                              messageText: addressMessage,
                              messageIcon: addressMessageIcon,
                              messageStyle: addressMessageStyle,
                              onChanged: (_) => _handleAddressChanged(),
                              keyboardType: TextInputType.text,
                              showClearButton: true,
                              onClear: () {
                                _addressSeq++;
                                _maxDebounceTimer?.cancel();
                                setState(() {
                                  _addressType = '';
                                  _error = null;
                                  if (_isMaxMode) {
                                    _validateSeq++;
                                    _maxSeq++;
                                    _maxQuote = null;
                                    _isResolvingMax = false;
                                    _amountError = '';
                                  }
                                });
                                if (!_isMaxMode) {
                                  _validateAmount();
                                }
                              },
                            ),
                          ),
                          const SizedBox(
                            height: _singleLineFieldOverlayReserve,
                          ),
                          const SizedBox(height: _singleLineFieldGap),
                          _SendFieldSurface(
                            child: AppTextField(
                              key: const ValueKey('send_amount_field'),
                              label: 'Amount',
                              tone: _showAmountError
                                  ? AppTextFieldTone.destructive
                                  : AppTextFieldTone.neutral,
                              focusNode: _amountFocusNode,
                              controller: _amountController,
                              hintText: '0.00',
                              leading: AppIcon(
                                AppIcons.zcash,
                                size: 20,
                                color: _amountController.text.trim().isNotEmpty
                                    ? colors.icon.accent
                                    : colors.icon.regular,
                              ),
                              leadingSlotWidth: 32,
                              trailingSlotWidth: 40,
                              inputHorizontalPadding: AppSpacing.s,
                              rightSlot: _SendMaxBalanceControl(
                                spendableText: spendableText,
                                onMaxPressed: _isResolvingMax
                                    ? null
                                    : _activateMaxMode,
                              ),
                              messageText: _showAmountError
                                  ? _amountError
                                  : null,
                              messageIcon: _showAmountError
                                  ? AppIcon(
                                      AppIcons.warning,
                                      size: 16,
                                      color: colors.text.destructive,
                                    )
                                  : null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                const ZecAmountInputFormatter(),
                              ],
                              onChanged: (_) => _handleAmountChanged(),
                              showClearButton: true,
                              onClear: () {
                                _maxDebounceTimer?.cancel();
                                _validateSeq++;
                                _maxSeq++;
                                setState(() {
                                  _isMaxMode = false;
                                  _isResolvingMax = false;
                                  _maxQuote = null;
                                  _amountError = '';
                                  _error = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(
                            height: _singleLineFieldOverlayReserve,
                          ),
                          const SizedBox(height: _singleLineFieldGap),
                          if (_showMemoControls) ...[
                            if (!_messageExpanded &&
                                _memoController.text.isEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                child: _SendAddMessageCard(
                                  onTap: () {
                                    setState(() {
                                      _messageExpanded = true;
                                    });
                                    _memoFocusNode.requestFocus();
                                  },
                                ),
                              ),
                            ] else ...[
                              _SendFieldSurface(
                                multiline: true,
                                child: AppTextField(
                                  label: 'Message',
                                  tone: _memoError != null
                                      ? AppTextFieldTone.destructive
                                      : AppTextFieldTone.neutral,
                                  focusNode: _memoFocusNode,
                                  controller: _memoController,
                                  hintText: 'Add a message',
                                  leading: AppIcon(
                                    AppIcons.scroll,
                                    size: 20,
                                    color: colors.icon.regular,
                                  ),
                                  rightSlot: Text(
                                    '$_memoLength/512',
                                    style: AppTypography.labelMedium.copyWith(
                                      color: colors.text.secondary,
                                    ),
                                  ),
                                  messageText: _memoError,
                                  messageIcon: _memoError != null
                                      ? AppIcon(
                                          AppIcons.warning,
                                          size: 16,
                                          color: colors.text.destructive,
                                        )
                                      : null,
                                  minLines: 6,
                                  maxLines: 6,
                                  scrollController: _memoScrollController,
                                  textStyle: AppTypography.bodyMedium.copyWith(
                                    color: colors.text.accent,
                                  ),
                                  onChanged: (_) => setState(() {
                                    _error = null;
                                  }),
                                  showClearButton: true,
                                  clearButtonRequiresText: false,
                                  clearButtonSemanticLabel: 'Close message',
                                  onClear: () {
                                    setState(() {
                                      _messageExpanded = false;
                                      _error = null;
                                    });
                                    if (_isMaxMode) {
                                      _scheduleMaxEstimate();
                                    } else {
                                      _validateAmount();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(
                                height: _multilineFieldOverlayReserve,
                              ),
                            ],
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _SendGlobalError(message: _error!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendMainContent extends StatelessWidget {
  const _SendMainContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

class _SendComposeLayout extends StatelessWidget {
  const _SendComposeLayout({required this.child, required this.reviewButton});

  static const _contentMaxWidth = 420.0;
  static const _formWidth = 352.0;
  static const _reviewButtonWidth = 256.0;
  static const _fieldsVerticalGap = AppSpacing.md;

  final Widget child;
  final Widget reviewButton;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              const _SendTitle(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: _fieldsVerticalGap,
                  ),
                  child: Center(
                    child: SizedBox(width: _formWidth, child: child),
                  ),
                ),
              ),
              SizedBox(width: _reviewButtonWidth, child: reviewButton),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendPageToolbar extends StatelessWidget {
  const _SendPageToolbar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 48,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppRouteBackLink(),
        ),
      ),
    );
  }
}

class _SendTitle extends StatelessWidget {
  const _SendTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Send $kZcashDefaultCurrencyTicker',
      style: AppTypography.headlineLarge.copyWith(
        color: context.colors.text.accent,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _SendFieldSurface extends StatelessWidget {
  const _SendFieldSurface({required this.child, this.multiline = false});

  final Widget child;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final shellTop = multiline ? 16.0 + AppSpacing.xs : 16.0 + AppSpacing.xxs;
    final shellHeight = multiline ? 148.0 : 46.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: shellTop,
          height: shellHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.small),
                boxShadow: _sendSurfaceShadow(context.colors),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _SendFieldRightLink extends StatelessWidget {
  const _SendFieldRightLink({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        AppIcon(AppIcons.chevronForward, size: 16, color: colors.icon.muted),
      ],
    );
  }
}

class _SendMaxBalanceControl extends StatelessWidget {
  const _SendMaxBalanceControl({
    required this.spendableText,
    required this.onMaxPressed,
  });

  final String spendableText;
  final VoidCallback? onMaxPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Use maximum spendable balance',
      hint: 'Your spendable balance may be lower than your total balance.',
      child: MouseRegion(
        cursor: onMaxPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMaxPressed,
          child: Text(
            'Max: $spendableText',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendAddMessageCard extends StatelessWidget {
  const _SendAddMessageCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = Container(
      width: 352,
      height: 96,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: _sendSurfaceShadow(colors),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.scroll, size: 16, color: colors.icon.accent),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Add a memo',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Encrypted, for Shielded Addresses only.',
            style: AppTypography.labelMedium.copyWith(color: colors.text.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

List<BoxShadow> _sendSurfaceShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
  ];
}

class _SendGlobalError extends StatelessWidget {
  const _SendGlobalError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIcon(
          AppIcons.warning,
          size: 16,
          color: context.colors.text.destructive,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
        ),
      ],
    );
  }
}
