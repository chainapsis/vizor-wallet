import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/liquid_metal.dart';
import '../providers/nu7_announcement_provider.dart';

/// NU7 announcement content, shown in the mobile sheet and the desktop modal.
class Nu7AnnouncementContent extends StatelessWidget {
  const Nu7AnnouncementContent({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      key: const ValueKey('nu7_announcement'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Nu7AnnouncementHeader(onClose: onClose),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'NU7 update is live.\nWhat does this mean for you?',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Nu7AnnouncementPoint(
                title: '~3× faster confirmations',
                body:
                    'Average wait for first confirmation drops from ~75s '
                    'to ~25s.',
              ),
              SizedBox(height: AppSpacing.xs),
              _Nu7AnnouncementPoint(
                title: 'Improved wallet protection',
                body:
                    'New limits on shielded activity reduce spam risk and '
                    'keep syncing lighter.',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: AppButton(
            key: const ValueKey('nu7_announcement_got_it_button'),
            variant: AppButtonVariant.secondary,
            expand: true,
            constrainContent: true,
            height: 50,
            onPressed: onClose,
            child: const Text('Got it'),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
      ],
    );
  }
}

/// Desktop card around [Nu7AnnouncementContent], styled like the mobile sheet.
class Nu7AnnouncementModal extends StatelessWidget {
  const Nu7AnnouncementModal({required this.onClose, super.key});

  static const width = 361.0;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('nu7_announcement_modal'),
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
        // Figma `Shadow Overlay`, as on the mobile sheet.
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            offset: Offset(0, 14),
            blurRadius: 28,
          ),
          BoxShadow(
            color: Color(0x08000000),
            offset: Offset(0, -6),
            blurRadius: 12,
          ),
          BoxShadow(
            color: Color(0x0F000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Nu7AnnouncementContent(onClose: onClose),
    );
  }
}

class _Nu7AnnouncementHeader extends ConsumerWidget {
  const _Nu7AnnouncementHeader({required this.onClose});

  static const _height = 210.0;

  // The logo's bounds in the Figma header.
  static const _logoTop = 61.0;
  static const _logoWidth = 241.0;
  static const _logoHeight = 99.0;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final animate = ref.watch(nu7AnnouncementMotionEnabledProvider);
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 209,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // The Figma mask: 18% (15% in dark) fading out downward.
                colors: [
                  Color(isDark ? 0x26FFFFFF : 0x2EFFFFFF),
                  const Color(0x00FFFFFF),
                ],
              ).createShader(bounds),
              child: const Image(
                image: AssetImage(
                  'assets/illustrations/nu7_announcement_background.webp',
                ),
                fit: BoxFit.fill,
              ),
            ),
          ),
          Positioned(
            top: _logoTop,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: _logoWidth,
                height: _logoHeight,
                child: LiquidMetal(
                  image: const AssetImage(
                    'assets/illustrations/nu7_liquid_metal_shape.webp',
                  ),
                  preprocessed: true,
                  colorBack: const Color(0x00000000),
                  softness: 1,
                  speed: animate ? 1 : 0,
                  scale: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Semantics(
              label: 'Close',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Container(
                  key: const ValueKey('nu7_announcement_close_button'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.button.secondary.bg,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(
                    AppIcons.cross,
                    size: 20,
                    color: colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Nu7AnnouncementPoint extends StatelessWidget {
  const _Nu7AnnouncementPoint({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: SizedBox(
              height: 16,
              child: OverflowBox(
                maxHeight: 20,
                child: AppIcon(
                  AppIcons.migrationFast,
                  size: 20,
                  color: colors.icon.brandCrimson,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                body,
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
