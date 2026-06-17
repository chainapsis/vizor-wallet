import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart'
    show InputDecoration, Scaffold, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../services/send_flow.dart';
import '../../widgets/send_recipient_resolver.dart';
import 'mobile_send_scan_screen.dart';

enum _SendStep { recipient, amount, review }

enum _SendPhase { compose, failed }

class _ReviewRecipientPresentation {
  const _ReviewRecipientPresentation({
    required this.headline,
    required this.verifyTitle,
    this.profilePictureId,
    this.useZecIcon = false,
  });

  final String headline;
  final String verifyTitle;
  final String? profilePictureId;
  final bool useZecIcon;

  Widget buildReviewLeading() {
    return KeyedSubtree(
      key: const ValueKey('mobile_send_review_recipient_picture'),
      child: useZecIcon
          ? const _ReviewZecIcon()
          : AppProfilePicture(
              profilePictureId: profilePictureId ?? '',
              size: AppProfilePictureSize.navLarge,
            ),
    );
  }

  Widget? buildVerifyLeading() {
    if (useZecIcon) return const _ReviewZecIcon();
    return AppProfilePicture(
      profilePictureId: profilePictureId ?? '',
      size: AppProfilePictureSize.large,
    );
  }
}

typedef MobileSendAddressValidator =
    Future<rust_sync.AddressValidationResult> Function({
      required String address,
    });

typedef MobileSendFeeEstimator =
    Future<BigInt> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String toAddress,
      required BigInt amountZatoshi,
      String? memo,
    });

typedef MobileSendScanner = Future<String?> Function(BuildContext context);

const _kMobileSendRecipientLineHeight = 17.0;
const _kMobileSendAddressActionHeight = 36.0;
const _kMobileSendAddressActionSlotWidth = 96.0;
const _kMobileSendAddressPasteWidth = 76.0;
const _kMobileSendAddressClearWidth = 73.0;
const _kMobileSendAddressErrorGap = AppSpacing.xxs;
const _kMobileSendAddressFieldGroupHeight =
    AppInputSizing.height +
    _kMobileSendAddressErrorGap +
    _kMobileSendRecipientLineHeight;
const _kMobileSendAmountFieldHeight = 178.0;
const _kMobileSendAmountInputHeight = 64.0;
const _kMobileSendAmountLineHeight = 17.0;
const _kMobileSendAmountCaretHeight = 48.0;
const _kMobileSendAmountCaretWidth = 3.0;
const _kMobileSendAmountFontSize = 48.0;
const _kMobileSendAmountLineHeightPx = 40.0;
const _kMobileSendAmountTopContentHeight = 299.0;
const _kMobileSendAmountRecipientBlockHeight = 97.0;
const _kMobileSendAmountRecipientLabelHeight = 25.0;
const _kMobileSendAmountRecipientRowHeight = 68.0;
const _kMobileSendReviewInfoHeight = 268.0;
const _kMobileSendReviewInfoRowHeight = 90.0;
const _kMobileSendReviewInfoDetailsHeight = 89.0;
const _kMobileSendReviewIconRowHeight = 24.0;
const _kMobileSendReviewWrapHeight = 161.0;
const _kMobileSendReviewRowHeight = 32.0;
const _kMobileSendReviewDividerHeight = 1.0;

/// The mobile send wizard — Figma `Send to` → `Enter amount` →
/// `Review Send` (4423:119950, 4479:47503, 4481:51525) plus the memo
/// modal (4484:62917). This screen owns proposal creation and hands
/// the proposal to the mobile status route for broadcast.
class MobileSendScreen extends ConsumerStatefulWidget {
  const MobileSendScreen({
    this.loadWalletDbPath = getWalletDbPath,
    this.validateAddress,
    this.estimateFee,
    this.openScanner = showMobileSendScanSheet,
    this.initialRecipient,
    this.initialAmount,
    this.initialAmountError,
    this.initialAmountReady = false,
    this.initialReview = false,
    this.initialMemo,
    this.initialContactLabel,
    this.initialContactPictureId,
    this.initialRecipientFocused = false,
    super.key,
  });

  /// Test seam: widget tests cannot complete the real file IO behind
  /// [getWalletDbPath] inside the fake-async zone.
  final Future<String> Function() loadWalletDbPath;

  /// Pre-fills the recipient step (e.g. the accounts row menu's
  /// "Send ZEC" action passes that account's shielded address).
  final String? initialRecipient;

  /// Preview/test seam for opening the amount step with a preset value.
  final String? initialAmount;
  final String? initialAmountError;
  final bool initialAmountReady;
  final bool initialReview;
  final String? initialMemo;

  /// Preview/test seam for recipient summary states.
  final String? initialContactLabel;
  final String? initialContactPictureId;
  final bool initialRecipientFocused;

  /// Preview/test seam for the direct Rust validation call.
  final MobileSendAddressValidator? validateAddress;

  /// Preview/test seam for the direct Rust fee-estimation call.
  final MobileSendFeeEstimator? estimateFee;

  /// Preview/test seam for the mobile scanner sheet.
  final MobileSendScanner openScanner;

  @override
  ConsumerState<MobileSendScreen> createState() => _MobileSendScreenState();
}

class _MobileSendScreenState extends ConsumerState<MobileSendScreen> {
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  late final String _sendFlowId = newSendFlowId();

  var _step = _SendStep.recipient;
  var _phase = _SendPhase.compose;
  var _isConfirmingSend = false;

  // Recipient state.
  String _addressType = '';
  String? _contactLabel;
  String? _contactPictureId;
  int _addressSeq = 0;

  // Amount state. The raw text is numpad-driven.
  String _amountText = '';
  String? _amountError = ''; // null = valid, '' = silently incomplete
  int _validateSeq = 0;

  // Review state.
  String _memo = '';
  BigInt? _feeZatoshi;
  int _feeSeq = 0;

  // Failure state.
  String? _error;

