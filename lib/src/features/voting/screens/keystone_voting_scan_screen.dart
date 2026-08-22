import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';

class KeystoneVotingScanScreen extends StatelessWidget {
  const KeystoneVotingScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppDesktopShell(
      sidebar: AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            AppPaneToolbar(),
            Expanded(child: KeystoneVotingScanView()),
          ],
        ),
      ),
    );
  }
}

class KeystoneVotingScanView extends ConsumerStatefulWidget {
  const KeystoneVotingScanView({super.key});

  @override
  ConsumerState<KeystoneVotingScanView> createState() =>
      _KeystoneVotingScanViewState();
}

class _KeystoneVotingScanViewState
    extends ConsumerState<KeystoneVotingScanView> {
  bool _decoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kAppFormFactor == AppFormFactor.desktop) {
        ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      }
    });
  }

  void _handleScanComplete(ScanResult result) {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
    });

    if (!mounted) return;
    context.pop(result.data);
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed voting QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.s,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scan voting signature',
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Hold the Keystone QR code steady in front of your camera',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.base),
            KeystoneQrScannerCard(
              expectedUrType: 'zcash-batch-sig-result',
              decoding: _decoding,
              error: _error,
              onProgress: (progress) {
                if (!mounted) return;
                setState(() {
                  if (progress > 0) _error = null;
                });
              },
              onDecodeError: _handleDecodeError,
              onComplete: _handleScanComplete,
              decodingLabel: 'Reading signature...',
              unavailableMessage:
                  'Keystone voting uses camera QR scanning only. Connect a camera and try again.',
            ),
          ],
        ),
      ),
    );
  }
}
