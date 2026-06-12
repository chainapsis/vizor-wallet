import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

class AddressTypesScreen extends StatelessWidget {
  const AddressTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: OnboardingStep.intro.label,
        routePath: OnboardingStep.intro.routePath,
      ),
      bodyPadding: EdgeInsets.zero,
      child: const _HeroLayout(),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout();

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Column(
                  children: [
                    Expanded(child: _OnPageContent()),
                    _ButtonStack(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnPageContent extends StatelessWidget {
  const _OnPageContent();

  static const double _sectionGap = 32;

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TitleBlock(),
        SizedBox(height: _sectionGap),
        _AddressTypesPanel(),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Zcash Address Types',
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Zcash has two addresses types.\n'
          'One for Privacy, one for Transparency.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AddressTypesPanel extends StatelessWidget {
  const _AddressTypesPanel();

  static const _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final fill = isDark ? colors.background.base : colors.background.ground;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: const Column(
        children: [
          _AddressTypeSection(kind: _AddressTypeKind.shielded),
          SizedBox(height: AppSpacing.md),
          _Divider(),
          SizedBox(height: AppSpacing.md),
          _AddressTypeSection(kind: _AddressTypeKind.transparent),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.border.regular,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: const SizedBox(height: 1, width: double.infinity),
    );
  }
}

enum _AddressTypeKind { shielded, transparent }

class _AddressTypeSection extends StatelessWidget {
  const _AddressTypeSection({required this.kind});

  final _AddressTypeKind kind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AddressTypeHeader(kind: kind),
          const SizedBox(height: AppSpacing.sm),
          _AddressTypeDescription(kind: kind),
        ],
      ),
    );
  }
}

class _AddressTypeHeader extends StatelessWidget {
  const _AddressTypeHeader({required this.kind});

  final _AddressTypeKind kind;

  bool get _isShielded => kind == _AddressTypeKind.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                _isShielded
                    ? AppIcons.shieldKeyholeOutline
                    : AppIcons.transparentBalance,
                size: 24,
                color: colors.icon.brandCrimson,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  _isShielded ? 'Shielded Address' : 'Transparent Address',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _AddressChip(kind: kind),
      ],
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({required this.kind});

  final _AddressTypeKind kind;

  bool get _isShielded => kind == _AddressTypeKind.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final background = _isShielded
        ? colors.background.inverse
        : isDark
        ? colors.background.overlay
        : colors.background.raised;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AddressBadge(kind: kind),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            _isShielded ? 'vtr42...3F5wF' : 'vt5r2...3F8wF',
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: AppTypography.codeMedium.copyWith(
              color: _isShielded ? colors.text.inverse : colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBadge extends StatelessWidget {
  const _AddressBadge({required this.kind});

  final _AddressTypeKind kind;

  bool get _isShielded => kind == _AddressTypeKind.shielded;

  static const _shieldedFill = Color(0xFFC2546A);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 21,
      height: 21,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _isShielded ? _shieldedFill : colors.background.inverse,
        borderRadius: BorderRadius.circular(AppSpacing.xxs),
      ),
      child: Text(
        _isShielded ? 'u1' : 't',
        style: AppTypography.codeMedium.copyWith(
          color: _isShielded ? colors.text.homeCard : colors.text.inverse,
        ),
      ),
    );
  }
}

class _AddressTypeDescription extends StatelessWidget {
  const _AddressTypeDescription({required this.kind});

  final _AddressTypeKind kind;

  bool get _isShielded => kind == _AddressTypeKind.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    final emphasisStyle = AppTypography.bodyMediumStrong.copyWith(
      color: colors.text.accent,
    );

    if (_isShielded) {
      return Text.rich(
        TextSpan(
          style: bodyStyle,
          children: [
            const TextSpan(text: 'Address starts with '),
            TextSpan(text: 'u1', style: emphasisStyle),
            const TextSpan(text: ' (or '),
            TextSpan(text: 'zs', style: emphasisStyle),
            const TextSpan(
              text:
                  ' for legacy). Only you can see your account balance and transaction history.',
            ),
          ],
        ),
      );
    }

    return Text(
      "Address starts with t, similar to Bitcoin, your address' balance "
      'and transaction history are publicly visible.',
      style: bodyStyle,
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack();

  static const double _buttonMinWidth = 196;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => context.go(OnboardingStep.thingsToKnow.routePath),
      variant: AppButtonVariant.primary,
      minWidth: _buttonMinWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: const Text('Tell me how Zcash works'),
    );
  }
}
