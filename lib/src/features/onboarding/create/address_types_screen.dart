import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';

import '../../../core/navigation/onboarding_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

@visibleForTesting
bool usesMobileAddressTypesCardScroll(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) {
  if (isWeb) return false;
  return switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

bool get _usesMobileCardScroll =>
    usesMobileAddressTypesCardScroll(defaultTargetPlatform);

class AddressTypesScreen extends StatelessWidget {
  const AddressTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingTrailingPane(child: _Content());
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _BackRow(),
        SizedBox(height: AppSpacing.xs),
        Expanded(child: _HeroLayout()),
      ],
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                navigateOnboardingBack(context, OnboardingStep.intro.routePath),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.chevronBackward,
                  size: AppIconSize.medium,
                  color: colors.text.accent,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Back',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

class _HeroLayout extends StatelessWidget {
  const _HeroLayout();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: Center(child: _HeroBlock())),
        SizedBox(height: AppSpacing.md),
        _ActionRow(),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleBlock(),
        SizedBox(height: AppSpacing.lg),
        _CardsRow(),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );
    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Zcash Address Types',
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                const TextSpan(text: 'Zcash has two address types: one for '),
                TextSpan(
                  text: 'Privacy',
                  style: bodyStyle.copyWith(
                    color: colors.text.brandCrimson,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(text: ', one for '),
                TextSpan(
                  text: 'Transparency',
                  style: bodyStyle.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CardsRow extends StatelessWidget {
  const _CardsRow();

  static const _width = 588.0;

  @override
  Widget build(BuildContext context) {
    const cards = SizedBox(
      width: _width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AddressTypeCard(kind: _AddressTypeCardKind.shielded),
          SizedBox(width: AppSpacing.md),
          _AddressTypeCard(kind: _AddressTypeCardKind.transparent),
        ],
      ),
    );
    if (!_usesMobileCardScroll) return cards;
    return const SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: cards,
      ),
    );
  }
}

enum _AddressTypeCardKind { shielded, transparent }

class _AddressTypeCard extends StatelessWidget {
  const _AddressTypeCard({required this.kind});

  final _AddressTypeCardKind kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 282,
      height: 251,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AddressCardTop(kind: kind),
            const SizedBox(height: AppSpacing.sm),
            _AddressCardContent(kind: kind),
          ],
        ),
      ),
    );
  }
}

class _AddressCardTop extends StatelessWidget {
  const _AddressCardTop({required this.kind});

  final _AddressTypeCardKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded = kind == _AddressTypeCardKind.shielded;
    return Container(
      height: 96,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: isShielded ? colors.background.inverse : colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: isShielded
            ? Border.all(color: colors.border.subtleOpacity)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AppIcon(
              isShielded
                  ? AppIcons.shieldKeyholeOutline
                  : AppIcons.transparentBalance,
              size: AppIconSize.large,
              color: isShielded ? colors.icon.inverse : colors.icon.accent,
            ),
          ),
          _AddressLine(kind: kind),
        ],
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.kind});

  final _AddressTypeCardKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded = kind == _AddressTypeCardKind.shielded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AddressPrefixBadge(
          text: isShielded ? 'u1' : 't',
          shielded: isShielded,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'vtr241aaf13...jFJxxTmd3FwF',
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: AppTypography.codeMedium.copyWith(
            color: isShielded ? colors.text.inverse : colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _AddressPrefixBadge extends StatelessWidget {
  const _AddressPrefixBadge({required this.text, required this.shielded});

  static const double _radius = 4;

  final String text;
  final bool shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 21,
      height: 21,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: shielded
            ? colors.background.base
            : colors.background.neutralStrongOpacity,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Text(
        text,
        style: AppTypography.codeMedium.copyWith(color: colors.text.accent),
      ),
    );
  }
}

class _AddressCardContent extends StatelessWidget {
  const _AddressCardContent({required this.kind});

  final _AddressTypeCardKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded = kind == _AddressTypeCardKind.shielded;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isShielded ? 'Shielded Address' : 'Transparent Address',
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: isShielded ? 256 : 258,
            child: isShielded
                ? _ShieldedDescription(colors: colors)
                : Text(
                    'Address starts with t. Balance and transaction history '
                    'are publicly visible.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShieldedDescription extends StatelessWidget {
  const _ShieldedDescription({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    final emphasisStyle = bodyStyle.copyWith(
      color: colors.text.brandCrimson,
      fontWeight: FontWeight.w500,
    );
    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          const TextSpan(text: 'Address starts with '),
          TextSpan(text: 'u1', style: emphasisStyle),
          const TextSpan(text: ' (or '),
          TextSpan(text: 'zs', style: emphasisStyle),
          const TextSpan(text: ' for legacy).\n'),
          const TextSpan(
            text:
                'Only you can see your account balance and transaction history.',
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow();

  static const double _buttonWidth = 256;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => navigateOnboardingForward(
        context,
        OnboardingStep.thingsToKnow.routePath,
      ),
      variant: AppButtonVariant.primary,
      minWidth: _buttonWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: const Text('Continue'),
    );
  }
}
