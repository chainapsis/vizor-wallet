@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/payment_links_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';
import '../../support/payment_links_screen_support.dart';

class _LifecycleOperations extends FakePaymentLinkOperations {
  _LifecycleOperations({
    super.prepareClaimGates,
    super.prepareClaimFailures,
    super.longSyncConfirmationRequired,
  });
  late ProviderContainer container;
  int attempts = 0;

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    attempts++;
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    return coordinator.trackPreparation(() async {
      final generation = coordinator.beginPreparation();
      final session = await super.prepareClaim(
        link,
        allowLongSync: allowLongSync,
      );
      coordinator.requirePreparation(generation);
      return session;
    });
  }
}

void main() {
  setUpAll(loadPaymentLinksTestFonts);
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final arrival in ['paused', 'inactive', 'resumed']) {
    final resumedBeforeLink = arrival == 'resumed';
    testWidgets(
      'native gift link waits for mobile resume: arrival=$arrival',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final operations = _LifecycleOperations();
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          bootstrap: homeBootstrap,
          logicalSize: const Size(520, 1100),
        );
        final context = tester.element(find.byType(Scaffold).first);
        final container = ProviderScope.containerOf(context);
        operations.container = container;
        final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(coordinator.acceptsPreparation, isFalse);
        if (arrival != 'paused') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (resumedBeforeLink) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        final delivered = Completer<void>();
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          kIncomingUriChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onUris', [incomingLink.toUri().toString()]),
          ),
          (_) => delivered.complete(),
        );
        await delivered.future;
        if (arrival == 'paused') {
          await tester.pump();
          expect(operations.attempts, 0);
          expect(
            container.read(paymentLinkIntakeProvider).pendingLink,
            isNotNull,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(PaymentLinksScreen), findsOneWidget);
        if (!resumedBeforeLink) {
          expect(operations.attempts, 0);
          expect(
            find.text('Card balance could not be checked. Try again.'),
            findsNothing,
          );
          expect(
            container.read(paymentLinkIntakeProvider).pendingLink,
            isNotNull,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        expect(coordinator.canStartPreparation, isTrue);
        expect(operations.attempts, 1);
        expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
        expect(
          find.text('Card balance could not be checked. Try again.'),
          findsNothing,
        );
        expect(find.byType(PaymentLinkReceivedMobileView), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  const platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  testWidgets('initial inactive lifecycle also defers durable claim recovery', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var recoveries = 0;
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_TestSecurity.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
          recoveries++;
          return const [];
        }),
      ],
    );
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    await tester.pump();
    expect(coordinator.canStartPreparation, isFalse);
    expect(recoveries, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(recoveries, 1);
    container.dispose();
  }, variant: platforms);

  testWidgets('wallet change interruption offers a fresh manual check', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _LifecycleOperations(prepareClaimGates: {1: gate});
    final container = await _openCards(tester, operations);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    final drain = coordinator.quiesceAndDrain();
    gate.complete();
    await drain;
    coordinator.resumeAfterReset();
    await _pumpFrames(tester);
    expect(operations.attempts, 1);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await _pumpFrames(tester);
    expect(operations.attempts, 2);
    expect(find.byType(PaymentLinkReceivedMobileView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('fast foreground return drains the old check before retry', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _LifecycleOperations(prepareClaimGates: {1: gate});
    final container = await _openCards(tester, operations);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    expect(operations.attempts, 1);
    _background(tester);
    _foreground(tester);
    container.read(paymentLinkClaimCoordinatorProvider).resumeForLifecycle();
    container.read(paymentLinkClaimCoordinatorProvider).resumeForLifecycle();
    await _pumpFrames(tester);
    expect(operations.attempts, 1);
    expect(
      container.read(paymentLinkClaimCoordinatorProvider).canStartPreparation,
      isFalse,
    );
    gate.complete();
    await _pumpFrames(tester);
    expect(operations.attempts, 2);
    expect(find.byType(PaymentLinkReceivedMobileView), findsOneWidget);
    expect(
      find.text('Card balance could not be checked. Try again.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('leaving an interrupted preview prevents automatic retry', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _LifecycleOperations(prepareClaimGates: {1: gate});
    final container = await _openCards(tester, operations);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    _background(tester);
    _foreground(tester);
    GoRouter.of(tester.element(find.byType(PaymentLinksScreen))).go('/home');
    await _pumpFrames(tester);
    gate.complete();
    await _pumpFrames(tester);
    expect(operations.attempts, 1);
    expect(find.byType(PaymentLinksScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('a real check failure still requires an explicit retry', (
    tester,
  ) async {
    final operations = _LifecycleOperations(prepareClaimFailures: 1);
    final container = await _openCards(tester, operations);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    expect(find.text('Try again'), findsOneWidget);
    _background(tester);
    _foreground(tester);
    await _pumpFrames(tester);
    expect(operations.attempts, 1);
    await tester.tap(find.text('Try again'));
    await _pumpFrames(tester);
    expect(operations.attempts, 2);
    expect(find.byType(PaymentLinkReceivedMobileView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('locking an active preview returns its link to unlock intake', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _LifecycleOperations(prepareClaimGates: {1: gate});
    final container = await _openCards(tester, operations);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    container.read(appSecurityProvider.notifier).lock();
    await _pumpFrames(tester);
    gate.complete();
    await _pumpFrames(tester);
    expect(
      container
          .read(paymentLinkIntakeProvider)
          .pendingLink
          ?.hasSameCanonicalPayload(incomingLink),
      isTrue,
    );
    expect(operations.attempts, 1);
    expect(find.byType(PaymentLinksScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('locking retains an accepted card even when intake fills', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _LifecycleOperations(prepareClaimGates: {1: gate});
    final container = await _openCards(tester, operations);
    final intake = container.read(paymentLinkIntakeProvider.notifier);
    intake.receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    for (var i = 1; i < kPaymentLinkIntakeQueueCapacity; i++) {
      expect(
        intake.receive(
          VizorPaymentLink(
            network: incomingLink.network,
            address: incomingLink.address,
            amountZatoshi: incomingLink.amountZatoshi + BigInt.from(i),
            mnemonic: incomingLink.mnemonic,
            birthdayHeight: incomingLink.birthdayHeight,
            label: incomingLink.label,
            createdAt: incomingLink.createdAt,
          ).toUri().toString(),
        ),
        PaymentLinkIntakeResult.accepted,
      );
    }
    expect(
      intake.receive(secondIncomingLink.toUri().toString()),
      PaymentLinkIntakeResult.rejected,
    );
    container.read(appSecurityProvider.notifier).lock();
    await tester.pump();
    gate.complete();
    await tester.pump(const Duration(milliseconds: 20));
    // The old route can still be mounted while its cancelled check settles.
    // Its slot must survive that gap until unlock intake owns the Card again.
    expect(
      intake.receive(secondIncomingLink.toUri().toString()),
      PaymentLinkIntakeResult.rejected,
    );
    await _pumpFrames(tester);
    final pending = container.read(paymentLinkIntakeProvider).pendingLinks;
    expect(pending, hasLength(kPaymentLinkIntakeQueueCapacity));
    expect(pending.first.hasSameCanonicalPayload(incomingLink), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('resume retains consent to the longer check', (tester) async {
    final gate = Completer<void>();
    final operations = _LifecycleOperations(
      prepareClaimGates: {2: gate},
      longSyncConfirmationRequired: true,
    );
    final container = await _openCards(tester, operations);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await _pumpFrames(tester);
    await tester.tap(find.text('Check gift card'));
    await _pumpFrames(tester);
    expect(operations.allowLongSyncCalls, [false, true]);
    _background(tester);
    _foreground(tester);
    gate.complete();
    await _pumpFrames(tester);
    expect(operations.allowLongSyncCalls, [false, true, true]);
    expect(find.byType(PaymentLinkReceivedMobileView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);
}

Future<ProviderContainer> _openCards(
  WidgetTester tester,
  _LifecycleOperations operations,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await pumpPaymentLinksScreen(
    tester,
    operations: operations,
    securityNotifier: _TestSecurity(),
    bootstrap: AppBootstrapState(
      initialLocation: paymentLinksBootstrap.initialLocation,
      initialAccountState: paymentLinksBootstrap.initialAccountState,
      initialSyncSnapshot: paymentLinksBootstrap.initialSyncSnapshot,
      network: paymentLinksBootstrap.network,
      rpcEndpointConfig: paymentLinksBootstrap.rpcEndpointConfig,
      themeMode: paymentLinksBootstrap.themeMode,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: false,
      passwordRotationRecoveryFailed: false,
    ),
    logicalSize: const Size(520, 1100),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(PaymentLinksScreen)),
  );
  operations.container = container;
  return container;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _foreground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

class _TestSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}
