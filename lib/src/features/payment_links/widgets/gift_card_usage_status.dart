import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../providers/app_security_provider.dart';
import '../models/gift_card_usage.dart';
import '../providers/gift_card_tracking_provider.dart';

/// Keeps observation demand attached to visible product surfaces, not to the
/// lifetime of a global provider or each card row.
class GiftCardTrackingScope extends ConsumerStatefulWidget {
  const GiftCardTrackingScope({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<GiftCardTrackingScope> createState() =>
      _GiftCardTrackingScopeState();
}

class _GiftCardTrackingScopeState extends ConsumerState<GiftCardTrackingScope> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  void _refresh() {
    if (!mounted) return;
    unawaited(
      ref
          .read(giftCardTrackingServiceProvider)
          .refresh()
          .catchError((Object _) {}),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appSecurityProvider, (old, next) {
      if (old?.requiresUnlock == true && !next.requiresUnlock) _refresh();
    });
    return widget.child;
  }
}

class GiftCardUsageStatusView extends ConsumerWidget {
  const GiftCardUsageStatusView({
    required this.address,
    this.showCheckedAt = false,
    this.inline = false,
    super.key,
  });
  final String address;
  final bool showCheckedAt;
  final bool inline;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage =
        ref.watch(giftCardUsageProvider(address)).value ??
        const GiftCardUsage();
    final state = ref.watch(giftCardTrackingStateProvider);
    final checking = !usage.cleaned && state.checking;
    final label = checking && usage.status == GiftCardUsageStatus.unknown
        ? 'Checking usage…'
        : usage.label;
    final suffix = usage.cleaned
        ? ''
        : state.checking
        ? usage.status == GiftCardUsageStatus.unknown
              ? ''
              : ' · Checking…'
        : state.failedFor(address)
        ? ' · Update failed'
        : '';
    if (inline) {
      final failed = !usage.cleaned && !checking && state.failedFor(address);
      final description =
          'Card use: $label'
          '${checking
              ? '. Checking'
              : failed
              ? '. Update failed'
              : ''}'
          '${usage.explanation == null ? '' : '. ${usage.explanation}'}';
      return AppTooltip(
        message: description,
        tapToShow: true,
        excludeFromSemantics: true,
        child: Semantics(
          label: description,
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Reserve space before the label so its right edge stays fixed
              // next to the card actions, including when checking stops.
              SizedBox(
                width: 16,
                height: 16,
                child: checking || failed
                    ? AppIcon(
                        checking ? AppIcons.loader : AppIcons.warningCircle,
                        size: 16,
                        color: context.colors.icon.regular,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: AppTypography.bodySmall.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final checked = usage.checkedAt?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTooltip(
            message: usage.explanation ?? 'Card use: $label$suffix',
            tapToShow: true,
            child: Text(
              'Card use: $label$suffix',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          if (showCheckedAt && checked != null)
            Text(
              'Last checked: ${checked.toString().split('.').first}',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
      ),
    );
  }
}
