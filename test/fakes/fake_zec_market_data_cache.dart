import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

class FakeZecMarketDataCache implements ZecMarketDataCache {
  FakeZecMarketDataCache({this.value});

  CachedZecMarketData? value;
  final writes = <CachedZecMarketData>[];

  @override
  Future<CachedZecMarketData?> read() async => value;

  @override
  Future<void> write(CachedZecMarketData next) async {
    value = next;
    writes.add(next);
  }
}
