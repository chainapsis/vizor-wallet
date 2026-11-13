import 'dart:async';

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
class NativeTabBarCapture extends StatefulWidget {
  const NativeTabBarCapture({super.key});

  @override
  State<NativeTabBarCapture> createState() => _NativeTabBarCaptureState();
}

class _NativeTabBarCaptureState extends State<NativeTabBarCapture> {
  String _selectedId = '/home';
  int _selectionCount = 0;
  bool _hidden = false;
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
