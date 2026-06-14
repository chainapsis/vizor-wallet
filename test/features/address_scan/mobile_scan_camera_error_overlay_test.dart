@Tags(['mobile'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart';

Widget _app(MobileScannerController controller) {
  return AppTheme(
    data: AppThemeData.dark,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 393,
        height: 852,
        child: MobileScanCameraErrorOverlay(
          controller: controller,
          maxWidth: 260,
          permissionDeniedMessage:
              'Camera access is off. Allow it in Settings to scan addresses.',
          unavailableMessage: 'The camera is unavailable right now.',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders permission errors above the scan scrim bounds', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    expect(find.textContaining('Camera access is off'), findsNothing);

    controller.value = controller.value.copyWith(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    );
    await tester.pump();

    final message = find.text(
      'Camera access is off. Allow it in Settings to scan addresses.',
    );
    expect(message, findsOneWidget);
    expect(tester.getSize(message).width, lessThanOrEqualTo(260));
  });

  testWidgets('renders non-permission camera errors with the fallback copy', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));

    controller.value = controller.value.copyWith(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerUninitialized,
      ),
    );
    await tester.pump();

    expect(find.text('The camera is unavailable right now.'), findsOneWidget);
  });
}
