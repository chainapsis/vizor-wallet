import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_wrap_card.dart';

/// A full-width external lookup action inside a Swap or Pay progress card.
class SwapProgressExplorerFooter extends StatelessWidget {
  const SwapProgressExplorerFooter({required this.uri, super.key});

  final Uri uri;

  Future<void> _open() async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A platform without a browser must not interrupt status tracking.
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: AppSpacing.s),
      const ReviewWrapDivider(),
      const SizedBox(height: AppSpacing.xxs),
      AppButton(
        key: const ValueKey('swap_progress_explorer_link'),
        onPressed: () => unawaited(_open()),
        variant: AppButtonVariant.ghost,
        height: AppButtonSizing.largeHeight,
        expand: true,
        constrainContent: true,
        growWithContent: true,
        borderRadius: BorderRadius.circular(AppRadii.small),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Row(
          children: [
            const Expanded(child: Text('View on NEAR Intents')),
            const SizedBox(width: AppSpacing.xs),
            AppIcon(
              AppIcons.arrowTopRight,
              size: AppIconSize.medium,
              color: context.colors.icon.muted,
            ),
          ],
        ),
      ),
    ],
  );
}
