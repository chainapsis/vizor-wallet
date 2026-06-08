import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../migration_copy.dart';
import '../migration_formatters.dart';
import '../models/migration_demo_state.dart';
import '../models/migration_view_state.dart';
import '../providers/migration_demo_provider.dart';
import '../widgets/migration_completion_dialog.dart';
import '../widgets/migration_signing_overlay.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  bool _signing = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _ensureTicker(bool active) {
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _startSigning() => setState(() => _signing = true);
  void _cancelSigning() => setState(() => _signing = false);

  Future<void> _completeSigning() async {
    setState(() => _signing = false);
    if (!mounted) return;
    await showMigrationCompletionDialog(context);
  }

  Future<void> _resetDemo() => ref.read(migrationDemoProvider.notifier).reset();

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    final isHardware = account?.isHardware ?? false;
    final demo = ref.watch(migrationDemoProvider).value;
    final now = DateTime.now();

    final viewState = migrationViewState(
      isHardware: isHardware,
      demo: demo,
      now: now,
    );
    _ensureTicker(viewState == MigrationViewState.inProgress);

    final Widget body = switch (viewState) {
      MigrationViewState.softwareRequired => const _SoftwareRequiredView(),
      MigrationViewState.idle => _IdleView(onStart: _startSigning),
      MigrationViewState.inProgress => _InProgressView(
        demo: demo!,
        now: now,
        onReset: _resetDemo,
      ),
      MigrationViewState.complete => _CompleteView(onDone: _resetDemo),
    };

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: body,
            ),
            if (_signing)
              MigrationSigningOverlay(
                onCancel: _cancelSigning,
                onComplete: () => unawaited(_completeSigning()),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final orchard =
        ref.watch(syncProvider).value?.orchardBalance ?? BigInt.zero;
    final amount = ZecAmount.fromZatoshi(
      orchard,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.idleTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.idleBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _PoolTransition(),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MigrationCopy.readyToMigrateLabel,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                amount,
                key: const ValueKey('migration_ready_amount'),
                style: AppTypography.displaySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                MigrationCopy.poolFlow,
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        const _Bullets(),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('migration_start_button'),
          onPressed: onStart,
          leading: const AppIcon(AppIcons.doubleArrowVertical),
          child: const Text(MigrationCopy.startCta),
        ),
      ],
    );
  }
}

class _SoftwareRequiredView extends StatelessWidget {
  const _SoftwareRequiredView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.softwareRequiredTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Text(
            MigrationCopy.softwareRequiredBody,
            key: const ValueKey('migration_software_required'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _InProgressView extends StatelessWidget {
  const _InProgressView({
    required this.demo,
    required this.now,
    required this.onReset,
  });
  final MigrationDemoState demo;
  final DateTime now;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      demo.displayAmountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final sent = demo.transfersSent(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.inProgressTitle,
          key: const ValueKey('migration_in_progress_title'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.inProgressBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MigrationCopy.migratingAmount(amount),
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  value: demo.progressFraction(now),
                  minHeight: 8,
                  backgroundColor: colors.background.neutralSubtleOpacity,
                  color: colors.icon.success,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatRemaining(demo.remaining(now))} · '
                '${formatStartedAgo(demo.sinceStart(now))}',
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Column(
            children: [
              for (var i = 0; i < demo.transferOffsetsMs.length; i++) ...[
                if (i > 0)
                  Divider(height: AppSpacing.md, color: colors.border.subtle),
                Row(
                  children: [
                    AppIcon(
                      sent[i] ? AppIcons.checkCircle : AppIcons.time,
                      size: AppIconSize.medium,
                      color: sent[i] ? colors.icon.success : colors.icon.muted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        MigrationCopy.transferLabel(
                          i + 1,
                          demo.transferOffsetsMs.length,
                        ),
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    Text(
                      sent[i]
                          ? MigrationCopy.transferSent
                          : formatTransferEta(demo.transferEta(i, now)),
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                AppIcons.warning,
                size: AppIconSize.medium,
                color: colors.icon.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  MigrationCopy.keepOpenWarning,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('migration_reset_button'),
          onPressed: onReset,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.medium,
          child: const Text(MigrationCopy.resetCta),
        ),
      ],
    );
  }
}

class _CompleteView extends StatelessWidget {
  const _CompleteView({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.doneTitle,
          key: const ValueKey('migration_done_title'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.doneBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          onPressed: onDone,
          child: const Text(MigrationCopy.doneButton),
        ),
      ],
    );
  }
}

class _PoolTransition extends StatelessWidget {
  const _PoolTransition();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.fromPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.fromPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: AppIcon(
            AppIcons.arrowForwardIos,
            size: AppIconSize.medium,
            color: colors.icon.muted,
          ),
        ),
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.toPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.toPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '›  ',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bullet(MigrationCopy.bullet1),
        bullet(MigrationCopy.bullet2),
        bullet(MigrationCopy.bullet3),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: child,
    );
  }
}
