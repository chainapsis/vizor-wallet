import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../domain/near_intents_service_status.dart';
import '../domain/swap_asset.dart';
import '../domain/swap_direction.dart';
import '../providers/near_intents_service_status_provider.dart';

final nearIntentsServiceStatusPage = Uri.https(
  'partners.near-intents.org',
  '/shield/status',
);

typedef ServiceStatusPageLauncher = Future<bool> Function(Uri uri);

final nearIntentsServiceStatusPageLauncherProvider =
    Provider<ServiceStatusPageLauncher>(
      (ref) =>
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

/// Inserted only on the Swap composer and Pay amount step, never on review or
/// signing screens. No state from this advisory participates in button gating.
class NearIntentsServiceNotice extends ConsumerWidget {
  const NearIntentsServiceNotice({
    required this.direction,
    required this.externalAsset,
    this.payMode = false,
    super.key,
  });

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final bool payMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drop the subscription while a review/picker route covers the first screen.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(nearIntentsServiceStatusProvider);
    final notice = status.noticeFor(
      inputChain: direction.fromAsset(externalAsset).chainTicker,
      outputChain: direction.toAsset(externalAsset).chainTicker,
    );
    if (notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: NearIntentsServiceNoticeCard(
        notice: notice,
        payMode: payMode,
        chainLabels: {
          'zec': 'Zcash',
          externalAsset.chainTicker: externalAsset.chainLabel,
        },
        onDetails: () async {
          try {
            await ref.read(nearIntentsServiceStatusPageLauncherProvider)(
              nearIntentsServiceStatusPage,
            );
          } catch (_) {
            // Opening optional details must not interrupt the payment form.
          }
        },
      ),
    );
  }
}

/// Pure presentation so previews and captures never require HTTP or Rust.
class NearIntentsServiceNoticeCard extends StatelessWidget {
  const NearIntentsServiceNoticeCard({
    required this.notice,
    required this.onDetails,
    this.payMode = false,
    this.chainLabels = const {},
    super.key,
  });

  final NearIntentsServiceNoticeData notice;
  final Future<void> Function() onDetails;
  final bool payMode;
  final Map<String, String> chainLabels;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final upcoming = notice.upcoming;
    // A provisional information tint blended with the themed surface. Current
    // issues use the design system's gold utility background and warning ink.
    const informationTint = Color(0xFF6E8CA8);
    final background = upcoming
        ? Color.lerp(colors.background.base, informationTint, 0.15)!
        : colors.background.utilitySuccessSubtle;
    final iconColor = upcoming ? colors.icon.muted : colors.icon.warning;
    final title = upcoming
        ? 'Maintenance scheduled'
        : payMode
        ? 'Payments may not work'
        : 'Swaps may not work';
    final windows = <NearIntentsServiceIssue>[];
    final seen = <String>{};
    for (final issue in notice.issues) {
      if (!issue.isMaintenance) continue;
      final chains = issue.chains.toList()..sort();
      if (seen.add(
        '${issue.startsAt}:${issue.finishesAt}:${chains.join(',')}:${issue.direction}',
      )) {
        windows.add(issue);
      }
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('near_intents_service_notice'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 240 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final details = AppButton(
                  key: const ValueKey('near_intents_service_notice_details'),
                  variant: AppButtonVariant.ghost,
                  size: kAppFormFactor == AppFormFactor.mobile
                      ? AppButtonSize.large
                      : AppButtonSize.medium,
                  onPressed: () => unawaited(onDetails()),
                  trailing: const AppIcon(
                    AppIcons.arrowTopRight,
                    size: AppIconSize.medium,
                  ),
                  child: const Text('Details'),
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: AppIcon(
                            upcoming ? AppIcons.time : AppIcons.warningCircle,
                            size: AppIconSize.medium,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              title,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.accent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        if (!stacked) details,
                      ],
                    ),
                    if (stacked)
                      Align(alignment: Alignment.centerRight, child: details),
                  ],
                );
              },
            ),
            if (upcoming) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                payMode
                    ? 'Payments may not work during this time.'
                    : 'Swaps may not work during this time.',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            for (final window in windows) ...[
              const SizedBox(height: AppSpacing.xs),
              if (windows.length > 1)
                Text(
                  window.chains.contains('*')
                      ? 'All networks'
                      : window.chains
                            .map((c) => chainLabels[c] ?? c.toUpperCase())
                            .join(', '),
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              _TimeRow(label: 'Starts', time: window.startsAt!),
              const SizedBox(height: AppSpacing.xxs),
              _TimeRow(label: 'Ends', time: window.finishesAt!),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.time});
  final String label;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final local = time.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final value =
        '${months[local.month - 1]} ${local.day}, ${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} ${local.timeZoneName}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}
