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
import '../../../core/widgets/app_icon.dart';
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
          wait: wait.changeWait,
          amount: wait.changeWaiting,
        ),
      if (wait.receivedWaiting > BigInt.zero)
        (
          key: 'received',
          label: l10n.sendAvailableReceivedRow,
          wait: wait.receivedWait,
          amount: wait.receivedWaiting,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                style:
                    (compact
                            ? AppTypography.headlineMedium
                            : AppTypography.headlineLarge)
                        .copyWith(color: colors.text.accent),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? AppSpacing.s : AppSpacing.sm),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows) ...[
                  Padding(
                    key: ValueKey('spendable_wait_row_${row.key}'),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          AppIcons.time,
                          size: compact ? 18 : 20,
                          color: colors.icon.muted,
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
                              if (row.wait != null)
                                Text(
                                  availableInLabel(l10n, row.wait!),
                                  style: AppTypography.bodySmall.copyWith(
                                    color: colors.text.secondary,
                                  ),
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
                  Container(height: 1, color: colors.border.regular),
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
            ),
          ),
        ),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            l10n.sendAvailableFootnote,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
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
  // The balance is unsettled while a new block is scanned; keep the last
  // settled breakdown rather than blanking the sheet for that moment.
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
    return Padding(
      key: const ValueKey('mobile_spendable_wait_sheet'),
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

  // The popover overhangs the icon so its tail sits under the icon's center.
  static const _overhang = 12.0;
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
              width: 16,
              height: 16,
              child: Center(
                child: ExcludeSemantics(
                  child: AppIcon(
                    AppIcons.time,
                    size: 16,
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
            right: SendSpendableWaitButton._overhang + 8 - 5,
            top: tailBelow ? null : -5,
            bottom: tailBelow ? -5 : null,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 10,
                height: 10,
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
