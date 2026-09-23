import 'package:flutter/material.dart';

import '../../../../core/widgets/app_icon.dart';
import '../../../../core/theme/app_theme.dart';

/// Keeps a stable extent so changing the header never moves the ballot.
class VotingScrollHeader extends StatelessWidget {
  const VotingScrollHeader({
    super.key,
    required this.title,
    required this.compact,
    required this.navigation,
    required this.onBack,
  });

  final String title;
  final bool compact;
  final Widget? navigation;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final largeText =
        scaler.scale(16) > 22 ||
        MediaQuery.sizeOf(context).width < 260 + scaler.scale(60);
    Widget layer(bool visible, Widget child) => Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: child,
    );
    Widget backButton() => Semantics(
      label: 'Back',
      button: true,
      onTap: onBack,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onBack,
        tooltip: 'Back',
        icon: AppIcon(
          AppIcons.chevronBackward,
          size: 24,
          color: context.colors.icon.accent,
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Stack(
        alignment: Alignment.center,
        children: [
          layer(
            !compact,
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  backButton(),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style:
                          (largeText
                                  ? AppTypography.bodyLarge
                                  : AppTypography.headlineLarge)
                              .copyWith(color: context.colors.text.accent),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          layer(
            compact,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: largeText
                  ? Column(
                      children: [
                        Row(
                          children: [
                            backButton(),
                            Expanded(
                              child: Text(
                                'Voting',
                                style: AppTypography.bodyLarge.copyWith(
                                  color: context.colors.text.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (navigation != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xxs,
                            ),
                            child: navigation,
                          ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                    )
                  : Row(
                      children: [
                        backButton(),
                        Expanded(
                          child: Text(
                            'Voting',
                            style: AppTypography.bodyLarge.copyWith(
                              color: context.colors.text.accent,
                            ),
                          ),
                        ),
                        if (navigation != null)
                          SizedBox(width: 184, child: navigation),
                        const SizedBox(width: AppSpacing.xxs),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
