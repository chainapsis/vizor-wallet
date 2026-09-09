import 'package:flutter/material.dart' show Material, MaterialApp, Dialog;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_error_messages.dart';
import 'package:zcash_wallet/src/features/settings/widgets/settings_pane_backdrop.dart';
import 'package:zcash_wallet/widgetbook/ledger_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';

const _mobileTokens = kAppFormFactor == AppFormFactor.mobile;

void main() {
  test(
    'Ledger catalog keeps one entry per flow in the compiled form factor',
    () {
      Iterable<String> names(WidgetbookNode node) sync* {
        yield node.name;
        for (final child in node.children ?? <WidgetbookNode>[]) {
          yield* names(child);
        }
      }

      final entries = names(buildLedgerWidgetbookFolder()).toList();
      expect(
        entries,
        containsAll([
          'Transfer limits',
          'Recovery flow',
          'Connect Ledger',
          'Additional account',
          'Account groups',
          'Recovery information',
          'Rename group',
          'Device approval',
          'Bundle approval',
        ]),
      );
      expect(
        entries.where(
          (name) =>
              name.startsWith('Design ') ||
              name.contains('Compare inline') ||
              name.contains('Integrated field') ||
              name.contains('Amount tile') ||
              name.contains('Inline assist') ||
              name == 'Flow gallery' ||
              name == 'Device app prompt',
        ),
        isEmpty,
      );
      expect(entries.where((name) => name == 'Connect Ledger'), hasLength(1));
      expect(entries, isNot(contains(_mobileTokens ? 'Desktop' : 'Mobile')));
      expect(entries.contains('Mobile device picker'), _mobileTokens);
    },
  );

  setUpAll(loadFigmaCompareFonts);
  testWidgets('approved Ledger previews render with isolated preview data', (
    tester,
  ) async {
    // Each Widgetbook binary exposes only its compiled token form factor.
    // Render the same routes users can select in that binary.
    for (final mobile in [_mobileTokens]) {
      for (final screen in [
        'Connect Ledger',
        'Add another account',
        'Open device app',
        'Approve transaction',
        'Slow response',
        'Reconnect',
        'Ready to continue',
        'Recovery information',
        'Account groups',
        'Rename group',
        'Voting approval',
        'Devices found',
        'No devices',
        'Bluetooth permission',
      ]) {
        await _pumpUseCase(
          tester,
          (_) => buildLedgerFlowPreview(screen: screen, mobile: mobile),
        );
        await _pumpAsyncState(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: '$screen mobile=$mobile',
        );
        if (screen == 'Reconnect') {
          expect(find.text('Let’s reconnect your Ledger'), findsOneWidget);
          expect(find.text('Connection needed'), findsNothing);
          expect(find.text('Reconnect'), findsOneWidget);
        }
        const captureDir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
        if (captureDir.isNotEmpty &&
            const [
              'Connect Ledger',
              'Account groups',
              'Approve transaction',
              'Reconnect',
              'Recovery information',
              'Voting approval',
            ].contains(screen)) {
          await expectLater(
            find.byKey(const ValueKey('ledger_preview_capture')),
            matchesGoldenFile(
              Uri.file(
                '$captureDir/${screen.toLowerCase().replaceAll(' ', '-')}.png',
              ),
            ),
          );
        }
        if (screen == 'Connect Ledger' || screen == 'Add another account') {
          final prefix = mobile ? 'mobile_' : '';
          final disclosure = find.byKey(
            ValueKey('${prefix}ledger_advanced_options_disclosure'),
          );
          await tester.ensureVisible(disclosure);
          await tester.tap(disclosure);
          await tester.pump(const Duration(milliseconds: 300));
          final input = find.byKey(
            ValueKey('${prefix}ledger_account_index_field'),
          );
          if (screen == 'Add another account') {
            await tester.enterText(input, '2');
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              find.text('Index 2 is already used by this Ledger wallet.'),
              findsOneWidget,
            );
          }
          final message = find.byKey(
            ValueKey('${prefix}ledger_account_index_message'),
          );
          await tester.ensureVisible(message);
          await tester.pump(const Duration(milliseconds: 300));
          if (mobile) {
            expect(
              tester.getRect(message).bottom,
              lessThan(
                tester
                    .getRect(
                      find.byKey(const ValueKey('mobile_ledger_import_button')),
                    )
                    .top,
              ),
            );
          }
          if (captureDir.isNotEmpty) {
            await expectLater(
              find.byKey(const ValueKey('ledger_preview_capture')),
              matchesGoldenFile(
                Uri.file(
                  '$captureDir/${screen == 'Connect Ledger' ? 'account-index' : 'duplicate-index'}.png',
                ),
              ),
            );
          }
          expect(tester.takeException(), isNull);
        }
        if (mobile) {
          final frame = find.byKey(const ValueKey('ledger_flow_mobile_frame'));
          expect(tester.getSize(frame), const Size(393, 852));
          expect(tester.getCenter(frame).dx, 640);
          if (screen == 'Rename group') {
            await tester.tap(find.text('Open rename sheet'));
            await tester.pumpAndSettle();
            final nameField = find.byKey(
              const ValueKey('mobile_ledger_wallet_name'),
            );
            expect(nameField, findsOneWidget);
            expect(tester.getSize(nameField).width, lessThanOrEqualTo(393));
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
        }
      }
    }
  });

  testWidgets('initial Ledger preview continues without a device request', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerFlowPreview(
        screen: 'Connect Ledger',
        mobile: _mobileTokens,
      ),
    );
    await _pumpAsyncState(tester);
    await _connectPreviewLedger(tester);
    await tester.pump(const Duration(seconds: 1));
    await _pumpAsyncState(tester);
    expect(find.textContaining('Connection approved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('additional Ledger preview ends before importing an account', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerFlowPreview(
        screen: 'Add another account',
        mobile: _mobileTokens,
      ),
    );
    await _pumpAsyncState(tester);
    await _connectPreviewLedger(tester);
    await tester.pump(const Duration(seconds: 1));
    await _pumpAsyncState(tester);
    expect(
      find.text('Navigated to /onboarding/ledger/birthday'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  if (!_mobileTokens) {
    testWidgets(
      'connection menu preserves its theme outside the preview navigator',
      (tester) async {
        await _pumpUseCase(
          tester,
          (_) =>
              buildLedgerFlowPreview(screen: 'Account groups', mobile: false),
          themeInsideHome: true,
        );
        await _pumpAsyncState(tester);
        final menu = find.byKey(
          const ValueKey('accounts_row_menu_button_preview-ledger-0'),
        );
        await tester.tap(menu);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Ledger connection'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsOneWidget);
        const captureDir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
        if (captureDir.isNotEmpty) {
          await expectLater(
            find.byKey(const ValueKey('ledger_preview_capture')),
            matchesGoldenFile(Uri.file('$captureDir/ledger-connection.png')),
          );
        }
        await tester.tap(find.text('USB'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Dialog), findsNothing);
        await tester.tap(menu);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Ledger connection'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final selected = find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
        );
        expect(
          find.descendant(of: selected, matching: find.text('USB')),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('recovery card renders without artwork in light and dark themes', (
    tester,
  ) async {
    for (final theme in [AppThemeData.light, AppThemeData.dark]) {
      await _pumpUseCase(
        tester,
        (_) => buildLedgerFlowPreview(
          screen: 'Recovery information',
          mobile: _mobileTokens,
        ),
        theme: theme,
      );
      await _pumpAsyncState(tester);
      expect(find.byType(SettingsPaneBackdrop), findsNothing);
      if (!_mobileTokens) {
        final card = tester.widget<Container>(
          find.byKey(const ValueKey('hardware_recovery_information_card')),
        );
        expect(
          (card.decoration! as BoxDecoration).color,
          theme.colors.background.ground,
        );
      }
      expect(tester.takeException(), isNull);
      const dir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
      if (dir.isNotEmpty) {
        await expectLater(
          find.byKey(const ValueKey('ledger_preview_capture')),
          matchesGoldenFile(
            Uri.file(
              '$dir/recovery-${theme == AppThemeData.dark ? 'dark' : 'light'}.png',
            ),
          ),
        );
      }
    }
  });

  testWidgets('recovery values copy with confirmation and reset', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await _pumpUseCase(
      tester,
      (_) => buildLedgerFlowPreview(
        screen: 'Recovery information',
        mobile: _mobileTokens,
      ),
    );
    await _pumpAsyncState(tester);
    for (final entry in {
      'Account index': '0',
      'Birthday date': 'July 28, 2026',
      'Birthday block height': '2870000',
    }.entries) {
      final button = find.byKey(ValueKey('copy_${entry.key}'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(copied.last, entry.value);
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(of: button, matching: find.byType(AppIcon)),
            )
            .name,
        AppIcons.check,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(of: button, matching: find.byType(AppIcon)),
            )
            .name,
        AppIcons.copy,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recovery preview contains metadata without profile or connection controls',
    (tester) async {
      await _pumpUseCase(
        tester,
        (_) => buildLedgerFlowPreview(
          screen: 'Recovery information',
          mobile: _mobileTokens,
        ),
      );
      await _pumpAsyncState(tester);
      expect(find.text('Account index'), findsOneWidget);
      expect(find.text('Birthday date'), findsOneWidget);
      expect(find.text('July 28, 2026'), findsOneWidget);
      expect(find.text('Birthday block height'), findsOneWidget);
      final card = find.byKey(
        const ValueKey('hardware_recovery_information_card'),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Account index')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Birthday block height')),
        findsOneWidget,
      );
      expect(find.byType(SettingsPaneBackdrop), findsNothing);
      expect(find.text('Ledger connection'), findsNothing);
      expect(
        find.byKey(const ValueKey('ledger_details_account_name')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ledger_add_another_account_button')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new signing states fit the mobile preview and lock cleanup actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final phase in [
        LedgerSigningModalPhase.connecting,
        LedgerSigningModalPhase.coolingDown,
        LedgerSigningModalPhase.cancelling,
        LedgerSigningModalPhase.reconnecting,
        LedgerSigningModalPhase.cancelled,
        LedgerSigningModalPhase.readyToRetry,
      ]) {
        await _pumpUseCase(
          tester,
          (_) => buildLedgerSigningPreview(phase: phase, mobile: true),
        );
        expect(tester.takeException(), isNull, reason: phase.name);
        if (phase == LedgerSigningModalPhase.cancelling ||
            phase == LedgerSigningModalPhase.reconnecting) {
          expect(find.text('Try again'), findsNothing);
          expect(find.text('Cancel'), findsOneWidget);
          final buttons = tester.widgetList<AppButton>(
            find.descendant(
              of: find.byType(LedgerSigningModal),
              matching: find.byType(AppButton),
            ),
          );
          expect(buttons.every((button) => button.onPressed == null), isTrue);
        }
      }
    },
  );

  testWidgets('recovery waits for cleanup and never signs on reconnect', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpUseCase(tester, (_) => const LedgerSigningRecoveryPreview());
    expect(find.text('Getting ready'), findsOneWidget);
    await tester.tap(find.text('Simulate 3-second guard complete'));
    await tester.pump();
    expect(find.text('Getting ready'), findsOneWidget);
    await tester.tap(find.text('Simulate request sent'));
    await tester.pump();
    await tester.tap(find.text('Simulate slow response'));
    await tester.pump();
    expect(find.textContaining('No request on your Ledger?'), findsOneWidget);
    await tester.tap(find.text('Simulate timeout'));
    await tester.pump();
    expect(find.text('Finishing your request'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Reconnect'), findsNothing);
    await tester.tap(find.text('Simulate previous request cleared'));
    await tester.pump();
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    expect(find.text('Reconnecting your Ledger'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.tap(find.text('Simulate connected'));
    await tester.pump();
    expect(find.text('Review on your Ledger'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Ledger folder keeps its playgrounds separate from generic screens', () {
    final folder = buildLedgerWidgetbookFolder();

    expect(folder.name, 'Ledger');
    final details = folder.children!
        .firstWhere((child) => child.name == 'Accounts')
        .children!
        .firstWhere((child) => child.name == 'Recovery information');
    expect(details.leaves.map((leaf) => leaf.name), [
      kAppFormFactor == AppFormFactor.mobile ? 'Mobile' : 'Desktop',
    ]);
    expect(
      folder.children!.map((child) => child.name),
      containsAll([
        'Onboarding & import',
        'Accounts',
        'Signing',
        if (_mobileTokens) 'Mobile device picker',
        'Voting',
      ]),
    );
    expect(
      folder.leaves.map((leaf) => leaf.name),
      containsAll([
        _mobileTokens ? 'Mobile' : 'Desktop',
        'Playground',
        'Recovery flow',
        if (_mobileTokens) ...['Devices found', 'Empty', 'Permission denied'],
      ]),
    );
    expect(folder.leaves, hasLength(_mobileTokens ? 17 : 14));
  });

  testWidgets('capacity guidance renders each transfer context', (
    tester,
  ) async {
    for (final kind in [
      LedgerRequestKind.send,
      LedgerRequestKind.swap,
      LedgerRequestKind.payment,
      LedgerRequestKind.shield,
      LedgerRequestKind.migration,
    ]) {
      await _pumpUseCase(
        tester,
        (_) => buildLedgerSigningPreview(
          phase: LedgerSigningModalPhase.failed,
          failureMode: LedgerSigningPlaygroundFailure.capacity,
          capacityRequestKind: kind,
          mobile: _mobileTokens,
        ),
      );
      await tester.pumpAndSettle();
        expect(find.text(kLedgerSmallerTransferTitle), findsOneWidget);
        expect(find.text('Try another connection'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(tester.takeException(), isNull, reason: kind.name);
      const captureDir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
      if (captureDir.isNotEmpty) {
        await expectLater(
          find.byKey(const ValueKey('ledger_preview_capture')),
          matchesGoldenFile(Uri.file('$captureDir/capacity-${kind.name}.png')),
        );
      }
    }
  });

  testWidgets('signing preview exposes multi-transaction Ledger review', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerSigningPreview(
        phase: LedgerSigningModalPhase.awaitingDevice,
        roundNumber: 2,
        roundCount: 3,
      ),
    );

    expect(find.text('Your turn on Ledger'), findsOne);
    expect(find.text('Approval 2 of 3'), findsOne);
    expect(find.text('Zcash · Ledger'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing preview exposes failed readiness guidance', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerSigningPreview(
        phase: LedgerSigningModalPhase.failed,
        readiness: LedgerSigningPlaygroundReadiness.failed,
      ),
    );

    expect(find.text('Ledger needs attention'), findsOne);
    expect(find.text('Action needed'), findsOne);
    expect(
      find.text('Reconnect your Ledger and open the Zcash app.'),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing transport choices update only the preview account', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerSigningPreview(phase: LedgerSigningModalPhase.failed),
    );

    final usb = find.byKey(const ValueKey('ledger_connection_usb'));
    final automatic = find.byKey(const ValueKey('ledger_connection_automatic'));
    final bluetooth = find.byKey(const ValueKey('ledger_connection_bluetooth'));
    expect(tester.getTopLeft(usb).dx, tester.getTopLeft(automatic).dx);
    expect(
      tester.getTopLeft(usb).dy,
      greaterThan(tester.getBottomLeft(automatic).dy),
    );
    expect(
      tester.getTopLeft(bluetooth).dy,
      greaterThan(tester.getBottomLeft(usb).dy),
    );
    expect(tester.widget<AppButton>(usb).variant, AppButtonVariant.secondary);

    await tester.tap(usb);
    await tester.pump();

    expect(tester.widget<AppButton>(usb).variant, AppButtonVariant.primary);
    expect(
      find.byKey(const ValueKey('ledger_connection_selected_usb')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger_connection_selected_automatic')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ledger_connection_selected_bluetooth')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('device picker previews found, empty, and denied states', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildLedgerDevicePickerFoundUseCase);
    await _pumpAsyncState(tester);
    expect(find.text('Ledger Flex'), findsWidgets);
    expect(find.text('Ledger Stax'), findsWidgets);

    await _pumpUseCase(tester, buildLedgerDevicePickerEmptyUseCase);
    await _pumpAsyncState(tester);
    expect(find.text('No Ledger devices found'), findsOne);
    expect(find.text('Try again'), findsOne);

    await _pumpUseCase(tester, buildLedgerDevicePickerPermissionDeniedUseCase);
    await _pumpAsyncState(tester);
    expect(find.text('Could not find your Ledger'), findsOne);
    expect(find.textContaining('Bluetooth permission is required'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voting preview advances through Ledger submission states', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (_) => buildLedgerVotingPreview(
        bundleNumber: 2,
        bundleCount: 3,
        displayMemo: 'Round 7 delegation memo',
      ),
    );

    expect(find.text('Approve voting delegation'), findsOne);
    expect(find.text('Approval 2 of 3'), findsOne);
    expect(find.text('Round 7 delegation memo'), findsOne);
    expect(find.byKey(const ValueKey('ledger_voting_signing_panel')), findsOne);
    expect(find.text('Checking your Ledger'), findsOne);
    expect(find.text('Signing with Keystone'), findsNothing);
    expect(find.text('Signing with Ledger'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Waiting for your approval'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Approval 3 of 3'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ledger_voting_signing_panel')),
      findsNothing,
    );
    expect(find.text('Advance to vote submission'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('1 of 2 ballots submitted'), findsOne);
    expect(find.text('Advance to finalizing'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Complete preview'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    expect(find.text('Restart preview'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('ledger_voting_preview_advance')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ledger_voting_cancel')));
    await tester.pump();
    expect(find.text('Ledger voting approval was cancelled.'), findsOne);
    expect(find.text('Retry'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account details and rename previews use production surfaces', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      _mobileTokens
          ? buildMobileLedgerAccountDetailsUseCase
          : buildLedgerAccountDetailsUseCase,
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      find.text(_mobileTokens ? 'Recovery info' : 'Recovery information'),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('ledger_details_account_name')),
      findsNothing,
    );
    expect(find.text('Account index'), findsOne);
    expect(find.text('2870000'), findsOne);

    await _pumpUseCase(tester, buildLedgerRenameUseCase);
    expect(find.text('Rename group name'), findsOne);
    expect(find.text('Group name'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile account details preview uses the mobile surface', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileLedgerAccountDetailsUseCase);
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Account Details'), findsOne);
    expect(
      find.byKey(const ValueKey('ledger_details_account_name')),
      findsNothing,
    );
    expect(find.text('Birthday block height'), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAsyncState(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _connectPreviewLedger(WidgetTester tester) async {
  if (_mobileTokens) {
    await tester.ensureVisible(find.text('Select Ledger'));
    await tester.tap(find.text('Select Ledger'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_ledger_device_sheet')))
          .width,
      lessThanOrEqualTo(393),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_ledger_device_preview-flex')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
  } else {
    await tester.ensureVisible(
      find.byKey(const ValueKey('ledger_connect_button')),
    );
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
  }
}

Future<void> _pumpUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  bool themeInsideHome = false,
  AppThemeData theme = AppThemeData.light,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('ledger_preview_capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            themeInsideHome ? child! : AppTheme(data: theme, child: child!),
        home: AppTheme(
          data: theme,
          child: Material(
            color: theme.colors.background.window,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
