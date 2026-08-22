import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/account_provider.dart';
import '../../../../services/qr_scanner.dart';
import '../../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../voting_polls_screen.dart';
import '../voting_proposal_detail_screen.dart';
import '../voting_results_screen.dart';
import '../voting_review_screen.dart';
import '../voting_status_screen.dart';
import '../voting_submission_confirmation_screen.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../../widgets/mobile/mobile_voting_config_settings_sheet.dart';

class MobileVotingPollsScreen extends StatelessWidget {
  const MobileVotingPollsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Coinholder voting',
      fallbackPath: '/home',
      trailing: _MobileVotingSettingsButton(
        onTap: () => showMobileVotingConfigSettingsSheet(context),
      ),
      child: const VotingPollsView(showDesktopChrome: false),
    );
  }
}

class MobileVotingProposalDetailScreen extends StatelessWidget {
  const MobileVotingProposalDetailScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Coinholder voting',
      child: VotingProposalDetailView(
        roundId: roundId,
        showDesktopToolbar: false,
      ),
    );
  }
}

class MobileVotingReviewScreen extends StatelessWidget {
  const MobileVotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Review vote',
      child: VotingReviewView(roundId: roundId, showDesktopToolbar: false),
    );
  }
}

class MobileVotingStatusScreen extends StatelessWidget {
  const MobileVotingStatusScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Submit vote',
      horizontalPadding: AppSpacing.sm,
      child: VotingStatusView(
        roundId: roundId,
        accountUuid: accountUuid,
        requireCurrentRouteForConfirmation: true,
      ),
    );
  }
}

class MobileVotingSubmissionConfirmationScreen extends StatelessWidget {
  const MobileVotingSubmissionConfirmationScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Vote submitted',
      child: VotingSubmissionConfirmationView(
        roundId: roundId,
        accountUuid: accountUuid,
        showDesktopToolbar: false,
      ),
    );
  }
}

class MobileVotingResultsScreen extends StatelessWidget {
  const MobileVotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Voting results',
      horizontalPadding: AppSpacing.sm,
      child: VotingResultsView(roundId: roundId, showDesktopToolbar: false),
    );
  }
}

class MobileKeystoneVotingScanScreen extends StatelessWidget {
  const MobileKeystoneVotingScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _MobileVotingScaffold(
      title: 'Scan signature',
      child: _MobileKeystoneVotingScanView(),
    );
  }
}

class _MobileKeystoneVotingScanView extends ConsumerStatefulWidget {
  const _MobileKeystoneVotingScanView();

  @override
  ConsumerState<_MobileKeystoneVotingScanView> createState() =>
      _MobileKeystoneVotingScanViewState();
}

class _MobileKeystoneVotingScanViewState
    extends ConsumerState<_MobileKeystoneVotingScanView> {
  bool _decoding = false;
  String? _error;

  void _handleScanComplete(ScanResult result) {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
    });
    context.pop(result.data);
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed voting QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.s,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scan voting signature',
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Hold the Keystone QR code steady in front of your camera',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.base),
            KeystoneQrScannerCard(
              expectedUrType: 'zcash-batch-sig-result',
              decoding: _decoding,
              error: _error,
              onProgress: (progress) {
                if (!mounted) return;
                setState(() {
                  if (progress > 0) _error = null;
                });
              },
              onDecodeError: _handleDecodeError,
              onComplete: _handleScanComplete,
              decodingLabel: 'Reading signature...',
              unavailableMessage:
                  'Keystone voting uses camera QR scanning only. Connect a camera and try again.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Account loading/error boundary for the mobile voting route tree. The
/// desktop guard remains desktop-only; both consume the same account state.
class MobileVotingAccountGuard extends ConsumerWidget {
  const MobileVotingAccountGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(accountProvider)
        .when(
          loading: () => const _MobileVotingScaffold(
            title: 'Coinholder voting',
            fallbackPath: '/home',
            child: VotingPaneLoading(),
          ),
          error: (error, _) => _MobileVotingScaffold(
            title: 'Coinholder voting',
            fallbackPath: '/home',
            horizontalPadding: AppSpacing.sm,
            child: Center(
              child: Text(
                "Couldn't load account.\n$error",
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ),
          data: (_) => child,
        );
  }
}

class _MobileVotingScaffold extends StatelessWidget {
  const _MobileVotingScaffold({
    required this.title,
    required this.child,
    this.fallbackPath = '/voting',
    this.horizontalPadding = 0,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String fallbackPath;
  final double horizontalPadding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final body = horizontalPadding == 0
        ? child
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: child,
          );
    return Material(
      color: context.colors.background.window,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileTopNav.back(
              title: title,
              trailing: trailing,
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(fallbackPath);
                }
              },
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _MobileVotingSettingsButton extends StatelessWidget {
  const _MobileVotingSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Voting config settings',
      button: true,
      child: GestureDetector(
        key: const ValueKey('mobile_voting_settings_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: AppIcon(
              AppIcons.cog,
              size: 22,
              color: context.colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}
