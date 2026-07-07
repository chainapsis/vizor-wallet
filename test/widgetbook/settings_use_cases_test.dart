import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  // Render with the real app fonts instead of the square-glyph test font.
  // The test font is much wider than Geist/Young Serif, which produces
  // RenderFlex overflows that do not exist in the running app.
  setUpAll(() async {
    final fonts = <String, List<String>>{
      'Geist': [
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
      ],
      'Geist Mono': [
        'assets/fonts/GeistMono-Regular.ttf',
        'assets/fonts/GeistMono-Medium.ttf',
      ],
      'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
      'Inter': [
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Medium.ttf',
        'assets/fonts/Inter-SemiBold.ttf',
        'assets/fonts/Inter-Bold.ttf',
      ],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });

  testWidgets('settings main use case renders the settings header', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(tester, buildSettingsMainUseCase);

    _expectNoCrash(errors);
    // "Settings" appears in the sidebar nav and as the page header.
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('settings endpoint use case renders the endpoint header', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsEndpointUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Endpoint'), findsOneWidget);
  });

  testWidgets('settings secret passphrase gate use case renders the gate', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsSecretPassphraseGateUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Confirm access'), findsOneWidget);
    expect(find.text('To view the secret passphrase.'), findsOneWidget);
  });

  testWidgets('settings change password gate use case renders the gate', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsChangePasswordGateUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Confirm access'), findsOneWidget);
    expect(find.text('Enter your current password first.'), findsOneWidget);
  });

  testWidgets('settings uninstall confirm use case renders the confirm view', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsUninstallConfirmUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Uninstall Vizor'), findsWidgets);
    expect(find.text('This cannot be undone.'), findsOneWidget);
  });

  testWidgets('settings uninstall done use case renders the done view', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsUninstallDoneUseCase,
      // The done view auto-plays a 1500ms badge animation in initState, so
      // advance past it to drain the ticker before the test ends.
      settleDuration: const Duration(milliseconds: 1600),
    );

    _expectNoCrash(errors);
    expect(find.text('Your data has been removed'), findsOneWidget);
  });

  testWidgets('settings wallet link initial use case renders the CTA', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsWalletLinkInitialUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Link Vizor Mobile'), findsOneWidget);
    expect(find.text('Start linking'), findsOneWidget);
  });

  testWidgets('settings wallet link confirm access use case renders the gate', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsWalletLinkConfirmAccessUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Confirm access'), findsOneWidget);
    expect(find.text('To link Vizor Mobile.'), findsOneWidget);
  });

  testWidgets('settings wallet link QR use case renders the timer', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsWalletLinkQrUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Scan with Vizor mobile'), findsOneWidget);
    expect(find.text('Expires in 0:59'), findsOneWidget);
  });

  testWidgets('settings wallet link success use case renders summary', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsWalletLinkSuccessUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Vizor Mobile linked successfully'), findsOneWidget);
    expect(
      find.text('6 accounts and 20 contacts were imported on mobile.'),
      findsOneWidget,
    );
  });

  testWidgets('settings wallet link expired use case renders renewal CTA', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsWalletLinkExpiredUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Time’s up'), findsOneWidget);
    expect(find.text('Generate new code'), findsOneWidget);
  });
}

/// Smoke assertion: the use case must not have thrown anything (missing
/// asset, null deref, bad provider state, render overflow, etc.).
///
/// Errors are captured per-frame in [_pumpSettingsUseCase] so each one can be
/// inspected individually (the test binding otherwise aggregates several
/// pending exceptions into a single opaque "Multiple exceptions" summary).
void _expectNoCrash(List<FlutterErrorDetails> errors) {
  for (final details in errors) {
    fail('Unexpected exception while rendering use case: ${details.exception}');
  }
}

Future<List<FlutterErrorDetails>> _pumpSettingsUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  Duration? settleDuration,
}) async {
  // Match the accounts widgetbook test viewport so the desktop shell
  // (full-window backdrop + sidebar) has room to lay out.
  tester.view.physicalSize = const Size(1512, 982);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Capture every error individually instead of letting the binding coalesce
  // them, so `_expectNoCrash` can distinguish cosmetic overflow warnings from
  // real failures.
  final errors = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previousOnError);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: AppTheme(
        data: AppThemeData.light,
        child: Builder(builder: builder),
      ),
    ),
  );
  // Not pumpAndSettle: these screens carry indefinite animations (e.g. the
  // sync spinner) that never settle.
  await tester.pump();
  if (settleDuration != null) {
    await tester.pump(settleDuration);
  }

  return errors;
}
