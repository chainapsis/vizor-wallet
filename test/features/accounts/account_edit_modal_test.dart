import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/account_edit_modal.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('allows submitting a one-character account name', (tester) async {
    var updatedName = '';

    await tester.pumpWidget(
      _AccountEditModalHarness(
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
      _AccountEditModalHarness(
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
    await tester.pumpWidget(const _AccountEditModalHarness());

    expect(find.text('Use up to 20 characters.'), findsNothing);
  });

  testWidgets('only shows the length warning when the name exceeds 20 chars', (
    tester,
  ) async {
    await tester.pumpWidget(const _AccountEditModalHarness());

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
      _AccountEditModalHarness(
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
    await tester.pumpWidget(const _AccountEditModalHarness());

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

  testWidgets('avatar edit badge opens the picture picker', (tester) async {
    var pickerOpened = 0;

    await tester.pumpWidget(
      _AccountEditModalHarness(onEditProfilePicture: () => pickerOpened += 1),
    );

    await tester.tap(
      find.byKey(const ValueKey('account_edit_profile_picture_button')),
    );
    await tester.pump();

    expect(pickerOpened, 1);
  });

  testWidgets('a picked picture enables Update without a name change', (
    tester,
  ) async {
    String? updatedName;

    await tester.pumpWidget(
      _AccountEditModalHarness(
        profilePictureChanged: true,
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );

    await tester.tap(find.text('Update'));
    await tester.pump();

    expect(updatedName, 'Account 2');
  });

  testWidgets('rebinding to another account drops the previous draft', (
    tester,
  ) async {
    String? updatedName;

    await tester.pumpWidget(
      _AccountEditModalHarness(
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );
    await tester.enterText(find.byType(TextField), 'Stale draft');
    await tester.pump();

    // Same mounted modal receives a different account (settings binds to the
    // active account; the sidebar can switch it while the modal is open).
    await tester.pumpWidget(
      _AccountEditModalHarness(
        accountUuid: 'uuid-3',
        accountName: 'Account 3',
        initialName: 'Account 3',
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );
    await tester.pump();

    expect(find.text('Stale draft'), findsNothing);
    expect(find.text('Account 3'), findsOneWidget);

    // Update stays a no-op until the user actually edits the new account.
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(updatedName, isNull);
  });

  testWidgets('rebinding resets even when both accounts share a name', (
    tester,
  ) async {
    String? updatedName;

    await tester.pumpWidget(
      _AccountEditModalHarness(
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );
    await tester.enterText(find.byType(TextField), 'Stale draft');
    await tester.pump();

    // Names are not unique, so an identically named account must still be
    // recognized as a different identity (uuid) and drop the draft.
    await tester.pumpWidget(
      _AccountEditModalHarness(
        accountUuid: 'uuid-3',
        onUpdate: (name) async {
          updatedName = name;
        },
      ),
    );
    await tester.pump();

    expect(find.text('Stale draft'), findsNothing);
    expect(find.text('Account 2'), findsOneWidget);

    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(updatedName, isNull);
  });
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));

  await geist.load();
}

class _AccountEditModalHarness extends StatelessWidget {
  const _AccountEditModalHarness({
    this.onUpdate,
    this.onEditProfilePicture,
    this.profilePictureChanged = false,
    this.accountUuid = 'uuid-2',
    this.accountName = 'Account 2',
    this.initialName = 'Account 2',
  });

  final Future<void> Function(String name)? onUpdate;
  final VoidCallback? onEditProfilePicture;
  final bool profilePictureChanged;
  final String accountUuid;
  final String accountName;
  final String initialName;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: Center(
            child: AccountEditModal(
              accountUuid: accountUuid,
              accountName: accountName,
              initialName: initialName,
              profilePictureId: 'pfp-01',
              profilePictureChanged: profilePictureChanged,
              onEditProfilePicture: onEditProfilePicture ?? () {},
              onNameChanged: (_) {},
              onCancel: () {},
              onUpdate: onUpdate ?? (_) async {},
            ),
          ),
        ),
      ),
    );
  }
}
