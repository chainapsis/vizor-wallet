// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/core/layout/app_desktop_shell.dart';
import '../../src/core/layout/app_form_factor.dart';
import '../../src/core/theme/app_theme.dart';

/// Which form factor a gallery use case is previewing.
enum WbLayout { desktop, mobile }

/// The form factor this binary's design tokens were compiled for.
///
/// [kAppFormFactor] is a compile-time const, so a knob can swap between
/// desktop and mobile *widget classes* but never flips token selection —
/// see [WbLaneOnly] for the surfaces where that distinction matters.
const WbLayout wbCompiledLaneLayout = kAppFormFactor == AppFormFactor.mobile
    ? WbLayout.mobile
    : WbLayout.desktop;

/// Desktop window box used by today's `_*PageFrame` fixtures
/// (`_SwapPageFrame`, `_PayDesktopFrame`, `buildActivityPageUseCase`).
const double kWbDesktopWindowWidth = 1080;
const double kWbDesktopWindowHeight = 720;

/// Phone box used by the mobile fixtures (`_MobileKeystoneScreenFrame`,
/// `_MobileSendScanFrame`, `payment_link_mobile_use_cases`).
const Size kWbPhoneSize = Size(393, 852);

/// Status-bar inset the mobile fixtures feed their frames as `viewPadding`.
const double kWbPhoneStatusBarInset = 55;

/// `Layout` dropdown, initialised to the compiled lane so the mobile binary
/// opens on the mobile preview.
WbLayout wbLayoutKnob(BuildContext context) {
  return context.knobs.object.dropdown<WbLayout>(
    label: 'Layout',
    options: WbLayout.values,
    initialOption: wbCompiledLaneLayout,
    labelBuilder: wbLayoutLabel,
  );
}

/// Knob label for a layout option.
String wbLayoutLabel(WbLayout layout) {
  return layout == WbLayout.desktop ? 'Desktop' : 'Mobile';
}

/// Whether [layout] is the form factor whose design tokens are compiled in.
bool wbLayoutMatchesLane(WbLayout layout) => layout == wbCompiledLaneLayout;

/// The widgetbook command that compiles the token set for [layout].
String wbLaneRunCommand(WbLayout layout) {
  final formFactor = layout == WbLayout.mobile ? 'mobile' : 'desktop';
  return 'fvm flutter run -t lib/widgetbook.dart '
      '--dart-define=VIZOR_FORM_FACTOR=$formFactor';
}

/// Frames a gallery use case in the surface its layout actually lives in.
///
/// Desktop reproduces the fixture pane convention: a 1080×720 window on
/// `macosUtility.window` (what [AppDesktopShell] paints) with the pane sitting
/// exactly where the shell puts it — [kAppDesktopShellMargin] (8) on three
/// edges and [appDesktopPaneLeftInset] (8 + 256 sidebar + 8) on the left — so
/// the child gets the same 800px-wide pane a real screen gets. The sidebar
/// column is left empty; galleries that need a sidebar keep using their own
/// fixture frames.
///
/// Mobile reproduces the phone convention: a 393×852 box on
/// `background.window` with the same size / 55px top `viewPadding` the mobile
/// fixtures hand their screens.
///
/// The desktop branch deliberately leaves the sidebar column empty, so moving
/// a fixture off its own frame onto [WbFrame] changes its render and needs
/// visual verification.
///
/// Both branches scale: the desktop window goes through [WbDesktopWindowBox]
/// and the phone through [WbPhoneBox], so neither is squeezed by a canvas
/// smaller than the box.
class WbFrame extends StatelessWidget {
  const WbFrame({
    required this.layout,
    required this.child,
    this.desktopWidth,
    this.desktopHeight,
    super.key,
  });

  final WbLayout layout;
  final Widget child;

  /// Desktop window box overrides; default to 1080×720.
  final double? desktopWidth;
  final double? desktopHeight;

  @override
  Widget build(BuildContext context) {
    return layout == WbLayout.desktop ? _desktop(context) : _phone(context);
  }

  Widget _desktop(BuildContext context) {
    return Center(
      child: WbDesktopWindowBox(
        size: Size(
          desktopWidth ?? kWbDesktopWindowWidth,
          desktopHeight ?? kWbDesktopWindowHeight,
        ),
        child: ColoredBox(
          color: context.colors.macosUtility.window,
          child: Padding(
            padding: EdgeInsets.only(
              left: appDesktopPaneLeftInset(kAppDesktopSidebarWidth),
              top: kAppDesktopShellMargin,
              right: kAppDesktopShellMargin,
              bottom: kAppDesktopShellMargin,
            ),
            child: AppDesktopPane(padding: EdgeInsets.zero, child: child),
          ),
        ),
      ),
    );
  }

  Widget _phone(BuildContext context) {
    return Center(child: WbPhoneBox(child: child));
  }
}

