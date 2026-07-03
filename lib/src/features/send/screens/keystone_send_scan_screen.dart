import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';

class KeystoneSendScanScreen extends ConsumerStatefulWidget {
  const KeystoneSendScanScreen({super.key});

  @override
  ConsumerState<KeystoneSendScanScreen> createState() =>
      _KeystoneSendScanScreenState();
}

class _KeystoneSendScanScreenState
    extends ConsumerState<KeystoneSendScanScreen> {
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
      final pcztBytes = await rust_keystone.decodePcztFromCbor(
        cbor: result.data,
      );
      if (!mounted) return;
      context.pop(Uint8List.fromList(pcztBytes));
    } catch (e, st) {
      log('KeystoneSendScanScreen: signed PCZT decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error = AppLocalizations.of(context).keystoneSendQrDecodeError;
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? AppLocalizations.of(context).keystoneOpenSignedTxQr
        : AppLocalizations.of(context).keystoneScanHoldSteady;
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
      sidebar: const AppMainSidebar(),
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
              child: AppBackLink(
                label: AppLocalizations.of(context).commonBack,
                onTap: _goBack,
              ),
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
                        AppLocalizations.of(context).keystoneScanQrTitle,
                        style: AppTypography.displaySmall.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        AppLocalizations.of(context).keystoneHoldQrSteady,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      KeystoneQrScannerCard(
                        expectedUrType: 'zcash-pczt',
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
                        decodingLabel: AppLocalizations.of(
                          context,
                        ).keystoneReadingSignature,
                        unavailableMessage: AppLocalizations.of(
                          context,
                        ).keystoneCameraOnly,
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
