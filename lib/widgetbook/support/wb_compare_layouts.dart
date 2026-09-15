// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; imports of it are confined to
// `lib/widgetbook/` and `lib/widgetbook.dart`, which are not reachable from
// the production entry point `lib/main.dart`.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
// The addon API does not expose the workbench key; see _PrimaryUseCase.
// ignore: implementation_imports
import 'package:widgetbook/src/workbench/use_case_builder.dart';

import '../../src/core/theme/app_theme.dart';
import 'wb_layout.dart';

/// Label of the `Layout` knob this addon pairs with.
///
/// Must stay equal to the label [wbLayoutKnob] registers — the knob registry
/// and the shareable URL are both keyed by it. Pinned in
/// `test/widgetbook/support/wb_compare_layouts_test.dart`.
const String kWbLayoutKnobLabel = 'Layout';

/// Field (and query-group) name of the compare toggle.
const String kWbCompareLayoutsField = 'Compare layouts';

/// Root key of the two-pane canvas.
const Key kWbCompareLayoutsKey = ValueKey('wb_compare_layouts');

/// Caption key of the pane previewing [layout].
Key wbCompareLayoutsCaptionKey(WbLayout layout) =>
    ValueKey('wb_compare_layouts_caption_${layout.name}');

/// The layout a `knobs` query group selects, or the knob's own default.
///
/// [wbLayoutKnob] initialises to [wbCompiledLaneLayout], so an absent or
/// unrecognised entry resolves to the compiled lane exactly like the knob does.
WbLayout wbCompareLayoutOf(Map<String, String> knobGroup) {
  final label = knobGroup[kWbLayoutKnobLabel];
  for (final layout in WbLayout.values) {
    if (wbLayoutLabel(layout) == label) return layout;
  }
  return wbCompiledLaneLayout;
}

/// The layout the compare pane shows opposite [layout].
WbLayout wbOtherLayout(WbLayout layout) =>
    layout == WbLayout.desktop ? WbLayout.mobile : WbLayout.desktop;

/// Caption note for the pane whose layout is not the compiled token lane.
///
/// `kAppFormFactor` is compile-time, so that pane renders the other lane's
/// widget classes under this binary's tokens — the same approximation the
/// `Layout` knob makes, spelled out so the pair is never read as two faithful
/// renders. A token-faithful view of that lane needs the other lane's binary.
String wbCompareTokenNote() =>
    '${wbLayoutLabel(wbCompiledLaneLayout).toLowerCase()} tokens (approx.)';

/// Shows a use case's desktop and mobile previews side by side.
///
/// Only use cases carrying a [kWbLayoutKnobLabel] knob can be compared; every
/// other use case renders unchanged, so the addon is additive.
///
/// Registered as the innermost addon, so `AppTheme` is in scope, and so the
/// design-status chip and the alignment apply once to the pair rather than to
/// each pane.
class WbCompareLayoutsAddon extends WidgetbookAddon<bool> {
  /// Creates the addon; the field starts off, one pane as before.
  WbCompareLayoutsAddon() : super(name: kWbCompareLayoutsField);

  @override
  List<Field> get fields => [
    BooleanField(name: kWbCompareLayoutsField, initialValue: false),
  ];

  @override
  bool valueFromQueryGroup(Map<String, String> group) =>
      valueOf<bool>(kWbCompareLayoutsField, group) ?? false;

  @override
  Widget buildUseCase(BuildContext context, Widget child, bool setting) {
    // `maybeOf` so the addon can also be exercised outside a Widgetbook root.
    final state = WidgetbookState.maybeOf(context);
    if (state == null) return child;
    return WbCompareLayoutsPanes(
      state: state,
      enabled: setting,
      primary: state.useCase == null ? child : const _PrimaryUseCase(),
    );
  }
}

// Widgetbook 3.22 keys its workbench by the entire URL, including addon
// toggles. Preserve that lifecycle for real fixture changes, but not for
// presentation-only compare/design controls. Both panes use the same rule.
Uri _fixtureUri(WidgetbookState state) {
  final params = Map<String, String>.from(state.uri.queryParameters)
    ..remove('compare-layouts')
    ..remove('design-status');
  return state.uri.replace(queryParameters: params);
}

class _PrimaryUseCase extends StatelessWidget {
  const _PrimaryUseCase();

