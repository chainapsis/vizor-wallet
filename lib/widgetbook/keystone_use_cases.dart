// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_scan/widgets/address_qr_scan_modal.dart';
import '../src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import '../src/features/onboarding/mobile/mobile_import_birthday_screen.dart';
import '../src/features/onboarding/mobile/mobile_keystone_scan_card.dart';
import '../src/features/onboarding/mobile/mobile_keystone_screens.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_scaffold.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/providers/account_provider.dart' show AccountState;
import '../src/rust/wallet/keystone.dart' show KeystoneAccountInfo;

Widget buildMobileKeystoneScanRequestingUseCase(BuildContext context) {
  return const _MobileKeystoneInlineScanFrame(
    child: MobileKeystoneScanCardContent(
      key: ValueKey('mobile_keystone_scan_widgetbook_card'),
      status: AddressQrCameraStatus.requesting,
      cameraView: _MobileKeystoneScanCameraPreview(),
      cameraHeight: 464,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileKeystoneScanDeniedUseCase(BuildContext context) {
  return const _MobileKeystoneInlineScanFrame(
    child: MobileKeystoneScanCardContent(
      key: ValueKey('mobile_keystone_scan_widgetbook_card'),
      status: AddressQrCameraStatus.denied,
      cameraView: _MobileKeystoneScanCameraPreview(),
      cameraHeight: 464,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileKeystoneScanActiveUseCase(BuildContext context) {
  return const _MobileKeystoneModalScanFrame(
    child: MobileKeystoneScanCardContent(
      key: ValueKey('mobile_keystone_scan_widgetbook_card'),
      status: AddressQrCameraStatus.active,
      cameraView: _MobileKeystoneScanCameraPreview(),
      cameraHeight: 694,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileKeystoneScanLoadingUseCase(BuildContext context) {
  return const _MobileKeystoneModalScanFrame(
    child: MobileKeystoneScanCardContent(
      key: ValueKey('mobile_keystone_scan_widgetbook_card'),
      status: AddressQrCameraStatus.loading,
      cameraView: _MobileKeystoneScanCameraPreview(),
      cameraHeight: 694,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileKeystoneConnectUseCase(BuildContext context) {
  return const _MobileKeystoneScreenFrame(child: MobileKeystoneIntroScreen());
}

Widget buildMobileKeystoneBirthdayUseCase(BuildContext context) {
  // The Keystone birthday step reuses the shared import birthday screen; we
  // render it directly with `loadChainMetadata: false` so the preview makes
  // no network call, and seed `appBootstrapProvider` so the lazy
  // `rpcEndpointProvider` read (block-height mode) resolves.
  return _MobileKeystoneScreenFrame(
    child: ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_widgetbookBootstrap()),
      ],
      child: MobileImportBirthdayScreen(
        args: const ImportBirthdayArgs(mnemonic: ''),
        loadChainMetadata: false,
        onHeightConfirmed: (_) async {},
      ),
    ),
  );
}

Widget buildMobileKeystoneSelectAccountUseCase(BuildContext context) {
  return const _MobileKeystoneSelectAccountFrame();
}

/// A bare 393×852 phone frame for Keystone onboarding screens that bring
/// their own scaffold.
class _MobileKeystoneScreenFrame extends StatelessWidget {
  const _MobileKeystoneScreenFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 393,
      height: 852,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          viewPadding: EdgeInsets.only(top: 55),
        ),
        child: child,
      ),
    );
  }
}

AppBootstrapState _widgetbookBootstrap() {
  return AppBootstrapState(
    initialLocation: '/onboarding/keystone/birthday',
    initialAccountState: const AccountState(accounts: []),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

/// Renders the real [MobileKeystoneSelectAccountScreen] with the onboarding
/// provider seeded so the radio list shows up without a live Keystone scan
/// (the simulator cannot scan the device QR).
class _MobileKeystoneSelectAccountFrame extends StatelessWidget {
  const _MobileKeystoneSelectAccountFrame();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        keystoneOnboardingProvider.overrideWith(
          _SeededKeystoneOnboardingNotifier.new,
        ),
      ],
      child: const SizedBox(
        width: 393,
        height: 852,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(393, 852),
            viewPadding: EdgeInsets.only(top: 55),
          ),
          child: MobileKeystoneSelectAccountScreen(),
        ),
      ),
    );
  }
}

class _SeededKeystoneOnboardingNotifier extends KeystoneOnboardingNotifier {
  @override
  KeystoneOnboardingState build() {
    final accounts = <KeystoneAccountInfo>[
      for (var i = 0; i < 4; i++)
        KeystoneAccountInfo(
          name: 'Account ${i + 1}',
          ufvk: 'u1asdasdasx0qqqqqqqqqqqqqqqqqq3123llasdasd',
          index: i,
          seedFingerprint: Uint8List.fromList(const [0, 0, 0, 0]),
        ),
    ];
    return KeystoneOnboardingState(
      accounts: accounts,
      selectedAccount: accounts.first,
    );
  }
}

class _MobileKeystoneInlineScanFrame extends StatelessWidget {
  const _MobileKeystoneInlineScanFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 393,
      height: 852,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          viewPadding: EdgeInsets.only(top: 55),
        ),
        child: MobileOnboardingStepScaffold(
          progress: 0.4,
          onBack: _noop,
          title: 'Scan QR Code',
          subtitle: 'Prepare your Keystone wallet',
          scrollable: false,
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    );
  }
}

class _MobileKeystoneModalScanFrame extends StatelessWidget {
  const _MobileKeystoneModalScanFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 393,
      height: 852,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          viewPadding: EdgeInsets.only(top: 55),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const MobileOnboardingStepScaffold(
              progress: 0.4,
              onBack: _noop,
              title: 'Scan QR Code',
              subtitle: 'Prepare your Keystone wallet',
              scrollable: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: MobileKeystoneScanCardContent(
                  status: AddressQrCameraStatus.denied,
                  cameraView: _MobileKeystoneScanCameraPreview(),
                  cameraHeight: 464,
                  onTorch: _noop,
                  onClose: _noop,
                  onRetry: _noop,
                ),
              ),
            ),
            ColoredBox(
              color: colors.background.neutralScrim,
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    MobileModalCard(child: child),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileKeystoneScanCameraPreview extends StatelessWidget {
  const _MobileKeystoneScanCameraPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF111515)),
      child: Center(
        child: SizedBox(
          width: 320,
          height: 320,
          child: PrettyQrView.data(
            data: 'ur:zcash-accounts/1-1/lftadkexamplekeystoneaccountpreview',
            decoration: const PrettyQrDecoration(
              quietZone: PrettyQrQuietZone.zero,
              shape: PrettyQrSmoothSymbol(
                roundFactor: 0,
                color: Color(0xFFEFEDEA),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _noop() {}
