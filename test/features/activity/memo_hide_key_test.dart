import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/models/memo_hide_key.dart';

void main() {
  test('builds key from memo fields', () {
    expect(memoHideKey(txidHex: 'ab12', outputPool: 2, outputIndex: 0), 'ab12:2:0');
  });
  test('builds key from detail output key', () {
    expect(memoHideKeyFromDetail(txidHex: 'ab12', memoOutputKey: '2:0'), 'ab12:2:0');
  });
}
