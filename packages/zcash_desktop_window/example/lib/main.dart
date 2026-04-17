import 'package:flutter/material.dart';
import 'package:zcash_desktop_window/zcash_desktop_window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZcashDesktopWindow.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: const Center(
          child: ZcashTitlebarSafeArea(
            child: Text('zcash_desktop_window example'),
          ),
        ),
      ),
    );
  }
}
