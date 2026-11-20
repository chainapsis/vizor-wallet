import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/providers/account_balance_breakdown_provider.dart';
import '../../features/home/services/account_balance_breakdown.dart';
import '../../providers/privacy_mode_provider.dart';
import '../formatting/zec_amount.dart';
import '../l10n/l10n.dart';
import '../privacy/privacy_mask.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_popover_surface.dart';
import 'app_desktop_shell.dart';

// No sign: these amounts are not on their way into the balance, and funds on
// hold mostly leave. The app keeps "+" for money received.
String _popoverAmount(BigInt zatoshi, {required bool privacyModeEnabled}) =>
    hideAmountIfPrivacyMode(
      ZecAmount.fromZatoshi(zatoshi)
          .compactBalancePretty(
            minFractionDigits: 0,
            denomStyle: ZecDenomStyle.upper,
          )
          .toString(),
      privacyModeEnabled: privacyModeEnabled,
    );

String _headlineLabel(
  AppLocalizations l10n,
  AccountBalanceBreakdown breakdown,
) => breakdown.ironwoodOnly
    ? l10n.activityBalanceIronwood
    : l10n.commonShieldedBalance;

typedef _BreakdownRow = ({
  String key,
  String icon,
  String label,
  String detail,
  BigInt amount,
});

List<_BreakdownRow> _breakdownRows(
  AppLocalizations l10n,
  AccountBalanceBreakdown breakdown,
) => [
  if (breakdown.transparent > BigInt.zero)
    (
      key: 'transparent',
      icon: AppIcons.transparentBalance,
      label: l10n.poolTransparent,
      detail: l10n.sidebarBalanceNotShielded,
      amount: breakdown.transparent,
    ),
  if (breakdown.migrating > BigInt.zero)
    (
      key: 'migrating',
      icon: AppIcons.loader,
      label: 'Orchard', // l10n-ignore: pool name
      detail: l10n.sidebarBalanceStillMigrating,
      amount: breakdown.migrating,
    ),
  if (breakdown.sapling > BigInt.zero)
    (
      key: 'sapling',
      icon: AppIcons.shieldKeyhole,
      label: 'Sapling', // l10n-ignore: pool name
      detail: l10n.sidebarBalanceOlderPool,
      amount: breakdown.sapling,
    ),
  if (breakdown.onHold > BigInt.zero)
    (
      key: 'on_hold',
      icon: AppIcons.lock,
      label: l10n.sidebarBalanceOnHold,
      detail: l10n.sidebarBalanceOnHoldDetail,
      amount: breakdown.onHold,
    ),
];

/// What the popover says, for a screen reader, which cannot hover: the
/// holdings the sidebar balance leaves out.
String sidebarBalanceBreakdownSummary(
  AppLocalizations l10n,
  AccountBalanceBreakdown breakdown, {
  required bool privacyModeEnabled,
}) => [
  for (final row in _breakdownRows(l10n, breakdown))
    '${row.label} ${_popoverAmount(row.amount, privacyModeEnabled: privacyModeEnabled)}',
].join(', ');

/// Opens the balance breakdown beside the sidebar while the pointer rests on
/// the account balance.
///
/// The sidebar's layout and tap targets stay as they are: nothing is added
/// to it, the popover opens over the pane rather than the navigation, and it
/// takes no pointer events, so a click meant for something under it lands.
class SidebarBalanceHover extends StatefulWidget {
  const SidebarBalanceHover({
    required this.enabled,
    required this.child,
    this.semanticsTooltip,
    super.key,
  });

  /// [AppTooltip]'s wait, so a pointer passing over the balance opens nothing.
  static const showDelay = Duration(milliseconds: 350);

  /// Opens the popover without a pointer, for a capture of it in place.
  /// Only the figma-compare scenario sets it, and clears it when it leaves.
  static bool debugAlwaysOpen = false;

  static const _gap = AppSpacing.xs;
  static const _edgeMargin = AppSpacing.xs;

  // The tail's center from the popover's top: past the rounded corner.
  static const _tailInset = AppRadii.large + AppPopoverSurface.tailSize;

  /// Whether the account holds anything the balance leaves out.
  final bool enabled;
  final String? semanticsTooltip;
  final Widget child;

  @override
  State<SidebarBalanceHover> createState() => _SidebarBalanceHoverState();
}

