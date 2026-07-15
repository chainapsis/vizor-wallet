import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Colors, CircularProgressIndicator, Divider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/network_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/primitives.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../providers/ironwood_migration_announcement_provider.dart';

enum IronwoodMigrationFlowStep { intro, howItWorks, options }

class IronwoodMigrationFlowData {
  const IronwoodMigrationFlowData({
    required this.amountZatoshi,
    required this.accountName,
    required this.profilePictureId,
  });

  final BigInt amountZatoshi;
  final String accountName;
  final String profilePictureId;

  String get amountText =>
      ZecAmount.fromZatoshi(amountZatoshi).balance.amountText;
}

final ironwoodMigrationFlowDataProvider =
    FutureProvider.autoDispose<IronwoodMigrationFlowData?>((ref) async {
      final cta = await ref.watch(ironwoodHomeMigrationCtaProvider.future);
      if (!cta.visible) return null;

      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      if (inputs.accountUuid == null || !inputs.hasAccountScopedData) {
        return null;
      }

      final targetTotal = _sumTargetValues(cta.status);
      final amount = targetTotal > BigInt.zero
          ? targetTotal
          : inputs.orchardBalance + inputs.orchardPendingBalance;
      if (amount <= BigInt.zero) return null;

      return IronwoodMigrationFlowData(
        amountZatoshi: amount,
        accountName: inputs.accountName,
        profilePictureId: inputs.profilePictureId,
      );
    });

BigInt _sumTargetValues(rust_sync.MigrationStatus? status) {
  if (status == null) return BigInt.zero;
  BigInt total = BigInt.zero;
  for (final value in status.targetValuesZatoshi) {
    total += value;
  }
  return total;
}

class IronwoodMigrationFlowScreen extends ConsumerWidget {
  const IronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.onOpenReleaseNotesOverride,
    super.key,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData? previewData;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewData;
    if (preview != null) {
      return _IronwoodMigrationShell(
        step: step,
        data: preview,
        onOpenReleaseNotesOverride: onOpenReleaseNotesOverride,
      );
    }

    final dataAsync = ref.watch(ironwoodMigrationFlowDataProvider);
    return dataAsync.when(
      skipLoadingOnReload: true,
      loading: () => _IronwoodMigrationLoadingShell(step: step),
      error: (_, _) => const _RedirectHome(),
      data: (data) {
        if (data == null) return const _RedirectHome();
        return _IronwoodMigrationShell(
          step: step,
          data: data,
          onOpenReleaseNotesOverride: onOpenReleaseNotesOverride,
        );
      },
    );
  }
}

