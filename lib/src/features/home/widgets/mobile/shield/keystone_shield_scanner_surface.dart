import 'dart:math' as math;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanViewfinderCorners;
import 'keystone_shield_morph.dart';

/// The scanner's visual surface, shared with deterministic motion captures.
/// The transaction owner supplies the real camera, decoding and torch actions.
class KeystoneShieldScannerSurface extends StatelessWidget {
  const KeystoneShieldScannerSurface({
    required this.constraints,
    required this.morph,
    required this.cameraBuilder,
    required this.onToggleTorch,
    this.cameraErrorBuilder,
    this.decoding = false,
    this.progress = 0,
    this.hint,
    super.key,
  });
  final BoxConstraints constraints;
  final KeystoneShieldMorph morph;
  final Widget Function(double size) cameraBuilder;
  final Widget Function(double size)? cameraErrorBuilder;
  final VoidCallback onToggleTorch;
  final bool decoding;
  final int progress;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final message = decoding
        ? 'Reading signature…'
        : hint ?? 'Scanning… $progress%';
    final style = AppTypography.bodyMedium.copyWith(
      color: const Color(0xFFFFFFFF),
    );
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final messageHeight = math.max(
      measure(message),
      math.max(measure('Reading signature…'), measure('Scanning… 100%')),
    );
    final overhead = math.max(100.0, messageHeight + 12 + 48);
    final viewSize = math.max(
      1.0,
      math.min(
        260.0,
        math.min(constraints.maxWidth, constraints.maxHeight - overhead),
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: viewSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.large),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: morph.scannerOpacity,
                    child: cameraBuilder(viewSize),
                  ),
                  KeystoneShieldAnchor(
                    morph: morph,
                    kind: KeystoneShieldAnchorKind.frame,
                    child: Opacity(
                      opacity: morph.scannerGlyphOpacity,
                      child: const MobileScanViewfinderCorners(),
                    ),
                  ),
                  if (cameraErrorBuilder != null) cameraErrorBuilder!(viewSize),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: messageHeight,
            child: Opacity(
              opacity: morph.scannerOpacity,
              child: Center(
                child: Text(message, textAlign: TextAlign.center, style: style),
              ),
            ),
          ),
          AppButton(
            variant: AppButtonVariant.ghost,
            disabledBackgroundColor: const Color(0x00000000),
            onPressed: morph.scannerGlyphOpacity >= 0.99 ? onToggleTorch : null,
            child: KeystoneShieldAnchor(
              morph: morph,
              kind: KeystoneShieldAnchorKind.torch,
              child: Opacity(
                opacity: morph.scannerGlyphOpacity,
                alwaysIncludeSemantics: true,
                child: const Icon(
                  Icons.flashlight_on_outlined,
                  color: Color(0xFFFFFFFF),
                  semanticLabel: 'Toggle flashlight',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
