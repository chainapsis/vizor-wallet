import 'package:flutter/material.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../voting_status_flow.dart';
import '../widgets/voting_pane_scroll_area.dart';
import '../widgets/voting_status_widgets.dart';

class VotingStatusScreen extends StatelessWidget {
  const VotingStatusScreen({super.key, required this.roundId, this.accountUuid});

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: VotingStatusFlow(
          roundId: roundId,
          accountUuid: accountUuid,
          confirmSkipRemainingBundles: (context) => showDialog<bool>(
            context: context,
            builder: (context) => const _SkipSignedBundlesDialog(),
          ),
          builder: (context, view) {
            if (view == null) return const VotingPaneLoading();
            return _StatusContent(view: view);
          },
        ),
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.view});

  final VotingStatusViewModel view;

  @override
  Widget build(BuildContext context) {
    if (view.softwareAccountRequired) {
      return const VotingSoftwareAccountRequiredContent();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return VotingPaneCenteredScrollView(
          maxWidth: 560,
          minHeight: minHeight,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: VotingStatusStepsBody(
            view: view,
            title: 'Submitting votes',
            subtitle:
                "Don't close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.",
          ),
        );
      },
    );
  }
}

class _SkipSignedBundlesDialog extends StatelessWidget {
  const _SkipSignedBundlesDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: colors.text.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Use signed bundles only?',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vizor can submit now using only signatures already scanned from Keystone.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Unsigned bundles are skipped, which lowers voting power for this voting round.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    variant: AppButtonVariant.secondary,
                    child: const Text('Keep signing'),
                  ),
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    variant: AppButtonVariant.primary,
                    child: const Text('Skip bundles'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
