import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';

class SwapNearIntentsAttribution extends StatelessWidget {
  const SwapNearIntentsAttribution({this.alignEnd = false, super.key});

  /// Right-aligns the narrower "Powered by" line under the wordmark so the
  /// lockup reads as one right-flush unit. Mobile anchors the lockup to the
  /// top-right of the nav (Figma 4686:102067) and sets this true; desktop
  /// anchors it bottom-left and keeps the default left-aligned stack.
  final bool alignEnd;

  static const _poweredByAsset = 'assets/icons/near_intents_powered_by.svg';
  static const _wordmarkAsset = 'assets/icons/near_intents_wordmark.svg';

  @override
  Widget build(BuildContext context) {
    final color = context.colors.background.overlay;
    final colorFilter = ColorFilter.mode(color, BlendMode.srcIn);

    return IgnorePointer(
      child: Column(
        key: const ValueKey('swap_near_intents_attribution'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            _poweredByAsset,
            key: const ValueKey('swap_near_intents_powered_by'),
            width: 64.296,
            height: 10.32,
            colorFilter: colorFilter,
            semanticsLabel: 'Powered by',
          ),
          const SizedBox(height: 6.2),
          SvgPicture.asset(
            _wordmarkAsset,
            key: const ValueKey('swap_near_intents_wordmark'),
            width: 90,
            height: 11,
            colorFilter: colorFilter,
            semanticsLabel: 'nearIntents',
          ),
        ],
      ),
    );
  }
}
