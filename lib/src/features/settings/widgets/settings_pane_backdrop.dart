import 'package:flutter/widgets.dart';

/// Artwork variants for the etched full-window settings backdrop.
enum SettingsBackdropArt {
  castle('assets/illustrations/settings_backdrop_castle.png'),
  vault('assets/illustrations/settings_backdrop_vault.png');

  const SettingsBackdropArt(this.assetPath);

  final String assetPath;
}

/// Etched illustration behind settings sub-screens, in both light and
/// dark mode.
///
/// Spans the full window width at the design's 1080x520 aspect,
/// top-anchored, washed to 15% alpha and fading out toward its
/// bottom edge. The PNGs are RGBA with a transparent background, so the
/// same artwork and wash render correctly over either theme. Mount it as
/// the `background` of an `AppDesktopBackdropShell` (or any full-window
/// Stack) so it bleeds behind the glass sidebar and the window margins
/// like the design.
class SettingsPaneBackdrop extends StatelessWidget {
  const SettingsPaneBackdrop({required this.art, super.key});

  final SettingsBackdropArt art;

  static const _imageAspectRatio = 1080 / 520;

  // Alpha mask: constant 15% until y=143 of the 520-tall artwork, then
  // linear fade to fully transparent at its bottom edge.
  static const _fadeStartStop = 143 / 520;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(
          aspectRatio: _imageAspectRatio,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x26FFFFFF), Color(0x26FFFFFF), Color(0x00FFFFFF)],
              stops: [0, _fadeStartStop, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Image.asset(art.assetPath, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }
}
