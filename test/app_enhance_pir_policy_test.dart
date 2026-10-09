import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';

AppBootstrapState _ready({required bool? enabled, String network = 'main'}) =>
    AppBootstrapState(
      initialLocation: '/home',
      initialAccountState: const AccountState(),
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: network,
      rpcEndpointConfig: defaultRpcEndpointConfig(network),
      themeMode: ThemeMode.system,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
      enhancePirEnabled: enabled,
    );

final _raised = ApiAppliedTransparentPolicy(
  mode: ApiTransparentLedgerMode.privateRequired,
  generation: BigInt.from(3),
  changed: true,
);
final _lowered = ApiAppliedTransparentPolicy(
  mode: ApiTransparentLedgerMode.public,
  generation: BigInt.from(4),
  changed: true,
);

void main() {
  late List<String> applied;
  late bool failRaise;
  late bool failLower;
  late _OptOutStore optOut;

  Future<void> apply(AppBootstrapState bootstrap) => applyEnhancePirPolicy(
    bootstrap,
    setRustEnabled: (enabled) => applied.add('rust:$enabled'),
    setPreferenceConfirmed: (confirmed) => applied.add('confirmed:$confirmed'),
    reconcileTransparentPolicy: (privateQueries) async {
      applied.add('reconcile:$privateQueries');
      if (privateQueries ? failRaise : failLower) {
        throw StateError('public lookups did not drain');
      }
      return privateQueries ? _raised : _lowered;
    },
    optOutStore: optOut,
    setNativePrivateRecovery: (enabled) async => applied.add('native:$enabled'),
    prepareCompanions: () async => applied.add('companions'),
  );

  setUp(() {
    applied = [];
    failRaise = false;
    failLower = false;
    optOut = _OptOutStore((step) => applied.add(step));
    TransparentPolicyStartup.current = const TransparentPolicyStartup();
  });
  tearDown(
    () => TransparentPolicyStartup.current = const TransparentPolicyStartup(),
  );

  // Masquerade builds never enable the production service.
  final available = isEnhancePirAvailableForNetwork('main');

  for (final kind in AppBootstrapFailureKind.values) {
    test(
      'a blocked bootstrap ($kind) leaves native private mode alone',
      () async {
        // The blocked state carries a default `false`, not the saved preference.
        final blocked = AppBootstrapState.blocked(
          failureKind: kind,
          failureMessage: 'blocked',
        );
        expect(blocked.enhancePirEnabled, isFalse);

        await apply(blocked);

        expect(applied, isEmpty, reason: 'nothing confirmed or reconciled');
      },
    );
  }

  test(
    'a saved preference is confirmed and raised before native is applied',
    () async {
      await apply(_ready(enabled: true));
      expect(applied, [
        'rust:$available',
        'confirmed:true',
        if (available) 'reconcile:true',
        'native:$available',
        'companions',
      ]);
      // The providers adopt what startup applied.
      expect(
        TransparentPolicyStartup.current.appliedPolicy,
        available ? _raised : isNull,
      );
    },
  );

  // Startup never rolled the setting back; with the toggle no longer rolling
  // it back either, a failed raise keeps private queries on everywhere and
  // records nothing applied. The next sync retries the raise.
  test('a failed raise keeps private queries on and applies nothing', () async {
    failRaise = true;
    await apply(_ready(enabled: true));
    expect(applied, [
      'rust:$available',
      'confirmed:true',
      if (available) 'reconcile:true',
      'native:$available',
      'companions',
    ]);
    expect(TransparentPolicyStartup.current.appliedPolicy, isNull);
    expect(TransparentPolicyStartup.current.optOutPending, isFalse);
  });

  group('an unfinished opt-out', () {
    test('is finished at startup and its marker cleared', () async {
      optOut.value = true;
      await apply(_ready(enabled: false));
      // The opt-out finishes before the runtime takes the public setting.
      expect(applied, [
        'reconcile:false',
        'optout:false',
        'rust:false',
        'confirmed:true',
        'native:false',
        'companions',
      ]);
      expect(TransparentPolicyStartup.current.appliedPolicy, _lowered);
      expect(TransparentPolicyStartup.current.optOutPending, isFalse);
    });

    test('that fails again stays pending and private', () async {
      optOut.value = true;
      failLower = true;
      await apply(_ready(enabled: false));
      expect(applied, [
        'reconcile:false',
        'rust:false',
        'confirmed:true',
        'native:false',
        'companions',
      ]);
      expect(optOut.value, isTrue);
      expect(TransparentPolicyStartup.current.appliedPolicy, isNull);
      expect(TransparentPolicyStartup.current.optOutPending, isTrue);
    });

    test('is finished on a network without the service', () async {
      optOut.value = true;
      await apply(_ready(enabled: false, network: 'test'));
      expect(applied, contains('reconcile:false'));
      expect(TransparentPolicyStartup.current.optOutPending, isFalse);
    });

    test('with an unreadable marker never lowers', () async {
      optOut.unreadable = true;
      await apply(_ready(enabled: false));
      expect(applied, [
        'rust:false',
        'confirmed:true',
        'native:false',
        'companions',
      ]);
    });

    test('with an unreadable preference never lowers', () async {
      optOut.value = true;
      await apply(_ready(enabled: null));
      expect(applied, isNot(contains('reconcile:false')));
      expect(optOut.value, isTrue);
    });

    test('is superseded while private queries are on', () async {
      optOut.value = true;
      await apply(_ready(enabled: true));
      expect(applied, isNot(contains('reconcile:false')));
    });
  });

  test(
    'an unreadable preference keeps both sides private, unconfirmed',
    () async {
      // What bootstrap builds when the saved preference cannot be read.
      final unreadable = await readEnhancePirEnabledPreference(
        _UnusedSecureStore(),
        preferences: _UnreadablePreferences(),
      );
      expect(unreadable, isNull);
      await apply(_ready(enabled: unreadable));
      expect(applied, [
        'rust:$available',
        'confirmed:false',
        'native:$available',
        'companions',
      ]);
      expect(applied, isNot(contains('native:false')));
    },
  );

  test('startup applies a disabled preference but never demotes', () async {
    await apply(_ready(enabled: false));
    // Only an explicit toggle-off lowers the transparent policy.
    expect(applied, [
      'rust:false',
      'confirmed:true',
      'native:false',
      'companions',
    ]);
  });

  test('a network without the service reconciles nothing', () async {
    await apply(_ready(enabled: true, network: 'test'));
    expect(applied, [
      'rust:false',
      'confirmed:true',
      'native:false',
      'companions',
    ]);
  });

  test('startup sweeps orphan companions and marks the current ones', () async {
    final steps = <String>[];
    await prepareTransparentRecoveryCompanions(
      resolveDbPath: () async => '/support/zcash_wallet.db',
      sweep: (current) async {
        steps.add('sweep:$current');
        throw StateError('a directory could not be deleted');
      },
      excludeFromBackup: (dbPath) async => steps.add('exclude:$dbPath'),
    );
    // A failed sweep does not stop the backup mark, or startup.
    expect(steps, [
      'sweep:/support/zcash_wallet.db',
      'exclude:/support/zcash_wallet.db',
    ]);

    steps.clear();
    await prepareTransparentRecoveryCompanions(
      resolveDbPath: () async => throw StateError('storage unavailable'),
      sweep: (current) async => steps.add('sweep:$current'),
      excludeFromBackup: (dbPath) async => steps.add('exclude:$dbPath'),
    );
    expect(steps, isEmpty, reason: 'no wallet path, nothing to touch');
  });
}

class _UnreadablePreferences implements EnhancePirPreferenceStore {
  @override
  Future<bool?> readEnabled() async => throw StateError('read failed');

  @override
  Future<void> writeEnabled(bool enabled) async =>
      fail('an unknown preference must not be written');
}

/// Never reached: the failed preference read returns before the legacy lane.
class _UnusedSecureStore extends AppSecureStore {
  _UnusedSecureStore() : super.testing(storage: const FlutterSecureStorage());

  @override
  Future<String?> readPlain(String key) async =>
      fail('legacy flag read after a failed preference read');
}

class _OptOutStore implements TransparentOptOutStore {
  _OptOutStore(this.record);

  final void Function(String step) record;
  bool value = false;
  bool unreadable = false;

  @override
  Future<bool> readPending() async {
    if (unreadable) throw StateError('read failed');
    return value;
  }

  @override
  Future<void> writePending(bool pending) async {
    record('optout:$pending');
    value = pending;
  }
}
