@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/receive/widgets/mobile/receive_address_info_sheet.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';
import 'package:zcash_wallet/widgetbook/receive_use_cases.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('receive mobile shielded use case renders receive screen', (
    tester,
  ) async {
    await _pumpReceiveMobileUseCase(tester, buildReceiveMobileShieldedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileReceiveScreen), findsOneWidget);
    expect(find.text('Receive ZEC'), findsOneWidget);
    expect(find.text('Account Name'), findsOneWidget);
    expect(find.text('Share shielded address'), findsOneWidget);
    expect(find.text('Copy shielded address'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_receive_share'))),
      const Size(300, 50),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_receive_copy'))),
      const Size(300, 50),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('receive_address_type_tabs'))),
      const Size(320, 44),
    );
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('receive_address_type_tabs')),
      ),
      const Offset(36.5, 102.5),
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_receive_qr_shielded')),
          matching: find.byType(ReceiveQrSurface),
        ),
      ),
      const Size(292, 308),
    );
    expect(
      tester.getTopLeft(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_receive_qr_shielded')),
          matching: find.byType(ReceiveQrSurface),
        ),
      ),
      const Offset(50.5, 178.5),
    );
  });

  testWidgets('receive mobile transparent use case renders transparent state', (
    tester,
  ) async {
    await _pumpReceiveMobileUseCase(
      tester,
      buildReceiveMobileTransparentUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Share transparent address'), findsOneWidget);
    expect(find.text('Copy transparent address'), findsOneWidget);
  });

  testWidgets('receive mobile shielded sheet use case opens info sheet', (
    tester,
  ) async {
    await _pumpReceiveMobileUseCase(
      tester,
      buildReceiveMobileShieldedSheetUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Shielded address'), findsOneWidget);
    expect(find.text('Strong privacy by default.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReceiveAddressInfoSheet)),
      const Size(361, 454),
    );
    expect(
      tester.getTopLeft(find.byType(ReceiveAddressInfoSheet)),
      const Offset(16, 366),
    );
    final firstItem = find.byKey(const ValueKey('receive_address_info_item_0'));
    final secondItem = find.byKey(
      const ValueKey('receive_address_info_item_1'),
    );
    final lastItem = find.byKey(const ValueKey('receive_address_info_item_2'));
    final closeButton = find.byKey(
      const ValueKey('receive_address_info_close'),
    );
    final modalClose = find.byKey(
      const ValueKey('receive_address_info_modal_close'),
    );
    final modalCloseIcon = find.byKey(
      const ValueKey('receive_address_info_modal_close_icon'),
    );
    expect(tester.getSize(closeButton), const Size(329, 50));
    expect(tester.getSize(modalClose), const Size(32, 32));
    expect(tester.getSize(modalCloseIcon), const Size(20, 20));
    expect(
      tester.getTopLeft(secondItem).dy - tester.getBottomLeft(firstItem).dy,
      moreOrLessEquals(8, epsilon: 0.1),
    );
    expect(
      tester.getTopLeft(closeButton).dy - tester.getBottomLeft(lastItem).dy,
      moreOrLessEquals(24, epsilon: 0.1),
    );
    expect(
      tester.getBottomLeft(find.byType(ReceiveAddressInfoSheet)).dy -
          tester.getBottomLeft(closeButton).dy,
      moreOrLessEquals(32, epsilon: 0.1),
    );
  });

  testWidgets('receive mobile transparent sheet use case opens info sheet', (
    tester,
  ) async {
    await _pumpReceiveMobileUseCase(
      tester,
      buildReceiveMobileTransparentSheetUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Transparent address'), findsOneWidget);
    expect(find.text('Publicly visible'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReceiveAddressInfoSheet)),
      const Size(361, 479),
    );
    expect(
      tester.getTopLeft(find.byType(ReceiveAddressInfoSheet)),
      const Offset(16, 341),
    );
  });
}

Future<void> _pumpReceiveMobileUseCase(
  WidgetTester tester,
  Widget Function(BuildContext context) builder,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(
        data: AppThemeData.dark,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}