  @override
  Widget build(BuildContext context) {
    final state = WidgetbookState.of(context);
    return Stack(
      children: [
        // The public addon API cannot change the workbench's URI key. Reuse its
        // builder here to retain knob clear/lock and integration notifications
        // rather than duplicating that lifecycle. Guarded by real Widgetbook
        // toggle/knob tests in wb_addon_state_test.dart.
        // ignore: invalid_use_of_internal_member
        UseCaseBuilder(
          key: ValueKey(_fixtureUri(state)),
          builder: (context) =>
              WidgetbookState.of(context).useCase!.build(context),
        ),
      ],
    );
  }
}

/// Renders [primary] — the real use case, at whatever layout [state] selects —
/// next to a second copy of the same use case forced to the other layout.
///
/// The secondary copy is built under a nested [WidgetbookScope] whose
/// [WidgetbookState] is a derived copy of [state]: same root, path and query
/// params, with only the `Layout` knob flipped. That derived state is inert —
/// see [_derivedState] — so previewing never writes back to the real state or
/// the URL.
class WbCompareLayoutsPanes extends StatefulWidget {
  /// Creates the two-pane canvas around [primary].
  const WbCompareLayoutsPanes({
    required this.state,
    required this.primary,
    this.enabled = true,
    super.key,
  });

  /// The real Widgetbook state driving the primary pane.
  final WidgetbookState state;

  /// The use case as the outer addons handed it over.
  final Widget primary;

  final bool enabled;

  @override
  State<WbCompareLayoutsPanes> createState() => _WbCompareLayoutsPanesState();
}

class _WbCompareLayoutsPanesState extends State<WbCompareLayoutsPanes> {
  WidgetbookState? _derived;

  /// Keeps the primary use case one element across the one-pane/two-pane flip.
  ///
  /// Without it the flip changes the child widget *type* below this State, so
  /// Flutter unmounts the whole use case and mounts a fresh one — every mount
  /// driver re-runs, and a driver that pushes onto the widgetbook root
  /// navigator leaves its first sheet orphaned above the canvas. Same trick as
  /// [WbScaleDownBox].
  final GlobalKey _primaryKey = GlobalKey();

  /// Whether the last completed frame registered a `Layout` knob; null until
  /// the use case below has built once.
  bool? _sawLayoutKnob;

  /// Path [_sawLayoutKnob] was observed on, so navigating away forgets it.
  String? _lastPath;

  /// Knobs the derived pane resolved differently, as `'Label: value'`.
  List<String> _drift = const [];

  @override
  void dispose() {
    _derived?.dispose();
    super.dispose();
  }

  /// Addons build *above* the use case, so on the frame a use case first
  /// builds its knobs are not registered yet. Re-checking after the frame is
  /// how `UseCaseBuilder` locks its own knobs, and it makes the addon
  /// self-sufficient instead of waiting for someone else's rebuild.
  void _recheckAfterFrame(Duration _) {
    if (!mounted) return;
    final seen = widget.state.knobs.containsKey(kWbLayoutKnobLabel);
    final drift = _derivedDrift();
    if (seen == _sawLayoutKnob && listEquals(drift, _drift)) return;
    setState(() {
      _sawLayoutKnob = seen;
      _drift = drift;
    });
  }

  /// Knobs whose options are filtered per layout resolve to that layout's
  /// default in the pane that does not offer the selected option — the query
  /// group is shared, but each pane registered its own knob for it. Reporting
  /// them in the caption keeps that from reading as "same state, two layouts".
  List<String> _derivedDrift() {
    final derived = _derived;
    if (derived == null) return const [];
    // Both panes decode the same group for every knob but `Layout`, so one
    // group is enough; what differs is the knob each pane registered.
    final group = FieldCodec.decodeQueryGroup(
      widget.state.queryParams['knobs'],
    );
    final drift = <String>[];
    for (final entry in derived.knobs.entries) {
      if (entry.key == kWbLayoutKnobLabel) continue;
      final real = widget.state.knobs[entry.key];
      // A knob only one lane registers is a lane-specific axis, not a drift.
      if (real == null) continue;
      for (final field in entry.value.fields) {
        final param = group[field.name];
        // No entry, or this pane accepts the selected option: same value.
        if (param == null || field.codec.toValue(param) != null) continue;
        final realField = _fieldNamed(real, field.name);
        // Only the pane whose options were filtered fell back; a param neither
        // pane decodes is a stale URL, which both take the same default for.
        if (realField == null || realField.codec.toValue(param) == null) {
          continue;
        }
        final fallback =
            field.initialValueStringified ?? field.defaultValueStringified;
        drift.add('${field.name}: $fallback');
      }
    }
    return drift;
  }

