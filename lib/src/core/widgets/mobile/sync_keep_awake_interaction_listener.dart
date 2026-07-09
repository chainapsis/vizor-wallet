import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../layout/app_form_factor.dart';
import '../../../providers/sync_keep_awake_provider.dart';

class SyncKeepAwakeInteractionListener extends ConsumerWidget {
  const SyncKeepAwakeInteractionListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kAppFormFactor != AppFormFactor.mobile) return child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markInteraction(ref),
      onPointerMove: (_) => _markInteraction(ref),
      onPointerSignal: (_) => _markInteraction(ref),
      child: child,
    );
  }

  void _markInteraction(WidgetRef ref) {
    ref.read(syncKeepAwakeInteractionProvider.notifier).markInteraction();
  }
}