class _RedirectHome extends StatefulWidget {
  const _RedirectHome();

  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IronwoodMigrationLoadingShell extends StatelessWidget {
  const _IronwoodMigrationLoadingShell({required this.step});

  final IronwoodMigrationFlowStep step;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _IronwoodMigrationShell extends StatelessWidget {
  const _IronwoodMigrationShell({
    required this.step,
    required this.data,
    this.onOpenReleaseNotesOverride,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData data;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context) {
    final content = switch (step) {
      IronwoodMigrationFlowStep.intro => _IronwoodMigrationIntroContent(
        data: data,
        onOpenReleaseNotes: () =>
            _openReleaseNotes(context, override: onOpenReleaseNotesOverride),
      ),
      IronwoodMigrationFlowStep.howItWorks =>
        _IronwoodMigrationHowItWorksContent(data: data),
      IronwoodMigrationFlowStep.options => _IronwoodMigrationOptionsContent(
        data: data,
      ),
    };

    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: content,
    );
  }
}

Future<void> _openReleaseNotes(
  BuildContext context, {
  VoidCallback? override,
}) async {
  if (override != null) {
    override();
    return;
  }
  final uri = Uri.parse(kIronwoodMigrationReleaseNotesUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget _toolbarFor(BuildContext context, IronwoodMigrationFlowStep step) {
  return AppPaneToolbar(
    leading: AppBackLink(
      label: switch (step) {
        IronwoodMigrationFlowStep.intro => 'Home',
        IronwoodMigrationFlowStep.howItWorks => 'Ironwood Pool',
        IronwoodMigrationFlowStep.options => 'How Migration Works',
      },
      onTap: () {
        switch (step) {
          case IronwoodMigrationFlowStep.intro:
            context.go('/home');
          case IronwoodMigrationFlowStep.howItWorks:
            context.go('/migration');
          case IronwoodMigrationFlowStep.options:
            context.go('/migration/how-it-works');
        }
      },
    ),
  );
}

class _IronwoodMigrationFrame extends StatelessWidget {
  const _IronwoodMigrationFrame({
    required this.toolbar,
    required this.child,
    required this.disableSidebarActions,
  });

  final Widget toolbar;
  final Widget child;
  final bool disableSidebarActions;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: AppMainSidebar(
        disabledRoutePaths: disableSidebarActions
            ? const {'/swap', '/voting'}
            : const {},
      ),
      pane: AppPaneScrollScaffold(
        toolbar: toolbar,
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
  }
}

class _IronwoodMigrationIntroContent extends StatelessWidget {
  const _IronwoodMigrationIntroContent({
    required this.data,
    required this.onOpenReleaseNotes,
  });

  final IronwoodMigrationFlowData data;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = data.amountText;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 16,
            width: 420,
            height: 200,
            child: _PoolMigrationHero(data: data),
          ),
          Positioned(
            left: 0,
            top: 250,
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _DarkBadge(label: 'Zcash Network Update'),
                const SizedBox(height: 24),
                SvgPicture.asset(
                  'assets/illustrations/ironwood_wordmark.svg',
                  width: 290,
                  height: 39,
                  colorFilter: ColorFilter.mode(
                    colors.text.accent,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 352,
                  child: Text(
                    'Ironwood is the latest Zcash shielded pool. '
                    "It's the first formally verified pool with cutting "
                    'edge cryptography.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 328,
                  child: Text(
                    'There will be a one-time mandatory upgrade from '
                    'the legacy (orchard) shielded pool. You need to '
                    'transition your $amount ZEC from the old Orchard pool '
                    'into the new Ironwood pool.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: _FlowButtons(
              primaryLabel: 'How the Migration works',
              onPrimary: () => context.go('/migration/how-it-works'),
              secondaryLabel: 'Official Release Note',
              onSecondary: onOpenReleaseNotes,
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationHowItWorksContent extends StatelessWidget {
  const _IronwoodMigrationHowItWorksContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = data.amountText;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 24,
            width: 396,
            child: Text(
              'How Migration Works',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 81.5,
            width: 396,
            height: 386,
            child: _ProcessCard(
              steps: [
                _ProcessStepData(
                  icon: _ProcessIconKind.split,
                  title: 'Split funds',
                  body:
                      'Your $amount ZEC balance is divided into several '
                      'smaller common notes (10/1/0.1 ZEC). Splitting the '
                      'balance into smaller batches mixes your transactions '
                      'with other users maximizing privacy.',
                ),
                const _ProcessStepData(
                  icon: _ProcessIconKind.schedule,
                  title: 'Schedule',
                  body:
                      'Transactions dispatch at irregular intervals instead '
                      'of all at once.',
                ),
                const _ProcessStepData(
                  icon: _ProcessIconKind.sign,
                  title: 'Sign Once',
                  body:
                      'You grant permission at the start, and the Vizor '
                      'executes the remaining steps.',
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: _FlowButtons(
              primaryLabel: 'Continue',
              onPrimary: () => context.go('/migration/options'),
              secondaryLabel: 'Go Back',
              onSecondary: () => context.go('/migration'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationOptionsContent extends StatefulWidget {
  const _IronwoodMigrationOptionsContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  State<_IronwoodMigrationOptionsContent> createState() =>
      _IronwoodMigrationOptionsContentState();
}

class _IronwoodMigrationOptionsContentState
    extends State<_IronwoodMigrationOptionsContent> {
  var _selected = _MigrationMode.private;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = widget.data.amountText;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 49,
            top: 32,
            width: 322,
            child: Column(
              children: [
                Text(
                  'Chose How to Migrate\nyour $amount ZEC',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 298,
                  child: Text(
                    'Whichever option you choose, your funds will be '
                    'safely deposited into the Ironwood pool.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 180.5,
            width: 396,
            child: Column(
              children: [
                _MigrationOptionCard(
                  mode: _MigrationMode.private,
                  selected: _selected == _MigrationMode.private,
                  title: 'Private Migration',
                  badge: 'Recommended',
                  body:
                      'Sends independent parts over time windows.\n'
                      'Slower, harder to correlate.',
                  onTap: () =>
                      setState(() => _selected = _MigrationMode.private),
                ),
                const SizedBox(height: 12),
                _MigrationOptionCard(
                  mode: _MigrationMode.fast,
                  selected: _selected == _MigrationMode.fast,
                  title: 'Fast Migration',
                  body:
                      'Sends now in one step. Amount and\n'
                      'timing are easier to associate.',
                  onTap: () => setState(() => _selected = _MigrationMode.fast),
                ),
              ],
            ),
          ),
          Positioned(
            left: 51,
            top: 457,
            width: 318,
            child: Text(
              'Plain-language comparison: speed vs. correlation\n'
              'exposure. No anchors, cohorts, PCZTs, or action counts\n'
              'here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              onPressed: () {},
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text('Select & Review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowButtons extends StatelessWidget {
  const _FlowButtons({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          onPressed: onPrimary,
          height: 44,
          minWidth: 230,
          expand: true,
          constrainContent: true,
          trailing: const AppIcon(AppIcons.chevronForward, size: 20),
          child: Text(
            primaryLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 20),
        AppButton(
          onPressed: onSecondary,
          variant: AppButtonVariant.ghost,
          height: 36,
          minWidth: 230,
          expand: true,
          constrainContent: true,
          child: Text(
            secondaryLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DarkBadge extends StatelessWidget {
  const _DarkBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.colors.background.inverse,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: context.colors.text.inverse,
          ),
        ),
      ),
    );
  }
}

class _PoolMigrationHero extends StatelessWidget {
  const _PoolMigrationHero({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = '${data.amountText} $kZcashDefaultCurrencyTicker';

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _PoolMigrationHeroPainter()),
          Positioned(
            left: 24,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            right: 27,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            left: 24,
            top: 116,
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '(Legacy)',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Orchard Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  amount,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 159,
            top: 95,
            width: 100,
            height: 30,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: GreenPrimitives.p500Light,
                shape: const StadiumBorder(),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(
                        AppIcons.shieldKeyhole,
                        size: 16,
                        color: Color(0xFFEAFEEF),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Migration',
                        style: AppTypography.labelLarge.copyWith(
                          color: const Color(0xFFEAFEEF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 32,
            top: 136,
            width: 116,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Ironwood Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: GreenPrimitives.p500Light,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  amount,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

class _PoolMigrationHeroPainter extends CustomPainter {
  const _PoolMigrationHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()..color = Colors.white;
    canvas.drawRect(rect, basePaint);

    final greenSoft = Paint()..color = const Color(0xFFE3FBEE);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.91, size.height * 0.50),
        width: 168,
        height: 270,
      ),
      greenSoft,
    );
    final greenSofter = Paint()..color = const Color(0xFFF0FFF6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.99, size.height * 0.50),
        width: 154,
        height: 270,
      ),
      greenSofter,
    );

    final dashedPath = Path()
      ..moveTo(size.width * 0.25, -16)
      ..cubicTo(
        size.width * 0.42,
        size.height * 0.20,
        size.width * 0.42,
        size.height * 0.79,
        size.width * 0.25,
        size.height + 16,
      );
    _drawDashedPath(
      canvas,
      dashedPath,
      Paint()
        ..color = const Color(0xFFB8B8B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
      dashLength: 2.4,
      gapLength: 4.2,
    );

    final linePaint = Paint()
      ..color = const Color(0xFF9A9A9A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.355, size.height * 0.50),
      Offset(size.width * 0.655, size.height * 0.50),
      linePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.355, size.height * 0.50),
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * 0.355, size.height * 0.50),
      5,
      Paint()..color = const Color(0xFFB8B8B8),
    );
    canvas.drawCircle(
      Offset(size.width * 0.655, size.height * 0.50),
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * 0.655, size.height * 0.50),
      5,
      Paint()..color = GreenPrimitives.p500Light,
    );
  }

  @override
  bool shouldRepaint(covariant _PoolMigrationHeroPainter oldDelegate) => false;
}

void _drawDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dashLength,
  required double gapLength,
}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dashLength, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gapLength;
    }
  }
}

class _ProcessCard extends StatelessWidget {
  const _ProcessCard({required this.steps});

  final List<_ProcessStepData> steps;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              _ProcessStep(step: steps[index]),
              if (index != steps.length - 1) ...[
                const SizedBox(height: 17),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.border.subtle,
                  indent: 36,
                  endIndent: 12,
                ),
                const SizedBox(height: 17),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessStepData {
  const _ProcessStepData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final _ProcessIconKind icon;
  final String title;
  final String body;
}

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({required this.step});

  final _ProcessStepData step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CustomPaint(
            painter: _ProcessIconPainter(step.icon, GreenPrimitives.p500Light),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                step.body,
                maxLines: step.icon == _ProcessIconKind.split ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ProcessIconKind { split, schedule, sign }

class _ProcessIconPainter extends CustomPainter {
  const _ProcessIconPainter(this.kind, this.color);

  final _ProcessIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case _ProcessIconKind.split:
        canvas.drawLine(const Offset(5, 5), const Offset(5, 11), paint);
        canvas.drawLine(const Offset(5, 11), const Offset(12, 11), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 16), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(16, 7), paint);
        _arrow(canvas, const Offset(12, 16), math.pi / 2, paint);
        _arrow(canvas, const Offset(16, 7), -math.pi / 4, paint);
      case _ProcessIconKind.schedule:
        canvas.drawCircle(const Offset(10, 10), 6.5, paint);
        canvas.drawLine(const Offset(10, 10), const Offset(10, 6), paint);
        canvas.drawLine(const Offset(10, 10), const Offset(13, 12), paint);
        canvas.drawLine(const Offset(6, 2), const Offset(4, 4), paint);
        canvas.drawLine(const Offset(14, 2), const Offset(16, 4), paint);
      case _ProcessIconKind.sign:
        canvas.drawLine(const Offset(4, 15), const Offset(16, 15), paint);
        canvas.drawLine(const Offset(5, 12), const Offset(8, 6), paint);
        canvas.drawLine(const Offset(8, 6), const Offset(12, 12), paint);
        canvas.drawLine(const Offset(12, 12), const Offset(15, 5), paint);
        canvas.drawCircle(const Offset(8, 6), 1.5, paint);
    }
  }

  void _arrow(Canvas canvas, Offset tip, double angle, Paint paint) {
    const length = 3.5;
    final a = angle + math.pi * 0.75;
    final b = angle - math.pi * 0.75;
    canvas.drawLine(
      tip,
      tip + Offset(math.cos(a), math.sin(a)) * length,
      paint,
    );
    canvas.drawLine(
      tip,
      tip + Offset(math.cos(b), math.sin(b)) * length,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProcessIconPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

enum _MigrationMode { private, fast }

class _MigrationOptionCard extends StatelessWidget {
  const _MigrationOptionCard({
    required this.mode,
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
    this.badge,
  });

  final _MigrationMode mode;
  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 118,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(24),
              boxShadow: selected
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x10000000),
                        offset: Offset(0, 2),
                        blurRadius: 10,
                      ),
                    ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _OptionIcon(mode: mode, selected: selected),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                ),
                                if (badge != null) ...[
                                  const SizedBox(width: 8),
                                  _RecommendedBadge(label: badge!),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            Flexible(
                              child: Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SelectionMark(selected: selected),
                    ],
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colors.text.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionIcon extends StatelessWidget {
  const _OptionIcon({required this.mode, required this.selected});

  final _MigrationMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.text.accent
        : context.colors.icon.disabled;
    return SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(
        painter: _OptionIconPainter(mode: mode, color: color),
      ),
    );
  }
}

class _OptionIconPainter extends CustomPainter {
  const _OptionIconPainter({required this.mode, required this.color});

  final _MigrationMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (mode == _MigrationMode.private) {
      final path = Path()
        ..moveTo(8, 1.5)
        ..lineTo(14, 4)
        ..lineTo(13, 10)
        ..quadraticBezierTo(11, 14, 8, 15)
        ..quadraticBezierTo(5, 14, 3, 10)
        ..lineTo(2, 4)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawLine(const Offset(8, 6), const Offset(8, 10), paint);
      canvas.drawLine(const Offset(6, 8), const Offset(10, 8), paint);
    } else {
      canvas.drawLine(const Offset(3, 5), const Offset(11, 5), paint);
      canvas.drawLine(const Offset(8, 2), const Offset(12, 5), paint);
      canvas.drawLine(const Offset(8, 8), const Offset(12, 5), paint);
      canvas.drawLine(const Offset(5, 11), const Offset(13, 11), paint);
      canvas.drawLine(const Offset(8, 8), const Offset(5, 11), paint);
      canvas.drawLine(const Offset(8, 14), const Offset(5, 11), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OptionIconPainter oldDelegate) {
    return oldDelegate.mode != mode || oldDelegate.color != color;
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: GreenPrimitives.p500Light,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: const Color(0xFFEAFEEF),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? context.colors.background.inverse
        : context.colors.background.raised;
    return Container(
      width: 20,
      height: 20,
      decoration: ShapeDecoration(color: fill, shape: const OvalBorder()),
      child: selected
          ? const Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: Color(0xFFFFFFFF),
              ),
            )
          : null,
    );
  }
}