  @override
  void initState() {
    super.initState();
    _addressFocus.addListener(_handleAddressFocusChanged);
    final initial = widget.initialRecipient;
    if (initial != null && initial.trim().isNotEmpty) {
      _addressController.text = initial.trim();
      _addressType = 'unified';
      unawaited(_validateAddress());
    }
    final initialContactLabel = widget.initialContactLabel;
    if (initialContactLabel != null && initialContactLabel.trim().isNotEmpty) {
      _contactLabel = initialContactLabel.trim();
    }
    _contactPictureId = widget.initialContactPictureId;
    final initialMemo = widget.initialMemo;
    if (initialMemo != null && initialMemo.trim().isNotEmpty) {
      _memo = initialMemo.trim();
    }
    if (widget.initialAmount != null) {
      _step = widget.initialReview ? _SendStep.review : _SendStep.amount;
      _amountText = widget.initialAmount!.trim();
      _amountController.text = _amountText;
      if (widget.initialAmountError != null) {
        _amountError = widget.initialAmountError;
      } else if (widget.initialAmountReady || widget.initialReview) {
        _amountError = null;
        _feeZatoshi = BigInt.from(10000);
      } else if (_amountText.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_validateAmount());
        });
      }
    }
    if (widget.initialRecipientFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addressFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _addressFocus.removeListener(_handleAddressFocusChanged);
    _addressController.dispose();
    _addressFocus.dispose();
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  // ── Recipient step ─────────────────────────────────────────────────

  bool get _hasValidAddress =>
      _addressController.text.trim().isNotEmpty &&
      _addressType.isNotEmpty &&
      _addressType != 'invalid' &&
      _addressType != 'error';

  bool get _showRecipientContinue =>
      _addressController.text.trim().isNotEmpty || _addressFocus.hasFocus;

  bool get _showRecipientFocusOverlay =>
      _phase == _SendPhase.compose &&
      _step == _SendStep.recipient &&
      _addressFocus.hasFocus;

  bool get _routePopAllowed =>
      _phase == _SendPhase.compose &&
      _step == _SendStep.recipient &&
      !_isConfirmingSend;

  bool get _isShieldedAddress =>
      _addressType == 'unified' || _addressType == 'sapling';

  void _handleAddressFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _validateAddress() async {
    final seq = ++_addressSeq;
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      if (mounted && seq == _addressSeq) setState(() => _addressType = '');
      return;
    }
    try {
      final result =
          await (widget.validateAddress ?? rust_sync.validateAddress)(
            address: address,
          );
      if (!mounted || seq != _addressSeq) return;
      setState(
        () => _addressType = result.isValid ? result.addressType : 'invalid',
      );
    } catch (e) {
      log('MobileSend: address validation error: $e');
      if (!mounted || seq != _addressSeq) return;
      setState(() => _addressType = 'error');
    }
  }

  void _handleAddressChanged({bool clearContact = true}) {
    setState(() {
      if (clearContact) {
        _contactLabel = null;
        _contactPictureId = null;
      }
      _addressType = '';
    });
    unawaited(_validateAddress());
  }

  void _selectContact(AddressBookContact contact) {
    final address = contact.address.trim();
    _addressController.value = TextEditingValue(
      text: address,
      selection: TextSelection.collapsed(offset: address.length),
    );
    setState(() {
      _contactLabel = contact.label.trim().isEmpty
          ? null
          : contact.label.trim();
      _contactPictureId = contact.profilePictureId;
    });
    _handleAddressChanged(clearContact: false);
  }

  Future<void> _openScanner() async {
    final scanned = await widget.openScanner(context);
    if (scanned == null || scanned.trim().isEmpty || !mounted) return;
    _addressController.value = TextEditingValue(
      text: scanned.trim(),
      selection: TextSelection.collapsed(offset: scanned.trim().length),
    );
    _handleAddressChanged();
  }

  Future<void> _pasteAddress() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text?.trim() ?? '';
    if (pasted.isEmpty || !mounted) return;
    _addressController.value = TextEditingValue(
      text: pasted,
      selection: TextSelection.collapsed(offset: pasted.length),
    );
    _handleAddressChanged();
  }

  void _clearAddress() {
    _addressController.clear();
    _handleAddressChanged();
  }

  Future<void> _showFullAddressSheet(
    String address,
    _ReviewRecipientPresentation recipient,
  ) {
    return showMobileAddressVerifySheet(
      context,
      title: recipient.verifyTitle,
      address: address,
      leading: recipient.buildVerifyLeading(),
    );
  }

  void _continueToAmount() {
    if (!_hasValidAddress) return;
    _addressFocus.unfocus();
    setState(() => _step = _SendStep.amount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
    unawaited(_validateAmount());
  }

  // ── Amount step ────────────────────────────────────────────────────

  BigInt get _spendable {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    return (ref.read(syncProvider).value ?? SyncState())
        .scopedToAccount(accountUuid)
        .spendableBalance;
  }

  void _handleAmountChanged(String value) {
    setState(() => _amountText = value.trim());
    unawaited(_validateAmount());
  }

  /// Same shape as the desktop validator — quick spendable pre-check,
  /// then a seq-guarded fee estimate so the total is covered. The
  /// mobile copy is the design's "Not enough ZEC".
  Future<void> _validateAmount() async {
    final seq = ++_validateSeq;
    final text = _amountText.trim();
    if (text.isEmpty || text == '.' || text == '0.') {
      setState(() => _amountError = '');
      return;
    }
    final zatoshi = parseZecAmount(text);
    if (zatoshi == null || zatoshi <= BigInt.zero) {
      setState(() => _amountError = '');
      return;
    }
    if (zatoshi > _spendable) {
      setState(() => _amountError = 'Not enough ZEC');
      return;
    }
    // Block Continue until the fee estimate confirms the total fits —
    // otherwise a quick Continue tap right after typing rides on the
    // previous amount's validation result.
    setState(() => _amountError = '');

    try {
      final dbPath = await widget.loadWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (!mounted || seq != _validateSeq || accountUuid == null) return;
      final fee = await (widget.estimateFee ?? rust_sync.estimateFee)(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        toAddress: _addressController.text.trim(),
        amountZatoshi: zatoshi,
        memo: _effectiveMemo.isNotEmpty ? _effectiveMemo : null,
      );
      if (!mounted || seq != _validateSeq) return;
      if (zatoshi + fee > _spendable) {
        setState(() => _amountError = 'Not enough ZEC');
      } else {
        setState(() {
          _amountError = null;
          _feeZatoshi = fee;
        });
      }
    } catch (e) {
      if (!mounted || seq != _validateSeq) return;
      final msg = e.toString();
      if (msg.contains('InsufficientFunds') || msg.contains('insufficient')) {
        setState(() => _amountError = 'Not enough ZEC');
      } else {
        log('MobileSend: fee estimation failed (non-blocking): $e');
        setState(() => _amountError = null);
      }
    }
  }

  bool get _amountReady =>
      _amountError == null &&
      (parseZecAmount(_amountText.trim()) ?? BigInt.zero) > BigInt.zero;

  void _continueToReview() {
    if (!_amountReady) return;
    _amountFocus.unfocus();
    setState(() => _step = _SendStep.review);
    // Refresh the fee for the review card (the memo may change it).
    unawaited(_estimateReviewFee());
  }

  // ── Review step ────────────────────────────────────────────────────

  String get _effectiveMemo => _isShieldedAddress ? _memo.trim() : '';

  Future<void> _estimateReviewFee() async {
    final seq = ++_feeSeq;
    final zatoshi = parseZecAmount(_amountText.trim());
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (zatoshi == null || accountUuid == null) return;
    try {
      final dbPath = await widget.loadWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      if (!mounted || seq != _feeSeq) return;
      final fee = await (widget.estimateFee ?? rust_sync.estimateFee)(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        toAddress: _addressController.text.trim(),
        amountZatoshi: zatoshi,
        memo: _effectiveMemo.isNotEmpty ? _effectiveMemo : null,
      );
      if (!mounted || seq != _feeSeq) return;
      setState(() => _feeZatoshi = fee);
    } catch (e) {
      log('MobileSend: review fee estimate failed (non-blocking): $e');
    }
  }

  Future<void> _editMemo() async {
    // A bottom sheet, not a top-pinned card: the modal rises from the
    // bottom and the sheet frame floats it 16px above the software
    // keyboard (Figma `Review Add Memo`, 4638:74505).
    final next = await showAppMobileSheet<String>(
      context: context,
      builder: (_) => _MemoSheet(initial: _memo),
    );
    if (next == null || !mounted) return;
    setState(() => _memo = next);
    unawaited(_estimateReviewFee());
  }

  Future<void> _showFeeInfo() {
    return showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colors = sheetContext.colors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tx fee',
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The network fee is set by the Zcash protocol (ZIP 317) '
                'based on the transaction size. Vizor adds no extra fee.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAndSend() async {
    if (_phase != _SendPhase.compose || _isConfirmingSend) return;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(accountUuid);
    final amountZatoshi = parseZecAmount(_amountText.trim());
    if (amountZatoshi == null || amountZatoshi <= BigInt.zero) return;

    setState(() {
      _isConfirmingSend = true;
      _error = null;
    });

    SendReviewArgs args;
    try {
      args = await proposeSendTransfer(
        ref: ref,
        loadDbPath: widget.loadWalletDbPath,
        accountUuid: accountUuid,
        sendFlowId: _sendFlowId,
        address: _addressController.text.trim(),
        addressType: _addressType,
        amountZatoshi: amountZatoshi,
        memo: _effectiveMemo.isNotEmpty ? _effectiveMemo : null,
      );
    } catch (e) {
      log('MobileSend: propose error: $e');
      if (!mounted) return;
      setState(() {
        _isConfirmingSend = false;
        _phase = _SendPhase.failed;
        _error = friendlyProposeSendError(e.toString());
      });
      return;
    }
    if (!mounted) {
      unawaited(
        discardSendProposal(
          proposalId: args.proposalId,
          sendFlowId: _sendFlowId,
          logContext: 'MobileSend(unmounted)',
        ),
      );
      return;
    }
    setState(() => _feeZatoshi = args.feeZatoshi);

    KeystoneBroadcastArgs? keystone;
    if (isHardware) {
      // Hand the PCZT to the device for the spend-auth signature; the
      // signing screen owns the QR display/scan round trip.
      keystone = await context.push<KeystoneBroadcastArgs>(
        '/send/keystone-sign',
        extra: args,
      );
      if (keystone == null) {
        // Cancelled (or failed before signing). The signing screen may
        // already have consumed the proposal — discard is idempotent.
        unawaited(
          discardSendProposal(
            proposalId: args.proposalId,
            sendFlowId: _sendFlowId,
            logContext: 'MobileSend(keystone cancelled)',
          ),
        );
        if (mounted) {
          setState(() {
            _isConfirmingSend = false;
            _phase = _SendPhase.compose;
          });
        }
        return;
      }
      if (!mounted) return;
      context.pushReplacement('/send/status', extra: keystone);
      return;
    }

    if (!mounted) return;
    context.pushReplacement('/send/status', extra: args);
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _handleBack() {
    switch (_phase) {
      case _SendPhase.failed:
        setState(() => _phase = _SendPhase.compose);
        return;
      case _SendPhase.compose:
        break;
    }
    switch (_step) {
      case _SendStep.recipient:
        context.pop();
      case _SendStep.amount:
        _amountFocus.unfocus();
        setState(() => _step = _SendStep.recipient);
      case _SendStep.review:
        setState(() => _step = _SendStep.amount);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _amountFocus.requestFocus();
        });
    }
  }

  String _truncateAddress(String address) {
    final value = address.trim();
    if (value.length <= 28) return value;
    return '${value.substring(0, 13)} ... '
        '${value.substring(value.length - 11)}';
  }

  String _compactReviewAddress(String address) {
    final value = address.trim();
    if (value.length <= 18) return value;
    return '${value.substring(0, 7)} .... '
        '${value.substring(value.length - 7)}';
  }

  _ReviewRecipientPresentation _reviewRecipientPresentation({
    required String address,
    required Iterable<AddressBookContact> contacts,
    required Map<String, AccountInfo> ownAccounts,
  }) {
    final contact = _contactForAddress(contacts, address);
    if (contact != null) {
      final label = contact.label.trim();
      return _ReviewRecipientPresentation(
        headline: label,
        verifyTitle: label,
        profilePictureId: contact.profilePictureId,
      );
    }

    final account = _ownAccountForAddress(ownAccounts, address);
    if (account != null) {
      return _ReviewRecipientPresentation(
        headline: account.name,
        verifyTitle: account.name,
        profilePictureId: account.profilePictureId,
      );
    }

    final rememberedContactLabel = _contactLabel?.trim();
    if (rememberedContactLabel != null && rememberedContactLabel.isNotEmpty) {
      return _ReviewRecipientPresentation(
        headline: rememberedContactLabel,
        verifyTitle: rememberedContactLabel,
        profilePictureId: _contactPictureId,
      );
    }

    final fallbackLabel = _fallbackAddressTypeLabel();
    return _ReviewRecipientPresentation(
      headline: fallbackLabel,
      verifyTitle: fallbackLabel,
      useZecIcon: true,
    );
  }

  String _fallbackAddressTypeLabel() {
    return switch (_addressType) {
      'unified' => 'Unified address',
      'sapling' => 'Shielded address',
      'transparent' => 'Transparent address',
      _ => 'Zcash address',
    };
  }

  AddressBookContact? _contactForAddress(
    Iterable<AddressBookContact> contacts,
    String address,
  ) {
    final target = address.trim();
    if (target.isEmpty) return null;
    for (final contact in contacts) {
      if (contact.network != AddressBookNetwork.zcash) continue;
      if (contact.address.trim() != target) continue;
      if (contact.label.trim().isEmpty) continue;
      return contact;
    }
    return null;
  }

  AccountInfo? _ownAccountForAddress(
    Map<String, AccountInfo> ownAccounts,
    String address,
  ) {
    final target = address.trim();
    if (target.isEmpty) return null;
    final account = ownAccounts[target];
    if (account == null || account.name.trim().isEmpty) return null;
    return account;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showRecipientFocusOverlay = _showRecipientFocusOverlay;
    final showRecipientFieldLayer =
        _phase == _SendPhase.compose && _step == _SendStep.recipient;

    final title = switch (_phase) {
      _SendPhase.compose => switch (_step) {
        _SendStep.recipient => 'Select Recipient',
        _SendStep.amount => 'Enter amount',
        _SendStep.review => 'Review Send',
      },
      _SendPhase.failed => 'Send failed',
    };

    final body = switch (_phase) {
      _SendPhase.compose => switch (_step) {
        _SendStep.recipient => _buildRecipientStep(
          context,
          hasFocusedRecipient: showRecipientFocusOverlay,
        ),
        _SendStep.amount => _buildAmountStep(context),
        _SendStep.review => _buildReviewStep(context),
      },
      _ => _buildStatus(context),
    };

    return PopScope<void>(
      canPop: _routePopAllowed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        resizeToAvoidBottomInset: true,
        body: AppToastHost(
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    MobileTopNav.back(title: title, onBack: _handleBack),
                    Expanded(child: body),
                  ],
                ),
              ),
              if (showRecipientFocusOverlay) ...[
                Positioned.fill(
                  key: const ValueKey(
                    'mobile_send_recipient_focus_scrim_layer',
                  ),
                  child: GestureDetector(
                    key: const ValueKey('mobile_send_recipient_focus_scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _addressFocus.unfocus,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
              if (showRecipientFieldLayer)
                Positioned(
                  key: const ValueKey('mobile_send_recipient_field_layer'),
                  top:
                      MediaQuery.paddingOf(context).top +
                      kMobileTopNavHeight +
                      AppSpacing.s,
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: _buildAddressFieldGroup(context),
                ),
              if (showRecipientFocusOverlay) ...[
                if (_showRecipientContinue)
                  Positioned(
                    key: const ValueKey(
                      'mobile_send_recipient_focus_continue_layer',
                    ),
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.s,
                    child: _buildRecipientContinueButton(
                      context,
                      useBackdropColors: true,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Step bodies ────────────────────────────────────────────────────

  Widget _buildRecipientStep(
    BuildContext context, {
    required bool hasFocusedRecipient,
  }) {
    final colors = context.colors;
    final contacts = [
      for (final contact
          in ref.watch(addressBookProvider).value?.contacts ??
              const <AddressBookContact>[])
        if (contact.network == AddressBookNetwork.zcash) contact,
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s +
                  _kMobileSendAddressFieldGroupHeight +
                  AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            children: [
              Semantics(
                button: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_send_scan_row'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_openScanner()),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 32,
                          decoration: BoxDecoration(
                            color: colors.background.neutralSubtleOpacity,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: Center(
                            child: AppIcon(
                              AppIcons.qr,
                              size: 16,
                              color: colors.icon.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RecipientLineText(
                                'Scan a QR Code',
                                color: colors.text.accent,
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              _RecipientLineText(
                                'Scan an address using camera',
                                color: colors.text.secondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxs),
                        child: Row(
                          children: [
                            AppIcon(
                              AppIcons.users,
                              size: 20,
                              color: colors.icon.muted,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Text(
                              '${contacts.length} '
                              'contact${contacts.length == 1 ? '' : 's'}',
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (var i = 0; i < contacts.length; i++) ...[
                        Semantics(
                          button: true,
                          child: GestureDetector(
                            key: ValueKey(
                              'mobile_send_contact_${contacts[i].id}',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _selectContact(contacts[i]),
                            child: SizedBox(
                              height: 44,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    height: 32,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: AppProfilePicture(
                                        profilePictureId:
                                            contacts[i].profilePictureId,
                                        size: AppProfilePictureSize.large,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _RecipientLineText(
                                          contacts[i].label,
                                          color: colors.text.accent,
                                        ),
                                        const SizedBox(height: AppSpacing.xxs),
                                        _RecipientLineText(
                                          _truncateAddress(contacts[i].address),
                                          color: colors.text.secondary,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (i != contacts.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_showRecipientContinue && !hasFocusedRecipient)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.s,
            ),
            child: _buildRecipientContinueButton(context),
          ),
      ],
    );
  }

  Widget _buildAddressFieldGroup(BuildContext context) {
    return Column(
      key: const ValueKey('mobile_send_address_field_group'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildAddressField(context), _buildAddressErrorSpace(context)],
    );
  }

  Widget _buildAddressField(BuildContext context) {
    final colors = context.colors;
    final showAction = _addressFocus.hasFocus;
    final hasAddressError =
        _addressType == 'invalid' || _addressType == 'error';
    return MobileTextField(
      key: const ValueKey('mobile_send_address_field'),
      fieldKey: const ValueKey('mobile_send_address_input'),
      controller: _addressController,
      focusNode: _addressFocus,
      hintText: 'Zcash Address',
      leading: SizedBox(
        width: AppInputSizing.iconWrapWidth,
        height: AppInputSizing.height,
        child: Align(
          alignment: Alignment.centerRight,
          child: AppIcon(
            AppIcons.plane,
            size: 20,
            color: _addressController.text.trim().isEmpty
                ? colors.icon.regular
                : colors.icon.accent,
          ),
        ),
      ),
      restingBorderColor: hasAddressError
          ? colors.border.utilityDestructive
          : null,
      focusedBorderColor: hasAddressError
          ? colors.border.utilityDestructive
          : const Color(0x00000000),
      focusedBoxShadow: showAction
          ? [
              BoxShadow(
                color: colors.background.neutralScrim,
                offset: const Offset(0, 4),
                blurRadius: 4,
                spreadRadius: 1000,
              ),
            ]
          : null,
      trailing: showAction
          ? SizedBox(
              key: const ValueKey('mobile_send_address_action_slot'),
              width: _kMobileSendAddressActionSlotWidth,
              height: AppInputSizing.height,
              child: Center(
                child: _AddressFieldActionButton(
                  label: _addressController.text.trim().isEmpty
                      ? 'Paste'
                      : 'Clear',
                  onTap: _addressController.text.trim().isEmpty
                      ? () => unawaited(_pasteAddress())
                      : _clearAddress,
                ),
              ),
            )
          : null,
      onChanged: (_) => _handleAddressChanged(),
      keyboardType: TextInputType.text,
    );
  }

  Widget _buildAddressErrorSpace(BuildContext context) {
    final colors = context.colors;
    final showError = _addressType == 'invalid' || _addressType == 'error';
    return SizedBox(
      height: _kMobileSendAddressErrorGap + _kMobileSendRecipientLineHeight,
      child: showError
          ? Padding(
              padding: const EdgeInsets.only(top: _kMobileSendAddressErrorGap),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  _addressType == 'invalid'
                      ? 'Invalid address'
                      : 'Address validation failed',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildRecipientContinueButton(
    BuildContext context, {
    bool useBackdropColors = false,
  }) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        key: const ValueKey('mobile_send_continue'),
        expand: true,
        constrainContent: true,
        disabledBackgroundColor: useBackdropColors
            ? Color.alphaBlend(colors.button.disabled.bg, colors.surface.input)
            : null,
        enabledBorderColor: useBackdropColors
            ? colors.border.subtleOpacity
            : null,
        onPressed: _hasValidAddress ? _continueToAmount : null,
        child: Text(
          _addressController.text.trim().isEmpty
              ? 'Enter address to continue'
              : 'Continue',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildAmountStep(BuildContext context) {
    final colors = context.colors;
    final spendableText = ZecAmount.fromZatoshi(
      _spendable,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final showError = _amountError != null && _amountError!.isNotEmpty;
    final amountStyle = AppTypography.displayLarge.copyWith(
      color: showError ? colors.text.destructive : colors.text.accent,
      fontSize: _kMobileSendAmountFontSize,
      height: _kMobileSendAmountLineHeightPx / _kMobileSendAmountFontSize,
      fontWeight: FontWeight.w500,
    );

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: const ValueKey('mobile_send_amount_top_content'),
                height: _kMobileSendAmountTopContentHeight,
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAmountField(
                      context,
                      showError: showError,
                      spendableText: spendableText,
                      amountStyle: amountStyle,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      key: const ValueKey('mobile_send_amount_recipient_block'),
                      height: _kMobileSendAmountRecipientBlockHeight,
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: _kMobileSendAmountRecipientLabelHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Sending to',
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          SizedBox(
                            key: const ValueKey(
                              'mobile_send_amount_recipient_row',
                            ),
                            height: _kMobileSendAmountRecipientRowHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s,
                              ),
                              child: Row(
                                children: [
                                  AppProfilePicture(
                                    key: const ValueKey(
                                      'mobile_send_amount_recipient_picture',
                                    ),
                                    profilePictureId: _contactPictureId ?? '',
                                    size: AppProfilePictureSize.navLarge,
                                  ),
                                  const SizedBox(width: AppSpacing.s),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: _contactLabel == null
                                          ? [
                                              _RecipientLineText(
                                                _truncateAddress(
                                                  _addressController.text,
                                                ),
                                                color: colors.text.accent,
                                              ),
                                            ]
                                          : [
                                              _RecipientLineText(
                                                _contactLabel!,
                                                color: colors.text.accent,
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.xxs,
                                              ),
                                              _RecipientLineText(
                                                _truncateAddress(
                                                  _addressController.text,
                                                ),
                                                color: colors.text.secondary,
                                              ),
                                            ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.s,
          ),
          child: SizedBox(
            width: double.infinity,
            child: AppButton(
              key: const ValueKey('mobile_send_review_button'),
              expand: true,
              constrainContent: true,
              onPressed: _amountReady ? _continueToReview : null,
              child: Text(
                _amountReady ? 'Finish & Review' : 'Enter amount to continue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountField(
    BuildContext context, {
    required bool showError,
    required String spendableText,
    required TextStyle amountStyle,
  }) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('mobile_send_amount_field'),
      height: _kMobileSendAmountFieldHeight,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: _kMobileSendAmountLineHeight,
              child: showError
                  ? Center(
                      child: Text(
                        _amountError!,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.destructive,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              height: _kMobileSendAmountInputHeight,
              child: TextField(
                key: const ValueKey('mobile_send_amount_input'),
                controller: _amountController,
                focusNode: _amountFocus,
                autofocus: true,
                onChanged: _handleAmountChanged,
                onSubmitted: (_) => _amountFocus.unfocus(),
                onTapOutside: (_) => _amountFocus.unfocus(),
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: const [
                  CommaToDotInputFormatter(),
                  _ZecAmountInputFormatter(maxFractionDigits: 8, maxLength: 17),
                ],
                maxLines: 1,
                style: amountStyle,
                cursorColor: showError
                    ? colors.text.destructive
                    : colors.text.accent,
                cursorWidth: _kMobileSendAmountCaretWidth,
                cursorHeight: _kMobileSendAmountCaretHeight,
                cursorRadius: const Radius.circular(AppRadii.full),
                decoration: InputDecoration.collapsed(
                  hintText: '0',
                  hintStyle: amountStyle.copyWith(color: colors.text.disabled),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              height: _kMobileSendAmountLineHeight,
              child: Text(
                'Max: $spendableText',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    // Uppercase ticker per the mobile review frame ("123.12 ZEC").
    final amountText =
        ZecAmount.tryParse(_amountText)?.activityDetail.toString() ??
        '$_amountText ZEC';
    final amountZatoshi = parseZecAmount(_amountText.trim());
    final amountFiatText = amountZatoshi == null
        ? null
        : fiatTextForZatoshi(
            amountZatoshi,
            zecUsdUnitPrice: ref.watch(zecHomeUsdUnitPriceProvider),
          );
    final feeText = _feeZatoshi == null
        ? '—'
        : ZecAmount.fromZatoshi(_feeZatoshi!).fee.toString();
    final address = _addressController.text.trim();
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = _reviewRecipientPresentation(
      address: address,
      contacts: addressBookContacts,
      ownAccounts: ownAccounts,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    key: const ValueKey('mobile_send_review_info'),
                    height: _kMobileSendReviewInfoHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          _ReviewInfoRow(
                            leading: const _ReviewZecIcon(),
                            title: 'Amount',
                            headline: amountText,
                            headlineKey: const ValueKey(
                              'mobile_send_review_amount',
                            ),
                            detail: amountFiatText,
                            detailKey: const ValueKey(
                              'mobile_send_review_amount_fiat',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const SizedBox(
                            width: 40,
                            height: _kMobileSendReviewIconRowHeight,
                            child: Center(
                              child: AppIcon(AppIcons.arrowDownward, size: 24),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _ReviewInfoRow(
                            leading: recipient.buildReviewLeading(),
                            title: 'To',
                            headline: recipient.headline,
                            bottom: _ReviewAddressLine(
                              address: _compactReviewAddress(address),
                              isShielded: _isShieldedAddress,
                              onFullAddress: () => unawaited(
                                _showFullAddressSheet(address, recipient),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  _ReviewWrap(
                    isShielded: _isShieldedAddress,
                    memo: _memo.trim(),
                    feeText: feeText,
                    onMemoTap: () => unawaited(_editMemo()),
                    onFeeInfoTap: () => unawaited(_showFeeInfo()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const ValueKey('mobile_send_review_buttons'),
            height: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const ValueKey('mobile_send_confirm'),
                  expand: true,
                  onPressed: _isConfirmingSend
                      ? null
                      : () => unawaited(_confirmAndSend()),
                  leading: const AppIcon(AppIcons.plane, size: 20),
                  child: Text(
                    _isConfirmingSend ? 'Preparing...' : 'Confirm & Send',
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('mobile_send_cancel'),
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = context.colors;
    final amountText =
        ZecAmount.tryParse(_amountText)?.receipt.toString() ??
        '$_amountText ZEC';
    final toLabel =
        _contactLabel ?? _truncateAddress(_addressController.text.trim());

    return Padding(
      key: ValueKey('mobile_send_status_${_phase.name}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  AppIcons.warning,
                  size: 48,
                  color: colors.text.destructive,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Send failed',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  '$amountText to $toLabel',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              key: const ValueKey('mobile_send_try_again'),
              onPressed: () => setState(() => _phase = _SendPhase.compose),
              child: const Text('Try again'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/home'),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Back to wallet',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _ZecAmountInputFormatter extends TextInputFormatter {
  const _ZecAmountInputFormatter({
    required this.maxFractionDigits,
    required this.maxLength,
  });

  final int maxFractionDigits;
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    var hasDecimal = false;
    for (final codeUnit in text.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      if (ch == '.') {
        if (hasDecimal) continue;
        hasDecimal = true;
        buffer.write(ch);
        continue;
      }
      if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        buffer.write(ch);
      }
    }

    text = buffer.toString();
    if (text.startsWith('.')) text = '0$text';
    if (text.length > maxLength) text = text.substring(0, maxLength);
    final decimalIndex = text.indexOf('.');
    if (decimalIndex >= 0) {
      final maxEnd = decimalIndex + 1 + maxFractionDigits;
      if (text.length > maxEnd) text = text.substring(0, maxEnd);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _ReviewZecIcon extends StatelessWidget {
  const _ReviewZecIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        // Zcash brand yellow — fixed brand color like the crimson shield,
        // not a theme token.
        color: Color(0xFFF4B728),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: AppIcon(
          AppIcons.zcashCurrency,
          size: 22,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

class _ReviewInfoRow extends StatelessWidget {
  const _ReviewInfoRow({
    required this.leading,
    required this.title,
    required this.headline,
    this.headlineKey,
    this.detail,
    this.detailKey,
    this.bottom,
  }) : assert(detail == null || bottom == null);

  final Widget leading;
  final String title;
  final String headline;
  final Key? headlineKey;
  final String? detail;
  final Key? detailKey;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detailText = detail;
    return SizedBox(
      height: _kMobileSendReviewInfoRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SizedBox(
              height: _kMobileSendReviewInfoDetailsHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: _kMobileSendReviewIconRowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    height: 33,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        headline,
                        key: headlineKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.headlineLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    height: _kMobileSendReviewIconRowHeight,
                    child:
                        bottom ??
                        Align(
                          alignment: Alignment.centerLeft,
                          child: detailText == null
                              ? const SizedBox.shrink()
                              : Text(
                                  detailText,
                                  key: detailKey,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewAddressLine extends StatelessWidget {
  const _ReviewAddressLine({
    required this.address,
    required this.isShielded,
    required this.onFullAddress,
  });

  final String address;
  final bool isShielded;
  final VoidCallback onFullAddress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              AppIcon(
                isShielded
                    ? AppIcons.shieldKeyhole
                    : AppIcons.transparentBalance,
                size: 16,
                color: isShielded
                    ? colors.icon.brandCrimson
                    : colors.icon.muted,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  address,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        _ReviewSmallButton(
          key: const ValueKey('mobile_send_full_address'),
          icon: AppIcons.eye,
          label: 'Full address',
          onTap: onFullAddress,
        ),
      ],
    );
  }
}

class _ReviewSmallButton extends StatelessWidget {
  const _ReviewSmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 16, color: colors.button.ghost.label),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.button.ghost.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewWrap extends StatelessWidget {
  const _ReviewWrap({
    required this.isShielded,
    required this.memo,
    required this.feeText,
    required this.onMemoTap,
    required this.onFeeInfoTap,
  });

  final bool isShielded;
  final String memo;
  final String feeText;
  final VoidCallback onMemoTap;
  final VoidCallback onFeeInfoTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('mobile_send_review_wrap'),
      height: isShielded ? _kMobileSendReviewWrapHeight : 96,
      child: MobileSurfaceCard(
        cornerRadius: AppRadii.xLarge - AppSpacing.xs,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.base,
        ),
        child: Column(
          children: [
            if (isShielded) ...[
              _ReviewListRow(
                key: const ValueKey('mobile_send_memo_row'),
                onTap: onMemoTap,
                leftLabel: memo.isEmpty ? null : 'Message',
                rightLabel: memo.isEmpty ? 'Add short encrypted message' : memo,
                rightIcon: memo.isEmpty
                    ? AppIcons.edit
                    : AppIcons.doubleArrowVertical,
                centered: memo.isEmpty,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                height: _kMobileSendReviewDividerHeight,
                color: colors.border.regular,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _ReviewListRow(
              leftLabel: 'Tx fee',
              rightLabel: feeText,
              rightIcon: AppIcons.help,
              rightKey: const ValueKey('mobile_send_fee'),
              onTap: onFeeInfoTap,
              semanticLabel: 'About the transaction fee',
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewListRow extends StatelessWidget {
  const _ReviewListRow({
    required this.rightLabel,
    this.leftLabel,
    this.rightIcon,
    this.rightKey,
    this.onTap,
    this.semanticLabel,
    this.centered = false,
    super.key,
  });

  final String? leftLabel;
  final String rightLabel;
  final String? rightIcon;
  final Key? rightKey;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final right = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.end,
      children: [
        if (rightIcon != null && centered) ...[
          AppIcon(rightIcon!, size: 20, color: colors.icon.muted),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Flexible(
          fit: centered ? FlexFit.loose : FlexFit.tight,
          child: Text(
            rightLabel,
            key: rightKey,
            textAlign: centered ? TextAlign.left : TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: centered && leftLabel == null
                  ? colors.text.secondary
                  : colors.text.accent,
            ),
          ),
        ),
        if (rightIcon != null && !centered) ...[
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(rightIcon!, size: 20, color: colors.icon.muted),
        ],
      ],
    );

    final content = SizedBox(
      height: _kMobileSendReviewRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: centered
            ? Center(child: right)
            : Row(
                children: [
                  if (leftLabel != null)
                    Text(
                      leftLabel!,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: right),
                ],
              ),
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Memo entry sheet — Figma `Review Add Memo` (4484:62917). Pops the
/// new memo text; popping an empty string clears it.
class _MemoSheet extends StatefulWidget {
  const _MemoSheet({required this.initial});

  final String initial;

  @override
  State<_MemoSheet> createState() => _MemoSheetState();
}

class _MemoSheetState extends State<_MemoSheet> {
  static const _memoByteLimit = 512;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_handleFocus);

  String get _initialMemo => widget.initial.trim();

  String get _currentMemo => _controller.text.trim();

  bool get _showClearMemo =>
      _initialMemo.isNotEmpty && _currentMemo == _initialMemo;

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() {});
  }

  int get _usedBytes => utf8.encode(_currentMemo).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overLimit = _usedBytes > _memoByteLimit;
    final labelStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.secondary,
      fontWeight: FontWeight.w400,
    );
    final primaryIsClear = _showClearMemo;
    final primaryDisabled = overLimit && !primaryIsClear;

    return MobileModalScaffold(
      title: 'Add Memo',
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.s,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('mobile_send_memo_text_area'),
            height: 222,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  SizedBox(
                    height: _kMobileSendRecipientLineHeight,
                    child: Row(
                      children: [
                        Text('Message', style: labelStyle),
                        const Spacer(),
                        Text(
                          // Used/total bytes, like the Add Memo frame's
                          // "51/512".
                          '$_usedBytes/$_memoByteLimit',
                          style: labelStyle.copyWith(
                            color: overLimit
                                ? colors.text.destructive
                                : colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MemoTextArea(
                    key: const ValueKey('mobile_send_memo_field'),
                    controller: _controller,
                    focusNode: _focusNode,
                    hintText: 'Only the recipient can read this',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: _kMobileSendRecipientLineHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: overLimit
                          ? Text(
                              'Message is too long',
                              style: labelStyle.copyWith(
                                color: colors.text.destructive,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            key: const ValueKey('mobile_send_memo_buttons'),
            height: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: ValueKey(
                    primaryIsClear
                        ? 'mobile_send_memo_clear'
                        : 'mobile_send_memo_save',
                  ),
                  expand: true,
                  leading: primaryIsClear
                      ? const AppIcon(AppIcons.trash)
                      : null,
                  onPressed: primaryDisabled
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(primaryIsClear ? '' : _currentMemo),
                  child: Text(primaryIsClear ? 'Clear memo' : 'Add Memo'),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('mobile_send_memo_cancel'),
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoTextArea extends StatefulWidget {
  const _MemoTextArea({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<_MemoTextArea> createState() => _MemoTextAreaState();
}

class _MemoTextAreaState extends State<_MemoTextArea> {
  late final ScrollController _scrollController = ScrollController();
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleCanScrollUpdate);
    _scrollController.addListener(_scheduleCanScrollUpdate);
    _scheduleCanScrollUpdate();
  }

  @override
  void didUpdateWidget(covariant _MemoTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleCanScrollUpdate);
      widget.controller.addListener(_scheduleCanScrollUpdate);
      _scheduleCanScrollUpdate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleCanScrollUpdate);
    _scrollController.removeListener(_scheduleCanScrollUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCanScrollUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nextCanScroll =
          _scrollController.hasClients &&
          _scrollController.position.hasContentDimensions &&
          _scrollController.position.maxScrollExtent > 0.5;
      if (_canScroll == nextCanScroll) return;
      setState(() {
        _canScroll = nextCanScroll;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final focused = widget.focusNode.hasFocus;

    return Container(
      height: 148,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(
          color: focused
              ? colors.background.inverse
              : colors.background.ground.withValues(alpha: 0),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: [
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
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _scheduleCanScrollUpdate();
                return false;
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: TextField(
                    key: const ValueKey('mobile_send_memo_editable'),
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: _scrollController,
                    autofocus: true,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                    cursorColor: colors.text.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hintText,
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 12,
            child: _MemoTextAreaScrollbar(
              visible: _canScroll,
              controller: _scrollController,
              thumbColor: colors.background.overlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoTextAreaScrollbar extends StatefulWidget {
  const _MemoTextAreaScrollbar({
    required this.visible,
    required this.controller,
    required this.thumbColor,
  });

  final bool visible;
  final ScrollController controller;
  final Color thumbColor;

  @override
  State<_MemoTextAreaScrollbar> createState() => _MemoTextAreaScrollbarState();
}

class _MemoTextAreaScrollbarState extends State<_MemoTextAreaScrollbar> {
  static const _horizontalInset = 3.0;
  static const _topInset = 8.0;
  static const _bottomInset = 8.0;
  static const _minThumbHeight = 24.0;
  static const _maxThumbHeight = 62.0;
  static const _thumbWidth = 6.0;

  double? _dragThumbOffset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _MemoTextAreaScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleScrollChanged);
      widget.controller.addListener(_handleScrollChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScrollChanged);
    super.dispose();
  }

  void _handleScrollChanged() {
    if (mounted) setState(() {});
  }

  _MemoScrollbarGeometry? _geometry(double height) {
    if (!widget.visible) return null;
    if (height <= 0) return null;
    if (!widget.controller.hasClients) return null;
    final position = widget.controller.position;
    if (!position.hasContentDimensions) return null;
    final maxScrollExtent = position.maxScrollExtent;
    if (maxScrollExtent <= 0) return null;

    final trackHeight = height - _topInset - _bottomInset;
    final viewportExtent = position.viewportDimension;
    final contentExtent = viewportExtent + maxScrollExtent;
    if (trackHeight <= 0 || viewportExtent <= 0 || contentExtent <= 0) {
      return null;
    }

    final maxThumbHeight = trackHeight < _maxThumbHeight
        ? trackHeight
        : _maxThumbHeight;
    if (maxThumbHeight <= 0) return null;
    final thumbHeight = (trackHeight * viewportExtent / contentExtent)
        .clamp(_minThumbHeight, maxThumbHeight)
        .toDouble();
    final thumbTravel = trackHeight - thumbHeight;
    final scrollFraction = thumbTravel <= 0
        ? 0.0
        : (position.pixels / maxScrollExtent).clamp(0.0, 1.0).toDouble();
    final thumbTop = _topInset + scrollFraction * thumbTravel;

    return _MemoScrollbarGeometry(
      trackHeight: trackHeight,
      thumbTop: thumbTop,
      thumbHeight: thumbHeight,
      thumbTravel: thumbTravel,
      maxScrollExtent: maxScrollExtent,
    );
  }

  void _jumpToLocalY(double localY, _MemoScrollbarGeometry geometry) {
    if (geometry.thumbTravel <= 0) return;
    final dragOffset = _dragThumbOffset ?? geometry.thumbHeight / 2;
    final targetThumbTop = localY - dragOffset;
    final scrollFraction = ((targetThumbTop - _topInset) / geometry.thumbTravel)
        .clamp(0.0, 1.0)
        .toDouble();
    widget.controller.jumpTo(scrollFraction * geometry.maxScrollExtent);
  }

  void _handlePointerDown(PointerDownEvent event, double height) {
    final geometry = _geometry(height);
    if (geometry == null) return;
    final localY = event.localPosition.dy;
    final hitThumb =
        localY >= geometry.thumbTop &&
        localY <= geometry.thumbTop + geometry.thumbHeight;
    _dragThumbOffset = hitThumb
        ? localY - geometry.thumbTop
        : geometry.thumbHeight / 2;
    _jumpToLocalY(localY, geometry);
  }

  void _handlePointerMove(PointerMoveEvent event, double height) {
    final geometry = _geometry(height);
    if (geometry == null) return;
    _jumpToLocalY(event.localPosition.dy, geometry);
  }

  void _clearDrag() {
    _dragThumbOffset = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final geometry = _geometry(height);
        if (geometry == null) return const SizedBox.shrink();

        return Listener(
          key: const ValueKey('mobile_send_memo_scrollbar'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handlePointerDown(event, height),
          onPointerMove: (event) => _handlePointerMove(event, height),
          onPointerUp: (_) => _clearDrag(),
          onPointerCancel: (_) => _clearDrag(),
          child: Stack(
            children: [
              Positioned(
                key: const ValueKey('mobile_send_memo_scrollbar_thumb'),
                left: _horizontalInset,
                top: geometry.thumbTop,
                width: _thumbWidth,
                height: geometry.thumbHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.thumbColor,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemoScrollbarGeometry {
  const _MemoScrollbarGeometry({
    required this.trackHeight,
    required this.thumbTop,
    required this.thumbHeight,
    required this.thumbTravel,
    required this.maxScrollExtent,
  });

  final double trackHeight;
  final double thumbTop;
  final double thumbHeight;
  final double thumbTravel;
  final double maxScrollExtent;
}

/// Mobile counterpart of the desktop Sapling params prompt — same copy,
/// presented as a sheet. Pops true to download.
/// Shared with the Keystone signing screen, which needs the same
/// proving-parameters consent before preparing a Sapling-bound PCZT.
class MobileSaplingParamsSheet extends StatelessWidget {
  const MobileSaplingParamsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Download Required',
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'To create this private transaction, your wallet needs to '
            'download about 50MB of cryptographic parameters.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "This happens once, then it's done.\n"
            'Network data charges may apply.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_send_sapling_download'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(false),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Cancel',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientLineText extends StatelessWidget {
  const _RecipientLineText(
    this.text, {
    required this.color,
    this.fontWeight = FontWeight.w500,
  });

  final String text;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kMobileSendRecipientLineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: color,
              fontWeight: fontWeight,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline action pill in the recipient field's trailing slot — Figma
/// `Send to Focus` variants switch it between Paste and Clear.
class _AddressFieldActionButton extends StatelessWidget {
  const _AddressFieldActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  double get _width => switch (label) {
    'Paste' => _kMobileSendAddressPasteWidth,
    'Clear' => _kMobileSendAddressClearWidth,
    _ => _kMobileSendAddressPasteWidth,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          key: ValueKey('mobile_send_address_${label.toLowerCase()}'),
          width: _width,
          height: _kMobileSendAddressActionHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.button.secondary.bg,
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.button.secondary.label,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