class _SidebarBalanceHoverState extends State<SidebarBalanceHover> {
  Timer? _timer;
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _openForCapture();
  }

  @override
  void didUpdateWidget(SidebarBalanceHover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _dismiss();
    _openForCapture();
  }

  void _openForCapture() {
    if (!SidebarBalanceHover.debugAlwaysOpen || !widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry == null) _show();
    });
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  void _schedule() {
    if (!widget.enabled || _entry != null) return;
    _timer?.cancel();
    _timer = Timer(SidebarBalanceHover.showDelay, _show);
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  void _show() {
    _timer = null;
    if (!mounted || !widget.enabled) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || box == null || !box.attached) return;
    // Beside the sidebar's own edge, so the popover never covers its rows.
    RenderBox sidebar = box;
    context.visitAncestorElements((element) {
      if (element.widget is! AppDesktopSidebarSurface) return true;
      final found = element.renderObject;
      if (found is RenderBox) sidebar = found;
      return false;
    });
    final anchorY = box
        .localToGlobal(box.size.centerLeft(Offset.zero), ancestor: overlayBox)
        .dy;
    final left =
        sidebar
            .localToGlobal(
              sidebar.size.topRight(Offset.zero),
              ancestor: overlayBox,
            )
            .dx +
        SidebarBalanceHover._gap +
        AppPopoverSurface.tailSize / 2;
    // The tail meets the balance's line; near the window's top the card
    // stops at the margin and the tail moves up its edge instead.
    final top = math.max(
      SidebarBalanceHover._edgeMargin,
      anchorY - SidebarBalanceHover._tailInset,
    );
    final appTheme = AppTheme.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: AppTheme(
            data: appTheme,
            child: _SidebarBalancePopover(tailInset: anchorY - top),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = widget.enabled ? widget.semanticsTooltip : null;
    return MouseRegion(
      onEnter: (_) => _schedule(),
      onExit: (_) => _dismiss(),
      // A press on the header opens the account menu; the popover gets out
      // of its way without taking the press.
      child: Listener(
        onPointerDown: (_) => _dismiss(),
        child: tooltip == null
            ? widget.child
            : Semantics(tooltip: tooltip, child: widget.child),
      ),
    );
  }
}

class _SidebarBalancePopover extends ConsumerWidget {
  const _SidebarBalancePopover({required this.tailInset});

  final double tailInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(activeAccountBalanceBreakdownProvider);
    if (!breakdown.hasMore) return const SizedBox.shrink();
    return SidebarBalancePopoverSurface(
      breakdown: breakdown,
      privacyModeEnabled: ref.watch(privacyModeProvider),
      tailInset: tailInset,
    );
  }
}

/// The popover's surface: the balance the sidebar shows, then each holding it
/// leaves out and why. A list, not a sum: funds on hold are mostly on their
/// way out, so a total with them would overstate what the account keeps.
class SidebarBalancePopoverSurface extends StatelessWidget {
  const SidebarBalancePopoverSurface({
    required this.breakdown,
    this.privacyModeEnabled = false,
    this.tailInset = AppRadii.large + AppPopoverSurface.tailSize,
    super.key,
  });

  static const width = 288.0;

  final AccountBalanceBreakdown breakdown;
  final bool privacyModeEnabled;

  /// The tail's center from the popover's top.
  final double tailInset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final detailStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
    );
    final rows = _breakdownRows(l10n, breakdown);
    final amountStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return AppPopoverSurface(
      surfaceKey: const ValueKey('sidebar_balance_popover'),
      width: width,
      tailEdge: AppPopoverTailEdge.left,
      tailInset: tailInset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headlineLabel(l10n, breakdown),
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  hideAmountIfPrivacyMode(
                    ZecAmount.fromZatoshi(
                      breakdown.headline,
                    ).pretty(denomStyle: ZecDenomStyle.upper).toString(),
                    privacyModeEnabled: privacyModeEnabled,
                  ),
                  key: const ValueKey('sidebar_balance_popover_headline'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
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
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0)
                      Container(height: 1, color: colors.border.regular),
                    Padding(
                      key: ValueKey('sidebar_balance_popover_row_${row.key}'),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          AppIcon(row.icon, size: 18, color: colors.icon.muted),
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
                                Text(row.detail, style: detailStyle),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _popoverAmount(
                              row.amount,
                              privacyModeEnabled: privacyModeEnabled,
                            ),
                            style: amountStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
