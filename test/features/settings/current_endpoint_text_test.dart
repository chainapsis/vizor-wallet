import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/custom_endpoint_settings_panel.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_latency_provider.dart';

Widget _app(RpcEndpointConfig preference, {RpcEndpointConfig? effective}) =>
    MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: Scaffold(
        body: CurrentEndpointText(
          current: preference,
          effectiveEndpoint: effective,
          automaticReady: effective != null,
          latencyState: const RpcEndpointLatencyState(),
        ),
      ),
    );

void main() {
  testWidgets(
    'automatic intent never displays its compatibility host as current',
    (tester) async {
      await tester.pumpWidget(_app(defaultRpcEndpointConfig('main')));
      expect(
        find.text('Current: Automatic', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('us.zec.stardust.rest', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets('automatic mode shows the resolved endpoint', (tester) async {
    await tester.pumpWidget(
      _app(
        defaultRpcEndpointConfig('main'),
        effective: const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://kr.zec.stardust.rest:443',
          presetId: 'kr-zec-stardust',
        ),
      ),
    );
    expect(
      find.text(
        'Current: Automatic · kr.zec.stardust.rest:443',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('manual US server is not labeled as the default policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://us.zec.stardust.rest:443',
          presetId: kManualUsRpcEndpointPresetId,
        ),
      ),
    );
    expect(
      find.text('Current: us.zec.stardust.rest:443', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('(Default)', findRichText: true), findsNothing);
  });
}
