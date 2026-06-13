import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show CircularProgressIndicator, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../services/send_flow.dart';
import '../../../../core/widgets/mobile/app_numeric_keypad.dart';

enum _SendStep { recipient, amount, review }

enum _SendPhase { compose, sending, succeeded, pendingBroadcast, failed }

/// The mobile send wizard — Figma `Send to` → `Enter amount` →
/// `Review Send` (4423:119950, 4479:47503, 4481:51525) plus the memo
/// modal (4484:62917) — driving the shared send pipeline in
/// `send_flow.dart`. One screen owns the whole flow so proposal
/// lifetime stays trivially scoped: a proposal exists only between
/// Confirm & Send and the broadcast outcome.
class MobileSendScreen extends ConsumerStatefulWidget {
  const MobileSendScreen({
    this.loadWalletDbPath = getWalletDbPath,
    this.initialRecipient,
    super.key,
  });

  /// Test seam: widget tests cannot complete the real file IO behind
  /// [getWalletDbPath] inside the fake-async zone.
  final Future<String> Function() loadWalletDbPath;

  /// Pre-fills the recipient step (e.g. the accounts row menu's
  /// "Send ZEC" action passes that account's shielded address).
  final String? initialRecipient;

  @override
  ConsumerState<MobileSendScreen> createState() => _MobileSendScreenState();
}

class _MobileSendScreenState extends ConsumerState<MobileSendScreen> {
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  late final String _sendFlowId = newSendFlowId();

  var _step = _SendStep.recipient;
  var _phase = _SendPhase.compose;

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

