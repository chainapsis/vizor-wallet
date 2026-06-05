import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';

void main() {
  testWidgets('read-only proposal card shows stale selected choice fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        child: Center(
          child: SizedBox(
            width: 420,
            child: VotingProposalCard(
              proposal: VotingProposalView(
                id: 1,
                title: 'Issuance timing',
                description: 'Select the fee reissuance schedule.',
                options: [
                  VotingOptionView(index: 0, label: 'Immediately'),
                  VotingOptionView(index: 1, label: 'Later'),
                ],
              ),
              selectedChoice: 4,
              readOnly: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Immediately'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Choice 4'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Choose'), findsNothing);
  });
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: Directionality(textDirection: TextDirection.ltr, child: child),
        ),
      ),
    );
  }
}
