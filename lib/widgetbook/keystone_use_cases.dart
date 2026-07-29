// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import '../src/features/keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import '../src/features/address_scan/widgets/address_qr_scan_modal.dart';
import '../src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import '../src/features/onboarding/mobile/mobile_import_birthday_screen.dart';
import '../src/features/onboarding/mobile/mobile_keystone_scan_card.dart';
import '../src/features/onboarding/mobile/mobile_keystone_screens.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_scaffold.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/providers/account_provider.dart' show AccountState;
import '../src/rust/wallet/keystone.dart' show KeystoneAccountInfo;
import '../src/services/qr_scanner.dart' show ScanResult;

Widget buildMobileKeystoneScanRequestingUseCase(BuildContext context) {
  return const _MobileKeystoneModalScanFrame(
    child: MobileKeystoneScanCardContent(
      key: ValueKey('mobile_keystone_scan_widgetbook_card'),
      status: AddressQrCameraStatus.requesting,
      cameraView: _MobileKeystoneScanCameraPreview(),
      cameraHeight: 694,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileKeystoneScanDeniedUseCase(BuildContext context) {
  return const _MobileKeystoneModalScanFrame(
    child: MobileKeystoneScanCardContent(
      key: ValueKey('mobile_keystone_scan_widgetbook_card'),
      status: AddressQrCameraStatus.denied,
      cameraView: _MobileKeystoneScanCameraPreview(),
      cameraHeight: 694,
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

Widget buildMobileKeystonePcztQrDefaultUseCase(BuildContext context) {
  return _MobileKeystonePcztQrFrame(
    child: KeystonePcztQrStage(
      phase: KeystonePcztQrStagePhase.ready,
      urParts: _pcztPreviewUrParts(),
      error: null,
    ),
  );
}

Widget buildMobileKeystonePcztQrOptimizedUseCase(BuildContext context) {
  return _MobileKeystonePcztQrFrame(
    child: KeystonePcztQrStage(
      phase: KeystonePcztQrStagePhase.ready,
      urParts: _pcztPreviewUrParts(),
      error: null,
      size: 280,
      scanOptimized: true,
      frameInterval: const Duration(milliseconds: 100),
    ),
  );
}

Widget buildMobileKeystoneSigningLoadingUseCase(BuildContext context) {
  return const _MobileKeystoneSigningFrame(phase: _SigningPreviewPhase.loading);
}

Widget buildMobileKeystoneSigningReadyUseCase(BuildContext context) {
  return const _MobileKeystoneSigningFrame(phase: _SigningPreviewPhase.ready);
}

Widget buildMobileKeystoneSigningScannerUseCase(BuildContext context) {
  return const _MobileKeystoneSigningFrame(phase: _SigningPreviewPhase.scanner);
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
              child: SizedBox.shrink(),
            ),
            IgnorePointer(
              child: ModalBarrier(color: colors.background.neutralScrim),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  MobileModalCard(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileKeystonePcztQrFrame extends StatelessWidget {
  const _MobileKeystonePcztQrFrame({required this.child});

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
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF000000)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  const SizedBox(height: 72),
                  Text(
                    'Confirm transaction',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: const Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Use your Keystone wallet to scan this transaction QR '
                    'code. Follow the steps on your device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: const Color(0xCCFFFFFF),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.background.ground,
                      borderRadius: BorderRadius.circular(AppRadii.large),
                    ),
                    child: child,
                  ),
                  const Spacer(),
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SigningPreviewPhase { loading, ready, scanner }

class _MobileKeystoneSigningFrame extends StatelessWidget {
  const _MobileKeystoneSigningFrame({required this.phase});

  final _SigningPreviewPhase phase;

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
        child: ProviderScope(
          child: MobileKeystonePcztSigningFlow(
            title: 'Confirm transaction',
            description:
                'Use your Keystone wallet to scan this transaction QR code. '
                'Follow the steps on your device.',
            keyPrefix: 'mobile_keystone_signing_widgetbook',
            onCancel: _noop,
            preparePczt: _prepare,
            scannerBuilder: _buildScannerPreview,
            forceScannerActiveForTesting: true,
            startInScannerForTesting: phase == _SigningPreviewPhase.scanner,
            signedPcztDecoder: (_) async => Uint8List.fromList(const [9]),
            onSigned: (_, _, _, _) async {},
            friendlyError: (_) => 'Keystone signing could not be prepared.',
          ),
        ),
      ),
    );
  }

  Future<MobileKeystonePcztSigningPayload> _prepare(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (phase == _SigningPreviewPhase.loading) {
      return Completer<MobileKeystonePcztSigningPayload>().future;
    }
    return MobileKeystonePcztSigningPayload(
      urParts: _pcztPreviewUrParts(),
      pcztWithProofs: Future.value(const [1, 2, 3]),
    );
  }

  Widget _buildScannerPreview(
    BuildContext context,
    ValueChanged<ScanResult> onComplete,
    ValueChanged<int> onProgress,
    Object? scanSessionResetToken,
  ) {
    return _MobileKeystoneSigningCameraPreview(onProgress: onProgress);
  }
}

class _MobileKeystoneSigningCameraPreview extends StatefulWidget {
  const _MobileKeystoneSigningCameraPreview({required this.onProgress});

  final ValueChanged<int> onProgress;

  @override
  State<_MobileKeystoneSigningCameraPreview> createState() =>
      _MobileKeystoneSigningCameraPreviewState();
}

class _MobileKeystoneSigningCameraPreviewState
    extends State<_MobileKeystoneSigningCameraPreview> {
  @override
  void initState() {
    super.initState();
    _emitPreviewProgress();
  }

  @override
  void didUpdateWidget(
    covariant _MobileKeystoneSigningCameraPreview oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onProgress != widget.onProgress) {
      _emitPreviewProgress();
    }
  }

  void _emitPreviewProgress() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onProgress(50);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('mobile_keystone_signing_widgetbook_camera'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060707), Color(0xFF141313), Color(0xFF080808)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: const Alignment(0, 0.18),
            child: Transform.rotate(
              angle: -0.035,
              child: Container(
                width: 244,
                height: 416,
                decoration: BoxDecoration(
                  color: const Color(0xFF101617),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF262B2B), width: 10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 40,
                      offset: Offset(0, 28),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 68, 16, 42),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16212C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: const [
                              _FakeKeystoneAppTile(
                                color: Color(0xFF5BAFA9),
                                label: 'BTC',
                              ),
                              SizedBox(width: 10),
                              _FakeKeystoneAppTile(
                                color: Color(0xFF4B9FB0),
                                label: 'ETH',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: _FakeKeystoneAppTile(
                              color: Color(0xFF52A798),
                              label: 'SOL',
                            ),
                          ),
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3B0),
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.85,
                colors: [Color(0x00000000), Color(0x99000000)],
                stops: [0.45, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FakeKeystoneAppTile extends StatelessWidget {
  const _FakeKeystoneAppTile({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontFamily: 'Geist',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1,
          ),
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

List<String> _pcztPreviewUrParts() {
  const payload =
      'lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcx'
      'hdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcx'
      'hdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcx';
  return [
    for (var i = 1; i <= 12; i++)
      'ur:zcash-pczt/$i-12/$payload${i.toString().padLeft(2, '0')}',
  ];
}

void _noop() {}
