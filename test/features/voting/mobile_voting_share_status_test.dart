@Tags(['mobile'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_share_status_card.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

void main() {
  testWidgets('high-level share progress fits on mobile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 8, 25, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: VotingShareStatusCard(
              now: now,
              records: [
                for (var index = 0; index < 16; index++)
                  _share(
                    index,
                    confirmed: index < 5,
                    submitAt: BigInt.from(nowSeconds + index * 60 * 60),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('5 of 16 shares submitted'), findsOneWidget);
    expect(find.text('31%'), findsOneWidget);
    expect(find.text('Complete in about 15 hours'), findsOneWidget);
    expect(
      find.textContaining('shares that are submitted at different times'),
      findsOneWidget,
    );
    expect(find.textContaining('close Vizor at any time'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voting_share_status_toggle')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

rust_wire.ShareDelegationRecordView _share(
  int shareIndex, {
  required bool confirmed,
  required BigInt submitAt,
}) {
  return rust_wire.ShareDelegationRecordView(
    roundId: 'round-1',
    bundleIndex: 0,
    proposalId: 7,
    shareIndex: shareIndex,
    sentToUrls: const ['https://helper.example'],
    ambiguousUrls: const [],
    targetCount: 1,
    nullifier: Uint8List.fromList(List.filled(32, shareIndex)),
    phase: confirmed ? 'confirmed' : 'submitted_share',
    confirmed: confirmed,
    submitAt: submitAt,
    createdAt: submitAt,
  );
}
