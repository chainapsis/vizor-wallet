import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/enhance_pir_provider.dart';

/// Offers to finish turning private queries off when the wallet's
/// transparent lookups are still private: an opt-out did not finish, or a
/// build with private transparent recovery made the wallet private.
///
/// Shown whether or not the private service is available on this network or
/// build, so the private queries toggle being hidden never strands a wallet
/// in private transparent lookups. Renders nothing otherwise.
class TransparentOptOutAction extends ConsumerWidget {
  const TransparentOptOutAction({
    this.keyPrefix = 'settings',
    this.showTransition = true,
    super.key,
  });

  /// Prefix of the widget keys, so each form factor keeps its own.
  final String keyPrefix;

  /// Whether to show the toggle's transition feedback here, where no toggle
  /// shows it.
  final bool showTransition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(transparentOptOutActionProvider)) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final transition = ref.watch(enhancePirTransitionProvider);
    final changing = transition == kEnhancePirChangingMessage;
    return Padding(
      key: ValueKey('${keyPrefix}_transparent_opt_out'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Transparent lookups are still private. Finish turning private '
            'queries off to use public transparent lookups again.',
            key: ValueKey('${keyPrefix}_transparent_opt_out_description'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (showTransition && transition != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              transition,
              key: ValueKey('${keyPrefix}_transparent_opt_out_transition'),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              key: ValueKey('${keyPrefix}_transparent_opt_out_button'),
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: changing
                  ? null
                  : () => unawaited(
                      ref
                          .read(enhancePirProvider.notifier)
                          .finishTransparentOptOut(),
                    ),
              child: const Text('Finish turning off'),
            ),
          ),
        ],
      ),
    );
  }
}
