@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';

import '../../support/activity_local_gift_entry_checks.dart';

void main() {
  activityLocalGiftEntryChecks(
    () => const MobileActivityScreen(),
    mobile: true,
  );
}
