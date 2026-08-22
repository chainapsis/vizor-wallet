import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/voting/voting_submission_guard_provider.dart';
import '../../voting_status_flow.dart';
import '../../widgets/voting_status_widgets.dart';

/// Mobile submission status: drives the vote submission job and renders the
/// shared step checklist (including the Keystone signing panel). Leaving the
/// screen is blocked while a submission guard is active, matching the
/// desktop sidebar block — the shared [VotingStatusFlow] owns everything
/// else.
class MobileVotingStatusScreen extends ConsumerWidget {
  const MobileVotingStatusScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final activeGuards = ref.watch(votingSubmissionGuardProvider);
    final blockingGuard = activeGuards
        .where((guard) => guard.roundId == roundId)
        .firstOrNull;
    return PopScope(
      canPop: blockingGuard == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || blockingGuard == null) return;
        showAppToast(context, blockingGuard.message);
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: AppToastHost(
          child: SafeArea(
            bottom: false,
            child: VotingStatusFlow(
              roundId: roundId,
              accountUuid: accountUuid,
              confirmSkipRemainingBundles: (context) =>
                  showAppMobileSheet<bool>(
                    context: context,
                    builder: (_) => const _SkipSignedBundlesSheet(),
                  ),
              builder: (context, view) => Column(
                children: [
                  MobileTopNav.back(
                    title: 'Vote',
                    onBack: () =>
                        _handleBack(context, blocked: blockingGuard != null),
                  ),
                  Expanded(
                    child: view == null
                        ? const Center(child: CircularProgressIndicator())
                        : view.softwareAccountRequired
                        ? const VotingSoftwareAccountRequiredContent()
                        : MobileBottomSafeArea(
                            bottomPadding: AppSpacing.md,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.sm,
                                AppSpacing.s,
                                AppSpacing.sm,
                                AppSpacing.md,
                              ),
                              child: VotingStatusStepsBody(
                                view: view,
                                title: 'Submitting votes',
                                subtitle:
                                    'Keep Vizor open. Generating '
                                    'zero-knowledge proofs can take a while; '
                                    'leaving now may lose in-flight proof '
                                    'work.',
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack(BuildContext context, {required bool blocked}) {
    if (blocked) {
      showAppToast(context, kVotingSubmissionInProgressMessage);
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/voting');
  }
}

class _SkipSignedBundlesSheet extends StatelessWidget {
  const _SkipSignedBundlesSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.background.neutralSubtleOpacity,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.warning,
                    size: AppIconSize.medium,
                    color: colors.icon.regular,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Use signed bundles only?',
                  style: AppTypography.headlineSmall.copyWith(
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
            style: AppTypography.bodySmall.copyWith(color: colors.text.warning),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Skip bundles'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.ghost,
            child: const Text('Keep signing'),
          ),
        ],
      ),
    );
  }
}
