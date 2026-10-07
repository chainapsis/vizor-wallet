import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';

/// Changes the Private queries presentation setting without invoking Rust.
class FakeEnhancePirNotifier extends EnhancePirNotifier {
  FakeEnhancePirNotifier(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;

  @override
  Future<void> set(bool enabled) async => state = enabled;
}
