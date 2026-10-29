import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/liquid_metal.dart';
import '../providers/nu7_announcement_provider.dart';

/// NU7 announcement content, shown in the mobile sheet and the desktop modal.
class Nu7AnnouncementContent extends StatelessWidget {
  const Nu7AnnouncementContent({
    required this.onClose,
    this.compact = false,
    super.key,
  });

  final VoidCallback onClose;

  /// Desktop sizing, matching the Ironwood announcement modal.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gap = compact ? AppSpacing.sm : AppSpacing.md;
    return Column(
      key: const ValueKey('nu7_announcement'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Nu7AnnouncementHeader(onClose: onClose, compact: compact),
        SizedBox(height: gap),
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
        SizedBox(height: gap),
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
        SizedBox(height: gap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: AppButton(
            key: const ValueKey('nu7_announcement_got_it_button'),
            variant: AppButtonVariant.secondary,
            expand: true,
            constrainContent: true,
            height: compact ? 44 : 50,
            onPressed: onClose,
            child: const Text('Got it'),
          ),
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.base),
      ],
    );
  }
}

/// Desktop card around [Nu7AnnouncementContent], as wide as the Ironwood
/// announcement modal.
class Nu7AnnouncementModal extends StatelessWidget {
  const Nu7AnnouncementModal({required this.onClose, super.key});

  static const width = 312.0;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('nu7_announcement_modal'),
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
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
      child: Nu7AnnouncementContent(onClose: onClose, compact: true),
    );
  }
}

/// The desktop NU7 announcement over home. It appears without the user
/// asking, so it fades in with a slight scale unless motion is reduced.
class Nu7AnnouncementOverlay extends StatefulWidget {
  const Nu7AnnouncementOverlay({required this.onClose, super.key});

  static const entranceDuration = Duration(milliseconds: 220);

  final VoidCallback onClose;

  @override
  State<Nu7AnnouncementOverlay> createState() => _Nu7AnnouncementOverlayState();
}

class _Nu7AnnouncementOverlayState extends State<Nu7AnnouncementOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: Nu7AnnouncementOverlay.entranceDuration,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.96,
    end: 1,
  ).animate(_progress);
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _progress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppPaneModalOverlay(
              key: const ValueKey('nu7_announcement_overlay'),
              alignment: const Alignment(0, -0.08),
              onDismiss: widget.onClose,
              child: ScaleTransition(
                scale: _scale,
                child: Nu7AnnouncementModal(onClose: widget.onClose),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nu7AnnouncementHeader extends ConsumerWidget {
  const _Nu7AnnouncementHeader({required this.onClose, required this.compact});

  // The logo's bounds in the Figma header. The compact header matches the
  // Ironwood modal's 154 hero with the logo scaled to the narrower card.
  static const _logoAspect = 241 / 99;

  final VoidCallback onClose;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final animate = ref.watch(nu7AnnouncementMotionEnabledProvider);
    final logoWidth = compact ? 208.0 : 241.0;
    return SizedBox(
      height: compact ? 154 : 210,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 1,
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
              child: Image(
                image: const AssetImage(
                  'assets/illustrations/nu7_announcement_background.webp',
                ),
                fit: compact ? BoxFit.cover : BoxFit.fill,
              ),
            ),
          ),
          Positioned(
            top: compact ? 34 : 61,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: logoWidth,
                height: logoWidth / _logoAspect,
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
