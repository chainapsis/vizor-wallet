import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zxing2/qrcode.dart' as zxing;

// A complete synthetic 600-byte transport payload from the released UR encoder:
// three 200-byte source fragments and two redundant frames. No wallet data.
const votingQrFrames = [
  'UR:ZCASH-SIGN-BATCH/1-3/LPADAXCFAOHDCYCFCYDSUOHDSPAENNFNTNKSCHREGUWNMYDMSFIMAYOSFEVLLYCTRNHHZSMKENTLJKBYPEGLWPLEDESWIHAXOYFHUEKECYROHFYKMUEHTKJNBNPKFDVALPCNSEHEZCNSFTTPKOBZQDGYWSLGDWSGISAMOXFXVYLBCARFHTYAMTEETEJSBSPMGRWDLODSSSIAADNEFSUYKNCSRPGHWFMEDLSNJEBKPDFGVELFCLRSHLZONYETTBJYBGPAGWWELUDRSPIYAAOEFPURKICWRHHDYNMWEYTTJLBTPYGAVSLNDKSAHNZMNTFRTAKSCMQZGMWTMYDPSBINAYOLFYVOLACTRYHPYTMSENTYJPBEPEGTWMLDDISWIEAONBFHUTKGCFRLHFWKMODYTOJNBDPTFLVALRCPRTHYZCJPBZTAHK',
  'UR:ZCASH-SIGN-BATCH/2-3/LPAOAXCFAOHDCYCFCYDSUOHDSPNDESTSKPBBPRGDWYLGDNSOIOAHOXFWVTKBCARKHKYLMDEETDJOBAPSGRWLLTDASSIDAENNFNUYKKCHREGHWZMHDMSFJEASOSFEVLLFCXRNHHZONLEMTLJKBGPFGLWPLEDTSTIHAXOEFZUEKECYRHHGYKMUEYTIJTBNPKGAVDLPCNSEHNZENSFTTAKTBZQDGYWTMNDWSGINATONFXVYLACKRFHTYAMSECTEJSBEPLGSWDLODISKIAADNEFMUOKNCSRLGOWFMEDLTOJZBKPDFLVWLSCLRSHYZTNYETTBKPBWPAGWWYLKDRSPIYAHOTFPURKBCERDHDYNMDEOTTJLBTPSGEVSLNDASRHSZMNTFNTNKSCMQZGUWNMYDPSFIMAYOLFYVLLYCTRYHHZSMKHENLGYDL',
  'UR:ZCASH-SIGN-BATCH/3-3/LPAXAXCFAOHDCYCFCYDSUOHDSPENTYJKBYPEGTWMLEDESWIEAXOYFHUTKGCYROHFWKMUEHTKJNBDPKFDVALRCPSEHEZCNDFTTPKOBBPRGYWSLGDNSOISAMOXFWVYLBCARKHKYAMTEETDJSBSPMGRWLLODSSSIDAENEFSUYKKCSRPGHWZMHDLSNJEASPDFGVELFCXRSHLZONLEMTBJYBGPFGWWELUDTSTIYAAOEFZURKICWRHHGYNMWEYTIJTBTPYGAVDLNDKSAHNZENTFRTAKTBZQZGMWTMNDPSBINATONFYVOLACKRYHPYTMSECTYJPBEPLGSWMLDDISKIEAONBFMUOKGCFRLGOWKMODYTOJZBDPTFLVWLSCPRTHYZTNDESTSKPBWPRGDWYLKDRSOIOAHOTFWVTKBCERDHKYLMDEOYASPVOND',
  'UR:ZCASH-SIGN-BATCH/4-3/LPAAAXCFAOHDCYCFCYDSUOHDSPNDESTSKPBBPRGDWYLGDNSOIOAHOXFWVTKBCARKHKYLMDEETDJOBAPSGRWLLTDASSIDAENNFNUYKKCHREGHWZMHDMSFJEASOSFEVLLFCXRNHHZONLEMTLJKBGPFGLWPLEDTSTIHAXOEFZUEKECYRHHGYKMUEYTIJTBNPKGAVDLPCNSEHNZENSFTTAKTBZQDGYWTMNDWSGINATONFXVYLACKRFHTYAMSECTEJSBEPLGSWDLODISKIAADNEFMUOKNCSRLGOWFMEDLTOJZBKPDFLVWLSCLRSHYZTNYETTBKPBWPAGWWYLKDRSPIYAHOTFPURKBCERDHDYNMDEOTTJLBTPSGEVSLNDASRHSZMNTFNTNKSCMQZGUWNMYDPSFIMAYOLFYVLLYCTRYHHZSMKPLISGRGH',
  'UR:ZCASH-SIGN-BATCH/5-3/LPAHAXCFAOHDCYCFCYDSUOHDSPNDESTSKPBBPRGDWYLGDNSOIOAHOXFWVTKBCARKHKYLMDEETDJOBAPSGRWLLTDASSIDAENNFNUYKKCHREGHWZMHDMSFJEASOSFEVLLFCXRNHHZONLEMTLJKBGPFGLWPLEDTSTIHAXOEFZUEKECYRHHGYKMUEYTIJTBNPKGAVDLPCNSEHNZENSFTTAKTBZQDGYWTMNDWSGINATONFXVYLACKRFHTYAMSECTEJSBEPLGSWDLODISKIAADNEFMUOKNCSRLGOWFMEDLTOJZBKPDFLVWLSCLRSHYZTNYETTBKPBWPAGWWYLKDRSPIYAHOTFPURKBCERDHDYNMDEOTTJLBTPSGEVSLNDASRHSZMNTFNTNKSCMQZGUWNMYDPSFIMAYOLFYVLLYCTRYHHZSMKUTHGPAHE',
];

