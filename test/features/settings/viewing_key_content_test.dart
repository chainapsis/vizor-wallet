import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/clipboard/sensitive_clipboard.dart';
import 'package:zcash_wallet/src/core/layout/app_pane_scroll_scaffold.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';
import 'package:zcash_wallet/src/features/settings/viewing_key_copy.dart';
import 'package:zcash_wallet/src/features/settings/widgets/viewing_key_content.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' show AccountViewingKeys;
import '../../figma_compare/figma_compare_font_loader.dart';

const _account = AccountInfo(uuid: 'target', name: 'Savings account', order: 0);
final _full = 'uview1${'q' * 491}previewonly';
final _incoming = 'uivk1${'q' * 281}previewonly';
const _copy = ValueKey('copy');
const _viewer = ValueKey('viewer');

Future<void> _pump(
  WidgetTester tester, {
  double scale = 1,
  bool reducedMotion = false,
  Size size = const Size(393, 852),
  double? contentWidth,
  ViewingKeyFormat format = ViewingKeyFormat.qr,
  ViewingKeyType? type = ViewingKeyType.full,
  Future<void> Function(String)? onCopy,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var selectedType = type;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
      ),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: AppPaneScrollScaffold(
            toolbar: TextButton(
              key: const ValueKey('test_back'),
              onPressed: () => setState(() => selectedType = null),
              child: const Text('Back to viewing key'),
            ),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: ViewingKeyContent(
                  account: _account,
                  viewingKeys: AccountViewingKeys(ufvk: _full, uivk: _incoming),
                  onCopy: onCopy ?? (_) async {},
                  onRetry: () {},
                  copyButtonKey: _copy,
                  keyValueKey: _viewer,
                  showTitle: true,
                  initialFormat: format,
                  type: selectedType,
                  onSelectType: (type) => setState(() => selectedType = type),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, bool incoming) async {
  final choice = find.byKey(
    ValueKey('viewing_key_choose_${incoming ? 'incoming' : 'full'}'),
  );
  if (choice.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('test_back')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUp(
    () =>
        SensitiveClipboard.debugExpirationDelay = (_) =>
            Completer<void>().future,
  );
  tearDown(() {
    SensitiveClipboard.debugExpirationDelay = null;
    SensitiveClipboard.debugCancelPendingExpiration();
  });
  for (final width in [361.0, 440.0]) {
    testWidgets(
      'text shows the whole key at ${width}px without nested scroll',
      (tester) async {
        await _pump(tester, size: const Size(1080, 720), contentWidth: width);
        for (final incoming in [false, true]) {
          await _select(tester, incoming);
          await tester.tap(
            find.byKey(const ValueKey('viewing_key_format_text')),
          );
          await tester.pumpAndSettle();
          final textScroll = find.descendant(
            of: find.byType(EditableText),
            matching: find.byType(Scrollable),
          );
          final position = tester.state<ScrollableState>(textScroll).position;
          expect(
            position.maxScrollExtent,
            0,
            reason: 'The full ${incoming ? 'incoming' : 'full'} key must fit',
          );
          final editable = tester.getRect(find.byType(EditableText));
          final viewer = tester.getRect(find.byKey(_viewer));
          expect(viewer.contains(editable.topLeft), isTrue);
          expect(viewer.contains(editable.bottomRight), isTrue);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('choosing access is required before showing any key', (
    tester,
  ) async {
    await _pump(tester, type: null);
    expect(find.byType(RequestQrSurface), findsNothing);
    expect(find.byKey(_copy), findsNothing);
    expect(find.text(viewingKeyChoiceSharingWarning), findsOneWidget);
    await _select(tester, true);
    expect(find.text(viewingKeyChoiceSharingWarning), findsNothing);
    expect(find.text('Incoming key'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewing_key_choose_full')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('test_back')));
    await tester.pumpAndSettle();
    expect(find.byType(RequestQrSurface), findsNothing);
    expect(find.byKey(_copy), findsNothing);
  });
  testWidgets('rapid page and format reversals settle on the current key', (
    tester,
  ) async {
    await _pump(tester, type: null);
    await tester.tap(find.byKey(const ValueKey('viewing_key_choose_full')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('test_back')));
    await tester.pump();
    expect(find.byKey(_copy).hitTestable(), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('viewing_key_choose_incoming')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const ValueKey('viewing_key_format_qr')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<RequestQrSurface>(find.byType(RequestQrSurface)).data,
      _incoming,
    );
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion disables flow and format fades', (tester) async {
    await _pump(tester, type: null, reducedMotion: true);
    await _select(tester, false);
    await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
    await tester.pumpAndSettle();
    for (final transition in tester.widgetList<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    )) {
      expect(transition.duration, Duration.zero);
    }
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      _full,
    );
  });
  testWidgets('copy confirms completion and repeated copies extend feedback', (
    tester,
  ) async {
    var pending = Completer<void>();
    var writes = 0;
    await _pump(
      tester,
      onCopy: (_) {
        writes++;
        return pending.future;
      },
    );
    final initial = tester.getRect(find.byKey(_copy));
    final icon = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.copy,
      ),
    );
    await tester.tap(find.byKey(_copy));
    await tester.pump();
    expect(find.text('Copied'), findsNothing);
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));
    final midwayIcon = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.check,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1440));
    final settledIcon = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.check,
      ),
    );
    expect(midwayIcon.left, greaterThan(icon.left));
    expect(midwayIcon.left, lessThan(settledIcon.left));
    expect(settledIcon.top, icon.top);
    pending = Completer<void>()..complete();
    await tester.tap(find.byKey(_copy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Copied'), findsOneWidget);
    expect(writes, 2);
    expect(tester.getRect(find.byKey(_copy)), initial);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Copy viewing key'), findsOneWidget);
  });
  testWidgets('copy failure offers retry without claiming success', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      onCopy: (_) async {
        if (++attempts == 1) throw StateError('clipboard denied');
      },
    );
    await tester.tap(find.byKey(_copy));
    await tester.pump();
    expect(find.text('Copied'), findsNothing);
    expect(find.text('Try copying again'), findsOneWidget);
    await tester.tap(find.byKey(_copy));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('QR is the default and copy has an isolated button label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(
      tester.widget<RequestQrSurface>(find.byType(RequestQrSurface)).data,
      _full,
    );
    final data = tester.getSemantics(find.byKey(_copy)).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isImage, isFalse);
    expect(data.label, 'Copy viewing key');
    handle.dispose();
  });
  testWidgets('copy remains reachable with Tab and Enter', (tester) async {
    final copied = <String>[];
    await _pump(
      tester,
      onCopy: (value) async {
        copied.add(value);
      },
    );
    await tester.ensureVisible(find.byKey(_copy));
    final node = Focus.of(tester.element(find.text('Copy viewing key')));
    for (var i = 0; i < 10 && !node.hasPrimaryFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(copied, [_full]);
  });
  testWidgets('selected key stays in sync across QR, text and copy', (
    tester,
  ) async {
    final copied = <String>[];
    await _pump(
      tester,
      onCopy: (value) async {
        copied.add(value);
      },
    );
    for (final incoming in [false, true, false]) {
      await _select(tester, incoming);
      final value = incoming ? _incoming : _full;
      final initial = tester.getRect(find.byKey(_copy));
      expect(
        tester.widget<RequestQrSurface>(find.byType(RequestQrSurface)).data,
        value,
      );
      expect(tester.getRect(find.byKey(_copy)), initial);
      await tester.tap(find.byKey(const ValueKey('viewing_key_format_text')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        value,
      );
      final textCopy = tester.getRect(find.byKey(_copy));
      expect(textCopy.size, initial.size);
      expect(
        textCopy.top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(_viewer)).bottom + 24),
      );
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(copied.last, value);
      await tester.tap(find.byKey(const ValueKey('viewing_key_format_qr')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_copy)), initial);
    }
  });
  testWidgets('full warning is absent from incoming accessibility content', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final warning = find.bySemanticsLabel(RegExp(viewingKeyWarningTitle));
    expect(warning, findsWidgets);
    expect(
      find.text('Share only with people or services you trust.'),
      findsNothing,
    );
    await _select(tester, true);
    expect(warning, findsNothing);
    expect(
      find.text('Share only with people or services you trust.'),
      findsNothing,
    );
    expect(find.text(incomingViewingKeyWarningTitle), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Reveals past and future incoming payments'),
      ),
      findsWidgets,
    );
    handle.dispose();
  });
  for (final format in ViewingKeyFormat.values) {
    testWidgets(
      '320px at 200 percent keeps ${format.name} and copy reachable',
      (tester) async {
        await _pump(
          tester,
          size: const Size(320, 568),
          scale: 2,
          format: format,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(_viewer));
        await tester.pump();
        final r = tester.getRect(find.byKey(_viewer));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(320));
        await tester.ensureVisible(find.byKey(_copy));
        await tester.pump();
        expect(find.byKey(_copy).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('text selection keyboard copy uses the expiring clipboard', (
    tester,
  ) async {
    final copied = <String>[];
    var expirations = 0;
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
    addTearDown(
      () => SensitiveClipboard.debugSupportsNativeClipboardOverride = null,
    );
    SensitiveClipboard.debugExpirationDelay = (_) {
      expirations++;
      return Completer<void>().future;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pump(tester, format: ViewingKeyFormat.text);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied, [_full.substring(0, 12)]);
    expect(expirations, 1);
  });
  testWidgets('key choices remain usable at 320px and 200 percent text', (
    tester,
  ) async {
    await _pump(tester, size: const Size(320, 568), scale: 2);
    await _select(tester, true);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<RequestQrSurface>(find.byType(RequestQrSurface)).data,
      _incoming,
    );
  });
}
