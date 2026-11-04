import 'dart:async';

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
// the app palette. Keep the content banner's exact orange treatment local.
const _warningOrange = Color(0xFFE7581B);

/// Standard card chrome for desktop and deterministic inline captures.
/// Production mobile presentation uses showAppMobileSheet, which owns the card.
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
    final content = NearIntentsServiceNoticeContent(
      notice: notice,
      payMode: payMode,
      onClose: onClose,
      onDetails: onDetails,
    );
    if (kAppFormFactor == AppFormFactor.mobile) {
      return SafeArea(bottom: false, child: MobileModalCard(child: content));
    }
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: constraints.maxHeight - AppSpacing.base,
          ),
          child: AppModalCard(padding: EdgeInsets.zero, child: content),
        ),
      ),
    );
  }
}

/// Sheet body only: the shared sheet owns its surface, safe-area margins,
/// keyboard avoidance, iOS corners and presentation/dismissal animation.
class NearIntentsServiceNoticeContent extends StatelessWidget {
  const NearIntentsServiceNoticeContent({
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
    final title = notice.maintenanceOnly
        ? 'Maintenance notice'
        : 'Service notice';
    final section = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: _NoticeBody(notice: notice, payMode: payMode),
        ),
        const SizedBox(height: AppSpacing.md),
        _NoticeActions(onClose: onClose, onDetails: onDetails),
      ],
    );
    final Widget content;
    if (kAppFormFactor == AppFormFactor.mobile) {
      content = MobileModalScaffold(
        title: title,
        onClose: onClose,
        titleMaxLines: 2,
        constrainBody: true,
        child: section,
      );
    } else {
      content = Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Text(
                    title,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w400,
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(child: section),
              ],
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Semantics(
              button: true,
              label: 'Close service notice',
              child: AppButton(
                key: const ValueKey('near_intents_service_notice_close'),
                variant: AppButtonVariant.secondary,
                height: 32,
                minWidth: 32,
                contentPadding: EdgeInsets.zero,
                onPressed: onClose,
                child: const ExcludeSemantics(
                  child: AppIcon(AppIcons.cross, size: 20),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      key: const ValueKey('near_intents_service_notice'),
      namesRoute: true,
      label: title,
      scopesRoute: true,
      explicitChildNodes: true,
      child: content,
    );
  }
}

class _NoticeBody extends StatelessWidget {
  const _NoticeBody({required this.notice, required this.payMode});
  final NearIntentsServiceNoticeData notice;
  final bool payMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chains = {for (final issue in notice.issues) ...issue.chains}.toList()
      ..sort();
    final networks = _networkNames(chains);
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
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );
    return SingleChildScrollView(
      key: const ValueKey('near_intents_service_notice_body'),
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice.maintenanceOnly) ...[
            Text('NEAR Intents is under maintenance.', style: bodyStyle),
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
                'Maintenance window: ${_networkNames(window.chains)}',
                style: bodyStyle,
              )
            else if (windows.length > 1)
              Text(_networkNames(window.chains), style: bodyStyle),
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
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      Text(
                        notice.maintenanceOnly
                            ? 'List of maintenance'
                            : 'Affected networks',
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineSmall.copyWith(
                          color: _warningOrange,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        networks,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
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
    );
  }
}

class _NoticeActions extends StatelessWidget {
  const _NoticeActions({required this.onClose, required this.onDetails});
  final VoidCallback onClose;
  final Future<void> Function() onDetails;

  @override
  Widget build(BuildContext context) {
    final size = kAppFormFactor == AppFormFactor.mobile
        ? AppButtonSize.large
        : AppButtonSize.mediumLarge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: const ValueKey('near_intents_service_notice_details'),
          variant: AppButtonVariant.ghost,
          size: size,
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
          size: size,
          expand: true,
          growWithContent: true,
          onPressed: onClose,
          child: const Text('Ok'),
        ),
      ],
    );
  }
}

String _networkNames(Iterable<String> chains) => chains.contains('*')
    ? 'All chains'
    : chains.map(swapChainDisplayName).join(', ');

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
