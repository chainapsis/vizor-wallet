import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../services/payment_link_qr_export.dart';
import '../payment_link_gift_card.dart';
import '../payment_link_qr_share_card.dart';

class PaymentLinkShareSheet extends StatefulWidget {
  const PaymentLinkShareSheet({
    required this.artwork,
    required this.link,
    required this.onShare,
    required this.onShareError,
    required this.onCopyLink,
    required this.onClose,
    super.key,
  });

  final PaymentLinkCardArtwork artwork;
  final String link;
  final Future<void> Function(Uint8List png, Rect origin) onShare;
  final VoidCallback onShareError;
  final Future<void> Function() onCopyLink;
  final VoidCallback onClose;

  @override
  State<PaymentLinkShareSheet> createState() => _PaymentLinkShareSheetState();
}

enum _ShareAction { share, copy }

class _PaymentLinkShareSheetState extends State<PaymentLinkShareSheet> {
  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  _ShareAction? _action;

  Future<void> _share() async {
    if (_action != null) return;
    final button =
        _shareButtonKey.currentContext!.findRenderObject()! as RenderBox;
    final origin = button.localToGlobal(Offset.zero) & button.size;
    final pixelRatio = max(3.0, View.of(context).devicePixelRatio);
    setState(() => _action = _ShareAction.share);
    try {
      final png = await capturePaymentLinkQr(_cardKey, pixelRatio: pixelRatio);
      if (mounted) await widget.onShare(png, origin);
    } catch (_) {
      if (mounted) widget.onShareError();
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  Future<void> _copy() async {
    if (_action != null) return;
    setState(() => _action = _ShareAction.copy);
    try {
      await widget.onCopyLink();
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileModalScaffold(
      key: const ValueKey('payment_link_share_sheet'),
      title: 'Share gift card',
      onClose: widget.onClose,
      bottomPadding: AppSpacing.base,
      constrainBody: true,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The preview scales to the sheet; the captured surface retains
            // its desktop export dimensions and resolution.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(
                key: _cardKey,
                child: PaymentLinkQrShareCard(
                  artwork: widget.artwork,
                  qrData: widget.link,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: _shareButtonKey,
              expand: true,
              constrainContent: true,
              onPressed: _action == null ? _share : null,
              leading: const AppIcon(AppIcons.share),
              child: Text(
                _action == _ShareAction.share ? 'Sharing...' : 'Share card',
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              key: const ValueKey('payment_link_share_copy_button'),
              variant: AppButtonVariant.secondary,
              expand: true,
              constrainContent: true,
              onPressed: _action == null ? _copy : null,
              child: Text(
                _action == _ShareAction.copy ? 'Copying...' : 'Copy link',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