  Field<dynamic>? _fieldNamed(Knob<dynamic> knob, String name) {
    for (final field in knob.fields) {
      if (field.name == name) return field;
    }
    return null;
  }

  /// The nested state, created once and re-pointed each build.
  ///
  /// Fields are assigned directly rather than through `updateQueryField`, so
  /// nothing here notifies; and it is built with no panels, which is what
  /// `WidgetbookState.notifyListeners` checks before syncing the router — so
  /// even a future notification cannot move the real URL.
  WidgetbookState _derivedState(
    Map<String, String> knobGroup,
    WbLayout layout,
  ) {
    final derived = _derived ??= WidgetbookState(
      root: widget.state.root,
      panels: const <LayoutPanel>{},
    );

    derived
      ..path = widget.state.path
      ..queryParams = {
        ...widget.state.queryParams,
        'knobs': FieldCodec.encodeQueryGroup({
          ...knobGroup,
          kWbLayoutKnobLabel: wbLayoutLabel(layout),
        }),
      };
    // Mirrors `UseCaseBuilder`: the registry is rebuilt by the pane below.
    derived.knobs.clear();
    return derived;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_recheckAfterFrame);

    final state = widget.state;
    if (state.path != _lastPath) {
      // `updatePath` mutates this same state and drops the knob group, so a
      // remembered `Layout` from the previous use case would otherwise render
      // a second copy of the new one for a frame.
      _lastPath = state.path;
      _sawLayoutKnob = null;
      _drift = const [];
    }

    // Always keyed, so the flip below reparents the use case instead of
    // remounting it.
    final primary = KeyedSubtree(key: _primaryKey, child: widget.primary);

    final knobGroup = FieldCodec.decodeQueryGroup(state.queryParams['knobs']);
    // The registry is authoritative once the use case has built; before that,
    // the URL is the only signal — `updatePath` drops the knob group on
    // navigation, so a `Layout` entry in it usually belongs to this use case.
    final hasLayoutKnob =
        _sawLayoutKnob ?? knobGroup.containsKey(kWbLayoutKnobLabel);
    final useCase = state.useCase;
    if (!widget.enabled || !hasLayoutKnob || useCase == null) return primary;

    final primaryLayout = wbCompareLayoutOf(knobGroup);
    final secondaryLayout = wbOtherLayout(primaryLayout);
    final derived = _derivedState(knobGroup, secondaryLayout);
    final secondary = WidgetbookScope(
      state: derived,
      // Like Workbench's URI-keyed primary, re-seed stateful fixtures when
      // knobs change. Caption-only rebuilds keep the same mounted subtree.
      child: Builder(
        key: ValueKey(_fixtureUri(derived)),
        builder: useCase.builder,
      ),
    );

    final primaryPane = _pane(context, primaryLayout, primary);
    final secondaryPane = _pane(context, secondaryLayout, secondary, _drift);

    return Row(
      key: kWbCompareLayoutsKey,
      // Stretch so each pane's caption row sits on a full-height column and
      // the divider has a height to paint.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Desktop is always the left pane, whichever one the real knob holds.
        Expanded(
          child: primaryLayout == WbLayout.desktop
              ? primaryPane
              : secondaryPane,
        ),
        SizedBox(
          width: 1,
          child: ColoredBox(color: context.colors.border.subtle),
        ),
        Expanded(
          child: primaryLayout == WbLayout.desktop
              ? secondaryPane
              : primaryPane,
        ),
      ],
    );
  }

  Widget _pane(
    BuildContext context,
    WbLayout layout,
    Widget child, [
    List<String> drift = const [],
  ]) {
    final caption = [
      wbLayoutLabel(layout),
      if (layout != wbCompiledLaneLayout) wbCompareTokenNote(),
      ...drift,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            caption,
            key: wbCompareLayoutsCaptionKey(layout),
            textAlign: TextAlign.center,
            style: AppTypography.labelSmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
        // `Align` reproduces the loosening `Stack` the workbench wraps the real
        // use case in — without it the secondary pane would lay its fixture out
        // under tight constraints and stretch a fixed-size preview frame to the
        // pane. It also re-centres both panes, which `AlignmentAddon` can no
        // longer do from outside the pair. Clipping keeps a fixture that does
        // not scale down (a raw component preview) inside its half.
        Expanded(
          child: ClipRect(
            child: Align(alignment: Alignment.center, child: child),
          ),
        ),
      ],
    );
  }
}
