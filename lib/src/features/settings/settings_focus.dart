import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A Settings row another screen can open Settings at.
enum SettingsFocus { privateQueries }

/// The row Settings should show next, until a [SettingsFocusTarget] for it
/// scrolls there. The Settings screens take no route arguments (mobile keeps
/// its tab alive), so the request travels here instead.
final settingsFocusRequestProvider =
    NotifierProvider<SettingsFocusRequest, SettingsFocus?>(
      SettingsFocusRequest.new,
    );

class SettingsFocusRequest extends Notifier<SettingsFocus?> {
  @override
  SettingsFocus? build() => null;

  void request(SettingsFocus focus) => state = focus;

  void clear() => state = null;
}

/// Opens Settings scrolled to [focus].
void openSettingsAt(BuildContext context, WidgetRef ref, SettingsFocus focus) {
  ref.read(settingsFocusRequestProvider.notifier).request(focus);
  context.go('/settings');
}

/// Marks the Settings row for [focus], and scrolls it into view when another
/// screen asks for it: at once if Settings is already open, or as Settings
/// first lays out.
class SettingsFocusTarget extends ConsumerStatefulWidget {
  const SettingsFocusTarget({
    required this.focus,
    required this.child,
    super.key,
  });

  final SettingsFocus focus;
  final Widget child;

  /// Where the row lands: a little below the top, clear of the header.
  static const alignment = 0.2;
  static const duration = Duration(milliseconds: 400);

  /// The app's curve for movement on screen.
  static const curve = Cubic(0.77, 0, 0.175, 1);

  @override
  ConsumerState<SettingsFocusTarget> createState() =>
      _SettingsFocusTargetState();
}

class _SettingsFocusTargetState extends ConsumerState<SettingsFocusTarget> {
  @override
  void initState() {
    super.initState();
    if (ref.read(settingsFocusRequestProvider) == widget.focus) _reveal();
  }

  void _reveal() {
    // After the frame that brings Settings on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(settingsFocusRequestProvider.notifier).clear();
      Scrollable.ensureVisible(
        context,
        alignment: SettingsFocusTarget.alignment,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : SettingsFocusTarget.duration,
        curve: SettingsFocusTarget.curve,
      );
    });
    // A request alone changes nothing on screen, so ask for that frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsFocusRequestProvider, (_, next) {
      if (next == widget.focus) _reveal();
    });
    return widget.child;
  }
}
