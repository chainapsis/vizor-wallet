/// The QR block a created request is read from: the code itself, the one-line
/// summary under it, and the PNG export both form factors hand out.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/pool_badge.dart';

/// Ink for a request QR. Theme-invariant black, paired with the theme-
/// invariant `surface.qrCode` white behind it.
const _requestQrInk = Color(0xFF000000);

/// Quiet zone in modules. Four is the QR specification's own margin; the
/// decorative receive code can drop it to zero because a wallet address is
/// short and forgiving, but a request URI pushes the symbol several versions
/// higher and a camera needs the border back.
const double _requestQrQuietZoneModules = 4;

/// A request QR: black square modules on white, with a real quiet zone and no
/// embedded badge.
///
/// This deliberately does not reuse `ReceiveQrSurface`. That one is the
/// decorative address code — dot modules, zero quiet zone, a pool badge
/// covering the middle — which survives because an address is a short,
/// low-version symbol. A ZIP-321 URI carries the address *plus* an amount and
/// up to 512 bytes of memo, so the same treatment would be asking a stranger's
/// camera to read a dense code through a hole in the middle of it. Scan
/// reliability wins here, exactly as it does for the Keystone PCZT codes.
class RequestQrSurface extends StatelessWidget {
  const RequestQrSurface({
    required this.data,
    required this.size,
    this.padding = AppSpacing.sm,
    super.key,
  });

  /// What the code encodes: the request URI, or the bare address before an
  /// amount has been entered.
  final String data;

  /// Side length of the code itself, excluding [padding].
  final double size;

  /// White margin drawn around the code, on top of its module quiet zone.
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('request_qr_surface'),
      width: size + padding * 2,
      height: size + padding * 2,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colors.surface.qrCode,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: data.isEmpty
          ? Center(
              child: Text(
                'QR unavailable',
                style: AppTypography.bodySmall.copyWith(color: _requestQrInk),
              ),
            )
          : PrettyQrView(
              qrImage: QrImage(
                QrCode.fromData(
                  data: data,
                  // M is the level the rest of the app scans at, and it keeps
                  // the symbol a version lower than Q would for the same URI.
                  errorCorrectLevel: QrErrorCorrectLevel.M,
                ),
              ),
              decoration: const PrettyQrDecoration(
                quietZone: PrettyQrQuietZone.modules(
                  _requestQrQuietZoneModules,
                ),
                shape: PrettyQrSquaresSymbol(color: _requestQrInk),
              ),
            ),
    );
  }
}

/// The one line under a request QR: `0.5 ZEC · Shielded`.
///
/// The amount is the value being asked for and takes the accent colour; the
/// pool badge beside it is the privacy fact a payer cannot infer from the
/// amount, and it is stated in the same badge every other surface uses.
class RequestSummaryRow extends StatelessWidget {
  const RequestSummaryRow({
    required this.amountText,
    required this.isShielded,
    super.key,
  });

  final String amountText;
  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('request_summary_row'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            amountText,
            key: const ValueKey('request_summary_amount'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '·',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.muted),
        ),
        const SizedBox(width: AppSpacing.xs),
        PoolBadge(isShielded: isShielded),
      ],
    );
  }
}

/// Side of the exported QR bitmap, in pixels.
///
/// The same 1536 the receive screen renders its cached bitmap at: large
/// enough that the PNG survives being pasted into a chat, a slide or a
/// printed sheet without the modules turning to mush.
const int kRequestQrExportSize = 1536;

/// Paper the exported code is printed on.
///
/// Export is theme-invariant black on white even in dark mode: the file
/// leaves the app and is scanned somewhere we do not control, and a
/// light-on-dark code is the one thing many camera pipelines refuse.
const Color _requestQrExportPaper = Color(0xFFFFFFFF);

/// Renders [uri] as a standalone PNG of the same square-module code
/// [RequestQrSurface] draws, quiet zone included.
///
/// Pure: no context, no theme, no storage. The caller decides what to do
/// with the bytes — write them to a file, or attach them to a share sheet.
Future<Uint8List> renderRequestQrPng(
  String uri, {
  int size = kRequestQrExportSize,
  double quietZoneModules = _requestQrQuietZoneModules,
}) async {
  if (uri.isEmpty) {
    throw ArgumentError.value(uri, 'uri', 'There is no request to export');
  }

  final qrImage = QrImage(
    QrCode.fromData(data: uri, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final bytes = await qrImage.toImageAsBytes(
    size: size,
    decoration: PrettyQrDecoration(
      background: _requestQrExportPaper,
      quietZone: PrettyQrQuietZone.modules(quietZoneModules),
      shape: const PrettyQrSquaresSymbol(color: _requestQrInk),
    ),
  );
  if (bytes == null) {
    throw StateError('Could not encode the request QR as an image');
  }
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

/// A button whose action needs the request as a PNG.
///
/// It owns the render so neither the modal nor the sheet has to become
/// stateful for it, and so both get the same double-tap guard: the encode is
/// near-instant, but "near" is not "always", and a second tap must not start
/// a second encode or fire the action twice.
class RequestQrExportButton extends StatefulWidget {
  const RequestQrExportButton({
    required this.uri,
    required this.label,
    required this.onBytes,
    this.variant = AppButtonVariant.primary,
    this.icon,
    super.key,
  });

  /// The request to encode, or null while there is not one yet — which
  /// renders the button disabled rather than hiding it.
  final String? uri;

  final String label;

  /// Receives the encoded PNG. Nothing is written or shared here.
  final ValueChanged<Uint8List>? onBytes;

  final AppButtonVariant variant;

  /// Icon name from [AppIcons], or null for a bare label.
  final String? icon;

  @override
  State<RequestQrExportButton> createState() => _RequestQrExportButtonState();
}

class _RequestQrExportButtonState extends State<RequestQrExportButton> {
  bool _busy = false;

  Future<void> _run() async {
    final uri = widget.uri;
    final onBytes = widget.onBytes;
    if (_busy || uri == null || uri.isEmpty || onBytes == null) return;

    setState(() => _busy = true);
    try {
      final png = await renderRequestQrPng(uri);
      if (!mounted) return;
      onBytes(png);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !_busy && widget.onBytes != null && (widget.uri?.isNotEmpty ?? false);
    final icon = widget.icon;

    return AppButton(
      expand: true,
      constrainContent: true,
      variant: widget.variant,
      onPressed: enabled ? _run : null,
      leading: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (icon == null ? null : AppIcon(icon)),
      child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
