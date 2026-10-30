import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_list_diff.dart';

void main() {
  test('retained IDs form a longest common subsequence across reorderings', () {
    final random = Random(12);
    for (var run = 0; run < 300; run++) {
      final before = List.generate(16, (i) => i)..shuffle(random);
      final after = List.generate(16, (i) => i + 4)..shuffle(random);
      final retained = retainedPaymentLinkEntryIds(before, after);
      final oldOrder = before.where(retained.contains).toList();
      final newOrder = after.where(retained.contains).toList();
      expect(oldOrder, newOrder);
      final lengths = List.generate(17, (_) => List<int>.filled(17, 0));
      for (var a = 15; a >= 0; a--) {
        for (var b = 15; b >= 0; b--) {
          lengths[a][b] = before[a] == after[b]
              ? lengths[a + 1][b + 1] + 1
              : max(lengths[a + 1][b], lengths[a][b + 1]);
        }
      }
      expect(retained.length, lengths[0][0]);
    }
  });

  test('large unchanged and reversed lists need no quadratic matrix', () {
    final ids = List.generate(10000, (i) => i);
    expect(retainedPaymentLinkEntryIds(ids, ids).length, ids.length);
    expect(retainedPaymentLinkEntryIds(ids, ids.reversed.toList()).length, 1);
    expect(retainedPaymentLinkEntryIds<int>([], ids), isEmpty);
    expect(retainedPaymentLinkEntryIds<int>(ids, []), isEmpty);
  });
}
