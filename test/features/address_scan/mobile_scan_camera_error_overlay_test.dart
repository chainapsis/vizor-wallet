@Tags(['mobile'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart';

Widget _app(
  MobileScannerController controller, {
  Future<void> Function()? onOpenSettings,
}) {
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
          onOpenSettings: onOpenSettings,
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
    expect(
      find.byKey(const ValueKey('mobile_scan_open_settings_button')),
      findsNothing,
    );
  });

  testWidgets('opens settings from permission denied errors', (tester) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);
    var opens = 0;

    await tester.pumpWidget(
      _app(
        controller,
        onOpenSettings: () async {
          opens++;
        },
      ),
    );

    controller.value = controller.value.copyWith(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    );
    await tester.pump();

    final button = find.byKey(
      const ValueKey('mobile_scan_open_settings_button'),
    );
    expect(button, findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();

    expect(opens, 1);
  });
}
