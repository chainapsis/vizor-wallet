import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';

import 'support/swap_update_required_notice_cases.dart';

// The mobile lane runs the same cases from
// mobile_swap_update_required_notice_test.dart.

void main() => swapUpdateRequiredNoticeTests(SwapActivityDetailLayout.desktop);