Future<void> checkVotingQrFrames(
  WidgetTester tester,
  GlobalKey key,
  double ratio, {
  required bool wholePixels,
}) async {
  final qr = find.byType(KeystonePcztQrStage);
  final viewport =
      RenderAbstractViewport.of(tester.renderObject(qr)) as RenderBox;
  final scrollBounds = viewport.localToGlobal(Offset.zero) & viewport.size;
  final initialRect = tester.getRect(qr);
  final initiallyVisible = scrollBounds.intersect(initialRect) == initialRect;
  await tester.ensureVisible(qr);
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final visibleRect = tester.getRect(qr);
  expect(scrollBounds.intersect(visibleRect), visibleRect);
  final rect = visibleRect.shift(-boundary.localToGlobal(Offset.zero));
  expect((Offset.zero & boundary.size).contains(rect.topLeft), isTrue);
  expect(rect.right, lessThanOrEqualTo(boundary.size.width));
  expect(rect.bottom, lessThanOrEqualTo(boundary.size.height));
  final unreadable = <int>[];
  final offGrid = <int>[];
  for (var i = 0; i < votingQrFrames.length; i++) {
    final source = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return zxing.RGBLuminanceSource(
          image.width,
          image.height,
          bytes.buffer.asInt32List(),
        ).crop(
          (rect.left * ratio).round(),
          (rect.top * ratio).round(),
          (rect.width * ratio).round(),
          (rect.height * ratio).round(),
        );
      } finally {
        image.dispose();
      }
    }))!;
    final bitmap = zxing.BinaryBitmap(zxing.HybridBinarizer(source));
    try {
      if (zxing.QRCodeReader().decode(bitmap).text != votingQrFrames[i]) {
        unreadable.add(i);
      }
    } on zxing.ReaderException {
      unreadable.add(i);
    }
    if (wholePixels) {
      final count = QrCode.fromData(
        data: votingQrFrames[i],
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ).moduleCount;
      if (!_hasSharpFinder(source, count)) offGrid.add(i);
    }
    await tester.pump(keystoneQrFrameInterval);
  }
  debugPrint(
    'QR ${rect.size} at ${ratio}x, fully visible before scroll: $initiallyVisible, unreadable: $unreadable, off grid: $offGrid',
  );
  expect(unreadable, isEmpty);
  expect(offGrid, isEmpty);
}

// The top edge of the finder pattern is seven solid black modules, surrounded
// by a white margin. Check actual pixels independently of the decoder.
bool _hasSharpFinder(zxing.LuminanceSource source, int count) {
  final pitch = source.width ~/ (count + 8);
  final margin = (source.width - pitch * count) ~/ 2;
  final row = source.getRow(margin, null).buffer.asUint8List();
  return pitch >= 3 &&
      row.take(margin).every((p) => p == 255) &&
      row.skip(margin).take(7 * pitch).every((p) => p == 0) &&
      row[margin + 7 * pitch] == 255;
}
