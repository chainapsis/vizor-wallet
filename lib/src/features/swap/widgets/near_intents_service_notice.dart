import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../domain/near_intents_service_status.dart';
import '../domain/swap_asset.dart';

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

// Figma's warning/light and warning-alpha-subtle tokens are not yet part of
// the app palette. Keep this notice's exact orange treatment local to it.
const _warningOrange = Color(0xFFE7581B);

/// Pure presentation, shared by production, Widgetbook and widget captures.
class NearIntentsServiceNoticeModal extends StatelessWidget {
  const NearIntentsServiceNoticeModal({
    required this.notice,
    required this.onClose,
    required this.onDetails,
    this.payMode = false,
    super.key,
  });
  final NearIntentsServiceNoticeData notice;
  final VoidCallback onClose;
  final Future<void> Function() onDetails;
  final bool payMode;

  @override
  Widget build(BuildContext context) {
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final content = _NoticeContent(
      notice: notice,
      payMode: payMode,
      onClose: onClose,
      onDetails: onDetails,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (mobile) {
          final bottom =
              AppSpacing.base +
              (defaultTargetPlatform == TargetPlatform.android
                  ? MediaQuery.viewPaddingOf(context).bottom
                  : 0);
          return MobileModalCard(
            margin: EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              bottom,
            ),
            child: content,
          );
        }
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight - AppSpacing.base,
            ),
            child: AppModalCard(
              padding: EdgeInsets.zero,
              highlight: true,
              child: content,
            ),
          ),
        );
      },
    );
  }
}

class _NoticeContent extends StatelessWidget {
  const _NoticeContent({
    required this.notice,
    required this.payMode,
    required this.onClose,
    required this.onDetails,
  });
  final NearIntentsServiceNoticeData notice;
  final bool payMode;
  final VoidCallback onClose;
  final Future<void> Function() onDetails;

  @override
  Widget build(BuildContext context) {
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final colors = context.colors;
    final chains = {for (final issue in notice.issues) ...issue.chains}.toList()
      ..sort();
    final networks = chains.contains('*')
        ? 'All chains'
        : chains.map(swapChainDisplayName).join(', ');
    final windows = <NearIntentsServiceIssue>[];
    final seen = <String>{};
    for (final issue in notice.issues) {
      if (!issue.isMaintenance) continue;
      if (seen.add(
        '${issue.startsAt}:${issue.finishesAt}:${(issue.chains.toList()..sort()).join(',')}',
      )) {
        windows.add(issue);
      }
    }
    final title = notice.maintenanceOnly
        ? 'Maintenance notice'
        : 'Service notice';
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );
    return Semantics(
      namesRoute: true,
      label: title,
      scopesRoute: true,
      explicitChildNodes: true,
      child: Stack(
        key: const ValueKey('near_intents_service_notice'),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sm,
              mobile ? AppSpacing.base : AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Text(
                    title,
                    style:
                        (mobile
                                ? AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )
                                : AppTypography.labelLarge.copyWith(
                                    fontWeight: FontWeight.w400,
                                  ))
                            .copyWith(color: colors.text.accent),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('near_intents_service_notice_body'),
                    primary: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (notice.maintenanceOnly) ...[
                          Text(
                            'NEAR Intents is under maintenance.',
                            style: bodyStyle,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        Text(
                          payMode
                              ? 'Payments may not work right now.'
                              : 'Swaps may not work right now.',
                          style: bodyStyle,
                        ),
                        for (final window in windows) ...[
                          const SizedBox(height: AppSpacing.sm),
                          if (!notice.maintenanceOnly)
                            Text(
                              'Maintenance window: ${window.chains.contains('*') ? 'All chains' : window.chains.map(swapChainDisplayName).join(', ')}',
                              style: bodyStyle,
                            )
                          else if (windows.length > 1)
                            Text(
                              window.chains.contains('*')
                                  ? 'All chains'
                                  : window.chains
                                        .map(swapChainDisplayName)
                                        .join(', '),
                              style: bodyStyle,
                            ),
                          Text(
                            'Start: ${formatNearIntentsServiceTime(window.startsAt!)}',
                            style: bodyStyle,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Expected end: ${formatNearIntentsServiceTime(window.finishesAt!)}',
                            style: bodyStyle,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: _warningOrange.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(
                              AppRadii.medium,
                            ),
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      notice.maintenanceOnly
                                          ? 'List of maintenance'
                                          : 'Affected networks',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.headlineSmall
                                          .copyWith(color: _warningOrange),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      networks,
                                      textAlign: TextAlign.center,
                                      style: AppTypography.bodyMediumStrong
                                          .copyWith(color: colors.text.accent),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: SvgPicture.asset(
                                  'assets/icons/near_intents_maintenance_wordmark.svg',
                                  width: 91.9008,
                                  height: 10.9945,
                                  semanticsLabel: 'NEAR Intents',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  key: const ValueKey('near_intents_service_notice_details'),
                  variant: AppButtonVariant.ghost,
                  size: mobile
                      ? AppButtonSize.large
                      : AppButtonSize.mediumLarge,
                  expand: true,
                  constrainContent: true,
                  growWithContent: true,
                  onPressed: () => unawaited(onDetails()),
                  trailing: const AppIcon(
                    AppIcons.arrowTopRight,
                    size: AppIconSize.medium,
                  ),
                  child: const Text(
                    'NEAR Intents status page',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('near_intents_service_notice_ok'),
                  size: mobile
                      ? AppButtonSize.large
                      : AppButtonSize.mediumLarge,
                  expand: true,
                  growWithContent: true,
                  onPressed: onClose,
                  child: const Text('Ok'),
                ),
              ],
            ),
          ),
          Positioned(
            // A 44px mobile hit target surrounds the 32px Figma circle.
            top: mobile ? AppSpacing.sm - 6 : AppSpacing.sm,
            right: mobile ? AppSpacing.sm - 6 : AppSpacing.sm,
            child: Semantics(
              button: true,
              label: 'Close service notice',
              child: AppButton(
                key: const ValueKey('near_intents_service_notice_close'),
                variant: mobile
                    ? AppButtonVariant.ghost
                    : AppButtonVariant.secondary,
                height: mobile ? 44 : 32,
                minWidth: mobile ? 44 : 32,
                contentPadding: EdgeInsets.zero,
                onPressed: onClose,
                child: ExcludeSemantics(
                  child: mobile
                      ? Container(
                          key: const ValueKey(
                            'near_intents_service_notice_close_circle',
                          ),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: colors.button.secondary.bg,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: AppIcon(AppIcons.cross, size: 20),
                          ),
                        )
                      : const AppIcon(AppIcons.cross, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Explicit local date and numeric UTC offset also disambiguate midnight,
/// long-running maintenance and repeated wall-clock times around DST changes.
String formatNearIntentsServiceTime(DateTime value) {
  final time = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final offset = time.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)} '
      '(UTC${offset.isNegative ? '-' : '+'}${two(minutes ~/ 60)}:${two(minutes % 60)})';
}
