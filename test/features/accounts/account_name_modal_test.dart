import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/account_name_modal.dart';

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('allows submitting a one-character account name', (tester) async {
    var updatedName = '';

    await tester.pumpWidget(
      _AccountNameModalHarness(
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );

    await tester.enterText(find.byType(TextField), 'J');
    await tester.pump();

    expect(find.text('Use up to 20 characters.'), findsNothing);

    await tester.tap(find.text('Update'));
    await tester.pump();

    expect(updatedName, 'J');
  });

  testWidgets('allows submitting twenty user-perceived characters', (
    tester,
  ) async {
    var updatedName = '';
    final name = List.filled(20, '😀').join();

    await tester.pumpWidget(
      _AccountNameModalHarness(
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );

    await tester.enterText(find.byType(TextField), name);
    await tester.pump();

    expect(find.text('Use up to 20 characters.'), findsNothing);

    await tester.tap(find.text('Update'));
    await tester.pump();

    expect(updatedName, name);
  });

  testWidgets('does not show the length warning for an empty name', (
    tester,
  ) async {
    await tester.pumpWidget(const _AccountNameModalHarness());

    expect(find.text('Use up to 20 characters.'), findsNothing);
  });

  testWidgets('only shows the length warning when the name exceeds 20 chars', (
    tester,
  ) async {
    await tester.pumpWidget(const _AccountNameModalHarness());

    await tester.enterText(find.byType(TextField), '12345678901234567890');
    await tester.pump();

    expect(find.text('Use up to 20 characters.'), findsNothing);

    await tester.enterText(find.byType(TextField), '123456789012345678901');
    await tester.pump();

    expect(find.text('Use up to 20 characters.'), findsOneWidget);
  });

  testWidgets('does not submit empty or overlong names', (tester) async {
    var updateCount = 0;

    await tester.pumpWidget(
      _AccountNameModalHarness(
        onUpdate: (_) async {
          updateCount += 1;
        },
      ),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pump();

    expect(updateCount, 0);

    await tester.enterText(find.byType(TextField), '123456789012345678901');
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pump();

    expect(updateCount, 0);
  });

  testWidgets('lays out modal actions as equal-width Figma buttons', (
    tester,
  ) async {
    await tester.pumpWidget(const _AccountNameModalHarness());

    final cancelButton = find.byKey(
      const ValueKey('account_modal_cancel_button'),
    );
    final actionButton = find.byKey(
      const ValueKey('account_modal_action_button'),
    );

    expect(tester.getSize(cancelButton).height, 36);
    expect(tester.getSize(actionButton).height, 36);
    expect(
      tester.getSize(cancelButton).width,
      moreOrLessEquals(tester.getSize(actionButton).width, epsilon: 0.1),
    );
    expect(tester.getSize(cancelButton).width, greaterThanOrEqualTo(96));
    expect(
      tester.getTopLeft(actionButton).dx - tester.getTopRight(cancelButton).dx,
      moreOrLessEquals(AppSpacing.s, epsilon: 0.1),
    );
  });
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));

  await geist.load();
}

class _AccountNameModalHarness extends StatelessWidget {
  const _AccountNameModalHarness({this.onUpdate});

  final Future<void> Function(String name)? onUpdate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: Center(
            child: AccountNameModal(
              accountName: 'Account 2',
              profilePictureId: 'pfp-01',
              onCancel: () {},
              onChangeProfilePicture: () {},
              onUpdate: onUpdate ?? (_) async {},
            ),
          ),
        ),
      ),
    );
  }
}
