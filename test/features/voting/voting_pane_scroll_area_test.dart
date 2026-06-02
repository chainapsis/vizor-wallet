import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_layout.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_pane_scroll_area.dart';

void main() {
  testWidgets('shows scrollbar on hover only when the pane can scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 240));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const _Harness(
        child: VotingPaneListView.separated(
          maxWidth: 240,
          itemCount: 24,
          itemBuilder: _itemBuilder,
          separatorBuilder: _separatorBuilder,
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isFalse,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(VotingPaneListView)));
    await tester.pump();

    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isDesktopLayoutPlatform,
    );

    await tester.pumpWidget(
      const _Harness(
        child: VotingPaneListView.separated(
          maxWidth: 240,
          itemCount: 1,
          itemBuilder: _itemBuilder,
          separatorBuilder: _separatorBuilder,
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isFalse,
    );
  });
}

Widget _itemBuilder(BuildContext context, int index) {
  return SizedBox(height: 40, child: Text('Item $index'));
}

Widget _separatorBuilder(BuildContext context, int index) {
  return const SizedBox(height: 8);
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: child)),
    );
  }
}
