import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/sync.dart' as rust_sync;

/// Starts the process-lifetime Orchard proving-key warm-up used by sends.
///
/// Overridable so tests and design fixtures do not require an initialized
/// Rust bridge.
final sendProvingKeyWarmupProvider = Provider<void Function()>((ref) {
  return rust_sync.warmOrchardProvingKeyCache;
});
