import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_review_row.dart';
import '../../../../core/widgets/mobile/mobile_tx_fee_info_sheet.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../../activity/activity_row_mapper.dart'
    show formatActivityTimestamp;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../services/send_flow.dart';
import '../../widgets/send_recipient_resolver.dart';
import '../../widgets/send_review_layout.dart' show SendReviewContactRecipient;
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

enum _MobileSendStatusPhase { sending, pendingBroadcast, succeeded, failed }

typedef MobileSendBroadcastRunner =
    Future<SendBroadcastOutcome> Function({
      required WidgetRef ref,
      required SendReviewArgs args,
      required AppLocalizations l10n,
      KeystoneBroadcastArgs? keystone,
      required Future<bool> Function() confirmSaplingParamsDownload,
      Future<bool> Function()? shouldAbort,
    });

class MobileSendStatusScreen extends ConsumerStatefulWidget {
  const MobileSendStatusScreen({
    required this.args,
    this.keystone,
    this.broadcastRunner,
    super.key,
  });

  final SendReviewArgs args;
  final KeystoneBroadcastArgs? keystone;

  @visibleForTesting
  final MobileSendBroadcastRunner? broadcastRunner;

  @override
  ConsumerState<MobileSendStatusScreen> createState() =>
      _MobileSendStatusScreenState();
}

