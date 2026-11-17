import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_context_menu.dart' show appContextMenuShadow;
import '../../../core/config/network_config.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/mobile/mobile_section.dart';
import '../../../core/widgets/mobile/mobile_serif_amount.dart';
import '../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../core/zcash/spendable_wait.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/spendable_wait_provider.dart';

/// What the account can send now, then each amount it cannot spend yet with
/// its wait, then their total. Only the spendable amount is emphasized.
///
/// Shared by the mobile sheet and the desktop popover on Send.
class SpendableWaitBreakdown extends StatelessWidget {
  const SpendableWaitBreakdown({
    required this.wait,
    this.privacyModeEnabled = false,
    this.compact = false,
    super.key,
  });

  final SpendableWait wait;
  final bool privacyModeEnabled;

  /// Desktop popover metrics.
  final bool compact;

  /// The amount without its ticker, for the sheet's serif figure.
  String _bareAmount(BigInt zatoshi) => hideIfPrivacyMode(
    ZecAmount.fromZatoshi(
      zatoshi,
    ).pretty(denomStyle: ZecDenomStyle.none).toString(),
    privacyModeEnabled: privacyModeEnabled,
  );

  String _amount(BigInt zatoshi, {bool added = false}) {
    final text = ZecAmount.fromZatoshi(
      zatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    return hideAmountIfPrivacyMode(
      added ? '+$text' : text,
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rows = [
      if (wait.changeWaiting > BigInt.zero)
        (
          key: 'change',
          label: l10n.sendAvailableChangeRow,
          wait: wait.changeWait!,
          amount: wait.changeWaiting,
        ),
      if (wait.receivedWaiting > BigInt.zero)
        (
          key: 'received',
          label: l10n.sendAvailableReceivedRow,
          wait: wait.receivedWait!,
          amount: wait.receivedWaiting,
        ),
    ];
    // The popover has room only for the small type; the sheet follows the
    // mobile standards (16px text, the shared card and hairline).
    final detailStyle =
        (compact ? AppTypography.bodySmall : AppTypography.bodyMedium).copyWith(
          color: colors.text.secondary,
        );
    final waitingRows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          Padding(
            key: ValueKey('spendable_wait_row_${row.key}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                AppIcon(
                  AppIcons.time,
                  size: compact ? 18 : 20,
                  color: compact ? colors.icon.muted : colors.icon.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                      Text(
                        availableInLabel(l10n, row.wait),
                        style: detailStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  _amount(row.amount, added: true),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (compact)
            Container(height: 1, color: colors.border.regular)
          else
            const MobileSectionDivider(),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.commonTotal,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              Text(
                _amount(wait.total),
                key: const ValueKey('spendable_wait_total'),
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.sendAvailableTitle,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _amount(wait.availableNow),
                  key: const ValueKey('spendable_wait_available_now'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          )
        else
          // The sheet's title names the amount; a long one shrinks to fit.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                key: const ValueKey('spendable_wait_available_now'),
                TextSpan(
                  children: [
                    serifPrivacyMaskSpan(
                      '${_bareAmount(wait.availableNow)} ',
                      kMobileSerifAmountStyle.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    TextSpan(
                      text: kZcashDefaultCurrencyTicker,
                      style: kMobileSerifTickerStyle.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ),
        SizedBox(height: compact ? AppSpacing.s : AppSpacing.sm),
        if (compact)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.neutralSubtleOpacity,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.xs,
              ),
              child: waitingRows,
            ),
          )
        else
          MobileSurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: waitingRows,
          ),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(l10n.sendAvailableFootnote, style: detailStyle),
        ),
      ],
    );
  }
}

/// Opens the breakdown of what [accountUuid] can send now and what it is
/// still waiting for. The sheet follows the balance while it is open.
Future<void> showMobileSpendableWaitSheet(
  BuildContext context, {
  required String accountUuid,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) =>
        _SpendableWaitSheetBody(accountUuid: accountUuid),
  );
}

class _SpendableWaitSheetBody extends ConsumerStatefulWidget {
  const _SpendableWaitSheetBody({required this.accountUuid});

  final String accountUuid;

  @override
  ConsumerState<_SpendableWaitSheetBody> createState() =>
      _SpendableWaitSheetBodyState();
}

class _SpendableWaitSheetBodyState
    extends ConsumerState<_SpendableWaitSheetBody> {
  // No wait is stated after a failed sync; keep the last breakdown rather
  // than blanking a sheet that is open.
  SpendableWait? _last;

  @override
  Widget build(BuildContext context) {
    final wait = ref.watch(spendableWaitProvider(widget.accountUuid)) ?? _last;
    _last = wait;
    return SpendableWaitSheetContent(
      wait: wait,
      privacyModeEnabled: ref.watch(privacyModeProvider),
      onClose: () => Navigator.of(context).pop(),
    );
  }
}

/// The sheet's content: the breakdown above a Close button.
class SpendableWaitSheetContent extends StatelessWidget {
  const SpendableWaitSheetContent({
    required this.wait,
    required this.onClose,
    this.privacyModeEnabled = false,
    super.key,
  });

