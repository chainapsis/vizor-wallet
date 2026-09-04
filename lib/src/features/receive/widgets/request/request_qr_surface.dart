/// The QR block a created request is read from: the code itself, the one-line
/// summary under it, and the PNG export both form factors hand out.
library;

import 'dart:math' as math;
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../../main.dart' show log;
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

/// Smallest side, in logical pixels, a single module may be drawn at.
///
/// Two is not an aesthetic floor, it is the renderer's: `PrettyQrSquaresSymbol`
/// clamps its module density into `[1, moduleDimension / 2]`, which is an
/// empty range — and an assertion — as soon as a module is under 2px. A memo
/// pushes a ZIP-321 URI into the high symbol versions, so a request QR pinned
/// to a fixed side hits that long before the code becomes unscannable.
const double _requestQrMinModuleSize = 2;

/// The side, in logical pixels, the code for [data] needs before its modules
/// fall under [minModulePx] — quiet zone included, [RequestQrSurface]'s own
/// white padding excluded.
///
/// Public because a fixed-width container has to ask *before* it lays the
/// surface out: [RequestQrSurface] can only grow into the width it is given,
/// so a caller that hands it too little turns the floor this file exists to
/// enforce into a clamp against it. Zero for an empty request, which draws no
/// code at all.
double requestQrSideFor(
  String data, {
  double minModulePx = _requestQrMinModuleSize,
}) {
  if (data.isEmpty) return 0;
  final qrImage = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  return _requestQrSide(qrImage, minModulePx);
}

double _requestQrSide(QrImage qrImage, double minModulePx) =>
    (qrImage.moduleCount + _requestQrQuietZoneModules * 2) * minModulePx;

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
///
/// [size] is a floor, not a fixed side: a dense request grows the code up to
/// the width it is given rather than shrinking its modules below
/// [_requestQrMinModuleSize]. The surface is square either way.
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

  /// Smallest side length of the code itself, excluding [padding].
  final double size;

  /// White margin drawn around the code, on top of its module quiet zone.
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final qrImage = data.isEmpty
        ? null
        : QrImage(
            QrCode.fromData(
              data: data,
              // M is the level the rest of the app scans at, and it keeps
              // the symbol a version lower than Q would for the same URI.
              errorCorrectLevel: QrErrorCorrectLevel.M,
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = _resolveSide(qrImage, constraints);
        return Container(
          key: const ValueKey('request_qr_surface'),
          width: side + padding * 2,
          height: side + padding * 2,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: colors.surface.qrCode,
            borderRadius: BorderRadius.circular(AppRadii.large),
            border: Border.all(color: colors.border.subtle),
          ),
          child: qrImage == null
              ? Center(
                  child: Text(
                    'QR unavailable',
                    style: AppTypography.bodySmall.copyWith(
                      color: _requestQrInk,
                    ),
                  ),
                )
              : PrettyQrView(
                  qrImage: qrImage,
                  decoration: const PrettyQrDecoration(
                    quietZone: PrettyQrQuietZone.modules(
                      _requestQrQuietZoneModules,
                    ),
                    shape: PrettyQrSquaresSymbol(color: _requestQrInk),
                  ),
                ),
        );
      },
    );
  }

  /// The side this code is actually drawn at: [size], grown to whatever the
  /// symbol needs to keep its modules legible, and capped by the space the
  /// caller has. The cap can only bite in a layout narrower than any symbol
  /// version needs, which is well under the width both request surfaces give.
  double _resolveSide(QrImage? qrImage, BoxConstraints constraints) {
    if (qrImage == null) return size;

    final needed = _requestQrSide(qrImage, _requestQrMinModuleSize);

    var available = double.infinity;
    if (constraints.hasBoundedWidth) {
      available = math.min(available, constraints.maxWidth - padding * 2);
    }
    if (constraints.hasBoundedHeight) {
      available = math.min(available, constraints.maxHeight - padding * 2);
    }
    if (!available.isFinite) return math.max(size, needed);
    return math.max(size, math.min(needed, math.max(size, available)));
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
    this.onError,
    this.variant = AppButtonVariant.primary,
    this.icon,
    super.key,
  });

  /// The request to encode, or null while there is not one yet — which
  /// renders the button disabled rather than hiding it.
  final String? uri;

  final String label;

  /// Receives the encoded PNG. Nothing is written or shared here.
  /// Receives the rendered PNG. Awaited: the button stays busy until the
  /// hand-off — a native save dialog, a share sheet — has completed, so a
  /// second press cannot start a second export while the first is still
  /// pending. A synchronous callback is fine too.
  final FutureOr<void> Function(Uint8List png)? onBytes;

  /// Called instead of [onBytes] when the encode fails.
  ///
  /// Without it the press is a silent no-op: the spinner blinks, the future
  /// this button is invoked as is never awaited, and the user is left looking
  /// at a share they have every reason to think they made. The caller says
  /// what failed and names the hand-off still available.
  final VoidCallback? onError;

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
      await onBytes(png);
    } catch (e) {
      // The exception stays in the log; the callback is what the user sees.
      log('RequestQr: ERROR rendering the request QR: $e');
      if (!mounted) return;
      widget.onError?.call();
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
