import 'dart:ui' show Size;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart' show ValueKey, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/multisig/screens/multisig_connect_screen.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';

void main() {
  testWidgets('shows create and join session actions', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_screen());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('multisig_connect_create_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('multisig_connect_join_button')),
      findsOneWidget,
    );
  });

  testWidgets('shows pending multisig summaries', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _screen(
        summaries: const [
          MultisigPendingSessionSummary(
            storageId: 'session-1:participant-1',
            sessionId: 'session-1',
            participantId: 'participant-1',
            role: MultisigPendingRole.creator,
            label: 'Family vault',
            state: 'collecting',
            updatedLocallyAt: 20,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Pending sessions'), findsOneWidget);
    expect(find.text('Family vault'), findsOneWidget);
    expect(find.text('session-1 · Collecting'), findsOneWidget);
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _screen({List<MultisigPendingSessionSummary> summaries = const []}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      multisigPendingSessionSummariesProvider.overrideWith(
        (ref) async => summaries,
      ),
      multisigAccountMaterialsProvider.overrideWith(
        (ref) async => const <MultisigAccountMaterial>[],
      ),
    ],
    child: const MaterialApp(
      home: AppTheme(data: AppThemeData.light, child: MultisigConnectScreen()),
    ),
  );
}