class _MobileSendStatusScreenState
    extends ConsumerState<MobileSendStatusScreen> {
  var _phase = _MobileSendStatusPhase.sending;
  var _proposalConsumed = false;
  var _discardScheduled = false;
  String? _displayTxid;
  String? _protocolTxid;
  String? _statusMessage;
  String? _error;
  late final DateTime _startedAt = DateTime.now();
  DateTime? _completedAt;

  @override
  void initState() {
    super.initState();
    _proposalConsumed = widget.keystone != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startBroadcast());
    });
  }

  @override
  void dispose() {
    if (_phase != _MobileSendStatusPhase.sending) {
      _scheduleDiscardIfNeeded();
    }
    super.dispose();
  }

  void _scheduleDiscardIfNeeded() {
    if (_proposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      discardSendProposal(
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: 'MobileSendStatus(dispose)',
      ),
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

  Future<void> _startBroadcast() async {
    final runner = widget.broadcastRunner ?? runSendBroadcast;
    final l10n = AppLocalizations.of(context);
    final outcome = await runner(
      ref: ref,
      args: widget.args,
      l10n: l10n,
      keystone: widget.keystone,
      confirmSaplingParamsDownload: _confirmSaplingParamsDownload,
      shouldAbort: () async => !mounted,
    );
    _proposalConsumed = outcome.proposalConsumed;
    if (outcome.phase == SendBroadcastPhase.aborted || !mounted) return;

    final displayTxid = outcome.txid?.trim();
    setState(() {
      _phase = switch (outcome.phase) {
        SendBroadcastPhase.succeeded => _MobileSendStatusPhase.succeeded,
        SendBroadcastPhase.pendingBroadcast =>
          _MobileSendStatusPhase.pendingBroadcast,
        SendBroadcastPhase.failed => _MobileSendStatusPhase.failed,
        SendBroadcastPhase.aborted => _MobileSendStatusPhase.failed,
      };
      _displayTxid = displayTxid == null || displayTxid.isEmpty
          ? null
          : displayTxid;
      _protocolTxid = _displayTxid == null
          ? null
          : _displayOrderToProtocolTxidHex(_displayTxid!);
      _statusMessage = outcome.statusMessage;
      _error = outcome.error;
      if (outcome.phase != SendBroadcastPhase.failed) {
        _completedAt = DateTime.now();
      }
    });
  }

  void _handleBack() {
    if (_phase == _MobileSendStatusPhase.sending) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  bool get _routePopAllowed => _phase != _MobileSendStatusPhase.sending;

  Future<void> _openExplorer() async {
    final txid = _displayTxid;
    if (txid == null) return;
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: txid,
      txidOrder: ZcashExplorerTxidOrder.display,
    );
    if (launched || !mounted) return;
    await Clipboard.setData(ClipboardData(text: _protocolTxid ?? txid));
    if (!mounted) return;
    showAppToast(context, AppLocalizations.of(context).activityTxHashCopied);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final args = widget.args;
    final statusMessage = _statusMessage?.trim();
    final error = _phase == _MobileSendStatusPhase.failed
        ? _error ?? AppLocalizations.of(context).sendTxCouldNotBeSent
        : null;
    final txid = _protocolTxid;
    final amountFiatText = fiatTextForZatoshi(
      args.amountZatoshi,
      zecUsdUnitPrice: ref.watch(zecHomeUsdUnitPriceProvider),
    );
    final recipientPoolLabel = _recipientPoolLabel(
      args.addressType,
      isShielded: args.isShielded,
      l10n: AppLocalizations.of(context),
    );
    // Resolve the recipient to a saved contact / own account so the To row
    // shows a name + avatar — parity with desktop send status and the
    // review step (a raw address right after "Alice" in review reads as a
    // regression).
    final namedRecipient = args.address.trim().isEmpty
        ? null
        : switch (sendReviewRecipientFor(
            contacts:
                ref.watch(addressBookProvider).value?.contacts ??
                const <AddressBookContact>[],
            address: args.address,
            ownAccounts:
                ref.watch(ownAccountAddressesProvider).value ??
                const <String, AccountInfo>{},
          )) {
            SendReviewContactRecipient r => r,
            _ => null,
          };

    return PopScope<void>(
      canPop: _routePopAllowed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: AppToastHost(
          child: SafeArea(
            child: Column(
              children: [
                MobileTopNav.back(
                  title: _title,
                  onBack: _phase == _MobileSendStatusPhase.sending
                      ? null
                      : _handleBack,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('mobile_send_status_${_phase.name}'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.s,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MobileReviewInfoRow(
                                label: AppLocalizations.of(context).navAmount,
                                value: ZecAmount.fromZatoshi(
                                  args.amountZatoshi,
                                ).activityDetail.toString(),
                                leading: const MobileReviewZecBadge(),
                                bottom: amountFiatText == null
                                    ? null
                                    : Text(
                                        amountFiatText,
                                        key: const ValueKey(
                                          'mobile_send_status_amount_fiat',
                                        ),
                                        style: AppTypography.labelMedium
                                            .copyWith(
                                              color: colors.text.secondary,
                                            ),
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              const MobileReviewFlowArrow(),
                              const SizedBox(height: AppSpacing.xs),
                              MobileReviewInfoRow(
                                label: 'To',
                                value: namedRecipient != null
                                    ? namedRecipient.name
                                    : _truncateAddress(args.address),
                                strikethrough:
                                    _phase == _MobileSendStatusPhase.failed,
                                leading: namedRecipient != null
                                    ? AppProfilePicture(
                                        profilePictureId:
                                            namedRecipient.profilePictureId,
                                        size: AppProfilePictureSize.navLarge,
                                      )
                                    : MobileReviewIconBadge(
                                        child: AppIcon(
                                          AppIcons.wallet,
                                          size: 18,
                                          color: colors.icon.regular,
                                        ),
                                      ),
                                bottom: Row(
                                  children: [
                                    AppIcon(
                                      args.isShielded
                                          ? AppIcons.shieldKeyhole
                                          : AppIcons.transparentBalance,
                                      size: AppIconSize.medium,
                                      color: args.isShielded
                                          ? colors.icon.brandCrimson
                                          : colors.icon.muted,
                                    ),
                                    const SizedBox(width: AppSpacing.xxs),
                                    Text(
                                      namedRecipient != null
                                          ? _truncateAddress(args.address)
                                          : recipientPoolLabel,
                                      style: AppTypography.labelMedium.copyWith(
                                        color: colors.text.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _DetailCard(
                          phase: _phase,
                          memo: args.memo,
                          timestampText: formatActivityTimestamp(
                            _completedAt ?? _startedAt,
                            l10n: AppLocalizations.of(context),
                          ),
                          txidText: txid == null ? null : truncatedTxid(txid),
                          onOpenExplorer: txid == null
                              ? null
                              : () => unawaited(_openExplorer()),
                          feeText: ZecAmount.fromZatoshi(
                            args.feeZatoshi,
                          ).fee.toString(),
                        ),
                        if (statusMessage != null &&
                            statusMessage.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            statusMessage,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            error,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.destructive,
                            ),
                          ),
                        ],
                      ],
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

  String get _title {
    final l10n = AppLocalizations.of(context);
    return switch (_phase) {
      _MobileSendStatusPhase.sending => l10n.activitySendingEllipsis,
      _MobileSendStatusPhase.pendingBroadcast => l10n.activitySendingEllipsis,
      _MobileSendStatusPhase.succeeded => l10n.activitySentSuccessfully,
      _MobileSendStatusPhase.failed => l10n.activitySendFailed,
    };
  }

  String _displayOrderToProtocolTxidHex(String txidHex) {
    final normalized = txidHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      return normalized;
    }
    final bytes = <String>[
      for (var i = 0; i < normalized.length; i += 2)
        normalized.substring(i, i + 2),
    ];
    return bytes.reversed.join();
  }

  String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)} ... '
        '${address.substring(address.length - 5)}';
  }
}

String _recipientPoolLabel(
  String addressType, {
  required bool isShielded,
  required AppLocalizations l10n,
}) {
  return switch (addressType.trim().toLowerCase()) {
    'tex' => 'TEX',
    'unified' || 'sapling' => l10n.receiveShielded,
    'transparent' => l10n.receiveTransparent,
    _ => isShielded ? l10n.receiveShielded : l10n.receiveTransparent,
  };
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.phase,
    required this.memo,
    required this.timestampText,
    required this.txidText,
    required this.onOpenExplorer,
    required this.feeText,
  });

  final _MobileSendStatusPhase phase;
  final String? memo;
  final String timestampText;
  final String? txidText;
  final VoidCallback? onOpenExplorer;
  final String feeText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final memoText = memo?.trim();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ListRow(
            label: AppLocalizations.of(context).navStatus,
            labelColor: phase == _MobileSendStatusPhase.failed
                ? colors.text.destructive
                : null,
            value: _StatusChip(phase: phase),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (memoText != null && memoText.isNotEmpty) ...[
            _ListRow(
              label: AppLocalizations.of(context).activityMessage,
              value: _ValueWithIcon(text: _previewMemo(memoText)),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          _ListRow(
            label: AppLocalizations.of(context).activityTimestamp,
            value: _ValueWithIcon(text: timestampText),
          ),
          if (txidText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ListRow(
              key: const ValueKey('mobile_send_status_txid'),
              label: AppLocalizations.of(context).activityTxId,
              value: _ValueWithIcon(
                text: txidText,
                iconName: AppIcons.arrowTopRight,
                onTap: onOpenExplorer,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: colors.border.regular),
          const SizedBox(height: AppSpacing.sm),
          _ListRow(
            label: AppLocalizations.of(context).txFeeSheetTitle,
            labelStyle: AppTypography.labelLarge,
            value: _ValueWithIcon(
              text: feeText,
              iconName: AppIcons.help,
              iconColor: context.colors.icon.regular.withValues(alpha: 0.72),
              onTap: () => unawaited(showMobileTxFeeInfoSheet(context)),
            ),
          ),
        ],
      ),
    );
  }

  String _previewMemo(String memoText) {
    final collapsed = memoText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 18) return collapsed;
    return '${collapsed.substring(0, 18).trimRight()}...';
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.label,
    required this.value,
    this.labelColor,
    this.labelStyle,
    super.key,
  });

  final String label;
  final Widget value;
  final Color? labelColor;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              label,
              style: (labelStyle ?? AppTypography.labelMedium).copyWith(
                color: labelColor ?? colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
  }
}

class _ValueWithIcon extends StatelessWidget {
  const _ValueWithIcon({this.text, this.iconName, this.onTap, this.iconColor});

  final String? text;
  final String? iconName;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text != null)
            Flexible(
              child: Text(
                text!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          if (iconName != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(
              iconName!,
              size: 20,
              color: iconColor ?? colors.icon.accent,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.phase});

  final _MobileSendStatusPhase phase;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final (iconName, text, color) = switch (phase) {
      _MobileSendStatusPhase.sending ||
      _MobileSendStatusPhase.pendingBroadcast => (
        AppIcons.loader,
        l10n.activityInProgress,
        colors.text.secondary,
      ),
      _MobileSendStatusPhase.succeeded => (
        AppIcons.checkCircle,
        l10n.activityCompleted,
        colors.text.positiveStrong,
      ),
      _MobileSendStatusPhase.failed => (
        AppIcons.cross,
        l10n.activityFailedFundsReturned,
        colors.text.destructive,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(iconName, size: 20, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
