import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../../../../l10n/app_localizations.dart';

class KeystoneVotingScanScreen extends ConsumerStatefulWidget {
  const KeystoneVotingScanScreen({super.key});

  @override
  ConsumerState<KeystoneVotingScanScreen> createState() =>
      _KeystoneVotingScanScreenState();
}

class _KeystoneVotingScanScreenState
    extends ConsumerState<KeystoneVotingScanScreen> {
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
      log('KeystoneVotingScanScreen: signed PCZT decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error =
            AppLocalizations.of(context).votingSignatureQrDecodeError;
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? AppLocalizations.of(context).votingOpenSignedQr
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
    context.go('/voting');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        // Back chevron sits 16px into the pane per the shared design rule
        // (4px pane padding + AppBackLink's 12px internal inset); the centered
        // content keeps md on the other sides.
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
              child: AppBackLink(label: AppLocalizations.of(context).commonBack, onTap: _goBack),
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
                        AppLocalizations.of(context).votingScanVotingSignature,
                        style: AppTypography.displaySmall.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        AppLocalizations.of(context).votingHoldKeystoneQr,
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
                        decodingLabel: AppLocalizations.of(context).keystoneReadingSignature,
                        unavailableMessage:
                            AppLocalizations.of(context).votingCameraOnly,
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
