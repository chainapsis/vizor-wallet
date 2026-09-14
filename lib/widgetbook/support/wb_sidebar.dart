import 'package:flutter/widgets.dart';
// ignore: depend_on_referenced_packages
import 'package:go_router/go_router.dart';
import '../../src/core/layout/app_main_sidebar.dart';

/// Pay and Sign out must not prepare swaps, lock storage or stop native sync.
final wbSidebarActions = appSidebarActionOverrideProvider.overrideWithValue(
  (context, path) async => context.go(path),
);

const wbSidebarPaths = [
  '/home',
  '/send',
  '/receive',
  '/swap',
  '/pay',
  '/voting',
  '/activity',
  '/accounts',
  '/add-account',
  '/settings',
  '/unlock',
];

Widget wbSidebarDestination(String path) =>
    Center(child: Text('Preview: $path'));
