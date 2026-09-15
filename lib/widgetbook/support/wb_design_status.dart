// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; imports of it are confined to
// `lib/widgetbook/` and `lib/widgetbook.dart`, which are not reachable from
// the production entry point `lib/main.dart`.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/core/theme/app_theme.dart';
import '../../src/core/widgets/app_tooltip.dart';

/// Sentinel `designLink` value marking a surface that deliberately has no
/// Figma frame. Optionally carries `?note=<urlencoded>` with the reason.
const kWbNoFigma = 'vizor-design:none';

/// Builds the [kWbNoFigma] sentinel, optionally carrying a [note].
String wbNoFigma({String? note}) {
  if (note == null || note.isEmpty) return kWbNoFigma;
  return '$kWbNoFigma?note=${Uri.encodeComponent(note)}';
}

/// Design-coverage state of a single use case.
enum WbDesignStatus {
  /// `designLink` points at a real design URL.
  linked,

  /// `designLink` is the [kWbNoFigma] sentinel.
  noFigma,

  /// `designLink` is absent — nobody has decided yet.
  unmarked,
}

/// Classifies a `WidgetbookUseCase.designLink`.
WbDesignStatus wbDesignStatusOf(String? designLink) {
  final link = designLink?.trim();
  if (link == null || link.isEmpty) return WbDesignStatus.unmarked;
  if (link == kWbNoFigma || link.startsWith('$kWbNoFigma?')) {
    return WbDesignStatus.noFigma;
  }
  return WbDesignStatus.linked;
}

/// The note carried by a [kWbNoFigma] sentinel, if any.
String? wbDesignNote(String? designLink) {
  if (wbDesignStatusOf(designLink) != WbDesignStatus.noFigma) return null;
  final note = Uri.parse(designLink!.trim()).queryParameters['note'];
  return (note == null || note.isEmpty) ? null : note;
}

/// The design URL of a [WbDesignStatus.linked] use case, if it parses.
Uri? wbDesignUri(String? designLink) {
  if (wbDesignStatusOf(designLink) != WbDesignStatus.linked) return null;
  return Uri.tryParse(designLink!.trim());
}

/// Human-readable label for [status], used by the chip and the handoff doc.
String wbDesignStatusLabel(WbDesignStatus status) => switch (status) {
  WbDesignStatus.linked => 'Figma',
  WbDesignStatus.noFigma => 'No Figma',
  WbDesignStatus.unmarked => 'Unmarked',
};

/// Overlays every use case with its design-status chip.
///
/// Registered after `ThemeAddon` so the chip can read `AppTheme` tokens.
class WbDesignStatusAddon extends WidgetbookAddon<bool> {
  /// Creates the addon; the field starts off until design marking begins.
  WbDesignStatusAddon() : super(name: 'Design status');

  static const _fieldName = 'Design status';

  @override
  List<Field> get fields => [
    BooleanField(name: _fieldName, initialValue: false),
  ];

  @override
  bool valueFromQueryGroup(Map<String, String> group) =>
      valueOf<bool>(_fieldName, group) ?? false;

  @override
  Widget buildUseCase(BuildContext context, Widget child, bool setting) {
    // `maybeOf` so the addon can also be exercised outside a Widgetbook root.
    final designLink = WidgetbookState.maybeOf(context)?.useCase?.designLink;
    return WbDesignStatusOverlay(
      enabled: setting,
      designLink: designLink,
      child: child,
    );
  }
}

/// Stacks [WbDesignStatusChip] over [child] in the top-right corner.
class WbDesignStatusOverlay extends StatefulWidget {
  /// Creates the overlay.
  const WbDesignStatusOverlay({
    required this.child,
    this.designLink,
    this.enabled = true,
    super.key,
  });

  /// The `designLink` of the use case underneath.
  final String? designLink;

  /// The use case being annotated.
  final Widget child;

  final bool enabled;

  @override
  State<WbDesignStatusOverlay> createState() => _WbDesignStatusOverlayState();
}

class _WbDesignStatusOverlayState extends State<WbDesignStatusOverlay> {
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // Unmarked is every use case until Phase 5 links them, so it gets no chip
    // at all rather than a badge over each surface's top-right corner.
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!widget.enabled ||
        wbDesignStatusOf(widget.designLink) == WbDesignStatus.unmarked) {
      return child;
    }

    // `Positioned` sizes the overlay to the chip alone, so hit-testing
    // anywhere else on the canvas still reaches the use case underneath.
    return Stack(
      children: [
        child,
        Positioned(
          top: AppSpacing.s,
          right: AppSpacing.s,
          child: WbDesignStatusChip(designLink: widget.designLink),
        ),
      ],
    );
  }
}

/// Design-status chip: a Figma link or a "No Figma" badge; unmarked shows
/// nothing, since that is every use case until the Figma linking pass.
class WbDesignStatusChip extends StatelessWidget {
  /// Creates the chip for a use case's [designLink].
  const WbDesignStatusChip({this.designLink, super.key});

  /// The raw `WidgetbookUseCase.designLink` value.
  final String? designLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = wbDesignStatusOf(designLink);

    switch (status) {
      case WbDesignStatus.linked:
        final uri = wbDesignUri(designLink);
        return _WbDesignBadge(
          label: 'Figma ↗',
          foreground: colors.text.accent,
          border: colors.border.strong,
          onTap: uri == null
              ? null
              : () => launchUrl(uri, mode: LaunchMode.externalApplication),
        );
      case WbDesignStatus.noFigma:
        final note = wbDesignNote(designLink);
        final badge = _WbDesignBadge(
          label: 'No Figma',
          foreground: colors.text.warning,
          border: colors.border.regular,
        );
        // Only a note earns pointer events (the tooltip needs hover); a bare
        // badge must not swallow taps meant for the surface underneath.
        return note == null
            ? IgnorePointer(child: badge)
            : AppTooltip(message: note, child: badge);
      case WbDesignStatus.unmarked:
        return const SizedBox.shrink();
    }
  }
}

class _WbDesignBadge extends StatelessWidget {
  const _WbDesignBadge({
    required this.label,
    required this.foreground,
    required this.border,
    this.onTap,
  });

  final String label;
  final Color foreground;
  final Color border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      key: const ValueKey('wb_design_status_chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: foreground),
      ),
    );

    if (onTap == null) return badge;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: badge),
    );
  }
}
