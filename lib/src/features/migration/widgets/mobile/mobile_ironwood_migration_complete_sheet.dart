import 'package:flutter/widgets.dart';

import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';

const _completionBadgeSize = 125.0;
const _completionTitleStyle = TextStyle(
  fontFamily: 'Young Serif',
  fontWeight: FontWeight.w400,
  fontSize: 45,
  height: 48 / 45,
  letterSpacing: -1.35,
  fontFeatures: [FontFeature.enable('case')],
);
const _completionLabelStyle = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);
const _completionBodyStyle = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 14,
  height: 21 / 14,
  letterSpacing: -0.21,
);

class MobileIronwoodMigrationCompleteSheet extends StatelessWidget {
  const MobileIronwoodMigrationCompleteSheet({
    required this.transferredZatoshi,
    required this.onDone,
    super.key,
  });

  final BigInt transferredZatoshi;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.base,
              ),
              child: Column(
                key: const ValueKey('mobile_ironwood_migration_complete_sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: Image(
                      image: AssetImage(
                        'assets/illustrations/'
                        'ironwood_migration_complete_badge.png',
                      ),
                      width: 124,
                      height: _completionBadgeSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    'Transferred: ${formatZecAmount(transferredZatoshi)} ZEC',
                    key: const ValueKey(
                      'mobile_ironwood_migration_complete_amount',
                    ),
                    textAlign: TextAlign.center,
                    style: _completionLabelStyle.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Your funds now\nin Ironwood',
                    textAlign: TextAlign.center,
                    style: _completionTitleStyle.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Ironwood is the latest Zcash shielded pool. '
                    'It’s the first formally verified pool with '
                    'cutting edge cryptography.',
                    textAlign: TextAlign.center,
                    style: _completionBodyStyle.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  AppButton(
                    key: const ValueKey(
                      'mobile_ironwood_migration_complete_done',
                    ),
                    expand: true,
                    constrainContent: true,
                    height: 44,
                    onPressed: onDone,
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
