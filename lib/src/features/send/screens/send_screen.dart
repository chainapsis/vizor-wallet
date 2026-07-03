import 'dart:async';
import 'dart:convert';

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
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/widgets/address_book_contact_picker_modal.dart';
import '../models/send_prefill_args.dart';
import '../services/send_flow.dart';

final sendWalletDbPathProvider = Provider<Future<String> Function()>((ref) {
  return getWalletDbPath;
});

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key, this.prefill});

  final SendPrefillArgs? prefill;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final accountState = ref.watch(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    final activeAccountIsHardware =
        accountState?.activeAccount?.isHardware ?? false;
    final sync = ref.watch(
      syncProvider.select(
        (value) =>
            (value.value ?? SyncState()).scopedToAccount(activeAccountUuid),
      ),
    );
    final spendableBalance = sync.spendableBalance;

    return _SendComposeBody(
      key: ValueKey('$activeAccountUuid:${widget.prefill?.fingerprint ?? ''}'),
      walletAsync: walletAsync,
      activeAccountUuid: activeAccountUuid,
      activeAccountIsHardware: activeAccountIsHardware,
      spendableBalance: spendableBalance,
      prefill: widget.prefill,
    );
  }
}

class _SendComposeBody extends ConsumerStatefulWidget {
  const _SendComposeBody({
    super.key,
    required this.walletAsync,
    required this.activeAccountUuid,
    required this.activeAccountIsHardware,
    required this.spendableBalance,
    this.prefill,
  });

