import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/features/swap/domain/near_intents_service_status.dart';
import '../src/features/swap/widgets/near_intents_service_notice.dart';

Widget buildCurrentServiceNoticeCapture(BuildContext context) =>
    _noticeCapture(context, upcoming: false);

Widget buildUpcomingServiceNoticeCapture(BuildContext context) =>
    _noticeCapture(context, upcoming: true);

/// The same pure cards used by the first screens, with deterministic windows.
/// Keeps visual iteration independent of API, wallet, storage and Rust state.
Widget _noticeCapture(BuildContext context, {required bool upcoming}) {
  final notice = NearIntentsServiceNoticeData(
    upcoming: upcoming,
    issues: [
      NearIntentsServiceIssue(
        chains: const {'*'},
        active: !upcoming,
        startsAt: DateTime.utc(2026, 11, 3, 12),
        finishesAt: DateTime.utc(2026, 11, 3, 14),
      ),
    ],
  );
  return ColoredBox(
    color: context.colors.background.base,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 396),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final pay in [false, true]) ...[
                NearIntentsServiceNoticeCard(
                  notice: notice,
                  payMode: pay,
                  onDetails: () async {},
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  expand: true,
                  onPressed: () {},
                  child: Text(pay ? 'Continue' : 'Review'),
                ),
                if (!pay) const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
