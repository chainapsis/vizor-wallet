import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'external_action_guard_provider.dart';

/// Holds a signing surface's lease for its mounted lifetime.
///
/// Acquire after mount and release after disposal. Incoming payment requests
/// drain after all post-frame callbacks via `WidgetsBinding.endOfFrame`, so
/// a surface mounted in the same frame takes its hold before delivery.
mixin ExternalActionGuardHoldMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  late final ExternalActionGuardNotifier _externalActionGuard;
  ExternalActionLease? _externalActionLease;

  @override
  void initState() {
    super.initState();
    _externalActionGuard = ref.read(externalActionGuardProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _externalActionLease ??= _externalActionGuard.acquire();
    });
  }

  @override
  void dispose() {
    _externalActionLease?.releaseAfterNavigation();
    super.dispose();
  }
}

/// Use above a conditional or keyed signing subtree so remounts do not leave
/// a gap in protection between signing rounds.
class ExternalActionGuardHold extends ConsumerStatefulWidget {
  const ExternalActionGuardHold({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ExternalActionGuardHold> createState() =>
      _ExternalActionGuardHoldState();
}

class _ExternalActionGuardHoldState
    extends ConsumerState<ExternalActionGuardHold>
    with ExternalActionGuardHoldMixin {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Prevent pointer and keyboard activation of navigation during protected work.
/// Async navigation callbacks also need `tryBeginNavigation` at entry.
class ExternalActionNavigationGuard extends ConsumerWidget {
  const ExternalActionNavigationGuard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(
      externalActionGuardProvider.select(
        (state) => state.blocks(ExternalAction.navigation),
      ),
    );
    return ExcludeFocus(
      excluding: blocked,
      child: AbsorbPointer(absorbing: blocked, child: child),
    );
  }
}
