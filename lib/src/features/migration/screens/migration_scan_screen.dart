import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../migration_copy.dart';

typedef MigrationScanScannerBuilder =
    Widget Function({
      required bool decoding,
      required String? error,
      required ValueChanged<Object> onDecodeError,
      required ValueChanged<ScanResult> onComplete,
    });

/// The completed scan of a Keystone migration signing response: the UR type
/// that was scanned (`zcash-batch-sig-result` or the legacy `zcash-sign-result`) and
/// its raw CBOR payload. The migration screen routes decoding on the type.
class MigrationSignedQrResult {
  const MigrationSignedQrResult({required this.urType, required this.cbor});

  final String urType;
  final Uint8List cbor;
}

class MigrationScanScreen extends ConsumerStatefulWidget {
  const MigrationScanScreen({this.scannerBuilder, super.key});

  /// Overrides scanner construction for tests so route behavior can be
  /// exercised without starting the camera plugin.
  final MigrationScanScannerBuilder? scannerBuilder;

  @override
  ConsumerState<MigrationScanScreen> createState() =>
      _MigrationScanScreenState();
}

class _MigrationScanScreenState extends ConsumerState<MigrationScanScreen> {
  // Newer migration firmware returns the compact signatures-only
  // `zcash-batch-sig-result` response. Current ForgeBox firmware still returns the
  // older `zcash-sign-result` envelope, which the migration flow normalizes
  // after scanning.
  static const _batchSigResultUrType = 'zcash-batch-sig-result';
  static const _signResultUrType = 'zcash-sign-result';

  bool _decoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  void _handleComplete(ScanResult result) {
    if (_decoding) return;
    setState(() => _decoding = true);
    final signedQr = MigrationSignedQrResult(
      urType: result.urType,
      cbor: Uint8List.fromList(result.data),
    );
    if (context.canPop()) {
      context.pop(signedQr);
      return;
    }
    context.go('/migration');
  }

  Widget _buildScanner() {
    final scannerBuilder = widget.scannerBuilder;
    if (scannerBuilder != null) {
      return scannerBuilder(
        decoding: _decoding,
        error: _error,
        onDecodeError: _handleDecodeError,
        onComplete: _handleComplete,
      );
    }

    return KeystoneQrScannerCard(
      expectedUrType: _batchSigResultUrType,
      additionalExpectedUrTypes: const [_signResultUrType],
      decoding: _decoding,
      error: _error,
      onProgress: (_) {},
      onDecodeError: _handleDecodeError,
      onComplete: _handleComplete,
      decodingLabel: MigrationCopy.scanDecodingLabel,
      unavailableMessage: MigrationCopy.scanUnavailable,
    );
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed migration QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() => _error = message);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/migration');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBackLink(label: 'Back', onTap: _goBack),
            const SizedBox(height: AppSpacing.s),
            Text(
              MigrationCopy.scanTitle,
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.scanBody,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: Center(child: _buildScanner())),
          ],
        ),
      ),
    );
  }
}
