import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_status_auto_refresh.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

final _enabled = NotifierProvider<_Enabled, bool>(_Enabled.new);

class _Enabled extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool enabled) => state = enabled;
}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1test',
  );
}

class _Refresher implements SwapActivityStatusRefresher {
  final accounts = <String>[];

  @override
  Future<void> refreshOpenActivities({
    required String accountUuid,
    bool force = false,
  }) async {
    accounts.add(accountUuid);
  }
}

void main() {
  testWidgets('polling follows availability changes and stops on disposal', (
    tester,
  ) async {
    final refresher = _Refresher();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_Accounts.new),
          swapFeatureEnabledProvider.overrideWith((ref) => ref.watch(_enabled)),
          swapActivityStatusRefresherProvider.overrideWithValue(refresher),
        ],
        child: const SwapActivityStatusAutoRefresh(child: SizedBox()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SwapActivityStatusAutoRefresh)),
    );
    expect(refresher.accounts, isEmpty);

    container.read(_enabled.notifier).set(true);
    await tester.pump();
    expect(refresher.accounts, ['account-1']);
    await tester.pump(swapActivityStatusRefreshInterval);
    expect(refresher.accounts, ['account-1', 'account-1']);

    container.read(_enabled.notifier).set(false);
    await tester.pump();
    await tester.pump(swapActivityStatusRefreshInterval * 2);
    expect(refresher.accounts, hasLength(2));

    container.read(_enabled.notifier).set(true);
    await tester.pump();
    expect(refresher.accounts, hasLength(3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(swapActivityStatusRefreshInterval * 2);
    expect(refresher.accounts, hasLength(3));
  });
}
