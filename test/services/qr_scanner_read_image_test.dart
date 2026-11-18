import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

/// Answers every image analysis with [barcodes].
class _FakeScannerPlatform extends MobileScannerPlatform {
  _FakeScannerPlatform(this.barcodes);

  final List<Barcode> barcodes;

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async => BarcodeCapture(barcodes: barcodes);
}

void main() {
  late MobileScannerPlatform original;

  setUp(() => original = MobileScannerPlatform.instance);
  tearDown(() => MobileScannerPlatform.instance = original);

  test('a code with no text still counts, so two codes stay two', () async {
    MobileScannerPlatform.instance = _FakeScannerPlatform(const [
      Barcode(rawValue: 'zcash:t1abc?amount=1'),
      Barcode(),
    ]);

    expect(await QrScanner.readImage('/unused.png'), [
      'zcash:t1abc?amount=1',
      '',
    ]);
  });

  test('a lone code with no text is one code with empty text', () async {
    MobileScannerPlatform.instance = _FakeScannerPlatform(const [Barcode()]);

    expect(await QrScanner.readImage('/unused.png'), ['']);
  });
}
