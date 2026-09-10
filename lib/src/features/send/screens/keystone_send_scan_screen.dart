import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/navigation/payment_uri_busy_surface_hold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';

class KeystoneSendScanArgs {
  const KeystoneSendScanArgs({
    this.expectedUrType = 'zcash-pczt',
    this.unexpectedUrMessage =
        'Open the signed transaction QR on Keystone, then scan again.',
    this.decodePcztResponse = true,
    this.suppressSidebarSelection = false,
  });

  const KeystoneSendScanArgs.batch({this.suppressSidebarSelection = false})
    : expectedUrType = 'zcash-batch-sig-result',
      unexpectedUrMessage =
          'Open the signature result QR on Keystone, then scan again.',
      decodePcztResponse = false;

  final String expectedUrType;
  final String unexpectedUrMessage;
  final bool decodePcztResponse;
  final bool suppressSidebarSelection;
}

class KeystoneSendScanScreen extends ConsumerStatefulWidget {
  const KeystoneSendScanScreen({
    this.args = const KeystoneSendScanArgs(),
    super.key,
  });

  final KeystoneSendScanArgs args;

  @override
  ConsumerState<KeystoneSendScanScreen> createState() =>
      _KeystoneSendScanScreenState();
}

// The device is showing the signed-transaction QR this screen's camera is
// reading. A payment-request card over it would scrim a live scan, so the
// screen holds the busy-surface latch for as long as it is mounted.
class _KeystoneSendScanScreenState extends ConsumerState<KeystoneSendScanScreen>
    with PaymentUriBusySurfaceHoldMixin {
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

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
    });

    try {
      final response = widget.args.decodePcztResponse
          ? await rust_keystone.decodePcztFromCbor(cbor: result.data)
          : result.data;
      if (!mounted) return;
      context.pop(response);
    } catch (error, stackTrace) {
      log(
        'KeystoneSendScanScreen: signed response decode error: '
        '$error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error =
            'This QR code could not be decoded as a Keystone transaction signature.';
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? widget.args.unexpectedUrMessage
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/send');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: AppMainSidebar(
        suppressActiveSelection: widget.args.suppressSidebarSelection,
      ),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxs,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(label: 'Back', onTap: _goBack),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Scan QR Code',
                        style: AppTypography.displaySmall.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Hold the QR code steady in front of your camera',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      KeystoneQrScannerCard(
                        expectedUrType: widget.args.expectedUrType,
                        decoding: _decoding,
                        error: _error,
                        onProgress: (progress) {
                          if (!mounted) return;
                          setState(() {
                            if (progress > 0) _error = null;
                          });
                        },
                        onDecodeError: _handleDecodeError,
                        onComplete: (result) =>
                            unawaited(_handleScanComplete(result)),
                        decodingLabel: 'Reading signature...',
                        unavailableMessage:
                            'Keystone signing uses camera QR scanning only. Connect a camera and try again.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
