import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';

import '../../support/activity_local_gift_entry_checks.dart';

void main() {
  activityLocalGiftEntryChecks(() => const ActivityScreen(), mobile: false);
}
