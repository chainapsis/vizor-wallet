import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/widgetbook/accounts_settings_use_cases.dart';
import 'package:zcash_wallet/widgetbook/core_use_cases.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('settings to core URI replacement keeps the incoming platform', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await tester.pumpWidget(const _FixtureHost(surface: _Surface.settings));
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.windows);

    await tester.pumpWidget(const _FixtureHost(surface: _Surface.core));
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.macOS);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.linux);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('core to settings URI replacement keeps the incoming platform', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await tester.pumpWidget(const _FixtureHost(surface: _Surface.core));
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.macOS);

    await tester.pumpWidget(const _FixtureHost(surface: _Surface.settings));
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.windows);

    // The modal opener schedules a rebuild after the URI replacement. The
    // Windows-only row must still accompany the modal in that later frame.
    await tester.pump();
    expect(find.text('Available'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(debugDefaultTargetPlatformOverride, TargetPlatform.linux);
    debugDefaultTargetPlatformOverride = null;
  });
}

enum _Surface { settings, core }

class _FixtureHost extends StatelessWidget {
  const _FixtureHost({required this.surface});

  final _Surface surface;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: Material(
          child: KeyedSubtree(
            key: ValueKey('/${surface.name}'),
            child: Builder(
              builder: (context) => switch (surface) {
                _Surface.settings => settingsDesktopScreenFixture(
                  accountState: accountsPreviewDesignState,
                  themeMode: ThemeMode.system,
                  networkPrivacyState: const NetworkPrivacyState.off(),
                  modal: SettingsPreviewDesktopModal.updates,
                ),
                _Surface.core => mainSidebarFixture(
                  context,
                  account: CoreAccountCase.software,
                  route: CoreSidebarRoute.home,
                  sync: CoreSyncCase.synced,
                  privacyMode: false,
                  swapEnabled: true,
                  migration: CoreSidebarMigrationCase.none,
                  platform: TargetPlatform.macOS,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}
