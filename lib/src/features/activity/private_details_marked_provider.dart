import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/enhance_pir_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;

/// Whether Activity rows and receipts mark entries whose details are not
/// final. They do while Private queries is on, and while turning it off has
/// not finished: privately recovered entries can still be provisional then,
/// and without the marks their amounts would read as final.
final privateDetailsMarkedProvider = Provider<bool>(
  (ref) =>
      ref.watch(enhancePirProvider) ||
      ref.watch(syncProvider.select((sync) => sync.value?.transparentStop)) ==
          rust_sync.TransparentStopReason.optOutUnfinished,
);