/// Fits a fixed-size preview box into whatever canvas it is given.
///
/// `BoxFit.scaleDown` only ever shrinks, so a phone frame fits the ~670pt
/// canvas the default 1080×720 window leaves instead of overflowing it; the
/// [LayoutBuilder] keeps the box untouched whenever it already fits, so a
/// capture viewport that equals [size] renders byte-identically.
///
/// The pass-through branch is deliberate rather than a bare [FittedBox]: under
/// *tight* constraints larger than [size] — what the gallery test harness hands
/// a use case — a [FittedBox] would centre the child at its natural size, which
/// collapses fixtures that only differ outside the phone box into one
/// fingerprint. Pinned in `test/widgetbook/support/wb_layout_test.dart`.
///
/// Only the frame scales: a sheet presented with `useRootNavigator: true` or a
/// toast on the root overlay escapes this box, so a scaled preview still paints
/// those at canvas scale.
class WbScaleDownBox extends StatefulWidget {
  const WbScaleDownBox({required this.size, required this.child, super.key});

  /// The box's own size. [child] must lay out to it under loose constraints.
  final Size size;

  final Widget child;

  @override
  State<WbScaleDownBox> createState() => _WbScaleDownBoxState();
}

class _WbScaleDownBoxState extends State<WbScaleDownBox> {
  /// Keeps the previewed subtree the same element across the fits/does-not-fit
  /// threshold, so resizing the canvas reparents it instead of remounting it —
  /// an interactive preview (typed text, open sheet, router route) survives.
  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyed = KeyedSubtree(key: _childKey, child: widget.child);
        final tooNarrow =
            constraints.hasBoundedWidth && constraints.maxWidth < size.width;
        final tooShort =
            constraints.hasBoundedHeight && constraints.maxHeight < size.height;
        if (!tooNarrow && !tooShort) return keyed;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: keyed,
        );
      },
    );
  }
}

/// The desktop window box every desktop screen preview renders in: a fixed
/// [size] carrying the window's own `MediaQuery`, scaled down through
/// [WbScaleDownBox] when the canvas is smaller than the window.
///
/// The app never lays out below 1080×720 (`defaultSize` / `minimumSize` in
/// `core/layout/app_layout.dart`), so a desktop preview is that whole window
/// scaled to the canvas, not a layout squeezed to canvas proportions. A
/// fixture whose branch only exists at a shorter pane passes its own
/// sub-minimum [size] and says so at the knob (`HomeWindowHeight.compact`,
/// `_swapScreenPackedWindowSize`).
///
/// Which previews get the box: the ones that reproduce the app's *window or
/// pane shell* — a screen, a router harness, or a modal on its pane backdrop
/// (`_AddressVerifyModalFrame`). A preview of the modal surface alone, with no
/// window chrome around it, does not (`_AddressScanModalFrame` in
/// `address_scan_use_cases.dart`, a bare 361-wide box): it carries no window,
/// and it renders in the mobile lane too, where a 1080×720 box would be wrong.
class WbDesktopWindowBox extends StatelessWidget {
  const WbDesktopWindowBox({
    required this.child,
    this.size = const Size(kWbDesktopWindowWidth, kWbDesktopWindowHeight),
    super.key,
  });

  final Widget child;

  /// Defaults to the 1080×720 window; a fixture with its own larger fixed
  /// window passes that size instead.
  final Size size;

  @override
  Widget build(BuildContext context) {
    return WbScaleDownBox(
      size: size,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          // The window carries its own metrics, so the canvas's size and any
          // host inset never reach the previewed screen.
          data: MediaQuery.of(context).copyWith(
            size: size,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The phone box every mobile fixture frames its screen in: a fixed [size] on
/// `background.window` carrying the phone's own `MediaQuery`, scaled down
/// through [WbScaleDownBox] when the canvas is shorter than the phone.
class WbPhoneBox extends StatelessWidget {
  const WbPhoneBox({
    required this.child,
    this.background,
    this.size = kWbPhoneSize,
    this.statusBarInset = kWbPhoneStatusBarInset,
    super.key,
  });

  final Widget child;

  /// Defaults to `background.window`, the phone convention.
  final Color? background;

  final Size size;
  final double statusBarInset;

  @override
  Widget build(BuildContext context) {
    return WbScaleDownBox(
      size: size,
      child: SizedBox.fromSize(
        size: size,
        child: ColoredBox(
          color: background ?? context.colors.background.window,
          child: MediaQuery(
            // Replace host insets with the simulated phone geometry. SafeArea
            // consumes padding, while explicit status-bar layouts read
            // viewPadding; both must describe the same unobscured screen.
            data: MediaQuery.of(context).copyWith(
              size: size,
              viewPadding: EdgeInsets.only(top: statusBarInset),
              padding: EdgeInsets.only(top: statusBarInset),
              viewInsets: EdgeInsets.zero,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Renders [child] only when [layout] is the compiled token lane.
///
/// For surfaces whose metrics come from `kAppFormFactor`, previewing the other
/// lane would silently mix that lane's widgets with this lane's tokens, so the
/// knob shows the run command instead of a misleading approximation.
class WbLaneOnly extends StatelessWidget {
  const WbLaneOnly({required this.layout, required this.child, super.key});

  final WbLayout layout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (wbLayoutMatchesLane(layout)) return child;
    return _WbLaneNotice(requested: layout);
  }
}

class _WbLaneNotice extends StatelessWidget {
  const _WbLaneNotice({required this.requested});

  final WbLayout requested;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.base,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            key: const ValueKey('wb_lane_only_notice'),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surface.card,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(color: colors.border.subtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compiled for ${wbCompiledLaneLayout.name}',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Run the ${requested.name} lane to preview this layout.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.background.raised,
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: Text(
                    wbLaneRunCommand(requested),
                    style: AppTypography.codeSmall.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
