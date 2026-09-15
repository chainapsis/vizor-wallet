import 'package:flutter/widgets.dart';
// ignore: depend_on_referenced_packages
import 'package:go_router/go_router.dart';
import '../../src/core/layout/app_main_sidebar.dart';
import '../../src/features/migration/providers/ironwood_migration_announcement_provider.dart';

/// Derive activation UI from the fixture's CTA, never the host chain or store.
final wbPostMigrationState = ironwoodPostMigrationStateProvider.overrideWith((
  ref,
) async {
  final cta = ref.watch(ironwoodHomeMigrationPresentationProvider);
  return switch (cta.mode) {
    IronwoodHomeMigrationCtaMode.hidden =>
      const IronwoodPostMigrationState.inactive(),
    IronwoodHomeMigrationCtaMode.start => IronwoodPostMigrationState.required(
      network: cta.network!,
      accountUuid: cta.accountUuid!,
      status: cta.status,
    ),
    IronwoodHomeMigrationCtaMode.resume =>
      IronwoodPostMigrationState.inProgress(
        network: cta.network!,
        accountUuid: cta.accountUuid!,
        status: cta.status!,
      ),
  };
});

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
