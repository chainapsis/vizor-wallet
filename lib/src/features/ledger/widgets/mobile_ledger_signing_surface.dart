import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import 'mobile/mobile_ledger_help_navigation.dart';

/// A mobile Ledger modal over its caller. The operation owner stays mounted
/// across discovery, verification and signing; changing content never pops a
/// route or cancels the operation. Route-backed callers must be non-opaque.
class MobileLedgerSigningSurface extends StatefulWidget {
  const MobileLedgerSigningSurface({
    required this.child,
    required this.onBack,
    required this.canLeave,
    this.onPrevious,
    this.title = 'Ledger',
    super.key,
  });
  final Widget child;
  final VoidCallback onBack;

  /// Returns to the previous step; dismissal still uses [onBack].
  final VoidCallback? onPrevious;
  final bool canLeave;
  final String title;

  @override
  State<MobileLedgerSigningSurface> createState() =>
      _MobileLedgerSigningSurfaceState();
}

class _MobileLedgerSigningSurfaceState
    extends State<MobileLedgerSigningSurface> {
  bool _closing = false;
  double _dragDistance = 0;
  final _helpNavigation = MobileLedgerHelpNavigation();

  @override
  void didUpdateWidget(covariant MobileLedgerSigningSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The owner can keep this surface mounted after cleanup fails. Its latest
    // canLeave value permits another attempt, even when the busy and failure
    // updates were coalesced into a single frame.
    if (widget.canLeave) _closing = false;
  }

  void _dismiss() {
    if (!widget.canLeave || _closing) return;
    _closing = true;
    widget.onBack();
  }

  void _previous() {
    if (!widget.canLeave || _closing) return;
    if (_helpNavigation.previous()) return;
    _closing = true;
    (widget.onPrevious ?? widget.onBack)();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _previous();
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          color: context.colors.background.neutralScrim,
          dismissible: widget.canLeave,
          onDismiss: _dismiss,
          semanticsLabel: 'Close Ledger',
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onVerticalDragStart: (_) => _dragDistance = 0,
              onVerticalDragUpdate: (details) =>
                  _dragDistance += details.delta.dy,
              onVerticalDragEnd: (details) {
                if (_dragDistance > 80 ||
                    (details.primaryVelocity ?? 0) > 700) {
                  _dismiss();
                }
              },
              child: MobileModalCard(
                onBack: widget.onPrevious == null ? null : _previous,
                backEnabled: widget.canLeave && !_closing,
                child: MobileLedgerHelpScope(
                  navigation: _helpNavigation,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
