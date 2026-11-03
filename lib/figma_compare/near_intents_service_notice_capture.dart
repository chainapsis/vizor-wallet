import 'package:flutter/widgets.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/swap/domain/near_intents_service_status.dart';
import '../src/features/swap/widgets/near_intents_service_notice.dart';

Widget buildCurrentServiceNoticeCapture(BuildContext context) =>
    _capture(context);
Widget buildAllChainsServiceNoticeCapture(BuildContext context) =>
    _capture(context, all: true);
Widget buildPayServiceNoticeCapture(BuildContext context) =>
    _capture(context, pay: true);

/// Production modal with deterministic data; no API, wallet, storage or Rust.
Widget _capture(BuildContext context, {bool all = false, bool pay = false}) {
  final notice = NearIntentsServiceNoticeData(
    issues: [
      NearIntentsServiceIssue(
        chains: all
            ? const {'*'}
            : const {
                'eth',
                'arb',
                'base',
                'bsc',
                'avax',
                'pol',
                'op',
                'gnosis',
                'scroll',
                'monad',
                'aurora',
                'xlayer',
              },
        startsAt: DateTime.utc(2026, 11, 3, 12, 15),
        finishesAt: DateTime.utc(2026, 11, 3, 15, 15),
      ),
    ],
  );
  final modal = NearIntentsServiceNoticeModal(
    notice: notice,
    payMode: pay,
    onClose: () {},
    onDetails: () async {},
  );
  return Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: context.colors.background.base),
      if (kAppFormFactor == AppFormFactor.mobile) ...[
        ColoredBox(color: context.colors.background.neutralScrim),
        modal,
      ] else
        AppPaneModalOverlay(onDismiss: () {}, child: modal),
    ],
  );
}
