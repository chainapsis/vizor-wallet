import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/widgets/transaction_receipt_view.dart';

void main() {
  test(
    'compactTransactionReceiptSavedAddress keeps sixteen characters at each edge',
    () {
      const address =
          'u1z76wfe98p8ue25zwrrdg7v4hv28grpcxtqwuwd1c12ttmcw0hcsr6ju6cdtnjxjc744qhmyyt5qxze6683576ujdvamp6tkh9076ee3ny5jqqtgnq6u8gh0h95y04yx97rz2hxrzz44ypk1yegx6mllga4hn7m4q3eatnj3jxdvggvdg2';

      final compact = compactTransactionReceiptSavedAddress(address);

      expect(
        compact,
        '${address.substring(0, 16)} ... ${address.substring(address.length - 16)}',
      );
      expect(compact, isNot(address));
    },
  );

  test(
    'compactTransactionReceiptSavedAddress keeps short addresses unchanged',
    () {
      const address = 'u1shortaddress';

      expect(compactTransactionReceiptSavedAddress(address), address);
    },
  );
}
