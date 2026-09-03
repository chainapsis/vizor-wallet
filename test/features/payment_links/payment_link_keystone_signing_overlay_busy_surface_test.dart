import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_keystone_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The Gift Card funding overlay is the payment-links counterpart of the home
/// shield and swap deposit overlays: a Keystone reads an animated PCZT QR out
/// of it while `matchedLocation` never leaves `/payment-links`, so only the
/// hold can tell the payment-URI drain that this surface is mid-session.
///
/// Without it, a `zcash:` link arriving mid-signing drops a payment-request
/// card over a QR the device's camera is part-way through reading.
void main() {
  testWidgets('the Gift Card Keystone signing overlay holds the payment-URI '
      'busy latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: PaymentLinkKeystoneSigningOverlay(
        amountZatoshi: BigInt.from(300000),
        sourceAccountUuid: 'account-1',
        onCancel: () {},
        onFundingBroadcast: (_, _) async {},
      ),
      drainExceptions: true,
    );
  });
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      paymentLinkHardwareSigningServiceProvider.overrideWithValue(
        _StalledSigningService(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget Function(Widget) _host(ProviderContainer container) =>
    (child) => UncontrolledProviderScope(
      container: container,
      child: AppTheme(
        data: AppThemeData.dark,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

/// Never resolves, so the overlay stays in its `preparing` phase for the whole
/// test. The latch is about the surface being mounted, not about which phase
/// it reached.
class _StalledSigningService implements PaymentLinkHardwareSigningService {
  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) => Completer<PaymentLinkHardwarePcztDraft>().future;

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async => const [];

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async => const [];

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [];

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {}

  @override
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => Completer<PaymentLinkHardwareFundingResult>().future;
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1paymentlinkoverlay',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
