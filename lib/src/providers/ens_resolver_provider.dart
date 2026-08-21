import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/naming/ens_name_resolver.dart';
import '../core/naming/ens_rpc_transport.dart';

final ensResolverProvider = Provider<EnsNameResolver>((ref) {
  return EnsNameResolver(HttpEnsRpcTransport());
});
