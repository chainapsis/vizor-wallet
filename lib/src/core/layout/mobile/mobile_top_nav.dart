import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';

/// Height of [MobileTopNav] — Figma `Mobile Top Nav` (node 4237:92733).
const double kMobileTopNavHeight = 72;

/// Mobile top navigation bar with the three Figma variants:
///
/// - [MobileTopNav.account] — avatar + account name (+ optional balance)
///   on the left, sync status label + edge glow indicator on the right.
///   Used by the tab roots.
/// - [MobileTopNav.steps] — back button + centered progress track. Used
///   by multi-step flows (onboarding, send wizard).
/// - [MobileTopNav.back] — back button + centered serif title. Used by
///   pushed detail screens; with a null [onBack] the button is omitted
///   and only the centered title remains (tab roots like Activity).
///
/// Metrics come from Figma node 4237:92733 (393×72; not tokenized as
/// variables yet, so they live here as constants). The Back-variant
/// title uses [AppTypography.headlineMedium] per the Fonts token sheet —
/// the Figma component instance shows "Young Serif", which is design
/// drift from the token collection, and tokens win.
class MobileTopNav extends StatelessWidget {
  const MobileTopNav.account({
    required this.accountName,
    this.balanceLabel,
    this.syncLabel,
    this.avatar,
    this.onAccountTap,
    super.key,
  }) : _variant = _MobileTopNavVariant.account,
       title = '',
       progress = 0,
       onBack = null;

  const MobileTopNav.steps({required this.progress, this.onBack, super.key})
    : _variant = _MobileTopNavVariant.steps,
      accountName = '',
      balanceLabel = null,
      syncLabel = null,
      avatar = null,
      onAccountTap = null,
      title = '';

  const MobileTopNav.back({required this.title, this.onBack, super.key})
    : _variant = _MobileTopNavVariant.back,
      accountName = '',
      balanceLabel = null,
      syncLabel = null,
      avatar = null,
      onAccountTap = null,
      progress = 0;

  final _MobileTopNavVariant _variant;

  /// Account variant: display name, optional secondary balance line, and
  /// the right-aligned sync status label.
  final String accountName;
  final String? balanceLabel;
  final String? syncLabel;

  /// Account variant: leading 40×40 avatar. Falls back to a plain
  /// surface circle until real profile pictures are wired in.
  final Widget? avatar;
  final VoidCallback? onAccountTap;

  /// Steps variant: progress through the flow, 0.0–1.0.
  final double progress;

  /// Back variant: centered serif title.
  final String title;

  final VoidCallback? onBack;

  static const _avatarSize = 40.0;
  static const _backButtonSize = 44.0;
  static const _progressTrackWidth = 196.0;
  static const _progressTrackHeight = 6.0;
  static const _syncIndicatorSize = Size(6, 50);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMobileTopNavHeight,
      child: switch (_variant) {
        _MobileTopNavVariant.account => _buildAccount(context),
        _MobileTopNavVariant.steps => _buildSteps(context),
        _MobileTopNavVariant.back => _buildBack(context),
      },
    );
  }

  Widget _buildAccount(BuildContext context) {
    final colors = context.colors;
    final account = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAccountTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar ?? _AvatarPlaceholder(size: _avatarSize),
          const SizedBox(width: AppSpacing.s),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accountName,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.text.accent,
                ),
              ),
              if (balanceLabel != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  balanceLabel!,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Row(
      children: [
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: account),
        ),
        if (syncLabel != null) ...[
          Text(
            syncLabel!,
            style: AppTypography.labelMedium.copyWith(color: colors.sync.text),
          ),
          const SizedBox(width: AppSpacing.s),
          _SyncEdgeIndicator(size: _syncIndicatorSize, color: colors.sync.glow),
        ] else
          const SizedBox(width: AppSpacing.sm),
      ],
    );
  }

  Widget _buildSteps(BuildContext context) {
    final colors = context.colors;
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: SizedBox(
            width: _progressTrackWidth,
            height: _progressTrackHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.overlay,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background.inverse,
                      borderRadius: BorderRadius.circular(AppRadii.full),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.s,
          child: _BackButton(size: _backButtonSize, onTap: onBack),
        ),
      ],
    );
  }

  Widget _buildBack(BuildContext context) {
    final colors = context.colors;
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: Padding(
            // Keep the centered title clear of the back button on both
            // sides so it stays optically centered.
            padding: const EdgeInsets.symmetric(
              horizontal: _backButtonSize + AppSpacing.s,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.headlineMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ),
        if (onBack != null)
          Positioned(
            left: AppSpacing.s,
            child: _BackButton(size: _backButtonSize, onTap: onBack),
          ),
      ],
    );
  }
}

enum _MobileTopNavVariant { account, steps, back }

class _BackButton extends StatelessWidget {
  const _BackButton({required this.size, this.onTap});

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Back',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AppIcon(
              AppIcons.chevronBackward,
              size: 24,
              color: context.colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.background.overlay,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// The thin glow bar hugging the right screen edge in the account
/// variant — Figma `_Nav Sync Widget > light` (node 4237:92744).
class _SyncEdgeIndicator extends StatelessWidget {
  const _SyncEdgeIndicator({required this.size, required this.color});

  final Size size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(size.width / 2),
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 12),
        ],
      ),
    );
  }
}
