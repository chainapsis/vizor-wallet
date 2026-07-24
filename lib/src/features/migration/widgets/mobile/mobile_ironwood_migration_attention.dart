import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/primitives.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';

enum MobileIronwoodMigrationAttentionKind {
  signature,
  continueMigration,
  proof,
  lateBroadcast,
}

class MobileIronwoodMigrationAttentionSheetBody extends StatelessWidget {
  const MobileIronwoodMigrationAttentionSheetBody({
    required this.kind,
    required this.count,
    required this.onOpenMigration,
    required this.onLater,
    super.key,
  });

  final MobileIronwoodMigrationAttentionKind kind;
  final int count;
  final VoidCallback onOpenMigration;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = switch (kind) {
      MobileIronwoodMigrationAttentionKind.signature =>
        count == 1
            ? '1 note is ready for your signature'
            : '$count notes are ready for your signature',
      MobileIronwoodMigrationAttentionKind.continueMigration =>
        'Continue your migration',
      MobileIronwoodMigrationAttentionKind.proof =>
        'Your next migration batch is ready',
      MobileIronwoodMigrationAttentionKind.lateBroadcast =>
        'A migration transaction needs attention',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.s,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppIcon(AppIcons.checkCircle, size: 48, color: colors.icon.success),
          const SizedBox(height: AppSpacing.s),
          Text(
            title,
            textAlign: TextAlign.center,
            style: appSerifDisplayStyle(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.base),
          AppButton(
            expand: true,
            height: 50,
            onPressed: onOpenMigration,
            child: const Text('Go to migration page'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            expand: true,
            height: 50,
            variant: AppButtonVariant.ghost,
            onPressed: onLater,
            child: const Text('I’ll visit later'),
          ),
        ],
      ),
    );
  }
}

class MobileIronwoodMigrationBanner extends StatefulWidget {
  const MobileIronwoodMigrationBanner({
    required this.inProgress,
    required this.attentionKind,
    required this.actionNeededCount,
    required this.remainingText,
    required this.onTap,
    super.key,
  });

  final bool inProgress;
  final MobileIronwoodMigrationAttentionKind? attentionKind;
  final int actionNeededCount;
  final String? remainingText;
  final VoidCallback onTap;

  bool get actionNeeded => attentionKind != null;

  @override
  State<MobileIronwoodMigrationBanner> createState() =>
      _MobileIronwoodMigrationBannerState();
}

class _MobileIronwoodMigrationBannerState
    extends State<MobileIronwoodMigrationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MobileIronwoodMigrationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inProgress != widget.inProgress ||
        oldWidget.attentionKind != widget.attentionKind ||
        oldWidget.actionNeededCount != widget.actionNeededCount) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final animate =
        !widget.inProgress &&
        !widget.actionNeeded &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = widget.actionNeeded
        ? switch (widget.attentionKind!) {
            MobileIronwoodMigrationAttentionKind.signature =>
              widget.actionNeededCount == 1
                  ? '1 note is ready for signing'
                  : '${widget.actionNeededCount} notes are ready for signing',
            MobileIronwoodMigrationAttentionKind.continueMigration =>
              'Continue your migration',
            MobileIronwoodMigrationAttentionKind.proof =>
              'Next migration batch is ready',
            MobileIronwoodMigrationAttentionKind.lateBroadcast =>
              'Migration needs attention',
          }
        : widget.inProgress
        ? widget.remainingText == null
              ? 'Migration in progress'
              : '${widget.remainingText} ZEC still migrating'
        : 'Migrate to Ironwood';
    final contentColor = colors.text.homeCard;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey('mobile_home_ironwood_migration_banner'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.actionNeeded
                ? const Color(0xFF00A460)
                : colors.background.homeCard,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!widget.actionNeeded)
                Positioned.fill(
                  child: ShaderMask(
                    key: const ValueKey(
                      'mobile_home_ironwood_migration_banner_image_mask',
                    ),
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0x0DFFFFFF), Color(0x8CFFFFFF)],
                    ).createShader(bounds),
                    child: Image.asset(
                      'assets/illustrations/'
                      'ironwood_migration_home_card_background.png',
                      key: const ValueKey(
                        'mobile_home_ironwood_migration_banner_background',
                      ),
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (!widget.actionNeeded) ...[
                      if (widget.inProgress)
                        AppIcon(
                          AppIcons.loader,
                          key: const ValueKey(
                            'mobile_home_ironwood_migration_loader',
                          ),
                          size: 20,
                          color: contentColor,
                        )
                      else
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) {
                            final timeline = _controller.value;
                            final rippleProgress = timeline <= 0.1
                                ? 0.0
                                : timeline >= 0.7
                                ? 1.0
                                : Curves.easeInOut.transform(
                                    (timeline - 0.1) / 0.6,
                                  );
                            final rippleSize = lerpDouble(
                              8,
                              56,
                              rippleProgress,
                            )!;
                            return SizedBox(
                              key: const ValueKey(
                                'mobile_home_ironwood_migration_blink',
                              ),
                              width: 16,
                              height: 16,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: (16 - rippleSize) / 2,
                                    top: (16 - rippleSize) / 2,
                                    child: Opacity(
                                      key: const ValueKey(
                                        'mobile_home_ironwood_migration_blink_ripple',
                                      ),
                                      opacity: 1 - rippleProgress,
                                      child: SizedBox(
                                        width: rippleSize,
                                        height: rippleSize,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: GreenPrimitives.p200Dark,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Positioned(
                                    left: 3,
                                    top: 3,
                                    width: 10,
                                    height: 10,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: RadialGradient(
                                          colors: [
                                            GreenPrimitives.p200Light,
                                            GreenPrimitives.p300Dark,
                                          ],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: GreenPrimitives.p300Dark,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      SizedBox(
                        width: widget.inProgress
                            ? AppSpacing.xxs
                            : AppSpacing.sm,
                      ),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: contentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppIcon(
                      AppIcons.chevronForward,
                      size: 20,
                      color: contentColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
