import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/account_provider.dart';
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
  static const _singleLineFieldOverlayReserve = 20.0;
  static const _singleLineFieldGap = AppSpacing.xs;
  static const _multilineFieldOverlayReserve = 24.0;
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _addressFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();
  final _memoFocusNode = FocusNode();
  final _memoScrollController = ScrollController();
  bool _isSending = false;
  bool _messageExpanded = false;
  String? _error;
  String _addressType = '';
  String?
  _amountError; // null = no error, empty string = silent invalid (empty/dot)
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
    _validateAmount();
    if (mounted) setState(() {});
  }

  void _handleFieldVisualStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _validateAddress() async {
    final addr = _addressController.text.trim();
    if (addr.isEmpty) {
      setState(() => _addressType = '');
      return;
    }
    try {
      final result = await rust_sync.validateAddress(address: addr);
      setState(
        () => _addressType = result.isValid ? result.addressType : 'invalid',
      );
    } catch (e) {
      log('Send: address validation error: $e');
      setState(() => _addressType = 'error');
    }
  }

  BigInt _getSpendableBalance() {
    final syncState = ref.read(syncProvider).value;
    return syncState?.spendableBalance ?? BigInt.zero;
  }

  bool get _hasValidAddress =>
      _addressController.text.trim().isNotEmpty &&
      _addressType.isNotEmpty &&
      _addressType != 'invalid' &&
      _addressType != 'error';

  bool get _isShieldedAddress =>
      _addressType == 'unified' || _addressType == 'sapling';

  bool get _showAmountError =>
      _amountError != null && _amountError!.trim().isNotEmpty;

  int get _memoLength => utf8.encode(_memoController.text).length;

  String? get _memoError {
    if (_memoLength > 512) return 'Message is too long';
    if (_memoController.text.trim().isNotEmpty && !_isShieldedAddress) {
      return 'Message is only available for shielded addresses';
    }
    return null;
  }

  bool get _canReview =>
      !_isSending &&
      _hasValidAddress &&
      _isAmountValid &&
      _memoError == null &&
      (_isShieldedAddress || _memoController.text.trim().isEmpty);

  String _formatSpendableLabel(BigInt zatoshi) {
    final whole = zatoshi ~/ BigInt.from(100000000);
    final frac = (zatoshi % BigInt.from(100000000)).toString().padLeft(8, '0');

    if (frac == '00000000') return whole.toString();
    if (whole == BigInt.zero && int.parse(frac) < 1000000) {
      return '0.${frac.replaceFirst(RegExp(r'0+$'), '')}';
    }

    final short = frac.substring(0, 2).replaceFirst(RegExp(r'0+$'), '');
    return short.isEmpty ? whole.toString() : '$whole.$short';
  }

  Future<void> _validateAmount() async {
    final seq = ++_validateSeq;
    final text = _amountController.text.trim();

    // Empty or just "." — silently invalid (no error shown, button disabled)
    if (text.isEmpty || text == '.') {
      setState(() => _amountError = '');
      return;
    }

    final zatoshi = _parseZecToZatoshi(text);
    if (zatoshi == null || zatoshi <= 0) {
      setState(() => _amountError = 'Invalid amount');
      return;
    }

    // Quick balance pre-check
    final spendable = _getSpendableBalance();
    if (BigInt.from(zatoshi) > spendable) {
      setState(() => _amountError = 'Insufficient balance');
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
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
      final memo = _memoController.text.trim();
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        setState(() => _amountError = null);
        return;
      }
      final fee = await rust_sync.estimateFee(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
        toAddress: address,
        amountZatoshi: BigInt.from(zatoshi),
        memo: memo.isNotEmpty ? memo : null,
      );

      // Stale check — new input arrived while awaiting
      if (seq != _validateSeq) return;

      final totalNeeded = BigInt.from(zatoshi) + fee;
      if (totalNeeded > spendable) {
        final feeZec = _formatZec(fee);
        setState(
          () => _amountError = 'Insufficient balance (fee: $feeZec ZEC)',
        );
      } else {
        setState(() => _amountError = null);
      }
    } catch (e) {
      if (seq != _validateSeq) return;
      final msg = e.toString();
      if (msg.contains('InsufficientFunds') || msg.contains('insufficient')) {
        setState(() => _amountError = 'Insufficient balance including fee');
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
      return 'Insufficient balance to cover amount and fee.';
    }
    if (lower.contains('grpc connect failed') ||
        lower.contains('connection refused') ||
        lower.contains('dns error') ||
        lower.contains('tls error')) {
      return 'Network error. Please check your connection and try again.';
    }
    // Partial broadcast must be checked before generic "broadcast rejected"
    if (lower.contains('broadcast failed after') &&
        lower.contains('txs sent')) {
      return 'Some transactions were broadcast but not all. '
          'Please check your transaction history before retrying.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again.';
    }
    if (lower.contains('proposal not found')) {
      return 'Transaction expired. Please try again.';
    }
    return 'Send failed. Please try again.';
  }

  String _formatZec(BigInt zatoshi) {
    final abs = zatoshi.abs();
    final whole = abs ~/ BigInt.from(100000000);
    final frac = (abs % BigInt.from(100000000)).toString().padLeft(8, '0');
    final sign = zatoshi < BigInt.zero ? '-' : '';
    return '$sign$whole.$frac';
  }

  /// Parse a ZEC string to zatoshi without floating-point.
  /// Handles: "1.5", ".01", "100", "0.00000001"
  int? _parseZecToZatoshi(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('.')) s = '0$s';

    final parts = s.split('.');
    if (parts.length > 2) return null;

    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    if (whole == null || whole < 0) return null;

    String frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > 8) frac = frac.substring(0, 8);
    frac = frac.padRight(8, '0');

    final fracInt = int.tryParse(frac);
    if (fracInt == null) return null;

    return whole * 100000000 + fracInt;
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
      final amountZatoshi = _parseZecToZatoshi(_amountController.text.trim());

      if (!_hasValidAddress) {
        setState(() {
          _error = 'Enter a valid address';
          _isSending = false;
        });
        return;
      }

      if (amountZatoshi == null || amountZatoshi <= 0) {
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
      final spendable = _getSpendableBalance();
      if (BigInt.from(amountZatoshi) > spendable) {
        setState(() {
          _error = 'Insufficient balance.';
          _isSending = false;
        });
        return;
      }

      final memo = _memoController.text.trim();
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';

      // Step 1: Propose transfer
      log('Send: proposing transfer');
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        setState(() {
          _error = 'No active account';
          _isSending = false;
        });
        return;
      }
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
        toAddress: address,
        amountZatoshi: BigInt.from(amountZatoshi),
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
          address: address,
          addressType: _addressType,
          amountZatoshi: BigInt.from(amountZatoshi),
          feeZatoshi: proposal.feeZatoshi,
          memo: memo.isNotEmpty ? memo : null,
          needsSaplingParams: proposal.needsSaplingParams,
        ),
      );
    } catch (e) {
      log('Send: review preparation error: $e');
      setState(() {
        _error = _friendlyError(e.toString());
        _isSending = false;
      });
    } finally {
      if (activeProposalId != null && !pushedReview) {
        try {
          await rust_sync.discardProposal(proposalId: activeProposalId);
          log('Send: released proposal $activeProposalId (review not opened)');
        } catch (e) {
          log('Send: discardProposal cleanup failed (non-critical): $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final accountAsync = ref.watch(accountProvider);
    final matchedLocation = GoRouterState.of(context).matchedLocation;
    final accountName = accountAsync.value?.activeAccount?.name ?? 'Username';
    final spendable = _getSpendableBalance();
    final colors = context.colors;

    final addressTone = switch (_addressType) {
      'unified' || 'sapling' => AppTextFieldTone.brandPurple,
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
        color: colors.text.brandPurple,
      ),
      'invalid' || 'error' => AppIcon(
        AppIcons.warning,
        size: 16,
        color: colors.text.warning,
      ),
      'transparent' => AppIcon(
        AppIcons.eye,
        size: 16,
        color: colors.text.muted,
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
      sidebar: AppMainSidebar(
        accountName: accountName,
        matchedLocation: matchedLocation,
      ),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox.expand(
          child: walletAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                'Error: $err',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.warning,
                ),
              ),
            ),
            data: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SendBackRow(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.s),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Center(
                              child: SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.s,
                                      ),
                                      child: SizedBox(
                                        width: 352,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AppTextField(
                                              label: 'Send to',
                                              tone: addressTone,
                                              focusNode: _addressFocusNode,
                                              controller: _addressController,
                                              hintText: 'zCash Address',
                                              leading: AppIcon(
                                                AppIcons.users,
                                                size: 20,
                                                color:
                                                    _addressController.text
                                                        .trim()
                                                        .isNotEmpty
                                                    ? colors.icon.accent
                                                    : colors.icon.regular,
                                              ),
                                              rightSlot: _SendTrailingLabel(
                                                label: 'Contacts',
                                                icon: AppIcon(
                                                  AppIcons.chevronForward,
                                                  size: 16,
                                                  color: colors.text.secondary,
                                                ),
                                              ),
                                              messageText: addressMessage,
                                              messageIcon: addressMessageIcon,
                                              messageStyle: addressMessageStyle,
                                              onChanged: (_) {
                                                _validateAddress();
                                                _validateAmount();
                                              },
                                              keyboardType: TextInputType.text,
                                              showClearButton: true,
                                              onClear: () {
                                                setState(() {
                                                  _addressType = '';
                                                  _error = null;
                                                });
                                                _validateAmount();
                                              },
                                            ),
                                            const SizedBox(
                                              height:
                                                  _singleLineFieldOverlayReserve,
                                            ),
                                            const SizedBox(
                                              height: _singleLineFieldGap,
                                            ),
                                            AppTextField(
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
                                                color:
                                                    _amountController.text
                                                        .trim()
                                                        .isNotEmpty
                                                    ? colors.icon.accent
                                                    : colors.icon.regular,
                                              ),
                                              rightSlot: Text(
                                                'Max: ${_formatSpendableLabel(spendable)} ZEC',
                                                style: AppTypography.labelMedium
                                                    .copyWith(
                                                      color:
                                                          colors.text.secondary,
                                                    ),
                                              ),
                                              messageText: _showAmountError
                                                  ? _amountError
                                                  : null,
                                              messageIcon: _showAmountError
                                                  ? AppIcon(
                                                      AppIcons.warning,
                                                      size: 16,
                                                      color:
                                                          colors.text.warning,
                                                    )
                                                  : null,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: [
                                                FilteringTextInputFormatter.allow(
                                                  RegExp(r'[\d.]'),
                                                ),
                                                _ZecAmountFormatter(),
                                              ],
                                              onChanged: (_) =>
                                                  _validateAmount(),
                                              showClearButton: true,
                                              onClear: () {
                                                setState(() {
                                                  _amountError = '';
                                                  _error = null;
                                                });
                                              },
                                            ),
                                            const SizedBox(
                                              height:
                                                  _singleLineFieldOverlayReserve,
                                            ),
                                            const SizedBox(
                                              height: _singleLineFieldGap,
                                            ),
                                            if (!_messageExpanded &&
                                                _memoController
                                                    .text
                                                    .isEmpty) ...[
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: AppSpacing.xs,
                                                    ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const AppDecorativeDivider(
                                                      width: 256,
                                                      middleWidth: 53.553,
                                                      middleHeight: 14,
                                                    ),
                                                    const SizedBox(
                                                      height: AppSpacing.sm,
                                                    ),
                                                    _SendAddMessageCard(
                                                      onTap: () {
                                                        setState(() {
                                                          _messageExpanded =
                                                              true;
                                                        });
                                                        _memoFocusNode
                                                            .requestFocus();
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ] else ...[
                                              AppTextField(
                                                label: 'Message',
                                                tone: _memoError != null
                                                    ? AppTextFieldTone
                                                          .destructive
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
                                                  style: AppTypography
                                                      .labelMedium
                                                      .copyWith(
                                                        color: colors
                                                            .text
                                                            .secondary,
                                                      ),
                                                ),
                                                messageText: _memoError,
                                                messageIcon: _memoError != null
                                                    ? AppIcon(
                                                        AppIcons.warning,
                                                        size: 16,
                                                        color:
                                                            colors.text.warning,
                                                      )
                                                    : null,
                                                minLines: 6,
                                                maxLines: 6,
                                                scrollController:
                                                    _memoScrollController,
                                                textStyle: AppTypography
                                                    .bodyMedium
                                                    .copyWith(
                                                      color: colors.text.accent,
                                                    ),
                                                onChanged: (_) => setState(() {
                                                  _error = null;
                                                }),
                                                showClearButton: true,
                                                onClear: () {
                                                  setState(() {
                                                    _messageExpanded = false;
                                                    _error = null;
                                                  });
                                                  _validateAmount();
                                                },
                                              ),
                                              const SizedBox(
                                                height:
                                                    _multilineFieldOverlayReserve,
                                              ),
                                            ],
                                            if (_error != null) ...[
                                              const SizedBox(
                                                height: AppSpacing.xs,
                                              ),
                                              _SendGlobalError(
                                                message: _error!,
                                              ),
                                            ],
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            const SizedBox(height: 40),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: AppSpacing.s,
                            child: Center(
                              child: SizedBox(
                                width: 256,
                                child: AppButton(
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
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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

class _SendBackRow extends StatelessWidget {
  const _SendBackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: 16,
                color: colors.icon.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendTrailingLabel extends StatelessWidget {
  const _SendTrailingLabel({required this.label, this.icon});

  final String label;
  final Widget? icon;

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
        if (icon != null) ...[const SizedBox(width: AppSpacing.xxs), icon!],
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
      width: 352,
      height: 96,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
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
                'Add a Message',
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

class _SendGlobalError extends StatelessWidget {
  const _SendGlobalError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIcon(AppIcons.warning, size: 16, color: context.colors.text.warning),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.warning,
            ),
          ),
        ),
      ],
    );
  }
}

/// Enforces: one decimal point max, up to 8 fractional digits.
class _ZecAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Allow empty
    if (text.isEmpty) return newValue;

    // Only one decimal point
    if ('.'.allMatches(text).length > 1) return oldValue;

    // Limit fractional digits to 8
    final dotIndex = text.indexOf('.');
    if (dotIndex != -1 && text.length - dotIndex - 1 > 8) return oldValue;

    return newValue;
  }
}
