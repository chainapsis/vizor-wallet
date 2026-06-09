import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, Scrollbar, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show
        BackdropFilter,
        Column,
        Expanded,
        Focus,
        FocusNode,
        Scrollable,
        ScrollableState,
        SingleChildScrollView,
        Size,
        SizedBox,
        ValueKey,
        Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  testWidgets('shows BIP39 prefix suggestions for the focused word', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'ca');
    await tester.pump();

    expect(find.text('cabbage'), findsOneWidget);
    expect(find.text('cabin'), findsOneWidget);
    expect(find.text('cable'), findsOneWidget);
    expect(find.text('cactus'), findsOneWidget);
  });

  testWidgets(
    'shows the body scrollbar only below the reference layout height',
    (tester) async {
      await _setDesktopViewport(tester, const Size(1080, 720));
      await tester.pumpWidget(_importPassphraseScreen());

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isFalse,
      );
      final referenceFirstFieldTop = tester.getTopLeft(_wordField(0)).dy;
      final referenceButtonTop = tester
          .getTopLeft(find.byKey(_submitButtonKey))
          .dy;

      await tester.binding.setSurfaceSize(const Size(1080, 560));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isTrue,
      );
      expect(
        tester.getSize(find.byType(SingleChildScrollView)).width,
        greaterThan(396),
      );
      final bodyScrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(bodyScrollable.position.maxScrollExtent, greaterThan(32));
      bodyScrollable.position.jumpTo(bodyScrollable.position.maxScrollExtent);
      await tester.pump();

      final viewportBottom = tester
          .getBottomLeft(find.byType(SingleChildScrollView))
          .dy;
      final buttonBottom = tester
          .getBottomLeft(find.byKey(_submitButtonKey))
          .dy;
      expect(viewportBottom - buttonBottom, closeTo(32, 0.1));
      bodyScrollable.position.jumpTo(0);
      await tester.pump();

      expect(tester.getTopLeft(_wordField(0)).dy, referenceFirstFieldTop);
      expect(
        tester.getTopLeft(find.byKey(_submitButtonKey)).dy,
        referenceButtonTop,
      );

      await tester.binding.setSurfaceSize(const Size(1080, 900));
      await tester.pump();

      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isFalse,
      );
      expect(
        tester.getTopLeft(_wordField(0)).dy,
        greaterThan(referenceFirstFieldTop),
      );
      expect(
        tester.getTopLeft(find.byKey(_submitButtonKey)).dy,
        greaterThan(referenceButtonTop),
      );
      expect(
        tester.getBottomLeft(find.byType(SingleChildScrollView)).dy -
            tester.getBottomLeft(find.byKey(_submitButtonKey)).dy,
        closeTo(16, 0.1),
      );
    },
  );

  testWidgets('keeps autocomplete overlay stable while resizing the body', (
    tester,
  ) async {
    await _setDesktopViewport(tester, const Size(1080, 720));
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    expect(find.text('cabbage'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1080, 560));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('cabbage'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1080, 720));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('cabbage'), findsOneWidget);
  });

  testWidgets(
    'tapping a suggestion fills the word and focuses the next field',
    (tester) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(_importPassphraseScreen());
      await tester.enterText(_wordField(0), 'cab');
      await tester.pump();

      await tester.tap(find.text('cabbage'));
      await tester.pump();

      expect(_textField(tester, 0).controller!.text, 'cabbage');
      expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('Enter accepts the highlighted suggestion and moves next', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'cabbage');
    expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Tab moves the highlighted suggestion down without selecting', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'cab');
    expect(_textField(tester, 0).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'cabin');
    expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Shift+Tab moves the highlighted suggestion up', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'cabin');
    expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Tab moves focus when autocomplete is hidden', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'zzz');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'zzz');
    expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Tab leaves the last word when autocomplete is hidden', (
    tester,
  ) async {
    final afterNode = FocusNode();
    addTearDown(afterNode.dispose);

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen(afterNode: afterNode));
    await tester.enterText(_wordField(23), 'zzz');
    _textField(tester, 23).focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(afterNode.hasFocus, isTrue);
  });

  testWidgets('Tab from the focus cycle end enters the first word', (
    tester,
  ) async {
    final afterNode = FocusNode();
    addTearDown(afterNode.dispose);

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen(afterNode: afterNode));
    afterNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_textField(tester, 0).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Shift+Tab leaves the first word when autocomplete is hidden', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'zzz');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(_textField(tester, 0).focusNode!.hasFocus, isFalse);
  });

  testWidgets(
    'Tab scrolls clipped suggestions when highlight moves below view',
    (tester) async {
      await _setDesktopViewport(tester, const Size(1280, 720));
      await tester.pumpWidget(_importPassphraseScreen());
      await tester.enterText(_wordField(23), 'ca');
      await tester.pump();

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      expect(scrollable.position.viewportDimension, lessThan(152));
      expect(find.text('cage'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(scrollable.position.pixels, greaterThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(_textField(tester, 23).controller!.text, 'cactus');
    },
  );

  testWidgets('keeps existing paste-to-fill behavior', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'abandon ability able');
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'abandon');
    expect(_textField(tester, 1).controller!.text, 'ability');
    expect(_textField(tester, 2).controller!.text, 'able');
    expect(_textField(tester, 3).focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'submits a valid 12-word mnemonic without requiring empty fields',
    (tester) async {
      ImportBirthdayArgs? submittedArgs;
      final router = _importPassphraseRouter((args) => submittedArgs = args);
      addTearDown(router.dispose);

      await _setDesktopViewport(tester);
      await tester.pumpWidget(_routerHarness(router));
      await _enterWords(tester, 12);

      expect(_submitButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(_submitButtonKey));
      await tester.pumpAndSettle();

      expect(submittedArgs?.mnemonic, _words(12).join(' '));
    },
  );

  testWidgets('accepts supported mnemonic lengths and rejects partial steps', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());

    await _enterWords(tester, 12);
    expect(_submitButton(tester).onPressed, isNotNull);

    await tester.enterText(_wordField(12), _wordAt(12));
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNull);

    await tester.enterText(_wordField(13), _wordAt(13));
    await tester.enterText(_wordField(14), _wordAt(14));
    await tester.pump();
    expect(_submitButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'rejects mnemonic words with a gap before the last entered word',
    (tester) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(_importPassphraseScreen());

      await _enterWords(tester, 12);
      expect(_submitButton(tester).onPressed, isNotNull);

      await tester.enterText(_wordField(5), '');
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'privacy shield ignores empty focused words when focus is unsafe',
    (tester) async {
      final controller = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(controller.dispose);

      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _importPassphraseScreen(privacyOverlayController: controller),
      );

      _textField(tester, 0).focusNode!.requestFocus();
      await tester.pump();

      expect(_textField(tester, 0).focusNode!.hasFocus, isTrue);
      expect(_textField(tester, 0).controller!.text, isEmpty);
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    },
  );

  testWidgets('privacy shield covers entered words when focus is unsafe', (
    tester,
  ) async {
    final controller = SensitivePrivacyOverlayController(initiallySafe: false);
    addTearDown(controller.dispose);

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _importPassphraseScreen(privacyOverlayController: controller),
    );

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

    await tester.enterText(_wordField(0), 'abandon');
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);

    controller.markSafe();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
  });

  testWidgets('privacy shield hides active autocomplete suggestions', (
    tester,
  ) async {
    final controller = SensitivePrivacyOverlayController();
    addTearDown(controller.dispose);

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _importPassphraseScreen(privacyOverlayController: controller),
    );
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    expect(find.text('cabbage'), findsOneWidget);

    controller.markUnsafe();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);
    expect(find.text('cabbage'), findsNothing);

    controller.markSafe();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    expect(find.text('cabbage'), findsNothing);

    await tester.tap(_wordField(0));
    await tester.pump();
    await tester.pump();

    expect(find.text('cabbage'), findsOneWidget);

    controller.markUnsafe();
    await tester.pump();
    controller.markSafe();
    await tester.pump();

    expect(find.text('cabbage'), findsNothing);

    await tester.tap(_wordField(0));
    await tester.pump();
    await tester.pump();

    expect(find.text('cabbage'), findsOneWidget);
  });
}

