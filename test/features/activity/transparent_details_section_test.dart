import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/transparent_details_section.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../support/localized_test_scope.dart';
import '../../support/test_l10n.dart';

Widget _section(String kind) => AppTheme(
  data: AppThemeData.light,
  child: LocalizedTestScope(
    child: TransparentDetailsSection(
      privacyModeEnabled: false,
      detail: rust_sync.TransactionDetail(
        txidHex: 'aa',
        txKind: kind,
        outputs: const [],
        detailsComplete: false,
        provisional: false,
        transparentDetailsState: rust_sync.TransparentDetailsState.available,
        transparentRecipients: [
          rust_sync.TransparentRecipient(
            outputIndex: 0,
            address: 't1other',
            amountZatoshi: BigInt.from(1000),
            isOwn: false,
          ),
        ],
        transparentOutputCount: 3,
        transparentOmissions: const [
          'multiple_source_scripts',
          'more_than_two_outputs',
        ],
      ),
    ),
  ),
);

void main() {
  final omitted = find.byKey(const ValueKey('transparent_details_omissions'));

  testWidgets('a receive shows no "Not shown" row', (tester) async {
    await tester.pumpWidget(_section('received'));
    expect(omitted, findsNothing);
  });

  testWidgets('a send names what its output list leaves out, not its funding', (
    tester,
  ) async {
    await tester.pumpWidget(_section('sent'));
    expect(omitted, findsOneWidget);
    expect(find.text(testL10n.activityOmissionMoreOutputs(1)), findsOneWidget);
    expect(find.textContaining('other sending addresses'), findsNothing);
  });
}
