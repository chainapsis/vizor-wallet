import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_calendar_overlay.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';

void main() {
  testWidgets('birthday tab labels show a click cursor', (tester) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(_birthdayHarness());
    await tester.pump();

    expect(_cursorForText(tester, 'Enter the date'), SystemMouseCursors.click);
    expect(
      _cursorForText(tester, 'Enter the block height'),
      SystemMouseCursors.click,
    );
  });

  testWidgets('birthday date field shows a click cursor when enabled', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(_birthdayHarness());
    await tester.pump();
    await tester.pump();

    expect(_cursorForText(tester, 'mm/dd/yyyy'), SystemMouseCursors.click);
  });

  testWidgets('birthday date field opens before endpoint metadata finishes', (
    tester,
  ) async {
    final metadataCompleter = Completer<ImportBirthdayMetadata>();
    addTearDown(() {
      if (!metadataCompleter.isCompleted) {
        metadataCompleter.complete(_metadataFixture());
      }
    });

    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _birthdayHarness(
        failoverBuilder: () => _PendingMetadataRpcEndpointFailoverNotifier(
          metadataCompleter.future,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('mm/dd/yyyy'));
    await tester.pump();

    expect(find.byType(ImportBirthdayCalendarOverlay), findsOneWidget);

    metadataCompleter.complete(_metadataFixture());
    await tester.pump();
  });

  testWidgets('block height error state shows the design message', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _birthdayHarness(
        args: const ImportBirthdayArgs(
          mnemonic: 'test mnemonic',
          initialBirthdayHeight: 312009123,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final errorText = find.text("That doesn't look like a valid block height.");
    expect(errorText, findsOneWidget);

    final textWidget = tester.widget<Text>(errorText);
    expect(
      textWidget.style?.color,
      AppThemeData.light.colors.border.utilityDestructive,
    );
    expect(textWidget.style?.fontWeight, FontWeight.w400);
  });
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1512, 982));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _birthdayHarness({
  ImportBirthdayArgs args = const ImportBirthdayArgs(mnemonic: 'test mnemonic'),
  RpcEndpointFailoverNotifier Function()? failoverBuilder,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      rpcEndpointFailoverProvider.overrideWith(
        failoverBuilder ?? _FakeRpcEndpointFailoverNotifier.new,
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
        child: Material(
          type: MaterialType.transparency,
          child: AppTheme(
            data: AppThemeData.light,
            child: ImportWalletBirthdayScreen(args: args),
          ),
        ),
      ),
    ),
  );
}

MouseCursor _cursorForText(WidgetTester tester, String text) {
  final mouseRegion = find.ancestor(
    of: find.text(text),
    matching: find.byType(MouseRegion),
  );
  expect(mouseRegion, findsOneWidget);
  return tester.widget<MouseRegion>(mouseRegion).cursor;
}

ImportBirthdayMetadata _metadataFixture() {
  return ImportBirthdayMetadata(
    saplingActivationHeight: 419200,
    saplingActivationDate: DateTime(2016, 10, 28),
    tipHeight: 3336000,
    tipDate: DateTime(2026, 5, 11),
  );
}

class _FakeRpcEndpointFailoverNotifier extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return _metadataFixture() as T;
    }
    return action(state.current);
  }
}

class _PendingMetadataRpcEndpointFailoverNotifier
    extends RpcEndpointFailoverNotifier {
  _PendingMetadataRpcEndpointFailoverNotifier(this.metadata);

  final Future<ImportBirthdayMetadata> metadata;

  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return await metadata as T;
    }
    return action(state.current);
  }
}
