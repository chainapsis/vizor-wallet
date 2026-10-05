import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/ledger/ledger_capability.dart';
import '../src/features/onboarding/mobile/mobile_hardware_selection_screen.dart';

Widget buildMobileHardwareSelectionCapture(BuildContext context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: const EdgeInsets.only(top: 55, bottom: 24),
    viewPadding: const EdgeInsets.only(top: 55, bottom: 24),
  ),
  child: ProviderScope(
    overrides: [
      ledgerStaticCapabilityProvider.overrideWithValue(
        const LedgerCapability.supported(),
      ),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
    ],
    child: const MobileHardwareSelectionScreen(),
  ),
);
