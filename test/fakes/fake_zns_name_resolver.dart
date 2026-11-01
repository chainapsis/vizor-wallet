import 'package:zcash_wallet/src/core/naming/zns_name_resolver.dart';

/// Answers ZNS lookups from a fixed name-to-address table, and records every
/// name it was asked about. A [failure] makes every lookup throw it.
class FakeZnsNameResolver implements ZnsNameResolver {
  FakeZnsNameResolver([this.addresses = const {}, this.failure]);

  final Map<String, String> addresses;
  final Object? failure;
  final lookups = <String>[];

  @override
  Future<ZnsResolution?> resolve(String name) async {
    lookups.add(name);
    if (failure case final error?) throw error;
    final address = addresses[name];
    return address == null ? null : ZnsResolution(name: name, address: address);
  }
}