  final SpendableWait? wait;
  final bool privacyModeEnabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MobileModalScaffold(
      key: const ValueKey('mobile_spendable_wait_sheet'),
      title: context.l10n.sendAvailableTitle,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wait != null)
            SpendableWaitBreakdown(
              wait: wait!,
              privacyModeEnabled: privacyModeEnabled,
            ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: onClose,
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }
}

/// The clock beside Use Max on desktop Send, shown while some funds cannot
/// be spent yet. Opens the breakdown in a popover anchored to it; the
/// popover follows the balance while it is open.
class SendSpendableWaitButton extends ConsumerStatefulWidget {
  const SendSpendableWaitButton({required this.accountUuid, super.key});

  static const popoverWidth = 288.0;

  // Enough for two waiting rows; decides only which way the popover opens.
  static const _popoverHeightEstimate = 280.0;

  static const _iconSize = 16.0;
  static const _tailSize = 10.0;

  // The tail's center from the popover's trailing edge: past the rounded
  // corner, on the straight part of the edge.
  static const _tailInset = AppRadii.large + _tailSize;

  // How far the popover overhangs the icon, so the tail meets its center.
  static const _overhang = _tailInset - _iconSize / 2;
  static const _gap = AppSpacing.xs;

  final String accountUuid;

  @override
  ConsumerState<SendSpendableWaitButton> createState() =>
      _SendSpendableWaitButtonState();
}

class _SendSpendableWaitButtonState
    extends ConsumerState<SendSpendableWaitButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide(rebuild: false);
    super.dispose();
  }

  void _toggle() => _entry == null ? _show() : _hide();

  void _show() {
    final appTheme = AppTheme.of(context);
    // Above the icon, clear of the amount field, unless there is no room.
    final box = context.findRenderObject() as RenderBox?;
    final top = box?.localToGlobal(Offset.zero).dy ?? double.infinity;
    final above =
        top >=
        SendSpendableWaitButton._popoverHeightEstimate +
            SendSpendableWaitButton._gap;
    _entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: above ? Alignment.topRight : Alignment.bottomRight,
            followerAnchor: above ? Alignment.bottomRight : Alignment.topRight,
            offset: Offset(
              SendSpendableWaitButton._overhang,
              above
                  ? -SendSpendableWaitButton._gap
                  : SendSpendableWaitButton._gap,
            ),
            child: AppTheme(
              data: appTheme,
              child: _SpendableWaitPopover(
                accountUuid: widget.accountUuid,
                tailBelow: above,
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _hide({bool rebuild = true}) {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final open = _entry != null;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        expanded: open,
        label: context.l10n.sendSpendableInfoLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('send_spendable_wait_button'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: SizedBox(
              width: SendSpendableWaitButton._iconSize,
              height: SendSpendableWaitButton._iconSize,
              child: Center(
                child: ExcludeSemantics(
                  child: AppIcon(
                    AppIcons.time,
                    size: SendSpendableWaitButton._iconSize,
                    color: open ? colors.icon.accent : colors.icon.regular,
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

class _SpendableWaitPopover extends ConsumerStatefulWidget {
  const _SpendableWaitPopover({
    required this.accountUuid,
    required this.tailBelow,
  });

  final String accountUuid;
  final bool tailBelow;

  @override
  ConsumerState<_SpendableWaitPopover> createState() =>
      _SpendableWaitPopoverState();
}

class _SpendableWaitPopoverState extends ConsumerState<_SpendableWaitPopover> {
  SpendableWait? _last;

  @override
  Widget build(BuildContext context) {
    final wait = ref.watch(spendableWaitProvider(widget.accountUuid)) ?? _last;
    _last = wait;
    if (wait == null) return const SizedBox.shrink();
    return SpendableWaitPopoverSurface(
      wait: wait,
      privacyModeEnabled: ref.watch(privacyModeProvider),
      tailBelow: widget.tailBelow,
    );
  }
}

/// The popover's surface: the compact breakdown on a raised card, with a
/// tail at its trailing corner pointing at the icon that opened it.
class SpendableWaitPopoverSurface extends StatelessWidget {
  const SpendableWaitPopoverSurface({
    required this.wait,
    this.privacyModeEnabled = false,
    this.tailBelow = true,
    super.key,
  });

  final SpendableWait wait;
  final bool privacyModeEnabled;

  /// Whether the popover sits above its icon, with the tail on its bottom.
  final bool tailBelow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final edge = BorderSide(color: colors.border.subtleOpacity);
    // Merged, not replaced: the ambient style carries the locale's fonts.
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: const ValueKey('send_spendable_wait_popover'),
            width: SendSpendableWaitButton.popoverWidth,
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.raised,
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: colors.border.subtleOpacity),
              boxShadow: appContextMenuShadow,
            ),
            child: SpendableWaitBreakdown(
              wait: wait,
              privacyModeEnabled: privacyModeEnabled,
              compact: true,
            ),
          ),
          Positioned(
            right:
                SendSpendableWaitButton._tailInset -
                SendSpendableWaitButton._tailSize / 2,
            top: tailBelow ? null : -SendSpendableWaitButton._tailSize / 2,
            bottom: tailBelow ? -SendSpendableWaitButton._tailSize / 2 : null,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: SendSpendableWaitButton._tailSize,
                height: SendSpendableWaitButton._tailSize,
                decoration: BoxDecoration(
                  color: colors.background.raised,
                  border: tailBelow
                      ? Border(right: edge, bottom: edge)
                      : Border(left: edge, top: edge),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
