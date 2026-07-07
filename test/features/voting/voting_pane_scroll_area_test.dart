import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_pane_scroll_area.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

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
      tester.widget<RawScrollbar>(find.byType(RawScrollbar)).thumbVisibility,
      isFalse,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(VotingPaneListView)));
    await tester.pump();

    // The shared pane scrollbar shows the design thumb on hover when the pane
    // can scroll (no desktop-platform gate; it relies on hover instead).
    expect(
      tester.widget<RawScrollbar>(find.byType(RawScrollbar)).thumbVisibility,
      isTrue,
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
      tester.widget<RawScrollbar>(find.byType(RawScrollbar)).thumbVisibility,
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
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(body: SizedBox.expand(child: child)),
      ),
    );
  }
}
