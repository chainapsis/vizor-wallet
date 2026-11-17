import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';

import '../../support/localized_test_scope.dart';

void main() {
  testWidgets('a key fires on touch, dims while held, and fades back', (
    tester,
  ) async {
    final digits = <int>[];
    await tester.pumpWidget(
      LocalizedTestScope(
        locale: const Locale('en'),
        child: AppTheme(
          data: AppThemeData.dark,
          child: PasscodeNumpad(onDigit: digits.add, onBackspace: () {}),
        ),
      ),
    );

    AnimatedOpacity keyOpacity() => tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text('7'),
        matching: find.byKey(const ValueKey('passcode_key_opacity')),
      ),
    );
    expect(keyOpacity().opacity, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('7')),
    );
    await tester.pump();
    expect(digits, [7]);
    expect(keyOpacity().opacity, 0.5);
    expect(keyOpacity().duration, Duration.zero);

    await gesture.up();
    await tester.pump();
    expect(keyOpacity().opacity, 1);
    expect(keyOpacity().duration, const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(digits, [7]);
  });
}