Future<void> _setDesktopViewport(
  WidgetTester tester, [
  Size size = const Size(1280, 900),
]) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _importPassphraseScreen({
  FocusNode? afterNode,
  SensitivePrivacyOverlayController? privacyOverlayController,
}) {
  Widget body = ImportSecretPassphraseScreen(
    privacyOverlayController: privacyOverlayController,
  );
  if (afterNode != null) {
    body = Column(
      children: [
        Expanded(child: body),
        Focus(focusNode: afterNode, child: const SizedBox(width: 1, height: 1)),
      ],
    );
  }

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(body: body),
      ),
    ),
  );
}

GoRouter _importPassphraseRouter(
  void Function(ImportBirthdayArgs args) onSubmit,
) {
  return GoRouter(
    initialLocation: '/import',
    routes: [
      GoRoute(
        path: '/import',
        builder: (_, _) => const Scaffold(body: ImportSecretPassphraseScreen()),
      ),
      GoRoute(
        path: '/import/birthday',
        builder: (_, state) {
          onSubmit(state.extra as ImportBirthdayArgs);
          return const SizedBox.shrink();
        },
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
}

Widget _routerHarness(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.light,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

Finder _wordField(int index) => find.byType(TextField).at(index);

TextField _textField(WidgetTester tester, int index) {
  return tester.widget<TextField>(_wordField(index));
}

const _submitButtonKey = ValueKey('import_secret_submit_button');

AppButton _submitButton(WidgetTester tester) {
  return tester.widget<AppButton>(find.byKey(_submitButtonKey));
}

Future<void> _enterWords(WidgetTester tester, int count) async {
  for (var index = 0; index < count; index++) {
    await tester.enterText(_wordField(index), _wordAt(index));
  }
  await tester.pump();
}

List<String> _words(int count) {
  return List.generate(count, _wordAt);
}

String _wordAt(int index) => _wordList[index % _wordList.length];

class _RustApiFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => _wordList;

  @override
  bool crateApiWalletValidateMnemonic({required String mnemonic}) {
    final count = mnemonic.trim().split(RegExp(r'\s+')).length;
    return count >= 12 && count <= 24 && count % 3 == 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

const _wordList = <String>[
  'abandon',
  'ability',
  'able',
  'about',
  'above',
  'cabbage',
  'cabin',
  'cable',
  'cactus',
  'cage',
  'cake',
  'call',
  'calm',
  'camera',
  'camp',
];
