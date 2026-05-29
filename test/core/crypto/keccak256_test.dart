import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/crypto/keccak256.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('keccak256', () {
    test('hashes the empty input', () {
      expect(
        _hex(keccak256(const [])),
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
      );
    });

    test('hashes "abc"', () {
      expect(
        _hex(keccak256(utf8.encode('abc'))),
        '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45',
      );
    });

    test('hashes a multi-word message', () {
      expect(
        _hex(keccak256(utf8.encode('The quick brown fox jumps over the '
            'lazy dog'))),
        '4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15',
      );
    });
  });
}
