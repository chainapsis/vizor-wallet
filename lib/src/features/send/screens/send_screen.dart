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
    _memoFocusNode.addListener(_handleMemoFocusChanged);
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
    _memoFocusNode.removeListener(_handleMemoFocusChanged);
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
    if (mounted) setState(() {});
  }

  void _handleFieldVisualStateChanged() {
    if (mounted) setState(() {});
  }

  void _handleMemoFocusChanged() {
    if (!_memoFocusNode.hasFocus && _memoController.text.isEmpty) {
      _messageExpanded = false;
    }
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
      'unified' || 'sapling' => _SendFieldTone.brandPurple,
      'invalid' || 'error' => _SendFieldTone.destructive,
      _ => _SendFieldTone.neutral,
    };
    final addressMessage = switch (_addressType) {
      'unified' || 'sapling' => 'Shielded Address',
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
                const SizedBox(height: AppSpacing.sm),
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
                                        vertical: AppSpacing.sm,
                                      ),
                                      child: SizedBox(
                                        width: 352,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _SendInputField(
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
                                              trailingLabel: _SendTrailingLabel(
                                                label: 'Contacts',
                                                icon: AppIcon(
                                                  AppIcons.chevronForward,
                                                  size: 16,
                                                  color: colors.text.secondary,
                                                ),
                                              ),
                                              messageText: addressMessage,
                                              messageIcon: addressMessageIcon,
                                              onChanged: (_) {
                                                _validateAddress();
                                                _validateAmount();
                                              },
                                              keyboardType: TextInputType.text,
                                              trailing:
                                                  _addressFocusNode.hasFocus &&
                                                      _addressController.text
                                                          .trim()
                                                          .isNotEmpty
                                                  ? _ClearFieldButton(
                                                      onTap: () {
                                                        _addressController
                                                            .clear();
                                                        setState(() {
                                                          _addressType = '';
                                                          _error = null;
                                                        });
                                                        _validateAmount();
                                                      },
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xs,
                                            ),
                                            _SendInputField(
                                              label: 'Amount',
                                              tone: _showAmountError
                                                  ? _SendFieldTone.destructive
                                                  : _SendFieldTone.neutral,
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
                                              trailingLabel: Text(
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
                                              trailing:
                                                  _amountFocusNode.hasFocus &&
                                                      _amountController.text
                                                          .trim()
                                                          .isNotEmpty
                                                  ? _ClearFieldButton(
                                                      onTap: () {
                                                        _amountController
                                                            .clear();
                                                        setState(() {
                                                          _amountError = '';
                                                          _error = null;
                                                        });
                                                      },
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            if (!_messageExpanded &&
                                                _memoController
                                                    .text
                                                    .isEmpty) ...[
                                              AppDecorativeDivider(
                                                width: 256,
                                                middleWidth: 53.553,
                                                middleHeight: 14,
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.sm,
                                              ),
                                              _SendAddMessageCard(
                                                enabled: _isShieldedAddress,
                                                onTap: _isShieldedAddress
                                                    ? () {
                                                        setState(() {
                                                          _messageExpanded =
                                                              true;
                                                        });
                                                        _memoFocusNode
                                                            .requestFocus();
                                                      }
                                                    : null,
                                              ),
                                            ] else ...[
                                              _SendInputField(
                                                label: 'Message',
                                                tone: _memoError != null
                                                    ? _SendFieldTone.destructive
                                                    : _SendFieldTone.neutral,
                                                focusNode: _memoFocusNode,
                                                controller: _memoController,
                                                hintText: 'Add a message',
                                                leading: AppIcon(
                                                  AppIcons.scroll,
                                                  size: 20,
                                                  color: colors.icon.regular,
                                                ),
                                                trailingLabel: Text(
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
                                                onChanged: (_) => setState(() {
                                                  _error = null;
                                                }),
                                                trailing:
                                                    _memoController.text
                                                        .trim()
                                                        .isNotEmpty
                                                    ? _ClearFieldButton(
                                                        onTap: () {
                                                          _memoController
                                                              .clear();
                                                          setState(() {
                                                            _messageExpanded =
                                                                false;
                                                            _error = null;
                                                          });
                                                        },
                                                      )
                                                    : null,
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

enum _SendFieldTone { neutral, destructive, brandPurple }

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

class _ClearFieldButton extends StatelessWidget {
  const _ClearFieldButton({required this.onTap});

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
          width: 20,
          height: 20,
          child: Center(
            child: AppIcon(AppIcons.cross, size: 20, color: colors.icon.accent),
          ),
        ),
      ),
    );
  }
}

class _SendInputField extends StatelessWidget {
  const _SendInputField({
    required this.label,
    required this.tone,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.hintText,
    this.leading,
    this.trailing,
    this.trailingLabel,
    this.messageText,
    this.messageIcon,
    this.keyboardType,
    this.inputFormatters,
    this.minLines = 1,
    this.maxLines = 1,
    this.scrollController,
  });

  final String label;
  final _SendFieldTone tone;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final Widget? leading;
  final Widget? trailing;
  final Widget? trailingLabel;
  final String? messageText;
  final Widget? messageIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int minLines;
  final int maxLines;
  final ScrollController? scrollController;

  bool get _isMultiline => maxLines > 1 || minLines > 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = switch (tone) {
      _SendFieldTone.neutral when focusNode.hasFocus => colors.border.strong,
      _SendFieldTone.neutral => colors.border.subtle,
      _SendFieldTone.destructive => colors.border.utilityDestructive,
      _SendFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final focusRingColor = switch (tone) {
      _SendFieldTone.neutral => colors.state.focusRing,
      _SendFieldTone.destructive => colors.border.utilityDestructive,
      _SendFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final messageColor = switch (tone) {
      _SendFieldTone.neutral => colors.text.secondary,
      _SendFieldTone.destructive => colors.text.warning,
      _SendFieldTone.brandPurple => colors.text.brandPurple,
    };
    final shellHeight = _isMultiline ? 148.0 : 46.0;

    final input = TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      maxLines: _isMultiline ? null : 1,
      minLines: _isMultiline ? null : 1,
      expands: _isMultiline,
      scrollController: scrollController,
      textAlignVertical: _isMultiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: _isMultiline
          ? AppTypography.bodyMedium.copyWith(color: colors.text.accent)
          : AppTypography.labelLarge.copyWith(color: colors.text.accent),
      cursorColor: colors.text.accent,
      decoration: InputDecoration.collapsed(
        hintText: hintText,
        hintStyle: AppTypography.labelLarge.copyWith(color: colors.text.muted),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            if (trailingLabel != null) ...[trailingLabel!],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          height: shellHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.base,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                ),
              ),
              if (focusNode.hasFocus)
                Positioned(
                  left: -2.5,
                  right: -2.5,
                  top: -2.5,
                  bottom: -2.5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        border: Border.all(color: focusRingColor, width: 2),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: _isMultiline
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    if (leading != null && !_isMultiline)
                      SizedBox(
                        width: 32,
                        height: shellHeight,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: leading,
                          ),
                        ),
                      ),
                    if (leading != null && _isMultiline)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: SizedBox(
                          width: 20,
                          height: 48,
                          child: Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: leading,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: _isMultiline
                            ? const EdgeInsets.fromLTRB(
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                              )
                            : const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                        child: _isMultiline
                            ? ScrollbarTheme(
                                data: ScrollbarThemeData(
                                  thumbColor: WidgetStatePropertyAll(
                                    colors.background.overlay.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  radius: const Radius.circular(AppRadii.full),
                                  thickness: const WidgetStatePropertyAll(6),
                                  thumbVisibility: const WidgetStatePropertyAll(
                                    true,
                                  ),
                                  trackVisibility: const WidgetStatePropertyAll(
                                    false,
                                  ),
                                ),
                                child: Scrollbar(
                                  controller: scrollController,
                                  child: input,
                                ),
                              )
                            : input,
                      ),
                    ),
                    if (!_isMultiline)
                      SizedBox(
                        width: 40,
                        height: shellHeight,
                        child: Center(child: trailing),
                      ),
                    if (_isMultiline)
                      SizedBox(
                        width: 40,
                        height: shellHeight,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 14,
                              left: 10,
                              right: 10,
                            ),
                            child: trailing,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          height: 16,
          child: messageText == null
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    if (messageIcon != null) ...[
                      messageIcon!,
                      const SizedBox(width: AppSpacing.xxs),
                    ],
                    Text(
                      messageText!,
                      style: AppTypography.labelMedium.copyWith(
                        color: messageColor,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SendAddMessageCard extends StatelessWidget {
  const _SendAddMessageCard({required this.enabled, this.onTap});

  final bool enabled;
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
              AppIcon(
                AppIcons.scroll,
                size: 16,
                color: enabled ? colors.icon.accent : colors.icon.regular,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Add a Message',
                style: AppTypography.labelMedium.copyWith(
                  color: enabled ? colors.text.accent : colors.text.secondary,
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
