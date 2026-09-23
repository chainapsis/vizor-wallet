// Dev-only native verification. Uses the real iOS Runner and modal widgets,
// without starting the wallet, Rust runtime, storage, or sync.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'src/core/layout/app_form_factor.dart';
import 'src/core/layout/mobile/app_mobile_sheet.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/legacy_material_theme.dart';
import 'src/core/widgets/app_button.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assert(kAppFormFactor == AppFormFactor.mobile);
  runApp(const _Preview());
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool dark = true;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildLegacyLightTheme(),
    darkTheme: buildLegacyDarkTheme(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (_, child) => AppTheme(
      data: dark ? AppThemeData.dark : AppThemeData.light,
      child: child!,
    ),
    home: _Cases(onLight: () => setState(() => dark = false)),
  );
}

class _Cases extends StatefulWidget {
  const _Cases({required this.onLight});
  final VoidCallback onLight;
  @override
  State<_Cases> createState() => _CasesState();
}

class _CasesState extends State<_Cases> {
  final cardKey = GlobalKey();
  final focus = FocusNode();
  final records = <Map<String, Object?>>[];
  final output = Directory('${Directory.systemTemp.path}/vizor-modal-corners');
  String status = 'Preparing modal verification';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> capture(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final surfaces = <Map<String, Object?>>[];
    void inspect(Element element) {
      final widget = element.widget;
      if (widget is Material && widget.shape is RoundedSuperellipseBorder) {
        final radius = (widget.shape! as RoundedSuperellipseBorder).borderRadius
            .resolve(TextDirection.ltr);
        final box = element.renderObject! as RenderBox;
        final offset = box.localToGlobal(Offset.zero);
        surfaces.add({
          'tl': radius.topLeft.x,
          'bl': radius.bottomLeft.x,
          'br': radius.bottomRight.x,
          'frame': [offset.dx, offset.dy, box.size.width, box.size.height],
        });
        return;
      }
      element.visitChildren(inspect);
    }

    final element = cardKey.currentContext as Element?;
    element?.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Material && widget.shape is RoundedSuperellipseBorder) {
        inspect(ancestor);
        return false;
      }
      return true;
    });
    if (!mounted) return;
    final view = View.of(context);
    final record = <String, Object?>{
      'id': id,
      'surfaces': surfaces,
      'keyboard': view.viewInsets.bottom / view.devicePixelRatio,
    };
    records.add(record);
    await File('${output.path}/ready.json').writeAsString(jsonEncode(record));
    for (var i = 0; i < 600; i++) {
      final ack = File('${output.path}/ack.txt');
      if (await ack.exists() && await ack.readAsString() == id) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Capture timed out: $id');
  }

  Widget body(BuildContext context, {bool tall = false}) => SizedBox(
    key: cardKey,
    child: MobileModalScaffold(
      title: tall ? 'Choose an account' : 'Add memo',
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tall)
            SizedBox(
              height: 380,
              child: ListView.builder(
                itemCount: 20,
                itemBuilder: (_, i) =>
                    ListTile(title: Text('Preview account ${i + 1}')),
              ),
            ),
          if (!tall)
            TextField(
              focusNode: focus,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Enter a memo'),
            ),
          const SizedBox(height: 24),
          AppButton(
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );

  Future<void> run() async {
    try {
      await output.create(recursive: true);
      for (final name in ['ready.json', 'ack.txt', 'results.json']) {
        final file = File('${output.path}/$name');
        if (await file.exists()) await file.delete();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final sheet = showAppMobileSheet<void>(context: context, builder: body);
      await capture('dark-sheet');
      focus.requestFocus();
      await capture('keyboard');
      focus.unfocus();
      await capture('keyboard-closed');
      if (!mounted) return;
      Navigator.of(context).pop();
      await sheet;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final dialog = showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: MobileModalCard(
            followsScreenCorners: false,
            margin: EdgeInsets.zero,
            child: body(context),
          ),
        ),
      );
      await capture('centered-dialog');
      if (!mounted) return;
      Navigator.of(context).pop();
      await dialog;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      widget.onLight();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final tall = showAppMobileSheet<void>(
        context: context,
        builder: (context) => body(context, tall: true),
      );
      await capture('light-tall-sheet');
      if (!mounted) return;
      Navigator.of(context).pop();
      await tall;
      await File(
        '${output.path}/results.json',
      ).writeAsString(jsonEncode(records));
      if (mounted) setState(() => status = 'Verification complete');
    } catch (error, stack) {
      await File('${output.path}/results.json').writeAsString(
        jsonEncode({'error': '$error', 'stack': '$stack', 'records': records}),
      );
      if (mounted) setState(() => status = '$error');
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(status)));

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }
}
