import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/ledger_wallet_rename_modal.dart';

void main() {
  testWidgets('rename keeps its actions stable while saving', (tester) async {
    final pending = Completer<void>();
    String? submittedName;
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Material(
            child: Center(
              child: LedgerWalletRenameModal(
                initialName: 'Ledger wallet',
                onCancel: () {},
                onRename: (name) {
                  submittedName = name;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      ),
    );
    final field = find.descendant(
      of: find.byKey(const ValueKey('ledger_wallet_rename_field')),
      matching: find.byType(EditableText),
    );
    final rename = find.byKey(const ValueKey('account_modal_action_button'));
    final cancel = find.byKey(const ValueKey('account_modal_cancel_button'));
    expect(tester.widget<AppButton>(rename).onPressed, isNull);
    await tester.enterText(field, 'Cold storage');
    await tester.pump();
    final renameBounds = tester.getRect(rename);
    final cancelBounds = tester.getRect(cancel);

    await tester.tap(rename);
    await tester.pump();
    expect(submittedName, 'Cold storage');
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Renaming...'), findsNothing);
    expect(tester.getRect(rename), renameBounds);
    expect(tester.getRect(cancel), cancelBounds);
    expect(tester.widget<AppButton>(cancel).onPressed, isNull);
    final spinner = find.descendant(
      of: rename,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.loader,
      ),
    );
    expect(spinner, findsOneWidget);
    expect(
      tester.getCenter(spinner).dx,
      greaterThan(tester.getCenter(find.text('Rename')).dx),
    );
    expect(tester.takeException(), isNull);

    pending.completeError(StateError('Preview write failed'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't rename group."), findsOneWidget);
    expect(tester.widget<AppButton>(rename).onPressed, isNotNull);
    expect(tester.widget<AppButton>(cancel).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
