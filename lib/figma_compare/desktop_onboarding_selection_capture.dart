import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/ledger/ledger_capability.dart';
import '../src/features/onboarding/import/desktop_import_method_selection_screen.dart';
import '../src/features/onboarding/import/desktop_hardware_selection_screen.dart';

Widget buildDesktopOnboardingImportCapture(BuildContext context) =>
    const DesktopImportMethodSelectionScreen();

Widget buildDesktopOnboardingHardwareCapture(BuildContext context) =>
    ProviderScope(
      overrides: [
        ledgerStaticCapabilityProvider.overrideWithValue(
          const LedgerCapability.supported(),
        ),
      ],
      child: const DesktopHardwareSelectionScreen(),
    );
