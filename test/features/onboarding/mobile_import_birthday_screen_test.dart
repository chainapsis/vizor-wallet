@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_calendar_overlay.dart'
    show ImportBirthdayCalendarPanel;
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/import/birthday',
  initialAccountState: const AccountState(accounts: []),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app() {
  return ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileImportBirthdayScreen(
        args: ImportBirthdayArgs(mnemonic: 'stub mnemonic'),
        loadChainMetadata: false,
      ),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('continue stays disabled until a plausible height is typed', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    AppButton continueButton() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );

    expect(continueButton().onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
    );
    await tester.pump();

    final heightField = find.byKey(
      const ValueKey('mobile_import_birthday_height'),
    );

    // Below the Sapling activation floor → still disabled.
    await tester.enterText(heightField, '1');
    await tester.pump();
    expect(continueButton().onPressed, isNull);

    // A plausible mainnet height enables the action.
    await tester.enterText(heightField, '2500000');
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);

    // Clearing it disables again.
    await tester.enterText(heightField, '');
    await tester.pump();
    expect(continueButton().onPressed, isNull);
  });

  testWidgets('the height field only accepts digits', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
    );
    await tester.pump();

    final heightField = find.byKey(
      const ValueKey('mobile_import_birthday_height'),
    );
    await tester.enterText(heightField, '25a.b00');
    await tester.pump();
    expect(
      tester.widget<EditableText>(heightField).controller.text,
      '2500',
    );
  });

  testWidgets('the date field is not typeable and opens the calendar', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    AppButton continueButton() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );

    // Date mode is the default — no editable text exists in it, and
    // continue is disabled until the calendar provides a date.
    expect(find.byType(EditableText), findsNothing);
    expect(continueButton().onPressed, isNull);
    expect(find.text('mm/dd/yyyy'), findsOneWidget);

    // Tapping anywhere on the field opens the calendar sheet.
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_date')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImportBirthdayCalendarPanel), findsOneWidget);

    // The sheet hugs the calendar instead of claiming the full
    // scroll-controlled height (panel + the AppSpacing.sm padding).
    final panelHeight = tester
        .getSize(find.byType(ImportBirthdayCalendarPanel))
        .height;
    final sheetHeight = tester.getSize(find.byType(BottomSheet)).height;
    expect(sheetHeight, closeTo(panelHeight + AppSpacing.sm * 2, 1.0));

    // The panel is its own card, so the sheet surface stays invisible —
    // only the scrim and the calendar render.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
      const Color(0x00000000),
    );

    // Selecting a (past) day fills the field and enables continue.
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    expect(find.byType(ImportBirthdayCalendarPanel), findsNothing);
    expect(continueButton().onPressed, isNotNull);
    expect(find.text('mm/dd/yyyy'), findsNothing);
  });
}
