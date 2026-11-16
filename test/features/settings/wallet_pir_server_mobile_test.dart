@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_radio_card.dart';
import 'package:zcash_wallet/src/features/settings/widgets/wallet_pir_server_settings.dart';
import 'package:zcash_wallet/src/providers/wallet_pir_server_provider.dart';
import 'package:zcash_wallet/src/services/wallet_pir/wallet_pir_config.dart';

// Reserved example hosts, never contacted.
const _first = WalletPirServerOption(
  label: 'Demo server A',
  baseUrl: 'https://pir-a.example',
);
const _second = WalletPirServerOption(
  label: 'Demo server B',
  baseUrl: 'https://pir-b.example/wallet',
);

final _state = WalletPirServerState(
  source: 'https://pir-config.example/static.json',
  config: WalletPirConfigView(
    scope: 'demo',
    snapshotJson: '{}',
    servers: const [_first, _second],
    selectionState: WalletPirSelectionState.kept,
    selectedBaseUrl: _first.baseUrl,
  ),
  refreshing: false,
);

Widget _harness(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  home: AppTheme(
    data: AppThemeData.light,
    child: Scaffold(
      body: Center(child: SizedBox(width: 345, child: child)),
    ),
  ),
);

void main() {
  testWidgets('a long detail wraps and the card grows to fit it', (
    tester,
  ) async {
    Widget card(String address) => MobileRadioCard(
      title: 'Demo server',
      details: [address, '237ms'],
      selected: false,
      onTap: () {},
    );

    await tester.pumpWidget(_harness(card('pir.example')));
    final short = tester.getSize(find.byType(MobileRadioCard)).height;

    await tester.pumpWidget(
      _harness(card('wallet-pir-secondary-mirror.long-subdomain.example')),
    );
    final long = tester.getSize(find.byType(MobileRadioCard)).height;
    final address = tester.widget<Text>(
      find.text('wallet-pir-secondary-mirror.long-subdomain.example'),
    );

    expect(address.maxLines, isNull);
    expect(address.overflow, isNull);
    expect(long, greaterThan(short));
  });

  testWidgets(
    'mobile marks a server, applies it with Update, and offers Custom server',
    (tester) async {
      String? marked;
      var updates = 0;
      var customOpens = 0;
      Widget view() => WalletPirServerSettingsView(
        state: _state,
        onSelect: (baseUrl) => marked = baseUrl,
        pendingBaseUrl: marked,
        onCustom: () => customOpens++,
        actionButtons: true,
        onUpdate: () => updates++,
      );
      bool selected(String label) => tester
          .widget<MobileRadioCard>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(MobileRadioCard),
            ),
          )
          .selected;

      await tester.pumpWidget(_harness(view()));
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Custom server'), findsOneWidget);
      expect(find.text('Custom server…'), findsNothing);
      expect(selected('Demo server A'), isTrue);

      await tester.tap(find.text('Demo server B'));
      await tester.pumpWidget(_harness(view()));
      expect(marked, _second.baseUrl);
      expect(selected('Demo server A'), isFalse);
      expect(selected('Demo server B'), isTrue);
      expect(updates, 0, reason: 'tapping a card only marks it');

      await tester.tap(find.byKey(const ValueKey('wallet_pir_server_update')));
      expect(updates, 1);

      await tester.tap(
        find.byKey(const ValueKey('wallet_pir_custom_server_option')),
      );
      expect(customOpens, 1);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('wallet_pir_custom_server_option')),
            )
            .variant,
        AppButtonVariant.secondary,
      );
    },
  );
}
