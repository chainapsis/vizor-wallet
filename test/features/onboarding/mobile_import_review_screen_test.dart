@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_review_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';

const _words = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('review shows the Figma copy', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Review Import'), findsOneWidget);
    expect(
      find.text('Review your Secret Passphrase before import starts.'),
      findsOneWidget,
    );
    expect(find.text('Confirm & Continue'), findsOneWidget);
    expect(find.text('Clear Secret Phrase'), findsOneWidget);
  });

  testWidgets('Clear Secret Phrase pops with the cleared result', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_review_edit')));
    await tester.pumpAndSettle();

    // Back on the opener, which recorded the returned result.
    expect(find.text('result: ImportReviewResult.cleared'), findsOneWidget);
  });
}

Widget _host() {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    home: const _Opener(),
  );
}

class _Opener extends StatefulWidget {
  const _Opener();

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  Object? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('result: $_result'),
            TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(
                    builder: (_) => const MobileImportReviewScreen(
                      args: MobileImportReviewArgs(words: _words),
                    ),
                  ),
                );
                if (mounted) setState(() => _result = result);
              },
              child: const Text('open'),
            ),
          ],
        ),
      ),
    );
  }
}
