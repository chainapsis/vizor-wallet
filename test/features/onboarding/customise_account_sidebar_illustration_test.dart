import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_onboarding_flow.dart';

const _customiseAccountAsset =
    'assets/illustrations/onboarding_customise_account_sidebar.png';

void main() {
  testWidgets('import customisation shows the full-height illustration', (
    tester,
  ) async {
    await _setDesktopSurface(tester);

    await tester.pumpWidget(
      _harness(
        const ImportOnboardingShell(
          activeStep: ImportOnboardingStep.customiseAccount,
          showPasswordStep: false,
          child: SizedBox.shrink(),
        ),
      ),
    );

    expect(tester.getSize(_customiseAccountImage()), const Size(256, 430));
  });

  testWidgets('import keeps the shorter illustration frame on other steps', (
    tester,
  ) async {
    await _setDesktopSurface(tester);

    await tester.pumpWidget(
      _harness(
        const ImportOnboardingShell(
          activeStep: ImportOnboardingStep.secretPassphrase,
          showPasswordStep: false,
          child: SizedBox.shrink(),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Image).last), const Size(256, 405));
  });

  testWidgets('Keystone customisation shows the full-height illustration', (
    tester,
  ) async {
    await _setDesktopSurface(tester);

    await tester.pumpWidget(
      _harness(
        const KeystoneOnboardingShell(
          activeStep: KeystoneOnboardingStep.customiseAccount,
          showPasswordStep: false,
          child: SizedBox.shrink(),
        ),
      ),
    );

    expect(tester.getSize(_customiseAccountImage()), const Size(256, 430));
  });

  testWidgets('Keystone keeps the shorter illustration frame on other steps', (
    tester,
  ) async {
    await _setDesktopSurface(tester);

    await tester.pumpWidget(
      _harness(
        const KeystoneOnboardingShell(
          activeStep: KeystoneOnboardingStep.howToConnect,
          showPasswordStep: false,
          child: SizedBox.shrink(),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Image).last), const Size(256, 405));
  });
}

Finder _customiseAccountImage() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == _customiseAccountAsset,
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: AppTheme(data: AppThemeData.light, child: child),
  );
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