  // Broadcast state.
  String? _txid;
  String? _statusMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecipient;
    if (initial != null && initial.trim().isNotEmpty) {
      _addressController.text = initial.trim();
      unawaited(_validateAddress());
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  // ── Recipient step ─────────────────────────────────────────────────

  bool get _hasValidAddress =>
      _addressController.text.trim().isNotEmpty &&
      _addressType.isNotEmpty &&
      _addressType != 'invalid' &&
      _addressType != 'error';

  bool get _isShieldedAddress =>
      _addressType == 'unified' || _addressType == 'sapling';

  Future<void> _validateAddress() async {
    final seq = ++_addressSeq;
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      if (mounted && seq == _addressSeq) setState(() => _addressType = '');
      return;
    }
    try {
      final result = await rust_sync.validateAddress(address: address);
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
    final scanned = await context.push<String>('/send/scan');
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

  /// Full recipient address in a chunked grid for visual verification —
  /// Figma `Full Address WIP` (4638:13249): 5-character chunks laid out
  /// five per row with the first and last highlighted crimson, replacing
  /// the old inline expand.
  Future<void> _showFullAddressSheet(String address) {
    final chunks = <String>[
      for (var i = 0; i < address.length; i += 5)
        address.substring(i, i + 5 > address.length ? address.length : i + 5),
    ];
    final label =
        _contactLabel ??
        (_isShieldedAddress ? 'Shielded address' : 'Transparent address');
    return showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colors = sheetContext.colors;
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
              Row(
                children: [
                  AppProfilePicture(
                    profilePictureId: _contactPictureId ?? '',
                    size: AppProfilePictureSize.medium,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(sheetContext).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colors.background.raised,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.cross,
                            size: 16,
                            color: colors.icon.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _AddressChunkGrid(
                key: const ValueKey('mobile_send_full_address_chunks'),
                chunks: chunks,
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        'Close',
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
      },
    );
  }

  void _continueToAmount() {
    if (!_hasValidAddress) return;
    _addressFocus.unfocus();
    setState(() => _step = _SendStep.amount);
    unawaited(_validateAmount());
  }

  // ── Amount step ────────────────────────────────────────────────────

  BigInt get _spendable {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    return (ref.read(syncProvider).value ?? SyncState())
        .scopedToAccount(accountUuid)
        .spendableBalance;
  }

  void _appendDigit(int digit) {
    if (_amountText.length >= 17) return;
    final next = _amountText == '0' ? '$digit' : '$_amountText$digit';
    final decimals = next.contains('.') ? next.split('.').last.length : 0;
    if (decimals > 8) return;
    setState(() => _amountText = next);
    unawaited(_validateAmount());
  }

  void _appendDecimalPoint() {
    if (_amountText.contains('.')) return;
    setState(() => _amountText = _amountText.isEmpty ? '0.' : '$_amountText.');
    unawaited(_validateAmount());
  }

  void _amountBackspace() {
    if (_amountText.isEmpty) return;
    setState(
      () => _amountText = _amountText.substring(0, _amountText.length - 1),
    );
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
      final fee = await rust_sync.estimateFee(
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
      final fee = await rust_sync.estimateFee(
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

  Future<bool> _confirmSaplingParamsDownload() async {
    if (!mounted) return false;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => const MobileSaplingParamsSheet(),
    );
    return confirmed == true;
  }

  Future<void> _confirmAndSend() async {
    if (_phase != _SendPhase.compose) return;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(accountUuid);
    final amountZatoshi = parseZecAmount(_amountText.trim());
    if (amountZatoshi == null || amountZatoshi <= BigInt.zero) return;

    setState(() {
      _phase = _SendPhase.sending;
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
        if (mounted) setState(() => _phase = _SendPhase.compose);
        return;
      }
      if (!mounted) return;
    }

    final outcome = await runSendBroadcast(
      ref: ref,
      args: args,
      keystone: keystone,
      confirmSaplingParamsDownload: _confirmSaplingParamsDownload,
      shouldAbort: () async => !mounted,
    );
    if (outcome.phase == SendBroadcastPhase.failed &&
        !outcome.proposalConsumed) {
      // Non-consuming failure (e.g. params declined) — release it so a
      // retry can propose again.
      unawaited(
        discardSendProposal(
          proposalId: args.proposalId,
          sendFlowId: _sendFlowId,
          logContext: 'MobileSend(failed before execute)',
        ),
      );
    }
    if (outcome.phase == SendBroadcastPhase.aborted || !mounted) return;
    setState(() {
      _phase = switch (outcome.phase) {
        SendBroadcastPhase.succeeded => _SendPhase.succeeded,
        SendBroadcastPhase.pendingBroadcast => _SendPhase.pendingBroadcast,
        _ => _SendPhase.failed,
      };
      _txid = outcome.txid;
      _statusMessage = outcome.statusMessage;
      _error = outcome.error;
    });
  }

  Future<void> _openExplorer() async {
    final txid = _txid;
    if (txid == null) return;
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: txid,
      txidOrder: ZcashExplorerTxidOrder.display,
    );
    if (launched || !mounted) return;
    await Clipboard.setData(ClipboardData(text: txid));
    if (!mounted) return;
    showAppToast(context, 'Transaction Hash Copied');
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _handleBack() {
    switch (_phase) {
      case _SendPhase.sending:
        return; // Blocked while broadcasting.
      case _SendPhase.succeeded:
      case _SendPhase.pendingBroadcast:
        context.go('/home');
        return;
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
        setState(() => _step = _SendStep.recipient);
      case _SendStep.review:
        setState(() => _step = _SendStep.amount);
    }
  }

  String _truncateAddress(String address) {
    final value = address.trim();
    if (value.length <= 28) return value;
    return '${value.substring(0, 13)} ... '
        '${value.substring(value.length - 11)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final title = switch (_phase) {
      _SendPhase.compose => switch (_step) {
        _SendStep.recipient => 'Select Recipient',
        _SendStep.amount => 'Enter amount',
        _SendStep.review => 'Review Send',
      },
      _SendPhase.sending => 'Sending',
      _SendPhase.succeeded => 'Sent',
      _SendPhase.pendingBroadcast => 'Almost there',
      _SendPhase.failed => 'Send failed',
    };

    final body = switch (_phase) {
      _SendPhase.compose => switch (_step) {
        _SendStep.recipient => _buildRecipientStep(context),
        _SendStep.amount => _buildAmountStep(context),
        _SendStep.review => _buildReviewStep(context),
      },
      _ => _buildStatus(context),
    };

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        resizeToAvoidBottomInset: true,
        body: AppToastHost(
          child: SafeArea(
            child: Column(
              children: [
                MobileTopNav.back(
                  title: title,
                  onBack: _phase == _SendPhase.sending ? null : _handleBack,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step bodies ────────────────────────────────────────────────────

  Widget _buildRecipientStep(BuildContext context) {
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
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            children: [
              AppTextField(
                key: const ValueKey('mobile_send_address_field'),
                label: 'Send to',
                // The design's field carries only the hint, no label.
                showLabel: false,
                controller: _addressController,
                focusNode: _addressFocus,
                hintText: 'Zcash Address',
                leading: AppIcon(
                  AppIcons.plane,
                  size: 20,
                  color: _addressController.text.trim().isEmpty
                      ? colors.icon.regular
                      : colors.icon.accent,
                ),
                tone: _addressType == 'invalid' || _addressType == 'error'
                    ? AppTextFieldTone.destructive
                    : AppTextFieldTone.neutral,
                messageText: switch (_addressType) {
                  'invalid' => 'Invalid address',
                  'error' => 'Address validation failed',
                  _ => null,
                },
                // Empty field offers Paste (Figma `Send to Focus`); once
                // it has text the shared clear (X) takes the slot. The
                // pill needs its intrinsic width, hence trailingFitsSlot.
                showClearButton: true,
                trailing: _PasteButton(onTap: () => unawaited(_pasteAddress())),
                trailingFitsSlot: true,
                onChanged: (_) => _handleAddressChanged(),
                onClear: _handleAddressChanged,
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                button: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_send_scan_row'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_openScanner()),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          // Same subtle disc as the activity rows — a
                          // white disc disappears on the window bg.
                          color: colors.background.neutralSubtleOpacity,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.qr,
                            size: 20,
                            color: colors.icon.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan a QR Code',
                              style: AppTypography.bodyMediumStrong.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            Text(
                              'Scan an address using camera',
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    AppIcon(AppIcons.users, size: 16, color: colors.icon.muted),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${contacts.length} '
                      'contact${contacts.length == 1 ? '' : 's'}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                for (final contact in contacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s),
                    child: Semantics(
                      button: true,
                      child: GestureDetector(
                        key: ValueKey('mobile_send_contact_${contact.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectContact(contact),
                        child: Row(
                          children: [
                            AppProfilePicture(
                              profilePictureId: contact.profilePictureId,
                              size: AppProfilePictureSize.large,
                            ),
                            const SizedBox(width: AppSpacing.s),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contact.label,
                                    style: AppTypography.bodyMediumStrong
                                        .copyWith(color: colors.text.accent),
                                  ),
                                  Text(
                                    _truncateAddress(contact.address),
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: colors.text.secondary,
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
              ],
            ],
          ),
        ),
        // The Figma empty state carries no action button — Continue
        // appears once something is typed or pasted.
        if (_addressController.text.trim().isNotEmpty)
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
                key: const ValueKey('mobile_send_continue'),
                expand: true,
                onPressed: _hasValidAddress ? _continueToAmount : null,
                child: const Text('Continue'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAmountStep(BuildContext context) {
    final colors = context.colors;
    final spendableText = ZecAmount.fromZatoshi(
      _spendable,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final showError = _amountError != null && _amountError!.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: Column(
            // The Figma amount step keeps the amount near the top
            // (~90 below the nav), not vertically centered.
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 90),
              if (showError)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    _amountError!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _amountText.isEmpty ? '' : _amountText,
                      key: const ValueKey('mobile_send_amount_display'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: AppTypography.displayLarge.copyWith(
                        color: showError
                            ? colors.text.destructive
                            : colors.text.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  _BlinkingCaret(
                    height: AppTypography.displayLarge.fontSize ?? 40,
                    color: colors.text.accent,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Max: $spendableText',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sending to',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  AppProfilePicture(
                    profilePictureId: _contactPictureId ?? '',
                    size: AppProfilePictureSize.large,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_contactLabel != null)
                          Text(
                            _contactLabel!,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        Text(
                          _truncateAddress(_addressController.text),
                          style: AppTypography.bodyMedium.copyWith(
                            color: _contactLabel == null
                                ? colors.text.accent
                                : colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  key: const ValueKey('mobile_send_review_button'),
                  expand: true,
                  onPressed: _amountReady ? _continueToReview : null,
                  child: Text(
                    _amountReady
                        ? 'Finish & Review'
                        : 'Enter amount to continue',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppNumericKeypad(
                onDigit: _appendDigit,
                onDecimalPoint: _appendDecimalPoint,
                onBackspace: _amountBackspace,
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final colors = context.colors;
    // Uppercase ticker per the mobile review frame ("123.12 ZEC").
    final amountText =
        ZecAmount.tryParse(_amountText)?.activityDetail.toString() ??
        '$_amountText ZEC';
    final feeText = _feeZatoshi == null
        ? '—'
        : ZecAmount.fromZatoshi(_feeZatoshi!).fee.toString();
    final address = _addressController.text.trim();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      // Zcash brand yellow — fixed brand color like the
                      // crimson shield, not a theme token.
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
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Amount',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                        Text(
                          amountText,
                          key: const ValueKey('mobile_send_review_amount'),
                          style: AppTypography.headlineMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppIcon(AppIcons.arrowDownward, size: 20),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppProfilePicture(
                    profilePictureId: _contactPictureId ?? '',
                    size: AppProfilePictureSize.large,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'To',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                        Text(
                          _contactLabel ?? _truncateAddress(address),
                          // No saved contact: the compact address is the
                          // headline; the smaller style keeps it on one
                          // line instead of re-ellipsizing the already
                          // truncated form.
                          style:
                              (_contactLabel == null
                                      ? AppTypography.headlineSmall
                                      : AppTypography.headlineMedium)
                                  .copyWith(color: colors.text.accent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Semantics(
                          button: true,
                          child: GestureDetector(
                            key: const ValueKey('mobile_send_full_address'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                unawaited(_showFullAddressSheet(address)),
                            child: Row(
                              children: [
                                AppIcon(
                                  _isShieldedAddress
                                      ? AppIcons.shieldKeyhole
                                      : AppIcons.transparentBalance,
                                  size: 16,
                                  color: _isShieldedAddress
                                      ? colors.icon.brandCrimson
                                      : colors.icon.muted,
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Expanded(
                                  child: Text(
                                    _truncateAddress(address),
                                    style: AppTypography.labelMedium.copyWith(
                                      color: colors.text.secondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                AppIcon(
                                  AppIcons.eye,
                                  size: 16,
                                  color: colors.icon.muted,
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Text(
                                  'Full address',
                                  style: AppTypography.labelMedium.copyWith(
                                    color: colors.text.accent,
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
              const SizedBox(height: AppSpacing.md),
              MobileSurfaceCard(
                child: Column(
                  children: [
                    if (_isShieldedAddress) ...[
                      Semantics(
                        button: true,
                        child: GestureDetector(
                          key: const ValueKey('mobile_send_memo_row'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(_editMemo()),
                          child: SizedBox(
                            height: 44,
                            child: _memo.trim().isEmpty
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AppIcon(
                                        AppIcons.edit,
                                        size: 16,
                                        color: colors.icon.muted,
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text(
                                        'Add short encrypted message',
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                              color: colors.text.secondary,
                                            ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Text(
                                        'Message',
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                              color: colors.text.secondary,
                                            ),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(
                                        child: Text(
                                          _memo.trim(),
                                          textAlign: TextAlign.right,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodyMedium
                                              .copyWith(
                                                color: colors.text.accent,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      AppIcon(
                                        AppIcons.doubleArrowVertical,
                                        size: 16,
                                        color: colors.icon.muted,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      Container(height: 1, color: colors.background.raised),
                    ],
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          Text(
                            'Tx fee',
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            feeText,
                            key: const ValueKey('mobile_send_fee'),
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Semantics(
                            button: true,
                            label: 'About the transaction fee',
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => unawaited(_showFeeInfo()),
                              child: AppIcon(
                                AppIcons.help,
                                size: 16,
                                color: colors.icon.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.s,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(
                key: const ValueKey('mobile_send_confirm'),
                expand: true,
                onPressed: () => unawaited(_confirmAndSend()),
                leading: const AppIcon(AppIcons.plane, size: 20),
                child: const Text('Confirm & Send'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pop(),
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
        ),
      ],
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = context.colors;
    final amountText =
        ZecAmount.tryParse(_amountText)?.receipt.toString() ??
        '$_amountText ZEC';
    final toLabel =
        _contactLabel ?? _truncateAddress(_addressController.text.trim());

    final (Widget icon, String headline, String? detail) = switch (_phase) {
      _SendPhase.sending => (
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        'Sending...',
        null,
      ),
      _SendPhase.succeeded => (
        AppIcon(AppIcons.checkCircle, size: 48, color: colors.icon.accent),
        'Sent',
        null,
      ),
      _SendPhase.pendingBroadcast => (
        AppIcon(AppIcons.warning, size: 48, color: colors.icon.accent),
        'Almost there',
        _statusMessage,
      ),
      _ => (
        AppIcon(AppIcons.warning, size: 48, color: colors.text.destructive),
        'Send failed',
        _error,
      ),
    };

    return Padding(
      key: ValueKey('mobile_send_status_${_phase.name}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: AppSpacing.md),
                Text(
                  headline,
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
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: _phase == _SendPhase.failed
                          ? colors.text.destructive
                          : colors.text.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_phase != _SendPhase.sending) ...[
            if ((_phase == _SendPhase.succeeded ||
                    _phase == _SendPhase.pendingBroadcast) &&
                _txid != null) ...[
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  variant: AppButtonVariant.secondary,
                  onPressed: () => unawaited(_openExplorer()),
                  child: const Text('View transaction'),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            SizedBox(
              width: double.infinity,
              child: _phase == _SendPhase.failed
                  ? AppButton(
                      key: const ValueKey('mobile_send_try_again'),
                      onPressed: () =>
                          setState(() => _phase = _SendPhase.compose),
                      child: const Text('Try again'),
                    )
                  : AppButton(
                      key: const ValueKey('mobile_send_done'),
                      onPressed: () => context.go('/home'),
                      child: const Text('Done'),
                    ),
            ),
            if (_phase == _SendPhase.failed) ...[
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
            ],
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// Text-cursor bar after the amount — the Figma amount step shows a
/// caret even though entry comes from the in-app keypad. Static (no
/// blink): a repeating animation would keep `pumpAndSettle` from ever
/// settling in widget tests.
class _BlinkingCaret extends StatelessWidget {
  const _BlinkingCaret({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 2.5, height: height, color: color);
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _usedBytes => utf8.encode(_controller.text.trim()).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overLimit = _usedBytes > _memoByteLimit;

    // The sheet frame floats this card above the software keyboard, so
    // no manual keyboard inset is needed here.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add Memo',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Close',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.background.raised,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.cross,
                        size: AppIconSize.medium,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Text(
                'Message',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const Spacer(),
              Text(
                // Used/total bytes, like the Add Memo frame's "51/512".
                '$_usedBytes/$_memoByteLimit',
                style: AppTypography.bodyMedium.copyWith(
                  color: overLimit
                      ? colors.text.destructive
                      : colors.text.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            key: const ValueKey('mobile_send_memo_field'),
            label: 'Message',
            // The sheet renders its own label/counter row.
            showLabel: false,
            controller: _controller,
            hintText: 'Only the recipient can read this',
            maxLines: 5,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_send_memo_save'),
            expand: true,
            onPressed: overLimit
                ? null
                : () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Add Memo'),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (widget.initial.trim().isNotEmpty)
            Semantics(
              button: true,
              child: GestureDetector(
                key: const ValueKey('mobile_send_memo_clear'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(''),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      'Clear memo',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
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

/// Inline "Paste" pill shown in the recipient field's trailing slot while
/// it is empty — Figma `Send to Focus` (4423:119668). Tapping pastes the
/// clipboard text into the address field.
class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Paste',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('mobile_send_address_paste'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.background.raised,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Text(
            'Paste',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Five-per-row grid of 5-character address chunks with the first and
/// last chunk highlighted crimson — Figma `Full Address WIP`.
class _AddressChunkGrid extends StatelessWidget {
  const _AddressChunkGrid({required this.chunks, super.key});

  final List<String> chunks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const columns = 5;
    final rows = <List<int>>[];
    for (var i = 0; i < chunks.length; i += columns) {
      rows.add([for (var c = i; c < i + columns && c < chunks.length; c++) c]);
    }
    final lastIndex = chunks.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                for (var c = 0; c < columns; c++)
                  Expanded(
                    child: c < rows[r].length
                        ? Text(
                            chunks[rows[r][c]],
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: rows[r][c] == 0 || rows[r][c] == lastIndex
                                  ? colors.text.brandCrimson
                                  : colors.text.accent,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          if (r < rows.length - 1)
            Container(height: 1, color: colors.border.regular),
        ],
      ],
    );
  }
}
