import 'package:flutter/material.dart' show Builder, MaterialApp, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('in-progress sync row never displays 100 percent', (
    tester,
  ) async {
    late String amountText;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              amountText = buildSyncActivityRow(
                context: context,
                sync: SyncState(
                  isSyncing: true,
                  percentage: 1,
                  displayPercentage: 1,
                ),
              ).amountText;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(amountText, '99%');
  });
}