  final AsyncValue<WalletState> walletAsync;
  final String? activeAccountUuid;
  final bool activeAccountIsHardware;
  final BigInt spendableBalance;
  final SendPrefillArgs? prefill;

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

class _SendComposeBodyState extends ConsumerState<_SendComposeBody> {
  static const _singleLineFieldOverlayReserve = 20.0;
  static const _singleLineFieldGap = AppSpacing.xs;
  static const _multilineFieldOverlayReserve = 24.0;
  static const _maxDebounceDuration = Duration(milliseconds: 300);
  static const _hardwareTexUnsupportedText =
      'Keystone does not support TEX sends yet.';
  final _addressController = _AddressTextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _addressFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();
  final _memoFocusNode = FocusNode();
  final _memoScrollController = ScrollController();
  late final String _sendFlowId = newSendFlowId();
  bool _isSending = false;
  bool _messageExpanded = false;
  bool _contactPickerOpen = false;
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
    _applyPrefill(widget.prefill);
    _memoController.addListener(_handleMemoChanged);
    _addressFocusNode.addListener(_handleFieldVisualStateChanged);
    _amountFocusNode.addListener(_handleFieldVisualStateChanged);
    _memoFocusNode.addListener(_handleFieldVisualStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  void _applyPrefill(SendPrefillArgs? prefill) {
    if (prefill == null) return;
    _addressController.text = prefill.address;
    if (prefill.amountText != null) {
      _amountController.text = prefill.amountText!;
      _amountError = null;
    }
    if (prefill.memoText != null && prefill.memoText!.isNotEmpty) {
      _memoController.text = prefill.memoText!;
      _messageExpanded = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_validateAddress());
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

  void _openContactPicker() {
    setState(() => _contactPickerOpen = true);
  }

  void _closeContactPicker() {
    setState(() => _contactPickerOpen = false);
  }

  void _selectContact(AddressBookContact contact) {
    final address = contact.address.trim();
    _addressController.value = TextEditingValue(
      text: address,
      selection: TextSelection.collapsed(offset: address.length),
    );
    setState(() => _contactPickerOpen = false);
    _handleAddressChanged();
  }

  @override
  void didUpdateWidget(covariant _SendComposeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spendableBalance != widget.spendableBalance) {
      if (_isMaxMode) {
        _scheduleMaxEstimate(immediate: true);
      } else if (_amountController.text.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _validateAmount();
        });
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
      final nextAddressType = result.isValid ? result.addressType : 'invalid';
      setState(() {
        _addressType = nextAddressType;
        if (_isTransparentLikeType(nextAddressType)) {
          _messageExpanded = false;
        }
      });
      if (_isTransparentLikeType(nextAddressType) &&
          _memoController.text.isNotEmpty) {
        _memoController.clear();
      }
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

  bool get _isTexAddress => _addressType == 'tex';
  bool get _isTransparentLikeAddress => _isTransparentLikeType(_addressType);

  bool _isTransparentLikeType(String addressType) =>
      addressType == 'transparent' || addressType == 'tex';

  String get _effectiveMemo =>
      _isTransparentLikeAddress ? '' : _memoController.text.trim();

  BigInt get _availableBalanceForCurrentAddress => widget.spendableBalance;
  String get _insufficientBalanceText =>
      _isTexAddress ? 'Insufficient balance' : 'Insufficient shielded balance';
  String get _insufficientBalanceToCoverFeeText =>
      '$_insufficientBalanceText to cover fee';
  String get _insufficientBalanceIncludingFeeText =>
      '$_insufficientBalanceText including fee';
  String _insufficientBalanceWithFeeText(String feeText) =>
      '$_insufficientBalanceText (fee: $feeText)';
  bool get _isHardwareTexSend =>
      _isTexAddress && widget.activeAccountIsHardware;

  bool get _showAmountError =>
      _amountError != null &&
      _amountError!.trim().isNotEmpty &&
      _amountError != _hardwareTexUnsupportedText;
  String? get _ctaWarningText =>
      _isHardwareTexSend ? _hardwareTexUnsupportedText : null;

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
      !_isHardwareTexSend &&
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
    if (_isHardwareTexSend) return _hardwareTexUnsupportedText;
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
      final dbPath = await ref.read(sendWalletDbPathProvider).call();
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
          _amountError = _insufficientBalanceToCoverFeeText;
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
          _amountError = _insufficientBalanceToCoverFeeText;
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

    final address = _addressController.text.trim();
    if (address.isEmpty ||
        _addressType == 'invalid' ||
        _addressType == 'error' ||
        _addressType.isEmpty) {
      setState(() => _amountError = null);
      return;
    }

    if (_isHardwareTexSend) {
      setState(() => _amountError = _hardwareTexUnsupportedText);
      return;
    }
    final available = _availableBalanceForCurrentAddress;
    if (zatoshi > available) {
      setState(() => _amountError = _insufficientBalanceText);
      return;
    }
    setState(() => _amountError = null);
    try {
      final dbPath = await ref.read(sendWalletDbPathProvider).call();
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
      if (totalNeeded > available) {
        final feeText = ZecAmount.fromZatoshi(fee).fee.toString();
        setState(() => _amountError = _insufficientBalanceWithFeeText(feeText));
      } else {
        setState(() => _amountError = null);
      }
    } catch (e) {
      if (!mounted || seq != _validateSeq) return;
      final msg = e.toString();
      if (msg.contains('InsufficientFunds') || msg.contains('insufficient')) {
        setState(() => _amountError = _insufficientBalanceIncludingFeeText);
      } else {
        log('Send: fee estimation failed (non-blocking): $e');
        setState(() => _amountError = null);
      }
    }
  }

  bool get _isAmountValid => _amountError == null;

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

      if (_isHardwareTexSend) {
        setState(() {
          _error = _hardwareTexUnsupportedText;
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
      final available = _availableBalanceForCurrentAddress;
      if (amountZatoshi > available) {
        setState(() {
          _error = '$_insufficientBalanceText.';
          _isSending = false;
        });
        return;
      }

      final memo = _effectiveMemo;

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
      final reviewArgs = await proposeSendTransfer(
        ref: ref,
        loadDbPath: ref.read(sendWalletDbPathProvider),
        accountUuid: accountUuid,
        sendFlowId: _sendFlowId,
        address: address,
        addressType: _addressType,
        amountZatoshi: amountZatoshi,
        memo: memo.isNotEmpty ? memo : null,
      );
      activeProposalId = reviewArgs.proposalId;

      if (!mounted) {
        return;
      }
      setState(() => _isSending = false);
      pushedReview = true;
      await context.push('/send/review', extra: reviewArgs);
    } catch (e) {
      log('Send: review preparation error: $e');
      if (!mounted) return;
      setState(() {
        _error = friendlyProposeSendError(e.toString());
        _isSending = false;
      });
    } finally {
      if (activeProposalId != null && !pushedReview) {
        await discardSendProposal(
          proposalId: activeProposalId,
          sendFlowId: _sendFlowId,
          logContext: 'Send(review not opened)',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableBalanceForCurrentAddress;
    final visibleSpendableText = ZecAmount.fromZatoshi(
      available,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final spendableText = hideAmountIfPrivacyMode(
      visibleSpendableText,
      privacyModeEnabled: ref.watch(privacyModeProvider),
    );
    final colors = context.colors;

    _addressController.edgeHighlightColor = null;

    final addressTone = switch (_addressType) {
      'invalid' || 'error' => AppTextFieldTone.destructive,
      _ => AppTextFieldTone.neutral,
    };
    final addressMessage = switch (_addressType) {
      'invalid' => 'Invalid address',
      'error' => 'Address validation failed',
      _ => null,
    };
    final addressMessageIcon = switch (_addressType) {
      'invalid' || 'error' => AppIcon(
        AppIcons.warning,
        size: 16,
        color: colors.text.destructive,
      ),
      _ => null,
    };
    final addressHasText = _addressController.text.trim().isNotEmpty;
    final addressLeadingIcon = switch (_addressType) {
      'unified' || 'sapling' => AppIcons.shieldKeyhole,
      'transparent' || 'tex' => AppIcons.transparentBalance,
      _ => AppIcons.plane,
    };
    final addressLeadingColor = switch (_addressType) {
      'unified' || 'sapling' => colors.icon.brandCrimson,
      'transparent' || 'tex' => colors.icon.muted,
      _ => addressHasText ? colors.icon.accent : colors.icon.regular,
    };
    final hideMemoControls = _isTransparentLikeAddress;
    final showMemoPrompt =
        !hideMemoControls && !_messageExpanded && _memoController.text.isEmpty;
    final VoidCallback? memoPromptOnTap = _isShieldedAddress
        ? () {
            setState(() {
              _messageExpanded = true;
            });
            _memoFocusNode.requestFocus();
          }
        : null;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppPaneToolbar(
                  leading: AppRouteBackLink(
                    key: ValueKey('send_pane_back_button'),
                    minWidth: 60,
                  ),
                ),
                Expanded(
                  child: widget.walletAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(
                      child: Text(
                        'Something went wrong. Try again in a moment.\n\n'
                        'Details: $err',
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.destructive,
                        ),
                      ),
                    ),
                    data: (_) => _SendComposeLayout(
                      reviewButton: AppButton(
                        key: const ValueKey('send_review_button'),
                        onPressed: _canReview ? _openReview : null,
                        variant: AppButtonVariant.primary,
                        minWidth: _SendComposeLayout.reviewButtonWidth,
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
                          AppTextField(
                            key: const ValueKey('send_address_field'),
                            label: 'Send to',
                            rightSlot: _SendContactsLabelButton(
                              label: 'Contacts',
                              onTap: _openContactPicker,
                            ),
                            tone: addressTone,
                            focusNode: _addressFocusNode,
                            controller: _addressController,
                            hintText: 'Zcash address',
                            leading: AppIcon(
                              addressLeadingIcon,
                              size: 20,
                              color: addressLeadingColor,
                            ),
                            messageText: addressMessage,
                            messageIcon: addressMessageIcon,
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
                          const SizedBox(
                            height: _singleLineFieldOverlayReserve,
                          ),
                          const SizedBox(height: _singleLineFieldGap),
                          AppTextField(
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
                            rightSlot: _SendMaxBalanceControl(
                              spendableText: spendableText,
                              onMaxPressed: _isResolvingMax
                                  ? null
                                  : _activateMaxMode,
                            ),
                            messageText: _showAmountError ? _amountError : null,
                            messageIcon: _showAmountError
                                ? AppIcon(
                                    AppIcons.warning,
                                    size: 16,
                                    color: colors.text.destructive,
                                  )
                                : null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [ZecAmountInputFormatter()],
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
                          const SizedBox(
                            height: _singleLineFieldOverlayReserve,
                          ),
                          const SizedBox(height: _singleLineFieldGap),
                          if (!hideMemoControls) ...[
                            if (showMemoPrompt) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                child: _SendAddMessageCard(
                                  onTap: memoPromptOnTap,
                                ),
                              ),
                            ] else ...[
                              AppTextField(
                                key: const ValueKey('send_memo_field'),
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
                                    color: _memoError != null
                                        ? colors.text.destructive
                                        : colors.text.secondary,
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
                              const SizedBox(
                                height: _multilineFieldOverlayReserve,
                              ),
                            ],
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _SendGlobalError(message: _error!),
                          ],
                          if (_error == null && _ctaWarningText != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _SendGlobalError(
                              key: const ValueKey('send_cta_warning'),
                              message: _ctaWarningText!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_contactPickerOpen)
              AppPaneModalOverlay(
                onDismiss: _closeContactPicker,
                child: Material(
                  type: MaterialType.transparency,
                  child: AddressBookContactPickerModal(
                    title: 'Contacts Zcash',
                    networks: const [AddressBookNetwork.zcash],
                    emptyTitle: 'No Zcash contacts',
                    onSelected: _selectContact,
                    onCancel: _closeContactPicker,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SendComposeLayout extends StatelessWidget {
  const _SendComposeLayout({required this.child, required this.reviewButton});

  static const contentWidth = 420.0;
  static const fieldsWidth = 396.0;
  static const reviewButtonWidth = 196.0;
  static const _containerHorizontalPadding = AppSpacing.s;
  static const _containerVerticalPadding = AppSpacing.md;
  static const _sectionGap = 32.0;
  static const _fieldsVerticalPadding = AppSpacing.xs;

  final Widget child;
  final Widget reviewButton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final minHeight = height == null
            ? 0.0
            : height < (_containerVerticalPadding * 2)
            ? 0.0
            : height - (_containerVerticalPadding * 2);

        return Center(
          child: SizedBox(
            width: contentWidth,
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _containerHorizontalPadding,
                vertical: _containerVerticalPadding,
              ),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _SendTitle(),
                      const SizedBox(height: _sectionGap),
                      SizedBox(
                        width: fieldsWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: _fieldsVerticalPadding,
                          ),
                          child: child,
                        ),
                      ),
                      const SizedBox(height: _sectionGap),
                      SizedBox(width: reviewButtonWidth, child: reviewButton),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

class _SendContactsLabelButton extends StatefulWidget {
  const _SendContactsLabelButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_SendContactsLabelButton> createState() =>
      _SendContactsLabelButtonState();
}

class _SendContactsLabelButtonState extends State<_SendContactsLabelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _hovered ? colors.text.accent : colors.text.secondary;
    return Semantics(
      button: true,
      label: 'Open contacts',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          key: const ValueKey('send_contacts_button'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: AppTypography.labelMedium.copyWith(color: color),
                ),
                const SizedBox(width: 2),
                AppIcon(AppIcons.chevronForward, size: 12, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }
}

class _SendMaxBalanceControl extends StatelessWidget {
  const _SendMaxBalanceControl({
    required this.spendableText,
    required this.onMaxPressed,
  });

  static const _tooltipTitle =
      'Your spendable balance may be lower than your total balance.';
  static const _tooltipBody =
      'Funds need confirmations before they can be spent: 3 for change from '
      'your own wallet, 10 for funds received from others. Shielded notes also '
      "need to be fully scanned. They'll become available shortly.";

  final String spendableText;
  final VoidCallback? onMaxPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxLabel = Text(
      'Max: $spendableText',
      style: AppTypography.labelMedium.copyWith(color: colors.text.secondary),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Use maximum spendable balance',
          child: MouseRegion(
            cursor: onMaxPressed == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMaxPressed,
              child: maxLabel,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        AppTooltip(
          richMessage: TextSpan(
            children: [
              TextSpan(
                text: _tooltipTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: '\n\n$_tooltipBody'),
            ],
          ),
          child: SizedBox(
            width: 18,
            height: 18,
            child: Center(
              child: AppIcon(
                AppIcons.help,
                size: 14,
                color: colors.icon.muted,
                semanticLabel: 'Spendable balance info',
              ),
            ),
          ),
        ),
      ],
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
      key: const ValueKey('send_add_memo_card'),
      width: double.infinity,
      height: 128,
      decoration: BoxDecoration(
        color: colors.surface.input.primary,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: _sendInputSurfaceShadow(colors),
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
            'Encrypted, for shielded addresses only.',
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

List<BoxShadow> _sendInputSurfaceShadow(AppColors colors) {
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
  const _SendGlobalError({super.key, required this.message});

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
