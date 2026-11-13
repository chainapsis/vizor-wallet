import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../src/core/l10n/l10n.dart';
import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/layout/mobile/ios_native_tab_bar.dart';
import '../src/core/navigation/mobile_destinations.dart';

/// Deterministic content behind the real native bar, without wallet services.
///
/// Run on iOS to inspect the material: a widget-test image cannot include UIKit
/// pixels. Changing tabs changes the backdrop, while scrolling moves text and
/// color boundaries through the glass. A static screenshot alone does not prove
/// that UIKit samples Flutter's backing surface.
class NativeTabBarCapture extends StatelessWidget {
  const NativeTabBarCapture({super.key});

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) => CupertinoPageRoute<void>(
      builder: (_) => const _NativeTabBarCapturePage(),
    ),
  );
}

class _NativeTabBarCapturePage extends StatefulWidget {
  const _NativeTabBarCapturePage();

  @override
  State<_NativeTabBarCapturePage> createState() => _NativeTabBarCaptureState();
}

class _NativeTabBarCaptureState extends State<_NativeTabBarCapturePage> {
  String _selectedId = '/home';
  int _selectionCount = 0;
  bool _hidden = false;
  int _barGeneration = 0;
  Timer? _reverseTimer;

  @override
  void dispose() {
    _reverseTimer?.cancel();
    super.dispose();
  }

  void _toggleVisibility() {
    _reverseTimer?.cancel();
    setState(() => _hidden = !_hidden);
  }

  void _reverseVisibility() {
    _reverseTimer?.cancel();
    setState(() => _hidden = true);
    _reverseTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _hidden = false);
    });
  }

  void _openModal() {
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Native tab modal'),
          content: const Text('The tabs stay behind this modal without input.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close modal'),
            ),
          ],
        ),
      ),
    );
  }

  void _pushPage({bool translucent = false}) {
    Widget page(BuildContext context) {
      final content = Center(
        child: Material(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translucent ? 'Close translucent page' : 'Close page'),
          ),
        ),
      );
      return translucent
          ? ColoredBox(color: const Color(0x88333333), child: content)
          : Scaffold(body: content);
    }

    unawaited(
      Navigator.of(context).push<void>(
        translucent
            ? PageRouteBuilder<void>(
                opaque: false,
                pageBuilder: (context, _, _) => page(context),
              )
            : CupertinoPageRoute<void>(builder: page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final destination in mobileDestinations)
        IosNativeTabBarItem(
          id: destination.path,
          iconName: destination.iconName,
          label: mobileDestinationLabel(context.l10n, destination.path),
        ),
    ];
    final selectedIndex = items.indexWhere((item) => item.id == _selectedId);
    void select(String id) {
      setState(() {
        _selectedId = id;
        _selectionCount += 1;
      });
    }

    return AppMobileShell(
      key: ValueKey(_barGeneration),
      nativeTabBar: IosNativeTabBarConfiguration(
        items: items,
        selectedId: _selectedId,
        onSelect: select,
        hidden: _hidden,
      ),
      tabBar: AppMobileTabBar(
        items: [
          for (final item in items)
            AppMobileTabItem(iconName: item.iconName, label: item.label),
        ],
        currentIndex: selectedIndex,
        onSelect: (index) => select(items[index].id),
      ),
      body: Stack(
        children: [
          ListView.builder(
            key: const PageStorageKey('native-tab-backdrop'),
            padding: EdgeInsets.zero,
            itemCount: 60,
            itemBuilder: (context, index) {
              const palette = [
                Color(0xFFFFD740),
                Color(0xFF2979FF),
                Color(0xFFFF4081),
                Color(0xFF00C853),
              ];
              final color = palette[(index + selectedIndex) % palette.length];
              return ColoredBox(
                color: color,
                child: SizedBox(
                  height: 96,
                  child: Center(
                    child: Text(
                      '${items[selectedIndex].label} · $_selectionCount · $index',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _toggleVisibility,
                      child: Text(_hidden ? 'Show tabs' : 'Hide tabs'),
                    ),
                    TextButton(
                      onPressed: _reverseVisibility,
                      child: const Text('Reverse after 80 ms'),
                    ),
                    TextButton(
                      onPressed: _openModal,
                      child: const Text('Open modal'),
                    ),
                    TextButton(
                      onPressed: _pushPage,
                      child: const Text('Push page'),
                    ),
                    TextButton(
                      onPressed: () => _pushPage(translucent: true),
                      child: const Text('Push translucent page'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _barGeneration++),
                      child: const Text('Recreate tabs'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildNativeTabBarCapture(BuildContext context) =>
    const NativeTabBarCapture();
