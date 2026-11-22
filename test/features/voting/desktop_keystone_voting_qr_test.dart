@Tags(['desktop'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zxing2/qrcode.dart' as zxing;

// A complete synthetic 600-byte transport payload from the released UR encoder:
// three 200-byte source fragments and two redundant frames. No wallet data.
const _frames = [
  'UR:ZCASH-SIGN-BATCH/1-3/LPADAXCFAOHDCYCFCYDSUOHDSPAENNFNTNKSCHREGUWNMYDMSFIMAYOSFEVLLYCTRNHHZSMKENTLJKBYPEGLWPLEDESWIHAXOYFHUEKECYROHFYKMUEHTKJNBNPKFDVALPCNSEHEZCNSFTTPKOBZQDGYWSLGDWSGISAMOXFXVYLBCARFHTYAMTEETEJSBSPMGRWDLODSSSIAADNEFSUYKNCSRPGHWFMEDLSNJEBKPDFGVELFCLRSHLZONYETTBJYBGPAGWWELUDRSPIYAAOEFPURKICWRHHDYNMWEYTTJLBTPYGAVSLNDKSAHNZMNTFRTAKSCMQZGMWTMYDPSBINAYOLFYVOLACTRYHPYTMSENTYJPBEPEGTWMLDDISWIEAONBFHUTKGCFRLHFWKMODYTOJNBDPTFLVALRCPRTHYZCJPBZTAHK',
  'UR:ZCASH-SIGN-BATCH/2-3/LPAOAXCFAOHDCYCFCYDSUOHDSPNDESTSKPBBPRGDWYLGDNSOIOAHOXFWVTKBCARKHKYLMDEETDJOBAPSGRWLLTDASSIDAENNFNUYKKCHREGHWZMHDMSFJEASOSFEVLLFCXRNHHZONLEMTLJKBGPFGLWPLEDTSTIHAXOEFZUEKECYRHHGYKMUEYTIJTBNPKGAVDLPCNSEHNZENSFTTAKTBZQDGYWTMNDWSGINATONFXVYLACKRFHTYAMSECTEJSBEPLGSWDLODISKIAADNEFMUOKNCSRLGOWFMEDLTOJZBKPDFLVWLSCLRSHYZTNYETTBKPBWPAGWWYLKDRSPIYAHOTFPURKBCERDHDYNMDEOTTJLBTPSGEVSLNDASRHSZMNTFNTNKSCMQZGUWNMYDPSFIMAYOLFYVLLYCTRYHHZSMKHENLGYDL',
  'UR:ZCASH-SIGN-BATCH/3-3/LPAXAXCFAOHDCYCFCYDSUOHDSPENTYJKBYPEGTWMLEDESWIEAXOYFHUTKGCYROHFWKMUEHTKJNBDPKFDVALRCPSEHEZCNDFTTPKOBBPRGYWSLGDNSOISAMOXFWVYLBCARKHKYAMTEETDJSBSPMGRWLLODSSSIDAENEFSUYKKCSRPGHWZMHDLSNJEASPDFGVELFCXRSHLZONLEMTBJYBGPFGWWELUDTSTIYAAOEFZURKICWRHHGYNMWEYTIJTBTPYGAVDLNDKSAHNZENTFRTAKTBZQZGMWTMNDPSBINATONFYVOLACKRYHPYTMSECTYJPBEPLGSWMLDDISKIEAONBFMUOKGCFRLGOWKMODYTOJZBDPTFLVWLSCPRTHYZTNDESTSKPBWPRGDWYLKDRSOIOAHOTFWVTKBCERDHKYLMDEOYASPVOND',
  'UR:ZCASH-SIGN-BATCH/4-3/LPAAAXCFAOHDCYCFCYDSUOHDSPNDESTSKPBBPRGDWYLGDNSOIOAHOXFWVTKBCARKHKYLMDEETDJOBAPSGRWLLTDASSIDAENNFNUYKKCHREGHWZMHDMSFJEASOSFEVLLFCXRNHHZONLEMTLJKBGPFGLWPLEDTSTIHAXOEFZUEKECYRHHGYKMUEYTIJTBNPKGAVDLPCNSEHNZENSFTTAKTBZQDGYWTMNDWSGINATONFXVYLACKRFHTYAMSECTEJSBEPLGSWDLODISKIAADNEFMUOKNCSRLGOWFMEDLTOJZBKPDFLVWLSCLRSHYZTNYETTBKPBWPAGWWYLKDRSPIYAHOTFPURKBCERDHDYNMDEOTTJLBTPSGEVSLNDASRHSZMNTFNTNKSCMQZGUWNMYDPSFIMAYOLFYVLLYCTRYHHZSMKPLISGRGH',
  'UR:ZCASH-SIGN-BATCH/5-3/LPAHAXCFAOHDCYCFCYDSUOHDSPNDESTSKPBBPRGDWYLGDNSOIOAHOXFWVTKBCARKHKYLMDEETDJOBAPSGRWLLTDASSIDAENNFNUYKKCHREGHWZMHDMSFJEASOSFEVLLFCXRNHHZONLEMTLJKBGPFGLWPLEDTSTIHAXOEFZUEKECYRHHGYKMUEYTIJTBNPKGAVDLPCNSEHNZENSFTTAKTBZQDGYWTMNDWSGINATONFXVYLACKRFHTYAMSECTEJSBEPLGSWDLODISKIAADNEFMUOKNCSRLGOWFMEDLTOJZBKPDFLVWLSCLRSHYZTNYETTBKPBWPAGWWYLKDRSPIYAHOTFPURKBCERDHDYNMDEOTTJLBTPSGEVSLNDASRHSZMNTFNTNKSCMQZGUWNMYDPSFIMAYOLFYVLLYCTRYHHZSMKUTHGPAHE',
];

void main() {
  for (final ratio in [1.0, 1.25, 2.0]) {
    testWidgets(
      'desktop voting renders scannable whole-pixel frames at ${ratio}x',
      (tester) async {
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = const Size(1080, 800) * ratio;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: appLocalizationsDelegates,
              home: AppTheme(
                data: AppThemeData.light,
                child: Scaffold(
                  body: RepaintBoundary(
                    key: key,
                    child: const VotingStatusContent(
                      phase: VotingSessionPhase.keystoneSigning,
                      isHardwareAccount: true,
                      keystoneSigningBundleIndex: 0,
                      keystoneUrParts: _frames,
                      keystoneBatchMessageCount: 1,
                      keystoneBatchTotalCount: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final rect = tester
            .getRect(find.byType(KeystonePcztQrStage))
            .shift(-boundary.localToGlobal(Offset.zero));
        final unreadable = <int>[];
        final offGrid = <int>[];
        for (var i = 0; i < _frames.length; i++) {
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
            if (zxing.QRCodeReader().decode(bitmap).text != _frames[i]) {
              unreadable.add(i);
            }
          } on zxing.ReaderException {
            unreadable.add(i);
          }
          final count = QrCode.fromData(
            data: _frames[i],
            errorCorrectLevel: QrErrorCorrectLevel.M,
          ).moduleCount;
          if (!_hasSharpFinder(source, count)) offGrid.add(i);
          await tester.pump(keystoneQrFrameInterval);
        }
        await tester.pumpWidget(const SizedBox());
        expect(
          {'unreadable frames': unreadable, 'off-grid frames': offGrid},
          {'unreadable frames': isEmpty, 'off-grid frames': isEmpty},
        );
      },
    );
  }
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
