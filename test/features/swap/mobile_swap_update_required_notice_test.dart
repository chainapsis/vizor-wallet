@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';

import 'support/swap_update_required_notice_cases.dart';

void main() => swapUpdateRequiredNoticeTests(SwapActivityDetailLayout.mobile);
