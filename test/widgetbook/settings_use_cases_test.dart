import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_pane_scroll_scaffold.dart';
import 'package:zcash_wallet/src/features/settings/widgets/viewing_key_content.dart';
import 'package:zcash_wallet/src/features/settings/viewing_key_copy.dart';
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
    expect(find.text('My gift cards'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
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

  testWidgets('settings explorer use case renders the explorer header', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsExplorerUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('ZecBlock'), findsOneWidget);
  });

  testWidgets('settings explorer custom use case shows the URL field', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsExplorerCustomUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(
      find.text('https://zcashblockexplorer.com/tx/{txid}'),
      findsOneWidget,
    );
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

  testWidgets('settings viewing key gate use case renders the gate', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsViewingKeyGateUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Confirm access'), findsOneWidget);
    expect(find.text('To view the viewing key.'), findsOneWidget);
  });

  testWidgets('settings viewing key reveal use case renders the key', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsViewingKeyRevealUseCase,
    );

    _expectNoCrash(errors);
    expect(find.text('Viewing key'), findsOneWidget);
    expect(find.text('Full viewing key'), findsOneWidget);
    expect(find.text(viewingKeyExplanation), findsOneWidget);
    expect(find.text(viewingKeyWarningTitle), findsOneWidget);
  });

  testWidgets('viewing key choice shows scope before revealing a key', (
    tester,
  ) async {
    final errors = await _pumpSettingsUseCase(
      tester,
      buildSettingsViewingKeyChoiceUseCase,
      viewport: const Size(1080, 720),
    );
    _expectNoCrash(errors);
    expect(find.text(viewingKeyChoiceSharingWarning), findsOneWidget);
    expect(
      find.byKey(const ValueKey('viewing_key_choose_incoming')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewing_key_choose_full')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings_viewing_key_value')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings_viewing_key_copy_button')),
      findsNothing,
    );
  });

  testWidgets('viewing keys fit the minimum desktop window in both formats', (
    tester,
  ) async {
    for (final type in ViewingKeyType.values) {
      for (final format in ViewingKeyFormat.values) {
        final errors = await _pumpSettingsUseCase(
          tester,
          (context) => buildSettingsViewingKeyRevealUseCase(
            context,
            type: type,
            format: format,
          ),
          viewport: const Size(1080, 720),
        );
        _expectNoCrash(errors);
        final outerScroll = find
            .descendant(
              of: find.byKey(AppPaneScrollScaffold.scrollViewKey),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(outerScroll).position;
        expect(
          position.maxScrollExtent,
          0,
          reason: '${type.name} / ${format.name}',
        );
        final copy = tester.getRect(
          find.byKey(const ValueKey('settings_viewing_key_copy_button')),
        );
        expect(
          copy.bottom,
          lessThanOrEqualTo(664),
          reason: 'Leave room below copy at the minimum window height',
        );
      }
    }
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
    expect(
      find.text('Open Vizor on your phone → Add a wallet → Link Vizor Desktop'),
      findsOneWidget,
    );
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
  Size viewport = const Size(1512, 982),
}) async {
  // Match the accounts widgetbook test viewport so the desktop shell
  // (full-window backdrop + sidebar) has room to lay out.
  tester.view.physicalSize = viewport;
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
